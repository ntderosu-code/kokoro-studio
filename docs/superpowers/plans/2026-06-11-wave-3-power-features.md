# Wave 3 Power Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement GitHub issues #11 (patch re-render: re-render one paragraph and splice into existing audio + captions), #37 (batch generation queue), and #38 (macOS Services integration).

**Architecture:** Patch re-render builds on wave 2's `CueAlignment` + `GeneratedAudio.sourceScript`: a pure `ScriptPatcher` computes a line-diff, maps the changed block to cue/sample boundaries, and produces a splice plan; AppState orchestrates synthesis of just the changed text and splices samples + cues. Batch queue reuses `makeSynthesisPlan`/`runSegments` per library document with that document's profile. Services are an `NSServices` Info.plist entry (in build-app.sh) plus an `@objc` provider that forwards pasteboard text into AppState.

**Tech Stack:** Swift / SwiftUI / AppKit, UserNotifications (guarded — crashes without a bundle), XCTest. No new dependencies.

**Constraints:**
- DO NOT push, tag, bump version, or run release scripts. Local commits only on branch `wave-3` (off `wave-2`).
- Test command: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter <ClassName>`
- Regex literals: always `#/.../#`. SourceKit diagnostics stale; trust `swift build`.
- Services can only be verified from the assembled .app (LaunchServices registration), not the bare binary.

---

### Task 1: ScriptPatcher — diff and patch plan (#11)

**Files:**
- Create: `Sources/KokoroStudio/ScriptPatcher.swift`
- Test: `Tests/KokoroStudioTests/ScriptPatcherTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class ScriptPatcherTests: XCTestCase {
    // MARK: changedLineRange

    func testDiffMiddleChange() {
        let old = ["a", "b", "c", "d"]
        let new = ["a", "X", "c", "d"]
        let diff = ScriptPatcher.changedLineRange(old: old, new: new)
        XCTAssertEqual(diff?.old, 1..<2)
        XCTAssertEqual(diff?.new, 1..<2)
    }

    func testDiffInsertion() {
        let diff = ScriptPatcher.changedLineRange(old: ["a", "b"],
                                                  new: ["a", "NEW", "b"])
        XCTAssertEqual(diff?.old, 1..<1)
        XCTAssertEqual(diff?.new, 1..<2)
    }

    func testDiffDeletion() {
        let diff = ScriptPatcher.changedLineRange(old: ["a", "b", "c"],
                                                  new: ["a", "c"])
        XCTAssertEqual(diff?.old, 1..<2)
        XCTAssertEqual(diff?.new, 1..<1)
    }

    func testDiffIdenticalIsNil() {
        XCTAssertNil(ScriptPatcher.changedLineRange(old: ["a"], new: ["a"]))
    }

    func testDiffChangeAtEnds() {
        XCTAssertEqual(ScriptPatcher.changedLineRange(
            old: ["a", "b"], new: ["X", "b"])?.old, 0..<1)
        XCTAssertEqual(ScriptPatcher.changedLineRange(
            old: ["a", "b"], new: ["a", "X"])?.old, 1..<2)
    }

    // MARK: plan

    /// 3 sentences, one per line, 1s of audio each at 1000 Hz "sample
    /// rate" with cues exactly on the second marks.
    private let oldScript = "First line here.\nSecond line here.\nThird line here."
    private let cues = [CaptionCue(start: 0.0, end: 0.9, text: "First line here."),
                        CaptionCue(start: 1.0, end: 1.9, text: "Second line here."),
                        CaptionCue(start: 2.0, end: 2.9, text: "Third line here.")]

    func testPlanMiddleLineEdit() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\nA changed middle line.\nThird line here.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.replacementText, "A changed middle line.")
        XCTAssertEqual(plan?.replacedCueRange, 1..<2)
        // Cut from the start of cue 1 to the start of cue 2 (the old
        // trailing pause is cut too and re-appended fresh).
        XCTAssertEqual(plan?.cutSampleRange, 1000..<2000)
        XCTAssertEqual(plan?.trailingPauseMs, PauseSettings().paragraphMs)
    }

    func testPlanEditAtEndHasNoTrailingPause() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\nSecond line here.\nA new ending.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.cutSampleRange, 2000..<2900)
        XCTAssertEqual(plan?.trailingPauseMs, 0)
    }

    func testPlanHeadingReplacementUsesHeadingPause() {
        let plan = ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "First line here.\n# Section Two\nThird line here.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.trailingPauseMs, PauseSettings().headingMs)
    }

    func testPlanPrependsSpeakerContext() {
        let old = "@Maya: Hello there.\nNice to meet you.\nGoodbye now."
        let speakerCues = [CaptionCue(start: 0, end: 0.9, text: "Hello there."),
                           CaptionCue(start: 1, end: 1.9, text: "Nice to meet you."),
                           CaptionCue(start: 2, end: 2.9, text: "Goodbye now.")]
        let plan = ScriptPatcher.plan(
            oldScript: old,
            newScript: "@Maya: Hello there.\nGreat to meet you.\nGoodbye now.",
            cues: speakerCues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings())
        XCTAssertEqual(plan?.replacementText, "@Maya:\nGreat to meet you.")
    }

    func testPlanRejectsWholesaleRewrite() {
        XCTAssertNil(ScriptPatcher.plan(
            oldScript: oldScript,
            newScript: "Totally.\nDifferent.\nScript.\nNow longer.",
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings()))
    }

    func testPlanIdenticalIsNil() {
        XCTAssertNil(ScriptPatcher.plan(
            oldScript: oldScript, newScript: oldScript,
            cues: cues, sampleRate: 1000, totalSamples: 2900,
            pauses: PauseSettings()))
    }
}
```

