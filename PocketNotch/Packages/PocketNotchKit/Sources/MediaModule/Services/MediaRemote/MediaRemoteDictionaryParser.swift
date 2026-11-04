import Foundation

/// 将 MediaRemote 的弱类型字典转换为稳定值，集中处理键别名和时间格式差异。
enum MediaRemoteDictionaryParser {
    static func string(from dictionary: NSDictionary, keys: String...) -> String {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    static func number(from dictionary: NSDictionary, keys: String...) -> TimeInterval? {
        for key in keys {
            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = dictionary[key] as? TimeInterval {
                return value
            }
        }
        return nil
    }

    static func bool(from dictionary: NSDictionary, keys: String...) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
            if let value = dictionary[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    static func data(from dictionary: NSDictionary, keys: String...) -> Data? {
        for key in keys {
            if let value = dictionary[key] as? Data {
                return value
            }
            if let value = dictionary[key] as? NSData {
                return value as Data
            }
        }
        return nil
    }

    static func date(from dictionary: NSDictionary, keys: String...) -> Date? {
        for key in keys {
            if let value = dictionary[key] as? Date {
                return value
            }
            if let value = dictionary[key] as? NSDate {
                return value as Date
            }
            if let value = dictionary[key] as? TimeInterval {
                return Date(timeIntervalSince1970: value)
            }
            if let value = dictionary[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue)
            }
            if let value = dictionary[key] as? String,
               let date = timestampDate(from: value) {
                return date
            }
        }
        return nil
    }

    static func timestampDate(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        if let interval = TimeInterval(value) {
            return Date(timeIntervalSince1970: interval)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        if let date = formatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}
