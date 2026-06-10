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

    var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: exportFormatRaw) ?? .wav }
        set { exportFormatRaw = newValue.rawValue }
    }

    private var engine: KokoroEngine?
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

    nonisolated static func locateModelDirectory() -> URL? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("model")
            if FileManager.default.fileExists(
                atPath: bundled.appendingPathComponent("model.onnx").path) {
                return bundled
            }
        }
        // Development fallback: running the bare binary from the repo root.
        let development = URL(fileURLWithPath: "vendor/model")
        if FileManager.default.fileExists(
            atPath: development.appendingPathComponent("model.onnx").path) {
            return development
        }
        return nil
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
        guard canGenerate, let engine else { return }
        let flag = CancellationFlag()
        currentCancellation = flag
        phase = .generating(0)

        let text = script
        let voice = voiceID
        let speedValue = Float(speed)

        Task.detached(priority: .userInitiated) {
            let samples = engine.synthesize(text: text, voiceID: voice,
                                            speed: speedValue) { progress in
                Task { @MainActor in
                    if case .generating = self.phase {
                        self.phase = .generating(progress)
                    }
                }
                return !flag.isCancelled
            }
            await MainActor.run {
                self.finishGeneration(samples: samples,
                                      sampleRate: engine.sampleRate,
                                      cancelled: flag.isCancelled)
            }
        }
    }

    private func finishGeneration(samples: [Float], sampleRate: Int, cancelled: Bool) {
        phase = .ready
        currentCancellation = nil
        guard !cancelled, !samples.isEmpty else { return }
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
