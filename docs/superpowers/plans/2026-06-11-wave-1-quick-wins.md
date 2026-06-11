# Wave 1 Quick Wins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement GitHub issues #29 (dictionary CSV import/export), #30 (loudness target presets), #31 (first-run sample script), and #32 (A/B voice audition) for Kokoro Studio.

**Architecture:** Each feature gets a small pure-logic file (testable without the TTS models) plus thin UI wiring into the existing SwiftUI views. Pure logic is TDD'd; UI changes are verified with `swift build` and a manual smoke check at the end.

**Tech Stack:** Swift / SwiftUI (macOS), XCTest, SwiftPM. No new dependencies.

**Constraints:**
- DO NOT push, tag, bump the version, or run release scripts. Local commits only — the user decides when to ship.
- Test command (engine tests need the dylibs on path): `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter <ClassName>`
- Code style: match the repo — `enum` namespaces for pure logic, doc comments explain *why*, 4-space indent, ~80-col wrap.

---

### Task 1: DictionaryCSV core logic (#29)

**Files:**
- Create: `Sources/KokoroStudio/DictionaryCSV.swift`
- Test: `Tests/KokoroStudioTests/DictionaryCSVTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class DictionaryCSVTests: XCTestCase {
    func testExportFormats() {
        let csv = DictionaryCSV.export(rulesText: """
        kokoro = koh koh roh
        APA = @letters
        NASA = @word
        IEP = @letters-first
        """)
        XCTAssertEqual(csv, """
        term,replacement,mode
        kokoro,koh koh roh,replace
        APA,,letters
        NASA,,word
        IEP,,letters-first

        """)
    }

    func testQuotingFieldsWithCommas() {
        let csv = DictionaryCSV.export(rulesText: "Smith, Jr. = smith junior")
        XCTAssertTrue(csv.contains("\"Smith, Jr.\",smith junior,replace"))
    }

    func testRoundTrip() {
        let original = """
        kokoro = koh koh roh
        APA = @letters
        NASA = @word
        IEP = @letters-first
        """
        let rules = DictionaryCSV.parse(DictionaryCSV.export(rulesText: original))
        XCTAssertEqual(rules, PronunciationDictionary.parse(original))
    }

    func testParseSkipsHeaderAndJunk() {
        let rules = DictionaryCSV.parse("""
        term,replacement,mode
        ,
        APA,,letters
        bogus,,unknown-mode
        """)
        XCTAssertEqual(rules, [PronunciationRule(word: "APA", kind: .letters)])
    }

    func testParseQuotedField() {
        let rules = DictionaryCSV.parse("\"Smith, Jr.\",smith junior,replace")
        XCTAssertEqual(rules, [PronunciationRule(word: "Smith, Jr.",
                                                 kind: .replace("smith junior"))])
    }

    func testMergeAppendsNewTerms() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "CSWE", kind: .letters)],
            into: "# my rules\nAPA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText,
                       "# my rules\nAPA = @letters\nCSWE = @letters\n")
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertTrue(result.conflictTerms.isEmpty)
    }

    func testMergeConflictKeepExisting() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .word)],
            into: "APA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText, "APA = @letters\n")
        XCTAssertEqual(result.conflictTerms, ["APA"])
    }

    func testMergeConflictUseImported() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .word)],
            into: "APA = @letters\n", preferImported: true)
        XCTAssertEqual(result.mergedText, "APA = @word\n")
    }

    func testMergeIdenticalRuleIsNeitherConflictNorAdd() {
        let result = DictionaryCSV.merge(
            imported: [PronunciationRule(word: "APA", kind: .letters)],
            into: "APA = @letters\n", preferImported: false)
        XCTAssertEqual(result.mergedText, "APA = @letters\n")
        XCTAssertTrue(result.conflictTerms.isEmpty)
        XCTAssertEqual(result.addedCount, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter DictionaryCSVTests`
Expected: compile error — `DictionaryCSV` not defined.

- [ ] **Step 3: Implement `DictionaryCSV`**

