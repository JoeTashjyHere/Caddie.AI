//
//  GreenCaddieView.swift
//  Caddie.AI iOS Client
//
//  Green mode view with interactive ball/hole positioning and aim line visualization
//

import SwiftUI
import CoreLocation

struct GreenCaddieView: View {
    let greenId: Int
    let initialBallLat: Double
    let initialBallLon: Double
    let initialHoleLat: Double
    let initialHoleLon: Double
    let onViewModelCreated: ((GreenCaddieViewModel) -> Void)?
    
    @StateObject private var viewModel: GreenCaddieViewModel
    @State private var canvasSize: CGSize = .zero
    @State private var draggedItem: DraggedItem? = nil
    
    init(
        greenId: Int,
        initialBallLat: Double,
        initialBallLon: Double,
        initialHoleLat: Double,
        initialHoleLon: Double,
        onViewModelCreated: ((GreenCaddieViewModel) -> Void)? = nil
    ) {
        self.greenId = greenId
        self.initialBallLat = initialBallLat
        self.initialBallLon = initialBallLon
        self.initialHoleLat = initialHoleLat
        self.initialHoleLon = initialHoleLon
        self.onViewModelCreated = onViewModelCreated
        
        let vm = GreenCaddieViewModel(
            greenId: greenId,
            ballLat: initialBallLat,
            ballLon: initialBallLon,
            holeLat: initialHoleLat,
            holeLon: initialHoleLon
        )
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    enum DraggedItem {
        case ball
        case hole
    }
    
    init(greenId: Int, initialBallLat: Double, initialBallLon: Double, initialHoleLat: Double, initialHoleLon: Double) {
        self.greenId = greenId
        self.initialBallLat = initialBallLat
        self.initialBallLon = initialBallLon
        self.initialHoleLat = initialHoleLat
        self.initialHoleLon = initialHoleLon
        
        _viewModel = StateObject(wrappedValue: GreenCaddieViewModel(
            greenId: greenId,
            ballLat: initialBallLat,
            ballLon: initialBallLon,
            holeLat: initialHoleLat,
            holeLon: initialHoleLon
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            summaryHeader
                .padding()
            
            // Green Canvas
            greenCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGray6))
        }
        .onAppear {
            onViewModelCreated?(viewModel)
            viewModel.fetchRead()
        }
    }
    
    // MARK: - Summary Header
    
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let response = viewModel.readingResponse {
                HStack {
                    Text("Green View")
                        .font(.headline)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                Text(formatReadingSummary(response: response))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if viewModel.isLoading {
                Text("Calculating read...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let error = viewModel.errorMessage {
                Text("Error: \(error)")
                    .font(.subheadline)
                    .foregroundColor(.red)
            } else {
                Text("Tap and drag ball/hole to adjust positions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatReadingSummary(response: GreenReadResponse) -> String {
        let distance = calculateDistance(
            lat1: viewModel.ballLat, lon1: viewModel.ballLon,
            lat2: viewModel.holeLat, lon2: viewModel.holeLon
        )
        let feet = Int(distance * 3.28084) // meters to feet
        
        let direction = response.aimOffsetFeet >= 0 ? "Right" : "Left"
        let offset = abs(response.aimOffsetFeet)
        
        return "\(feet) ft putt • \(String(format: "%.1f", offset)) in \(direction) • \(String(format: "%.1f", response.ballSlopePercent))% slope"
    }
    
    // MARK: - Green Canvas
    
    private var greenCanvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // Green shape (rounded rectangle for now)
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.green.opacity(0.3))
                    .stroke(Color.green, lineWidth: 2)
                
                // Drawing overlay
                greenDrawingOverlay(canvasSize: size)
            }
            .padding()
            .onAppear {
                canvasSize = size
            }
            .onChange(of: geometry.size) { _, newSize in
                canvasSize = newSize
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleDrag(value: value, canvasSize: canvasSize)
                }
                .onEnded { _ in
                    draggedItem = nil
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    // Long press to move hole
                    draggedItem = .hole
                }
        )
    }
    
