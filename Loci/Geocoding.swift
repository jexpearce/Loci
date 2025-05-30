// === File: GeocodingService.swift
// Path: Loci/Services/GeocodingService.swift

import Foundation
import CoreLocation

/// Protocol to allow mocking CLGeocoder in tests
protocol GeocodingProtocol {
    func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark]
}

extension CLGeocoder: GeocodingProtocol {
    func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await reverseGeocodeLocation(location)
    }
}

/// Service to perform reverse-geocoding with async/await
final class GeocodingService {
    static let shared = GeocodingService()
    private let geocoder: GeocodingProtocol

    /// Injectable for unit tests
    init(geocoder: GeocodingProtocol = CLGeocoder()) {
        self.geocoder = geocoder
    }

    /// Returns the name of the first placemark or nil on error
    func reverseGeocode(_ location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocode(location)
            return placemarks.first?.name
        } catch {
            print("[GeocodingService] error: \(error)")
            return nil
        }
    }
}


