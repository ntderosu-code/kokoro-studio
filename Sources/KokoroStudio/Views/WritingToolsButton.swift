import SwiftUI
import AppKit

enum EditorTextAccess {
    /// The editor's backing NSTextView in the given window, made first
    /// responder so text commands land on it.
    @discardableResult
    static func focusTextView(in window: NSWindow?) -> NSTextView? {
        guard let window else { return nil }
        if let textView = window.firstResponder as? NSTextView { return textView }
        guard let contentView = window.contentView,
              let textView = find(in: contentView) else { return nil }
        window.makeFirstResponder(textView)
        return textView
    }

    private static func find(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews {
            if let found = find(in: subview) { return found }
        }
        return nil
    }
}

/// A real NSButton so the Writing Tools popover anchors to the toolbar
/// button (AppKit anchors to the sender view) instead of the text caret.
struct WritingToolsToolbarButton: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "wand.and.sparkles",
                            accessibilityDescription: "Writing Tools")!
        let button = NSButton(image: image, target: context.coordinator,
                              action: #selector(Coordinator.showWritingTools(_:)))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.toolTip = "Proofread or rewrite the selection with Apple Intelligence"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        @objc func showWritingTools(_ sender: NSButton) {
            guard let textView = EditorTextAccess.focusTextView(in: sender.window)
            else { return }
            textView.perform(Selector(("showWritingTools:")), with: sender)
        }
    }
}
