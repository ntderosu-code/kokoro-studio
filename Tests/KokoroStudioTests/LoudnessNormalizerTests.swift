import XCTest
@testable import KokoroStudio

final class LoudnessNormalizerTests: XCTestCase {
    /// 997 Hz sine — the standard loudness test tone.
    private func sine(amplitude: Float, sampleRate: Int = 24000,
                      seconds: Double = 5) -> [Float] {
        let count = Int(Double(sampleRate) * seconds)
        return (0..<count).map { i in
            amplitude * sin(2 * .pi * 997 * Float(i) / Float(sampleRate))
        }
    }

    func testGainShiftsLoudnessByMatchingAmount() {
        let quiet = sine(amplitude: 0.1)
        let loud = quiet.map { $0 * 2 } // +6.02 dB
        let l1 = LoudnessNormalizer.integratedLoudness(samples: quiet,
                                                       sampleRate: 24000)
        let l2 = LoudnessNormalizer.integratedLoudness(samples: loud,
                                                       sampleRate: 24000)
        XCTAssertEqual(l2 - l1, 6.02, accuracy: 0.2)
    }

    func testNormalizeHitsTarget() {
        let result = LoudnessNormalizer.normalize(
            samples: sine(amplitude: 0.3), sampleRate: 24000, targetLUFS: -16)
        XCTAssertEqual(
            LoudnessNormalizer.integratedLoudness(samples: result,
                                                  sampleRate: 24000),
            -16, accuracy: 0.5)
    }

    func testPeakCeilingCapsGain() {
        // 0 LUFS is absurdly loud; the -1 dBFS ceiling must win.
        let result = LoudnessNormalizer.normalize(
            samples: sine(amplitude: 0.5), sampleRate: 24000, targetLUFS: 0)
        XCTAssertLessThanOrEqual(result.map { abs($0) }.max() ?? 0,
                                 AudioProcessing.peakTarget + 0.001)
    }

    func testSilenceIsUnmeasurableAndUnchanged() {
        let silence = [Float](repeating: 0, count: 24000)
        XCTAssertEqual(
            LoudnessNormalizer.integratedLoudness(samples: silence,
                                                  sampleRate: 24000),
            LoudnessNormalizer.unmeasurable)
        XCTAssertEqual(LoudnessNormalizer.normalize(samples: silence,
                                                    sampleRate: 24000,
                                                    targetLUFS: -16), silence)
    }

    func testPresetTargets() {
        XCTAssertNil(LoudnessPreset.lms.targetLUFS(custom: -20))
        XCTAssertEqual(LoudnessPreset.podcast.targetLUFS(custom: -20), -16)
        XCTAssertEqual(LoudnessPreset.streaming.targetLUFS(custom: -20), -14)
        XCTAssertEqual(LoudnessPreset.custom.targetLUFS(custom: -20), -20)
    }
}
