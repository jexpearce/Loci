import XCTest
import CoreLocation
@testable import Loci

/// Mock geocoder that returns controlled placemarks
class MockGeocoder: GeocodingProtocol {
    var placemarksToReturn: [CLPlacemark] = []
    func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        return placemarksToReturn
    }
}

/// Failing mock that always throws
class FailingGeocoder: GeocodingProtocol {
    func reverseGeocode(_ location: CLLocation) async throws -> [CLPlacemark] {
        throw NSError(domain: "Test", code: -1, userInfo: nil)
    }
}

final class GeocodingServiceTests: XCTestCase {
    func testReturnsNilWhenNoPlacemark() async {
        let mock = MockGeocoder()
        mock.placemarksToReturn = []
        let service = GeocodingService(geocoder: mock)

        let result = await service.reverseGeocode(
            CLLocation(latitude: 0, longitude: 0)
        )
        XCTAssertNil(result)
    }

    func testHandlesErrorGracefully() async {
        let service = GeocodingService(geocoder: FailingGeocoder())
        let result = await service.reverseGeocode(
            CLLocation(latitude: 0, longitude: 0)
        )
        XCTAssertNil(result)
    }
}
