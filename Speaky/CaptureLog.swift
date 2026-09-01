import Foundation

/// Append-only trace of capture attempts.
///
/// Selection grabbing fails silently by nature — every tier just returns
/// nothing — so the only way to tell a missing selection from a wrong target
/// app from a refused copy is to record what each step actually saw.
enum CaptureLog {
    /// Off by default. Tracing every capture writes on each hotkey press and
    /// records the text length of whatever the user had selected, so it stays
    /// something the user turns on while chasing a problem.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "captureLogEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "captureLogEnabled") }
    }

    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Speaky", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("capture.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        guard isEnabled else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func session(_ title: String) {
        write("──── \(title) ────")
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