```swift
import Foundation

/// CSV import/export for the pronunciation dictionary (#29), so course
/// teams can share one set of pronunciations across machines.
/// Columns: term,replacement,mode — replacement is empty unless mode is
/// "replace". Minimal RFC-4180: fields with commas/quotes/newlines are
/// quoted, `""` escapes a quote.
enum DictionaryCSV {
    static let header = "term,replacement,mode"

    struct MergeResult: Equatable {
        var mergedText: String
        var addedCount: Int
        var conflictTerms: [String]
    }

    static func export(rulesText: String) -> String {
        var lines = [header]
        for rule in PronunciationDictionary.parse(rulesText) {
            switch rule.kind {
            case .replace(let replacement):
                lines.append("\(field(rule.word)),\(field(replacement)),replace")
            case .letters:
                lines.append("\(field(rule.word)),,letters")
            case .word:
                lines.append("\(field(rule.word)),,word")
            case .lettersFirst:
                lines.append("\(field(rule.word)),,letters-first")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ csv: String) -> [PronunciationRule] {
        var rules: [PronunciationRule] = []
        for line in csv.components(separatedBy: .newlines) {
            let fields = splitCSVLine(line)
            guard fields.count >= 3 else { continue }
            let term = fields[0].trimmingCharacters(in: .whitespaces)
            let replacement = fields[1].trimmingCharacters(in: .whitespaces)
            let mode = fields[2].trimmingCharacters(in: .whitespaces).lowercased()
            guard !term.isEmpty, term.lowercased() != "term" else { continue }
            switch mode {
            case "letters":
                rules.append(PronunciationRule(word: term, kind: .letters))
            case "word":
                rules.append(PronunciationRule(word: term, kind: .word))
            case "letters-first", "lettersfirst":
                rules.append(PronunciationRule(word: term, kind: .lettersFirst))
            case "replace":
                guard !replacement.isEmpty else { continue }
                rules.append(PronunciationRule(word: term,
                                               kind: .replace(replacement)))
            default:
                continue
            }
        }
        return rules
    }

    /// Merges imported rules into the existing rules text. Existing text —
    /// including comments and ordering — is preserved; new terms are
    /// appended in dictionary line format. Terms whose imported rule
    /// differs are reported as conflicts; `preferImported` rewrites those
    /// lines in place.
    static func merge(imported: [PronunciationRule], into existingText: String,
                      preferImported: Bool) -> MergeResult {
        let existingByWord = Dictionary(
            PronunciationDictionary.parse(existingText)
                .map { ($0.word.lowercased(), $0) },
            uniquingKeysWith: { _, last in last })

        var conflicts: [String] = []
        var toAppend: [PronunciationRule] = []
        var appendedKeys = Set<String>()
        var replacements: [String: PronunciationRule] = [:]

        for rule in imported {
            let key = rule.word.lowercased()
            guard let current = existingByWord[key] else {
                if appendedKeys.insert(key).inserted { toAppend.append(rule) }
                continue
            }
            if current.kind == rule.kind { continue }
            conflicts.append(rule.word)
            if preferImported { replacements[key] = rule }
        }

        var lines = existingText.components(separatedBy: "\n")
        if !replacements.isEmpty {
            lines = lines.map { line in
                guard let parsed = PronunciationDictionary.parse(line).first,
                      let replacement = replacements[parsed.word.lowercased()]
                else { return line }
                return ruleLine(replacement)
            }
        }
        var mergedText = lines.joined(separator: "\n")
        if !toAppend.isEmpty {
            if !mergedText.isEmpty, !mergedText.hasSuffix("\n") {
                mergedText += "\n"
            }
            mergedText += toAppend.map(ruleLine).joined(separator: "\n") + "\n"
        }
        return MergeResult(mergedText: mergedText, addedCount: toAppend.count,
                           conflictTerms: conflicts)
    }

    /// A rule in dictionary text format, e.g. "APA = @letters".
    static func ruleLine(_ rule: PronunciationRule) -> String {
        switch rule.kind {
        case .replace(let replacement): return "\(rule.word) = \(replacement)"
        case .letters: return "\(rule.word) = @letters"
        case .word: return "\(rule.word) = @word"
        case .lettersFirst: return "\(rule.word) = @letters-first"
        }
    }

    // MARK: - CSV plumbing

    private static func field(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(line)
        var i = 0
        while i < characters.count {
            let character = characters[i]
            if inQuotes {
                if character == "\"" {
                    if i + 1 < characters.count, characters[i + 1] == "\"" {
                        current.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                } else {
                    current.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            i += 1
        }
        fields.append(current)
        return fields
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter DictionaryCSVTests`
Expected: all 9 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/DictionaryCSV.swift Tests/KokoroStudioTests/DictionaryCSVTests.swift
git commit -m "feat: dictionary CSV export/parse/merge core (#29)"
```

---

### Task 2: Dictionary tab Import/Export UI (#29)

**Files:**
- Modify: `Sources/KokoroStudio/Views/SettingsView.swift` (DictionarySettingsTab, lines ~70–109)

- [ ] **Step 1: Add `import AppKit` and the footer buttons**

In `SettingsView.swift`, add `import AppKit` under `import SwiftUI`. Replace the footer of `DictionarySettingsTab` (the `Text("\(ruleCount) rule…")` block after the second `Divider()`) with:

```swift
            HStack {
                Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s") active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import…") { importCSV() }
                    .help("Merge rules from a CSV file (term,replacement,mode)")
                Button("Export…") { exportCSV() }
                    .help("Save all rules to a CSV file you can share")
                    .disabled(ruleCount == 0)
            }
            .padding(8)
