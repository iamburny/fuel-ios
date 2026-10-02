import Foundation

// Station ratings: drivers' own reports of whether the pump price matched, plus stars and an
// optional moderated comment. None of this is Fuel Finder data. Every field the backend might
// omit decodes to a default rather than failing, so an older or newer backend never blanks the
// screen that shows it.

/// `rating_summary` on `GET /api/stations/{id}` — `null` until enough drivers have rated.
struct RatingSummaryDTO: Decodable, Sendable, Equatable {
    let raterCount: Int
    let avgStars: Double
    /// Raters who checked a price; a driver who didn't buy fuel rates without one.
    let priceCheckCount: Int
    /// Share of those checks where the pump matched, 0–100; `nil` when nobody checked a price.
    let priceMatchPct: Double?
    /// Mean of (price paid − price published) over mismatch reports that gave a price, so positive
    /// means drivers paid more than listed; `nil` when none gave a price.
    let avgGapPence: Double?

    enum CodingKeys: String, CodingKey {
        case raterCount = "rater_count"
        case avgStars = "avg_stars"
        case priceCheckCount = "price_check_count"
        case priceMatchPct = "price_match_pct"
        case avgGapPence = "avg_gap_pence"
    }
}

// In an extension so the memberwise initialiser is kept.
extension RatingSummaryDTO {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        raterCount = try c.decode(Int.self, forKey: .raterCount)
        avgStars = try c.decode(Double.self, forKey: .avgStars)
        priceCheckCount = try c.decodeIfPresent(Int.self, forKey: .priceCheckCount) ?? 0
        priceMatchPct = try c.decodeIfPresent(Double.self, forKey: .priceMatchPct)
        avgGapPence = try c.decodeIfPresent(Double.self, forKey: .avgGapPence)
    }
}

/// One published comment from `GET /api/stations/{id}/ratings`. Reviewers are anonymous;
/// `authorRef` is an opaque handle used only to hide a reviewer.
struct PublicRatingDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: Int
    let stars: Int
    /// Both `nil` when the driver didn't buy fuel, and so made no price check.
    let priceMatched: Bool?
    let fuelType: String?
    let gapPence: Double?
    let comment: String?
    let createdAt: String
    let edited: Bool
    let authorRef: String

    enum CodingKeys: String, CodingKey {
        case id, stars
        case priceMatched = "price_matched"
        case fuelType = "fuel_type"
        case gapPence = "gap_pence"
        case comment
        case createdAt = "created_at"
        case edited
        case authorRef = "author_ref"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        stars = try c.decode(Int.self, forKey: .stars)
        priceMatched = try c.decodeIfPresent(Bool.self, forKey: .priceMatched)
        fuelType = try c.decodeIfPresent(String.self, forKey: .fuelType)
        gapPence = try c.decodeIfPresent(Double.self, forKey: .gapPence)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        authorRef = try c.decodeIfPresent(String.self, forKey: .authorRef) ?? ""
    }
}

struct PublicRatingsResponse: Decodable, Sendable {
    let items: [PublicRatingDTO]
    let total: Int
    let page: Int
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([PublicRatingDTO].self, forKey: .items) ?? []
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 20
    }
}

/// The signed-in user's own rating, including where its comment stands in moderation.
struct OwnRatingDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: Int
    let stationId: Int
    let stars: Int
    let priceMatched: Bool?
    let fuelType: String?
    let reportedPricePence: Double?
    let publishedPricePence: Double?
    let gapPence: Double?
    let comment: String?
    /// `none | pending | approved | held | rejected | hidden`, kept as the raw string so an
    /// unknown future status still decodes (and reads as "not yet published").
    let commentStatus: String
    /// Only set for a rejected comment.
    let moderationReason: String?
    let editsRemaining: Int
    let editableUntil: String?
    let createdAt: String
    let editedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case stationId = "station_id"
        case stars
        case priceMatched = "price_matched"
        case fuelType = "fuel_type"
        case reportedPricePence = "reported_price_pence"
        case publishedPricePence = "published_price_pence"
        case gapPence = "gap_pence"
        case comment
        case commentStatus = "comment_status"
        case moderationReason = "moderation_reason"
        case editsRemaining = "edits_remaining"
        case editableUntil = "editable_until"
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        stationId = try c.decodeIfPresent(Int.self, forKey: .stationId) ?? 0
        stars = try c.decode(Int.self, forKey: .stars)
        priceMatched = try c.decodeIfPresent(Bool.self, forKey: .priceMatched)
        fuelType = try c.decodeIfPresent(String.self, forKey: .fuelType)
        reportedPricePence = try c.decodeIfPresent(Double.self, forKey: .reportedPricePence)
        publishedPricePence = try c.decodeIfPresent(Double.self, forKey: .publishedPricePence)
        gapPence = try c.decodeIfPresent(Double.self, forKey: .gapPence)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        commentStatus = try c.decodeIfPresent(String.self, forKey: .commentStatus) ?? "none"
        moderationReason = try c.decodeIfPresent(String.self, forKey: .moderationReason)
        editsRemaining = try c.decodeIfPresent(Int.self, forKey: .editsRemaining) ?? 0
        editableUntil = try c.decodeIfPresent(String.self, forKey: .editableUntil)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        editedAt = try c.decodeIfPresent(String.self, forKey: .editedAt)
    }

    /// Still inside the edit window with edits left — the rate sheet then opens in edit mode.
    func isEditable(now: Date = Date()) -> Bool {
        guard editsRemaining > 0, let until = editableUntil.flatMap(RatingFormat.parseDate) else { return false }
        return until > now
    }
}

