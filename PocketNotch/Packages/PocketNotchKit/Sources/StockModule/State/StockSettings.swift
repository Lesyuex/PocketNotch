import Combine
import Foundation

public struct StockPriorityTimeRange: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var startMinute: Int
    public var endMinute: Int

    public init(id: UUID = UUID(), startMinute: Int, endMinute: Int) {
        self.id = id
        self.startMinute = Self.normalized(startMinute)
        self.endMinute = Self.normalized(endMinute)
    }

    public func contains(minuteOfDay: Int) -> Bool {
        let minute = Self.normalized(minuteOfDay)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        if startMinute > endMinute {
            return minute >= startMinute || minute < endMinute
        }
        return false
    }

    private static func normalized(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }
}

@MainActor
public final class StockSettings: ObservableObject {
    private enum Keys {
        static let isPersistent = "stocks.compact.isPersistent"
        static let orderedIDs = "stocks.watchlist.order"
        static let priorityTimeRanges = "stocks.priority.timeRanges"
        static let excludesWeekends = "stocks.display.excludesWeekends"
    }

    public static let defaultOrder = [
        "600519", "002036", "688256", "000001", "000333", "000858", "300750",
        "300059", "600036", "601318", "600900", "601899", "688981"
    ]
    public static let defaultPriorityTimeRanges = [
        StockPriorityTimeRange(startMinute: 9 * 60 + 30, endMinute: 11 * 60 + 30),
        StockPriorityTimeRange(startMinute: 13 * 60, endMinute: 15 * 60)
    ]
    public static let defaultExcludesWeekends = true

    @Published public var isPersistent: Bool {
        didSet { defaults.set(isPersistent, forKey: Keys.isPersistent) }
    }

    @Published public var excludesWeekends: Bool {
        didSet { defaults.set(excludesWeekends, forKey: Keys.excludesWeekends) }
    }

    @Published public private(set) var orderedIDs: [String] {
        didSet { defaults.set(orderedIDs, forKey: Keys.orderedIDs) }
    }

    @Published public private(set) var priorityTimeRanges: [StockPriorityTimeRange] {
        didSet {
            guard let data = try? JSONEncoder().encode(priorityTimeRanges) else { return }
            defaults.set(data, forKey: Keys.priorityTimeRanges)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPersistent = defaults.object(forKey: Keys.isPersistent) as? Bool ?? false
        orderedIDs = defaults.stringArray(forKey: Keys.orderedIDs) ?? Self.defaultOrder
        excludesWeekends = defaults.object(forKey: Keys.excludesWeekends) as? Bool
            ?? Self.defaultExcludesWeekends
        priorityTimeRanges = defaults.data(forKey: Keys.priorityTimeRanges)
            .flatMap { try? JSONDecoder().decode([StockPriorityTimeRange].self, from: $0) }
            ?? Self.defaultPriorityTimeRanges
    }

    public func moveUp(id: String) {
        guard let index = orderedIDs.firstIndex(of: id), index > 0 else { return }
        orderedIDs.swapAt(index, index - 1)
    }

    public func moveDown(id: String) {
        guard let index = orderedIDs.firstIndex(of: id), index + 1 < orderedIDs.count else { return }
        orderedIDs.swapAt(index, index + 1)
    }

    public func remove(id: String) {
        orderedIDs.removeAll { $0 == id }
    }

    public func move(id: String, before targetID: String) {
        guard let fromIndex = orderedIDs.firstIndex(of: id),
              let targetIndex = orderedIDs.firstIndex(of: targetID),
              fromIndex != targetIndex else { return }
        orderedIDs.remove(at: fromIndex)
        let insertIndex = orderedIDs.firstIndex(of: targetID) ?? orderedIDs.count
        orderedIDs.insert(id, at: insertIndex)
    }

    public func addNextDefault() {
        guard let id = Self.defaultOrder.first(where: { !orderedIDs.contains($0) }) else { return }
        orderedIDs.append(id)
    }

    public func addPriorityTimeRange() {
        priorityTimeRanges.append(
            StockPriorityTimeRange(startMinute: 9 * 60 + 30, endMinute: 15 * 60)
        )
    }

    public func removePriorityTimeRange(id: UUID) {
        priorityTimeRanges.removeAll { $0.id == id }
    }

    public func updatePriorityTimeRange(id: UUID, startMinute: Int? = nil, endMinute: Int? = nil) {
        guard let index = priorityTimeRanges.firstIndex(where: { $0.id == id }) else { return }
        if let startMinute {
            priorityTimeRanges[index].startMinute = normalizedMinute(startMinute)
        }
        if let endMinute {
            priorityTimeRanges[index].endMinute = normalizedMinute(endMinute)
        }
    }

    public func isPriorityDisplayActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isPersistent else { return false }
        if excludesWeekends {
            let weekday = calendar.dateComponents([.weekday], from: date).weekday
            guard let weekday, (2...6).contains(weekday) else { return false }
        }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute else { return false }
        let minuteOfDay = hour * 60 + minute
        return priorityTimeRanges.contains { $0.contains(minuteOfDay: minuteOfDay) }
    }

    private func normalizedMinute(_ minute: Int) -> Int {
        ((minute % 1_440) + 1_440) % 1_440
    }

    public func resetToDefault() {
        isPersistent = false
        orderedIDs = Self.defaultOrder
        excludesWeekends = Self.defaultExcludesWeekends
        priorityTimeRanges = Self.defaultPriorityTimeRanges
    }

    public var usesDefaultValues: Bool {
        isPersistent == false
            && orderedIDs == Self.defaultOrder
            && excludesWeekends == Self.defaultExcludesWeekends
            && priorityTimeRanges == Self.defaultPriorityTimeRanges
    }
}
