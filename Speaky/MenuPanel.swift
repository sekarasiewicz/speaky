import SwiftUI

/// The menu bar panel: transport controls and a seekable progress bar.
///
/// A plain menu could only ever list actions, so position was a line of text and
/// seeking meant pressing a skip shortcut repeatedly. A window-style panel can
/// show where you are and let you drag to somewhere else.
struct MenuPanel: View {
    @EnvironmentObject private var controller: SpeakyController
    @Environment(\.openSettings) private var openSettings

    /// While the user drags, the slider owns the position. Without this the
    /// 4 Hz ticker would keep writing playback position into the same binding
    /// and the knob would fight the finger.
    @State private var scrubbing = false
    @State private var scrubPosition: TimeInterval = 0

    private var skip: Int { Int(AppSettings.shared.skipSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                if controller.state.isActive { transport }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, controller.state.isActive ? 12 : 8)

            // Rows run edge to edge like a system menu, so they sit outside the
            // padded block above and carry their own inset.
            VStack(alignment: .leading, spacing: 0) {
                MenuRow(title: "Read selection", systemImage: "text.viewfinder", isProminent: true) {
                    controller.readSelection()
                }
                MenuRow(title: "Read clipboard", systemImage: "clipboard", isProminent: true) {
                    controller.speakClipboard()
                }

                Divider().padding(.vertical, 5)

                MenuRow(title: "Settings…", systemImage: "gearshape") {
                    SettingsWindow.open(openSettings)
                }
                MenuRow(title: "Quit", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 6)
        }
        .frame(width: 280)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Label(statusText, systemImage: statusIcon)
                .font(.headline)
                .foregroundStyle(statusColor)
            Spacer()
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubPosition : controller.position },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(controller.duration, 0.1),
                onEditingChanged: { editing in
                    if editing {
                        scrubPosition = controller.position
                        scrubbing = true
                    } else {
                        controller.seek(to: scrubPosition)
                        scrubbing = false
                    }
                }
            )

            HStack {
                Text(timecode(scrubbing ? scrubPosition : controller.position))
                Spacer()
                // Projected from the character count until the last chunk
                // arrives, and marked as such: the true length is not knowable
                // until the text has actually been spoken.
                Text(controller.durationIsEstimate
                     ? "~\(timecode(controller.duration))"
                     : timecode(controller.duration))
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button { controller.skip(backwards: true) } label: {
                    Label("\(skip)s", systemImage: "gobackward")
                }
                Button { controller.togglePause() } label: {
                    Image(systemName: controller.state == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 24)
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { controller.skip(backwards: false) } label: {
                    Label("\(skip)s", systemImage: "goforward")
                }
                Spacer()
                Button("Stop") { controller.stop() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusText: String {
        switch controller.state {
        case .idle:               return "Speaky"
        case .working:            return "Reading"
        case .paused:             return "Paused"
        case .error(let message): return message
        }
    }

    private var statusIcon: String {
        switch controller.state {
        case .idle:    return "waveform"
        case .working: return "waveform.circle.fill"
        case .paused:  return "pause.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        if case .error = controller.state { return .orange }
        return .primary
    }

    private func timecode(_ time: TimeInterval) -> String {
        let seconds = Int(time.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
