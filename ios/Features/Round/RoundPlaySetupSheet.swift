//
//  RoundPlaySetupSheet.swift
//  Caddie.ai
//
//  Tee + round length before starting Play round.
//

import SwiftUI

struct RoundPlaySetupSheet: View {
    let course: Course
    let onStart: (RoundPlayLaunchConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tees: [TeeData] = []
    @State private var selectedTeeId: String?
    @State private var roundLength: RoundLength = .full18
    @State private var loadError: String?
    @State private var isLoading = true

    /// Only show 18/Front9/Back9 selector for courses that represent a full 18-hole layout.
    private var isFullCourse: Bool {
        guard let par = course.par else { return true }
        return par >= 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.displayName)
                            .font(GolfTheme.bodyFont)
                        if let label = course.courseLabel {
                            Text(label)
                                .font(GolfTheme.captionFont)
                                .foregroundColor(GolfTheme.textSecondary)
                        }
                    }
                } header: {
                    Text("Course")
                }

                if isLoading {
                    Section {
                        ProgressView()
                    }
                } else if let loadError {
                    Section {
                        Text(loadError)
                            .foregroundColor(.red)
                    }
                } else {
                    Section {
                        if tees.isEmpty {
                            Text("No tees in course context")
                                .foregroundColor(GolfTheme.textSecondary)
                        } else {
                            Picker("Tee", selection: $selectedTeeId) {
                                ForEach(tees) { tee in
                                    Text("\(tee.name) — \(tee.totalYards) yds").tag(Optional(tee.id))
                                }
                            }
                        }
                    } header: {
                        Text("Tee")
                    }

                    if isFullCourse {
                        Section {
                            Picker("Round length", selection: $roundLength) {
                                Text("18 holes").tag(RoundLength.full18)
                                Text("Front 9").tag(RoundLength.front9)
                                Text("Back 9").tag(RoundLength.back9)
                            }
                            .pickerStyle(.segmented)
                        } header: {
                            Text("Round")
                        }
                    }
                }
            }
            .navigationTitle("Start round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let teeId = selectedTeeId ?? tees.first?.id
                        let teeName = tees.first { $0.id == teeId }?.name ?? "default"
                        print("[PLAY] Starting round for course \(course.displayName), tee \(teeName), roundType \(roundLength.rawValue)")
                        onStart(RoundPlayLaunchConfig(roundLength: roundLength, selectedTeeId: teeId))
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadTees()
            }
        }
    }

    private func loadTees() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        guard !course.id.isEmpty else {
            loadError = "Course has no id — cannot load tees."
            return
        }

        do {
            let dto = try await APIService.shared.fetchCourseContext(courseId: course.id)
            tees = dto.tees.map { TeeData(id: $0.id, name: $0.name, totalYards: $0.totalYards, slope: $0.slope, courseRating: $0.courseRating) }
            if selectedTeeId == nil {
                selectedTeeId = tees.first?.id
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
