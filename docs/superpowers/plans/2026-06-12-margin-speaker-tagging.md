# Margin Speaker Tagging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a toggleable left-margin speaker-tagging mode to the script editor that reads and writes the existing `@Speaker:` syntax — one clickable icon per paragraph, colored speaker chips, and a Liquid-Glass assignment popover.

**Architecture:** A visual front-end over the `@Speaker:` text, which stays the single source of truth. Pure, testable logic (`SpeakerIdentity`, `ParagraphSpeakers`, `SpeakerTagEditor`) computes effective speakers and produces minimal range-edits; AppKit rendering (gutter overlay + speaker chips) and a SwiftUI popover sit on top. The text→audio pipeline, segmenter, and patcher are untouched. **"Narrator" is a reserved speaker name** bound to the default voice, so a narrator reset is just an ordinary `@Narrator:` tag.

**Tech Stack:** Swift / SwiftUI / AppKit (macOS 14+), SwiftPM, XCTest. Domain logic in caseless `enum` namespaces, matching the repo convention (`ScriptSegmenter`, `CueAlignment`, …).

---

## Conventions

- Build: `swift build`
- Run a test class: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter <ClassName>`
- The pure-logic tests (Tasks 2–4) need no models or dylibs, but running through `swift test` still wants the path; the command above is safe for all.
- Swift regex literals must use `#/.../#` delimiters (repo gotcha).
- The speaker-tag regex used everywhere is the segmenter's: `#/^@([\w ]+):\s*(.*)$/#`.
- Reserved narrator name: the string `"Narrator"`.

## File Structure

**Create (logic + tests):**
- `Sources/KokoroStudio/SpeakerIdentity.swift` — palette of colors/symbols + deterministic auto-assignment. One responsibility: a speaker's visual identity.
- `Sources/KokoroStudio/ParagraphSpeakers.swift` — parse script into paragraph spans with effective (sticky) speaker. One responsibility: "who speaks each paragraph."
- `Sources/KokoroStudio/SpeakerTagEditor.swift` — produce a minimal range-edit to assign a speaker to a paragraph (smart insert/clean). One responsibility: "how to rewrite the text."
- `Tests/KokoroStudioTests/SpeakerIdentityTests.swift`
- `Tests/KokoroStudioTests/ParagraphSpeakersTests.swift`
- `Tests/KokoroStudioTests/SpeakerTagEditorTests.swift`

**Create (UI):**
- `Sources/KokoroStudio/Views/SpeakerGutterView.swift` — AppKit overlay drawing the clickable per-paragraph icons, aligned to the editor's text via the layout manager.
- `Sources/KokoroStudio/Views/SpeakerChipRenderer.swift` — applies chip styling to `@Name:` ranges via layout-manager temporary attributes (Fallback B baseline; the rounded-background "A" enhancement is Task 11).
- `Sources/KokoroStudio/Views/SpeakerPickerPopover.swift` — SwiftUI Liquid-Glass popover for assigning / creating a speaker.

**Modify:**
- `Sources/KokoroStudio/AppState.swift` — new `@AppStorage` maps + mode flag + accessors (Task 1); confirm "Narrator"/unknown speaker resolves to the default voice (Task 5).
- `Sources/KokoroStudio/Views/ContentView.swift` — toolbar toggle (Task 6); host the gutter + chips + popover in `EditorView` (Tasks 7–10).

---

## Task 1: AppState data model

**Files:**
- Modify: `Sources/KokoroStudio/AppState.swift` (near the existing `speakerVoices` accessor, ~line 90; and the `@AppStorage` block, ~line 77)

- [ ] **Step 1: Add the storage fields and mode flag**

In the `@AppStorage` block near `speakerVoicesJSON` (line 77), add:

```swift
    @AppStorage("speakerColors") var speakerColorsJSON = ""
    @AppStorage("speakerSymbols") var speakerSymbolsJSON = ""
    @AppStorage("marginSpeakerMode") var marginSpeakerMode = false
```

- [ ] **Step 2: Add the typed accessors**

Immediately after the `speakerSpeeds` computed property (ends ~line 120), add two accessors that mirror the existing JSON-map pattern exactly:

```swift
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
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: builds with no errors (warnings about unused properties are fine until later tasks wire them up).

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/AppState.swift
git commit -m "feat: AppState storage for speaker colors, symbols, and margin mode"
```

---

## Task 2: SpeakerIdentity (palette + auto-assignment)

**Files:**
- Create: `Sources/KokoroStudio/SpeakerIdentity.swift`
- Test: `Tests/KokoroStudioTests/SpeakerIdentityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/KokoroStudioTests/SpeakerIdentityTests.swift`:

