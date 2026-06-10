import XCTest
@testable import KokoroStudio

final class KokoroEngineTests: XCTestCase {
    // The engine holds a ~310MB model; load it once for the whole test class.
    static var sharedEngine: KokoroEngine?

    func makeEngine() throws -> KokoroEngine {
        if let engine = Self.sharedEngine { return engine }
        let path = ProcessInfo.processInfo.environment["KOKORO_MODEL_DIR"] ?? "vendor/model"
        guard FileManager.default.fileExists(atPath: path + "/model.onnx") else {
            throw XCTSkip("model not present; run scripts/fetch-deps.sh")
        }
        let engine = try KokoroEngine(modelDirectory: URL(fileURLWithPath: path))
        Self.sharedEngine = engine
        return engine
    }

    func testSynthesizeProducesAudio() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.sampleRate, 24000)
        XCTAssertEqual(engine.numberOfSpeakers, 53)

        var progressValues: [Float] = []
        let samples = engine.synthesize(text: "Hello from Kokoro Studio.",
                                        voiceID: 3, speed: 1.0,
                                        progress: { progressValues.append($0); return true })
        XCTAssertGreaterThan(samples.count, 10_000)
        XCTAssertFalse(progressValues.isEmpty)
    }

    func testCancelStopsEarly() throws {
        let engine = try makeEngine()
        let longText = Array(repeating: "This is a sentence to synthesize.",
                             count: 30).joined(separator: " ")
        let samples = engine.synthesize(text: longText, voiceID: 3, speed: 1.0,
                                        progress: { _ in false }) // cancel at first callback
        // A cancelled run must be far shorter than the full ~70s of speech.
        XCTAssertLessThan(samples.count, 24000 * 30)
    }
}