```

- [ ] **Step 2: Add the panel + conflict-alert methods to `DictionarySettingsTab`**

```swift
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "pronunciation-dictionary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DictionaryCSV.export(rulesText: state.pronunciationRulesText)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            state.errorMessage = "Could not export dictionary: \(error.localizedDescription)"
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let csv = try? String(contentsOf: url, encoding: .utf8) else { return }
        let imported = DictionaryCSV.parse(csv)
        guard !imported.isEmpty else {
            state.errorMessage = "No dictionary rules found in that file."
            return
        }
        // Dry run finds conflicts before asking how to resolve them.
        let dryRun = DictionaryCSV.merge(imported: imported,
                                         into: state.pronunciationRulesText,
                                         preferImported: false)
        if dryRun.conflictTerms.isEmpty {
            state.pronunciationRulesText = dryRun.mergedText
            return
        }
        let alert = NSAlert()
        alert.messageText = dryRun.conflictTerms.count == 1
            ? "1 term already has a different rule"
            : "\(dryRun.conflictTerms.count) terms already have different rules"
        alert.informativeText = "Conflicting: "
            + dryRun.conflictTerms.joined(separator: ", ")
        alert.addButton(withTitle: "Keep Existing")
        alert.addButton(withTitle: "Use Imported")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            state.pronunciationRulesText = dryRun.mergedText
        case .alertSecondButtonReturn:
            state.pronunciationRulesText = DictionaryCSV.merge(
                imported: imported, into: state.pronunciationRulesText,
                preferImported: true).mergedText
        default:
            break
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build complete, no warnings about the new code.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/SettingsView.swift
git commit -m "feat: Import/Export CSV buttons in Dictionary settings (#29)"
```

---

### Task 3: LoudnessNormalizer core (#30)

**Files:**
- Create: `Sources/KokoroStudio/LoudnessNormalizer.swift`
- Test: `Tests/KokoroStudioTests/LoudnessNormalizerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class LoudnessNormalizerTests: XCTestCase {
    /// 997 Hz sine — the standard loudness test tone.
    private func sine(amplitude: Float, sampleRate: Int = 24000,
                      seconds: Double = 5) -> [Float] {
        let count = Int(Double(sampleRate) * seconds)
        return (0..<count).map { i in
            amplitude * sin(2 * .pi * 997 * Float(i) / Float(sampleRate))
        }
    }

    func testGainShiftsLoudnessByMatchingAmount() {
        let quiet = sine(amplitude: 0.1)
        let loud = quiet.map { $0 * 2 } // +6.02 dB
        let l1 = LoudnessNormalizer.integratedLoudness(samples: quiet,
                                                       sampleRate: 24000)
        let l2 = LoudnessNormalizer.integratedLoudness(samples: loud,
                                                       sampleRate: 24000)
        XCTAssertEqual(l2 - l1, 6.02, accuracy: 0.2)
    }

    func testNormalizeHitsTarget() {
        let result = LoudnessNormalizer.normalize(
            samples: sine(amplitude: 0.3), sampleRate: 24000, targetLUFS: -16)
        XCTAssertEqual(
            LoudnessNormalizer.integratedLoudness(samples: result,
                                                  sampleRate: 24000),
            -16, accuracy: 0.5)
    }

    func testPeakCeilingCapsGain() {
        // 0 LUFS is absurdly loud; the -1 dBFS ceiling must win.
        let result = LoudnessNormalizer.normalize(
            samples: sine(amplitude: 0.5), sampleRate: 24000, targetLUFS: 0)
        XCTAssertLessThanOrEqual(result.map { abs($0) }.max() ?? 0,
                                 AudioProcessing.peakTarget + 0.001)
    }

    func testSilenceIsUnmeasurableAndUnchanged() {
        let silence = [Float](repeating: 0, count: 24000)
        XCTAssertEqual(
            LoudnessNormalizer.integratedLoudness(samples: silence,
                                                  sampleRate: 24000),
            LoudnessNormalizer.unmeasurable)
        XCTAssertEqual(LoudnessNormalizer.normalize(samples: silence,
                                                    sampleRate: 24000,
                                                    targetLUFS: -16), silence)
    }

    func testPresetTargets() {
        XCTAssertNil(LoudnessPreset.lms.targetLUFS(custom: -20))
        XCTAssertEqual(LoudnessPreset.podcast.targetLUFS(custom: -20), -16)
        XCTAssertEqual(LoudnessPreset.streaming.targetLUFS(custom: -20), -14)
        XCTAssertEqual(LoudnessPreset.custom.targetLUFS(custom: -20), -20)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter LoudnessNormalizerTests`
Expected: compile error — `LoudnessNormalizer` not defined.

- [ ] **Step 3: Implement `LoudnessNormalizer`**

```swift
import Foundation

/// Loudness targets for export (#30). `lms` keeps the existing pipeline
/// (peak-only leveling during generation); the others add an integrated-
/// loudness gain pass at export time.
enum LoudnessPreset: String, CaseIterable, Identifiable {
    case lms, podcast, streaming, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lms: return "LMS / e-learning"
        case .podcast: return "Podcast (−16 LUFS)"
        case .streaming: return "Streaming (−14 LUFS)"
        case .custom: return "Custom"
        }
    }

    /// nil means "no LUFS pass" — the classic peak-normalized output.
    func targetLUFS(custom: Double) -> Double? {
        switch self {
        case .lms: return nil
        case .podcast: return -16
        case .streaming: return -14
        case .custom: return custom
        }
    }
}

