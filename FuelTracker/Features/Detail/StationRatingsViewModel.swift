import Foundation
import Observation

/// The ratings calls `StationRatingsViewModel` makes: `FuelRepository` in the app, a fake in tests.
@MainActor
protocol StationRatingsRepository: AnyObject {
    var isLoggedIn: Bool { get }
    func getStationRatings(stationId: Int, page: Int) async throws -> PublicRatingsResponse
    func getMyRating(stationId: Int) async throws -> MyRatingStateDTO
    func createRating(stationId: Int, input: RatingInput) async throws -> RatingSaveResponse
    func updateRating(id: Int, input: RatingInput) async throws -> RatingSaveResponse
    func reportRating(id: Int, reason: String) async throws
    func blockRatingAuthor(ratingId: Int) async throws -> String
    func getBlockedReviewers() async throws -> [String]
    func unblockReviewer(authorRef: String) async throws
    func requestEmailVerification() async throws -> VerifyEmailResponse
    func acceptTerms(version: String) async throws
}

/// Dates and pence amounts as the ratings UI shows them: UK format, Europe/London time.
enum RatingFormat {
    private static let londonTimeZone = TimeZone(identifier: "Europe/London") ?? .current

    /// Parses the backend's ISO-8601 timestamps, with or without fractional seconds.
    static func parseDate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)
    }

    /// "1 Oct 2026"; falls back to the raw date part if the timestamp doesn't parse.
    static func ukDate(_ iso: String) -> String {
        guard let date = parseDate(iso) else { return String(iso.prefix(10)) }
        return string(from: date, format: "d MMM yyyy")
    }

    /// "14:05" in UK time, or `nil` if the timestamp doesn't parse.
    static func ukTime(_ iso: String) -> String? {
        parseDate(iso).map { string(from: $0, format: "HH:mm") }
    }

    private static func string(from date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = londonTimeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// "4" / "3.5": whole numbers without a decimal, anything else to one place.
    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// "3.1p more than listed" / "2p less than listed".
    static func gapPhrase(_ gapPence: Double) -> String {
        if gapPence == 0 { return "the listed price" }
        let pence = "\(number(abs(gapPence)))p"
        return gapPence > 0 ? "\(pence) more than listed" : "\(pence) less than listed"
    }

    /// "+3.1p" / "−2p": the sign says whether drivers paid more or less than listed.
    static func signedPence(_ gapPence: Double) -> String {
        "\(gapPence > 0 ? "+" : "\u{2212}")\(number(abs(gapPence)))p"
    }
}

/// User-facing ratings copy, matching the website's wording.
enum RatingCopy {
    static let termsURL = URL(string: "https://fueltracker.uk/terms#reviews")!

    static let reportReasons = [
        "Offensive or abusive",
        "Contains personal information",
        "Spam or advertising",
        "Not about this station",
        "Something else",
    ]

    static func blockerMessage(_ raw: String, dailyCapResetsAt: String?) -> String {
        guard let blocker = RatingBlocker(rawValue: raw) else { return "You can't leave a rating right now." }
        switch blocker {
        case .suspended:
            return "Your account can no longer leave ratings."
        case .emailUnverified:
            return "Verify your email address to leave a rating."
        case .accountTooNew:
            return "Accounts need to be 3 days old before they can leave a rating."
        case .terms:
            return "Please accept the reviews content policy first."
        case .dailyCap:
            let resets = dailyCapResetsAt.flatMap(RatingFormat.ukTime).map { " You can rate again from \($0)." } ?? ""
            return "You've reached today's limit of 5 ratings." + resets
        }
    }

