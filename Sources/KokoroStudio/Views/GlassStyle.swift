import SwiftUI

// Liquid Glass adoption (macOS 26+) with material fallbacks for macOS 14–25.
// Glass is applied only to the floating-controls layer (action bar, player
// bar) per HIG — content surfaces and the settings form stay standard.

/// One corner radius for the floating bars and the editor card, so the
/// layered surfaces read as one design system.
enum GlassMetrics {
    static let cornerRadius: CGFloat = 14
}

extension View {
    /// Opts the editor into full inline Apple Intelligence Writing Tools
    /// where available; no-op on older systems.
    @ViewBuilder
    func editorWritingTools() -> some View {
        if #available(macOS 15.4, *) {
            self.writingToolsBehavior(.complete)
        } else {
            self
        }
    }

    /// Floating-bar chrome: Liquid Glass on macOS 26+, material card below.
    /// Controls inside these bars use plain bordered styles — glass
    /// buttons on a glass surface would layer Liquid Glass on Liquid
    /// Glass, which the HIG warns against.
    @ViewBuilder
    func barGlass(cornerRadius: CGFloat = GlassMetrics.cornerRadius) -> some View {
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

    /// Identity for glass morphing: when one bar leaves the hierarchy and
    /// another arrives inside the same BarGlassContainer, the system
    /// morphs between them instead of cross-fading. No-op before 26.
    @ViewBuilder
    func barGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
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
