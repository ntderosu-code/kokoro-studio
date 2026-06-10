import SwiftUI

// Liquid Glass adoption (macOS 26+) with material fallbacks for macOS 14–25.
// Glass is applied only to the floating-controls layer (action bar, player
// bar) per HIG — content surfaces and the settings form stay standard.

extension View {
    /// Frosted window backdrop: the whole window becomes translucent material
    /// so the desktop glows through — the "desk" the page card sits on.
    @ViewBuilder
    func deskBackground() -> some View {
        if #available(macOS 15.0, *) {
            self.containerBackground(.thinMaterial, for: .window)
        } else {
            self.background(Color(nsColor: .windowBackgroundColor),
                            ignoresSafeAreaEdges: .bottom)
        }
    }

    /// Floating-bar chrome: Liquid Glass on macOS 26+, material card below.
    @ViewBuilder
    func barGlass(cornerRadius: CGFloat = 14) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.bar, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.quaternary)
                )
        }
    }

    /// Primary-action button: glassProminent on 26+, borderedProminent below.
    @ViewBuilder
    func prominentActionButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary-action button: glass on 26+, bordered below.
    @ViewBuilder
    func secondaryActionButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Groups multiple glass surfaces so they share one sampling region and can
/// morph into each other; transparent passthrough on older systems.
struct BarGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