    private func greenDrawingOverlay(canvasSize: CGSize) -> some View {
        Canvas { context, _ in
            guard canvasSize.width > 0, canvasSize.height > 0 else { return }
            
            // Calculate coordinate bounds
            guard let bounds = calculateCoordinateBounds() else { return }
            
            let (minLat, maxLat, minLon, maxLon) = bounds
            let latRange = maxLat - minLat
            let lonRange = maxLon - minLon
            
            // Calculate scale and offset
            let padding: CGFloat = 20
            let availableWidth = canvasSize.width - padding * 2
            let availableHeight = canvasSize.height - padding * 2
            
            let scaleX = availableWidth / CGFloat(lonRange)
            let scaleY = availableHeight / CGFloat(latRange)
            let scale = min(scaleX, scaleY)
            
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            
            func toViewPoint(lat: Double, lon: Double) -> CGPoint {
                let x = centerX + CGFloat((lon - (minLon + maxLon) / 2)) * scale
                let y = centerY - CGFloat((lat - (minLat + maxLat) / 2)) * scale
                return CGPoint(x: x, y: y)
            }
            
            // Draw fall line (if available)
            if let response = viewModel.readingResponse,
               let fallLine = response.fallLineFromHole,
               !fallLine.isEmpty {
                var path = Path()
                for (index, point) in fallLine.enumerated() {
                    let viewPoint = toViewPoint(lat: point.lat, lon: point.lon)
                    if index == 0 {
                        path.move(to: viewPoint)
                    } else {
                        path.addLine(to: viewPoint)
                    }
                }
                context.stroke(path, with: .color(.orange), lineWidth: 2)
            }
            
            // Draw aim line
            if let response = viewModel.readingResponse,
               !response.aimLine.isEmpty {
                var path = Path()
                for (index, point) in response.aimLine.enumerated() {
                    let viewPoint = toViewPoint(lat: point.lat, lon: point.lon)
                    if index == 0 {
                        path.move(to: viewPoint)
                    } else {
                        path.addLine(to: viewPoint)
                    }
                }
                context.stroke(path, with: .color(.blue), lineWidth: 3)
            }
            
            // Draw direct line (ball to hole, dashed)
            let ballPoint = toViewPoint(lat: viewModel.ballLat, lon: viewModel.ballLon)
            let holePoint = toViewPoint(lat: viewModel.holeLat, lon: viewModel.holeLon)
            
            var directPath = Path()
            directPath.move(to: ballPoint)
            directPath.addLine(to: holePoint)
            context.stroke(directPath, with: .color(.gray), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            
            // Draw hole
            let holeRect = CGRect(
                x: holePoint.x - 10,
                y: holePoint.y - 10,
                width: 20,
                height: 20
            )
            context.fill(Path(ellipseIn: holeRect), with: .color(.black))
            
            // Draw ball
            let ballRect = CGRect(
                x: ballPoint.x - 8,
                y: ballPoint.y - 8,
                width: 16,
                height: 16
            )
            context.fill(Path(ellipseIn: ballRect), with: .color(.white))
            context.stroke(Path(ellipseIn: ballRect), with: .color(.black), lineWidth: 2)
        }
    }
    
    private func handleDrag(value: DragGesture.Value, canvasSize: CGSize) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        guard let bounds = calculateCoordinateBounds() else { return }
        
        let location = value.location
        
        // Convert view coordinates to lat/lon
        let (minLat, maxLat, minLon, maxLon) = bounds
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        let padding: CGFloat = 20
        let availableWidth = canvasSize.width - padding * 2
        let availableHeight = canvasSize.height - padding * 2
        
        let scaleX = availableWidth / CGFloat(lonRange)
        let scaleY = availableHeight / CGFloat(latRange)
        let scale = min(scaleX, scaleY)
        
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        
        let lon = Double((location.x - centerX) / scale) + (minLon + maxLon) / 2
        let lat = Double((centerY - location.y) / scale) + (minLat + maxLat) / 2
        
        // Determine what we're dragging
        if let dragged = draggedItem {
            // Continue dragging existing item
            switch dragged {
            case .ball:
                viewModel.updateBallPosition(lat: lat, lon: lon)
            case .hole:
                viewModel.updateHolePosition(lat: lat, lon: lon)
            }
        } else {
            // Check which item is closest
            let ballPoint = toViewPoint(
                lat: viewModel.ballLat,
                lon: viewModel.ballLon,
                bounds: bounds,
                canvasSize: canvasSize
            )
            let holePoint = toViewPoint(
                lat: viewModel.holeLat,
                lon: viewModel.holeLon,
                bounds: bounds,
                canvasSize: canvasSize
            )
            
            let ballDistance = sqrt(pow(location.x - ballPoint.x, 2) + pow(location.y - ballPoint.y, 2))
            let holeDistance = sqrt(pow(location.x - holePoint.x, 2) + pow(location.y - holePoint.y, 2))
            
            let threshold: CGFloat = 30
            
            if holeDistance < threshold && holeDistance < ballDistance {
                draggedItem = .hole
                viewModel.updateHolePosition(lat: lat, lon: lon)
            } else if ballDistance < threshold {
                draggedItem = .ball
                viewModel.updateBallPosition(lat: lat, lon: lon)
            }
        }
    }
    
