import XCTest
@testable import KokoroStudio

final class SupertonicEngineTests: XCTestCase {
    static var sharedEngine: SupertonicEngine?

    func makeEngine() throws -> SupertonicEngine {
        let path = ProcessInfo.processInfo.environment["SUPERTONIC_MODEL_DIR"]
            ?? "vendor/supertonic"
        guard FileManager.default.fileExists(atPath: path + "/voice.bin") else {
            throw XCTSkip("supertonic model not present; run scripts/fetch-deps.sh")
        }
        if let engine = Self.sharedEngine { return engine }
        let engine = try SupertonicEngine(modelDirectory: URL(fileURLWithPath: path))
        Self.sharedEngine = engine
        return engine
    }

    func testModelExposesTenVoicesAt44kHz() throws {
        let engine = try makeEngine()
        XCTAssertEqual(engine.speakerCount, SupertonicVoiceCatalog.voices.count)
        XCTAssertEqual(engine.sampleRate, 44_100)
    }

    func testSynthesizesAudibleSamples() throws {
        let engine = try makeEngine()
        let samples = engine.synthesize(text: "Hello from Supertonic.",
                                        voiceID: SupertonicVoiceCatalog.defaultVoiceID,
                                        speed: 1.0,
                                        progress: { _ in true })
        XCTAssertGreaterThan(samples.count, 5_000)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.01)
    }

    func testEveryCatalogVoiceIDIsValid() throws {
        let engine = try makeEngine()
        for voice in SupertonicVoiceCatalog.voices {
            XCTAssertLessThan(voice.id, engine.speakerCount,
                              "voice \(voice.name) out of range")
        }
    }
}
