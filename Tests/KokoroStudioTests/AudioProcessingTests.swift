import XCTest
@testable import KokoroStudio

final class AudioProcessingTests: XCTestCase {
    func testNormalizePeakHitsTarget() {
        let quiet: [Float] = [0.1, -0.2, 0.05]
        let normalized = AudioProcessing.normalizePeak(quiet)
        XCTAssertEqual(normalized.map { abs($0) }.max()!,
                       AudioProcessing.peakTarget, accuracy: 0.0001)
    }

    func testNormalizeSilenceIsNoop() {
        let silence = [Float](repeating: 0, count: 100)
        XCTAssertEqual(AudioProcessing.normalizePeak(silence), silence)
    }

    func testTrimSilenceKeepsPad() {
        // 1s silence + 1s tone + 1s silence at 1000Hz sample rate
        var samples = [Float](repeating: 0, count: 1000)
        samples += [Float](repeating: 0.5, count: 1000)
        samples += [Float](repeating: 0, count: 1000)
        let trimmed = AudioProcessing.trimSilence(samples, sampleRate: 1000)
        // tone (1000) + 60ms pad each side (60 + 60)
        XCTAssertEqual(trimmed.count, 1120)
    }

    func testFadesStartAndEndNearZero() {
        let samples = [Float](repeating: 0.8, count: 4800)
        let faded = AudioProcessing.applyFades(samples, sampleRate: 24000)
        XCTAssertEqual(faded.first!, 0, accuracy: 0.01)
        XCTAssertEqual(faded.last!, 0, accuracy: 0.01)
        XCTAssertEqual(faded[2400], 0.8) // middle untouched
    }

    func testFinalizePipeline() {
        var samples = [Float](repeating: 0, count: 2400)
        samples += (0..<24000).map { sin(Float($0) * 2 * .pi * 440 / 24000) * 0.3 }
        samples += [Float](repeating: 0, count: 2400)
        let final = AudioProcessing.finalize(samples: samples, sampleRate: 24000)
        XCTAssertLessThan(final.count, samples.count)        // trimmed
        XCTAssertEqual(final.map { abs($0) }.max()!,
                       AudioProcessing.peakTarget, accuracy: 0.01) // normalized
    }
}
