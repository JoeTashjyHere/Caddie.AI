//
//  GreenReadingView.swift
//  Caddie.AI - Green Reading API Integration Example
//
//  SwiftUI view demonstrating integration with the green reading API.
//  Shows how to call the API and visualize aim line and fall line.
//

import SwiftUI

struct GreenReadingView: View {
    // API configuration
    @State private var apiBaseURL: String = "http://localhost:8081"
    
    // Input fields
    @State private var greenId: String = "1"
    @State private var ballLat: String = "36.568"
    @State private var ballLon: String = "-121.95"
    @State private var holeLat: String = "36.5681"
    @State private var holeLon: String = "-121.949"
    
    // Response data
    @State private var readingResponse: GreenReadingResponse?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Input Section
                    inputSection
                    
                    // Get Read Button
                    Button(action: fetchGreenRead) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isLoading ? "Computing..." : "Get Green Read")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isLoading ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal)
                    
                    // Error Display
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    // Results Section
                    if let response = readingResponse {
                        resultsSection(response: response)
                        
                        // Visualization
                        visualizationSection(response: response)
                    }
                }
                .padding()
            }
            .navigationTitle("Green Reading")
        }
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Parameters")
                .font(.headline)
            
            Group {
                TextField("Green Feature ID", text: $greenId)
                TextField("Ball Latitude", text: $ballLat)
                TextField("Ball Longitude", text: $ballLon)
                TextField("Hole Latitude", text: $holeLat)
                TextField("Hole Longitude", text: $holeLon)
                TextField("API Base URL", text: $apiBaseURL)
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Results Section
    
    private func resultsSection(response: GreenReadingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Green Read Results")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Aim Offset:")
                    Spacer()
                    Text(String(format: "%.2f feet", response.aimOffsetFeet))
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Ball Slope:")
                    Spacer()
                    Text(String(format: "%.2f%%", response.ballSlopePercent))
                }
                
                HStack {
                    Text("Hole Slope:")
                    Spacer()
                    Text(String(format: "%.2f%%", response.holeSlopePercent))
                }
                
                if let maxSlope = response.maxSlopeAlongLine {
                    HStack {
                        Text("Max Slope:")
                        Spacer()
                        Text(String(format: "%.2f%%", maxSlope))
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - Visualization Section
    
    private func visualizationSection(response: GreenReadingResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visualization")
                .font(.headline)
            
            GeometryReader { geometry in
                GreenReadingCanvas(
                    ballLat: Double(ballLat) ?? 0,
                    ballLon: Double(ballLon) ?? 0,
                    holeLat: Double(holeLat) ?? 0,
                    holeLon: Double(holeLon) ?? 0,
                    aimLine: response.aimLine,
                    fallLine: response.fallLineFromHole,
                    size: geometry.size
                )
            }
            .frame(height: 400)
            .background(Color.white)
            .border(Color.gray, width: 1)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - API Call
    
    private func fetchGreenRead() {
        isLoading = true
        errorMessage = nil
        
        guard let greenIdInt = Int(greenId),
              let ballLatDouble = Double(ballLat),
              let ballLonDouble = Double(ballLon),
              let holeLatDouble = Double(holeLat),
              let holeLonDouble = Double(holeLon) else {
            errorMessage = "Invalid input values"
            isLoading = false
            return
        }
        
        let url = URL(string: "\(apiBaseURL)/greens/\(greenIdInt)/read")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "ball_lat": ballLatDouble,
            "ball_lon": ballLonDouble,
            "hole_lat": holeLatDouble,
            "hole_lon": holeLonDouble
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    errorMessage = "No data received"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    if let errorString = String(data: data, encoding: .utf8) {
                        errorMessage = "API error (\(httpResponse.statusCode)): \(errorString)"
                    } else {
                        errorMessage = "API error: HTTP \(httpResponse.statusCode)"
                    }
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    readingResponse = try decoder.decode(GreenReadingResponse.self, from: data)
                    errorMessage = nil
                } catch {
                    errorMessage = "Decode error: \(error.localizedDescription)"
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("Response JSON: \(jsonString)")
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Response Models

struct GreenReadingResponse: Codable {
    let aimLine: [Point2D]
    let fallLineFromHole: [Point2D]?
    let aimOffsetFeet: Double
    let ballSlopePercent: Double
    let holeSlopePercent: Double
    let maxSlopeAlongLine: Double?
    let debugInfo: [String: String]?  // Simplified to String values for Codable
    
    enum CodingKeys: String, CodingKey {
        case aimLine = "aim_line"
        case fallLineFromHole = "fall_line_from_hole"
        case aimOffsetFeet = "aim_offset_feet"
        case ballSlopePercent = "ball_slope_percent"
        case holeSlopePercent = "hole_slope_percent"
        case maxSlopeAlongLine = "max_slope_along_line"
        case debugInfo = "debug_info"
    }
}

struct Point2D: Codable {
    let lat: Double
    let lon: Double
}

// MARK: - Visualization Canvas

struct GreenReadingCanvas: View {
    let ballLat: Double
    let ballLon: Double
    let holeLat: Double
    let holeLon: Double
    let aimLine: [Point2D]
    let fallLine: [Point2D]?
    let size: CGSize
    
    var body: some View {
        Canvas { context, size in
            // Normalize coordinates to view space
            let bounds = calculateBounds()
            let scale = min(size.width / bounds.width, size.height / bounds.height) * 0.9
            let offsetX = (size.width - bounds.width * scale) / 2 - bounds.minX * scale
            let offsetY = (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            
            func toView(_ lat: Double, _ lon: Double) -> CGPoint {
                let x = lon * scale + offsetX
                let y = (1.0 - lat) * scale + offsetY  // Flip Y axis
                return CGPoint(x: x, y: y)
            }
            
            // Draw fall line (if available)
            if let fallLine = fallLine, !fallLine.isEmpty {
                var path = Path()
                for (index, point) in fallLine.enumerated() {
                    let viewPoint = toView(point.lat, point.lon)
                    if index == 0 {
                        path.move(to: viewPoint)
                    } else {
                        path.addLine(to: viewPoint)
                    }
                }
                context.stroke(path, with: .color(.orange), lineWidth: 2)
            }
            
            // Draw aim line
            if !aimLine.isEmpty {
                var path = Path()
                for (index, point) in aimLine.enumerated() {
                    let viewPoint = toView(point.lat, point.lon)
                    if index == 0 {
                        path.move(to: viewPoint)
                    } else {
                        path.addLine(to: viewPoint)
                    }
                }
                context.stroke(path, with: .color(.blue), lineWidth: 3)
            }
            
            // Draw direct line (ball to hole)
            let ballPoint = toView(ballLat, ballLon)
            let holePoint = toView(holeLat, holeLon)
            var directPath = Path()
            directPath.move(to: ballPoint)
            directPath.addLine(to: holePoint)
            context.stroke(directPath, with: .color(.gray), lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [5, 5])
            
            // Draw ball position
            context.fill(
                Path(ellipseIn: CGRect(
                    x: ballPoint.x - 8,
                    y: ballPoint.y - 8,
                    width: 16,
                    height: 16
                )),
                with: .color(.white)
            )
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: ballPoint.x - 8,
                    y: ballPoint.y - 8,
                    width: 16,
                    height: 16
                )),
                with: .color(.black),
                lineWidth: 2
            )
            
            // Draw hole position
            context.fill(
                Path(ellipseIn: CGRect(
                    x: holePoint.x - 10,
                    y: holePoint.y - 10,
                    width: 20,
                    height: 20
                )),
                with: .color(.black)
            )
        }
    }
    
    private func calculateBounds() -> (minX: Double, minY: Double, width: Double, height: Double) {
        var minLat = min(ballLat, holeLat)
        var maxLat = max(ballLat, holeLat)
        var minLon = min(ballLon, holeLon)
        var maxLon = max(ballLon, holeLon)
        
        for point in aimLine {
            minLat = min(minLat, point.lat)
            maxLat = max(maxLat, point.lat)
            minLon = min(minLon, point.lon)
            maxLon = max(maxLon, point.lon)
        }
        
        if let fallLine = fallLine {
            for point in fallLine {
                minLat = min(minLat, point.lat)
                maxLat = max(maxLat, point.lat)
                minLon = min(minLon, point.lon)
                maxLon = max(maxLon, point.lon)
            }
        }
        
        // Add padding
        let latPadding = (maxLat - minLat) * 0.1
        let lonPadding = (maxLon - minLon) * 0.1
        
        return (
            minX: minLon - lonPadding,
            minY: minLat - latPadding,
            width: (maxLon - minLon) + 2 * lonPadding,
            height: (maxLat - minLat) + 2 * latPadding
        )
    }
}

// MARK: - Preview

#Preview {
    GreenReadingView()
}