```swift
import XCTest
@testable import KokoroStudio

final class SpeakerIdentityTests: XCTestCase {
    func testNarratorHasFixedStyle() {
        let style = SpeakerIdentity.style(for: "Narrator",
                                          colorOverrides: [:], symbolOverrides: [:])
        XCTAssertEqual(style.colorIndex, SpeakerIdentity.narratorColorIndex)
        XCTAssertEqual(style.symbolIndex, SpeakerIdentity.narratorSymbolIndex)
    }

    func testNextFreeStylePicksLowestUnusedSlot() {
        let next = SpeakerIdentity.nextFreeStyle(usedColors: [0, 1], usedSymbols: [0, 1])
        XCTAssertEqual(next.colorIndex, 2)
        XCTAssertEqual(next.symbolIndex, 2)
    }

    func testNextFreeStyleWrapsWhenPaletteFull() {
        let used = Array(0..<SpeakerIdentity.paletteCount)
        let next = SpeakerIdentity.nextFreeStyle(usedColors: used, usedSymbols: used)
        XCTAssertTrue((0..<SpeakerIdentity.paletteCount).contains(next.colorIndex))
    }

    func testOverrideTakesPrecedence() {
        let style = SpeakerIdentity.style(for: "Alex",
                                          colorOverrides: ["Alex": 5],
                                          symbolOverrides: ["Alex": 3])
        XCTAssertEqual(style.colorIndex, 5)
        XCTAssertEqual(style.symbolIndex, 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SpeakerIdentityTests`
Expected: FAIL — `cannot find 'SpeakerIdentity' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/KokoroStudio/SpeakerIdentity.swift`:

```swift
import AppKit

/// Visual identity (color + SF Symbol) for a speaker in margin mode.
/// Pure data + deterministic slot assignment; no app state.
enum SpeakerIdentity {
    struct Style: Equatable {
        let colorIndex: Int
        let symbolIndex: Int
    }

    /// SF Symbol names, one per palette slot.
    static let symbolNames = [
        "circle.fill", "diamond.fill", "triangle.fill", "square.fill",
        "hexagon.fill", "star.fill", "seal.fill", "drop.fill",
    ]

    /// Palette colors, index-aligned with `symbolNames`.
    static let colors: [NSColor] = [
        .systemBlue, .systemOrange, .systemGreen, .systemPurple,
        .systemPink, .systemTeal, .systemYellow, .systemRed,
    ]

    static var paletteCount: Int { symbolNames.count }

    static let narratorName = "Narrator"
    static let narratorColorIndex = -1   // sentinel: render gray
    static let narratorSymbolIndex = -1  // sentinel: render "text.alignleft"

    static let narratorColor = NSColor.systemGray
    static let narratorSymbolName = "text.alignleft"

    /// Resolve a speaker to its style, honoring overrides, else auto-assigning.
    static func style(for name: String,
                      colorOverrides: [String: Int],
                      symbolOverrides: [String: Int]) -> Style {
        if name == narratorName {
            return Style(colorIndex: narratorColorIndex, symbolIndex: narratorSymbolIndex)
        }
        let auto = nextFreeStyle(usedColors: Array(colorOverrides.values),
                                 usedSymbols: Array(symbolOverrides.values))
        return Style(colorIndex: colorOverrides[name] ?? auto.colorIndex,
                     symbolIndex: symbolOverrides[name] ?? auto.symbolIndex)
    }

    /// Lowest palette slot not already used; wraps modulo when full.
    static func nextFreeStyle(usedColors: [Int], usedSymbols: [Int]) -> Style {
        Style(colorIndex: lowestFree(in: usedColors),
              symbolIndex: lowestFree(in: usedSymbols))
    }

    private static func lowestFree(in used: [Int]) -> Int {
        let set = Set(used)
        for i in 0..<paletteCount where !set.contains(i) { return i }
        return (used.max() ?? -1).advanced(by: 1) % paletteCount
    }

    /// Display color for a resolved style (handles the narrator sentinel).
    static func displayColor(colorIndex: Int) -> NSColor {
        colorIndex < 0 ? narratorColor : colors[colorIndex % colors.count]
    }

    /// SF Symbol name for a resolved style (handles the narrator sentinel).
    static func displaySymbol(symbolIndex: Int) -> String {
        symbolIndex < 0 ? narratorSymbolName : symbolNames[symbolIndex % symbolNames.count]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SpeakerIdentityTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/SpeakerIdentity.swift Tests/KokoroStudioTests/SpeakerIdentityTests.swift
git commit -m "feat: SpeakerIdentity palette and deterministic auto-assignment"
```

---

## Task 3: ParagraphSpeakers (effective-speaker resolution)

**Files:**
- Create: `Sources/KokoroStudio/ParagraphSpeakers.swift`
- Test: `Tests/KokoroStudioTests/ParagraphSpeakersTests.swift`

**Contract:** A paragraph is a maximal run of consecutive non-blank lines (blank = empty or whitespace only). `resolve` returns one `Span` per paragraph, in document order. `speaker` is the effective speaker as of the paragraph's first line (after applying that line's tag if present); untagged paragraphs inherit from above, defaulting to `"Narrator"`. `hasLiteralTag` is true when the paragraph's first line is itself an `@Name:` tag. A tag on a non-first line updates inheritance for *later* paragraphs but does not change the current paragraph's `speaker` (documented edge case).

- [ ] **Step 1: Write the failing test**

Create `Tests/KokoroStudioTests/ParagraphSpeakersTests.swift`:

