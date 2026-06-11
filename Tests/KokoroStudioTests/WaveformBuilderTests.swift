import XCTest
@testable import KokoroStudio

final class WaveformBuilderTests: XCTestCase {
    func testPeaksBucketCountAndNormalization() {
        let samples: [Float] = [0.1, -0.5, 0.2, 0.25, 0.0, -0.1, 0.05, 0.02]
        let peaks = WaveformBuilder.peaks(samples: samples, buckets: 4)
        XCTAssertEqual(peaks.count, 4)
        XCTAssertEqual(peaks[0], 1.0)          // 0.5 is the global max
        XCTAssertEqual(peaks[1], 0.5, accuracy: 0.001) // 0.25 / 0.5
        XCTAssertEqual(peaks.max(), 1.0)
    }

    func testPeaksEmptyAndOversizedBuckets() {
        XCTAssertEqual(WaveformBuilder.peaks(samples: [], buckets: 10), [])
        // Fewer samples than buckets still draws something sensible.
        let peaks = WaveformBuilder.peaks(samples: [0.5, 0.25], buckets: 10)
        XCTAssertFalse(peaks.isEmpty)
        XCTAssertLessThanOrEqual(peaks.count, 10)
    }

    func testHeadingMarkersMatchHeadingCues() {
        let script = "# Intro\nWelcome along.\n# Wrap Up\nThat is all."
        let cues = [CaptionCue(start: 0.0, end: 0.8, text: "Intro"),
                    CaptionCue(start: 1.0, end: 2.5, text: "Welcome along."),
                    CaptionCue(start: 3.0, end: 3.9, text: "Wrap Up"),
                    CaptionCue(start: 4.0, end: 5.0, text: "That is all.")]
        XCTAssertEqual(WaveformBuilder.headingMarkers(cues: cues, script: script),
                       [HeadingMarker(time: 0.0, title: "Intro"),
                        HeadingMarker(time: 3.0, title: "Wrap Up")])
    }

    func testNoHeadingsNoMarkers() {
        let cues = [CaptionCue(start: 0, end: 1, text: "Hello.")]
        XCTAssertTrue(WaveformBuilder.headingMarkers(cues: cues,
                                                     script: "Hello.").isEmpty)
    }
}
