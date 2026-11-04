import Foundation

struct WeatherSnapshotCache {
    private enum Keys {
        static let snapshot = "weather.lastSuccessfulSnapshot"
    }

    private let defaults: UserDefaults
    private let maximumAge: TimeInterval

    init(
        defaults: UserDefaults = .standard,
        maximumAge: TimeInterval = 5 * 60
    ) {
        self.defaults = defaults
        self.maximumAge = maximumAge
    }

    func load(now: Date = Date()) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: Keys.snapshot),
              let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              now.timeIntervalSince(snapshot.updatedAt) <= maximumAge else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Keys.snapshot)
    }
}
