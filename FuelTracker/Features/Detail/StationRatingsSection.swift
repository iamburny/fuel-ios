import SwiftUI

/// "Driver reports" on the Detail screen: the score, how often drivers found the pump price
/// matched, and their moderated comments. Everything here comes from signed-in drivers, never from
/// the Fuel Finder data, and the section says so — it sits apart from the price rows, which stay
/// exactly as published.
struct StationRatingsSection: View {
    let viewModel: StationRatingsViewModel
    let summary: RatingSummaryDTO?
    let useLongNames: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Driver reports").font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("From signed-in drivers who used this station. Not part of the official Fuel Finder price data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let summary {
                summaryCard(summary)
            } else {
                Text("Not enough reports yet. A score appears once three drivers have rated this station.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Rating itself starts from the button beside "Get directions"; this shows where the
            // user's own rating stands.
            if let status = viewModel.ownStatusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.visibleRatings) { rating in
                RatingCommentRow(
                    rating: rating,
                    useLongNames: useLongNames,
                    message: viewModel.commentMessages[rating.id],
                    isBusy: viewModel.pendingCommentActions.contains(rating.id),
                    isLoggedIn: viewModel.isLoggedIn,
                    onSignIn: onSignIn,
                    onReport: { reason in Task { await viewModel.report(rating, reason: reason) } },
                    onHideReviewer: { Task { await viewModel.hideReviewer(rating) } }
                )
            }

            if viewModel.hiddenRatingCount > 0 {
                let count = viewModel.hiddenRatingCount
                HStack(spacing: 4) {
                    Text("\(count) comment\(count == 1 ? "" : "s") from reviewers you've hidden.")
                    Button("Show them again") { Task { await viewModel.showHiddenReviewers() } }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if viewModel.canLoadMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView()
                    } else {
                        Text("Show more comments")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoadingMore)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await viewModel.loadInitial() }
    }

    @ViewBuilder
    private func summaryCard(_ summary: RatingSummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(String(format: "%.1f", summary.avgStars)).font(.title2.bold())
                    StarsView(value: summary.avgStars)
                }
                Text("Average from \(summary.raterCount) driver\(summary.raterCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let pct = summary.priceMatchPct {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(pct.rounded()))%").font(.title2.bold())
                    Text(summary.priceCheckCount < summary.raterCount
                         ? "of the \(summary.priceCheckCount) who bought fuel found the pump price matched"
                         : "found the pump price matched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let gap = summary.avgGapPence, gap != 0 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RatingFormat.signedPence(gap)).font(.title2.bold())
                    Text("on average when it didn't (\(RatingFormat.gapPhrase(gap)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.1)))
    }
}

/// Five stars filled to the nearest whole star, read out as the exact value.
struct StarsView: View {
    let value: Double

    var body: some View {
        let rounded = Int(value.rounded())
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= rounded ? "star.fill" : "star")
            }
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", value))
    }
}

/// One published comment, with its Report and Hide-reviewer actions. Signed-out taps on either
/// action go to sign-in instead.
private struct RatingCommentRow: View {
    let rating: PublicRatingDTO
    let useLongNames: Bool
    let message: String?
    let isBusy: Bool
    let isLoggedIn: Bool
    let onSignIn: () -> Void
    let onReport: (String) -> Void
    let onHideReviewer: () -> Void

    @State private var showingReportReasons = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StarsView(value: Double(rating.stars))
                if let fuel = rating.fuelType {
                    Text(FuelType.label(forRaw: fuel, useLongNames: useLongNames))
                        .font(.caption.bold())
                }
                if let label = RatingCopy.matchLabel(rating) {
                    let tint = rating.priceMatched == true ? Color.green : AccuracyWarningChip.tint
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }
            }
            Text("Verified driver · \(RatingFormat.ukDate(rating.createdAt))\(rating.edited ? " · edited" : "")")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let comment = rating.comment {
                Text(comment).font(.subheadline)
            }

            HStack(spacing: 16) {
                Button("Report") {
                    if isLoggedIn { showingReportReasons = true } else { onSignIn() }
                }
                Button("Hide comments from this reviewer") {
                    if isLoggedIn { onHideReviewer() } else { onSignIn() }
                }
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .disabled(isBusy)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator)))
        .confirmationDialog("Why are you reporting this?", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(RatingCopy.reportReasons, id: \.self) { reason in
                Button(reason) { onReport(reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