/// What stops the caller rating right now, in the order the backend says to resolve them.
enum RatingBlocker: String, Sendable {
    case suspended
    case emailUnverified = "email_unverified"
    case accountTooNew = "account_too_new"
    case terms
    case dailyCap = "daily_cap"
}

/// `GET /api/ratings/mine?station_id=`.
struct MyRatingStateDTO: Decodable, Sendable, Equatable {
    let rating: OwnRatingDTO?
    let canRateAt: String?
    /// Raw codes, so an unknown future blocker still decodes; see `RatingBlocker` for the known ones.
    let blockers: [String]
    let dailyCapResetsAt: String?
    let termsVersion: String?

    enum CodingKeys: String, CodingKey {
        case rating
        case canRateAt = "can_rate_at"
        case blockers
        case dailyCapResetsAt = "daily_cap_resets_at"
        case termsVersion = "terms_version"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try c.decodeIfPresent(OwnRatingDTO.self, forKey: .rating)
        canRateAt = try c.decodeIfPresent(String.self, forKey: .canRateAt)
        blockers = try c.decodeIfPresent([String].self, forKey: .blockers) ?? []
        dailyCapResetsAt = try c.decodeIfPresent(String.self, forKey: .dailyCapResetsAt)
        termsVersion = try c.decodeIfPresent(String.self, forKey: .termsVersion)
    }
}

/// Body for both `POST /api/stations/{id}/ratings` and `PATCH /api/ratings/{id}`. Encodes absent
/// values as explicit `null`s, so an edit that clears the comment says so rather than leaving the
/// key out. A driver who didn't buy fuel sends a `nil` `fuelType`, and then `priceMatched` is
/// `nil` too.
struct RatingInput: Encodable, Sendable, Equatable {
    let fuelType: String?
    let priceMatched: Bool?
    let reportedPricePence: Double?
    let stars: Int
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case priceMatched = "price_matched"
        case reportedPricePence = "reported_price_pence"
        case stars, comment
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fuelType, forKey: .fuelType)
        try c.encode(priceMatched, forKey: .priceMatched)
        try c.encode(reportedPricePence, forKey: .reportedPricePence)
        try c.encode(stars, forKey: .stars)
        try c.encode(comment, forKey: .comment)
    }
}

/// Response to a create (which also carries `can_rate_at`) or an edit (which doesn't).
struct RatingSaveResponse: Decodable, Sendable {
    let rating: OwnRatingDTO
    let canRateAt: String?

    enum CodingKeys: String, CodingKey {
        case rating
        case canRateAt = "can_rate_at"
    }
}

/// The body of a 409 `reason: "cooldown"` answer to a create: the caller already rated this
/// station recently, and `rating` is that stored rating — which is what a retried submit gets back.
struct RatingCooldownBody: Decodable, Sendable {
    let reason: String?
    let canRateAt: String?
    let rating: OwnRatingDTO?

    enum CodingKeys: String, CodingKey {
        case reason
        case canRateAt = "can_rate_at"
        case rating
    }
}

struct ReportRatingRequest: Encodable, Sendable {
    let reason: String
}

struct BlockAuthorResponse: Decodable, Sendable {
    let authorRef: String

    enum CodingKeys: String, CodingKey {
        case authorRef = "author_ref"
    }
}

struct BlockedReviewersResponse: Decodable, Sendable {
    let authorRefs: [String]

    enum CodingKeys: String, CodingKey {
        case authorRefs = "author_refs"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authorRefs = try c.decodeIfPresent([String].self, forKey: .authorRefs) ?? []
    }
}

struct VerifyEmailResponse: Decodable, Sendable {
    let ok: Bool
    let alreadyVerified: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case alreadyVerified = "already_verified"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        alreadyVerified = try c.decodeIfPresent(Bool.self, forKey: .alreadyVerified) ?? false
    }
}

struct AcceptTermsRequest: Encodable, Sendable {
    let version: String
}
