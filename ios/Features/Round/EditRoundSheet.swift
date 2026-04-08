//
//  EditRoundSheet.swift
//  Caddie.ai
//

import SwiftUI

struct EditRoundSheet: View {
    let currentCourse: Course
    @Binding var currentHole: Int
    /// When set, hole picker is limited to this range (e.g. front/back nine).
    var allowedHoleRange: ClosedRange<Int>? = nil
    let onCourseChange: () -> Void
    
    @EnvironmentObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @Environment(\.dismiss) var dismiss
    
    @State private var showingCourseSelection = false
    @State private var selectedCourse: Course?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    HStack {
                        Text((selectedCourse ?? currentCourse).name)
                            .font(GolfTheme.bodyFont)
                        Spacer()
                        Button("Change") {
                            showingCourseSelection = true
                        }
                        .foregroundColor(GolfTheme.grassGreen)
                    }
                }
                
                Section("Hole") {
                    Picker("Hole", selection: $currentHole) {
                        ForEach(1...18, id: \.self) { hole in
                            Text("Hole \(hole)").tag(hole)
                        }
                    }
                }
            }
            .navigationTitle("Edit Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(GolfTheme.grassGreen)
                }
            }
            .sheet(isPresented: $showingCourseSelection) {
                CourseSelectionView()
                    .environmentObject(courseViewModel)
                    .environmentObject(locationService)
                    .onDisappear {
                        if let newCourse = courseViewModel.currentCourse {
                            selectedCourse = newCourse
                            onCourseChange()
                        }
                    }
            }
        }
    }
}

#Preview {
    EditRoundSheet(
        currentCourse: Course(name: "Pebble Beach Golf Links", par: 72),
        currentHole: .constant(5),
        allowedHoleRange: nil,
        onCourseChange: {}
    )
    .environmentObject(CourseViewModel())
    .environmentObject(LocationService.shared)
}

