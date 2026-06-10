import Foundation

/// Post-processing applied to generated audio before preview/export:
/// silence trim, loudness normalization, and click-removing micro fades.
enum AudioProcessing {
    /// Peak target: -1 dBFS.
    static let peakTarget: Float = 0.891

    static func finalize(samples: [Float], sampleRate: Int) -> [Float] {
        var result = trimSilence(samples, sampleRate: sampleRate)
        result = normalizePeak(result)
        result = applyFades(result, sampleRate: sampleRate)
        return result
    }

    /// Removes leading/trailing audio below -60 dBFS, keeping a 60ms pad.
    static func trimSilence(_ samples: [Float], sampleRate: Int) -> [Float] {
        let threshold: Float = 0.001
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold }) else {
            return samples // all silence; leave untouched
        }
        let pad = sampleRate * 60 / 1000
        let start = max(0, first - pad)
        let end = min(samples.count, last + pad + 1)
        return Array(samples[start..<end])
    }

    /// Scales so the loudest sample sits at -1 dBFS.
    static func normalizePeak(_ samples: [Float]) -> [Float] {
        guard let peak = samples.map({ abs($0) }).max(), peak > 0 else {
            return samples
        }
        let gain = peakTarget / peak
        return samples.map { $0 * gain }
    }

    /// 10ms linear fade in/out to avoid clicks at clip boundaries.
    static func applyFades(_ samples: [Float], sampleRate: Int) -> [Float] {
        let fadeLength = min(sampleRate * 10 / 1000, samples.count / 2)
        guard fadeLength > 0 else { return samples }
        var result = samples
        for i in 0..<fadeLength {
            let ramp = Float(i) / Float(fadeLength)
            result[i] *= ramp
            result[result.count - 1 - i] *= ramp
        }
        return result
    }
}
