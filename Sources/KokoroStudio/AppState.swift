import SwiftUI
import AppKit
import AVFoundation

/// Clears preview state when a voice sample finishes playing.
final class VoicePreviewDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                     successfully flag: Bool) {
        Task { @MainActor in self.onFinish?() }
    }
}

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
        let cues: [CaptionCue]
        /// True when this came from Preview Selection, not the full script.
        let isPreview: Bool
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
    @AppStorage("sentencePauseMs") var sentencePauseMs = 0
    @AppStorage("clausePauseMs") var clausePauseMs = 0
    @AppStorage("headingPauseMs") var headingPauseMs = 800
    @AppStorage("pronunciationRules") var pronunciationRulesText = ""
    @AppStorage("speakerVoices") var speakerVoicesJSON = ""
    @AppStorage("numberPreset") private var numberPresetRaw = NumberPreset.natural.rawValue

    var numberPreset: NumberPreset {
        get { NumberPreset(rawValue: numberPresetRaw) ?? .natural }
        set { numberPresetRaw = newValue.rawValue }
    }

    var pauseSettings: PauseSettings {
        PauseSettings(paragraphMs: paragraphPauseMs, sentenceMs: sentencePauseMs,
                      clauseMs: clausePauseMs, headingMs: headingPauseMs)
    }

    /// Speaker name -> Kokoro voice ID, persisted as JSON.
    var speakerVoices: [String: Int] {
        get {
            guard let data = speakerVoicesJSON.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: Int].self, from: data)
            else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                speakerVoicesJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }

    @AppStorage("speakerSpeeds") var speakerSpeedsJSON = ""

    /// Speaker name -> speed multiplier (1.0 = the main Speed setting).
    var speakerSpeeds: [String: Double] {
        get {
            guard let data = speakerSpeedsJSON.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                speakerSpeedsJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }
    @AppStorage("engineKind") private var engineKindRaw = TTSEngineKind.kokoro.rawValue
    @AppStorage("pocketVoicePath") var pocketVoicePath = ""
    @AppStorage("normalizeLoudness") var normalizeLoudness = true
    @AppStorage("loudnessPreset") private var loudnessPresetRaw
        = LoudnessPreset.lms.rawValue
    @AppStorage("customLoudnessLUFS") var customLoudnessLUFS = -16.0

    var loudnessPreset: LoudnessPreset {
        get { LoudnessPreset(rawValue: loudnessPresetRaw) ?? .lms }
        set { loudnessPresetRaw = newValue.rawValue }
    }
    @AppStorage("calibratedWordsPerSecond") var calibratedWordsPerSecond
        = DurationEstimator.defaultWordsPerSecond
    @AppStorage("leadInMs") var leadInMs = 0
    @AppStorage("leadOutMs") var leadOutMs = 0

    // MARK: Preferences (Settings window)

    @AppStorage("editorFontSize") var editorFontSize = 14.0
    @AppStorage("settingsTab") var settingsTab = "general"
    @AppStorage("autoplayAfterGenerate") var autoplayAfterGenerate = false
    @AppStorage("revealInFinderAfterExport") var revealInFinderAfterExport = true
    @AppStorage("timestampInFilenames") var timestampInFilenames = true
    @AppStorage("favoriteVoiceIDs") private var favoriteVoiceIDsJSON = ""
    @AppStorage("hiddenVoiceIDs") private var hiddenVoiceIDsJSON = ""

    private func decodeIDs(_ json: String) -> Set<Int> {
        guard let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private func encodeIDs(_ ids: Set<Int>) -> String {
        (try? JSONEncoder().encode(ids.sorted()))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var favoriteVoiceIDs: Set<Int> {
        get { decodeIDs(favoriteVoiceIDsJSON) }
        set { favoriteVoiceIDsJSON = encodeIDs(newValue) }
    }

    var hiddenVoiceIDs: Set<Int> {
        get { decodeIDs(hiddenVoiceIDsJSON) }
        set { hiddenVoiceIDsJSON = encodeIDs(newValue) }
    }

    var visibleVoiceGroups: [(label: String, voices: [Voice])] {
        VoiceCatalog.visibleGroups(favorites: favoriteVoiceIDs,
                                   hidden: hiddenVoiceIDs,
                                   selectedID: voiceID)
    }
    @AppStorage("captionFormat") private var captionFormatRaw = CaptionFormat.off.rawValue

    var captionFormat: CaptionFormat {
        get { CaptionFormat(rawValue: captionFormatRaw) ?? .off }
        set { captionFormatRaw = newValue.rawValue }
    }

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

    // MARK: - Voice previews

    static let voicePreviewText = "This is the sound of my voice."

    @Published var previewingVoiceID: Int?
    @Published var renderingPreviewVoiceID: Int?
    private let voicePreviewDelegate = VoicePreviewDelegate()
    private var voicePreviewPlayer: AVAudioPlayer?

    private static var voicePreviewDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,
                                 in: .userDomainMask)[0]
            .appendingPathComponent("Kokoro Studio/VoicePreviews")
    }

    /// Plays a cached "This is the sound of my voice." sample for the voice,
    /// rendering and caching it on first use. Toggles off if already playing.
    func toggleVoicePreview(_ voiceID: Int) {
        if previewingVoiceID == voiceID {
            voicePreviewPlayer?.stop()
            previewingVoiceID = nil
            return
        }
        voicePreviewPlayer?.stop()
        previewingVoiceID = nil

        let cacheURL = Self.voicePreviewDirectory
            .appendingPathComponent("v\(voiceID).wav")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            playPreview(from: cacheURL, voiceID: voiceID)
            return
        }
        guard let engine, renderingPreviewVoiceID == nil, !isGenerating else { return }
        renderingPreviewVoiceID = voiceID
        Task.detached(priority: .userInitiated) {
            let samples = engine.synthesize(text: AppState.voicePreviewText,
                                            voiceID: voiceID, speed: 1.0,
                                            progress: { _ in true })
            await MainActor.run {
                self.renderingPreviewVoiceID = nil
                guard !samples.isEmpty else { return }
                do {
                    try FileManager.default.createDirectory(
                        at: Self.voicePreviewDirectory,
                        withIntermediateDirectories: true)
                    try AudioExporter.write(
                        samples: AudioProcessing.normalizePeak(samples),
                        sampleRate: engine.sampleRate,
                        to: cacheURL, format: .wav)
                    self.playPreview(from: cacheURL, voiceID: voiceID)
                } catch {
                    self.errorMessage = "Could not render voice preview: \(error.localizedDescription)"
                }
            }
        }
    }

    private func playPreview(from url: URL, voiceID: Int) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        voicePreviewDelegate.onFinish = { [weak self] in
            self?.previewingVoiceID = nil
        }
        player.delegate = voicePreviewDelegate
        voicePreviewPlayer = player
        previewingVoiceID = voiceID
        player.play()
    }

    // MARK: - Document import (#33)

    /// Toggled by the File menu; ContentView owns the fileImporter.
    @Published var showingImportPanel = false
    /// Non-nil presents the import preview sheet with converted text.
    @Published var importedText: String?

    // MARK: - A/B voice audition (#32)

    /// Non-nil presents the Compare Voices sheet with this text.
    @Published var auditionText: String?
    @Published var auditionRendering: AuditionVoice?
    @Published var auditionPlaying: AuditionVoice?
    private var auditionPlayer: AVAudioPlayer?
    private let auditionPlayerDelegate = VoicePreviewDelegate()
    /// Session cache: cacheKey -> rendered WAV in the temp directory, so
    /// replaying and switching sides is instant.
    private var auditionCache: [String: URL] = [:]

    func toggleAudition(text: String, voice: AuditionVoice) {
        if auditionPlaying == voice {
            auditionPlayer?.stop()
            auditionPlaying = nil
            return
        }
        auditionPlayer?.stop()
        auditionPlaying = nil

        let key = AuditionSupport.cacheKey(text: text,
                                           voiceLabel: voice.cacheLabel)
        if let url = auditionCache[key] {
            playAudition(from: url, voice: voice)
            return
        }
        guard auditionRendering == nil, !isGenerating else { return }

        // Same text pipeline as Generate so the comparison is honest.
        let rules = PronunciationDictionary.parse(pronunciationRulesText)
        var processed = InlineOverrides.apply(to: text)
        processed = PronunciationDictionary.apply(rules, to: processed)
        processed = NumberNormalizer.normalize(processed, preset: numberPreset)

        auditionRendering = voice
        let speedValue = Float(speed)

        switch voice {
        case .kokoro(let voiceID):
            guard let engine else {
                auditionRendering = nil
                return
            }
            Task.detached(priority: .userInitiated) {
                let samples = engine.synthesize(text: processed,
                                                voiceID: voiceID,
                                                speed: speedValue,
                                                progress: { _ in true })
                await MainActor.run {
                    self.finishAuditionRender(samples: samples,
                                              sampleRate: engine.sampleRate,
                                              key: key, voice: voice)
                }
            }
        case .pocket:
            let referenceURL = pocketVoiceURL
            let cachedPocketEngine = pocketEngine
            Task.detached(priority: .userInitiated) {
                do {
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
                    guard let referenceURL else {
                        throw KokoroEngineError.modelLoadFailed(
                            "no voice sample selected for Pocket TTS")
                    }
                    let reference = try ReferenceAudioLoader.load(url: referenceURL)
                    let samples = pocket.synthesize(
                        text: processed,
                        referenceAudio: reference.samples,
                        referenceSampleRate: reference.sampleRate,
                        speed: speedValue, progress: { _ in true })
                    await MainActor.run {
                        self.finishAuditionRender(samples: samples,
                                                  sampleRate: pocket.sampleRate,
                                                  key: key, voice: voice)
                    }
                } catch {
                    await MainActor.run {
                        self.auditionRendering = nil
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func finishAuditionRender(samples: [Float], sampleRate: Int,
                                      key: String, voice: AuditionVoice) {
        auditionRendering = nil
        guard !samples.isEmpty else { return }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kokoro-audition-\(key)")
                .appendingPathExtension("wav")
            try AudioExporter.write(
                samples: AudioProcessing.normalizePeak(samples),
                sampleRate: sampleRate, to: url, format: .wav)
            auditionCache[key] = url
            playAudition(from: url, voice: voice)
        } catch {
            errorMessage = "Could not render audition: \(error.localizedDescription)"
        }
    }

    private func playAudition(from url: URL, voice: AuditionVoice) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        auditionPlayerDelegate.onFinish = { [weak self] in
            self?.auditionPlaying = nil
        }
        player.delegate = auditionPlayerDelegate
        auditionPlayer = player
        auditionPlaying = voice
        player.play()
    }

    /// "Use This Voice" — adopts the audition side as the script's voice.
    func useAuditionVoice(_ voice: AuditionVoice) {
        switch voice {
        case .kokoro(let id):
            engineKind = .kokoro
            voiceID = id
        case .pocket:
            engineKind = .pocket
        }
    }

    func stopAudition() {
        auditionPlayer?.stop()
        auditionPlaying = nil
    }

    // MARK: - Sample script (#31)

    @AppStorage("hasSeededSampleScript") private var hasSeededSampleScript = false

    /// Pure guard so the seeding rule is testable: only an untouched app
    /// (never seeded, empty editor) gets the sample.
    nonisolated static func shouldSeedSample(hasSeeded: Bool,
                                             script: String) -> Bool {
        !hasSeeded
            && script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func seedSampleScriptIfFirstRun() {
        let shouldSeed = Self.shouldSeedSample(hasSeeded: hasSeededSampleScript,
                                               script: script)
        hasSeededSampleScript = true
        if shouldSeed { script = SampleScript.text }
    }

    /// Help-menu restore. Confirms first when it would replace user work.
    func requestRestoreSampleScript() {
        let current = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current != SampleScript.text {
            let alert = NSAlert()
            alert.messageText = "Replace the current script?"
            alert.informativeText = "The sample script will replace what's in the editor. This can't be undone."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        script = SampleScript.text
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

    /// `textOverride` generates a quick preview of just that text (e.g. the
    /// editor selection) with all the same processing.
    func generate(textOverride: String? = nil) {
        guard canGenerate || textOverride != nil, phase == .ready else { return }
        let flag = CancellationFlag()
        currentCancellation = flag
        phase = .generating(0)

        let kind = engineKind
        let isPreview = textOverride != nil
        let rules = PronunciationDictionary.parse(pronunciationRulesText)
        // Inline {word|sounds-like} overrides first (author-explicit wins),
        // then the dictionary, then number normalization.
        var processedScript = InlineOverrides.apply(to: textOverride ?? script)
        processedScript = PronunciationDictionary.apply(rules, to: processedScript)
        processedScript = NumberNormalizer.normalize(processedScript,
                                                     preset: numberPreset)
        let segments = ScriptSegmenter.segment(processedScript,
                                               pauses: pauseSettings,
                                               sentenceSplit: captionFormat != .off)
        let voice = voiceID
        let speakerMap = speakerVoices
        let speakerSpeedMap = speakerSpeeds
        let speedValue = Float(speed)
        let voiceReferenceURL = pocketVoiceURL
        let kokoroEngine = engine
        let cachedPocketEngine = pocketEngine

        Task.detached(priority: .userInitiated) {
            do {
                let plan = try await self.makeSynthesisPlan(
                    kind: kind, kokoroEngine: kokoroEngine,
                    cachedPocketEngine: cachedPocketEngine,
                    voiceReferenceURL: voiceReferenceURL, voice: voice,
                    speakerMap: speakerMap, speakerSpeedMap: speakerSpeedMap,
                    speedValue: speedValue)
                let (samples, results) = AppState.runSegments(
                    segments, plan: plan, flag: flag) { overall in
                    Task { @MainActor in
                        if case .generating = self.phase {
                            self.phase = .generating(overall)
                        }
                    }
                }
                await MainActor.run {
                    self.finishGeneration(samples: samples,
                                          sampleRate: plan.sampleRate,
                                          cancelled: flag.isCancelled,
                                          segmentResults: results,
                                          speed: Double(speedValue),
                                          isPreview: isPreview)
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

    // MARK: - Synthesis core (shared by Generate and module export)

    struct SynthesisPlan {
        let synthesize: (ScriptSegment, @escaping (Float) -> Bool) -> [Float]
        let sampleRate: Int
    }

    /// Builds the engine-specific segment synthesizer; loads Pocket lazily.
    private func makeSynthesisPlan(kind: TTSEngineKind,
                                   kokoroEngine: KokoroEngine?,
                                   cachedPocketEngine: PocketEngine?,
                                   voiceReferenceURL: URL?,
                                   voice: Int,
                                   speakerMap: [String: Int],
                                   speakerSpeedMap: [String: Double],
                                   speedValue: Float) async throws -> SynthesisPlan {
        switch kind {
        case .kokoro:
            guard let kokoroEngine else {
                throw KokoroEngineError.modelLoadFailed("Kokoro engine not loaded yet")
            }
            return SynthesisPlan(
                synthesize: { segment, onProgress in
                    let segmentVoice = segment.speaker
                        .flatMap { speakerMap[$0] } ?? voice
                    let speakerSpeed = segment.speaker
                        .flatMap { speakerSpeedMap[$0] }.map(Float.init) ?? speedValue
                    return kokoroEngine.synthesize(text: segment.text,
                                                   voiceID: segmentVoice,
                                                   speed: speakerSpeed * segment.speedMultiplier,
                                                   progress: onProgress)
                },
                sampleRate: kokoroEngine.sampleRate)
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
            return SynthesisPlan(
                synthesize: { segment, onProgress in
                    pocket.synthesize(text: segment.text,
                                      referenceAudio: reference.samples,
                                      referenceSampleRate: reference.sampleRate,
                                      speed: speedValue * segment.speedMultiplier,
                                      progress: onProgress)
                },
                sampleRate: pocket.sampleRate)
        }
    }

    /// Runs segments through a plan, splicing pauses; reports 0…1 progress.
    nonisolated static func runSegments(
        _ segments: [ScriptSegment], plan: SynthesisPlan, flag: CancellationFlag,
        onProgress: @escaping (Float) -> Void
    ) -> (samples: [Float], results: [(text: String, sampleCount: Int, pauseAfterMs: Int)]) {
        var allSamples: [Float] = []
        var segmentResults: [(text: String, sampleCount: Int, pauseAfterMs: Int)] = []
        let segmentCount = max(segments.count, 1)
        for (index, segment) in segments.enumerated() {
            if flag.isCancelled { break }
            // Silence-only segments (from bare [pause] markers).
            if segment.text.isEmpty {
                let silenceFrames = plan.sampleRate * segment.pauseAfterMs / 1000
                allSamples.append(contentsOf: [Float](repeating: 0, count: silenceFrames))
                segmentResults.append(("", 0, segment.pauseAfterMs))
                continue
            }
            let segmentSamples = plan.synthesize(segment) { progress in
                onProgress((Float(index) + progress) / Float(segmentCount))
                return !flag.isCancelled
            }
            allSamples.append(contentsOf: segmentSamples)
            segmentResults.append((segment.text, segmentSamples.count,
                                   segment.pauseAfterMs))
            if segment.pauseAfterMs > 0, !flag.isCancelled {
                let silenceFrames = plan.sampleRate * segment.pauseAfterMs / 1000
                allSamples.append(contentsOf: [Float](repeating: 0, count: silenceFrames))
            }
        }
        return (allSamples, segmentResults)
    }

    /// Splits the script at `## file:` markers and exports each module as
    /// its own audio (+ captions) file into the chosen folder.
    func exportModules() {
        let modules = ModuleSplitter.split(script)
        guard modules.count > 1, phase == .ready else { return }
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

        let flag = CancellationFlag()
        currentCancellation = flag
        phase = .generating(0)

        let kind = engineKind
        let rules = PronunciationDictionary.parse(pronunciationRulesText)
        let preset = numberPreset
        let pauses = pauseSettings
        let sentenceSplit = captionFormat != .off
        let voice = voiceID
        let speakerMap = speakerVoices
        let speakerSpeedMap = speakerSpeeds
        let speedValue = Float(speed)
        let voiceReferenceURL = pocketVoiceURL
        let kokoroEngine = engine
        let cachedPocketEngine = pocketEngine
        let format = exportFormat
        let captions = captionFormat
        let normalize = normalizeLoudness
        let loudnessTarget = loudnessPreset.targetLUFS(custom: customLoudnessLUFS)
        let padIn = leadInMs
        let padOut = leadOutMs

        Task.detached(priority: .userInitiated) {
            do {
                let plan = try await self.makeSynthesisPlan(
                    kind: kind, kokoroEngine: kokoroEngine,
                    cachedPocketEngine: cachedPocketEngine,
                    voiceReferenceURL: voiceReferenceURL, voice: voice,
                    speakerMap: speakerMap, speakerSpeedMap: speakerSpeedMap,
                    speedValue: speedValue)
                var written: [URL] = []
                for (moduleIndex, module) in modules.enumerated() {
                    if flag.isCancelled { break }
                    var text = InlineOverrides.apply(to: module.body)
                    text = PronunciationDictionary.apply(rules, to: text)
                    text = NumberNormalizer.normalize(text, preset: preset)
                    let segments = ScriptSegmenter.segment(
                        text, pauses: pauses, sentenceSplit: sentenceSplit)
                    let base = Float(moduleIndex) / Float(modules.count)
                    let span = 1 / Float(modules.count)
                    let (rawSamples, results) = AppState.runSegments(
                        segments, plan: plan, flag: flag) { progress in
                        let overall = base + progress * span
                        Task { @MainActor in
                            if case .generating = self.phase {
                                self.phase = .generating(overall)
                            }
                        }
                    }
                    if flag.isCancelled || rawSamples.isEmpty { continue }

                    var cues = CaptionWriter.buildCues(segments: results,
                                                       sampleRate: plan.sampleRate)
                    var samples = rawSamples
                    if normalize {
                        let trimOffset = Double(AudioProcessing.leadingTrimCount(
                            rawSamples, sampleRate: plan.sampleRate)) / Double(plan.sampleRate)
                        samples = AudioProcessing.finalize(samples: rawSamples,
                                                           sampleRate: plan.sampleRate)
                        cues = CaptionWriter.adjust(cues, offset: trimOffset,
                                                    totalDuration: Double(samples.count) / Double(plan.sampleRate))
                    }
                    if let loudnessTarget {
                        samples = LoudnessNormalizer.normalize(
                            samples: samples, sampleRate: plan.sampleRate,
                            targetLUFS: loudnessTarget)
                    }
                    samples = AudioProcessing.pad(samples, sampleRate: plan.sampleRate,
                                                  leadInMs: padIn, leadOutMs: padOut)
                    cues = CaptionWriter.adjust(cues, offset: -Double(padIn) / 1000,
                                                totalDuration: Double(samples.count) / Double(plan.sampleRate))

                    let safeName = module.name.replacingOccurrences(of: "/", with: "-")
                    let audioURL = folder.appendingPathComponent(safeName)
                        .appendingPathExtension(format.fileExtension)
                    try AudioExporter.write(samples: samples,
                                            sampleRate: plan.sampleRate,
                                            to: audioURL, format: format)
                    written.append(audioURL)
                    if captions != .off, !cues.isEmpty {
                        let captionText = captions == .vtt
                            ? CaptionWriter.vtt(cues) : CaptionWriter.srt(cues)
                        try captionText.write(
                            to: folder.appendingPathComponent(safeName)
                                .appendingPathExtension(captions.fileExtension),
                            atomically: true, encoding: .utf8)
                    }
                }
                let exported = written
                await MainActor.run {
                    self.phase = .ready
                    self.currentCancellation = nil
                    if self.revealInFinderAfterExport, let first = exported.first {
                        NSWorkspace.shared.activateFileViewerSelecting([first])
                    }
                }
            } catch {
                await MainActor.run {
                    self.phase = .ready
                    self.currentCancellation = nil
                    self.errorMessage = "Module export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func finishGeneration(samples rawSamples: [Float], sampleRate: Int,
                                  cancelled: Bool,
                                  segmentResults: [(text: String, sampleCount: Int, pauseAfterMs: Int)],
                                  speed: Double, isPreview: Bool = false) {
        phase = .ready
        currentCancellation = nil
        guard !cancelled, !rawSamples.isEmpty else { return }

        // Calibrate the duration estimate from what was actually produced.
        let spokenWords = segmentResults.reduce(0) {
            $0 + DurationEstimator.wordCount(of: $1.text)
        }
        let pauseSeconds = segmentResults.reduce(0.0) {
            $0 + Double($1.pauseAfterMs) / 1000
        }
        if let updated = DurationEstimator.calibrate(
            previousRate: calibratedWordsPerSecond, words: spokenWords,
            audioSeconds: Double(rawSamples.count) / Double(sampleRate),
            pauseSeconds: pauseSeconds, speed: speed) {
            calibratedWordsPerSecond = updated
        }

        let samples: [Float]
        var cues = CaptionWriter.buildCues(segments: segmentResults,
                                           sampleRate: sampleRate)
        if normalizeLoudness {
            // Trimming leading silence shifts everything earlier; keep the
            // cues in sync with what listeners actually hear.
            let trimOffset = Double(AudioProcessing.leadingTrimCount(
                rawSamples, sampleRate: sampleRate)) / Double(sampleRate)
            samples = AudioProcessing.finalize(samples: rawSamples,
                                               sampleRate: sampleRate)
            cues = CaptionWriter.adjust(cues, offset: trimOffset,
                                        totalDuration: Double(samples.count) / Double(sampleRate))
        } else {
            samples = rawSamples
        }

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kokoro-preview-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try AudioExporter.write(samples: samples, sampleRate: sampleRate,
                                    to: url, format: .wav)
            lastAudio = GeneratedAudio(samples: samples, sampleRate: sampleRate,
                                       previewWAV: url, cues: cues,
                                       isPreview: isPreview)
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
        let filename = AudioExporter.defaultFilename(
            for: script, includeTimestamp: timestampInFilenames)
        let destination = folder.appendingPathComponent(filename)
            .appendingPathExtension(exportFormat.fileExtension)
        do {
            var exportSamples = audio.samples
            if let target = loudnessPreset.targetLUFS(custom: customLoudnessLUFS) {
                exportSamples = LoudnessNormalizer.normalize(
                    samples: exportSamples, sampleRate: audio.sampleRate,
                    targetLUFS: target)
            }
            let paddedSamples = AudioProcessing.pad(exportSamples,
                                                    sampleRate: audio.sampleRate,
                                                    leadInMs: leadInMs,
                                                    leadOutMs: leadOutMs)
            try AudioExporter.write(samples: paddedSamples,
                                    sampleRate: audio.sampleRate,
                                    to: destination, format: exportFormat)
            if captionFormat != .off, !audio.cues.isEmpty {
                // Shift cues by the lead-in (negative offset = later).
                let shiftedCues = CaptionWriter.adjust(
                    audio.cues, offset: -Double(leadInMs) / 1000,
                    totalDuration: Double(paddedSamples.count) / Double(audio.sampleRate))
                let captionText = captionFormat == .vtt
                    ? CaptionWriter.vtt(shiftedCues)
                    : CaptionWriter.srt(shiftedCues)
                let captionURL = destination.deletingPathExtension()
                    .appendingPathExtension(captionFormat.fileExtension)
                try captionText.write(to: captionURL, atomically: true,
                                      encoding: .utf8)
            }
            if revealInFinderAfterExport {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Profiles

    func currentProfile() -> Profile {
        Profile(engineKind: engineKind.rawValue, voiceID: voiceID,
                pocketVoicePath: pocketVoicePath, speed: speed,
                paragraphPauseMs: paragraphPauseMs,
                sentencePauseMs: sentencePauseMs,
                clausePauseMs: clausePauseMs,
                headingPauseMs: headingPauseMs,
                pronunciationRules: pronunciationRulesText,
                captionFormat: captionFormat.rawValue,
                normalizeLoudness: normalizeLoudness,
                exportFormat: exportFormat.rawValue,
                speakerVoicesJSON: speakerVoicesJSON,
                numberPreset: numberPreset.rawValue,
                loudnessPreset: loudnessPreset.rawValue,
                customLoudnessLUFS: customLoudnessLUFS)
    }

    func apply(_ profile: Profile) {
        engineKind = TTSEngineKind(rawValue: profile.engineKind) ?? .kokoro
        voiceID = profile.voiceID
        pocketVoicePath = profile.pocketVoicePath
        speed = profile.speed
        paragraphPauseMs = profile.paragraphPauseMs
        sentencePauseMs = profile.sentencePauseMs
        clausePauseMs = profile.clausePauseMs
        headingPauseMs = profile.headingPauseMs
        pronunciationRulesText = profile.pronunciationRules
        captionFormat = CaptionFormat(rawValue: profile.captionFormat) ?? .off
        normalizeLoudness = profile.normalizeLoudness
        exportFormat = ExportFormat(rawValue: profile.exportFormat) ?? .wav
        speakerVoicesJSON = profile.speakerVoicesJSON
        numberPreset = profile.numberPreset
            .flatMap { NumberPreset(rawValue: $0) } ?? .natural
        loudnessPreset = profile.loudnessPreset
            .flatMap { LoudnessPreset(rawValue: $0) } ?? .lms
        customLoudnessLUFS = profile.customLoudnessLUFS ?? -16.0
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
