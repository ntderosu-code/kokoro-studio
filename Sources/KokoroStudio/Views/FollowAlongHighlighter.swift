import SwiftUI
import AppKit

/// Highlights the sentence being spoken in the editor and maps clicks
/// back to cue times (#35). Uses layout-manager temporary attributes so
/// the highlight never touches the script text or undo stack.
@MainActor
final class FollowAlongHighlighter: ObservableObject {
    private var cues: [CaptionCue] = []
    private var alignedRanges: [NSRange?] = []
    private var activeIndex: Int?
    private weak var textView: NSTextView?

    var isReady: Bool { !cues.isEmpty }

    /// Builds the cue->editor mapping. Bails for previews (cues map to the
    /// selection, not the document) and stale audio (script edited since
    /// generation) — a mis-aligned highlight is worse than none.
    func prepare(audio: AppState.GeneratedAudio?, script: String) {
        clearHighlight()
        cues = []
        alignedRanges = []
        activeIndex = nil
        guard let audio, !audio.isPreview, audio.sourceScript == script else {
            return
        }
        cues = audio.cues
        alignedRanges = CueAlignment.align(cues: cues.map(\.text), script: script)
        textView = EditorTextAccess.findTextView(in: NSApp.keyWindow)
    }

    func update(time: Double) {
        guard isReady else { return }
        let index = CueAlignment.cueIndex(at: time, cues: cues)
        guard index != activeIndex else { return }
        clearHighlight()
        activeIndex = index
        guard let index, let range = alignedRanges[index],
              let textView, let layoutManager = textView.layoutManager,
              NSMaxRange(range) <= (textView.string as NSString).length else {
            return
        }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor.findHighlightColor.withAlphaComponent(0.45),
            forCharacterRange: range)
        textView.scrollRangeToVisible(range)
    }

    func clearHighlight() {
        guard let textView, let layoutManager = textView.layoutManager else {
            return
        }
        let fullRange = NSRange(location: 0,
                                length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor,
                                               forCharacterRange: fullRange)
        activeIndex = nil
    }

    /// Cue start time for a click at a character location, if it lands
    /// inside an aligned sentence.
    func seekTarget(forCharacterAt location: Int) -> Double? {
        for (index, range) in alignedRanges.enumerated() {
            if let range, NSLocationInRange(location, range) {
                return cues[index].start
            }
        }
        return nil
    }
}
