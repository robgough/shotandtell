import os

/// Log categories, one per subsystem of the app. `Log.capture.debug(…)` shows up
/// in Console.app filtered by subsystem `net.robgough.ShotAndTell`.
enum Log {
    private static let subsystem = "net.robgough.ShotAndTell"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
