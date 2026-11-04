import Foundation

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let temperature: Double
    public let apparentTemperature: Double
    public let humidity: Int?
    public let weatherCode: Int
    public let isDay: Bool
    public let windSpeed: Double?
    public let windGust: Double?
    public let forecast: [WeatherForecastDay]
    public let updatedAt: Date

    public init(
        temperature: Double,
        apparentTemperature: Double,
        humidity: Int? = nil,
        weatherCode: Int,
        isDay: Bool,
        windSpeed: Double? = nil,
        windGust: Double? = nil,
        forecast: [WeatherForecastDay] = [],
        updatedAt: Date = Date()
    ) {
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.weatherCode = weatherCode
        self.isDay = isDay
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.forecast = forecast
        self.updatedAt = updatedAt
    }

    public var roundedTemperatureText: String {
        "\(Int(temperature.rounded()))°"
    }

    public var conditionText: String {
        WeatherPresentation.conditionText(for: weatherCode)
    }

    public var symbolName: String {
        WeatherPresentation.symbolName(for: weatherCode, isDay: isDay)
    }
}

public struct WeatherForecastDay: Codable, Equatable, Sendable {
    public let date: String
    public let highTemperature: Double
    public let lowTemperature: Double
    public let weatherCode: Int
    public let precipitationProbability: Int?
    public let maximumWindSpeed: Double?
    public let sunriseTime: String?
    public let sunsetTime: String?

    public init(
        date: String,
        highTemperature: Double,
        lowTemperature: Double,
        weatherCode: Int,
        precipitationProbability: Int? = nil,
        maximumWindSpeed: Double? = nil,
        sunriseTime: String? = nil,
        sunsetTime: String? = nil
    ) {
        self.date = date
        self.highTemperature = highTemperature
        self.lowTemperature = lowTemperature
        self.weatherCode = weatherCode
        self.precipitationProbability = precipitationProbability
        self.maximumWindSpeed = maximumWindSpeed
        self.sunriseTime = sunriseTime
        self.sunsetTime = sunsetTime
    }

    public var temperatureRangeText: String {
        "\(Int(highTemperature.rounded()))° / \(Int(lowTemperature.rounded()))°"
    }

    public var shortDateText: String {
        let components = date.split(separator: "-")
        guard components.count == 3,
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return date
        }
        return "\(month)月\(day)日"
    }

    public var weekdayText: String {
        let components = date.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return date
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let parsedDate = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return date
        }

        let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return weekdays[calendar.component(.weekday, from: parsedDate) - 1]
    }

    public var dateAndWeekdayText: String {
        let components = date.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return date
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let parsedDate = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return date
        }

        let style = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .weekday(.abbreviated)
            .locale(.current)
        return parsedDate.formatted(style)
    }

    public var highTemperatureText: String {
        "\(Int(highTemperature.rounded()))°"
    }

    public var lowTemperatureText: String {
        "\(Int(lowTemperature.rounded()))°"
    }

    public var precipitationProbabilityText: String {
        precipitationProbability.map { "\($0)%" } ?? "--"
    }

    public var maximumWindSpeedText: String {
        maximumWindSpeed.map { "\(Int($0.rounded()))" } ?? "--"
    }

    public var conditionText: String {
        WeatherPresentation.conditionText(for: weatherCode)
    }

    public var symbolName: String {
        WeatherPresentation.symbolName(for: weatherCode, isDay: true)
    }
}

private enum WeatherPresentation {
    static func conditionText(for weatherCode: Int) -> String {
        switch weatherCode {
        case 0: "晴"
        case 1: "大致晴朗"
        case 2: "多云"
        case 3: "阴"
        case 45, 48: "有雾"
        case 51, 53, 55, 56, 57: "毛毛雨"
        case 61, 63, 65, 66, 67: "有雨"
        case 71, 73, 75, 77: "有雪"
        case 80, 81, 82: "阵雨"
        case 85, 86: "阵雪"
        case 95, 96, 99: "雷雨"
        default: "天气"
        }
    }

    static func symbolName(for weatherCode: Int, isDay: Bool) -> String {
        switch weatherCode {
        case 0:
            isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            "cloud.fill"
        case 45, 48:
            "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82:
            "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            "cloud.snow.fill"
        case 95, 96, 99:
            "cloud.bolt.rain.fill"
        default:
            "cloud.fill"
        }
    }
}