```swift
import XCTest
@testable import KokoroStudio

final class ParagraphSpeakersTests: XCTestCase {
    func testUntaggedScriptIsAllNarrator() {
        let script = "First para.\n\nSecond para."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans.map(\.speaker), ["Narrator", "Narrator"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [false, false])
    }

    func testInlineTagSetsSpeakerForItsParagraph() {
        let script = "@Alex: Hello there.\n\n@Sam: Hi back."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Sam"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [true, true])
    }

    func testTagIsStickyAcrossUntaggedParagraphs() {
        let script = "@Alex:\nLine one.\n\nLine two still Alex.\n\n@Sam:\nNow Sam."
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Alex", "Sam"])
        XCTAssertEqual(spans.map(\.hasLiteralTag), [true, false, true])
    }

    func testBlankLinesProduceNoEmptySpans() {
        let script = "\n\n@Alex:\nHello.\n\n\n\nGoodbye.\n"
        let spans = ParagraphSpeakers.resolve(script: script)
        XCTAssertEqual(spans.map(\.speaker), ["Alex", "Alex"])
    }

    func testSpanRangesCoverTheRightText() {
        let script = "@Alex:\nHello.\n\nGoodbye."
        let spans = ParagraphSpeakers.resolve(script: script)
        let ns = script as NSString
        XCTAssertTrue(ns.substring(with: spans[0].range).contains("@Alex:"))
        XCTAssertTrue(ns.substring(with: spans[1].range).contains("Goodbye."))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter ParagraphSpeakersTests`
Expected: FAIL — `cannot find 'ParagraphSpeakers' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/KokoroStudio/ParagraphSpeakers.swift`:

```swift
import Foundation

/// Splits a script into paragraph blocks and resolves the effective
/// (sticky) `@Speaker:` for each. Pure logic — no AppKit, no models.
enum ParagraphSpeakers {
    static let narratorName = "Narrator"

    struct Span: Equatable {
        let range: NSRange      // character range of the paragraph in the script
        let speaker: String     // effective speaker name ("Narrator" by default)
        let hasLiteralTag: Bool // first line of the paragraph is an @Name: tag
    }

    static func resolve(script: String) -> [Span] {
        let ns = script as NSString
        var spans: [Span] = []
        var effective = narratorName

        var blockRange: NSRange?
        var blockSpeaker = narratorName
        var blockHasTag = false
        var blockHasFirstLine = false

        func endBlock() {
            if let range = blockRange {
                spans.append(Span(range: range, speaker: blockSpeaker,
                                  hasLiteralTag: blockHasTag))
            }
            blockRange = nil
            blockHasTag = false
            blockHasFirstLine = false
        }

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines]) { line, lineRange, enclosingRange, _ in
            let trimmed = (line ?? "").trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                endBlock()
                return
            }
            var isTagLine = false
            if let match = trimmed.firstMatch(of: #/^@([\w ]+):\s*(.*)$/#) {
                effective = String(match.1).trimmingCharacters(in: .whitespaces)
                isTagLine = true
            }
            if blockRange == nil {
                blockRange = enclosingRange
            } else {
                blockRange = NSUnionRange(blockRange!, enclosingRange)
            }
            if !blockHasFirstLine {
                blockSpeaker = effective
                blockHasTag = isTagLine
                blockHasFirstLine = true
            }
        }
        endBlock()
        return spans
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter ParagraphSpeakersTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/ParagraphSpeakers.swift Tests/KokoroStudioTests/ParagraphSpeakersTests.swift
git commit -m "feat: ParagraphSpeakers resolves sticky effective speakers per paragraph"
```

---

## Task 4: SpeakerTagEditor (smart insert/clean)

**Files:**
- Create: `Sources/KokoroStudio/SpeakerTagEditor.swift`
- Test: `Tests/KokoroStudioTests/SpeakerTagEditorTests.swift`

**Contract:** `assign(script:, paragraphIndex:, to:)` returns a single `(range, replacement)` edit, or `nil` if the index is out of range. Applying the edit to `script` yields the new script. Rules: the *inherited* speaker for paragraph `i` is paragraph `i-1`'s effective speaker (or `"Narrator"` for `i == 0`).
- chosen == inherited, paragraph has a literal tag → strip the tag (bare tag line removed entirely; inline `@Name: text` keeps `text`).
- chosen == inherited, no literal tag → no-op (empty edit at paragraph start).
- chosen != inherited, no literal tag → insert `@chosen:\n` at paragraph start.
- chosen != inherited, has literal tag → rewrite the tag line's name, preserving any inline text.

- [ ] **Step 1: Write the failing test**

Create `Tests/KokoroStudioTests/SpeakerTagEditorTests.swift`:

```swift
import XCTest
@testable import KokoroStudio

final class SpeakerTagEditorTests: XCTestCase {
    private func apply(_ script: String, _ index: Int, _ speaker: String) -> String? {
        guard let edit = SpeakerTagEditor.assign(script: script,
                                                 paragraphIndex: index, to: speaker)
        else { return nil }
        let ns = script as NSString
        return ns.replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testInsertsTagWhenSpeakerDiffersFromInherited() {
        let script = "Hello there.\n\nGoodbye now."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "Hello there.\n\n@Alex:\nGoodbye now.")
    }

    func testNoOpWhenSpeakerMatchesInherited() {
        let script = "Hello there.\n\nGoodbye now."
        // Paragraph 0 inherits Narrator; choosing Narrator changes nothing.
        XCTAssertEqual(apply(script, 0, "Narrator"), script)
    }

    func testStripsRedundantBareTag() {
        // Both paragraphs are Alex; tagging para 1 as Alex (already inherited)
        // removes its now-redundant tag.
        let script = "@Alex:\nFirst.\n\n@Alex:\nSecond."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "@Alex:\nFirst.\n\nSecond.")
    }

    func testStripsRedundantInlineTagButKeepsText() {
        let script = "@Alex:\nFirst.\n\n@Alex: Second."
        XCTAssertEqual(apply(script, 1, "Alex"),
                       "@Alex:\nFirst.\n\nSecond.")
    }

    func testRenamesExistingTag() {
        let script = "@Alex:\nHello."
        XCTAssertEqual(apply(script, 0, "Sam"), "@Sam:\nHello.")
    }

    func testRenamesExistingInlineTagPreservingText() {
        let script = "@Alex: Hello there."
        XCTAssertEqual(apply(script, 0, "Sam"), "@Sam: Hello there.")
    }

    func testNarratorResetInsertsNarratorTag() {
        let script = "@Alex:\nHello.\n\nStill Alex here."
        XCTAssertEqual(apply(script, 1, "Narrator"),
                       "@Alex:\nHello.\n\n@Narrator:\nStill Alex here.")
    }

    func testOutOfRangeReturnsNil() {
        XCTAssertNil(SpeakerTagEditor.assign(script: "Hi.", paragraphIndex: 5, to: "Alex"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SpeakerTagEditorTests`
