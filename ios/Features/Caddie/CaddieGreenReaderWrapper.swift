//
//  CaddieGreenReaderWrapper.swift
//  Caddie.ai
//
//  Wrapper to reuse GreenView with CaddieSession instead of Round

import SwiftUI

struct CaddieGreenReaderWrapper: View {
    @ObservedObject var caddieSession: CaddieViewModel
    @ObservedObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var puttingViewModel = PuttingViewModel()
    
    init(caddieSession: CaddieViewModel, courseViewModel: CourseViewModel) {
        self.caddieSession = caddieSession
        self.courseViewModel = courseViewModel
    }
    
    var body: some View {
        Group {
            if let course = caddieSession.session.course,
               let holeNumber = caddieSession.session.currentHoleNumber {
                GreenView(course: course, holeNumber: holeNumber)
                    .environmentObject(locationService)
            } else {
                // Show course/hole selection if not set
                VStack(spacing: 24) {
                    Image(systemName: "flag.2.crossed")
                        .font(.system(size: 64))
                        .foregroundColor(GolfTheme.grassGreen)
                    
                    Text("Select Course & Hole")
                        .font(GolfTheme.titleFont)
                        .foregroundColor(GolfTheme.textPrimary)
                    
                    Text("Please select a course and hole number before using Green Reader")
                        .font(GolfTheme.bodyFont)
                        .foregroundColor(GolfTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    NavigationLink {
                        CaddieCourseSelectionForGreenReader(
                            caddieSession: caddieSession,
                            courseViewModel: courseViewModel
                        )
                    } label: {
                        Text("Select Course & Hole")
                            .font(GolfTheme.headlineFont)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(GolfTheme.grassGreen)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Course Selection for Green Reader

struct CaddieCourseSelectionForGreenReader: View {
    @ObservedObject var caddieSession: CaddieViewModel
    @ObservedObject var courseViewModel: CourseViewModel
    @EnvironmentObject var locationService: LocationService
    @Environment(\.dismiss) var dismiss
    
    init(caddieSession: CaddieViewModel, courseViewModel: CourseViewModel) {
        self.caddieSession = caddieSession
        self.courseViewModel = courseViewModel
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Select Course")
                .font(GolfTheme.titleFont)
                .foregroundColor(GolfTheme.textPrimary)
                .padding(.top)
            
            // Course list
            List {
                ForEach(courseViewModel.displayedCourses(searchText: "")) { course in
                    Button {
                        caddieSession.selectCourse(course)
                        // After course selection, show hole picker
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(course.displayName)
                                    .font(GolfTheme.headlineFont)
                                    .foregroundColor(GolfTheme.textPrimary)
                                if let par = course.par {
                                    Text("Par \(par)")
                                        .font(GolfTheme.captionFont)
                                        .foregroundColor(GolfTheme.textSecondary)
                                }
                            }
                            Spacer()
                            if caddieSession.session.course?.id == course.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(GolfTheme.grassGreen)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            
            // Hole selection (if course is selected)
            if caddieSession.session.course != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Hole")
                        .font(GolfTheme.headlineFont)
                        .foregroundColor(GolfTheme.textPrimary)
                        .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(1...18, id: \.self) { hole in
                                Button {
                                    caddieSession.selectHole(hole)
                                    dismiss()
                                } label: {
                                    Text("\(hole)")
                                        .font(GolfTheme.headlineFont)
                                        .foregroundColor(caddieSession.session.currentHoleNumber == hole ? .white : GolfTheme.textPrimary)
                                        .frame(width: 50, height: 50)
                                        .background(caddieSession.session.currentHoleNumber == hole ? GolfTheme.grassGreen : GolfTheme.cream)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .background(GolfTheme.cream.ignoresSafeArea())
        .navigationTitle("Setup Green Reader")
        .navigationBarTitleDisplayMode(.inline)
    }
}

