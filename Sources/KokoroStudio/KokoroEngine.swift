import Foundation
import CSherpaOnnx

enum KokoroEngineError: Error, LocalizedError {
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let detail):
            return "Could not load the Kokoro model: \(detail)"
        }
    }
}

/// Thin wrapper around the sherpa-onnx offline TTS C API.
/// Not thread-safe; call `synthesize` from one task at a time.
final class KokoroEngine {
    // SherpaOnnxOfflineTts is an opaque C type; Swift imports pointers to it
    // as OpaquePointer.
    private let tts: OpaquePointer
    let sampleRate: Int
    let numberOfSpeakers: Int

    init(modelDirectory: URL) throws {
        let dir = modelDirectory.path

        // The C API keeps no copy of these strings during creation only, but
        // strdup-ing once per engine keeps ownership rules simple. The engine
        // lives for the whole app session, so the bytes are never freed.
        func owned(_ string: String) -> UnsafePointer<CChar> {
            UnsafePointer(strdup(string)!)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)
        config.model.kokoro.model = owned("\(dir)/model.onnx")
        config.model.kokoro.voices = owned("\(dir)/voices.bin")
        config.model.kokoro.tokens = owned("\(dir)/tokens.txt")
        config.model.kokoro.data_dir = owned("\(dir)/espeak-ng-data")
        config.model.kokoro.lexicon = owned("\(dir)/lexicon-us-en.txt,\(dir)/lexicon-zh.txt")
        config.model.kokoro.length_scale = 1.0
        config.model.num_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        config.model.provider = owned("cpu")
        // One sentence per chunk so progress callbacks arrive frequently and
        // cancellation takes effect quickly.
        config.max_num_sentences = 1

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw KokoroEngineError.modelLoadFailed(
                "engine creation returned NULL — check the model files in \(dir)")
        }
        tts = handle
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(handle))
        numberOfSpeakers = Int(SherpaOnnxOfflineTtsNumSpeakers(handle))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// `progress` receives values in 0...1; return false to cancel.
    /// Returns the generated mono samples (possibly partial if cancelled).
    func synthesize(text: String, voiceID: Int, speed: Float,
                    progress: @escaping (Float) -> Bool) -> [Float] {
        final class CallbackBox {
            let report: (Float) -> Bool
            init(_ report: @escaping (Float) -> Bool) { self.report = report }
        }
        let box = CallbackBox(progress)

        var generationConfig = SherpaOnnxGenerationConfig()
        memset(&generationConfig, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
        generationConfig.sid = Int32(voiceID)
        generationConfig.speed = speed

        let cCallback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, progressValue, arg in
            let box = Unmanaged<CallbackBox>.fromOpaque(arg!).takeUnretainedValue()
            return box.report(progressValue) ? 1 : 0
        }

        let audio = withExtendedLifetime(box) {
            SherpaOnnxOfflineTtsGenerateWithConfig(
                tts, text, &generationConfig, cCallback,
                Unmanaged.passUnretained(box).toOpaque())
        }
        guard let audio else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let sampleCount = Int(audio.pointee.n)
        guard sampleCount > 0, let samplesPointer = audio.pointee.samples else { return [] }
        return Array(UnsafeBufferPointer(start: samplesPointer, count: sampleCount))
    }
}
