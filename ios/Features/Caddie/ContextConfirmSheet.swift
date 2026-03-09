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

    private var isFormValid: Bool {
        let courseNameValid = !courseNameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cityValid = !cityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let stateValid = !stateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let holeValid = Int(holeNumberText).map { (1...18).contains($0) } ?? false
        let distanceValid = Double(distanceText).map { $0 > 0 } ?? false
        return hasPhoto && courseNameValid && cityValid && stateValid && holeValid && distanceValid
    }

    @ViewBuilder
    var body: some View {
        NavigationStack {
            ScrollView {
                mainContent
            }
            .navigationTitle("Confirm Context")
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
        .interactiveDismissDisabled(isSubmitting)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 24) {
            courseNameSection
            citySection
            stateSection
            holeNumberSection
            distanceInputSection
            shotTypeSection
            lieTypeSection
            hazardsSection
            confidenceSection

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
        Text("Required: photo, course name, city, state, hole number, and distance.")
            .font(GolfTheme.captionFont)
            .foregroundColor(.red)
            .padding(.horizontal)
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
                }
                Text(isSubmitting ? "Analyzing..." : "Get Recommendation")
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

#Preview {
    ContextConfirmSheet(
        draft: .constant(CaddieContextDraft()),
        confidence: .medium,
        hasPhoto: true,
        isSubmitting: false,
        onGetRecommendation: {}
    )
}
