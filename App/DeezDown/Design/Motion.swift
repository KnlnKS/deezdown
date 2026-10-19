import SwiftUI

/// Critically damped by default; bounce is reserved for motion a gesture actually threw.
enum Motion {
    static let standard = Animation.smooth(duration: 0.32)
    static let quick = Animation.smooth(duration: 0.2)
    static let momentum = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

extension View {
    /// Presses read as instant because the scale lands on pointer-down, not on release.
    func pressable() -> some View {
        buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

struct HoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : Motion.quick, value: hovering)
    }
}

extension View {
    func hoverHighlight() -> some View {
        modifier(HoverHighlight())
    }
}