    /// Prefers the API's own `detail` wording; a 401 that survived the token refresh means the
    /// session has ended (the client has already signed the user out by then).
    static func errorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            let detail: String?
            switch apiError {
            case .http(_, let message), .rejected(_, let message, _, _): detail = message
            case .decoding, .invalidURL: detail = nil
            }
            if apiError.statusCode == 401 { return "Your session has expired. Sign in again to continue." }
            if apiError.statusCode == 429 { return detail ?? "Too many attempts. Try again in a little while." }
            if let detail { return detail }
        }
        return "Something went wrong. Please try again."
    }

    static func savedMessage(_ rating: OwnRatingDTO) -> String {
        switch rating.commentStatus {
        case "approved", "none":
            return "Thanks — your rating is live."
        case "rejected":
            let reason = rating.moderationReason.map { ": \($0)." } ?? "."
            return "Your rating counts, but your comment wasn't published\(reason) You can edit it within 24 hours."
        default:
            return "Thanks — your rating counts now. Your comment will appear once it's been checked."
        }
    }

    /// Tells the user where their own rating and comment stand, since the comment may not be
    /// public yet.
    static func ownStatus(_ state: MyRatingStateDTO?, now: Date) -> String? {
        guard let own = state?.rating else { return nil }
        var text = "You rated this station on \(RatingFormat.ukDate(own.createdAt))."
        switch own.commentStatus {
        case "pending", "held":
            text += " Your rating counts now; your comment will appear once it's been checked."
        case "rejected":
            text += own.moderationReason.map { " Your comment wasn't published: \($0)." } ?? " Your comment wasn't published."
        case "hidden":
            text += " Your comment is hidden while it's reviewed."
        default:
            break
        }
        if let canRateAt = state?.canRateAt, !own.isEditable(now: now) {
            text += " You can rate it again from \(RatingFormat.ukDate(canRateAt))."
        }
        return text
    }

    static func matchLabel(_ rating: PublicRatingDTO) -> String {
        if rating.priceMatched { return "Price matched" }
        if let gap = rating.gapPence, gap != 0 { return "Charged \(RatingFormat.gapPhrase(gap))" }
        return "Price didn't match"
    }
}

/// What the rate sheet shows, resolved from `GET /api/ratings/mine` in the backend's order:
/// a pending cooldown, then email verification, then any other blocker except the content policy
/// (accepted inline as part of submitting), then the form.
enum RatingSheetMode: Equatable {
    case loading
    /// The session ended while the sheet was open.
    case signedOut
    case unavailable
    case cooldown(ratedOn: String?, canRateAt: String)
    case verifyEmail
    case blocked(message: String)
    case noFuels
    case form(existing: OwnRatingDTO?, needsTerms: Bool)
    case saved(OwnRatingDTO)

    static func resolve(state: MyRatingStateDTO?, isLoading: Bool, fuelTypes: [String], now: Date) -> RatingSheetMode {
        guard let state else { return isLoading ? .loading : .unavailable }
        let own = state.rating
        let editing = own?.isEditable(now: now) ?? false
        if !editing {
            if let canRateAt = state.canRateAt {
                return .cooldown(ratedOn: own?.createdAt, canRateAt: canRateAt)
            }
            if state.blockers.contains(RatingBlocker.emailUnverified.rawValue) {
                return .verifyEmail
            }
            if let blocker = state.blockers.first(where: { $0 != RatingBlocker.terms.rawValue }) {
                return .blocked(message: RatingCopy.blockerMessage(blocker, dailyCapResetsAt: state.dailyCapResetsAt))
            }
        }
        if fuelTypes.isEmpty { return .noFuels }
        return .form(existing: editing ? own : nil, needsTerms: !editing && state.blockers.contains(RatingBlocker.terms.rawValue))
    }
}

/// Driver reports for one station on the Detail screen: the public comments, the signed-in user's
/// own rating state, the reviewers they've hidden, and the rate sheet's form. Everything here is
/// driver-reported, never Fuel Finder data. Each fetch is best-effort and independent, so a
/// failure only leaves its own part empty.
@Observable
@MainActor
final class StationRatingsViewModel {
    static let commentMaxLength = 280
    static let paidRange = 50.0...400.0

