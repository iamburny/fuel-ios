import Testing
import Foundation
@testable import FuelTracker

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

/// A fixed "now" well inside the edit windows used by the fixtures below.
private let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!

private func ownRatingJSON(
    id: Int = 9,
    commentStatus: String = "approved",
    editsRemaining: Int = 3,
    editableUntil: String = "2026-10-02T09:00:00.000Z",
    moderationReason: String? = nil
) -> String {
    let reason = moderationReason.map { "\"\($0)\"" } ?? "null"
    return """
    {"id": \(id), "station_id": 431, "stars": 2, "price_matched": false, "fuel_type": "E10",
     "reported_price_pence": 152.9, "published_price_pence": 149.9, "gap_pence": 3,
     "comment": "Pump was 3p more", "comment_status": "\(commentStatus)", "moderation_reason": \(reason),
     "edits_remaining": \(editsRemaining), "editable_until": "\(editableUntil)",
     "created_at": "2026-10-01T09:00:00.000Z", "edited_at": null}
    """
}

private func mineJSON(rating: String = "null", canRateAt: String? = nil, blockers: [String] = []) -> String {
    let can = canRateAt.map { "\"\($0)\"" } ?? "null"
    let list = blockers.map { "\"\($0)\"" }.joined(separator: ",")
    return """
    {"rating": \(rating), "can_rate_at": \(can), "blockers": [\(list)], "daily_cap_resets_at": null, "terms_version": "1"}
    """
}

private func publicRating(id: Int, authorRef: String) throws -> PublicRatingDTO {
    try decode(PublicRatingDTO.self, """
    {"id": \(id), "stars": 4, "price_matched": true, "fuel_type": "E10", "gap_pence": null,
     "comment": "Fine", "created_at": "2026-09-30T10:00:00.000Z", "edited": false, "author_ref": "\(authorRef)"}
    """)
}

/// Scripted stand-in for `FuelRepository`'s ratings calls; records what the view model sent.
@MainActor
private final class FakeRatingsRepository: StationRatingsRepository {
    var isLoggedIn = true
    var mine: MyRatingStateDTO?
    var ratingsPages: [Int: PublicRatingsResponse] = [:]
    var blocked: [String] = []
    var createResult: Result<RatingSaveResponse, Error>?
    var updateResult: Result<RatingSaveResponse, Error>?

    private(set) var calls: [String] = []
    private(set) var lastInput: RatingInput?
    private(set) var acceptedTermsVersion: String?

    func getStationRatings(stationId: Int, page: Int) async throws -> PublicRatingsResponse {
        calls.append("ratings:\(page)")
        guard let response = ratingsPages[page] else { throw APIError.http(status: 404, message: "Not found") }
        return response
    }

    func getMyRating(stationId: Int) async throws -> MyRatingStateDTO {
        calls.append("mine")
        guard let mine else { throw APIError.http(status: 404, message: "Not found") }
        return mine
    }

    func createRating(stationId: Int, input: RatingInput) async throws -> RatingSaveResponse {
        calls.append("create")
        lastInput = input
        return try createResult!.get()
    }

    func updateRating(id: Int, input: RatingInput) async throws -> RatingSaveResponse {
        calls.append("update:\(id)")
        lastInput = input
        return try updateResult!.get()
    }

    func reportRating(id: Int, reason: String) async throws { calls.append("report:\(id)") }

    func blockRatingAuthor(ratingId: Int) async throws -> String {
        calls.append("block:\(ratingId)")
        return "ref-\(ratingId)"
    }

    func getBlockedReviewers() async throws -> [String] { blocked }

    func unblockReviewer(authorRef: String) async throws { calls.append("unblock:\(authorRef)") }

    func requestEmailVerification() async throws -> VerifyEmailResponse {
        calls.append("verify")
        return try decode(VerifyEmailResponse.self, #"{"ok": true}"#)
    }

    func acceptTerms(version: String) async throws {
        calls.append("terms")
        acceptedTermsVersion = version
    }
}

struct RatingDTODecodingTests {
    @Test func stationFromOlderBackendHasNoRatingFields() throws {
        let station = try decode(StationDTO.self, """
        {"id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0, "prices": []}
        """)
        #expect(station.ratingSummary == nil)
        #expect(station.priceAccuracyWarning == false)
    }