- [ ] **Step 2: Run `--filter ScriptPatcherTests`, expect compile failure.**

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Everything needed to re-render one edited block and splice it into
/// existing audio (#11).
struct PatchPlan: Equatable {
    /// New text to synthesize, including a speaker-context line when the
    /// edit sits inside dialogue.
    let replacementText: String
    /// Sample range of the existing audio to remove.
    let cutSampleRange: Range<Int>
    /// Indices into the old cue array being replaced (may be empty for
    /// pure insertions).
    let replacedCueRange: Range<Int>
    /// Silence to append after the new chunk; 0 when the patch reaches
    /// the end of the audio.
    let trailingPauseMs: Int
}

/// Computes what to re-render after an edit, by diffing the script the
/// audio was generated from against the current script and mapping the
/// changed block onto cue/sample boundaries via CueAlignment. Pure logic
/// — synthesis and splicing orchestration live in AppState.
enum ScriptPatcher {
    /// Line-level diff via common prefix/suffix. nil when equal.
    static func changedLineRange(old: [String], new: [String])
        -> (old: Range<Int>, new: Range<Int>)? {
        guard old != new else { return nil }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        return (prefix..<(old.count - suffix), prefix..<(new.count - suffix))
    }

    static func plan(oldScript: String, newScript: String,
                     cues: [CaptionCue], sampleRate: Int, totalSamples: Int,
                     pauses: PauseSettings) -> PatchPlan? {
        let oldLines = oldScript.components(separatedBy: "\n")
        let newLines = newScript.components(separatedBy: "\n")
        guard let changed = changedLineRange(old: oldLines, new: newLines),
              !cues.isEmpty else { return nil }

        // A wholesale rewrite patches worse than it regenerates.
        if newLines.count > 2,
           changed.new.count * 2 > newLines.count { return nil }

        // Char span (UTF-16, matching CueAlignment's NSRanges) of the
        // changed old lines.
        var offsets: [Int] = [0]
        for line in oldLines {
            offsets.append(offsets.last! + (line as NSString).length + 1)
        }
        let changedStart = offsets[changed.old.lowerBound]
        let changedEnd = changed.old.isEmpty
            ? changedStart
            : offsets[changed.old.upperBound] - 1 // exclude the newline

        let aligned = CueAlignment.align(cues: cues.map(\.text),
                                         script: oldScript)

        // Cues whose aligned range intersects the changed span.
        var intersecting: [Int] = []
        for (index, range) in aligned.enumerated() {
            guard let range else { continue }
            let rangeEnd = range.location + range.length
            if range.location < changedEnd, rangeEnd > changedStart {
                intersecting.append(index)
            }
        }

        let replacedCueRange: Range<Int>
        if let first = intersecting.first, let last = intersecting.last {
            replacedCueRange = first..<(last + 1)
        } else {
            // Pure insertion (or change in non-audible lines): splice at
            // the first cue that starts after the change.
            let insertIndex = aligned.enumerated().first { _, range in
                guard let range else { return false }
                return range.location >= changedStart
            }?.offset ?? cues.count
            replacedCueRange = insertIndex..<insertIndex
        }

        // Unaligned cues at the boundaries mean the cut points can't be
        // trusted — bail to full regeneration.
        let guardLow = max(0, replacedCueRange.lowerBound - 1)
        let guardHigh = min(cues.count, replacedCueRange.upperBound + 1)
        for index in guardLow..<guardHigh where aligned[index] == nil {
            return nil
        }

        let cutStart = replacedCueRange.isEmpty
            ? (replacedCueRange.lowerBound < cues.count
                ? sampleIndex(cues[replacedCueRange.lowerBound].start,
                              rate: sampleRate)
                : totalSamples)
            : sampleIndex(cues[replacedCueRange.lowerBound].start,
                          rate: sampleRate)
        let cutEnd = replacedCueRange.upperBound < cues.count
            ? sampleIndex(cues[replacedCueRange.upperBound].start,
                          rate: sampleRate)
            : totalSamples
        guard cutStart <= cutEnd, cutEnd <= totalSamples else { return nil }

        // Speaker context: an edit inside dialogue must keep its voice,
        // so prepend the speaker active at the start of the change.
        var replacement = newLines[changed.new].joined(separator: "\n")
        let changedHasOwnTag = newLines[changed.new].first?
            .trimmingCharacters(in: .whitespaces).hasPrefix("@") ?? false
        if !changedHasOwnTag, !replacement.isEmpty,
           let speaker = activeSpeaker(inLinesBefore: changed.new.lowerBound,
                                       of: newLines) {
            replacement = "@\(speaker):\n" + replacement
        }

        // The cut removed the old trailing pause; the new chunk re-adds
        // one sized by its own last line — unless the patch runs to the
        // end of the audio, where generation never pauses either.
        let trailingPauseMs: Int
        if replacedCueRange.upperBound < cues.count {
            let lastLine = newLines[changed.new]
                .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            trailingPauseMs = (lastLine?.trimmingCharacters(in: .whitespaces)
                .hasPrefix("#") ?? false) ? pauses.headingMs : pauses.paragraphMs
        } else {
            trailingPauseMs = 0
        }

        return PatchPlan(replacementText: replacement,
                         cutSampleRange: cutStart..<cutEnd,
                         replacedCueRange: replacedCueRange,
                         trailingPauseMs: trailingPauseMs)
    }

