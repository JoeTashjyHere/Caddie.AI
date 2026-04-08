//
//  CourseMapView.swift
//  Caddie.ai
//
//  Map view showing user location and course markers

import SwiftUI
import MapKit
import CoreLocation

// Add user location annotation
struct UserLocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

// Wrapper struct to make CLLocationCoordinate2D observable in onChange
struct LocationKey: Equatable {
    let latitude: Double
    let longitude: Double
    
    init?(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate = coordinate else { return nil }
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct CourseMapView: View {
    let courses: [Course]
    let userLocation: CLLocationCoordinate2D?
    let selectedCourseId: String?
    let onCourseSelected: (Course) -> Void
    
    @State private var position: MapCameraPosition
    @State private var mapAnnotations: [CourseAnnotation] = []
    
    // Computed property to make userLocation observable
    private var userLocationKey: LocationKey? {
        LocationKey(userLocation)
    }
    
    init(
        courses: [Course],
        userLocation: CLLocationCoordinate2D?,
        selectedCourseId: String? = nil,
        onCourseSelected: @escaping (Course) -> Void
    ) {
        self.courses = courses
        self.userLocation = userLocation
        self.selectedCourseId = selectedCourseId
        self.onCourseSelected = onCourseSelected
        
        // Initialize position to show user location or default to a reasonable area
        let initialLocation = userLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: initialLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )))
    }
    
    var body: some View {
        Map(position: $position) {
            ForEach(mapAnnotations) { annotation in
                Annotation(annotation.course.displayName, coordinate: annotation.coordinate) {
                    CourseMapPin(
                        course: annotation.course,
                        isSelected: annotation.course.id == selectedCourseId,
                        onTap: {
                            onCourseSelected(annotation.course)
                        }
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            updateAnnotations()
            updateRegion()
        }
        .onChange(of: courses) { oldValue, newValue in
            updateAnnotations()
            updateRegion()
        }
        .onChange(of: userLocationKey) { oldValue, newValue in
            updateRegion()
        }
        .onChange(of: selectedCourseId) { oldValue, newValue in
            // Recenter map on selected course
            if let selectedId = newValue,
               let selectedCourse = courses.first(where: { $0.id == selectedId }),
               let location = selectedCourse.location {
                withAnimation(.easeInOut(duration: 0.5)) {
                    position = .region(MKCoordinateRegion(
                        center: location.clLocation,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }
    
    private func updateAnnotations() {
        var seen = Set<String>()
        mapAnnotations = courses.compactMap { course in
            guard let location = course.location else { return nil }
            let key = course.displayName
            guard seen.insert(key).inserted else { return nil }
            return CourseAnnotation(
                course: course,
                coordinate: location.clLocation
            )
        }
    }
    
    private func updateRegion() {
        guard !mapAnnotations.isEmpty else { return }
        
        // If user location exists, center on it
        if let userLocation = userLocation {
            let allCoordinates = mapAnnotations.map { $0.coordinate } + [userLocation]
            let bounds = calculateBounds(coordinates: allCoordinates)
            
            let centerLat = (bounds.minLat + bounds.maxLat) / 2
            let centerLon = (bounds.minLon + bounds.maxLon) / 2
            
            // Add padding to span
            let latSpan = max(bounds.maxLat - bounds.minLat, 0.01) * 1.3
            let lonSpan = max(bounds.maxLon - bounds.minLon, 0.01) * 1.3
            
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
                ))
            }
        } else {
            // Center on courses only
            let bounds = calculateBounds(coordinates: mapAnnotations.map { $0.coordinate })
            
            let centerLat = (bounds.minLat + bounds.maxLat) / 2
            let centerLon = (bounds.minLon + bounds.maxLon) / 2
            
            let latSpan = max(bounds.maxLat - bounds.minLat, 0.01) * 1.5
            let lonSpan = max(bounds.maxLon - bounds.minLon, 0.01) * 1.5
            
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                    span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
                ))
            }
        }
    }
    
    private func calculateBounds(coordinates: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        guard !coordinates.isEmpty else {
            return (0, 0, 0, 0)
        }
        
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        
        return (
            minLat: lats.min() ?? 0,
            maxLat: lats.max() ?? 0,
            minLon: lons.min() ?? 0,
            maxLon: lons.max() ?? 0
        )
    }
}

struct CourseAnnotation: Identifiable {
    let id: String
    let course: Course
    let coordinate: CLLocationCoordinate2D
    
    init(course: Course, coordinate: CLLocationCoordinate2D) {
        self.id = course.id
        self.course = course
        self.coordinate = coordinate
    }
}

struct CourseMapPin: View {
    let course: Course
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            ZStack {
                Circle()
                    .fill(isSelected ? GolfTheme.grassGreen : Color.blue)
                    .frame(width: isSelected ? 36 : 32, height: isSelected ? 36 : 32)
                    .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: "flag.fill")
                    .foregroundColor(.white)
                    .font(.system(size: isSelected ? 16 : 14))
            }
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

