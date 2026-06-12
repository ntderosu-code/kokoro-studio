import Foundation

struct CaptionCue: Equatable {
    let start: Double // seconds
    let end: Double
    let text: String
    /// Effective `@Speaker:` name, without the "@"; nil for untagged text.
    let speaker: String?

    init(start: Double, end: Double, text: String, speaker: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
    }
}

enum CaptionFormat: String, CaseIterable, Identifiable {
    case off, vtt, srt
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .vtt: return "VTT"
        case .srt: return "SRT"
        }
    }
    var fileExtension: String { rawValue }
}

enum CaptionWriter {
    /// Builds cue timings from per-segment synthesis results. Timing comes
    /// from actual sample counts, so cues stay exact regardless of voice or
    /// speed. Spliced pauses count toward the timeline but not cue duration.
    static func buildCues(segments: [(text: String, sampleCount: Int,
                                      pauseAfterMs: Int, speaker: String?)],
                          sampleRate: Int) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        var cursor = 0.0
        for segment in segments {
            let duration = Double(segment.sampleCount) / Double(sampleRate)
            if duration > 0, !segment.text.isEmpty {
                cues.append(CaptionCue(start: cursor, end: cursor + duration,
                                       text: segment.text,
                                       speaker: segment.speaker))
            }
            cursor += duration + Double(segment.pauseAfterMs) / 1000.0
        }
        return cues
    }

    /// Shifts all cues earlier by `offset` seconds (e.g. after leading-silence
    /// trim) and clamps the last cue to `totalDuration`.
    static func adjust(_ cues: [CaptionCue], offset: Double,
                       totalDuration: Double) -> [CaptionCue] {
        cues.map { cue in
            CaptionCue(start: max(0, cue.start - offset),
                       end: min(totalDuration, max(0, cue.end - offset)),
                       text: cue.text, speaker: cue.speaker)
        }
        .filter { $0.end > $0.start }
    }

    /// Caption text with a "Name: " prefix only on the cue where the speaker
    /// changes; runs of the same speaker (and untagged cues) stay bare.
    private static func labeledTexts(_ cues: [CaptionCue]) -> [String] {
        var previousSpeaker: String?
        return cues.map { cue in
            defer { if cue.speaker != nil { previousSpeaker = cue.speaker } }
            if let speaker = cue.speaker, speaker != previousSpeaker {
                return "\(speaker): \(cue.text)"
            }
            return cue.text
        }
    }

    static func vtt(_ cues: [CaptionCue]) -> String {
        var lines = ["WEBVTT", ""]
        for (cue, text) in zip(cues, labeledTexts(cues)) {
            lines.append("\(timestamp(cue.start, fraction: ".")) --> \(timestamp(cue.end, fraction: "."))")
            lines.append(text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func srt(_ cues: [CaptionCue]) -> String {
        var lines: [String] = []
        for (index, (cue, text)) in zip(cues, labeledTexts(cues)).enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(timestamp(cue.start, fraction: ",")) --> \(timestamp(cue.end, fraction: ","))")
            lines.append(text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func timestamp(_ seconds: Double, fraction separator: String) -> String {
        let totalMilliseconds = Int((seconds * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let secs = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d%@%03d",
                      hours, minutes, secs, separator, milliseconds)
    }
}