    static func splice(old: [Float], cut: Range<Int>,
                       replacement: [Float]) -> [Float] {
        Array(old[..<cut.lowerBound]) + replacement + Array(old[cut.upperBound...])
    }

    /// Old cues before the patch, the new chunk's cues shifted to the
    /// splice point, and the old cues after shifted by the length delta.
    static func rebuildCues(old: [CaptionCue], replacedRange: Range<Int>,
                            newCues: [CaptionCue], insertAt: Double,
                            timeDelta: Double,
                            totalDuration: Double) -> [CaptionCue] {
        let before = Array(old[..<replacedRange.lowerBound])
        let inserted = newCues.map {
            CaptionCue(start: $0.start + insertAt, end: $0.end + insertAt,
                       text: $0.text)
        }
        let after = old[replacedRange.upperBound...].map {
            CaptionCue(start: $0.start + timeDelta,
                       end: min(totalDuration, $0.end + timeDelta),
                       text: $0.text)
        }
        return (before + inserted + after).filter { $0.end > $0.start }
    }

    private static func sampleIndex(_ seconds: Double, rate: Int) -> Int {
        Int((seconds * Double(rate)).rounded())
    }

    /// Last `@Name:` tag in the lines before `index` (segmenter carries
    /// speakers forward the same way).
    private static func activeSpeaker(inLinesBefore index: Int,
                                      of lines: [String]) -> String? {
        for line in lines[..<index].reversed() {
            if let match = line.trimmingCharacters(in: .whitespaces)
                .firstMatch(of: #/^@([\w ]+):/#) {
                return String(match.1).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run, expect 10 PASS.** Watch `testPlanMiddleLineEdit`: cut end is the start of the FIRST cue after the replaced range (2000), not the end of the replaced cue.

- [ ] **Step 5: Add splice/rebuild tests + verify**

```swift
    func testSplice() {
        XCTAssertEqual(ScriptPatcher.splice(old: [1, 2, 3, 4, 5], cut: 1..<3,
                                            replacement: [9, 9, 9]),
                       [1, 9, 9, 9, 4, 5])
    }

    func testRebuildCuesShiftsTail() {
        let old = [CaptionCue(start: 0, end: 1, text: "a"),
                   CaptionCue(start: 2, end: 3, text: "b"),
                   CaptionCue(start: 4, end: 5, text: "c")]
        let rebuilt = ScriptPatcher.rebuildCues(
            old: old, replacedRange: 1..<2,
            newCues: [CaptionCue(start: 0, end: 1.5, text: "B long")],
            insertAt: 2, timeDelta: 0.5, totalDuration: 6)
        XCTAssertEqual(rebuilt, [CaptionCue(start: 0, end: 1, text: "a"),
                                 CaptionCue(start: 2, end: 3.5, text: "B long"),
                                 CaptionCue(start: 4.5, end: 5.5, text: "c")])
    }
```

- [ ] **Step 6: Commit** `feat: ScriptPatcher — diff, patch plan, splice, cue rebuild (#11)`

---

### Task 2: AppState.patchRegenerate + Patch button (#11)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift`
- Modify: `Sources/KokoroStudio/Views/PlayerBar.swift`

- [ ] **Step 1: AppState orchestration** (new section after Generation)

```swift
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
        let voiceReferenceURL = pocketVoiceURL
        let kokoroEngine = engine
        let cachedPocketEngine = pocketEngine
        let normalize = normalizeLoudness

        Task.detached(priority: .userInitiated) {
            do {
                let plan = try await self.makeSynthesisPlan(
                    kind: kind, kokoroEngine: kokoroEngine,
                    cachedPocketEngine: cachedPocketEngine,
                    voiceReferenceURL: voiceReferenceURL, voice: voice,
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
                             results: [(text: String, sampleCount: Int, pauseAfterMs: Int)],
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
```

- [ ] **Step 2: Patch button in PlayerBar** — after the Re-generate button:

```swift
            if state.canPatch {
                Button("Patch") {
                    player.stop()
                    state.patchRegenerate()
                }
                .secondaryActionButtonStyle()
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .help("Re-render only the edited lines and splice them into the existing audio (⌥⌘↩)")
            }
```

- [ ] **Step 3: `swift build` + ScriptPatcherTests still green. Commit** `feat: patch re-render — splice edited block into existing audio (#11)`

---

### Task 3: Batch queue engine in AppState (#37)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift`
- Test: `Tests/KokoroStudioTests/BatchSupportTests.swift` (filename sanitizing)

- [ ] **Step 1: Failing test for the one pure helper**

```swift
import XCTest
@testable import KokoroStudio

final class BatchSupportTests: XCTestCase {
    func testBatchFilename() {
        XCTAssertEqual(AppState.batchFilename(title: "Lesson 2: Intro/Review",
                                              moduleName: nil),
                       "Lesson 2- Intro-Review")
        XCTAssertEqual(AppState.batchFilename(title: "Course",
                                              moduleName: "lesson-2"),
                       "Course - lesson-2")
        XCTAssertEqual(AppState.batchFilename(title: "  ", moduleName: nil),
                       "kokoro")
    }
}
```

- [ ] **Step 2: AppState batch section**

```swift
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
        // A queued course render shouldn't die when the lid stays open
        // but the Mac idles.
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
              let index = batchItems.firstIndex(where: { $0.id == id }) else {
            return
        }
        batchItems[index].state = .queued
        startBatchRetry(ids: [id])
    }

    private func startBatchRetry(ids: [UUID]) {
        guard !outputFolderPath.isEmpty else { return }
        let folder = URL(fileURLWithPath: outputFolderPath)
        batchCancelled = false
        batchRunning = true
        Task { await runBatch(folder: folder, only: Set(ids)) }
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
                                onProgress: @escaping (Float) -> Void) async throws {
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
        let referenceURL: URL? = profile.map {
            $0.pocketVoicePath.isEmpty ? pocketVoiceURL
                : URL(fileURLWithPath: $0.pocketVoicePath)
        } ?? pocketVoiceURL

        let flag = CancellationFlag()
        currentCancellation = flag
        let plan = try await makeSynthesisPlan(
            kind: kind, kokoroEngine: engine,
            cachedPocketEngine: pocketEngine,
            voiceReferenceURL: referenceURL, voice: voice,
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
        await MainActor.run { self.currentCancellation = nil }
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
```

plus `import UserNotifications` at the top of AppState.swift.

- [ ] **Step 3: `swift build` + BatchSupportTests green. Commit** `feat: batch queue engine — per-document profiles, modules, retry (#37)`

---

### Task 4: Batch queue sheet UI (#37)

**Files:**
- Create: `Sources/KokoroStudio/Views/BatchQueueView.swift`
- Modify: `Sources/KokoroStudio/Views/SidebarView.swift` (entry button)
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (sheet presentation)

- [ ] **Step 1: `BatchQueueView.swift`** — fixed header / scrollable list / fixed footer:

```swift
import SwiftUI

/// Pick library scripts, render and export them unattended (#37).
struct BatchQueueView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()

    private var settingsSummary: String {
        var parts = [state.exportFormat.label,
                     state.loudnessPreset.label]
        if state.captionFormat != .off {
            parts.append("\(state.captionFormat.label) captions")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch Export").font(.headline)
                Text(state.batchRunning
                     ? "Rendering — you can close this window; the queue keeps going."
                     : "Each script renders with its own profile. Export settings: \(settingsSummary).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            if state.batchRunning || !state.batchItems.isEmpty {
                List(state.batchItems) { item in
                    HStack {
                        statusIcon(item.state)
                        Text(item.title).lineLimit(1)
                        Spacer()
                        statusDetail(item)
                    }
                }
            } else {
                List(state.documents, selection: $selection) { doc in
                    Text(doc.title).tag(doc.id)
                }
                .environment(\.editMode, .constant(.active))
            }

            Divider()

            HStack {
                if state.batchRunning {
                    Button("Cancel Batch", role: .destructive) {
                        state.cancelBatch()
                    }
                } else if !state.batchItems.isEmpty {
                    Button("New Batch") {
                        state.batchItems = []
                        selection = []
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                if !state.batchRunning, state.batchItems.isEmpty {
                    Button("Start (\(selection.count))") {
                        state.startBatch(documentIDs: state.documents
                            .map(\.id).filter { selection.contains($0) })
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || state.phase != .ready)
                }
            }
            .padding(12)
        }
        .frame(width: 440, height: 420)
    }

    @ViewBuilder
    private func statusIcon(_ itemState: AppState.BatchItem.State) -> some View {
        switch itemState {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .rendering:
            ProgressView().controlSize(.small)
        case .exported:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func statusDetail(_ item: AppState.BatchItem) -> some View {
        switch item.state {
        case .rendering(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .failed(let message):
            HStack(spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") { state.retryBatchItem(item.id) }
                    .controlSize(.small)
                    .disabled(state.batchRunning)
            }
        default:
            EmptyView()
        }
    }
}
```

Note: macOS `List(selection:)` multi-select works without editMode — drop the `.environment(\.editMode, …)` line if it fails to compile on macOS (it's iOS API).

- [ ] **Step 2: Entries.** SidebarView Scripts section, after "New Script":

```swift
                Button("Batch Export…", systemImage: "square.stack.3d.up") {
                    state.showingBatchSheet = true
                }
                .disabled(state.phase != .ready && !state.batchRunning)
                .help("Render and export several scripts unattended")
```

ContentView, after the import sheet: `.sheet(isPresented: $state.showingBatchSheet) { BatchQueueView() }`

- [ ] **Step 3: `swift build`. Commit** `feat: batch export sheet with per-item status and retry (#37)`

---

### Task 5: Services provider + handlers (#38)

**Files:**
- Create: `Sources/KokoroStudio/ServiceProvider.swift`
- Modify: `Sources/KokoroStudio/AppState.swift` (handlers + pending text)
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift` (registration)

- [ ] **Step 1: `ServiceProvider.swift`**

```swift
import AppKit

/// Receives macOS Services invocations (#38). Methods are looked up by
/// name from the NSServices entries in Info.plist; the bare binary has
/// no Info.plist, so Services only function in the assembled .app.
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()
    @MainActor weak var state: AppState?

    @objc func speakText(_ pasteboard: NSPasteboard, userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text in the selection."
            return
        }
        Task { @MainActor in
            self.state?.handleSpeakService(text: text)
        }
    }

    @objc func newScriptFromText(_ pasteboard: NSPasteboard, userData: String,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text in the selection."
            return
        }
        Task { @MainActor in
            self.state?.handleNewScriptService(text: text)
        }
    }
}
```

- [ ] **Step 2: AppState handlers** (new section near audition)

```swift
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
        let voice: AuditionVoice = engineKind == .pocket
            ? .pocket : .kokoro(voiceID)
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
```

In `loadModel()`, after `self.phase = .ready` add `self.flushPendingServiceText()`.

- [ ] **Step 3: Registration** in `KokoroStudioApp` window `.task`, after `state.loadLibrary()`:

```swift
                    ServiceProvider.shared.state = state
                    NSApp.servicesProvider = ServiceProvider.shared
                    NSUpdateDynamicServices()
```

- [ ] **Step 4: `swift build`. Commit** `feat: Services provider — Speak / New Script from any app (#38)`

---

### Task 6: NSServices entries in Info.plist (#38)

**Files:**
- Modify: `scripts/build-app.sh` (Info.plist heredoc)

- [ ] **Step 1:** Inside the `<dict>` of the Info.plist heredoc, before `</dict></plist>`:

```xml
  <key>NSServices</key><array>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>Speak with Kokoro Studio</string></dict>
      <key>NSMessage</key><string>speakText</string>
      <key>NSPortName</key><string>Kokoro Studio</string>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string></array>
    </dict>
    <dict>
      <key>NSMenuItem</key><dict><key>default</key><string>New Kokoro Studio Script</string></dict>
      <key>NSMessage</key><string>newScriptFromText</string>
      <key>NSPortName</key><string>Kokoro Studio</string>
      <key>NSSendTypes</key><array><string>NSStringPboardType</string></array>
    </dict>
  </array>
```

- [ ] **Step 2: Commit** `feat: register Speak / New Script services in Info.plist (#38)`

---

### Task 7: Full verification

- [ ] **Step 1:** `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test` — all green.
- [ ] **Step 2:** `./scripts/build-app.sh` — app assembles (required for Services registration).
- [ ] **Step 3:** Report manual smoke checklist: patch a middle sentence after generating and listen across the splice points; batch-export two scripts with different profiles; check Services menu from TextEdit after launching the built app once (may need `/System/Library/CoreServices/pbs -update`). Do NOT push or ship.
