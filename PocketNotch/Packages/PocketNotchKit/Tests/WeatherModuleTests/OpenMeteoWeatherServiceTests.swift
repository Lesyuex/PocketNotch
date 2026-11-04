import CoreLocation
import Foundation
import XCTest
@testable import WeatherModule

final class OpenMeteoWeatherServiceTests: XCTestCase {
    func testUsesCurrentWeatherWithoutHourlyInference() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherURLProtocol.self]
        let session = URLSession(configuration: configuration)

        WeatherURLProtocol.responseData = Data(responseJSON.utf8)
        defer { WeatherURLProtocol.responseData = nil }

        let service = OpenMeteoWeatherService(session: session, directSession: session)
        let snapshot = try await service.currentWeather(
            at: CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579)
        )

        XCTAssertEqual(snapshot.temperature, 31.4)
        XCTAssertEqual(snapshot.weatherCode, 2)
        XCTAssertEqual(snapshot.conditionText, "多云")
    }

    private var responseJSON: String {
        """
        {
          "current": {
            "temperature_2m": 31.4,
            "apparent_temperature": 36.2,
            "relative_humidity_2m": 74,
            "weather_code": 2,
            "is_day": 0,
            "wind_speed_10m": 8.5,
            "wind_gusts_10m": 15.2
          },
          "daily": {
            "time": ["2026-08-15"],
            "weather_code": [95],
            "temperature_2m_max": [34.0],
            "temperature_2m_min": [27.0],
            "precipitation_probability_max": [80],
            "wind_speed_10m_max": [18.0],
            "sunrise": ["2026-08-15T05:58"],
            "sunset": ["2026-08-15T18:55"]
          }
        }
        """
    }
}

private final class WeatherURLProtocol: URLProtocol {
    static var responseData: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let data = Self.responseData,
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
