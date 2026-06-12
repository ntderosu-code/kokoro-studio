import Foundation
import CSherpaOnnx

/// Wrapper around sherpa-onnx Supertonic 3 TTS — a fast multilingual model
/// with ten built-in voices selected by speaker ID (no cloning).
/// Not thread-safe; call `synthesize` from one task at a time.
final class SupertonicEngine {
    private let tts: OpaquePointer
    let sampleRate: Int
    let speakerCount: Int

    init(modelDirectory: URL) throws {
        let dir = modelDirectory.path

        func owned(_ string: String) -> UnsafePointer<CChar> {
            UnsafePointer(strdup(string)!)
        }

        var config = SherpaOnnxOfflineTtsConfig()
        memset(&config, 0, MemoryLayout<SherpaOnnxOfflineTtsConfig>.size)
        config.model.supertonic.duration_predictor = owned("\(dir)/duration_predictor.int8.onnx")
        config.model.supertonic.text_encoder = owned("\(dir)/text_encoder.int8.onnx")
        config.model.supertonic.vector_estimator = owned("\(dir)/vector_estimator.int8.onnx")
        config.model.supertonic.vocoder = owned("\(dir)/vocoder.int8.onnx")
        config.model.supertonic.tts_json = owned("\(dir)/tts.json")
        config.model.supertonic.unicode_indexer = owned("\(dir)/unicode_indexer.bin")
        config.model.supertonic.voice_style = owned("\(dir)/voice.bin")
        config.model.num_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        config.model.provider = owned("cpu")

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw KokoroEngineError.modelLoadFailed(
                "Supertonic engine creation returned NULL — check the model files in \(dir)")
        }
        tts = handle
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(handle))
        speakerCount = Int(SherpaOnnxOfflineTtsNumSpeakers(handle))
    }

    deinit {
        SherpaOnnxDestroyOfflineTts(tts)
    }

    /// `voiceID` is a Supertonic speaker ID (see `SupertonicVoiceCatalog`).
    /// `progress` receives 0...1; return false to cancel.
    func synthesize(text: String, voiceID: Int, speed: Float,
                    progress: @escaping (Float) -> Bool) -> [Float] {
        final class CallbackBox {
            let report: (Float) -> Bool
            init(_ report: @escaping (Float) -> Bool) { self.report = report }
        }
        let box = CallbackBox(progress)

        let cCallback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, progressValue, arg in
            let box = Unmanaged<CallbackBox>.fromOpaque(arg!).takeUnretainedValue()
            return box.report(progressValue) ? 1 : 0
        }

        var generationConfig = SherpaOnnxGenerationConfig()
        memset(&generationConfig, 0, MemoryLayout<SherpaOnnxGenerationConfig>.size)
        generationConfig.sid = Int32(voiceID)
        generationConfig.num_steps = 8
        generationConfig.speed = speed
        let extra = strdup("{\"lang\": \"en\"}")
        generationConfig.extra = UnsafePointer(extra)
        defer { free(extra) }

        let audio = withExtendedLifetime(box) {
            SherpaOnnxOfflineTtsGenerateWithConfig(
                tts, text, &generationConfig, cCallback,
                Unmanaged.passUnretained(box).toOpaque())
        }
        guard let audio else { return [] }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }

        let sampleCount = Int(audio.pointee.n)
        guard sampleCount > 0, let samplesPointer = audio.pointee.samples else { return [] }
        let raw = Array(UnsafeBufferPointer(start: samplesPointer, count: sampleCount))
        // Supertonic's "s" sounds run hot; tame the sibilance band before
        // the samples reach any consumer (generate, audition, previews).
        return DeEsser.process(raw, sampleRate: sampleRate)
    }
}

/// The ten Supertonic 3 voice styles. IDs match the order styles were
/// packed into `voice.bin` (alphabetical: F1–F5 then M1–M5).
enum SupertonicVoiceCatalog {
    struct Voice: Identifiable, Equatable {
        let id: Int
        let name: String
        let blurb: String
        var displayName: String { "\(name) — \(blurb)" }
    }

    static let voices: [Voice] = [
        Voice(id: 0, name: "F1", blurb: "calm, steady, slightly low"),
        Voice(id: 1, name: "F2", blurb: "bright, cheerful, youthful"),
        Voice(id: 2, name: "F3", blurb: "professional announcer"),
        Voice(id: 3, name: "F4", blurb: "crisp, confident, expressive"),
        Voice(id: 4, name: "F5", blurb: "kind, gentle, soothing"),
        Voice(id: 5, name: "M1", blurb: "lively, upbeat, confident"),
        Voice(id: 6, name: "M2", blurb: "deep, calm, serious"),
        Voice(id: 7, name: "M3", blurb: "polished, authoritative"),
        Voice(id: 8, name: "M4", blurb: "soft, friendly, youthful"),
        Voice(id: 9, name: "M5", blurb: "warm storyteller"),
    ]

    /// F3 — the announcer-style voice, a good default for narration.
    static let defaultVoiceID = 2

    static func voice(forID id: Int) -> Voice {
        voices.first(where: { $0.id == id }) ?? voices[defaultVoiceID]
    }
}
