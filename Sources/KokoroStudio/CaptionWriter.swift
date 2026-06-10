import Foundation

struct CaptionCue: Equatable {
    let start: Double // seconds
    let end: Double
    let text: String
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
    static func buildCues(segments: [(text: String, sampleCount: Int, pauseAfterMs: Int)],
                          sampleRate: Int) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        var cursor = 0.0
        for segment in segments {
            let duration = Double(segment.sampleCount) / Double(sampleRate)
            if duration > 0, !segment.text.isEmpty {
                cues.append(CaptionCue(start: cursor, end: cursor + duration,
                                       text: segment.text))
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
                       text: cue.text)
        }
        .filter { $0.end > $0.start }
    }

    static func vtt(_ cues: [CaptionCue]) -> String {
        var lines = ["WEBVTT", ""]
        for cue in cues {
            lines.append("\(timestamp(cue.start, fraction: ".")) --> \(timestamp(cue.end, fraction: "."))")
            lines.append(cue.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func srt(_ cues: [CaptionCue]) -> String {
        var lines: [String] = []
        for (index, cue) in cues.enumerated() {
            lines.append("\(index + 1)")
            lines.append("\(timestamp(cue.start, fraction: ",")) --> \(timestamp(cue.end, fraction: ","))")
            lines.append(cue.text)
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
