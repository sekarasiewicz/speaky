import AppKit

/// Other copies of Speaky running from a different bundle.
///
/// Two copies can now coexist — a debug build and the one in /Applications —
/// because terminating anything sharing the bundle identifier meant each
/// launch quietly killed the other. The cost is that only one of them wins the
/// global hotkeys, and the loser looks broken rather than displaced. Surfacing
/// the other copy turns that into something a user can see and act on.
enum RunningInstances {
    static func others() -> [URL] {
        let ownPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).compactMap { app -> URL? in
            guard app.processIdentifier != ownPID, let url = app.bundleURL else { return nil }
            return url.resolvingSymlinksInPath().path == ownPath ? nil : url
        }
    }
}