    @Test func stationDecodesRatingSummaryAndWarning() throws {
        let station = try decode(StationDTO.self, """
        {"id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0, "prices": [],
         "rating_summary": {"rater_count": 7, "avg_stars": 2.4, "price_match_pct": 43, "avg_gap_pence": 3.1},
         "price_accuracy_warning": true}
        """)
        #expect(station.ratingSummary == RatingSummaryDTO(raterCount: 7, avgStars: 2.4, priceCheckCount: 0, priceMatchPct: 43, avgGapPence: 3.1))
        #expect(station.priceAccuracyWarning == true)
    }

    @Test func malformedRatingSummaryDoesNotLoseTheStation() throws {
        let station = try decode(StationDTO.self, """
        {"id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0, "prices": [],
         "rating_summary": {"rater_count": "lots"}, "price_accuracy_warning": null}
        """)
        #expect(station.name == "Test")
        #expect(station.ratingSummary == nil)
        #expect(station.priceAccuracyWarning == false)
    }

    @Test func decodesNullGapInSummary() throws {
        let summary = try decode(RatingSummaryDTO.self, #"{"rater_count": 3, "avg_stars": 4, "price_match_pct": 100, "avg_gap_pence": null}"#)
        #expect(summary.avgGapPence == nil)
    }

    @Test func decodesPublicRatingsPage() throws {
        let page = try decode(PublicRatingsResponse.self, """
        {"items": [{"id": 3, "stars": 2, "price_matched": false, "fuel_type": "B7_STANDARD", "gap_pence": 3.5,
          "comment": "Dear", "created_at": "2026-09-30T10:00:00.000Z", "edited": true, "author_ref": "abc"}],
         "total": 21, "page": 1, "page_size": 20}
        """)
        #expect(page.items.count == 1)
        #expect(page.items[0].gapPence == 3.5)
        #expect(page.items[0].edited == true)
        #expect(page.total == 21)
        #expect(page.pageSize == 20)
        #expect(RatingCopy.matchLabel(page.items[0]) == "Charged 3.5p more than listed")
    }

    @Test func decodesMyRatingState() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(rating: ownRatingJSON(commentStatus: "held"), blockers: ["terms"]))
        #expect(state.rating?.commentStatus == "held")
        #expect(state.rating?.reportedPricePence == 152.9)
        #expect(state.blockers == ["terms"])
        #expect(state.termsVersion == "1")
    }

    @Test func ownRatingWithMissingFieldsStillDecodes() throws {
        let rating = try decode(OwnRatingDTO.self, #"{"id": 1, "stars": 5}"#)
        #expect(rating.commentStatus == "none")
        #expect(rating.editsRemaining == 0)
        #expect(rating.isEditable(now: now) == false)
    }

    @Test func ratingWithoutFuelDecodesWithNoPriceCheck() throws {
        let page = try decode(PublicRatingsResponse.self, #"{"items": [{"id": 3, "stars": 4, "price_matched": null, "fuel_type": null, "author_ref": "abc"}]}"#)
        #expect(page.items[0].priceMatched == nil)
        #expect(page.items[0].fuelType == nil)
        #expect(RatingCopy.matchLabel(page.items[0]) == nil)

        let summary = try decode(RatingSummaryDTO.self, #"{"rater_count": 3, "avg_stars": 4, "price_check_count": 0, "price_match_pct": null, "avg_gap_pence": null}"#)
        #expect(summary.priceCheckCount == 0)
        #expect(summary.priceMatchPct == nil)
    }

    @Test func ratingWithoutFuelSendsExplicitNulls() throws {
        let data = try RatingInput(fuelType: nil, priceMatched: nil, reportedPricePence: nil, stars: 3, comment: nil).asJSONData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["fuel_type"] is NSNull)
        #expect(object?["price_matched"] is NSNull)
    }

    @Test func ratingInputSendsExplicitNulls() throws {
        let data = try RatingInput(fuelType: "E10", priceMatched: true, reportedPricePence: nil, stars: 4, comment: nil).asJSONData()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["fuel_type"] as? String == "E10")
        #expect(object?["price_matched"] as? Bool == true)
        #expect(object?["stars"] as? Int == 4)
        #expect(object?["comment"] is NSNull)
        #expect(object?["reported_price_pence"] is NSNull)
    }
}

struct RatingFormatTests {
    @Test func gapPhrasesAndSignedPence() {
        #expect(RatingFormat.gapPhrase(4) == "4p more than listed")
        #expect(RatingFormat.gapPhrase(-2) == "2p less than listed")
        #expect(RatingFormat.gapPhrase(3.1) == "3.1p more than listed")
        #expect(RatingFormat.signedPence(4) == "+4p")
        #expect(RatingFormat.signedPence(-2) == "\u{2212}2p")
    }

