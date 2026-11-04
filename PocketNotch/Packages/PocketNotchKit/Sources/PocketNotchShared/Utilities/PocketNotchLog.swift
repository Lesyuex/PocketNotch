import OSLog

public enum PocketNotchLog {
    public static let core = Logger(subsystem: "com.pocketnotch.app", category: "core")
    public static let media = Logger(subsystem: "com.pocketnotch.app", category: "media")
    public static let shelf = Logger(subsystem: "com.pocketnotch.app", category: "shelf")
    public static let system = Logger(subsystem: "com.pocketnotch.app", category: "system")
}
