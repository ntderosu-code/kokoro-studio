import SwiftUI
import AppKit

/// Cross-thread cancellation flag shared with the synthesis thread.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum TTSEngineKind: String, CaseIterable, Identifiable {
    case kokoro, pocket
    var id: String { rawValue }
    var label: String { self == .kokoro ? "Kokoro" : "Pocket (cloning)" }
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loadingModel
        case ready
        case generating(Float)
        case failed(String)
    }

    struct GeneratedAudio {
        let samples: [Float]
        let sampleRate: Int
        let previewWAV: URL
    }

    @Published var script = ""
    @Published var phase: Phase = .loadingModel
    @Published var lastAudio: GeneratedAudio?
    @Published var errorMessage: String?

    @AppStorage("voiceID") var voiceID = 3 // af_heart
    @AppStorage("speed") var speed = 1.0
    @AppStorage("exportFormat") private var exportFormatRaw = ExportFormat.wav.rawValue
    @AppStorage("outputFolderPath") var outputFolderPath = ""
    @AppStorage("paragraphPauseMs") var paragraphPauseMs = 500
    @AppStorage("punctuationPauseMs") var punctuationPauseMs = 0
    @AppStorage("pronunciationRules") var pronunciationRulesText = ""
    @AppStorage("engineKind") private var engineKindRaw = TTSEngineKind.kokoro.rawValue
    @AppStorage("pocketVoicePath") var pocketVoicePath = ""
    @AppStorage("normalizeLoudness") var normalizeLoudness = true

    var engineKind: TTSEngineKind {
        get { TTSEngineKind(rawValue: engineKindRaw) ?? .kokoro }
        set { engineKindRaw = newValue.rawValue }
    }

    var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: exportFormatRaw) ?? .wav }
        set { exportFormatRaw = newValue.rawValue }
    }

    private var engine: KokoroEngine?
    private var pocketEngine: PocketEngine?
    private var currentCancellation: CancellationFlag?

    var isGenerating: Bool {
        if case .generating = phase { return true }
        return false
    }

    var canGenerate: Bool {
        phase == .ready
            && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Model loading

    nonisolated private static func locateResource(bundleName: String,
                                                   developmentPath: String,
                                                   marker: String) -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent(bundleName)
            if FileManager.default.fileExists(
                atPath: bundled.appendingPathComponent(marker).path) {
                return bundled
            }
        }
        // Development fallback: running the bare binary from the repo root.
        let development = URL(fileURLWithPath: developmentPath)
        if FileManager.default.fileExists(
            atPath: development.appendingPathComponent(marker).path) {
            return development
        }
        return nil
    }

    nonisolated static func locateModelDirectory() -> URL? {
        locateResource(bundleName: "model", developmentPath: "vendor/model",
                       marker: "model.onnx")
    }

    nonisolated static func locatePocketDirectory() -> URL? {
        locateResource(bundleName: "pocket", developmentPath: "vendor/pocket",
                       marker: "lm_main.int8.onnx")
    }

    /// The reference clip whose voice Pocket TTS clones. Falls back to the
    /// bundled "Bria" sample.
    var pocketVoiceURL: URL? {
        if !pocketVoicePath.isEmpty,
           FileManager.default.fileExists(atPath: pocketVoicePath) {
            return URL(fileURLWithPath: pocketVoicePath)
        }
        return Self.locatePocketDirectory()?
            .appendingPathComponent("test_wavs/bria.wav")
    }

    func loadModel() {
        guard engine == nil else { return }
        phase = .loadingModel
        Task.detached(priority: .userInitiated) {
            do {
                guard let directory = AppState.locateModelDirectory() else {
                    throw KokoroEngineError.modelLoadFailed(
                        "model folder not found — the app bundle appears incomplete")
                }
                let engine = try KokoroEngine(modelDirectory: directory)
                await MainActor.run {
                    self.engine = engine
                    self.phase = .ready
                }
            } catch {
                await MainActor.run {
                    self.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Generation

    func generate() {
        guard canGenerate else { return }
        let flag = CancellationFlag()
        currentCancellation = flag
        phase = .generating(0)

        let kind = engineKind
        let rules = PronunciationDictionary.parse(pronunciationRulesText)
        let processedScript = PronunciationDictionary.apply(rules, to: script)
        let segments = ScriptSegmenter.segment(processedScript,
                                               paragraphPauseMs: paragraphPauseMs,
                                               punctuationPauseMs: punctuationPauseMs)
        let voice = voiceID
        let speedValue = Float(speed)
        let voiceReferenceURL = pocketVoiceURL
        let kokoroEngine = engine
        let cachedPocketEngine = pocketEngine

        Task.detached(priority: .userInitiated) {
            do {
                let synthesizeSegment: (String, @escaping (Float) -> Bool) -> [Float]
                let sampleRate: Int

                switch kind {
                case .kokoro:
                    guard let kokoroEngine else { return }
                    sampleRate = kokoroEngine.sampleRate
                    synthesizeSegment = { text, onProgress in
                        kokoroEngine.synthesize(text: text, voiceID: voice,
                                                speed: speedValue, progress: onProgress)
                    }
                case .pocket:
                    let pocket: PocketEngine
                    if let cachedPocketEngine {
                        pocket = cachedPocketEngine
                    } else {
                        guard let directory = AppState.locatePocketDirectory() else {
                            throw KokoroEngineError.modelLoadFailed(
                                "Pocket TTS model folder not found in the app bundle")
                        }
                        pocket = try PocketEngine(modelDirectory: directory)
                        await MainActor.run { self.pocketEngine = pocket }
                    }
                    guard let voiceReferenceURL else {
                        throw KokoroEngineError.modelLoadFailed(
                            "no voice sample selected for Pocket TTS")
                    }
                    let reference = try ReferenceAudioLoader.load(url: voiceReferenceURL)
                    sampleRate = pocket.sampleRate
                    synthesizeSegment = { text, onProgress in
                        pocket.synthesize(text: text,
                                          referenceAudio: reference.samples,
                                          referenceSampleRate: reference.sampleRate,
                                          speed: speedValue, progress: onProgress)
                    }
                }

                var allSamples: [Float] = []
                let segmentCount = max(segments.count, 1)
                for (index, segment) in segments.enumerated() {
                    if flag.isCancelled { break }
                    let segmentSamples = synthesizeSegment(segment.text) { progress in
                        let overall = (Float(index) + progress) / Float(segmentCount)
                        Task { @MainActor in
                            if case .generating = self.phase {
                                self.phase = .generating(overall)
                            }
                        }
                        return !flag.isCancelled
                    }
                    allSamples.append(contentsOf: segmentSamples)
                    if segment.pauseAfterMs > 0, !flag.isCancelled {
                        let silenceFrames = sampleRate * segment.pauseAfterMs / 1000
                        allSamples.append(contentsOf: [Float](repeating: 0, count: silenceFrames))
                    }
                }
                let samples = allSamples
                await MainActor.run {
                    self.finishGeneration(samples: samples, sampleRate: sampleRate,
                                          cancelled: flag.isCancelled)
                }
            } catch {
                await MainActor.run {
                    self.phase = .ready
                    self.currentCancellation = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func finishGeneration(samples rawSamples: [Float], sampleRate: Int,
                                  cancelled: Bool) {
        phase = .ready
        currentCancellation = nil
        guard !cancelled, !rawSamples.isEmpty else { return }
        let samples = normalizeLoudness
            ? AudioProcessing.finalize(samples: rawSamples, sampleRate: sampleRate)
            : rawSamples
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kokoro-preview-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try AudioExporter.write(samples: samples, sampleRate: sampleRate,
                                    to: url, format: .wav)
            lastAudio = GeneratedAudio(samples: samples, sampleRate: sampleRate,
                                       previewWAV: url)
        } catch {
            errorMessage = "Could not prepare preview audio: \(error.localizedDescription)"
        }
    }

    func cancelGeneration() {
        currentCancellation?.cancel()
    }

    // MARK: - Export

    func export() {
        guard let audio = lastAudio else { return }
        let folder: URL
        if !outputFolderPath.isEmpty,
           FileManager.default.fileExists(atPath: outputFolderPath) {
            folder = URL(fileURLWithPath: outputFolderPath)
        } else if let chosen = Self.chooseFolder() {
            outputFolderPath = chosen.path
            folder = chosen
        } else {
            return
        }
        let filename = AudioExporter.defaultFilename(for: script)
        let destination = folder.appendingPathComponent(filename)
            .appendingPathExtension(exportFormat.fileExtension)
        do {
            try AudioExporter.write(samples: audio.samples,
                                    sampleRate: audio.sampleRate,
                                    to: destination, format: exportFormat)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func chooseOutputFolder() {
        if let chosen = Self.chooseFolder() {
            outputFolderPath = chosen.path
        }
    }

    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a folder for exported audio"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
