# Wave 2 Editor & Document Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement GitHub issues #33 (document import with syntax conversion), #34 (script library with autosave), #35 (follow-along sentence highlighting + click-to-seek), and #36 (waveform player bar with heading markers).

**Architecture:** Pure-logic modules (`ScriptImporter`, `DocumentStore`, `CueAlignment`, `WaveformBuilder`) are TDD'd without the TTS models. UI wiring goes into existing views. `.docx`/`.rtf` are read via `NSAttributedString` document types (no new dependencies). Follow-along maps caption cues to editor ranges with fuzzy word alignment because cue text is post-preprocessing (dictionary/number rewrites) while the editor shows raw text.

**Tech Stack:** Swift / SwiftUI / AppKit (macOS), Combine (autosave debounce), XCTest, SwiftPM. No new dependencies.

**Constraints:**
- DO NOT push, tag, bump version, or run release scripts. Local commits only on branch `wave-2` (off `wave-1`).
- Test command: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter <ClassName>`
- Bare Swift regex literals ending in `*/` mis-lex as comment ends — always use `#/.../#` delimiters.
- SourceKit diagnostics in this repo are often stale; trust `swift build`.

---

### Task 1: ScriptImporter — markdown + plain text conversion (#33)

**Files:**
- Create: `Sources/KokoroStudio/ScriptImporter.swift`
- Test: `Tests/KokoroStudioTests/ScriptImporterTests.swift`

- [ ] **Step 1: Failing tests** (`ScriptImporterTests` part 1)

```swift
import XCTest
@testable import KokoroStudio

final class ScriptImporterTests: XCTestCase {
    func testMarkdownHeadingsCollapseToScriptHeadings() {
        // All MD heading levels become single-# so they never collide with
        // the "## file:" module-split syntax.
        XCTAssertEqual(ScriptImporter.convertMarkdown("## Lesson One\nBody."),
                       "# Lesson One\nBody.")
        XCTAssertEqual(ScriptImporter.convertMarkdown("# Top\n### Deep"),
                       "# Top\n# Deep")
    }

    func testBoldBecomesEmphasisItalicBecomesPlain() {
        XCTAssertEqual(
            ScriptImporter.convertMarkdown("This **matters** but *this* less so."),
            "This *matters* but this less so.")
        XCTAssertEqual(
            ScriptImporter.convertMarkdown("Also __strong__ and _soft_."),
            "Also *strong* and soft.")
    }

    func testListsBlockquotesLinksImagesCode() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("""
        - First point
        2. Second point
        > Quoted wisdom
        See [the docs](https://x.y) and ![diagram](img.png) here.
        Use `code` sparingly.
        """), """
        First point
        Second point
        Quoted wisdom
        See the docs and  here.
        Use code sparingly.
        """)
    }

    func testTablesAndRulesDropped() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("""
        Before.
        | a | b |
        |---|---|
        | 1 | 2 |
        ---
        After.
        """), "Before.\nAfter.")
    }

    func testCodeFenceMarkersDroppedContentKept() {
        XCTAssertEqual(ScriptImporter.convertMarkdown("```\nplain inside\n```"),
                       "plain inside")
    }

    func testSmartPunctuationNormalized() {
        XCTAssertEqual(
            ScriptImporter.normalizePlainText("\u{201C}Hi\u{201D} it\u{2019}s\u{00A0}me\u{2026}"),
            "\"Hi\" it's me...")
    }
}
```

- [ ] **Step 2: Run, expect compile failure** (`--filter ScriptImporterTests`)

- [ ] **Step 3: Implement** (markdown part of `ScriptImporter.swift`)

