import Foundation
import AVFoundation
import CSherpaOnnx

/// Wrapper around sherpa-onnx Pocket TTS (Kyutai) — a voice-cloning model.
/// The voice comes from a short reference audio clip rather than a speaker ID.
/// Not thread-safe; call `synthesize` from one task at a time.
final class PocketEngine {
    private let tts: OpaquePointer
    let sampleRate: Int

    init(modelDirectory: URL) throws {
        let dir = modelDirectory.path

        func owned(_ string: String) -> UnsafePointer<CChar> {
            UnsafePointer(strdup(string)!)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)
        config.model.pocket.lm_flow = owned("\(dir)/lm_flow.int8.onnx")
        config.model.pocket.lm_main = owned("\(dir)/lm_main.int8.onnx")
        config.model.pocket.encoder = owned("\(dir)/encoder.onnx")
        config.model.pocket.decoder = owned("\(dir)/decoder.int8.onnx")
        config.model.pocket.text_conditioner = owned("\(dir)/text_conditioner.onnx")
        config.model.pocket.vocab_json = owned("\(dir)/vocab.json")
        config.model.pocket.token_scores_json = owned("\(dir)/token_scores.json")
        config.model.pocket.voice_embedding_cache_capacity = 8
        config.model.num_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        config.model.provider = owned("cpu")

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw KokoroEngineError.modelLoadFailed(
                "Pocket TTS engine creation returned NULL — check the model files in \(dir)")
        }
        tts = handle
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(handle))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// `referenceAudio` must be mono float samples; the voice in that clip is
    /// cloned. `progress` receives 0...1; return false to cancel.
    func synthesize(text: String, referenceAudio: [Float], referenceSampleRate: Int,
                    speed: Float, progress: @escaping (Float) -> Bool) -> [Float] {
        final class CallbackBox {
            let report: (Float) -> Bool
            init(_ report: @escaping (Float) -> Bool) { self.report = report }
        }
        let box = CallbackBox(progress)

        let cCallback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, progressValue, arg in
            let box = Unmanaged<CallbackBox>.fromOpaque(arg!).takeUnretainedValue()
            return box.report(progressValue) ? 1 : 0
        }

        let audio = referenceAudio.withUnsafeBufferPointer { reference -> UnsafePointer<SherpaOnnxGeneratedAudio>? in
            var generationConfig = SherpaOnnxGenerationConfig()
            memset(&generationConfig, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
            generationConfig.reference_audio = reference.baseAddress
            generationConfig.reference_audio_len = Int32(reference.count)
            generationConfig.reference_sample_rate = Int32(referenceSampleRate)
            generationConfig.num_steps = 5
            generationConfig.speed = speed
            return withExtendedLifetime(box) {
                SherpaOnnxOfflineTtsGenerateWithConfig(
                    tts, text, &generationConfig, cCallback,
                    Unmanaged.passUnretained(box).toOpaque())
            }
        }
        guard let audio else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let sampleCount = Int(audio.pointee.n)
        guard sampleCount > 0, let samplesPointer = audio.pointee.samples else { return [] }
        return Array(UnsafeBufferPointer(start: samplesPointer, count: sampleCount))
    }
}

/// Loads an audio file (wav/m4a/mp3/...) as mono float samples for use as a
/// Pocket TTS voice reference.
enum ReferenceAudioLoader {
    static func load(url: URL) throws -> (samples: [Float], sampleRate: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frameCount) else {
            throw KokoroEngineError.modelLoadFailed("could not allocate audio buffer")
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw KokoroEngineError.modelLoadFailed("unsupported audio format in \(url.lastPathComponent)")
        }
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        // Mix down to mono.
        var mono = [Float](repeating: 0, count: frames)
        for channel in 0..<channels {
            let data = channelData[channel]
            for frame in 0..<frames {
                mono[frame] += data[frame] / Float(channels)
            }
        }
        return (mono, Int(format.sampleRate))
    }
}