    let stationId: Int

    private(set) var ratings: [PublicRatingDTO] = []
    private(set) var total = 0
    private(set) var isLoadingMore = false
    private var page = 1
    private var hasLoadedRatings = false

    private(set) var myRating: MyRatingStateDTO?
    private(set) var isLoadingMine = false
    private(set) var blockedAuthorRefs: Set<String> = []

    /// Comments with a report/hide call in flight, so a double tap can't send it twice.
    private(set) var pendingCommentActions: Set<Int> = []
    private(set) var commentMessages: [Int: String] = [:]

    private(set) var fuelTypes: [String] = []
    private(set) var formFuelType = ""
    private(set) var formPriceMatched: Bool?
    private(set) var formPaidText = ""
    private(set) var formStars: Int?
    private(set) var formComment = ""
    var termsAccepted = false
    /// Guards `submit()` re-entrancy, the same way `DetailViewModel.pendingFavouriteToggle` does.
    private(set) var isSubmitting = false
    private(set) var submitError: String?
    private(set) var savedRating: OwnRatingDTO?
    private(set) var verifyEmailStatus: VerifyEmailStatus = .idle

    enum VerifyEmailStatus: Equatable {
        case idle
        case sending
        case sent
        case alreadyVerified
        case failed(String)
    }

    private let repository: StationRatingsRepository
    private let analytics: AppAnalytics
    private let now: () -> Date
    private var defaultFuelType = FuelType.default.rawValue
    /// Set when the sheet opens before `/ratings/mine` has loaded, so the form is prefilled from
    /// the user's editable rating once it arrives.
    private var needsPrefill = false

    init(stationId: Int, repository: StationRatingsRepository, analytics: AppAnalytics, now: @escaping () -> Date = { Date() }) {
        self.stationId = stationId
        self.repository = repository
        self.analytics = analytics
        self.now = now
    }

    // MARK: - Derived state

    var isLoggedIn: Bool { repository.isLoggedIn }
    var ownRating: OwnRatingDTO? { myRating?.rating }
    var ownRatingIsEditable: Bool { ownRating?.isEditable(now: now()) ?? false }
    var rateButtonTitle: String { ownRatingIsEditable ? "Edit your rating" : "Rate this station" }
    var ownStatusText: String? { RatingCopy.ownStatus(myRating, now: now()) }

    var visibleRatings: [PublicRatingDTO] { ratings.filter { !blockedAuthorRefs.contains($0.authorRef) } }
    var hiddenRatingCount: Int { ratings.count - visibleRatings.count }
    var canLoadMore: Bool { ratings.count < total }

    var sheetMode: RatingSheetMode {
        if let savedRating { return .saved(savedRating) }
        if !repository.isLoggedIn { return .signedOut }
        return RatingSheetMode.resolve(state: myRating, isLoading: isLoadingMine, fuelTypes: fuelTypes, now: now())
    }

