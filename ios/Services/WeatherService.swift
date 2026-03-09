//
//  WeatherService.swift
//  Caddie.ai
//

import Foundation
import CoreLocation

enum EnvironmentalDataSource: String, Codable {
    case liveAPI
    case fallbackStub
    case unavailable
}

struct WeatherSnapshot {
    var windMph: Double
    var windDirDeg: Double
    var tempF: Double
    var source: EnvironmentalDataSource = .unavailable
}

class WeatherService {
    static let shared = WeatherService()
    
    private init() {}
    
    func fetchWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&current=temperature_2m,wind_speed_10m,wind_direction_10m&temperature_unit=fahrenheit&wind_speed_unit=mph"

        guard let url = URL(string: urlString) else {
            return fallbackSnapshot()
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return fallbackSnapshot()
            }

            let decoded = try JSONDecoder().decode(OpenMeteoWeatherResponse.self, from: data)
            if let current = decoded.current {
                return WeatherSnapshot(
                    windMph: current.windSpeed10m ?? 0,
                    windDirDeg: current.windDirection10m ?? 0,
                    tempF: current.temperature2m ?? 70,
                    source: .liveAPI
                )
            }
        } catch {
            DebugLogging.log("Weather API fetch failed, using fallback: \(error.localizedDescription)", category: "Environment")
        }

        return fallbackSnapshot()
    }

    private func fallbackSnapshot() -> WeatherSnapshot {
        WeatherSnapshot(
            windMph: 0,
            windDirDeg: 0,
            tempF: 70,
            source: .fallbackStub
        )
    }
}

private struct OpenMeteoWeatherResponse: Codable {
    let current: OpenMeteoCurrentWeather?
}

private struct OpenMeteoCurrentWeather: Codable {
    let temperature2m: Double?
    let windSpeed10m: Double?
    let windDirection10m: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case windSpeed10m = "wind_speed_10m"
        case windDirection10m = "wind_direction_10m"
    }
}
