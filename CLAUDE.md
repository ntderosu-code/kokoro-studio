# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Kokoro Studio — a fully offline macOS TTS app (SwiftUI, macOS 14+) over the Kokoro and Supertonic TTS models via sherpa-onnx. Pure SwiftPM executable; there is no Xcode project. Built for instructional-content narration: pause control, pronunciation dictionary, captions, module splitting.

## Commands

```bash
./scripts/fetch-deps.sh        # once: sherpa-onnx dylibs + models (~500MB) into vendor/
swift build                    # debug build

# Tests need the dylibs on the path:
DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test
DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter ScriptPatcherTests   # one class

./scripts/build-app.sh         # assemble build/Kokoro Studio.app (ad-hoc signed)
./scripts/build-app.sh --release   # Developer ID sign + notarize + staple (needs keychain creds)
```

- Engine tests (`KokoroEngineTests`, `SupertonicEngineTests`) load the real models — they run in seconds locally but fail without `vendor/`.
- The app's **Info.plist (including the version number and NSServices entries) lives inline in `scripts/build-app.sh`** — bump versions there.
- Features that need a bundle (macOS Services, UserNotifications) only work from the assembled `.app`, never the bare binary; code guards on `Bundle.main.bundleIdentifier`.

## Architecture

**`AppState` is the hub** (`@MainActor ObservableObject`, the largest file). All settings are `@AppStorage`; all orchestration (generation, export, batch queue, voice audition, patch re-render, script library, Services handlers) lives there. Views in `Views/` are thin and reach it via `@EnvironmentObject`.

**The text→audio pipeline order is a contract** (same order in `generate()`, `exportModules()`, batch, audition, and patch — keep them in sync):

1. `InlineOverrides` (`{word|sounds-like}`) → `PronunciationDictionary` → `NumberNormalizer`
2. `ScriptSegmenter.segment` — splits on pauses, `@Speaker:` tags, `#` headings, `[pause:N]`, `*emphasis*` (emphasis = breath + 0.92× speed, **not** louder)
3. `makeSynthesisPlan` picks the engine (`KokoroEngine` eager-loaded, `SupertonicEngine` lazy) and returns a per-segment synthesize closure
4. `AppState.runSegments` splices silence between segments and records per-segment sample counts
5. `AudioProcessing.finalize` (silence trim → −1 dBFS peak → micro fades); optional `LoudnessNormalizer` LUFS pass at export only

**The cue table is load-bearing.** `CaptionWriter.buildCues` derives sample-accurate sentence cues from step 4's sample counts. Four features consume it: caption export, follow-along highlighting, waveform heading markers, and patch re-render. Cue *text* is post-preprocessing, so `CueAlignment` fuzzy-matches it back to raw editor ranges (greedy word matching, ≥50% threshold, bails rather than mis-aligns). `GeneratedAudio.sourceScript` is the staleness guard — features compare it to the current script before trusting alignments.

**Patch re-render** (`ScriptPatcher`): line-diff old vs new script → map changed block to cue/sample boundaries → re-synthesize only that text (with `@Speaker:` context prepended) → splice samples and rebuild cues. Refuses (returns nil) on wholesale rewrites or unreliable alignment.

**Pure logic vs UI split**: domain logic lives in caseless `enum` namespaces (`ScriptSegmenter`, `DictionaryCSV`, `ScriptImporter`, `CueAlignment`, `WaveformBuilder`, `ScriptPatcher`, `LoudnessNormalizer`, …) and is fully testable without the models. Keep new logic in this shape — UI-free, model-free, TDD-able.

**Persistence**: settings in UserDefaults (`@AppStorage`); named profiles and the script library as JSON/plain-text files under `Application Support/Kokoro Studio/` (`ProfileStore`, `DocumentStore`). `DocumentStore.directoryOverride` exists so tests can point at a temp dir.

**Liquid Glass policy** (`Views/GlassStyle.swift`): glass on the floating bars only, gated `#available(macOS 26.0, *)` with material fallbacks. No glass buttons inside glass bars (HIG: no glass-on-glass). Editor card and bars share `GlassMetrics.cornerRadius`.

## Gotchas

- Swift regex literals ending in `*/` mis-lex as comment ends — always use `#/.../#` delimiters.
- SourceKit diagnostics in this repo are chronically stale and report missing types that exist; trust `swift build`.
- `##` at line start is reserved for `## file:` module splitting — that's why the document importer collapses all Markdown heading levels to a single `#`.
- SwiftUI's `TextEditor` exposes no selection API on macOS; selection and highlighting go through the responder chain via `EditorTextAccess` (find vs focus variants) and layout-manager temporary attributes.
