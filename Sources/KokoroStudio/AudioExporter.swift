import Foundation
import AVFoundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case wav, m4a

    var id: String { rawValue }
    var label: String { self == .wav ? "WAV (lossless)" : "M4A (AAC)" }
    var fileExtension: String { rawValue }
}

enum AudioExporter {
    static func write(samples: [Float], sampleRate: Int, to url: URL,
                      format: ExportFormat) throws {
        let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Double(sampleRate),
                                             channels: 1, interleaved: false)!
        let settings: [String: Any]
        switch format {
        case .wav:
            settings = [AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false]
        case .m4a:
            // A fixed bitrate can be rejected for 24kHz mono; let the encoder
            // pick one from a quality level instead.
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!,
                                               count: samples.count)
        }
        try file.write(from: buffer)
    }

    /// "Hello, world! This is..." -> "Hello-world-This-is-<timestamp>"
    static func defaultFilename(for script: String) -> String {
        let words = script.split { !$0.isLetter && !$0.isNumber }.prefix(5)
        let stem = words.joined(separator: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        return stem.isEmpty ? "kokoro-\(timestamp)" : "\(stem)-\(timestamp)"
    }
}
