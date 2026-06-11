# SwiftUI Performance Audit — Kokoro Studio v1.5

**Date:** 2026-06-11
**Scope:** Code-first review of `main` at v1.5 (no runtime profiling; no reported symptom — proactive sweep of invalidation paths, per-keystroke work, and main-thread costs).
**Status:** Findings only — no fixes applied yet.

## Summary

The app's heavy lifting (synthesis, waveform building, loudness measurement) is correctly off the render path: detached tasks, one-shot O(n) passes, disk-cached previews, stable `ForEach` identities. The performance debt is concentrated in **SwiftUI invalidation**: a 10 Hz playback timer invalidates the whole window, and several O(script-length) computed properties run inside `body`. The two multiply, and they peak during the app's core activity — listening to narration while reading along.

## Findings (ordered by impact)

### P1 — 10 Hz whole-window re-render during playback

`ContentView` holds `@StateObject private var player = PlayerController()` (`ContentView.swift:6`). `PlayerController.currentTime` is `@Published`, written by a 0.1 s timer while playing (`PlayerController.swift:46-54`). Because `@StateObject` subscribes to `objectWillChange`, **every tick re-evaluates the entire `ContentView` body** — toolbar, editor overlay stack, info row, and all of P2's computed work — ten times per second for the duration of playback.

**Fix:** remove `currentTime` from `PlayerController`'s `objectWillChange` path. Expose it as a `CurrentValueSubject` (or timer publisher) consumed via `.onReceive`; `PlayerBar` keeps a local `@State` copy for the scrubber/waveform, and the follow-along highlighter already consumes time via `.onReceive`, which does not invalidate `body`.
**Effort:** small refactor, ~3 files.

### P2 — O(script) work inside `body` on every invalidation

| Site | Work | Frequency |
|---|---|---|
| `ContentView.pronunciationSuspects` (`ContentView.swift:10-14`) | `PronunciationDictionary.parse` + `ScriptLinter.acronymSuspects` over the whole script | every body evaluation: every keystroke, every generation-progress tick, every P1 playback tick |
| `ContentView.scriptSummary` | word count + duration estimate | same |
| `SidebarView` rule-count caption | `PronunciationDictionary.parse(...).count` | every sidebar render |
| `SidebarView` Compare Voices button | `AuditionSupport.defaultText(from: state.script)` — called twice (label + disabled check) | every sidebar render |
| `ExportSheet.moduleCount` | `ModuleSplitter.split` | sheet-only; low frequency, acceptable as-is |

Sub-millisecond for a one-page script; milliseconds per keystroke on the main thread for the 50k-word course documents this app targets — and multiplied ×10/s by P1 during playback.

**Fix:** cache as `@State` updated from `.onChange(of: state.script)` with a short debounce (~300 ms). A linter flag that settles after typing pauses is better UX as well as cheaper.
**Effort:** small.

### P3 — Monolithic `AppState` invalidation fan-out

A single `ObservableObject` carries all app state; any `@Published`/`@AppStorage` write invalidates every observing view (ContentView, SidebarView, PlayerBar, sheets). High-frequency writers:

- `phase = .generating(progress)` — per synthesis progress callback
- `batchItems[i].state = .rendering(progress)` — per batch progress callback

Each write re-renders the sidebar `Form` (50-voice picker, script list) and the full editor pane.

**Fix (recommended now):** quantize progress writes — publish only when the displayed value changes, e.g. `if Int(new * 100) != Int(old * 100)`. **Fix (structural, only if still needed):** split playback/progress state into a child observable. With P1 + P2 fixed, the structural split is likely unnecessary at this app's scale.
**Effort:** trivial (quantize) / medium (split).

### P4 — Memory ceiling: full sample buffers retained and copied

`GeneratedAudio.samples` keeps the entire render in RAM: ~5.8 MB/min (mono Float32 @ 24 kHz); a 60-minute lesson ≈ 345 MB. Patch re-render's `splice` materializes a second full-size array transiently; export padding makes another copy. The samples genuinely back waveform, patch, and export, and this is desktop-acceptable — documented here so the ceiling is a known quantity, not a surprise.

**Fix if it ever bites:** memory-map from the preview WAV instead of retaining `[Float]`.
**Effort:** medium. Not recommended now.

### P5 — Minor

- `FollowAlongHighlighter.prepare` runs on every `script` change; it bails fast on stale audio but still calls `clearHighlight()` → full-range `removeTemporaryAttribute` per keystroke. Gate it on having something to clear. One line.
- Waveform `Canvas` redraws 240 bars per playback tick — trivial; fine.
- `runSegments` array growth, `WaveformBuilder.peaks`, `LoudnessNormalizer` — one-shot O(n), off or briefly on the main path; fine.

## Already healthy

- Synthesis on detached tasks with `MainActor.run` hops; UI never blocks on the engine
- Autosave debounced (1 s)
- Voice previews and audition renders cached to disk; instant replays
- Waveform downsampled once per generation, not per frame
- Stable `Identifiable` identities in every `ForEach` (UUIDs / voice IDs) — no identity churn
- Single leaf-level `GeometryReader` (WaveformView); no layout thrash patterns

## Recommended action

Fix **P1 + P2 + P3-quantize** together — one focused commit each, verified by the existing 137-test suite plus a typing-during-playback smoke test. Re-audit (or capture an Instruments SwiftUI trace while typing during playback) afterward if any jank remains; the trace would show the `ContentView.body` storm directly if P1's diagnosis needs runtime confirmation.
