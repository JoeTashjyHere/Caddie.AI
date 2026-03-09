//
//  HoleMapView.swift
//  Caddie.ai
//
//  MapKit view showing hole layout, user location, and distances (18Birdies-style)

import SwiftUI
import MapKit
import CoreLocation

// Helper to make CLLocationCoordinate2D Equatable for onChange
struct EquatableCoordinate: Equatable {
    let coordinate: CLLocationCoordinate2D
    
    static func == (lhs: EquatableCoordinate, rhs: EquatableCoordinate) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

struct HoleMapView: View {
    let courseId: String
    let holeNumber: Int
    let holeLayout: HoleLayout?
    let userLocation: CLLocationCoordinate2D?
    
    @State private var region = MKCoordinateRegion()
    @State private var distanceToGreen: Double?
    @State private var distanceToFront: Double?
    @State private var distanceToBack: Double?
    @State private var equatableUserLocation: EquatableCoordinate?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Use custom MapView wrapper that handles all overlays
            MapViewWithOverlays(
                region: $region,
                holeLayout: holeLayout,
                userLocation: userLocation,
                annotations: annotations
            )
            .mapStyle(.hybrid)
            
            // Distance bubble (top right)
            if let distance = distanceToGreen {
                distanceBubble(distance: distance)
                    .padding(.top, 60)
                    .padding(.trailing, 16)
            }
        }
        .frame(height: 300)
        .onAppear {
            setupMap()
            equatableUserLocation = userLocation.map { EquatableCoordinate(coordinate: $0) }
        }
        .onChange(of: equatableUserLocation) { oldValue, newValue in
            if let coord = newValue {
                updateDistances(from: coord.coordinate)
            }
        }
        // Update equatable wrapper when userLocation changes (tracking lat/lon separately to avoid Equatable requirement)
        .onChange(of: userLocation?.latitude) { _, _ in
            equatableUserLocation = userLocation.map { EquatableCoordinate(coordinate: $0) }
            if let location = userLocation {
                updateDistances(from: location)
            }
        }
        .onChange(of: userLocation?.longitude) { _, _ in
            equatableUserLocation = userLocation.map { EquatableCoordinate(coordinate: $0) }
            if let location = userLocation {
                updateDistances(from: location)
            }
        }
    }
    
    // MARK: - Map Annotations
    
    private var annotations: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        
        // Green center pin
        if let greenCenter = holeLayout?.greenCenter {
            items.append(MapAnnotationItem(
                coordinate: greenCenter,
                view: AnyView(
                    Image(systemName: "flag.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                        .background(GolfTheme.grassGreen)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                )
            ))
        }
        
        return items
    }
    
    
    // MARK: - Distance Bubble
    
    private func distanceBubble(distance: Double) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(distance))")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("YARDS")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(GolfTheme.grassGreen.opacity(0.95))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Setup
    
    private func setupMap() {
        guard let layout = holeLayout else { return }
        
        // Calculate bounding box of all geometries
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        
        let allPolygons = layout.greenPolygons + layout.fairwayPolygons + 
                         layout.bunkerPolygons + layout.waterPolygons + layout.teePolygons
        
        for polygon in allPolygons {
            let points = polygon.points()
            for i in 0..<polygon.pointCount {
                let coord = points[i].coordinate
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }
        }
        
        // Add padding
        let latPadding = (maxLat - minLat) * 0.2
        let lonPadding = (maxLon - minLon) * 0.2
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let spanLat = (maxLat - minLat) + latPadding * 2
        let spanLon = (maxLon - minLon) + lonPadding * 2
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: max(spanLat, 0.01), longitudeDelta: max(spanLon, 0.01))
        )
        
        // Update distances if user location available
        if let userLoc = userLocation {
            updateDistances(from: userLoc)
        }
    }
    
    private func updateDistances(from location: CLLocationCoordinate2D) {
        guard let layout = holeLayout else { return }
        
        // Distance to green center
        if let greenCenter = layout.greenCenter {
            let distance = calculateDistance(from: location, to: greenCenter)
            distanceToGreen = distance * 1.09361 // meters to yards
        }
        
        // Distance to front
        if let greenFront = layout.greenFront {
            let distance = calculateDistance(from: location, to: greenFront)
            distanceToFront = distance * 1.09361
        }
        
        // Distance to back
        if let greenBack = layout.greenBack {
            let distance = calculateDistance(from: location, to: greenBack)
            distanceToBack = distance * 1.09361
        }
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLoc = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLoc.distance(from: toLoc)
    }
}

// MARK: - Supporting Types

struct MapAnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let view: AnyView
}

