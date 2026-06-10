import XCTest
@testable import KokoroStudio

final class PocketEngineTests: XCTestCase {
    static var sharedEngine: PocketEngine?

    func makeEngine() throws -> (PocketEngine, URL) {
        let path = ProcessInfo.processInfo.environment["POCKET_MODEL_DIR"] ?? "vendor/pocket"
        let dir = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path + "/lm_main.int8.onnx") else {
            throw XCTSkip("pocket model not present; run scripts/fetch-deps.sh")
        }
        if let engine = Self.sharedEngine { return (engine, dir) }
        let engine = try PocketEngine(modelDirectory: dir)
        Self.sharedEngine = engine
        return (engine, dir)
    }

    func testCloneVoiceFromReference() throws {
        let (engine, dir) = try makeEngine()
        let reference = try ReferenceAudioLoader.load(
            url: dir.appendingPathComponent("test_wavs/bria.wav"))
        XCTAssertGreaterThan(reference.samples.count, 1000)

        let samples = engine.synthesize(text: "Hello from Pocket TTS.",
                                        referenceAudio: reference.samples,
                                        referenceSampleRate: reference.sampleRate,
                                        speed: 1.0,
                                        progress: { _ in true })
        XCTAssertGreaterThan(samples.count, 5_000)
        XCTAssertGreaterThan(engine.sampleRate, 8_000)
    }
}
