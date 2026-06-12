import AppKit
import SwiftUI

/// Per-paragraph speaker icons drawn in a strip to the left of the editor,
/// aligned to the text via the layout manager. Click opens the picker.
@MainActor
final class SpeakerGutterView: NSView {
    var onClickParagraph: ((Int) -> Void)?

    private weak var textView: NSTextView?
    private var iconRects: [(paragraphIndex: Int, rect: NSRect)] = []
    private var styles: [(color: NSColor, symbol: String)] = []

    override var isFlipped: Bool { true }

    func configure(textView: NSTextView) {
        self.textView = textView
    }

    /// Recompute icon positions from the current layout.
    func refresh(script: String,
                 colorOverrides: [String: Int],
                 symbolOverrides: [String: Int]) {
        guard let textView, let lm = textView.layoutManager,
              let container = textView.textContainer else { return }
        iconRects.removeAll()
        styles.removeAll()
        let textLength = (textView.string as NSString).length
        let spans = ParagraphSpeakers.resolve(script: script)
        for (index, span) in spans.enumerated() {
            guard span.range.location < textLength else { continue }
            let glyphRange = lm.glyphRange(
                forCharacterRange: NSRange(location: span.range.location, length: 1),
                actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            // Convert from text view coords to this gutter's coords.
            let inGutter = convert(rect, from: textView)
            let iconRect = NSRect(x: 7, y: inGutter.minY + 1, width: 20, height: 20)
            iconRects.append((index, iconRect))
            let style = SpeakerIdentity.style(for: span.speaker,
                                              colorOverrides: colorOverrides,
                                              symbolOverrides: symbolOverrides)
            styles.append((SpeakerIdentity.displayColor(colorIndex: style.colorIndex),
                           SpeakerIdentity.displaySymbol(symbolIndex: style.symbolIndex)))
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (offset, entry) in iconRects.enumerated() {
            let (color, symbolName) = styles[offset]
            let path = NSBezierPath(roundedRect: entry.rect, xRadius: 6, yRadius: 6)
            color.withAlphaComponent(0.9).setFill()
            path.fill()
            if let image = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: nil) {
                let symbolColor = SpeakerIdentity.iconForeground(on: color)
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                    .applying(.init(paletteColors: [symbolColor]))
                let tinted = image.withSymbolConfiguration(cfg)
                tinted?.draw(in: entry.rect.insetBy(dx: 4, dy: 4))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = iconRects.first(where: { $0.rect.contains(point) }) {
            onClickParagraph?(hit.paragraphIndex)
        }
    }
}

/// Hosts `SpeakerGutterView` in SwiftUI, finds the editor's text view, and
/// re-syncs icon positions on script edits and scrolling.
struct SpeakerGutterHost: NSViewRepresentable {
    let script: String
    let colorOverrides: [String: Int]
    let symbolOverrides: [String: Int]
    let paragraphTapped: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SpeakerGutterView {
        SpeakerGutterView()
    }

    func updateNSView(_ view: SpeakerGutterView, context: Context) {
        view.onClickParagraph = paragraphTapped
        let script = script
        let colors = colorOverrides
        let symbols = symbolOverrides
        context.coordinator.refresh = { [weak view] in
            guard let view else { return }
            view.refresh(script: script, colorOverrides: colors,
                         symbolOverrides: symbols)
        }
        // Defer so the text view exists and layout is current.
        DispatchQueue.main.async {
            context.coordinator.attach(gutter: view)
            context.coordinator.refresh()
        }
    }

    @MainActor
    final class Coordinator {
        var refresh: () -> Void = {}
        private var scrollObserver: NSObjectProtocol?
        private weak var attachedTextView: NSTextView?

        func attach(gutter: SpeakerGutterView) {
            guard let textView = EditorTextAccess.findTextView(in: gutter.window)
            else { return }
            guard attachedTextView !== textView else { return }
            attachedTextView = textView
            gutter.configure(textView: textView)
            guard let clipView = textView.enclosingScrollView?.contentView
            else { return }
            clipView.postsBoundsChangedNotifications = true
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }
    }
}