    /// `nil` for an empty field (the paid price is optional); accepts a comma as the decimal mark.
    var paidValue: Double? {
        let trimmed = formPaidText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    var paidIsValid: Bool {
        if formPaidText.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        guard let paidValue else { return false }
        return Self.paidRange.contains(paidValue)
    }

    var canSubmit: Bool {
        guard case .form(_, let needsTerms) = sheetMode, !isSubmitting,
              let matched = formPriceMatched, formStars != nil,
              fuelTypes.contains(formFuelType) else { return false }
        if !matched && !paidIsValid { return false }
        return !needsTerms || termsAccepted
    }

    /// The fuels a rating can be about: only those this station lists a price for, known types in
    /// the app's usual order and any unknown ones after them.
    static func ratableFuelTypes(for station: StationDTO) -> [String] {
        var seen = Set<String>()
        let listed = station.prices.map(\.fuelType).filter { seen.insert($0).inserted }
        let order = FuelType.allCases.map(\.rawValue)
        return listed.sorted { (order.firstIndex(of: $0) ?? order.count) < (order.firstIndex(of: $1) ?? order.count) }
    }

    // MARK: - Loading

    /// First page of comments plus the user's own state; called when the section first appears.
    func loadInitial() async {
        if !hasLoadedRatings {
            do {
                let response = try await repository.getStationRatings(stationId: stationId, page: 1)
                ratings = response.items
                total = response.total
                page = 1
                hasLoadedRatings = true
            } catch {
                // Ratings switched off server-side (404) or a transient failure: no comments shown.
            }
        }
        await authChanged()
    }

    func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = try await repository.getStationRatings(stationId: stationId, page: page + 1)
            let known = Set(ratings.map(\.id))
            ratings += next.items.filter { !known.contains($0.id) }
            total = next.total
            page += 1
        } catch {
            // Leaves what's shown in place; the button stays for another try.
        }
    }

    /// Re-reads everything tied to who's signed in — after signing in, or once the session ends.
    func authChanged() async {
        guard repository.isLoggedIn else {
            myRating = nil
            blockedAuthorRefs = []
            return
        }
        await refreshMine()
        do {
            blockedAuthorRefs = Set(try await repository.getBlockedReviewers())
        } catch {
            // Keeps whatever was known; comments just stay unfiltered until the next load.
        }
    }

    /// Also called when the app returns to the foreground, since email verification happens on
    /// the website and the app is never told about it directly.
    func refreshMine() async {
        guard repository.isLoggedIn else {
            myRating = nil
            isLoadingMine = false
            return
        }
        isLoadingMine = true
        do {
            myRating = try await repository.getMyRating(stationId: stationId)
        } catch {
            // Ratings switched off (404) or the session ended (401): no rating action is offered.
            // Any other failure keeps the last known state, so a blip on returning to the app
            // doesn't wipe an open form.
            if let status = (error as? APIError)?.statusCode, status == 404 || status == 401 {
                myRating = nil
            }
        }
        isLoadingMine = false
        if needsPrefill {
            needsPrefill = false
            prefillForm()
        }
    }

    // MARK: - Rate sheet

    func openRateSheet(fuelTypes: [String], defaultFuelType: String) {
        self.fuelTypes = fuelTypes
        self.defaultFuelType = defaultFuelType
        savedRating = nil
        submitError = nil
        termsAccepted = false
        verifyEmailStatus = .idle
        prefillForm()
        analytics.trackEvent("open_rating_form", params: ["station_id": stationId])
        if myRating == nil && repository.isLoggedIn {
            needsPrefill = true
            if !isLoadingMine {
                isLoadingMine = true
                Task { await refreshMine() }
            }
        }
    }

    /// Edit mode starts from the user's own rating; a new rating starts blank, on their fuel.
    private func prefillForm() {
        let existing = ownRatingIsEditable ? ownRating : nil
        if let existing, fuelTypes.contains(existing.fuelType) {
            formFuelType = existing.fuelType
        } else if fuelTypes.contains(defaultFuelType) {
            formFuelType = defaultFuelType
        } else {
            formFuelType = fuelTypes.first ?? defaultFuelType
        }
        formPriceMatched = existing?.priceMatched
        formPaidText = existing?.reportedPricePence.map(RatingFormat.number) ?? ""
        formStars = existing?.stars
        formComment = existing?.comment ?? ""
    }

    func setFuelType(_ value: String) { formFuelType = value }
    func setPriceMatched(_ value: Bool) { formPriceMatched = value }
    func setPaidText(_ value: String) { formPaidText = value }
    func setStars(_ value: Int) { formStars = min(max(value, 1), 5) }
    /// Capped in UTF-16 code units, which is how the backend measures the 280-character limit.
    func setComment(_ value: String) {
        var capped = value
        while capped.utf16.count > Self.commentMaxLength { capped.removeLast() }
        formComment = capped
    }

    func submit() async {
        guard canSubmit, case .form(let existing, let needsTerms) = sheetMode,
              let matched = formPriceMatched, let stars = formStars else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        submitError = nil

        let comment = formComment.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = RatingInput(
            fuelType: formFuelType,
            priceMatched: matched,
            reportedPricePence: matched ? nil : paidValue,
            stars: stars,
            comment: comment.isEmpty ? nil : comment
        )
        do {
            if needsTerms, let version = myRating?.termsVersion {
                try await repository.acceptTerms(version: version)
            }
            let saved: OwnRatingDTO
            if let existing {
                saved = try await repository.updateRating(id: existing.id, input: input).rating
            } else {
                saved = try await repository.createRating(stationId: stationId, input: input).rating
            }
            analytics.trackEvent(existing == nil ? "submit_rating" : "edit_rating", params: [
                "station_id": stationId,
                "price_matched": matched,
                "stars": stars,
                "has_comment": input.comment != nil,
            ])
            savedRating = saved
            await refreshMine()
        } catch {
            // A retried submit that already landed comes back as a cooldown carrying the stored
            // rating — that's the user's rating saved, not a failure.
            if existing == nil, let stored = Self.cooldownRating(from: error) {
                savedRating = stored
                await refreshMine()
            } else {
                submitError = RatingCopy.errorMessage(error)
                // A blocker, cooldown or closed edit window means the form no longer applies;
                // re-reading the state moves the sheet to the matching message.
                if let apiError = error as? APIError, case .rejected = apiError {
                    await refreshMine()
                }
            }
        }
    }

    static func cooldownRating(from error: Error) -> OwnRatingDTO? {
        guard let apiError = error as? APIError,
              case .rejected(let status, _, let reason, let body) = apiError,
              status == 409, reason == "cooldown" else { return nil }
        return (try? JSONDecoder().decode(RatingCooldownBody.self, from: body))?.rating
    }

    func sendVerificationEmail() async {
        guard verifyEmailStatus != .sending else { return }
        verifyEmailStatus = .sending
        do {
            let response = try await repository.requestEmailVerification()
            verifyEmailStatus = response.alreadyVerified ? .alreadyVerified : .sent
            if response.alreadyVerified { await refreshMine() }
        } catch {
            verifyEmailStatus = .failed(RatingCopy.errorMessage(error))
        }
    }

    // MARK: - Comment actions

    func report(_ rating: PublicRatingDTO, reason: String) async {
        guard !pendingCommentActions.contains(rating.id) else { return }
        pendingCommentActions.insert(rating.id)
        defer { pendingCommentActions.remove(rating.id) }
        do {
            try await repository.reportRating(id: rating.id, reason: reason)
            commentMessages[rating.id] = "Thanks. We'll review this comment."
            analytics.trackEvent("report_rating", params: ["rating_id": rating.id])
        } catch {
            commentMessages[rating.id] = RatingCopy.errorMessage(error)
        }
    }

    func hideReviewer(_ rating: PublicRatingDTO) async {
        guard !pendingCommentActions.contains(rating.id) else { return }
        pendingCommentActions.insert(rating.id)
        defer { pendingCommentActions.remove(rating.id) }
        do {
            let authorRef = try await repository.blockRatingAuthor(ratingId: rating.id)
            blockedAuthorRefs.insert(authorRef)
        } catch {
            commentMessages[rating.id] = RatingCopy.errorMessage(error)
        }
    }

    /// Un-hides every reviewer whose comments are currently hidden on the loaded pages.
    func showHiddenReviewers() async {
        let refs = Set(ratings.map(\.authorRef)).intersection(blockedAuthorRefs)
        for ref in refs {
            do {
                try await repository.unblockReviewer(authorRef: ref)
                blockedAuthorRefs.remove(ref)
            } catch {
                // Stays hidden; the link remains for another try.
            }
        }
    }
}