Expected: FAIL — `cannot find 'SpeakerTagEditor' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/KokoroStudio/SpeakerTagEditor.swift`:

```swift
import Foundation

/// Produces the minimal text edit to assign a speaker to a paragraph,
/// keeping `@Speaker:` tags only where the speaker actually changes.
/// Pure logic — returns a range replacement for the caller to apply.
enum SpeakerTagEditor {
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    static func assign(script: String, paragraphIndex: Int, to speaker: String) -> Edit? {
        let spans = ParagraphSpeakers.resolve(script: script)
        guard spans.indices.contains(paragraphIndex) else { return nil }
        let span = spans[paragraphIndex]
        let ns = script as NSString

        let inherited = paragraphIndex == 0
            ? ParagraphSpeakers.narratorName
            : spans[paragraphIndex - 1].speaker

        // First line of the paragraph (content range + terminator).
        let firstLineRange = ns.lineRange(
            for: NSRange(location: span.range.location, length: 0))
        let firstLine = ns.substring(with: firstLineRange)
        let firstLineNoNewline = firstLine.trimmingCharacters(in: .newlines)
        let inlineText: String? = {
            guard span.hasLiteralTag,
                  let match = firstLineNoNewline.firstMatch(of: #/^@([\w ]+):\s*(.*)$/#)
            else { return nil }
            let rest = String(match.2)
            return rest.isEmpty ? nil : rest
        }()

        if speaker == inherited {
            guard span.hasLiteralTag else {
                return Edit(range: NSRange(location: span.range.location, length: 0),
                            replacement: "") // no-op
            }
            if let inlineText {
                // Drop just the "@Name: " prefix, keep the spoken text.
                return Edit(range: firstLineRange, replacement: inlineText + "\n")
            }
            // Bare tag line: remove it entirely.
            return Edit(range: firstLineRange, replacement: "")
        }

        // speaker != inherited
        if span.hasLiteralTag {
            let replacementLine = inlineText.map { "@\(speaker): \($0)" } ?? "@\(speaker):"
            // Preserve the original terminator (newline or end-of-string).
            let terminator = firstLine.hasSuffix("\n") ? "\n" : ""
            return Edit(range: firstLineRange, replacement: replacementLine + terminator)
        }
        return Edit(range: NSRange(location: span.range.location, length: 0),
                    replacement: "@\(speaker):\n")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SpeakerTagEditorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/SpeakerTagEditor.swift Tests/KokoroStudioTests/SpeakerTagEditorTests.swift
git commit -m "feat: SpeakerTagEditor emits minimal smart insert/clean edits"
```

---

## Task 5: Confirm "Narrator"/unknown speaker maps to the default voice

The reserved `"Narrator"` name (and any speaker with no `speakerVoices` entry) must synthesize with the main `voiceID`. This is almost certainly already the behavior, but lock it with a test so the reserved-name assumption can't silently break.

**Files:**
- Test: `Tests/KokoroStudioTests/SpeakerTagEditorTests.swift` (append) — or a small dedicated test if voice resolution lives in a pure helper.
- Inspect: `Sources/KokoroStudio/AppState.swift` (search for where `speakerVoices` is read during `makeSynthesisPlan`).

- [ ] **Step 1: Locate voice resolution**

Run: `grep -n "speakerVoices\[" Sources/KokoroStudio/AppState.swift`
Read the surrounding lines. Identify the expression that maps a segment's `speaker` name to a voice ID (expected shape: `speakerVoices[name] ?? voiceID`).

- [ ] **Step 2: If resolution is inline, extract a pure helper**

If the lookup is an inline `speakerVoices[name] ?? voiceID`, leave it. If it is more complex, extract a static pure function so it can be tested, e.g. in `AppState.swift`:

```swift
    /// Voice ID for a speaker name: explicit mapping, else the default voice.
    /// "Narrator" and any unmapped name fall through to `defaultVoiceID`.
    static func voiceID(forSpeaker name: String?,
                        mapping: [String: Int],
                        defaultVoiceID: Int) -> Int {
        guard let name, let id = mapping[name] else { return defaultVoiceID }
        return id
    }
```

Then use it at the existing call site.

- [ ] **Step 3: Write the test**

Append to `SpeakerTagEditorTests.swift` (or a new `SpeakerVoiceResolutionTests.swift` if you extracted the helper):

