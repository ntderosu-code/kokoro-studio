import Foundation

/// Estimates how long the generated audio will run: spliced pauses are exact
/// (computed from the same segmentation used for synthesis); speech time uses
/// a words-per-second rate calibrated from previous generations.
enum DurationEstimator {
    /// Reasonable narration default (~170 wpm) until first calibration.
    static let defaultWordsPerSecond = 2.8

    static func wordCount(of text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func estimate(script: String, pauses: PauseSettings,
                         wordsPerSecond: Double, speed: Double) -> TimeInterval {
        let words = wordCount(of: script)
        guard words > 0 else { return 0 }
        let segments = ScriptSegmenter.segment(script, pauses: pauses)
        let pauseSeconds = segments.reduce(0.0) { $0 + Double($1.pauseAfterMs) / 1000 }
        let speechSeconds = Double(words) / (max(wordsPerSecond, 0.5) * max(speed, 0.1))
        return speechSeconds + pauseSeconds
    }

    /// Updates the calibrated rate from a finished generation. Returns the
    /// smoothed words-per-second at speed 1.0, or nil if the sample is junk.
    static func calibrate(previousRate: Double, words: Int,
                          audioSeconds: Double, pauseSeconds: Double,
                          speed: Double) -> Double? {
        let speechSeconds = audioSeconds - pauseSeconds
        guard words >= 5, speechSeconds > 1 else { return nil }
        let measured = Double(words) / speechSeconds / max(speed, 0.1)
        guard (0.8...8).contains(measured) else { return nil }
        // Exponential smoothing: stable but adapts within a few runs.
        return previousRate * 0.5 + measured * 0.5
    }

    /// "0:45", "3:20", "1:02:10"
    static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600,
                          total / 60 % 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