    @Test func datesAreUKFormatInLondonTime() {
        // 23:30 UTC on 30 Sep is already 1 Oct in London (BST); on 31 Oct, after the clocks go
        // back, it's still 31 Oct (GMT).
        #expect(RatingFormat.ukDate("2026-09-30T23:30:00.000Z") == "1 Oct 2026")
        #expect(RatingFormat.ukDate("2026-10-31T23:30:00Z") == "31 Oct 2026")
    }
}

@MainActor
struct RatingSheetModeTests {

    @Test func signedOutOrUnavailableBeforeAnyState() {
        #expect(RatingSheetMode.resolve(state: nil, isLoading: true, now: now) == .loading)
        #expect(RatingSheetMode.resolve(state: nil, isLoading: false, now: now) == .unavailable)
    }

    @Test func cooldownWinsWhenRatingIsNotEditable() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(
            rating: ownRatingJSON(editsRemaining: 0), canRateAt: "2026-10-08T09:00:00.000Z", blockers: ["email_unverified"]
        ))
        let mode = RatingSheetMode.resolve(state: state, isLoading: false, now: now)
        #expect(mode == .cooldown(ratedOn: "2026-10-01T09:00:00.000Z", canRateAt: "2026-10-08T09:00:00.000Z"))
    }

    @Test func emailVerificationBeforeOtherBlockers() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(blockers: ["email_unverified", "account_too_new"]))
        #expect(RatingSheetMode.resolve(state: state, isLoading: false, now: now) == .verifyEmail)
    }

    @Test func blockersOtherThanTermsShowTheirMessage() throws {
        let suspended = try decode(MyRatingStateDTO.self, mineJSON(blockers: ["suspended"]))
        #expect(RatingSheetMode.resolve(state: suspended, isLoading: false, now: now)
            == .blocked(message: "Your account can no longer leave ratings."))

        let tooNew = try decode(MyRatingStateDTO.self, mineJSON(blockers: ["terms", "account_too_new"]))
        #expect(RatingSheetMode.resolve(state: tooNew, isLoading: false, now: now)
            == .blocked(message: "Accounts need to be 3 days old before they can leave a rating."))
    }

    @Test func termsAloneShowsTheFormWithTheCheckbox() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(blockers: ["terms"]))
        #expect(RatingSheetMode.resolve(state: state, isLoading: false, now: now) == .form(existing: nil, needsTerms: true))
    }

    @Test func editableRatingOpensEditModeEvenDuringCooldown() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(rating: ownRatingJSON(), canRateAt: "2026-10-08T09:00:00.000Z"))
        guard case .form(let existing, let needsTerms) = RatingSheetMode.resolve(state: state, isLoading: false, now: now) else {
            Issue.record("Expected the form")
            return
        }
        #expect(existing?.id == 9)
        #expect(needsTerms == false)
    }

    @Test func expiredEditWindowIsNotEditable() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON(
            rating: ownRatingJSON(editableUntil: "2026-10-01T08:00:00.000Z"), canRateAt: "2026-10-08T09:00:00.000Z"
        ))
        guard case .cooldown = RatingSheetMode.resolve(state: state, isLoading: false, now: now) else {
            Issue.record("Expected the cooldown message")
            return
        }
    }

    @Test func stationWithNoPricesCanStillBeRatedWithoutFuel() throws {
        let state = try decode(MyRatingStateDTO.self, mineJSON())
        #expect(RatingSheetMode.resolve(state: state, isLoading: false, now: now) == .form(existing: nil, needsTerms: false))
    }
}

@MainActor
struct StationRatingsViewModelTests {
    private func makeViewModel(_ repository: FakeRatingsRepository) -> StationRatingsViewModel {
        StationRatingsViewModel(stationId: 431, repository: repository, analytics: NoOpAppAnalytics(), now: { now })
    }

    private func fillForm(_ viewModel: StationRatingsViewModel) {
        viewModel.setPriceMatched(false)
        viewModel.setPaidText("152.9")
        viewModel.setStars(2)
        viewModel.setComment("  Pump was 3p more  ")
    }

    @Test func newRatingDefaultsToTheUsualFuel() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10", "E5"], defaultFuelType: "E5")
        #expect(viewModel.formFuelType == "E5")

