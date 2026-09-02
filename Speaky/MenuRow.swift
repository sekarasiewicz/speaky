import SwiftUI

/// A row that behaves like an item in a system menu.
///
/// A window-style `MenuBarExtra` loses the automatic menu appearance, and the
/// built-in button styles all read as something else — `.link` looks like a web
/// page, `.bordered` like a form. This restores the expected behaviour: full
/// width, left aligned, and highlighted with the accent colour on hover.
struct MenuRow: View {
    let title: String
    var systemImage: String?
    var isProminent = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                }
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovering ? AnyShapeStyle(.white) : AnyShapeStyle(isProminent ? .primary : .secondary))
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovering ? Color.accentColor : .clear)
        )
        .onHover { isHovering = $0 }
    }
}
