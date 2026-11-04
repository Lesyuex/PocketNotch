import CFNetwork
import CoreLocation
import Foundation

protocol WeatherProviding: Sendable {
    func currentWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot
}

struct OpenMeteoWeatherService: WeatherProviding {
    private let session: URLSession
    private let directSession: URLSession

    init(
        session: URLSession = .shared,
        directSession: URLSession? = nil
    ) {
        self.session = session
        self.directSession = directSession ?? Self.makeDirectSession()
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let apparentTemperature: Double
            let relativeHumidity2m: Int
            let weatherCode: Int
            let isDay: Int
            let windSpeed10m: Double?
            let windGusts10m: Double?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case relativeHumidity2m = "relative_humidity_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
                case windSpeed10m = "wind_speed_10m"
                case windGusts10m = "wind_gusts_10m"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int]
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]
            let precipitationProbabilityMax: [Int]
            let windSpeed10mMax: [Double]
            let sunrise: [String]
            let sunset: [String]

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
                case windSpeed10mMax = "wind_speed_10m_max"
                case sunrise
                case sunset
            }
        }

        let current: Current
        let daily: Daily
    }

    func currentWeather(at coordinate: CLLocationCoordinate2D) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m,wind_gusts_10m"
            ),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise,sunset"
            ),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        do {
            return try await weatherSnapshot(from: url, using: session)
        } catch {
            guard !Task.isCancelled,
                  (error as? URLError)?.code != .cancelled else {
                throw CancellationError()
            }
            return try await weatherSnapshot(from: url, using: directSession)
        }
    }

    private func weatherSnapshot(
        from url: URL,
        using session: URLSession
    ) async throws -> WeatherSnapshot {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let current = decoded.current
        return WeatherSnapshot(
            temperature: current.temperature2m,
            apparentTemperature: current.apparentTemperature,
            humidity: current.relativeHumidity2m,
            weatherCode: current.weatherCode,
            isDay: current.isDay == 1,
            windSpeed: current.windSpeed10m,
            windGust: current.windGusts10m,
            forecast: forecastDays(from: decoded.daily)
        )
    }

    private static func makeDirectSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
            kCFNetworkProxiesSOCKSEnable as String: false,
            kCFNetworkProxiesProxyAutoConfigEnable as String: false,
            kCFNetworkProxiesProxyAutoDiscoveryEnable as String: false,
            kCFNetworkProxiesExceptionsList as String: ["*"],
        ]
        return URLSession(configuration: configuration)
    }

    private func forecastDays(from daily: Response.Daily) -> [WeatherForecastDay] {
        let count = min(
            daily.time.count,
            daily.weatherCode.count,
            daily.temperature2mMax.count,
            daily.temperature2mMin.count,
            daily.precipitationProbabilityMax.count,
            daily.windSpeed10mMax.count,
            daily.sunrise.count,
            daily.sunset.count
        )
        guard count > 0 else { return [] }

        return (0..<min(count, 3)).map { index in
            WeatherForecastDay(
                date: daily.time[index],
                highTemperature: daily.temperature2mMax[index],
                lowTemperature: daily.temperature2mMin[index],
                weatherCode: daily.weatherCode[index],
                precipitationProbability: daily.precipitationProbabilityMax[index],
                maximumWindSpeed: daily.windSpeed10mMax[index],
                sunriseTime: clockTime(from: daily.sunrise[index]),
                sunsetTime: clockTime(from: daily.sunset[index])
            )
        }
    }

    private func clockTime(from localDateTime: String) -> String {
        guard let time = localDateTime.split(separator: "T", maxSplits: 1).last,
              time.count >= 5 else {
            return localDateTime
        }
        return String(time.prefix(5))
    }
}
