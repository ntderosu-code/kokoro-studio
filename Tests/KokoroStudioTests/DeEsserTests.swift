import XCTest
@testable import KokoroStudio

final class DeEsserTests: XCTestCase {
    private let sampleRate = 44_100

    private func sine(frequency: Float, amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { index in
            amplitude * sin(2 * .pi * frequency * Float(index) / Float(sampleRate))
        }
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
    }

    func testEmptyAndSilencePassThrough() {
        XCTAssertEqual(DeEsser.process([], sampleRate: sampleRate), [])
        let silence = [Float](repeating: 0, count: 1_000)
        XCTAssertEqual(DeEsser.process(silence, sampleRate: sampleRate), silence)
    }

    func testLowFrequencyContentIsUntouched() {
        let voice = sine(frequency: 1_000, amplitude: 0.5, count: sampleRate)
        let processed = DeEsser.process(voice, sampleRate: sampleRate)
        // Skip the first 50ms while filters settle.
        let start = sampleRate / 20
        let inLevel = rms(voice[start...])
        let outLevel = rms(processed[start...])
        XCTAssertEqual(outLevel, inLevel, accuracy: inLevel * 0.06,
                       "1 kHz content should pass through nearly unchanged")
    }

    func testLoudSibilanceBandIsAttenuated() {
        // Quiet speech-band tone with a loud 8 kHz "s" burst on top.
        let count = sampleRate
        let base = sine(frequency: 500, amplitude: 0.1, count: count)
        let hiss = sine(frequency: 8_000, amplitude: 0.5, count: count)
        let mixed = zip(base, hiss).map(+)
        let processed = DeEsser.process(mixed, sampleRate: sampleRate)

        // Compare the high-band level by subtracting the (unchanged) base.
        let start = sampleRate / 10
        let hissIn = rms(zip(mixed, base).map(-)[start...])
        let hissOut = rms(zip(processed, base).map(-)[start...])
        let reductionDB = 20 * log10(hissOut / hissIn)
        XCTAssertLessThan(reductionDB, -3,
                          "expected ≥3 dB reduction, got \(reductionDB) dB")
    }

    func testOutputLengthMatchesInput() {
        let noise = (0..<12_345).map { _ in Float.random(in: -0.3...0.3) }
        XCTAssertEqual(DeEsser.process(noise, sampleRate: sampleRate).count,
                       noise.count)
    }
}
