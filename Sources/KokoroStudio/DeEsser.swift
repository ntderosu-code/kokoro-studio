import Foundation

/// Tames harsh "s" sounds by compressing just the sibilance band
/// (above ~5 kHz) when it spikes, leaving the rest of the signal alone.
/// Pure DSP on mono float samples; no engine or UI dependencies.
enum DeEsser {
    /// Split the signal at `crossoverHz`, follow the high band's envelope,
    /// and apply soft-knee compression to that band only. The threshold is
    /// relative to the clip's peak so the result is level-independent.
    static func process(_ samples: [Float], sampleRate: Int,
                        crossoverHz: Float = 5_000,
                        thresholdOfPeak: Float = 0.12,
                        ratio: Float = 3,
                        maxReductionDB: Float = 10) -> [Float] {
        guard samples.count > 1, sampleRate > 0 else { return samples }
        let peak = samples.lazy.map(abs).max() ?? 0
        guard peak > 0 else { return samples }
        let threshold = thresholdOfPeak * peak

        // One-pole crossover: low band from the filter, high band = remainder.
        let lowpassCoefficient = exp(-2 * Float.pi * crossoverHz / Float(sampleRate))
        // Envelope follower: fast attack so short "s" bursts are caught,
        // slower release so the gain doesn't flutter.
        let attackCoefficient = exp(-1 / (Float(sampleRate) * 0.001))
        let releaseCoefficient = exp(-1 / (Float(sampleRate) * 0.06))
        let minimumGain = pow(10, -maxReductionDB / 20)

        var output = [Float](repeating: 0, count: samples.count)
        // Two cascaded one-pole stages (12 dB/oct) so the sibilance band
        // separates cleanly instead of leaking into the untouched low band.
        var lowStage1: Float = samples[0]
        var low: Float = samples[0]
        var envelope: Float = 0
        for index in samples.indices {
            let sample = samples[index]
            lowStage1 = lowpassCoefficient * lowStage1 + (1 - lowpassCoefficient) * sample
            low = lowpassCoefficient * low + (1 - lowpassCoefficient) * lowStage1
            let high = sample - low

            let magnitude = abs(high)
            let coefficient = magnitude > envelope ? attackCoefficient
                                                   : releaseCoefficient
            envelope = coefficient * envelope + (1 - coefficient) * magnitude

            var gain: Float = 1
            if envelope > threshold {
                // Soft compression: output level rises 1/ratio dB per dB
                // above the threshold.
                let compressed = threshold * pow(envelope / threshold, 1 / ratio)
                gain = max(compressed / envelope, minimumGain)
            }
            output[index] = low + high * gain
        }
        return output
    }
}