// Single MapView wrapper that handles all overlays
struct MapViewWithOverlays: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let holeLayout: HoleLayout?
    let userLocation: CLLocationCoordinate2D?
    let annotations: [MapAnnotationItem]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region
        mapView.setRegion(region, animated: false)
        
        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        // Add polygon overlays
        if let layout = holeLayout {
            // Green polygons
            for polygon in layout.greenPolygons {
                mapView.addOverlay(polygon, level: .aboveLabels)
                let grassGreenUIColor = UIColor(GolfTheme.grassGreen)
                context.coordinator.configurePolygon(polygon, 
                                                     fillColor: grassGreenUIColor.withAlphaComponent(0.5),
                                                     strokeColor: grassGreenUIColor,
                                                     strokeWidth: 2)
            }
            
            // Fairway polygons
            for polygon in layout.fairwayPolygons {
                mapView.addOverlay(polygon, level: .aboveLabels)
                context.coordinator.configurePolygon(polygon,
                                                     fillColor: UIColor.systemGreen.withAlphaComponent(0.3),
                                                     strokeColor: UIColor.systemGreen,
                                                     strokeWidth: 1)
            }
            
            // Bunker polygons
            for polygon in layout.bunkerPolygons {
                mapView.addOverlay(polygon, level: .aboveLabels)
                context.coordinator.configurePolygon(polygon,
                                                     fillColor: UIColor.brown.withAlphaComponent(0.4),
                                                     strokeColor: UIColor.brown,
                                                     strokeWidth: 1)
            }
            
            // Water polygons
            for polygon in layout.waterPolygons {
                mapView.addOverlay(polygon, level: .aboveLabels)
                context.coordinator.configurePolygon(polygon,
                                                     fillColor: UIColor.systemBlue.withAlphaComponent(0.5),
                                                     strokeColor: UIColor.systemBlue,
                                                     strokeWidth: 1)
            }
            
            // Distance line from user to green
            if let userLoc = userLocation, let greenCenter = layout.greenCenter {
                let coordinates = [userLoc, greenCenter]
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                mapView.addOverlay(polyline, level: .aboveLabels)
                context.coordinator.configurePolyline(polyline)
            }
        }
        
        // Add annotations
        for annotationItem in annotations {
            let annotation = CustomAnnotation(coordinate: annotationItem.coordinate, view: annotationItem.view)
            mapView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var polygonConfigs: [MKPolygon: (fillColor: UIColor, strokeColor: UIColor, strokeWidth: CGFloat)] = [:]
        var polylineConfigs: [MKPolyline: Void] = [:]
        
        func configurePolygon(_ polygon: MKPolygon, fillColor: UIColor, strokeColor: UIColor, strokeWidth: CGFloat) {
            polygonConfigs[polygon] = (fillColor, strokeColor, strokeWidth)
        }
        
        func configurePolyline(_ polyline: MKPolyline) {
            polylineConfigs[polyline] = ()
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon, let config = polygonConfigs[polygon] {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor = config.fillColor
                renderer.strokeColor = config.strokeColor
                renderer.lineWidth = config.strokeWidth
                return renderer
            }
            
            if let polyline = overlay as? MKPolyline, polylineConfigs[polyline] != nil {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.7)
                renderer.lineWidth = 2
                renderer.lineDashPattern = [5, 5]
                return renderer
            }
            
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let customAnnotation = annotation as? CustomAnnotation {
                let identifier = "CustomAnnotation"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? CustomAnnotationView
                
                if view == nil {
                    view = CustomAnnotationView(annotation: customAnnotation, reuseIdentifier: identifier)
                } else {
                    view?.annotation = customAnnotation
                    view?.updateView(customAnnotation.view)
                }
                
                return view
            }
            
            return nil
        }
    }
}

// Custom annotation class
class CustomAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let view: AnyView
    
    init(coordinate: CLLocationCoordinate2D, view: AnyView) {
        self.coordinate = coordinate
        self.view = view
        super.init()
    }
}

// Custom annotation view
class CustomAnnotationView: MKAnnotationView {
    private var hostingController: UIHostingController<AnyView>?
    
    init(annotation: CustomAnnotation, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        centerOffset = CGPoint(x: 0, y: -frame.size.height / 2)
        updateView(annotation.view)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateView(_ view: AnyView) {
        hostingController?.view.removeFromSuperview()
        hostingController = UIHostingController(rootView: view)
        hostingController?.view.backgroundColor = .clear
        
        if let hostingView = hostingController?.view {
            hostingView.frame = bounds
            hostingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(hostingView)
        }
    }
}

// MARK: - Preview

#Preview {
    HoleMapView(
        courseId: "test-course",
        holeNumber: 1,
        holeLayout: nil,
        userLocation: CLLocationCoordinate2D(latitude: 36.568, longitude: -121.95)
    )
}


