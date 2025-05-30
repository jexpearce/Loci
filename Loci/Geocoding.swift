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


// === Diff: SessionManager.swift
// Path: Loci/Services/SessionManager.swift

@@ private func performLocationUpdate() {
-        // Reverse geocode to get building
-        locationManager.reverseGeocode(location: location) { [weak self] building in
-            guard let self = self else { return }
+        // Async reverse-geocode via GeocodingService
+        Task { [weak self] in
+            guard let self = self else { return }
+            let clLocation = CLLocation(latitude: location.coordinate.latitude,
+                                        longitude: location.coordinate.longitude)
+            let building = await GeocodingService.shared.reverseGeocode(clLocation)

-            // Get current Spotify track
-            self.spotifyManager.getCurrentTrack { track in
+            // Get current Spotify track
+            self.spotifyManager.getCurrentTrack { track in
@@
-                // End background task
-                self.endBackgroundTask()
+                // defer in wrapper will end the BG task automatically
             }
-        }
+        }
@@