```swift
    func testNarratorAndUnknownResolveToDefaultVoice() {
        let map = ["Alex": 7]
        XCTAssertEqual(
            AppState.voiceID(forSpeaker: "Narrator", mapping: map, defaultVoiceID: 3), 3)
        XCTAssertEqual(
            AppState.voiceID(forSpeaker: "Unknown", mapping: map, defaultVoiceID: 3), 3)
        XCTAssertEqual(
            AppState.voiceID(forSpeaker: "Alex", mapping: map, defaultVoiceID: 3), 7)
        XCTAssertEqual(
            AppState.voiceID(forSpeaker: nil, mapping: map, defaultVoiceID: 3), 3)
    }
```

If you did **not** extract a helper (the inline `?? voiceID` was already correct), skip this test and instead add a one-line comment at the call site noting that `"Narrator"` intentionally relies on the default-voice fallthrough, then move on.

- [ ] **Step 4: Run tests + build**

Run: `swift build && DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter SpeakerTagEditorTests`
Expected: builds; tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test: lock Narrator/unknown speaker to default voice resolution"
```

---

## Task 6: Toolbar toggle for margin mode

Wire the mode flag to a toolbar button. No gutter/chips yet — just prove the toggle flips state and persists.

**Files:**
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (the `.toolbar(id: "main")` block, ~line 196 alongside the "editing" `ToolbarItem`)

- [ ] **Step 1: Add a toolbar toggle**

Inside `.toolbar(id: "main")`, after the `"editing"` `ToolbarItem` (closes ~line 209), add:

```swift
            ToolbarItem(id: "margin-speakers") {
                Button {
                    state.marginSpeakerMode.toggle()
                } label: {
                    Label("Speaker Margins",
                          systemImage: state.marginSpeakerMode
                              ? "person.crop.rectangle.badge.plus.fill"
                              : "person.crop.rectangle.badge.plus")
                }
                .help(state.marginSpeakerMode
                      ? "Hide the speaker margin"
                      : "Show speaker icons in the margin to assign voices per paragraph")
            }
```

- [ ] **Step 2: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: the toolbar shows a new toggle; clicking flips the icon; quitting and relaunching preserves the on/off state (it is `@AppStorage`-backed).

- [ ] **Step 3: Commit**

```bash
git add Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: toolbar toggle for speaker margin mode"
```

---

## Task 7: Speaker chips (Fallback B baseline)

Render each `@Name:` tag range with a colored tint + leading dot via layout-manager temporary attributes — the same mechanism as `FollowAlongHighlighter`, so the two coexist (chips use `.foregroundColor`/`.backgroundColor` on tag ranges only; follow-along uses `.backgroundColor` on sentence ranges — verify no visible clash on tag lines during playback). This is the safe baseline; the rounded-pill "A" look is Task 11.

**Files:**
- Create: `Sources/KokoroStudio/Views/SpeakerChipRenderer.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (`EditorView`, ~line 428)

- [ ] **Step 1: Create the renderer**

Create `Sources/KokoroStudio/Views/SpeakerChipRenderer.swift`:

```swift
import AppKit

/// Tints `@Name:` tag ranges in the editor with each speaker's color via
/// layout-manager temporary attributes. Never edits the text or undo stack.
@MainActor
enum SpeakerChipRenderer {
    /// Apply (or, when `enabled` is false, clear) chip styling for `script`.
    static func apply(enabled: Bool,
                      script: String,
                      colorOverrides: [String: Int],
                      symbolOverrides: [String: Int],
                      in textView: NSTextView?) {
        guard let textView, let lm = textView.layoutManager else { return }
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)

        guard enabled else { return }
        let ns = script as NSString
        for span in ParagraphSpeakers.resolve(script: script) where span.hasLiteralTag {
            let lineRange = ns.lineRange(
                for: NSRange(location: span.range.location, length: 0))
            guard let match = ns.substring(with: lineRange)
                .firstMatch(of: #/^@([\w ]+):/#) else { continue }
            let tagLength = ns.substring(with: lineRange)
                .distance(from: match.0.startIndex, to: match.0.endIndex)
            let tagRange = NSRange(location: lineRange.location, length: tagLength)
            guard NSMaxRange(tagRange) <= ns.length else { continue }
            let style = SpeakerIdentity.style(for: span.speaker,
                                              colorOverrides: colorOverrides,
                                              symbolOverrides: symbolOverrides)
            let color = SpeakerIdentity.displayColor(colorIndex: style.colorIndex)
            lm.addTemporaryAttribute(.foregroundColor, value: color,
                                     forCharacterRange: tagRange)
        }
    }
}
```

- [ ] **Step 2: Drive it from EditorView**

In `EditorView` (ContentView.swift ~line 428), after the `TextEditor` modifiers, add a refresh that runs on appear and whenever the script or mode changes. Add near the top of `EditorView`:

```swift
    private func refreshChips() {
        SpeakerChipRenderer.apply(
            enabled: state.marginSpeakerMode,
            script: state.script,
            colorOverrides: state.speakerColors,
            symbolOverrides: state.speakerSymbols,
            in: EditorTextAccess.findTextView(in: NSApp.keyWindow))
    }
```

and attach to the `TextEditor` (inside `body`, after `.shadow(...)` on the outer view):

