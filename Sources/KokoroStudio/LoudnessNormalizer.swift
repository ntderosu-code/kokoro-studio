import Foundation

/// Loudness targets for export (#30). `lms` keeps the existing pipeline
/// (peak-only leveling during generation); the others add an integrated-
/// loudness gain pass at export time.
enum LoudnessPreset: String, CaseIterable, Identifiable {
    case lms, podcast, streaming, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lms: return "LMS / e-learning"
        case .podcast: return "Podcast (−16 LUFS)"
        case .streaming: return "Streaming (−14 LUFS)"
        case .custom: return "Custom"
        }
    }

    /// nil means "no LUFS pass" — the classic peak-normalized output.
    func targetLUFS(custom: Double) -> Double? {
        switch self {
        case .lms: return nil
        case .podcast: return -16
        case .streaming: return -14
        case .custom: return custom
        }
    }
}

/// Integrated loudness measurement and normalization for mono audio,
/// following ITU-R BS.1770 / EBU R128: K-weighting filter, 400 ms blocks
/// with 75% overlap, −70 LUFS absolute gate, then a −10 LU relative gate.
enum LoudnessNormalizer {
    /// Returned when the audio is silent or too short to measure.
    static let unmeasurable: Double = -100

    static func integratedLoudness(samples: [Float], sampleRate: Int) -> Double {
        let blockSize = sampleRate * 400 / 1000
        guard blockSize > 0, samples.count >= blockSize else { return unmeasurable }

        let weighted = kWeighted(samples, sampleRate: sampleRate)

        // Mean square per 400 ms block, hopping 100 ms (75% overlap).
        let hop = sampleRate / 10
        var blockMeanSquares: [Double] = []
        var start = 0
        while start + blockSize <= weighted.count {
            var sum = 0.0
            for i in start..<(start + blockSize) {
                sum += Double(weighted[i]) * Double(weighted[i])
            }
            blockMeanSquares.append(sum / Double(blockSize))
            start += hop
        }

        func loudness(_ meanSquare: Double) -> Double {
            -0.691 + 10 * log10(max(meanSquare, .leastNormalMagnitude))
        }

        // Gating keeps speech blocks and drops silence so pauses don't
        // drag the measurement down.
        let aboveAbsolute = blockMeanSquares.filter { loudness($0) > -70 }
        guard !aboveAbsolute.isEmpty else { return unmeasurable }
        let relativeThreshold = loudness(
            aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)) - 10
        let gated = blockMeanSquares.filter { loudness($0) > relativeThreshold }
        guard !gated.isEmpty else { return unmeasurable }

        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    /// Gain to bring integrated loudness to `targetLUFS`, capped so the
    /// sample peak never exceeds the app's −1 dBFS ceiling — normalization
    /// must never introduce clipping.
    static func normalize(samples: [Float], sampleRate: Int,
                          targetLUFS: Double) -> [Float] {
        let measured = integratedLoudness(samples: samples, sampleRate: sampleRate)
        guard measured > unmeasurable else { return samples }
        var gain = Float(pow(10, (targetLUFS - measured) / 20))
        if let peak = samples.map({ abs($0) }).max(), peak > 0 {
            gain = min(gain, AudioProcessing.peakTarget / peak)
        }
        return samples.map { $0 * gain }
    }

    // MARK: - K-weighting (BS.1770 reference filter, any sample rate)

    private struct Biquad {
        let b0, b1, b2, a1, a2: Double

        func apply(_ input: [Float]) -> [Float] {
            var output = [Float](repeating: 0, count: input.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in input.indices {
                let x0 = Double(input[i])
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                output[i] = Float(y0)
                x2 = x1; x1 = x0
                y2 = y1; y1 = y0
            }
            return output
        }
    }

    private static func kWeighted(_ samples: [Float],
                                  sampleRate: Int) -> [Float] {
        highPass(sampleRate: sampleRate)
            .apply(highShelf(sampleRate: sampleRate).apply(samples))
    }

    /// Stage 1: +4 dB high-shelf modeling head response. Parameters are the
    /// BS.1770 reference values; coefficients are recomputed for the actual
    /// sample rate (the spec only tabulates 48 kHz).
    private static func highShelf(sampleRate: Int) -> Biquad {
        let gainDb = 3.999843853973347
        let q = 0.7071752369554196
        let centerHz = 1681.974450955533
        let k = tan(.pi * centerHz / Double(sampleRate))
        let vh = pow(10, gainDb / 20)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return Biquad(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)
    }

    /// Stage 2: high-pass that drops inaudible rumble from the measurement.
    private static func highPass(sampleRate: Int) -> Biquad {
        let q = 0.5003270373238773
        let centerHz = 38.13547087602444
        let k = tan(.pi * centerHz / Double(sampleRate))
        let a0 = 1 + k / q + k * k
        return Biquad(
            b0: 1, b1: -2, b2: 1,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)
    }
}
