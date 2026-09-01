import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a combination. Escape cancels, Delete clears.
struct KeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { combo = $0 }
        view.combo = combo
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.combo = combo
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var combo: KeyCombo = .empty
        var onChange: ((KeyCombo) -> Void)?
        private var recording = false

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording = true
            needsDisplay = true
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            needsDisplay = true
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }

            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return
            }
            if event.keyCode == UInt16(kVK_Delete) {
                combo = .empty
                onChange?(combo)
                stopRecording()
                return
            }
            guard let new = KeyCombo(event: event) else {
                NSSound.beep()   // modifier-less keys are rejected
                return
            }
            combo = new
            onChange?(new)
            stopRecording()
        }

        private func stopRecording() {
            recording = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()

            let text = recording ? "Naciśnij…" : combo.display
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
                withAttributes: attributes
            )
        }
    }
}