/// Integrated loudness measurement and normalization for mono audio,
/// following ITU-R BS.1770 / EBU R128: K-weighting filter, 400 ms blocks
/// with 75% overlap, −70 LUFS absolute gate, then a −10 LU relative gate.
enum LoudnessNormalizer {
    /// Returned when the audio is silent or too short to measure.
    static let unmeasurable: Double = -100

    static func integratedLoudness(samples: [Float], sampleRate: Int) -> Double {
        let blockSize = sampleRate * 400 / 1000
        guard blockSize > 0, samples.count >= blockSize else { return unmeasurable }

        let weighted = kWeighted(samples, sampleRate: sampleRate)

        // Mean square per 400 ms block, hopping 100 ms (75% overlap).
        let hop = sampleRate / 10
        var blockMeanSquares: [Double] = []
        var start = 0
        while start + blockSize <= weighted.count {
            var sum = 0.0
            for i in start..<(start + blockSize) {
                sum += Double(weighted[i]) * Double(weighted[i])
            }
            blockMeanSquares.append(sum / Double(blockSize))
            start += hop
        }

        func loudness(_ meanSquare: Double) -> Double {
            -0.691 + 10 * log10(max(meanSquare, .leastNormalMagnitude))
        }

        // Gating keeps speech blocks and drops silence so pauses don't
        // drag the measurement down.
        let aboveAbsolute = blockMeanSquares.filter { loudness($0) > -70 }
        guard !aboveAbsolute.isEmpty else { return unmeasurable }
        let relativeThreshold = loudness(
            aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)) - 10
        let gated = blockMeanSquares.filter { loudness($0) > relativeThreshold }
        guard !gated.isEmpty else { return unmeasurable }

        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    /// Gain to bring integrated loudness to `targetLUFS`, capped so the
    /// sample peak never exceeds the app's −1 dBFS ceiling — normalization
    /// must never introduce clipping.
    static func normalize(samples: [Float], sampleRate: Int,
                          targetLUFS: Double) -> [Float] {
        let measured = integratedLoudness(samples: samples, sampleRate: sampleRate)
        guard measured > unmeasurable else { return samples }
        var gain = Float(pow(10, (targetLUFS - measured) / 20))
        if let peak = samples.map({ abs($0) }).max(), peak > 0 {
            gain = min(gain, AudioProcessing.peakTarget / peak)
        }
        return samples.map { $0 * gain }
    }

    // MARK: - K-weighting (BS.1770 reference filter, any sample rate)

    private struct Biquad {
        let b0, b1, b2, a1, a2: Double

        func apply(_ input: [Float]) -> [Float] {
            var output = [Float](repeating: 0, count: input.count)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for i in input.indices {
                let x0 = Double(input[i])
                let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                output[i] = Float(y0)
                x2 = x1; x1 = x0
                y2 = y1; y1 = y0
            }
            return output
        }
    }

    private static func kWeighted(_ samples: [Float],
                                  sampleRate: Int) -> [Float] {
        highPass(sampleRate: sampleRate)
            .apply(highShelf(sampleRate: sampleRate).apply(samples))
    }

    /// Stage 1: +4 dB high-shelf modeling head response. Parameters are the
    /// BS.1770 reference values; coefficients are recomputed for the actual
    /// sample rate (the spec only tabulates 48 kHz).
    private static func highShelf(sampleRate: Int) -> Biquad {
        let gainDb = 3.999843853973347
        let q = 0.7071752369554196
        let centerHz = 1681.974450955533
        let k = tan(.pi * centerHz / Double(sampleRate))
        let vh = pow(10, gainDb / 20)
        let vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return Biquad(
            b0: (vh + vb * k / q + k * k) / a0,
            b1: 2 * (k * k - vh) / a0,
            b2: (vh - vb * k / q + k * k) / a0,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)
    }