```swift
        .onAppear { refreshChips() }
        .onChange(of: state.script) { _, _ in refreshChips() }
        .onChange(of: state.marginSpeakerMode) { _, _ in refreshChips() }
```

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: with margin mode ON and a script containing `@Alex:` / `@Sam:` lines, each tag line shows in its speaker's color; toggling OFF clears it; editing text keeps colors correct.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/SpeakerChipRenderer.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: tint @Speaker: tags with per-speaker color in margin mode"
```

---

## Task 8: Gutter overlay (primary technical risk — spike first)

A thin AppKit view aligned to the editor's text, drawing one clickable icon per paragraph. macOS `TextEditor` exposes no layout API, so icons are positioned from the layout manager's bounding rect for each paragraph's first glyph, in the scroll view's coordinate space, and refreshed on scroll/resize/edit.

> **De-risk note:** Begin with Step 1 as a spike. If stable per-line alignment cannot be achieved within a reasonable effort, fall back to **making the chip itself the click target** (Task 9 reads the clicked character index from the text view instead of from gutter icons) and ship without the gutter. The pure-logic core and Tasks 7/9/10 do not depend on the gutter existing.

**Files:**
- Create: `Sources/KokoroStudio/Views/SpeakerGutterView.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (`EditorView`)

- [ ] **Step 1 (spike): Prove glyph-rect alignment**

Create `Sources/KokoroStudio/Views/SpeakerGutterView.swift` with a view that, given the editor's `NSTextView`, computes the y-position of each paragraph's first line and logs it:

```swift
import AppKit

/// Per-paragraph speaker icons drawn in a strip to the left of the editor,
/// aligned to the text via the layout manager. Click opens the picker.
@MainActor
final class SpeakerGutterView: NSView {
    var onClickParagraph: ((Int) -> Void)?

    private weak var textView: NSTextView?
    private var iconRects: [(paragraphIndex: Int, rect: NSRect)] = []
    private var styles: [(color: NSColor, symbol: String)] = []

    func configure(textView: NSTextView) {
        self.textView = textView
    }

    /// Recompute icon positions from the current layout.
    func refresh(script: String,
                 colorOverrides: [String: Int],
                 symbolOverrides: [String: Int]) {
        guard let textView, let lm = textView.layoutManager,
              let container = textView.textContainer else { return }
        iconRects.removeAll()
        styles.removeAll()
        let ns = script as NSString
        let spans = ParagraphSpeakers.resolve(script: script)
        for (index, span) in spans.enumerated() {
            let glyphRange = lm.glyphRange(
                forCharacterRange: NSRange(location: span.range.location, length: 1),
                actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            // Convert from text view coords to this gutter's coords.
            let inGutter = convert(rect, from: textView)
            let iconRect = NSRect(x: 7, y: inGutter.minY + 1, width: 20, height: 20)
            iconRects.append((index, iconRect))
            let style = SpeakerIdentity.style(for: span.speaker,
                                              colorOverrides: colorOverrides,
                                              symbolOverrides: symbolOverrides)
            styles.append((SpeakerIdentity.displayColor(colorIndex: style.colorIndex),
                           SpeakerIdentity.displaySymbol(symbolIndex: style.symbolIndex)))
            _ = ns // keep ns referenced; used by callers/debug
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (offset, entry) in iconRects.enumerated() {
            let (color, symbolName) = styles[offset]
            let path = NSBezierPath(roundedRect: entry.rect, xRadius: 6, yRadius: 6)
            color.withAlphaComponent(0.9).setFill()
            path.fill()
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                let tinted = image.withSymbolConfiguration(cfg)
                NSColor.white.set()
                tinted?.draw(in: entry.rect.insetBy(dx: 4, dy: 4))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let hit = iconRects.first(where: { $0.rect.contains(point) }) {
            onClickParagraph?(hit.paragraphIndex)
        }
    }
}
```

Run a build and a quick manual check that icon y-positions track the right lines (temporarily add `Swift.print(iconRects)` if needed). Confirm before proceeding.

Run: `swift build`
Expected: builds.

- [ ] **Step 2: Host the gutter beside the editor and keep it in sync**

In `EditorView` (ContentView.swift), wrap the editor in an `HStack` with a fixed-width gutter host when margin mode is on. Add a small `NSViewRepresentable` host that creates the `SpeakerGutterView`, finds the editor text view via `EditorTextAccess.findTextView`, and calls `refresh(...)`. Trigger `refresh` on: `.onAppear`, `state.script` change, `state.marginSpeakerMode` change, and the `NSView.boundsDidChangeNotification` of the editor's scroll view (for scroll/resize). Reuse the `refreshChips()` pattern; add the gutter refresh alongside it.

Concretely, add to `EditorView.body`, replacing the bare `TextEditor(...)` wrapper with:

```swift
        HStack(spacing: 0) {
            if state.marginSpeakerMode {
                SpeakerGutterHost(paragraphTapped: handleParagraphTap)
                    .frame(width: 34)
            }
            editorCore   // the existing TextEditor + its modifiers, extracted into a computed `editorCore`
        }
```

Extract the current `TextEditor(...)` chain (lines ~432–459) into a `private var editorCore: some View`. Implement `SpeakerGutterHost` as an `NSViewRepresentable` wrapping `SpeakerGutterView`, wiring `onClickParagraph` to `paragraphTapped`. Implement `handleParagraphTap(_:)` as a stub for now:

