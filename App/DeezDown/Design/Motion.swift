import SwiftUI

/// Critically damped by default; bounce is reserved for motion a gesture actually threw.
enum Motion {
    static let standard = Animation.smooth(duration: 0.32)
    static let quick = Animation.smooth(duration: 0.2)
    static let momentum = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension View {
    /// Presses read as instant because the scale lands on pointer-down, not on release.
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableButtonStyle(scale: scale))
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var corner: CGFloat = Metrics.cornerRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            }
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
    }
}

extension View {
    func hoverHighlight(corner: CGFloat = Metrics.cornerRadius) -> some View {
        modifier(HoverHighlight(corner: corner))
    }
}
