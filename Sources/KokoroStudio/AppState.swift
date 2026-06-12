import SwiftUI
import AppKit
import AVFoundation
import Combine
import UserNotifications

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
    case kokoro, supertonic
    var id: String { rawValue }
    var label: String { self == .kokoro ? "Kokoro" : "Supertonic" }
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
        /// The raw editor text this was generated from — follow-along
        /// highlighting and waveform markers align against it and bail
        /// when the script has been edited since (#35, #36).
        let sourceScript: String
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
    @AppStorage("speakerColors") var speakerColorsJSON = ""
    @AppStorage("speakerSymbols") var speakerSymbolsJSON = ""
    @AppStorage("marginSpeakerMode") var marginSpeakerMode = false
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
    /// Speaker name -> palette color index (see SpeakerIdentity). Overrides
    /// the auto-assigned color.
    var speakerColors: [String: Int] {
        get {
            guard let data = speakerColorsJSON.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: Int].self, from: data)
            else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                speakerColorsJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }

    /// Speaker name -> palette symbol index (see SpeakerIdentity). Overrides
    /// the auto-assigned symbol.
    var speakerSymbols: [String: Int] {
        get {
            guard let data = speakerSymbolsJSON.data(using: .utf8),
                  let map = try? JSONDecoder().decode([String: Int].self, from: data)
            else { return [:] }
            return map
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                speakerSymbolsJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }

    @AppStorage("engineKind") private var engineKindRaw = TTSEngineKind.kokoro.rawValue
    @AppStorage("supertonicVoiceID") var supertonicVoiceID
        = SupertonicVoiceCatalog.defaultVoiceID
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
    @AppStorage("followAlongHighlight") var followAlongHighlight = true
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
    private var supertonicEngine: SupertonicEngine?
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

    // MARK: - Script library (#34)

    @Published var documents: [ScriptDocumentMeta] = []
    @AppStorage("currentDocumentID") private var currentDocumentIDRaw = ""
    /// The active settings profile, shared with document metadata so each
    /// script remembers its sound. Previously view-local in ContentView.
    @AppStorage("currentProfileName") var currentProfileName = ""
    private var autosaveCancellable: AnyCancellable?

    var currentDocumentID: UUID? {
        get { UUID(uuidString: currentDocumentIDRaw) }
        set { currentDocumentIDRaw = newValue?.uuidString ?? "" }
    }

    @AppStorage("openTabIDs") private var openTabIDsJSON = ""

    /// Open script tabs, in display order. Persisted across launches.
    var openTabIDs: [UUID] {
        get {
            guard let data = openTabIDsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap(UUID.init(uuidString:))
        }
        set {
            if let data = try? JSONEncoder().encode(newValue.map(\.uuidString)) {
                openTabIDsJSON = String(data: data, encoding: .utf8) ?? ""
            }
        }
    }

    private var tabState: ScriptTabs.State {
        ScriptTabs.State(openIDs: openTabIDs, activeID: currentDocumentID)
    }

    /// Applies a ScriptTabs transition result: persists the open set and
    /// switches documents if the active tab changed.
    private func applyTabState(_ state: ScriptTabs.State) {
        openTabIDs = state.openIDs
        if let active = state.activeID, active != currentDocumentID {
            selectDocument(active)
        } else if state.activeID == nil {
            createDocument()
        }
    }

    func openTab(_ id: UUID) {
        applyTabState(ScriptTabs.open(id, in: tabState))
    }

    func closeTab(_ id: UUID) {
        applyTabState(ScriptTabs.close(id, in: tabState,
                                       library: documents.map(\.id)))
    }

    func closeOtherTabs(keeping id: UUID) {
        applyTabState(ScriptTabs.closeOthers(keeping: id, in: tabState))
    }

    func nextTab() { cycleTab(by: 1) }
    func previousTab() { cycleTab(by: -1) }

    private func cycleTab(by offset: Int) {
        let ids = openTabIDs
        guard ids.count > 1, let current = currentDocumentID,
              let index = ids.firstIndex(of: current) else { return }
        selectDocument(ids[(index + offset + ids.count) % ids.count])
    }

    /// Call once at launch, after sample-script seeding so a first run's
    /// sample becomes the first library item.
    func loadLibrary() {
        documents = DocumentStore.list()
        if documents.isEmpty {
            createDocument(text: script)
        } else if let id = currentDocumentID,
                  documents.contains(where: { $0.id == id }) {
            script = DocumentStore.loadText(id: id)
        } else {
            selectDocument(documents[0].id)
        }
        applyTabState(ScriptTabs.reconcile(tabState, library: documents.map(\.id)))
        startAutosave()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil,
            queue: .main) { [weak self] _ in
            Task { @MainActor in self?.saveCurrentDocumentNow() }
        }
    }

    private func startAutosave() {
        autosaveCancellable = $script
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveCurrentDocumentNow() }
    }

    func saveCurrentDocumentNow() {
        guard let id = currentDocumentID,
              var meta = documents.first(where: { $0.id == id }) else { return }
        if !meta.customTitle {
            meta.title = ScriptDocumentMeta.autoTitle(for: script)
        }
        meta.profileName = currentProfileName.isEmpty ? nil : currentProfileName
        meta.updatedAt = Date()
        try? DocumentStore.save(meta: meta, text: script)
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index] = meta
        }
    }

    func selectDocument(_ id: UUID) {
        guard id != currentDocumentID else { return }
        saveCurrentDocumentNow()
        guard let meta = documents.first(where: { $0.id == id }) else { return }
        currentDocumentID = id
        script = DocumentStore.loadText(id: id)
        // Switching scripts drops the old script's audio; regenerating is
        // cheap and a stale player invites exporting the wrong lesson.
        lastAudio = nil
        if let profileName = meta.profileName,
           let profile = ProfileStore.load(name: profileName) {
            currentProfileName = profileName
            apply(profile)
        }
    }

    @discardableResult
    func createDocument(text: String = "") -> ScriptDocumentMeta {
        saveCurrentDocumentNow()
        var meta = ScriptDocumentMeta(title: ScriptDocumentMeta.autoTitle(for: text))
        meta.profileName = currentProfileName.isEmpty ? nil : currentProfileName
        try? DocumentStore.save(meta: meta, text: text)
        documents.insert(meta, at: 0)
        currentDocumentID = meta.id
        openTabIDs = ScriptTabs.open(meta.id, in: tabState).openIDs
        script = text
        lastAudio = nil
        return meta
    }

    func renameDocument(_ id: UUID, to newTitle: String) {
        guard var meta = documents.first(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        meta.title = trimmed
        meta.customTitle = true
        meta.updatedAt = Date()
        try? DocumentStore.saveMeta(meta)
        if let index = documents.firstIndex(where: { $0.id == id }) {
            documents[index] = meta
        }
    }

    func duplicateDocument(_ id: UUID) {
        saveCurrentDocumentNow()
        guard let copy = DocumentStore.duplicate(id: id) else { return }
        documents.insert(copy, at: 0)
        openTab(copy.id)
    }

    /// Removes the library entry only — exported audio is never touched.
    func deleteDocument(_ id: UUID) {
        let next = ScriptTabs.close(id, in: tabState,
                                    library: documents.map(\.id))
        DocumentStore.delete(id: id)
        documents.removeAll { $0.id == id }
        if currentDocumentID == id {
            currentDocumentID = nil // force reload in selectDocument
        }
        applyTabState(next)
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
        case .supertonic(let voiceID):
            let cachedEngine = supertonicEngine
            Task.detached(priority: .userInitiated) {
                do {
                    let supertonic = try await self.loadSupertonicEngine(
                        cached: cachedEngine)
                    let samples = supertonic.synthesize(
                        text: processed, voiceID: voiceID,
                        speed: speedValue, progress: { _ in true })
                    await MainActor.run {
                        self.finishAuditionRender(samples: samples,
                                                  sampleRate: supertonic.sampleRate,
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

    /// Returns the cached Supertonic engine or loads it from the bundle.
    private nonisolated func loadSupertonicEngine(
        cached: SupertonicEngine?) async throws -> SupertonicEngine {
        if let cached { return cached }
        guard let directory = AppState.locateSupertonicDirectory() else {
            throw KokoroEngineError.modelLoadFailed(
                "Supertonic model folder not found in the app bundle")
        }
        let engine = try SupertonicEngine(modelDirectory: directory)
        await MainActor.run { self.supertonicEngine = engine }
        return engine
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
        case .supertonic(let id):
            engineKind = .supertonic
            supertonicVoiceID = id
        }
    }

    func stopAudition() {
        auditionPlayer?.stop()
        auditionPlaying = nil
    }

    // MARK: - macOS Services (#38)

    /// Text waiting for the engine when a service fires before the model
    /// finished loading (services can launch the app cold).
    private var pendingServiceSpeakText: String?

    func handleSpeakService(text: String) {
        let cleaned = ScriptImporter.normalizePlainText(text)
        guard phase == .ready else {
            pendingServiceSpeakText = cleaned
            return
        }
        // The audition path already renders one-off text with the current
        // voice and plays it without touching the editor.
        let voice: AuditionVoice = engineKind == .supertonic
            ? .supertonic(supertonicVoiceID) : .kokoro(voiceID)
        toggleAudition(text: String(cleaned.prefix(2000)), voice: voice)
    }

    func handleNewScriptService(text: String) {
        createDocument(text: ScriptImporter.normalizePlainText(text))
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call when phase flips to .ready (model loaded).
    func flushPendingServiceText() {
        if let pending = pendingServiceSpeakText {
            pendingServiceSpeakText = nil
            handleSpeakService(text: pending)
        }
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

    nonisolated static func locateSupertonicDirectory() -> URL? {
        locateResource(bundleName: "supertonic",
                       developmentPath: "vendor/supertonic",
                       marker: "voice.bin")
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
                    self.flushPendingServiceText()
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
        let rawSource = textOverride ?? script
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
        let kokoroEngine = engine
        let cachedSupertonicEngine = supertonicEngine
        let supertonicVoice = supertonicVoiceID

        Task.detached(priority: .userInitiated) {
            do {
                let plan = try await self.makeSynthesisPlan(
                    kind: kind, kokoroEngine: kokoroEngine,
                    cachedSupertonicEngine: cachedSupertonicEngine,
                    supertonicVoice: supertonicVoice, voice: voice,
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
                                          isPreview: isPreview,
                                          sourceScript: rawSource)
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

    /// Builds the engine-specific segment synthesizer; loads Supertonic lazily.
    private func makeSynthesisPlan(kind: TTSEngineKind,
                                   kokoroEngine: KokoroEngine?,
                                   cachedSupertonicEngine: SupertonicEngine?,
                                   supertonicVoice: Int,
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
                    // "Narrator" (and any unmapped speaker) intentionally has no
                    // speakerMap entry, so it falls through to the default voice.
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
        case .supertonic:
            let supertonic = try await loadSupertonicEngine(
                cached: cachedSupertonicEngine)
            return SynthesisPlan(
                synthesize: { segment, onProgress in
                    // One voice for the whole script; @Speaker: tags still
                    // honor per-speaker speeds.
                    let speakerSpeed = segment.speaker
                        .flatMap { speakerSpeedMap[$0] }.map(Float.init) ?? speedValue
                    return supertonic.synthesize(
                        text: segment.text, voiceID: supertonicVoice,
                        speed: speakerSpeed * segment.speedMultiplier,
                        progress: onProgress)
                },
                sampleRate: supertonic.sampleRate)
        }
    }

    /// Runs segments through a plan, splicing pauses; reports 0…1 progress.
    nonisolated static func runSegments(
        _ segments: [ScriptSegment], plan: SynthesisPlan, flag: CancellationFlag,
        onProgress: @escaping (Float) -> Void
    ) -> (samples: [Float], results: [(text: String, sampleCount: Int,
                                       pauseAfterMs: Int, speaker: String?)]) {
        var allSamples: [Float] = []
        var segmentResults: [(text: String, sampleCount: Int,
                              pauseAfterMs: Int, speaker: String?)] = []
        let segmentCount = max(segments.count, 1)
        for (index, segment) in segments.enumerated() {
            if flag.isCancelled { break }
            // Silence-only segments (from bare [pause] markers).
            if segment.text.isEmpty {
                let silenceFrames = plan.sampleRate * segment.pauseAfterMs / 1000
                allSamples.append(contentsOf: [Float](repeating: 0, count: silenceFrames))
                segmentResults.append(("", 0, segment.pauseAfterMs, segment.speaker))
                continue
            }
            let segmentSamples = plan.synthesize(segment) { progress in
                onProgress((Float(index) + progress) / Float(segmentCount))
                return !flag.isCancelled
            }
            allSamples.append(contentsOf: segmentSamples)
            segmentResults.append((segment.text, segmentSamples.count,
                                   segment.pauseAfterMs, segment.speaker))
            if segment.pauseAfterMs > 0, !flag.isCancelled {
                let silenceFrames = plan.sampleRate * segment.pauseAfterMs / 1000
                allSamples.append(contentsOf: [Float](repeating: 0, count: silenceFrames))
            }
        }
        return (allSamples, segmentResults)
    }

    // MARK: - Batch generation queue (#37)

    struct BatchItem: Identifiable, Equatable {
        let id: UUID
        let title: String
        var state: State

        enum State: Equatable {
            case queued
            case rendering(Float)
            case exported
            case failed(String)
        }
    }

    @Published var batchItems: [BatchItem] = []
    @Published var batchRunning = false
    @Published var showingBatchSheet = false
    private var batchCancelled = false
    private var batchActivity: NSObjectProtocol?

    nonisolated static func batchFilename(title: String,
                                          moduleName: String?) -> String {
        var stem = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        if stem.isEmpty { stem = "kokoro" }
        if let moduleName { stem += " - \(moduleName)" }
        return stem
    }

    func startBatch(documentIDs: [UUID]) {
        guard !batchRunning, phase == .ready, !documentIDs.isEmpty else { return }
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
        saveCurrentDocumentNow()
        batchItems = documentIDs.compactMap { id in
            documents.first { $0.id == id }
                .map { BatchItem(id: id, title: $0.title, state: .queued) }
        }
        batchCancelled = false
        batchRunning = true
        // A queued course render shouldn't die when the Mac idles.
        batchActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: "Batch audio generation")
        Task { await runBatch(folder: folder) }
    }

    func cancelBatch() {
        batchCancelled = true
        currentCancellation?.cancel()
    }

    func retryBatchItem(_ id: UUID) {
        guard !batchRunning,
              let index = batchItems.firstIndex(where: { $0.id == id }),
              !outputFolderPath.isEmpty else {
            return
        }
        batchItems[index].state = .queued
        batchCancelled = false
        batchRunning = true
        let folder = URL(fileURLWithPath: outputFolderPath)
        Task { await runBatch(folder: folder, only: [id]) }
    }

    private func runBatch(folder: URL, only: Set<UUID>? = nil) async {
        var exported = 0
        var failed = 0
        for index in batchItems.indices {
            if batchCancelled { break }
            let item = batchItems[index]
            if let only, !only.contains(item.id) { continue }
            if item.state == .exported { continue }
            batchItems[index].state = .rendering(0)
            do {
                try await renderDocument(id: item.id, folder: folder) { progress in
                    Task { @MainActor in
                        if self.batchItems.indices.contains(index) {
                            self.batchItems[index].state = .rendering(progress)
                        }
                    }
                }
                batchItems[index].state = .exported
                exported += 1
            } catch {
                batchItems[index].state = .failed(error.localizedDescription)
                failed += 1
            }
        }
        batchRunning = false
        if let activity = batchActivity {
            ProcessInfo.processInfo.endActivity(activity)
            batchActivity = nil
        }
        notifyBatchFinished(exported: exported, failed: failed,
                            cancelled: batchCancelled)
    }

    /// Renders one library document with ITS OWN profile (falling back to
    /// the current settings), honoring module-split markers.
    private func renderDocument(id: UUID, folder: URL,
                                onProgress: @escaping @Sendable (Float) -> Void) async throws {
        guard let meta = documents.first(where: { $0.id == id }) else {
            throw KokoroEngineError.modelLoadFailed("script not found in library")
        }
        let text = id == currentDocumentID ? script : DocumentStore.loadText(id: id)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KokoroEngineError.modelLoadFailed("script is empty")
        }

        // Settings come from the document's profile when it has one.
        let profile = meta.profileName.flatMap { ProfileStore.load(name: $0) }
        let kind = profile.flatMap { TTSEngineKind(rawValue: $0.engineKind) }
            ?? engineKind
        let voice = profile?.voiceID ?? voiceID
        let speedValue = Float(profile?.speed ?? speed)
        let rules = PronunciationDictionary.parse(
            profile?.pronunciationRules ?? pronunciationRulesText)
        let pauses = profile.map {
            PauseSettings(paragraphMs: $0.paragraphPauseMs,
                          sentenceMs: $0.sentencePauseMs,
                          clauseMs: $0.clausePauseMs,
                          headingMs: $0.headingPauseMs)
        } ?? pauseSettings
        let captions = profile.flatMap { CaptionFormat(rawValue: $0.captionFormat) }
            ?? captionFormat
        let normalize = profile?.normalizeLoudness ?? normalizeLoudness
        let format = profile.flatMap { ExportFormat(rawValue: $0.exportFormat) }
            ?? exportFormat
        let preset = profile?.numberPreset.flatMap { NumberPreset(rawValue: $0) }
            ?? numberPreset
        let loudnessTarget = (profile?.loudnessPreset
            .flatMap { LoudnessPreset(rawValue: $0) } ?? loudnessPreset)
            .targetLUFS(custom: profile?.customLoudnessLUFS ?? customLoudnessLUFS)
        let speakerMap: [String: Int] = profile.flatMap {
            guard let data = $0.speakerVoicesJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([String: Int].self, from: data)
        } ?? speakerVoices
        let supertonicVoice = profile?.supertonicVoiceID ?? supertonicVoiceID

        let flag = CancellationFlag()
        currentCancellation = flag
        let plan = try await makeSynthesisPlan(
            kind: kind, kokoroEngine: engine,
            cachedSupertonicEngine: supertonicEngine,
            supertonicVoice: supertonicVoice, voice: voice,
            speakerMap: speakerMap, speakerSpeedMap: speakerSpeeds,
            speedValue: speedValue)

        let modules = ModuleSplitter.split(text)
        let padIn = leadInMs
        let padOut = leadOutMs
        let title = meta.title

        try await Task.detached(priority: .userInitiated) {
            for (moduleIndex, module) in modules.enumerated() {
                if flag.isCancelled { break }
                var processed = InlineOverrides.apply(to: module.body)
                processed = PronunciationDictionary.apply(rules, to: processed)
                processed = NumberNormalizer.normalize(processed, preset: preset)
                let segments = ScriptSegmenter.segment(
                    processed, pauses: pauses, sentenceSplit: captions != .off)
                let base = Float(moduleIndex) / Float(modules.count)
                let span = 1 / Float(modules.count)
                let (rawSamples, results) = AppState.runSegments(
                    segments, plan: plan, flag: flag) { progress in
                    onProgress(base + progress * span)
                }
                if flag.isCancelled || rawSamples.isEmpty { continue }

                var cues = CaptionWriter.buildCues(segments: results,
                                                   sampleRate: plan.sampleRate)
                var samples = rawSamples
                if normalize {
                    let trimOffset = Double(AudioProcessing.leadingTrimCount(
                        rawSamples, sampleRate: plan.sampleRate))
                        / Double(plan.sampleRate)
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

                let filename = AppState.batchFilename(
                    title: title,
                    moduleName: modules.count > 1 ? module.name : nil)
                let audioURL = folder.appendingPathComponent(filename)
                    .appendingPathExtension(format.fileExtension)
                try AudioExporter.write(samples: samples,
                                        sampleRate: plan.sampleRate,
                                        to: audioURL, format: format)
                if captions != .off, !cues.isEmpty {
                    let captionText = captions == .vtt
                        ? CaptionWriter.vtt(cues) : CaptionWriter.srt(cues)
                    try captionText.write(
                        to: folder.appendingPathComponent(filename)
                            .appendingPathExtension(captions.fileExtension),
                        atomically: true, encoding: .utf8)
                }
            }
        }.value
        currentCancellation = nil
        if flag.isCancelled {
            throw KokoroEngineError.modelLoadFailed("cancelled")
        }
    }

    private func notifyBatchFinished(exported: Int, failed: Int,
                                     cancelled: Bool) {
        // UNUserNotificationCenter requires a real bundle; the bare dev
        // binary has none and would crash.
        guard Bundle.main.bundleIdentifier != nil else {
            NSSound.beep()
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = cancelled ? "Batch cancelled" : "Batch finished"
            content.body = "\(exported) exported"
                + (failed > 0 ? ", \(failed) failed" : "")
            center.add(UNNotificationRequest(
                identifier: UUID().uuidString, content: content,
                trigger: nil))
        }
    }

    // MARK: - Patch re-render (#11)

    /// True when the script has drifted from what the audio was made of
    /// — the precondition for offering Patch.
    var canPatch: Bool {
        guard let audio = lastAudio, !audio.isPreview,
              phase == .ready else { return false }
        return audio.sourceScript != script
    }

    /// Re-renders only the edited block and splices it into the existing
    /// audio and captions. Falls back to an explanatory error when the
    /// edit is too large or the cut points can't be trusted.
    func patchRegenerate() {
        guard let audio = lastAudio, canPatch else { return }
        let currentScript = script
        guard let patchPlan = ScriptPatcher.plan(
            oldScript: audio.sourceScript, newScript: currentScript,
            cues: audio.cues, sampleRate: audio.sampleRate,
            totalSamples: audio.samples.count,
            pauses: pauseSettings) else {
            errorMessage = "This edit is too large to patch — use Re-generate for the full script."
            return
        }

        let flag = CancellationFlag()
        currentCancellation = flag
        phase = .generating(0)

        let kind = engineKind
        let rules = PronunciationDictionary.parse(pronunciationRulesText)
        var processed = InlineOverrides.apply(to: patchPlan.replacementText)
        processed = PronunciationDictionary.apply(rules, to: processed)
        processed = NumberNormalizer.normalize(processed, preset: numberPreset)
        let segments = ScriptSegmenter.segment(processed, pauses: pauseSettings,
                                               sentenceSplit: captionFormat != .off)
        let voice = voiceID
        let speakerMap = speakerVoices
        let speakerSpeedMap = speakerSpeeds
        let speedValue = Float(speed)
        let kokoroEngine = engine
        let cachedSupertonicEngine = supertonicEngine
        let supertonicVoice = supertonicVoiceID
        let normalize = normalizeLoudness

        Task.detached(priority: .userInitiated) {
            do {
                let plan = try await self.makeSynthesisPlan(
                    kind: kind, kokoroEngine: kokoroEngine,
                    cachedSupertonicEngine: cachedSupertonicEngine,
                    supertonicVoice: supertonicVoice, voice: voice,
                    speakerMap: speakerMap, speakerSpeedMap: speakerSpeedMap,
                    speedValue: speedValue)
                let (rawChunk, results) = AppState.runSegments(
                    segments, plan: plan, flag: flag) { overall in
                    Task { @MainActor in
                        if case .generating = self.phase {
                            self.phase = .generating(overall)
                        }
                    }
                }
                await MainActor.run {
                    self.finishPatch(audio: audio, patchPlan: patchPlan,
                                     rawChunk: rawChunk, results: results,
                                     normalize: normalize,
                                     sourceScript: currentScript,
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

    private func finishPatch(audio: GeneratedAudio, patchPlan: PatchPlan,
                             rawChunk: [Float],
                             results: [(text: String, sampleCount: Int,
                                        pauseAfterMs: Int, speaker: String?)],
                             normalize: Bool, sourceScript: String,
                             cancelled: Bool) {
        phase = .ready
        currentCancellation = nil
        guard !cancelled else { return }

        // Match the chunk to the file's -1 dBFS target; no trim or fades
        // mid-file. An empty chunk is a pure deletion.
        var chunk = rawChunk
        if normalize, !chunk.isEmpty {
            chunk = AudioProcessing.normalizePeak(chunk)
        }
        if patchPlan.trailingPauseMs > 0, !chunk.isEmpty {
            chunk += [Float](repeating: 0,
                             count: audio.sampleRate * patchPlan.trailingPauseMs / 1000)
        }

        let spliced = ScriptPatcher.splice(old: audio.samples,
                                           cut: patchPlan.cutSampleRange,
                                           replacement: chunk)
        let newCues = CaptionWriter.buildCues(segments: results,
                                              sampleRate: audio.sampleRate)
        let insertAt = Double(patchPlan.cutSampleRange.lowerBound)
            / Double(audio.sampleRate)
        let timeDelta = Double(chunk.count - patchPlan.cutSampleRange.count)
            / Double(audio.sampleRate)
        let cues = ScriptPatcher.rebuildCues(
            old: audio.cues, replacedRange: patchPlan.replacedCueRange,
            newCues: newCues, insertAt: insertAt, timeDelta: timeDelta,
            totalDuration: Double(spliced.count) / Double(audio.sampleRate))

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("kokoro-preview-\(UUID().uuidString)")
                .appendingPathExtension("wav")
            try AudioExporter.write(samples: spliced,
                                    sampleRate: audio.sampleRate,
                                    to: url, format: .wav)
            lastAudio = GeneratedAudio(samples: spliced,
                                       sampleRate: audio.sampleRate,
                                       previewWAV: url, cues: cues,
                                       isPreview: false,
                                       sourceScript: sourceScript)
        } catch {
            errorMessage = "Could not prepare patched audio: \(error.localizedDescription)"
        }
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
        let kokoroEngine = engine
        let cachedSupertonicEngine = supertonicEngine
        let supertonicVoice = supertonicVoiceID
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
                    cachedSupertonicEngine: cachedSupertonicEngine,
                    supertonicVoice: supertonicVoice, voice: voice,
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
                                  segmentResults: [(text: String, sampleCount: Int,
                                                    pauseAfterMs: Int, speaker: String?)],
                                  speed: Double, isPreview: Bool = false,
                                  sourceScript: String = "") {
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
                                       isPreview: isPreview,
                                       sourceScript: sourceScript)
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
                speed: speed,
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
                customLoudnessLUFS: customLoudnessLUFS,
                supertonicVoiceID: supertonicVoiceID)
    }

    func apply(_ profile: Profile) {
        engineKind = TTSEngineKind(rawValue: profile.engineKind) ?? .kokoro
        voiceID = profile.voiceID
        supertonicVoiceID = profile.supertonicVoiceID
            ?? SupertonicVoiceCatalog.defaultVoiceID
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