        viewModel.openRateSheet(fuelTypes: ["E10"], defaultFuelType: "B7_STANDARD")
        #expect(viewModel.formFuelType == "E10")

        viewModel.openRateSheet(fuelTypes: [], defaultFuelType: "E10")
        #expect(viewModel.formFuelType == nil)
    }

    @Test func choosingNoFuelSkipsThePriceCheckAndSendsNulls() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        repository.createResult = .success(try decode(RatingSaveResponse.self, #"{"rating": \#(ownRatingJSON(commentStatus: "approved")), "can_rate_at": null}"#))
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10", "E5"], defaultFuelType: "E5")
        fillForm(viewModel)
        viewModel.setFuelType(nil)

        #expect(viewModel.formPriceMatched == nil)
        #expect(viewModel.canSubmit == true)
        await viewModel.submit()

        #expect(repository.lastInput == RatingInput(fuelType: nil, priceMatched: nil, reportedPricePence: nil, stars: 2, comment: "Pump was 3p more"))
    }

    @Test func acceptsTermsBeforeCreatingTheRating() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON(blockers: ["terms"]))
        repository.createResult = .success(try decode(RatingSaveResponse.self, #"{"rating": \#(ownRatingJSON(commentStatus: "approved")), "can_rate_at": null}"#))
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10", "E5"], defaultFuelType: "E5")
        fillForm(viewModel)

        #expect(viewModel.canSubmit == false)
        viewModel.termsAccepted = true
        #expect(viewModel.canSubmit == true)

        await viewModel.submit()

        let terms = try #require(repository.calls.firstIndex(of: "terms"))
        let create = try #require(repository.calls.firstIndex(of: "create"))
        #expect(terms < create)
        #expect(repository.acceptedTermsVersion == "1")
        #expect(repository.lastInput == RatingInput(fuelType: "E5", priceMatched: false, reportedPricePence: 152.9, stars: 2, comment: "Pump was 3p more"))
        guard case .saved(let saved) = viewModel.sheetMode else {
            Issue.record("Expected the saved state")
            return
        }
        #expect(RatingCopy.savedMessage(saved) == "Thanks — your rating is live.")
    }

    @Test func cooldownConflictCarryingTheRatingCountsAsSaved() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        let body = Data(#"{"detail": "You can rate this station once every 7 days.", "reason": "cooldown", "can_rate_at": "2026-10-08T09:00:00.000Z", "rating": \#(ownRatingJSON(commentStatus: "held"))}"#.utf8)
        repository.createResult = .failure(APIError.rejected(status: 409, message: "You can rate this station once every 7 days.", reason: "cooldown", body: body))
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10"], defaultFuelType: "E10")
        fillForm(viewModel)

        await viewModel.submit()

        #expect(viewModel.submitError == nil)
        #expect(viewModel.savedRating?.id == 9)
        #expect(viewModel.savedRating.map(RatingCopy.savedMessage) == "Thanks — your rating counts now. Your comment will appear once it's been checked.")
    }

    @Test func otherRejectionsShowTheAPIDetail() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        let body = Data(#"{"detail": "You can leave up to 5 ratings a day.", "reason": "daily_cap"}"#.utf8)
        repository.createResult = .failure(APIError.rejected(status: 403, message: "You can leave up to 5 ratings a day.", reason: "daily_cap", body: body))
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10"], defaultFuelType: "E10")
        fillForm(viewModel)

        await viewModel.submit()

        #expect(viewModel.savedRating == nil)
        #expect(viewModel.submitError == "You can leave up to 5 ratings a day.")
        #expect(viewModel.isSubmitting == false)
    }

    @Test func editModePrefillsAndPatchesTheExistingRating() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON(rating: ownRatingJSON(), canRateAt: "2026-10-08T09:00:00.000Z"))
        repository.updateResult = .success(try decode(RatingSaveResponse.self, #"{"rating": \#(ownRatingJSON(editsRemaining: 2))}"#))
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        #expect(viewModel.rateButtonTitle == "Edit your rating")

        viewModel.openRateSheet(fuelTypes: ["E10", "E5"], defaultFuelType: "E5")
        #expect(viewModel.formFuelType == "E10")
        #expect(viewModel.formPriceMatched == false)
        #expect(viewModel.formPaidText == "152.9")
        #expect(viewModel.formStars == 2)
        #expect(viewModel.formComment == "Pump was 3p more")

        viewModel.setStars(1)
        await viewModel.submit()

        #expect(repository.calls.contains("update:9"))
        #expect(!repository.calls.contains("create"))
        #expect(repository.lastInput?.stars == 1)
        #expect(viewModel.savedRating?.editsRemaining == 2)
    }

    @Test func paidPriceOutsideRangeBlocksSubmit() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        let viewModel = makeViewModel(repository)
        await viewModel.refreshMine()
        viewModel.openRateSheet(fuelTypes: ["E10"], defaultFuelType: "E10")
        fillForm(viewModel)
        viewModel.setPaidText("40")
        #expect(viewModel.canSubmit == false)
        viewModel.setPaidText("")
        #expect(viewModel.canSubmit == true)
    }

    @Test func commentIsCappedAt280Characters() {
        let viewModel = makeViewModel(FakeRatingsRepository())
        viewModel.setComment(String(repeating: "a", count: 300))
        #expect(viewModel.formComment.count == 280)
    }

    @Test func blockedReviewersAreFilteredAndCanBeShownAgain() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON())
        repository.blocked = ["ref-a"]
        let items = [try publicRating(id: 1, authorRef: "ref-a"), try publicRating(id: 2, authorRef: "ref-b"), try publicRating(id: 3, authorRef: "ref-a")]
        repository.ratingsPages[1] = try decode(PublicRatingsResponse.self, """
        {"items": [\(items.map(Self.json).joined(separator: ","))], "total": 3, "page": 1, "page_size": 20}
        """)
        let viewModel = makeViewModel(repository)
        await viewModel.loadInitial()

        #expect(viewModel.visibleRatings.map(\.id) == [2])
        #expect(viewModel.hiddenRatingCount == 2)

        await viewModel.showHiddenReviewers()

        #expect(repository.calls.filter { $0 == "unblock:ref-a" }.count == 1)
        #expect(viewModel.visibleRatings.map(\.id) == [1, 2, 3])
        #expect(viewModel.hiddenRatingCount == 0)
    }

    @Test func hidingAReviewerFiltersTheirComments() async throws {
        let repository = FakeRatingsRepository()
        let viewModel = makeViewModel(repository)
        repository.ratingsPages[1] = try decode(PublicRatingsResponse.self, """
        {"items": [\(Self.json(try publicRating(id: 5, authorRef: "ref-5"))), \(Self.json(try publicRating(id: 6, authorRef: "ref-6")))], "total": 2, "page": 1, "page_size": 20}
        """)
        await viewModel.loadInitial()
        #expect(viewModel.visibleRatings.count == 2)

        await viewModel.hideReviewer(viewModel.visibleRatings[0])

        #expect(viewModel.visibleRatings.map(\.id) == [6])
        #expect(viewModel.hiddenRatingCount == 1)
    }

    @Test func signingOutClearsOwnState() async throws {
        let repository = FakeRatingsRepository()
        repository.mine = try decode(MyRatingStateDTO.self, mineJSON(rating: ownRatingJSON()))
        repository.blocked = ["ref-a"]
        let viewModel = makeViewModel(repository)
        await viewModel.authChanged()
        #expect(viewModel.ownRating != nil)

        repository.isLoggedIn = false
        await viewModel.authChanged()

        #expect(viewModel.myRating == nil)
        #expect(viewModel.blockedAuthorRefs.isEmpty)
        #expect(viewModel.rateButtonTitle == "Rate this station")
    }

    @Test func ownStatusExplainsModeration() throws {
        let rejected = try decode(MyRatingStateDTO.self, mineJSON(
            rating: ownRatingJSON(commentStatus: "rejected", editsRemaining: 0, moderationReason: "Contains a phone number"),
            canRateAt: "2026-10-08T09:00:00.000Z"
        ))
        #expect(RatingCopy.ownStatus(rejected, now: now)
            == "You rated this station on 1 Oct 2026. Your comment wasn't published: Contains a phone number. You can rate it again from 8 Oct 2026.")
    }

    private static func json(_ rating: PublicRatingDTO) -> String {
        """
        {"id": \(rating.id), "stars": \(rating.stars), "price_matched": \(rating.priceMatched ?? true), "fuel_type": "\(rating.fuelType ?? "")",
         "gap_pence": null, "comment": "Fine", "created_at": "\(rating.createdAt)", "edited": false, "author_ref": "\(rating.authorRef)"}
        """
    }
}
