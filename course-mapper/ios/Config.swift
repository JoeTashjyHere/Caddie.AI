//
//  Config.swift
//  Caddie.AI iOS Client
//
//  Configuration for development and production
//

import Foundation

struct Config {
    /// Use mock data instead of calling real API (for previews/testing)
    static let useMockData = false
    
    /// Base URL for the course-mapper API
    static let baseURL = "http://localhost:8081"
    
    /// Network timeout in seconds
    static let networkTimeout: TimeInterval = 30.0
}