```swift
    private func handleParagraphTap(_ paragraphIndex: Int) {
        pendingPickerParagraph = paragraphIndex   // @State Int? added to EditorView
    }
```

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: with margin mode ON, a colored icon appears beside each paragraph's first line; icons stay aligned while scrolling and when font size changes; clicking an icon logs / sets the pending paragraph (add a temporary `Swift.print`).

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/SpeakerGutterView.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: per-paragraph speaker icons in the editor gutter"
```

---

## Task 9: Speaker picker popover + applying the edit

Clicking a gutter icon opens a Liquid-Glass popover listing Narrator, known speakers, and "New speaker…". Selecting one applies a `SpeakerTagEditor` edit through the text view (preserving undo) and refreshes the gutter + chips.

**Files:**
- Create: `Sources/KokoroStudio/Views/SpeakerPickerPopover.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (`EditorView`)

- [ ] **Step 1: Create the popover view**

Create `Sources/KokoroStudio/Views/SpeakerPickerPopover.swift`:

```swift
import SwiftUI

/// Liquid-Glass speaker picker shown when a gutter icon is clicked.
struct SpeakerPickerPopover: View {
    let knownSpeakers: [String]
    let currentSpeaker: String
    let colorOverrides: [String: Int]
    let symbolOverrides: [String: Int]
    let onPick: (String) -> Void
    let onNew: () -> Void

    private var rows: [String] {
        var names = [SpeakerIdentity.narratorName]
        names.append(contentsOf: knownSpeakers.filter { $0 != SpeakerIdentity.narratorName })
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Assign speaker").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(rows, id: \.self) { name in
                Button { onPick(name) } label: {
                    HStack(spacing: 8) {
                        swatch(for: name)
                        Text(name)
                        Spacer()
                        if name == currentSpeaker {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
            }
            Divider().padding(.vertical, 4)
            Button { onNew() } label: {
                Label("New speaker…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(width: 220)
    }

    private func swatch(for name: String) -> some View {
        let style = SpeakerIdentity.style(for: name,
                                          colorOverrides: colorOverrides,
                                          symbolOverrides: symbolOverrides)
        return Image(systemName: SpeakerIdentity.displaySymbol(symbolIndex: style.symbolIndex))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color(nsColor: SpeakerIdentity.displayColor(colorIndex: style.colorIndex)))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
```

- [ ] **Step 2: Present it and apply the edit**

In `EditorView`, present the popover from the gutter using a `.popover` bound to `pendingPickerParagraph` (the `@State Int?` from Task 8). Add a helper that applies the edit through the text view so native undo is preserved:

```swift
    private func assignSpeaker(_ speaker: String, toParagraph index: Int) {
        guard let edit = SpeakerTagEditor.assign(
                script: state.script, paragraphIndex: index, to: speaker),
              let textView = EditorTextAccess.focusTextView(in: NSApp.keyWindow)
        else { return }
        if textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
        }
        state.script = textView.string   // keep the binding in sync
        refreshChips()
        // gutter refresh happens via the script onChange wired in Task 8
    }
```

Wire the popover's `onPick` to `assignSpeaker(_:toParagraph:)` then clear `pendingPickerParagraph`. Compute `knownSpeakers` from `Array(state.speakerVoices.keys)` plus any names found by `ParagraphSpeakers.resolve(script:)`. Set `currentSpeaker` from the resolved span at `index`.

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: clicking a gutter icon opens the popover; picking a different speaker inserts/edits the `@Name:` line; picking the inherited speaker cleans a redundant tag; ⌘Z undoes the change as a single step; gutter + chips update.

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/SpeakerPickerPopover.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: speaker picker popover applies smart tag edits with undo"
```

---

## Task 10: New-speaker sub-flow (name + voice + auto/override color)

"New speaker…" collects a name and a voice, writes them into `speakerVoices`, auto-assigns and persists a color/symbol (user-overridable), then assigns the new speaker to the paragraph.

**Files:**
- Modify: `Sources/KokoroStudio/Views/SpeakerPickerPopover.swift` (add a second pane)
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (persist + assign)

- [ ] **Step 1: Add the new-speaker pane**

Add a `@State private var creating = false` to `SpeakerPickerPopover` and a second view shown when `creating` is true: a `TextField` for the name, a voice `Picker` over `state`'s visible voices (pass the voice list in), and a horizontal palette swatch row (8 colors) defaulting to the auto slot but tappable to override. Replace the `onNew: () -> Void` callback with `onCreate: (_ name: String, _ voiceID: Int, _ colorIndex: Int, _ symbolIndex: Int) -> Void`.

Pass the voice options in from `EditorView` (reuse `state.visibleVoiceGroups`). Compute the default swatch via:

```swift
let auto = SpeakerIdentity.nextFreeStyle(
    usedColors: Array(colorOverrides.values),
    usedSymbols: Array(symbolOverrides.values))
```

- [ ] **Step 2: Persist and assign on create**

In `EditorView`, implement the `onCreate` handler:

```swift
    private func createSpeaker(name: String, voiceID: Int,
                              colorIndex: Int, symbolIndex: Int,
                              forParagraph index: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != SpeakerIdentity.narratorName else { return }
        var voices = state.speakerVoices; voices[trimmed] = voiceID
        state.speakerVoices = voices
        var colors = state.speakerColors; colors[trimmed] = colorIndex
        state.speakerColors = colors
        var symbols = state.speakerSymbols; symbols[trimmed] = symbolIndex
        state.speakerSymbols = symbols
        assignSpeaker(trimmed, toParagraph: index)
    }
