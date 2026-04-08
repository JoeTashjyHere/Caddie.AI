//
//  ContextConfirmSheet.swift
//  Caddie.ai
//
//  Bottom sheet for confirming/editing context

import SwiftUI

struct ContextConfirmSheet: View {
    @Binding var draft: CaddieContextDraft
    let confidence: ConfidenceLevel
    let hasPhoto: Bool
    let isSubmitting: Bool
    let onGetRecommendation: () -> Void
    /// In-round flow: uses backend `courseId` from the active round.
    var roundContextMode: Bool = false
    /// Quick (text-only) mode does not require a photo.
    var photoOptional: Bool = false
    var isPuttingFlow: Bool = false

    @State private var distanceText: String = ""
    @State private var selectedLie: String = "Fairway"
    @State private var selectedShotType: ShotType = .approach
    @State private var courseNameText: String = ""
    @State private var cityText: String = ""
    @State private var stateText: String = ""
    @State private var holeNumberText: String = ""
    @State private var hazardsText: String = ""
    @State private var showValidationError: Bool = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case courseName
        case city
        case state
        case holeNumber
        case distance
        case hazards
    }

    let lieOptions = ["Fairway", "Rough", "Bunker", "Tee"]

    private var backendCourseIdMissing: Bool {
        let cid = draft.courseId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cid.isEmpty
    }

    private var isFormValid: Bool {
        let courseNameValid = !courseNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let holeValid = Int(holeNumberText).map { (1...18).contains($0) } ?? false
        let distanceValid = Double(distanceText).map { $0 > 0 } ?? false
        let photoOk = hasPhoto || photoOptional
        return photoOk && courseNameValid && holeValid && distanceValid && !backendCourseIdMissing
    }

    @ViewBuilder
    var body: some View {
        NavigationStack {
            ScrollView {
                if roundContextMode {
                    verifyContent
                } else {
                    mainContent
                }
            }
            .navigationTitle(roundContextMode ? "Verify Shot" : "Confirm Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                setupInitialValues()
            }
        }
        .presentationDetents(roundContextMode ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSubmitting)
    }

    /// Compact verification layout for in-round context (auto-filled, 1-tap confirm).
    @ViewBuilder
    private var verifyContent: some View {
        VStack(spacing: 16) {
            autoDetectedBadge
                .padding(.horizontal)
                .padding(.top, 4)

            verifyGrid
                .padding(.horizontal)

            if !isPuttingFlow {
                verifyShotRow
                    .padding(.horizontal)
            }

            if let h = hazardsText.nilIfEmpty {
                verifyField(icon: "exclamationmark.triangle.fill", label: "Hazards", value: h, color: .orange)
                    .padding(.horizontal)
            }

            if backendCourseIdMissing {
                Text("Course data required for accurate recommendations")
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if showValidationError && !isFormValid {
                validationErrorMessage
            }

            getRecommendationButton
                .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private var autoDetectedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GolfTheme.grassGreen)
            Text("Auto-detected")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GolfTheme.grassGreen)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(GolfTheme.grassGreen.opacity(0.1))
        .cornerRadius(8)
    }

    private var verifyGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            verifyTile(label: "Course", value: courseNameText.isEmpty ? "--" : courseNameText, icon: "flag.fill", color: GolfTheme.grassGreen)
            verifyTile(label: "Hole", value: holeNumberText.isEmpty ? "--" : "Hole \(holeNumberText)" + (draft.holePar.map { " • Par \($0)" } ?? ""), icon: "mappin.circle.fill", color: .blue)
            verifyTile(label: "Distance", value: distanceText.isEmpty ? "--" : "\(distanceText) yds", icon: "ruler.fill", color: .purple)
            verifyTile(label: "Tee", value: draft.teeName ?? "--", icon: "circle.fill", color: GolfTheme.accentGold)
        }
    }

    private func verifyTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(GolfTheme.textSecondary)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GolfTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var verifyShotRow: some View {
        HStack(spacing: 10) {
            verifyField(icon: "scope", label: "Shot Type", value: selectedShotType.displayName, color: .purple)
            verifyField(icon: "circle.grid.2x2.fill", label: "Lie", value: selectedLie, color: .blue)
        }
    }

    private func verifyField(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GolfTheme.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GolfTheme.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 24) {
            courseNameSection
            holeNumberSection
            distanceInputSection
            if !isPuttingFlow {
                shotTypeSection
                lieTypeSection
            }
            hazardsSection
            confidenceSection

            if backendCourseIdMissing {
                Text("Course data required for accurate recommendations")
                    .font(GolfTheme.captionFont)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if showValidationError && !isFormValid {
                validationErrorMessage
            }

            getRecommendationButton
        }
        .padding(.top)
    }

    private var courseNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Course Name *")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            TextField("Enter course name", text: $courseNameText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .courseName)
                .onChange(of: courseNameText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.courseName = trimmed.isEmpty ? nil : trimmed
                    showValidationError = false
                }
        }
        .padding(.horizontal)
    }

    private var citySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("City *")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            TextField("Enter city", text: $cityText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .city)
                .onChange(of: cityText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.city = trimmed.isEmpty ? nil : trimmed
                    showValidationError = false
                }
        }
        .padding(.horizontal)
    }

    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("State *")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            TextField("Enter state (e.g., CA or California)", text: $stateText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .state)
                .onChange(of: stateText) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft.state = trimmed.isEmpty ? nil : trimmed
                    showValidationError = false
                }
        }
        .padding(.horizontal)
    }

    private var holeNumberSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hole Number *")
                .font(GolfTheme.headlineFont)
                .foregroundColor(GolfTheme.textPrimary)
            TextField("Enter hole number", text: $holeNumberText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .holeNumber)
                .onChange(of: holeNumberText) { _, newValue in
                    if let holeNumber = Int(newValue) {
                        draft.holeNumber = holeNumber
                    } else if newValue.isEmpty {
                        draft.holeNumber = nil
                    }
                }
        }
        .padding(.horizontal)
    }

    private var distanceInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distance to Target (yards) *")
                .font(GolfTheme.headlineFont)
            TextField("Enter distance", text: $distanceText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .distance)
                .onChange(of: distanceText) { _, newValue in
                    if let value = Double(newValue), value > 0 {
                        draft.distanceYards = value
                    } else if newValue.isEmpty {
                        draft.distanceYards = nil
                    }
                }
        }
        .padding(.horizontal)
    }

    private var shotTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shot Type")
                .font(GolfTheme.headlineFont)
            Picker("Shot Type", selection: $selectedShotType) {
                ForEach([ShotType.approach, .drive, .chip], id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedShotType) { _, newValue in
                draft.shotType = newValue
            }
        }
        .padding(.horizontal)
    }

    private var lieTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lie")
                .font(GolfTheme.headlineFont)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(lieOptions, id: \.self) { lie in
                        lieButton(lie: lie)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func lieButton(lie: String) -> some View {
        Button {
            selectedLie = lie
            draft.lie = lie
        } label: {
            Text(lie)
                .font(GolfTheme.bodyFont)
                .foregroundColor(selectedLie == lie ? .white : GolfTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedLie == lie ? GolfTheme.grassGreen : GolfTheme.cream)
                .cornerRadius(8)
        }
    }

    private var hazardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Known Hazards to Consider")
                .font(GolfTheme.headlineFont)
            TextField("Trees left, water short, bunker right…", text: $hazardsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .focused($focusedField, equals: .hazards)
                .onChange(of: hazardsText) { _, newValue in
                    draft.hazards = newValue.isEmpty ? nil : newValue
                }
        }
        .padding(.horizontal)
    }

    private var confidenceSection: some View {
        HStack {
            Text("Confidence:")
                .font(GolfTheme.bodyFont)
                .foregroundColor(GolfTheme.textSecondary)
            ConfidenceChipView(confidence: confidence)
            Spacer()
        }
        .padding(.horizontal)
    }

    private var validationErrorMessage: some View {
        Group {
            if backendCourseIdMissing {
                Text("Course data required for accurate recommendations.")
            } else if roundContextMode {
                Text("Required: photo (unless quick mode), course name, backend course ID, hole number, and distance.")
            } else {
                Text("Required: photo (unless quick mode), course name, backend course ID, hole number, and distance.")
            }
        }
        .font(GolfTheme.captionFont)
        .foregroundColor(.red)
        .padding(.horizontal)
    }

    private var confirmButtonLabel: String {
        if isSubmitting { return "Analyzing…" }
        if roundContextMode { return "Confirm & Get Recommendation" }
        return isPuttingFlow ? "Get Putting Read" : "Get Recommendation"
    }

    private var getRecommendationButton: some View {
        Button {
            if isFormValid {
                showValidationError = false
                focusedField = nil
                onGetRecommendation()
            } else {
                showValidationError = true
            }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else if roundContextMode {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                }
                Text(confirmButtonLabel)
                    .font(GolfTheme.headlineFont)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background((isFormValid && !isSubmitting) ? GolfTheme.grassGreen : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(16)
        }
        .disabled(!isFormValid || isSubmitting)
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    private func setupInitialValues() {
        if let distance = draft.distanceYards {
            distanceText = String(Int(distance))
        }
        selectedLie = draft.lie ?? "Fairway"
        selectedShotType = draft.shotType
        courseNameText = draft.courseName ?? ""
        cityText = draft.city ?? ""
        stateText = draft.state ?? ""
        if let holeNumber = draft.holeNumber {
            holeNumberText = String(holeNumber)
        } else {
            holeNumberText = ""
        }
        hazardsText = draft.hazards ?? ""
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    ContextConfirmSheet(
        draft: .constant(CaddieContextDraft()),
        confidence: .medium,
        hasPhoto: true,
        isSubmitting: false,
        onGetRecommendation: {}
    )
}