    /// Stage 2: high-pass that drops inaudible rumble from the measurement.
    private static func highPass(sampleRate: Int) -> Biquad {
        let q = 0.5003270373238773
        let centerHz = 38.13547087602444
        let k = tan(.pi * centerHz / Double(sampleRate))
        let a0 = 1 + k / q + k * k
        return Biquad(
            b0: 1, b1: -2, b2: 1,
            a1: 2 * (k * k - 1) / a0,
            a2: (1 - k / q + k * k) / a0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter LoudnessNormalizerTests`
Expected: all 5 PASS. If `testGainShiftsLoudness` is off by more than the accuracy, the biquad difference equation is the first suspect.

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/LoudnessNormalizer.swift Tests/KokoroStudioTests/LoudnessNormalizerTests.swift
git commit -m "feat: BS.1770 integrated loudness measurement and presets (#30)"
```

---

### Task 4: Wire loudness presets into AppState, export paths, ExportSheet, Profile (#30)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift` (storage ~line 117; `export()` ~line 656; `exportModules()` ~line 559; `currentProfile()`/`apply()` ~lines 703–734)
- Modify: `Sources/KokoroStudio/Views/ExportSheet.swift`
- Modify: `Sources/KokoroStudio/ProfileStore.swift` (Profile struct)

- [ ] **Step 1: AppState storage**

Next to `@AppStorage("normalizeLoudness")` add:

```swift
    @AppStorage("loudnessPreset") private var loudnessPresetRaw
        = LoudnessPreset.lms.rawValue
    @AppStorage("customLoudnessLUFS") var customLoudnessLUFS = -16.0

    var loudnessPreset: LoudnessPreset {
        get { LoudnessPreset(rawValue: loudnessPresetRaw) ?? .lms }
        set { loudnessPresetRaw = newValue.rawValue }
    }
```

- [ ] **Step 2: Apply in `export()`**

In `export()`, replace the line
`let paddedSamples = AudioProcessing.pad(audio.samples,` … with:

```swift
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
```

- [ ] **Step 3: Apply in `exportModules()`**

Capture the preset before the detached task (next to `let normalize = normalizeLoudness`):

```swift
        let loudnessTarget = loudnessPreset.targetLUFS(custom: customLoudnessLUFS)
```

Inside the module loop, just before `samples = AudioProcessing.pad(samples, …)`:

```swift
                    if let loudnessTarget {
                        samples = LoudnessNormalizer.normalize(
                            samples: samples, sampleRate: plan.sampleRate,
                            targetLUFS: loudnessTarget)
                    }
```

- [ ] **Step 4: ExportSheet picker**

In `ExportSheet.swift`, after the `Toggle("Normalize loudness", …)` block add:

```swift
                Picker("Loudness", selection: Binding(
                    get: { state.loudnessPreset },
                    set: { state.loudnessPreset = $0 })) {
                    ForEach(LoudnessPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .help("Overall loudness at export. LMS keeps the classic −1 dBFS leveling; the others target an integrated LUFS level for podcast or video platforms.")

                if state.loudnessPreset == .custom {
                    LabeledContent("Target") {
                        Stepper(value: $state.customLoudnessLUFS,
                                in: -36...(-8), step: 1) {
                            Text("\(Int(state.customLoudnessLUFS)) LUFS")
                                .monospacedDigit()
                        }
                    }
                }
```

Change the sheet frame from `.frame(width: 420, height: 360)` to `.frame(width: 420, height: 420)` so the new rows fit.

- [ ] **Step 5: Profile round-trip**

In `ProfileStore.swift`, add to `Profile` (after `numberPreset`):

```swift
    // Added in v1.5 — optional so older profile files still decode.
    var loudnessPreset: String? = nil
    var customLoudnessLUFS: Double? = nil
```

In `AppState.currentProfile()` add arguments:

```swift
                numberPreset: numberPreset.rawValue,
                loudnessPreset: loudnessPreset.rawValue,
                customLoudnessLUFS: customLoudnessLUFS)
```

In `AppState.apply(_:)` add:

```swift
        loudnessPreset = profile.loudnessPreset
            .flatMap { LoudnessPreset(rawValue: $0) } ?? .lms
        customLoudnessLUFS = profile.customLoudnessLUFS ?? -16.0
```

- [ ] **Step 6: Build and run the full non-engine test suite**

Run: `swift build && DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter "DictionaryCSVTests|LoudnessNormalizerTests"`
Expected: build clean, tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/KokoroStudio/AppState.swift Sources/KokoroStudio/Views/ExportSheet.swift Sources/KokoroStudio/ProfileStore.swift
git commit -m "feat: loudness preset picker in export sheet, applied at export (#30)"
```

---

### Task 5: Sample script content and seed logic (#31)

**Files:**
- Create: `Sources/KokoroStudio/SampleScript.swift`
- Modify: `Sources/KokoroStudio/AppState.swift`
- Test: `Tests/KokoroStudioTests/SampleScriptTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class SampleScriptTests: XCTestCase {
    func testSampleExercisesEverySyntaxFeature() {
        let text = SampleScript.text
        XCTAssertTrue(text.contains("[pause:"), "inline pause marker")
        XCTAssertTrue(text.contains("{Roush|rowsh}"), "inline override")
        XCTAssertEqual(ScriptSegmenter.speakerNames(in: text), ["Maya", "Sam"],
                       "dialogue speakers")
        XCTAssertEqual(ModuleSplitter.split(text).count, 2, "module marker")
        let segments = ScriptSegmenter.segment(text, pauses: PauseSettings())
        XCTAssertTrue(segments.contains {
            $0.speedMultiplier == ScriptSegmenter.emphasisSpeedMultiplier
        }, "emphasis span")
        XCTAssertFalse(ScriptLinter.acronymSuspects(in: text, coveredBy: [])
            .isEmpty, "acronyms that trigger the linter")
    }

    func testSeedGuard() {
        XCTAssertTrue(AppState.shouldSeedSample(hasSeeded: false, script: ""))
        XCTAssertTrue(AppState.shouldSeedSample(hasSeeded: false, script: " \n"))
        XCTAssertFalse(AppState.shouldSeedSample(hasSeeded: true, script: ""))
        XCTAssertFalse(AppState.shouldSeedSample(hasSeeded: false,
                                                 script: "My own script"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SampleScriptTests`
Expected: compile error — `SampleScript` not defined.

- [ ] **Step 3: Create `SampleScript.swift`**

The sample is spoken narration that explains each feature as it uses it —
scripts have no comment syntax, so the script *is* the documentation.

```swift
import Foundation

/// The first-run welcome script (#31): a guided tour that exercises every
/// piece of script syntax so new users hear each feature working before
/// they read any documentation.
enum SampleScript {
    static let text = """
    # Welcome to Kokoro Studio
    This sample script is a guided tour. Press command return to generate \
    it, then listen along.
    The line above starts with a hash sign, so it reads as a heading and \
    gets a longer pause after it.
    You can ask for a deliberate beat anywhere. [pause:800] That silence \
    came from an inline pause marker.
    Words wrapped in asterisks get *gentle emphasis*, with a breath on \
    either side.
    @Maya: A line that starts with an at-sign and a name becomes dialogue.
    @Sam: Open Speakers in the sidebar to give each of us a different \
    voice and speed.
    The pronunciation dictionary controls acronyms: NASA can read as a \
    word, while APA spells out letter by letter.
    One-off fixes go right in the text, like the name {Roush|rowsh}.
    Numbers and symbols read naturally: $5.50, 25%, and version v1.2.
    ## file: splitting-demo
    A line of two hash signs, the word file, and a colon splits a long \
    script into separate audio files on export.
    That is the whole tour. Select all, delete, and paste in your own \
    script.
    """
}
```

- [ ] **Step 4: Add seed/restore logic to AppState**

After the `// MARK: - Voice previews` section header's preceding code (i.e. as a new section before `// MARK: - Model loading`):

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SampleScriptTests`
Expected: both PASS. (If `testSampleExercisesEverySyntaxFeature` fails on `speakerNames`, check the `@Maya:`/`@Sam:` lines survived the multiline-string line-wrapping backslashes.)

- [ ] **Step 6: Commit**

```bash
git add Sources/KokoroStudio/SampleScript.swift Sources/KokoroStudio/AppState.swift Tests/KokoroStudioTests/SampleScriptTests.swift
git commit -m "feat: first-run sample script content and seed logic (#31)"
```

---

### Task 6: First-run seeding + Help menu restore (#31)

**Files:**
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift`

- [ ] **Step 1: Seed on launch and add the Help item**

In `KokoroStudioApp`, change the window task:

```swift
                .task {
                    state.loadModel()
                    state.seedSampleScriptIfFirstRun()
                }
```

Change `HelpCommands` to carry state, and add the restore button after "Script Syntax Reference":

```swift
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var state: AppState

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Kokoro Studio Help",
                 destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio#readme")!)
            Button("Script Syntax Reference") {
                openWindow(id: "syntax-reference")
            }
            Button("Restore Sample Script") {
                state.requestRestoreSampleScript()
            }
            Divider()
            Link("Report an Issue…",
                 destination: URL(string: "https://github.com/ntderosu-code/kokoro-studio/issues")!)
        }
    }
}
```

And in the `.commands` block: `HelpCommands(state: state)`.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/KokoroStudio/KokoroStudioApp.swift
git commit -m "feat: seed sample script on first run; Restore Sample Script in Help (#31)"
```

---

### Task 7: Audition support helpers (#32)

**Files:**
- Create: `Sources/KokoroStudio/AuditionSupport.swift`
- Test: `Tests/KokoroStudioTests/AuditionSupportTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class AuditionSupportTests: XCTestCase {
    func testCacheKeyStableAndDistinct() {
        XCTAssertEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"))
        XCTAssertNotEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k2"))
        XCTAssertNotEqual(
            AuditionSupport.cacheKey(text: "Hello.", voiceLabel: "k3"),
            AuditionSupport.cacheKey(text: "Hi.", voiceLabel: "k3"))
    }

    func testDefaultTextIsFirstProseSentence() {
        XCTAssertEqual(AuditionSupport.defaultText(from: """
        # Heading line
        @Maya: First sentence here. Second sentence.
        """), "First sentence here.")
    }

    func testDefaultTextEmptyScript() {
        XCTAssertEqual(AuditionSupport.defaultText(from: "   \n"), "")
    }

    func testDefaultTextCapsLength() {
        let long = String(repeating: "word ", count: 100)
        XCTAssertLessThanOrEqual(
            AuditionSupport.defaultText(from: long).count, 240)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter AuditionSupportTests`
Expected: compile error — `AuditionSupport` not defined.

- [ ] **Step 3: Implement `AuditionSupport` and `AuditionVoice`**

```swift
import Foundation

/// One side of an A/B voice comparison (#32): a Kokoro catalog voice or
/// the current Pocket TTS cloned sample.
enum AuditionVoice: Equatable, Hashable {
    case kokoro(Int)
    case pocket

    var label: String {
        switch self {
        case .kokoro(let id): return VoiceCatalog.voice(forID: id).humanName
        case .pocket: return "Pocket (cloned sample)"
        }
    }

    /// Stable token for cache keys.
    var cacheLabel: String {
        switch self {
        case .kokoro(let id): return "k\(id)"
        case .pocket: return "pocket"
        }
    }
}

enum AuditionSupport {
    /// Deterministic cache filename component for one (text, voice) render.
    /// djb2 rather than Hasher because Hasher is seeded per-process and
    /// these names end up on disk.
    static func cacheKey(text: String, voiceLabel: String) -> String {
        var hash: UInt64 = 5381
        for byte in Array("\(voiceLabel)|\(text)".utf8) {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    /// What to audition when nothing is selected: the first prose sentence
    /// of the script — headings and speaker tags are skipped so the
    /// comparison plays natural narration.
    static func defaultText(from script: String) -> String {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var line = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? trimmed
        line = line.replacing(/^@[\w ]+:\s*/, with: "")
        var sentence = line
        if let end = line.firstIndex(where: { ".!?".contains($0) }) {
            sentence = String(line[...end])
        }
        return String(sentence.prefix(240))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter AuditionSupportTests`
Expected: all 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/AuditionSupport.swift Tests/KokoroStudioTests/AuditionSupportTests.swift
git commit -m "feat: audition voice model and text/cache helpers (#32)"
```

---

### Task 8: AppState audition rendering and playback (#32)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift` (new section after `// MARK: - Voice previews`)

- [ ] **Step 1: Add the audition section to AppState**

```swift
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
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/KokoroStudio/AppState.swift
git commit -m "feat: audition render/playback/cache plumbing in AppState (#32)"
```

---

### Task 9: VoiceAuditionView and entry points (#32)

**Files:**
- Create: `Sources/KokoroStudio/Views/VoiceAuditionView.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (toolbar `selection` ControlGroup ~line 130; sheets ~line 200)
- Modify: `Sources/KokoroStudio/Views/SidebarView.swift` (Voice section)

- [ ] **Step 1: Create the sheet view**

```swift
import SwiftUI

/// Side-by-side comparison of two voices speaking the same text (#32).
/// Renders are cached for the session, so alternating playback is instant
/// after the first listen on each side.
struct VoiceAuditionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let text: String

    @State private var voiceA: AuditionVoice = .kokoro(3)
    @State private var voiceB: AuditionVoice = .kokoro(2)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compare Voices").font(.headline)
                Text("“\(text)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            HStack(spacing: 0) {
                column(title: "Voice A", selection: $voiceA)
                Divider()
                column(title: "Voice B", selection: $voiceB)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 320)
        .onAppear {
            // A starts as whatever the script currently uses; B starts on
            // a different recommended voice so play-play comparison works
            // immediately.
            voiceA = state.engineKind == .pocket
                ? .pocket : .kokoro(state.voiceID)
            if voiceA == voiceB {
                voiceB = .kokoro(state.voiceID == 2 ? 3 : 2)
            }
        }
        .onDisappear { state.stopAudition() }
    }

    @ViewBuilder
    private func column(title: String,
                        selection: Binding<AuditionVoice>) -> some View {
        VStack(spacing: 14) {
            Picker(title, selection: selection) {
                ForEach(state.visibleVoiceGroups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.voices) { voice in
                            Text(voice.displayName)
                                .tag(AuditionVoice.kokoro(voice.id))
                        }
                    }
                }
                if state.engineKind == .pocket || !state.pocketVoicePath.isEmpty {
                    Text("Pocket (cloned sample)").tag(AuditionVoice.pocket)
                }
            }
            .labelsHidden()

            Button {
                state.toggleAudition(text: text, voice: selection.wrappedValue)
            } label: {
                if state.auditionRendering == selection.wrappedValue {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 34, height: 34)
                } else {
                    Image(systemName: state.auditionPlaying == selection.wrappedValue
                          ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                }
            }
            .buttonStyle(.plain)
            .disabled(state.auditionRendering != nil)
            .accessibilityLabel("Play \(selection.wrappedValue.label)")

            Button("Use This Voice") {
                state.useAuditionVoice(selection.wrappedValue)
                dismiss()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Toolbar entry point in ContentView**

Add to the `selection` ControlGroup, after the "Add to Dictionary" button:

```swift
                    Button("Compare Voices", systemImage: "person.2.wave.2") {
                        let text = selectedEditorText()
                            ?? AuditionSupport.defaultText(from: state.script)
                        guard !text.isEmpty else { return }
                        player.stop()
                        state.auditionText = text
                    }
                    .disabled(state.phase != .ready
                              || (state.script.trimmingCharacters(
                                    in: .whitespacesAndNewlines).isEmpty
                                  && !hasEditorSelection))
                    .help("Hear the selection (or first sentence) in two voices side by side")
```

Add a sheet after the existing QuickAdd sheet, plus the identifiable wrapper at file scope (next to `QuickAddTarget`'s usage pattern):

```swift
struct AuditionTarget: Identifiable {
    let text: String
    var id: String { text }
}
```

```swift
        .sheet(item: Binding(
            get: { state.auditionText.map(AuditionTarget.init) },
            set: { state.auditionText = $0?.text })) { target in
            VoiceAuditionView(text: target.text)
        }
```

- [ ] **Step 3: Sidebar entry point**

In `SidebarView.swift`, Voice section, after the `Button("Speakers…")` block (inside the kokoro branch) AND after `Text("5–15 seconds…")` (pocket branch) — or simpler, once right before the `LabeledContent("Speed")` row which both branches share:

```swift
                Button("Compare Voices…") {
                    state.auditionText
                        = AuditionSupport.defaultText(from: state.script)
                }
                .disabled(state.phase != .ready
                          || AuditionSupport.defaultText(from: state.script).isEmpty)
                .help("Hear the script's first sentence in two voices side by side")
```

- [ ] **Step 4: Build and full filtered test pass**

Run: `swift build && DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter "DictionaryCSVTests|LoudnessNormalizerTests|SampleScriptTests|AuditionSupportTests"`
Expected: build clean, all new tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/Views/VoiceAuditionView.swift Sources/KokoroStudio/Views/ContentView.swift Sources/KokoroStudio/Views/SidebarView.swift
git commit -m "feat: Compare Voices A/B audition sheet with toolbar and sidebar entry (#32)"
```

---

### Task 10: Full verification

- [ ] **Step 1: Run the entire test suite (includes engine tests — slow, loads models)**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test`
Expected: all tests PASS. Pre-existing engine tests must not regress.

- [ ] **Step 2: Manual smoke check (build the app)**

Run: `./scripts/build-app.sh && open "build/Kokoro Studio.app"`

Verify by hand:
1. Settings → Dictionary: Export… writes a CSV that opens in Numbers; Import… of that CSV on top of an edited dictionary shows the conflict alert.
2. Export sheet shows the Loudness picker; Custom reveals the LUFS stepper; default preset exports byte-identical audio to before (spot-check duration/size).
3. First run (`defaults delete com.kokorostudio.app` equivalent — delete the app's preferences or test on `hasSeededSampleScript` reset via `defaults write ... hasSeededSampleScript -bool false` plus relaunch with empty editor): sample script appears; Help → Restore Sample Script asks before replacing edited text.
4. Toolbar Compare Voices with a selection opens the sheet; both sides render and play; Use This Voice updates the sidebar picker; with Pocket engine active, "Pocket (cloned sample)" appears in the side pickers.

- [ ] **Step 3: Do NOT push.** Leave commits local; the user decides when to ship.
