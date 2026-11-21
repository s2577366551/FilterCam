import OSLog

enum Log {
    static let camera = Logger(subsystem: "com.filtercam.app", category: "camera")
    static let filter = Logger(subsystem: "com.filtercam.app", category: "filter")
    static let ui = Logger(subsystem: "com.filtercam.app", category: "ui")
}
