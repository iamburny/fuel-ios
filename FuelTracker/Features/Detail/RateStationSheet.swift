import SwiftUI

/// The rating form, plus whatever has to happen before it: waiting out the 7-day cooldown,
/// verifying an email address, or a blocker the user can't clear here. The content policy is
/// accepted inline, as part of submitting. Opens in edit mode while the user's latest rating is
/// still editable.
struct RateStationSheet: View {
    let viewModel: StationRatingsViewModel
    let stationName: String
    let useLongNames: Bool
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
    }

    /// `true`/`false` for editing/new while the form is showing, `nil` for every other state.
    private var formIsEditing: Bool? {
        if case .form(let existing, _) = viewModel.sheetMode { return existing != nil }
        return nil
    }

    private var title: String {
        formIsEditing == true ? "Edit your rating" : "Rate this station"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let editing = formIsEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onClose)
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSubmitting {
                    ProgressView()
                } else {
                    Button(editing ? "Save changes" : "Submit rating") {
                        Task { await viewModel.submit() }
                    }
                    .disabled(!viewModel.canSubmit)
                }
            }
        }
        if formIsEditing == nil {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaved ? "Done" : "Close", action: onClose)
            }
        }
    }

    private var isSaved: Bool {
        if case .saved = viewModel.sheetMode { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.sheetMode {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            message("Your session has expired. Sign in again to continue.")
        case .unavailable:
            message("Ratings aren't available right now. Please try again later.")
        case .cooldown(let ratedOn, let canRateAt):
            let rated = ratedOn.map { "You rated this station on \(RatingFormat.ukDate($0)). " } ?? ""
            message(rated + "You can rate it again from \(RatingFormat.ukDate(canRateAt)).")
        case .verifyEmail:
            verifyEmailPanel
        case .blocked(let text):
            message(text)
        case .noFuels:
            message("This station isn't listing any prices at the moment, so there's nothing to compare against.")
        case .form(let existing, let needsTerms):
            form(existing: existing, needsTerms: needsTerms)
        case .saved(let rating):
            message(RatingCopy.savedMessage(rating))
        }
    }

    private func message(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    private var verifyEmailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("To keep ratings trustworthy, we need to confirm your email address before you can rate. We'll send you a link; open it on any device, then come back here.")

                switch viewModel.verifyEmailStatus {
                case .sent:
                    Text("Check your inbox (and spam folder) for the verification link. It expires in 24 hours.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .alreadyVerified:
                    Text("Your email is already verified. Close this and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .failed(let error):
                    Text(error).font(.subheadline).foregroundStyle(.red)
                case .idle, .sending:
                    EmptyView()
                }

                Button {
                    Task { await viewModel.sendVerificationEmail() }
                } label: {
                    switch viewModel.verifyEmailStatus {
                    case .sending: Text("Sending…")
                    case .sent: Text("Email sent")
                    default: Text("Send verification email")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.verifyEmailStatus == .sending || viewModel.verifyEmailStatus == .sent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    @ViewBuilder
    private func form(existing: OwnRatingDTO?, needsTerms: Bool) -> some View {
        Form {
            Section {
                Text(stationName).font(.headline)
                if viewModel.fuelTypes.count > 1 {
                    Picker("Which fuel did you buy?", selection: Binding(
                        get: { viewModel.formFuelType },
                        set: { viewModel.setFuelType($0) }
                    )) {
                        ForEach(viewModel.fuelTypes, id: \.self) { type in
                            Text(FuelType.label(forRaw: type, useLongNames: useLongNames)).tag(type)
                        }
                    }
                } else {
                    Text("Fuel: \(FuelType.label(forRaw: viewModel.formFuelType, useLongNames: useLongNames))")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Did the pump price match the price shown?") {
                choiceRow("Yes, it matched", selected: viewModel.formPriceMatched == true) {
                    viewModel.setPriceMatched(true)
                }
                choiceRow("No, it was different", selected: viewModel.formPriceMatched == false) {
                    viewModel.setPriceMatched(false)
                }
            }

            if viewModel.formPriceMatched == false {
                Section {
                    TextField("e.g. 152.9", text: Binding(
                        get: { viewModel.formPaidText },
                        set: { viewModel.setPaidText($0) }
                    ))
                    .keyboardType(.decimalPad)
                } header: {
                    Text("What did you pay per litre? (optional, in pence)")
                } footer: {
                    Text(viewModel.paidIsValid ? "Pence per litre, as shown on the pump." : "Enter a price between 50 and 400 pence.")
                        .foregroundStyle(viewModel.paidIsValid ? Color.secondary : Color.red)
                }
            }

            Section("Overall, how would you rate this station?") {
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { n in
                        let filled = (viewModel.formStars ?? 0) >= n
                        Button {
                            viewModel.setStars(n)
                        } label: {
                            Image(systemName: filled ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
                        .accessibilityAddTraits(viewModel.formStars == n ? .isSelected : [])
                    }
                }
            }

            Section {
                TextField("e.g. The pump charged 4p more than the sign said", text: Binding(
                    get: { viewModel.formComment },
                    set: { viewModel.setComment($0) }
                ), axis: .vertical)
                .lineLimit(3...6)
            } header: {
                Text("Comment (optional)")
            } footer: {
                Text("\(viewModel.formComment.utf16.count)/\(StationRatingsViewModel.commentMaxLength). Comments are checked before they appear. Please don't include names, phone numbers, number plates or links.")
            }

            if needsTerms {
                Section {
                    Toggle("I agree to the reviews content policy", isOn: Binding(
                        get: { viewModel.termsAccepted },
                        set: { viewModel.termsAccepted = $0 }
                    ))
                    Button("Read the reviews content policy") { openURL(RatingCopy.termsURL) }
                } footer: {
                    Text("My rating is my honest experience at this station.")
                }
            }

            if let existing {
                Section {
                    let edits = existing.editsRemaining
                    let until = existing.editableUntil.map(RatingFormat.ukDate) ?? ""
                    Text("You can edit this rating until \(until) (\(edits) edit\(edits == 1 ? "" : "s") left).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = viewModel.submitError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .disabled(viewModel.isSubmitting)
    }

    private func choiceRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