    private func toViewPoint(lat: Double, lon: Double, bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double), canvasSize: CGSize) -> CGPoint {
        let (minLat, maxLat, minLon, maxLon) = bounds
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        let padding: CGFloat = 20
        let availableWidth = canvasSize.width - padding * 2
        let availableHeight = canvasSize.height - padding * 2
        
        let scaleX = availableWidth / CGFloat(lonRange)
        let scaleY = availableHeight / CGFloat(latRange)
        let scale = min(scaleX, scaleY)
        
        let centerX = canvasSize.width / 2
        let centerY = canvasSize.height / 2
        
        let x = centerX + CGFloat((lon - (minLon + maxLon) / 2)) * scale
        let y = centerY - CGFloat((lat - (minLat + maxLat) / 2)) * scale
        
        return CGPoint(x: x, y: y)
    }
    
    private func calculateCoordinateBounds() -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        var allLats: [Double] = [viewModel.ballLat, viewModel.holeLat]
        var allLons: [Double] = [viewModel.ballLon, viewModel.holeLon]
        
        if let response = viewModel.readingResponse {
            for point in response.aimLine {
                allLats.append(point.lat)
                allLons.append(point.lon)
            }
            if let fallLine = response.fallLineFromHole {
                for point in fallLine {
                    allLats.append(point.lat)
                    allLons.append(point.lon)
                }
            }
        }
        
        guard !allLats.isEmpty, !allLons.isEmpty else {
            // Default bounds around ball/hole
            let padding = 0.0001
            return (
                minLat: min(viewModel.ballLat, viewModel.holeLat) - padding,
                maxLat: max(viewModel.ballLat, viewModel.holeLat) + padding,
                minLon: min(viewModel.ballLon, viewModel.holeLon) - padding,
                maxLon: max(viewModel.ballLon, viewModel.holeLon) + padding
            )
        }
        
        let minLat = allLats.min()!
        let maxLat = allLats.max()!
        let minLon = allLons.min()!
        let maxLon = allLons.max()!
        
        // Add padding
        let latPadding = max((maxLat - minLat) * 0.2, 0.00005)
        let lonPadding = max((maxLon - minLon) * 0.2, 0.00005)
        
        return (
            minLat: minLat - latPadding,
            maxLat: maxLat + latPadding,
            minLon: minLon - lonPadding,
            maxLon: maxLon + lonPadding
        )
    }
    
    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let location1 = CLLocation(latitude: lat1, longitude: lon1)
        let location2 = CLLocation(latitude: lat2, longitude: lon2)
        return location1.distance(from: location2)
    }
}

// MARK: - Preview

#Preview {
    GreenCaddieView(
        greenId: 1,
        initialBallLat: 38.8706,
        initialBallLon: -77.0294,
        initialHoleLat: 38.87061,
        initialHoleLon: -77.02939
    )
}
