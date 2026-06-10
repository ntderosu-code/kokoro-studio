import XCTest
import AVFoundation
@testable import KokoroStudio

final class AudioExporterTests: XCTestCase {
    // one second of 440Hz sine at 24kHz
    var sine: [Float] {
        (0..<24000).map { sin(Float($0) * 2 * .pi * 440 / 24000) * 0.5 }
    }

    func tempURL(_ fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    func testWAVRoundTrip() throws {
        let url = tempURL("wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioExporter.write(samples: sine, sampleRate: 24000, to: url, format: .wav)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 24000)
        XCTAssertEqual(Int(file.length), 24000)
    }

    func testM4AWrites() throws {
        let url = tempURL("m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioExporter.write(samples: sine, sampleRate: 24000, to: url, format: .m4a)
        let file = try AVAudioFile(forReading: url)
        // AAC may pad with priming frames; duration within 15%
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1.0, accuracy: 0.15)
    }

    func testDefaultFilename() {
        let name = AudioExporter.defaultFilename(
            for: "Hello, world! This is a   test script that goes on.")
        XCTAssertTrue(name.hasPrefix("Hello-world-This-is"), "got \(name)")
        XCTAssertFalse(name.contains(" "))
        XCTAssertFalse(name.contains("/"))
    }

    func testDefaultFilenameEmptyScript() {
        XCTAssertTrue(AudioExporter.defaultFilename(for: "  ").hasPrefix("kokoro-"))
    }
}
