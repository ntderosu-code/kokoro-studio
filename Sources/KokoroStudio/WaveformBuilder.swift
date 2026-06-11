import Foundation

struct HeadingMarker: Equatable {
    let time: Double
    let title: String
}

/// Player-bar waveform data (#36): bucketed peaks for drawing and heading
/// tick positions derived from the same cue table captions use.
enum WaveformBuilder {
    /// Downsamples to at most `buckets` peak values, normalized so the
    /// loudest bucket is 1.0 (quiet audio still draws visibly).
    static func peaks(samples: [Float], buckets: Int) -> [Float] {
        guard buckets > 0, !samples.isEmpty else { return [] }
        let bucketSize = max(1, samples.count / buckets)
        var result: [Float] = []
        result.reserveCapacity(buckets)
        var start = 0
        while start < samples.count, result.count < buckets {
            let end = min(start + bucketSize, samples.count)
            var peak: Float = 0
            for index in start..<end {
                peak = max(peak, abs(samples[index]))
            }
            result.append(peak)
            start = end
        }
        if let maximum = result.max(), maximum > 0 {
            result = result.map { $0 / maximum }
        }
        return result
    }

    /// Cues whose text matches a `#` heading line of the source script,
    /// compared with punctuation/case stripped — preprocessing may have
    /// altered both sides slightly.
    static func headingMarkers(cues: [CaptionCue],
                               script: String) -> [HeadingMarker] {
        let headingTexts = Set(
            script.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .map { normalized(String($0.drop { $0 == "#" })) }
                .filter { !$0.isEmpty })
        guard !headingTexts.isEmpty else { return [] }
        return cues.filter { headingTexts.contains(normalized($0.text)) }
            .map { HeadingMarker(time: $0.start, title: $0.text) }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