```swift
import Foundation
import AppKit

/// Converts imported documents (#33) into script syntax: headings -> `#`,
/// bold -> `*emphasis*`, smart punctuation -> plain equivalents the
/// normalizer understands, lists/quotes/links flattened to spoken text.
enum ScriptImporter {
    static func normalizePlainText(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let replacements: [(String, String)] = [
            ("\u{2018}", "'"), ("\u{2019}", "'"),
            ("\u{201C}", "\""), ("\u{201D}", "\""),
            ("\u{00A0}", " "), ("\u{2026}", "..."),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    static func convertMarkdown(_ text: String) -> String {
        var lines: [String] = []
        var inCodeFence = false
        for rawLine in normalizePlainText(text).components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCodeFence.toggle(); continue }
            if inCodeFence {
                lines.append(line)
                continue
            }
            if line.isEmpty { lines.append(""); continue }
            // Tables and horizontal rules have no spoken equivalent.
            if line.hasPrefix("|") { continue }
            if line.allSatisfy({ "-*_".contains($0) }), line.count >= 3 { continue }
            // Headings: collapse every level to one # — "##" is reserved
            // for the module-split syntax in scripts.
            if let match = line.firstMatch(of: #/^(#{1,6})\s+(.*)$/#) {
                lines.append("# " + String(match.2))
                continue
            }
            if line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            line = line.replacing(#/^([-*+]|\d+[.)])\s+/#, with: "")
            line = line.replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: "")
            line = line.replacing(#/\[([^\]]+)\]\([^)]*\)/#) { String($0.output.1) }
            // Bold -> emphasis via placeholders so the italic pass below
            // doesn't strip the markers we just produced.
            line = line.replacing(#/\*\*([^*]+)\*\*/#) { "\u{1}\($0.output.1)\u{2}" }
            line = line.replacing(#/__([^_]+)__/#) { "\u{1}\($0.output.1)\u{2}" }
            line = line.replacing(#/\*([^*\n]+)\*/#) { String($0.output.1) }
            line = line.replacing(#/\b_([^_\n]+)_\b/#) { String($0.output.1) }
            line = line.replacingOccurrences(of: "\u{1}", with: "*")
            line = line.replacingOccurrences(of: "\u{2}", with: "*")
            line = line.replacingOccurrences(of: "`", with: "")
            lines.append(line)
        }
        return lines.joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run, expect 6 PASS.** Adjust the italic `_x_` regex if the word-boundary form fails (`\b_` requires the underscore adjacent to a word character; acceptable fallback: `#/(?<![\w])_([^_\n]+)_(?![\w])/#`).

- [ ] **Step 5: Commit** `feat: markdown/plain-text script conversion (#33)`

---

### Task 2: ScriptImporter — attributed documents (.docx/.rtf) + dispatch (#33)

**Files:**
- Modify: `Sources/KokoroStudio/ScriptImporter.swift`
- Modify: `Tests/KokoroStudioTests/ScriptImporterTests.swift`

- [ ] **Step 1: Failing tests** (append to `ScriptImporterTests`)

```swift
    private func attributed(_ runs: [(text: String, size: CGFloat, bold: Bool)])
        -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            let font = run.bold
                ? NSFont.boldSystemFont(ofSize: run.size)
                : NSFont.systemFont(ofSize: run.size)
            result.append(NSAttributedString(string: run.text,
                                             attributes: [.font: font]))
        }
        return result
    }

    func testAttributedHeadingByFontSize() {
        let doc = attributed([
            ("Lesson One\n", 18, false),
            ("Body text here.\n", 12, false),
            ("More body.", 12, false),
        ])
        XCTAssertEqual(ScriptImporter.convertAttributed(doc),
                       "# Lesson One\nBody text here.\nMore body.")
    }

    func testAttributedBoldRunBecomesEmphasis() {
        let doc = attributed([
            ("The ", 12, false), ("key term", 12, true), (" matters.", 12, false),
        ])
        XCTAssertEqual(ScriptImporter.convertAttributed(doc),
                       "The *key term* matters.")
    }

    func testImportFileDispatchesMarkdown() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-test-\(UUID().uuidString).md")
        try "## Title\n**bold**".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ScriptImporter.importFile(at: url), "# Title\n*bold*")
    }
```

- [ ] **Step 2: Run, expect compile failure** (no `convertAttributed`/`importFile`).

- [ ] **Step 3: Implement** (append to `ScriptImporter`)

```swift
    /// Word/RTF conversion. Headings aren't exposed as named styles by
    /// NSAttributedString, so a paragraph noticeably larger than the
    /// document's body size is treated as a heading. Bold runs inside
    /// normal paragraphs become *emphasis*.
    static func convertAttributed(_ attributed: NSAttributedString) -> String {
        let full = attributed.string as NSString
        var paragraphRanges: [NSRange] = []
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length),
                                 options: [.byParagraphs, .substringNotRequired]) {
            _, range, _, _ in
            paragraphRanges.append(range)
        }

        func dominantSize(_ range: NSRange) -> CGFloat {
            var weighted: [CGFloat: Int] = [:]
            attributed.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let size = (value as? NSFont)?.pointSize ?? 12
                weighted[size, default: 0] += runRange.length
            }
            return weighted.max { $0.value < $1.value }?.key ?? 12
        }

        let sizes = paragraphRanges.map(dominantSize)
        // Body size = the most common paragraph size across the document.
        var sizeCounts: [CGFloat: Int] = [:]
        for size in sizes { sizeCounts[size, default: 0] += 1 }
        let bodySize = sizeCounts.max { $0.value < $1.value }?.key ?? 12

        var lines: [String] = []
        for (index, range) in paragraphRanges.enumerated() {
            let plain = normalizePlainText(full.substring(with: range))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if plain.isEmpty { lines.append(""); continue }
            if sizes[index] >= bodySize * 1.15 {
                lines.append("# " + plain)
                continue
            }
            var line = ""
            attributed.enumerateAttribute(.font, in: range) { value, runRange, _ in
                let runText = normalizePlainText(full.substring(with: runRange))
                let isBold = (value as? NSFont)?.fontDescriptor.symbolicTraits
                    .contains(.bold) ?? false
                let trimmed = runText.trimmingCharacters(in: .whitespacesAndNewlines)
                if isBold, !trimmed.isEmpty {
                    line += runText.replacingOccurrences(of: trimmed,
                                                         with: "*\(trimmed)*")
                } else {
                    line += runText
                }
            }
            lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return lines.joined(separator: "\n")
            .replacing(#/\n{3,}/#, with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func importFile(at url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            return convertMarkdown(try String(contentsOf: url, encoding: .utf8))
        case "rtf":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
            return convertAttributed(attributed)
        case "docx":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil)
            return convertAttributed(attributed)
        default:
            return normalizePlainText(try String(contentsOf: url, encoding: .utf8))
        }
    }
```

- [ ] **Step 4: Run, expect all `ScriptImporterTests` PASS.** Note: `.byParagraphs` ranges exclude the trailing newline, so paragraph text needs no newline stripping beyond trimming.

- [ ] **Step 5: Commit** `feat: docx/rtf import via NSAttributedString, file dispatch (#33)`

---

### Task 3: Import UI — File menu, drag-and-drop, preview sheet (#33)

**Files:**
- Create: `Sources/KokoroStudio/Views/ImportPreviewView.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift`
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift`
- Modify: `Sources/KokoroStudio/AppState.swift` (two small published flags)

- [ ] **Step 1: AppState flags** (next to `auditionText`)

```swift
    // MARK: - Document import (#33)

    /// Toggled by the File menu; ContentView owns the fileImporter.
    @Published var showingImportPanel = false
    /// Non-nil presents the import preview sheet with converted text.
    @Published var importedText: String?
```

- [ ] **Step 2: `ImportPreviewView.swift`** — fixed header, scrollable preview, fixed footer (matches DictionaryEditorView pattern):

```swift
import SwiftUI

/// Preview of an imported document after conversion to script syntax
/// (#33), with explicit Replace / Insert actions so an import can never
/// silently overwrite editor content.
struct ImportPreviewView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Preview").font(.headline)
                Text("Headings became # lines, bold became *emphasis*, and smart punctuation was cleaned up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Insert at Cursor") {
                    insertAtCaret()
                    dismiss()
                }
                Button("Replace Script") {
                    state.script = text
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 440)
    }

    private func insertAtCaret() {
        if let textView = EditorTextAccess.focusTextView(in: NSApp.keyWindow) {
            textView.insertText(text, replacementRange: textView.selectedRange())
        } else {
            state.script += (state.script.isEmpty ? "" : "\n") + text
        }
    }
}
```

- [ ] **Step 3: ContentView wiring** — add below the audition sheet:

```swift
        .sheet(item: Binding(
            get: { state.importedText.map(AuditionTarget.init) },
            set: { state.importedText = $0?.text })) { target in
            ImportPreviewView(text: target.text)
        }
        .fileImporter(isPresented: $state.showingImportPanel,
                      allowedContentTypes: ScriptImporter.importableTypes) { result in
            if case .success(let url) = result { importDocument(at: url) }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url,
                      ScriptImporter.importableExtensions
                          .contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in importDocument(at: url) }
            }
            return true
        }
```

plus the helper on ContentView:

```swift
    private func importDocument(at url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let converted = try ScriptImporter.importFile(at: url)
            guard !converted.isEmpty else {
                state.errorMessage = "Nothing readable found in that document."
                return
            }
            state.importedText = converted
        } catch {
            state.errorMessage = "Could not import: \(error.localizedDescription)"
        }
    }
```

and the type lists on `ScriptImporter`:

```swift
    static let importableExtensions: Set<String> = ["md", "markdown", "txt",
                                                    "text", "rtf", "docx"]

    static var importableTypes: [UTType] {
        var types: [UTType] = [.plainText, .rtf]
        for ext in ["md", "docx"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }
```

(`import UniformTypeIdentifiers` at the top of `ScriptImporter.swift`.)

- [ ] **Step 4: File menu** — in `KokoroStudioApp.swift` `.commands` block:

```swift
            CommandGroup(after: .newItem) {
                Button("Import Document…") {
                    state.showingImportPanel = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
```

- [ ] **Step 5: `swift build`, commit** `feat: document import UI — File menu, drag-drop, preview sheet (#33)`

---

### Task 4: DocumentStore (#34)

**Files:**
- Create: `Sources/KokoroStudio/DocumentStore.swift`
- Test: `Tests/KokoroStudioTests/DocumentStoreTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class DocumentStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-store-tests-\(UUID().uuidString)")
        DocumentStore.directoryOverride = tempDir
    }

    override func tearDown() {
        DocumentStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveListLoadRoundTrip() throws {
        var meta = ScriptDocumentMeta(title: "Lesson 1")
        meta.profileName = "Course Voice"
        try DocumentStore.save(meta: meta, text: "Hello there.")
        let listed = DocumentStore.list()
        XCTAssertEqual(listed.map(\.id), [meta.id])
        XCTAssertEqual(listed.first?.title, "Lesson 1")
        XCTAssertEqual(listed.first?.profileName, "Course Voice")
        XCTAssertEqual(DocumentStore.loadText(id: meta.id), "Hello there.")
    }

    func testListSortsByUpdatedAtDescending() throws {
        var older = ScriptDocumentMeta(title: "Old")
        older.updatedAt = Date(timeIntervalSince1970: 100)
        var newer = ScriptDocumentMeta(title: "New")
        newer.updatedAt = Date(timeIntervalSince1970: 200)
        try DocumentStore.save(meta: older, text: "a")
        try DocumentStore.save(meta: newer, text: "b")
        XCTAssertEqual(DocumentStore.list().map(\.title), ["New", "Old"])
    }

    func testDeleteRemovesBothFiles() throws {
        let meta = ScriptDocumentMeta(title: "Doomed")
        try DocumentStore.save(meta: meta, text: "bye")
        DocumentStore.delete(id: meta.id)
        XCTAssertTrue(DocumentStore.list().isEmpty)
        XCTAssertEqual(DocumentStore.loadText(id: meta.id), "")
    }

    func testDuplicateCopiesTextWithNewIdentity() throws {
        let meta = ScriptDocumentMeta(title: "Original")
        try DocumentStore.save(meta: meta, text: "content")
        let copy = try XCTUnwrap(DocumentStore.duplicate(id: meta.id))
        XCTAssertNotEqual(copy.id, meta.id)
        XCTAssertEqual(copy.title, "Original copy")
        XCTAssertEqual(DocumentStore.loadText(id: copy.id), "content")
        XCTAssertEqual(DocumentStore.list().count, 2)
    }

    func testAutoTitleFromFirstLine() {
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: "# Welcome Tour\nHi."),
                       "Welcome Tour")
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: "Plain first line here\nMore."),
                       "Plain first line here")
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: ""), "Untitled")
        let long = String(repeating: "x", count: 100)
        XCTAssertEqual(ScriptDocumentMeta.autoTitle(for: long).count, 40)
    }
}
```

- [ ] **Step 2: Run, expect compile failure.**

- [ ] **Step 3: Implement `DocumentStore.swift`**

```swift
import Foundation

/// One saved script in the library (#34). Text lives in `<id>.txt`,
/// metadata in a `<id>.json` sidecar, so scripts stay greppable plain text.
struct ScriptDocumentMeta: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    /// True once the user renames explicitly; auto-titling stops then.
    var customTitle = false
    var profileName: String?
    var createdAt = Date()
    var updatedAt = Date()

    init(title: String) {
        self.title = title
    }

    /// Title derived from the first non-empty line, headings unwrapped.
    static func autoTitle(for text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let unwrapped = firstLine.drop { $0 == "#" }
            .trimmingCharacters(in: .whitespaces)
        return unwrapped.isEmpty ? "Untitled" : String(unwrapped.prefix(40))
    }
}

enum DocumentStore {
    /// Tests point this at a temp directory.
    static var directoryOverride: URL?

    static var directory: URL {
        directoryOverride
            ?? FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask)[0]
                .appendingPathComponent("Kokoro Studio/Scripts")
    }

    static func list() -> [ScriptDocumentMeta] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ScriptDocumentMeta.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func loadText(id: UUID) -> String {
        (try? String(contentsOf: textURL(id: id), encoding: .utf8)) ?? ""
    }

    static func save(meta: ScriptDocumentMeta, text: String) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try text.write(to: textURL(id: meta.id), atomically: true, encoding: .utf8)
        try saveMeta(meta)
    }

    static func saveMeta(_ meta: ScriptDocumentMeta) throws {
        try FileManager.default.createDirectory(at: directory,
                                                withIntermediateDirectories: true)
        try encoder.encode(meta).write(to: metaURL(id: meta.id))
    }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: textURL(id: id))
        try? FileManager.default.removeItem(at: metaURL(id: id))
    }

    static func duplicate(id: UUID) -> ScriptDocumentMeta? {
        guard let original = list().first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.title = original.title + " copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        do {
            try save(meta: copy, text: loadText(id: id))
            return copy
        } catch {
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func textURL(id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("txt")
    }

    private static func metaURL(id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}
```

- [ ] **Step 4: Run, expect 5 PASS.**

- [ ] **Step 5: Commit** `feat: script library document store (#34)`

---

### Task 5: AppState library integration — selection, autosave, profile association (#34)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift`
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift` (call `loadLibrary()`)
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (profile selection moves to AppState)

- [ ] **Step 1: AppState additions** (new section; `import Combine` at top)

```swift
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
    }

    /// Removes the library entry only — exported audio is never touched.
    func deleteDocument(_ id: UUID) {
        DocumentStore.delete(id: id)
        documents.removeAll { $0.id == id }
        if currentDocumentID == id {
            if let next = documents.first {
                currentDocumentID = nil // force reload in selectDocument
                selectDocument(next.id)
            } else {
                createDocument()
            }
        }
    }
```

- [ ] **Step 2: Launch order** in `KokoroStudioApp.swift`:

```swift
                .task {
                    state.loadModel()
                    state.seedSampleScriptIfFirstRun()
                    state.loadLibrary()
                }
```

- [ ] **Step 3: ContentView profile menu reads AppState** — replace `@State private var selectedProfile = ""` usage: delete the local var, change `$selectedProfile` to `$state.currentProfileName`, `selectedProfile` references to `state.currentProfileName` (menu label, delete button, save handler, onChange). The `onChange(of: selectedProfile)` modifier becomes `onChange(of: state.currentProfileName)`.

- [ ] **Step 4: `swift build` + run DocumentStoreTests again, commit** `feat: AppState script library — selection, autosave, profile association (#34)`

---

### Task 6: Sidebar library UI (#34)

**Files:**
- Modify: `Sources/KokoroStudio/Views/SidebarView.swift`

- [ ] **Step 1: Add a Scripts section** as the FIRST section in the Form (above "Engine"):

```swift
            Section("Scripts") {
                if state.documents.count > 5 {
                    TextField("Search scripts", text: $scriptSearch)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
                ForEach(filteredDocuments) { doc in
                    HStack {
                        Image(systemName: doc.id == state.currentDocumentID
                              ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(doc.id == state.currentDocumentID
                                             ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(doc.title).lineLimit(1)
                            if let profileName = doc.profileName {
                                Text(profileName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { state.selectDocument(doc.id) }
                    .contextMenu {
                        Button("Rename…") { renameTarget = doc }
                        Button("Duplicate") { state.duplicateDocument(doc.id) }
                        Divider()
                        Button("Delete", role: .destructive) { deleteTarget = doc }
                    }
                }
                Button("New Script", systemImage: "plus") {
                    state.createDocument()
                }
                .help("Add a new empty script to the library")
            }
```

with view state + helpers:

```swift
    @State private var scriptSearch = ""
    @State private var renameTarget: ScriptDocumentMeta?
    @State private var renameText = ""
    @State private var deleteTarget: ScriptDocumentMeta?

    private var filteredDocuments: [ScriptDocumentMeta] {
        guard !scriptSearch.trimmingCharacters(in: .whitespaces).isEmpty
        else { return state.documents }
        return state.documents.filter {
            $0.title.localizedCaseInsensitiveContains(scriptSearch)
        }
    }
```

and alerts appended after the existing sheets:

```swift
        .alert("Rename Script",
               isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } })) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    state.renameDocument(target.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .onChange(of: renameTarget) { _, target in
            if let target { renameText = target.title }
        }
        .alert("Delete \"\(deleteTarget?.title ?? "")\"?",
               isPresented: Binding(get: { deleteTarget != nil },
                                    set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { state.deleteDocument(target.id) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Removes the script from the library. Exported audio files are not affected.")
        }
```

- [ ] **Step 2: `swift build`, commit** `feat: script library section in sidebar (#34)`

---

### Task 7: GeneratedAudio.sourceScript + CueAlignment (#35)

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift` (GeneratedAudio + generate/finishGeneration)
- Create: `Sources/KokoroStudio/CueAlignment.swift`
- Test: `Tests/KokoroStudioTests/CueAlignmentTests.swift`

- [ ] **Step 1: `sourceScript` on GeneratedAudio.** Add `let sourceScript: String` to the struct. In `generate()`, capture `let rawSource = textOverride ?? script` before the detached task; thread it into `finishGeneration` as a new parameter `sourceScript: String` and store it in the `GeneratedAudio` constructed there. (Module export doesn't create GeneratedAudio — no change.)

- [ ] **Step 2: Failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class CueAlignmentTests: XCTestCase {
    func testExactTextAlignsEveryCue() {
        let script = "First sentence here. Second one follows. Third closes."
        let cues = ["First sentence here.", "Second one follows.", "Third closes."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertEqual(ranges.count, 3)
        let ns = script as NSString
        XCTAssertEqual(ranges.compactMap { $0.map(ns.substring(with:)) }, cues)
    }

    func testRewrittenWordsStillAlignViaNeighbors() {
        // Dictionary turned "APA" into "A. P. A." in the cue; surrounding
        // words still anchor the sentence.
        let script = "Follow APA style closely. Then continue on."
        let cues = ["Follow A. P. A. style closely.", "Then continue on."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertNotNil(ranges[0])
        XCTAssertNotNil(ranges[1])
        let ns = script as NSString
        XCTAssertTrue(ns.substring(with: ranges[0]!).hasPrefix("Follow"))
        XCTAssertEqual(ns.substring(with: ranges[1]!), "Then continue on.")
    }

    func testUnmatchableCueIsNilWithoutDerailingRest() {
        let script = "Alpha beta gamma. Delta epsilon zeta."
        let cues = ["completely unrelated words", "Delta epsilon zeta."]
        let ranges = CueAlignment.align(cues: cues, script: script)
        XCTAssertNil(ranges[0])
        XCTAssertNotNil(ranges[1])
    }

    func testCueIndexAtTime() {
        let cues = [CaptionCue(start: 0, end: 2, text: "a"),
                    CaptionCue(start: 2.5, end: 4, text: "b")]
        XCTAssertEqual(CueAlignment.cueIndex(at: 1.0, cues: cues), 0)
        XCTAssertEqual(CueAlignment.cueIndex(at: 3.0, cues: cues), 1)
        XCTAssertNil(CueAlignment.cueIndex(at: 2.2, cues: cues)) // in the pause
        XCTAssertNil(CueAlignment.cueIndex(at: 9.0, cues: cues))
    }
}
```

- [ ] **Step 3: Implement `CueAlignment.swift`**

```swift
import Foundation

/// Maps caption cues back to ranges in the raw editor script (#35). Cue
/// text is post-preprocessing (dictionary and number rewrites), so exact
/// search fails; instead each cue is aligned by greedy in-order word
/// matching with skip tolerance. Sequential by construction — cues are in
/// document order, so the cursor only moves forward.
enum CueAlignment {
    static func align(cues: [String], script: String) -> [NSRange?] {
        let tokens = tokenize(script)
        var results: [NSRange?] = []
        var cursor = 0
        for cue in cues {
            let cueWords = tokenize(cue).map(\.norm)
            guard !cueWords.isEmpty, cursor < tokens.count else {
                results.append(nil)
                continue
            }
            // Anchor on the first (or second) cue word found ahead.
            var start: Int?
            anchorSearch: for anchor in cueWords.prefix(2) {
                for index in cursor..<min(cursor + 300, tokens.count)
                where tokens[index].norm == anchor {
                    start = index
                    break anchorSearch
                }
            }
            guard let startIndex = start else {
                results.append(nil)
                continue
            }
            var matched = 1
            var last = startIndex
            var scriptIndex = startIndex + 1
            for word in cueWords.dropFirst() {
                var lookahead = 0
                var index = scriptIndex
                while index < tokens.count, lookahead < 8 {
                    if tokens[index].norm == word {
                        matched += 1
                        last = index
                        scriptIndex = index + 1
                        break
                    }
                    index += 1
                    lookahead += 1
                }
            }
            // Under half the words matched: too unreliable to highlight.
            guard Double(matched) / Double(cueWords.count) >= 0.5 else {
                results.append(nil)
                continue
            }
            let startLocation = tokens[startIndex].range.location
            let endLocation = tokens[last].range.location + tokens[last].range.length
            results.append(NSRange(location: startLocation,
                                   length: endLocation - startLocation))
            cursor = last + 1
        }
        return results
    }

    /// The cue audible at `time`, nil during spliced pauses or past the end.
    static func cueIndex(at time: Double, cues: [CaptionCue]) -> Int? {
        cues.firstIndex { time >= $0.start && time < $0.end }
    }

    static func tokenize(_ text: String) -> [(norm: String, range: NSRange)] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        return regex.matches(in: text,
                             range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                let norm = ns.substring(with: match.range).lowercased()
                    .filter { $0.isLetter || $0.isNumber }
                guard !norm.isEmpty else { return nil }
                return (norm, match.range)
            }
    }
}
```

- [ ] **Step 4: Run CueAlignmentTests, expect 4 PASS.** The "in the pause" assertion depends on `cueIndex` using strict interval containment — don't snap to nearest cue.

- [ ] **Step 5: `swift build`, commit** `feat: cue-to-editor alignment, sourceScript on GeneratedAudio (#35)`

---

### Task 8: Follow-along highlighter + click-to-seek + settings toggle (#35)

**Files:**
- Create: `Sources/KokoroStudio/Views/FollowAlongHighlighter.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift`
- Modify: `Sources/KokoroStudio/Views/WritingToolsButton.swift` (`EditorTextAccess.findTextView` non-focusing variant)
- Modify: `Sources/KokoroStudio/AppState.swift` (`followAlongHighlight` AppStorage)
- Modify: `Sources/KokoroStudio/Views/SettingsView.swift` (toggle in Playback section)

- [ ] **Step 1: non-focusing finder** in `EditorTextAccess`:

```swift
    /// Find-only variant: never steals first responder. Searches the given
    /// window first, then any window with an editable text view.
    static func findTextView(in window: NSWindow?) -> NSTextView? {
        if let window, let contentView = window.contentView,
           let textView = find(in: contentView) {
            return textView
        }
        for candidate in NSApp.windows {
            if let contentView = candidate.contentView,
               let textView = find(in: contentView) {
                return textView
            }
        }
        return nil
    }
```

- [ ] **Step 2: AppState storage** (next to `autoplayAfterGenerate`):

```swift
    @AppStorage("followAlongHighlight") var followAlongHighlight = true
```

- [ ] **Step 3: `FollowAlongHighlighter.swift`**

```swift
import SwiftUI
import AppKit

/// Highlights the sentence being spoken in the editor and maps clicks
/// back to cue times (#35). Uses layout-manager temporary attributes so
/// the highlight never touches the script text or undo stack.
@MainActor
final class FollowAlongHighlighter: ObservableObject {
    private var cues: [CaptionCue] = []
    private var alignedRanges: [NSRange?] = []
    private var activeIndex: Int?
    private weak var textView: NSTextView?

    var isReady: Bool { !cues.isEmpty }

    /// Builds the cue->editor mapping. Bails for previews (cues map to the
    /// selection, not the document) and stale audio (script edited since
    /// generation) — a mis-aligned highlight is worse than none.
    func prepare(audio: AppState.GeneratedAudio?, script: String) {
        clearHighlight()
        cues = []
        alignedRanges = []
        activeIndex = nil
        guard let audio, !audio.isPreview, audio.sourceScript == script else {
            return
        }
        cues = audio.cues
        alignedRanges = CueAlignment.align(cues: cues.map(\.text), script: script)
        textView = EditorTextAccess.findTextView(in: NSApp.keyWindow)
    }

    func update(time: Double) {
        guard isReady else { return }
        let index = CueAlignment.cueIndex(at: time, cues: cues)
        guard index != activeIndex else { return }
        clearHighlight()
        activeIndex = index
        guard let index, let range = alignedRanges[index],
              let textView, let layoutManager = textView.layoutManager,
              NSMaxRange(range) <= (textView.string as NSString).length else {
            return
        }
        layoutManager.addTemporaryAttribute(
            .backgroundColor,
            value: NSColor.findHighlightColor.withAlphaComponent(0.45),
            forCharacterRange: range)
        textView.scrollRangeToVisible(range)
    }

    func clearHighlight() {
        guard let textView, let layoutManager = textView.layoutManager else {
            return
        }
        let fullRange = NSRange(location: 0,
                                length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor,
                                               forCharacterRange: fullRange)
        activeIndex = nil
    }

    /// Cue start time for a click at a character location, if it lands
    /// inside an aligned sentence.
    func seekTarget(forCharacterAt location: Int) -> Double? {
        for (index, range) in alignedRanges.enumerated() {
            if let range, NSLocationInRange(location, range) {
                return cues[index].start
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: ContentView glue.**
  - `@StateObject private var highlighter = FollowAlongHighlighter()`
  - Extend the existing `.onChange(of: state.lastAudio?.previewWAV)` body with `highlighter.prepare(audio: state.lastAudio, script: state.script)`.
  - Add `.onChange(of: state.script) { highlighter.prepare(audio: state.lastAudio, script: state.script) }` (re-checks staleness; cheap because prepare bails on mismatch).
  - Add `.onReceive(player.$currentTime) { time in if state.followAlongHighlight, player.isPlaying { highlighter.update(time: time) } }`
  - Add `.onChange(of: player.isPlaying) { _, playing in if !playing { highlighter.clearHighlight() } }`
  - Click-to-seek inside the existing `didChangeSelectionNotification` `.onReceive`: after updating `hasEditorSelection`, append:

```swift
            // Click-to-seek: only while playing, so ordinary caret
            // placement during editing never jumps the audio.
            if player.isPlaying, state.followAlongHighlight,
               let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
               textView.selectedRange().length == 0,
               let target = highlighter.seekTarget(
                   forCharacterAt: textView.selectedRange().location) {
                player.seek(to: target)
            }
```

- [ ] **Step 5: Settings toggle** — `GeneralSettingsTab` Playback section:

```swift
                Toggle("Highlight sentence during playback",
                       isOn: $state.followAlongHighlight)
                    .help("Follows along in the editor while audio plays; click a sentence to jump there")
```

- [ ] **Step 6: `swift build`, full filtered test pass, commit** `feat: follow-along sentence highlight with click-to-seek (#35)`

---

### Task 9: WaveformBuilder (#36)

**Files:**
- Create: `Sources/KokoroStudio/WaveformBuilder.swift`
- Test: `Tests/KokoroStudioTests/WaveformBuilderTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import KokoroStudio

final class WaveformBuilderTests: XCTestCase {
    func testPeaksBucketCountAndNormalization() {
        let samples: [Float] = [0.1, -0.5, 0.2, 0.25, 0.0, -0.1, 0.05, 0.02]
        let peaks = WaveformBuilder.peaks(samples: samples, buckets: 4)
        XCTAssertEqual(peaks.count, 4)
        XCTAssertEqual(peaks[0], 1.0)          // 0.5 is the global max
        XCTAssertEqual(peaks[1], 0.5, accuracy: 0.001) // 0.25 / 0.5
        XCTAssertEqual(peaks.max(), 1.0)
    }

    func testPeaksEmptyAndOversizedBuckets() {
        XCTAssertEqual(WaveformBuilder.peaks(samples: [], buckets: 10), [])
        // Fewer samples than buckets still draws something sensible.
        let peaks = WaveformBuilder.peaks(samples: [0.5, 0.25], buckets: 10)
        XCTAssertFalse(peaks.isEmpty)
        XCTAssertLessThanOrEqual(peaks.count, 10)
    }

    func testHeadingMarkersMatchHeadingCues() {
        let script = "# Intro\nWelcome along.\n# Wrap Up\nThat is all."
        let cues = [CaptionCue(start: 0.0, end: 0.8, text: "Intro"),
                    CaptionCue(start: 1.0, end: 2.5, text: "Welcome along."),
                    CaptionCue(start: 3.0, end: 3.9, text: "Wrap Up"),
                    CaptionCue(start: 4.0, end: 5.0, text: "That is all.")]
        XCTAssertEqual(WaveformBuilder.headingMarkers(cues: cues, script: script),
                       [HeadingMarker(time: 0.0, title: "Intro"),
                        HeadingMarker(time: 3.0, title: "Wrap Up")])
    }

    func testNoHeadingsNoMarkers() {
        let cues = [CaptionCue(start: 0, end: 1, text: "Hello.")]
        XCTAssertTrue(WaveformBuilder.headingMarkers(cues: cues,
                                                     script: "Hello.").isEmpty)
    }
}
```

- [ ] **Step 2: Implement `WaveformBuilder.swift`**

```swift
import Foundation

struct HeadingMarker: Equatable {
    let time: Double
    let title: String
}

/// Player-bar waveform data (#36): bucketed peaks for drawing and heading
/// tick positions derived from the same cue table captions use.
enum WaveformBuilder {
    /// Downsamples to at most `buckets` peak values, normalized so the
    /// loudest bucket is 1.0 (quiet audio still draws visibly).
    static func peaks(samples: [Float], buckets: Int) -> [Float] {
        guard buckets > 0, !samples.isEmpty else { return [] }
        let bucketSize = max(1, samples.count / buckets)
        var result: [Float] = []
        result.reserveCapacity(buckets)
        var start = 0
        while start < samples.count, result.count < buckets {
            let end = min(start + bucketSize, samples.count)
            var peak: Float = 0
            for index in start..<end {
                peak = max(peak, abs(samples[index]))
            }
            result.append(peak)
            start = end
        }
        if let maximum = result.max(), maximum > 0 {
            result = result.map { $0 / maximum }
        }
        return result
    }

    /// Cues whose text matches a `#` heading line of the source script,
    /// compared with punctuation/case stripped — preprocessing may have
    /// altered both sides slightly.
    static func headingMarkers(cues: [CaptionCue],
                               script: String) -> [HeadingMarker] {
        let headingTexts = Set(
            script.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("#") }
                .map { normalized(String($0.drop { $0 == "#" })) }
                .filter { !$0.isEmpty })
        guard !headingTexts.isEmpty else { return [] }
        return cues.filter { headingTexts.contains(normalized($0.text)) }
            .map { HeadingMarker(time: $0.start, title: $0.text) }
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
```

- [ ] **Step 3: Run, expect 4 PASS. Commit** `feat: waveform peaks and heading markers (#36)`

---

### Task 10: WaveformView in PlayerBar (#36)

**Files:**
- Create: `Sources/KokoroStudio/Views/WaveformView.swift`
- Modify: `Sources/KokoroStudio/Views/PlayerBar.swift`

- [ ] **Step 1: `WaveformView.swift`**

```swift
import SwiftUI

/// Clickable waveform scrubber with heading tick marks (#36). Falls back
/// to nothing when peaks are empty — PlayerBar keeps its Slider then.
struct WaveformView: View {
    let peaks: [Float]
    let markers: [HeadingMarker]
    let duration: Double
    let currentTime: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let count = peaks.count
                    guard count > 0 else { return }
                    let barWidth = size.width / CGFloat(count)
                    let playedX = duration > 0
                        ? size.width * CGFloat(currentTime / duration) : 0
                    for (index, peak) in peaks.enumerated() {
                        let x = CGFloat(index) * barWidth
                        let barHeight = max(1.5, size.height * CGFloat(peak))
                        let rect = CGRect(x: x,
                                          y: (size.height - barHeight) / 2,
                                          width: max(1, barWidth - 1),
                                          height: barHeight)
                        let played = x + barWidth / 2 <= playedX
                        context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                                     with: .color(played
                                                  ? Color.accentColor
                                                  : Color.secondary.opacity(0.45)))
                    }
                }

                // Heading ticks with hover titles.
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    let x = duration > 0
                        ? width * CGFloat(marker.time / duration) : 0
                    Rectangle()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 1.5, height: height)
                        .offset(x: x)
                        .help(marker.title)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in seek(at: value.location.x, width: width) }
                    .onEnded { value in seek(at: value.location.x, width: width) })
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(Int(currentTime)) of \(Int(duration)) seconds")
        .accessibilityAdjustableAction { direction in
            let step = max(1, duration / 20)
            onSeek(direction == .increment
                   ? min(duration, currentTime + step)
                   : max(0, currentTime - step))
        }
    }

    private func seek(at x: CGFloat, width: CGFloat) {
        guard duration > 0, width > 0 else { return }
        let fraction = min(max(x / width, 0), 1)
        onSeek(Double(fraction) * duration)
    }
}
```

- [ ] **Step 2: PlayerBar integration.** Add state + recompute:

```swift
    @State private var peaks: [Float] = []
    @State private var markers: [HeadingMarker] = []

    private func rebuildWaveform() {
        guard let audio = state.lastAudio else {
            peaks = []
            markers = []
            return
        }
        peaks = WaveformBuilder.peaks(samples: audio.samples, buckets: 240)
        markers = WaveformBuilder.headingMarkers(cues: audio.cues,
                                                 script: audio.sourceScript)
    }
```

Replace the Slider block with:

```swift
            if peaks.isEmpty {
                Slider(value: Binding(get: { player.currentTime },
                                      set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 0.01)) {
                    Text("Playback position")
                }
                .labelsHidden()
            } else {
                WaveformView(peaks: peaks, markers: markers,
                             duration: player.duration,
                             currentTime: player.currentTime,
                             onSeek: { player.seek(to: $0) })
            }
```

and at the end of the HStack's modifiers:

```swift
        .onAppear { rebuildWaveform() }
        .onChange(of: state.lastAudio?.previewWAV) { rebuildWaveform() }
```

- [ ] **Step 3: `swift build`, commit** `feat: waveform scrubber with heading ticks in player bar (#36)`

---

### Task 11: Full verification

- [ ] **Step 1:** `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test` — all green, no regressions.
- [ ] **Step 2:** `./scripts/build-app.sh` — app assembles.
- [ ] **Step 3:** Report manual smoke checklist (import preview from a real .docx, library switching with profiles, follow-along during playback, waveform clicks) — do NOT push or ship.