```

Wire `onCreate` to this, then clear `pendingPickerParagraph`.

- [ ] **Step 3: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: "New speaker…" → name + voice + color picker; saving tags the paragraph with the new `@Name:`, the chip + gutter use the chosen color, and the speaker now appears in the picker list with its voice. Generating audio uses the assigned voice for that speaker (confirm by ear or by checking the segment plan).

- [ ] **Step 4: Commit**

```bash
git add Sources/KokoroStudio/Views/SpeakerPickerPopover.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: create speakers with voice and color from the picker"
```

---

## Task 11: Chip "A" — rounded pill via custom NSLayoutManager (enhancement)

The visual target from the design: a rounded, tinted background behind each `@Name:` range instead of just colored text. Optional polish; Task 7's tint remains the fallback if this proves fragile.

**Files:**
- Create: `Sources/KokoroStudio/Views/SpeakerChipLayoutManager.swift`
- Modify: `Sources/KokoroStudio/Views/ContentView.swift` (install the custom layout manager on the editor text view) and/or `SpeakerChipRenderer.swift`

- [ ] **Step 1: Subclass NSLayoutManager to draw rounded tag backgrounds**

Create `Sources/KokoroStudio/Views/SpeakerChipLayoutManager.swift`:

```swift
import AppKit

/// Draws a rounded, tinted background behind ranges carrying a custom
/// `.speakerChipColor` temporary attribute — the pill look for @Name: tags.
final class SpeakerChipLayoutManager: NSLayoutManager {
    static let chipColorAttr = NSAttributedString.Key("speakerChipColor")

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainer(forGlyphAt: glyphsToShow.location,
                                            effectiveRange: nil) else { return }
        enumerateTemporaryAttribute(
            Self.chipColorAttr, in: characterRange(forGlyphRange: glyphsToShow,
                                                   actualGlyphRange: nil)) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let gr = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: gr, in: container)
            rect.origin.x += origin.x; rect.origin.y += origin.y
            rect = rect.insetBy(dx: -3, dy: 0)
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            color.withAlphaComponent(0.28).setFill()
            path.fill()
        }
    }
}
```

> `enumerateTemporaryAttribute` is not a stock API name — implement the enumeration by walking `temporaryAttribute(_:atCharacterIndex:effectiveRange:)` across the range, or store chip ranges on the layout manager directly. Keep it simple: have `SpeakerChipRenderer` set the `.speakerChipColor` temporary attribute on tag ranges and store the list of `(range, color)` on the layout manager for `drawBackground` to iterate.

- [ ] **Step 2: Install the custom layout manager on the editor text view**

`TextEditor`'s text view uses a default layout manager. Replace it once, after locating the text view: `textView.textContainer?.replaceLayoutManager(SpeakerChipLayoutManager())`. Do this in the gutter/chip host setup. Guard so it runs once.

- [ ] **Step 3: Switch the renderer to set chip color + draw pills**

Update `SpeakerChipRenderer.apply` to also set `SpeakerChipLayoutManager.chipColorAttr` on the tag ranges (keep the foreground tint for contrast). With the custom layout manager installed, tag lines now show a rounded tinted pill.

- [ ] **Step 4: Build and verify manually**

Run: `swift build && ./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify: `@Name:` tags render inside a rounded tinted pill in the speaker's color; toggling mode off clears pills; follow-along highlighting during playback still works and does not visually fight the pills. **If alignment or redraw is unstable, revert this task — Task 7's tint is the shipped baseline.**

- [ ] **Step 5: Commit**

```bash
git add Sources/KokoroStudio/Views/SpeakerChipLayoutManager.swift Sources/KokoroStudio/Views/SpeakerChipRenderer.swift Sources/KokoroStudio/Views/ContentView.swift
git commit -m "feat: rounded speaker-chip pills via custom layout manager"
```

---

## Final verification

- [ ] **Run the full test suite**

Run: `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test`
Expected: all tests pass, including the three new logic suites.

- [ ] **End-to-end manual pass in the assembled app**

Run: `./scripts/build-app.sh && open "build/Kokoro Studio.app"`
Verify the whole flow: toggle margin mode → gutter icons appear → click → assign existing speaker → create new speaker with voice → redundant tags auto-clean → undo works → generate audio honors per-speaker voices → toggle off returns to the plain editor.

---

## Notes for the implementer

- **Source of truth is the text.** Every assignment must end as an `@Speaker:` edit; never store paragraph→speaker anywhere else.
- **Coexistence with follow-along highlighting:** both use layout-manager temporary attributes. Chips touch `@Name:` tag ranges; follow-along touches sentence ranges. If you adopt the custom layout manager (Task 11), confirm `FollowAlongHighlighter` still finds its layout manager (it calls `textView.layoutManager`) — replacing the layout manager must happen before or independently of its `prepare(...)`.
- **Risk ordering:** Tasks 1–5 are pure and cheap — do them first. Task 8 (gutter alignment) is the main risk; its spike step gates the UI. If the gutter can't be made stable, ship chips + click-the-chip and skip Task 8's overlay.
- **YAGNI:** no drag-reassign, no per-paragraph voice, no multi-select, no gutter in export/caption/waveform views.
