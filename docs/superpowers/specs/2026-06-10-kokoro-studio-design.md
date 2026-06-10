# Kokoro Studio — Design Spec

Date: 2026-06-10
Status: Approved by user

## Purpose

A simple, self-contained macOS app for generating speech from text using the
Kokoro TTS model, fully offline. One window: script editor on the left,
settings sidebar on the right, player bar at the bottom.

## Decisions (user-confirmed)

- **Stack:** Native SwiftUI app (macOS 14+) using **sherpa-onnx** to run the
  Kokoro ONNX model. No Python, no network at runtime.
- **Model files:** Bundled inside the .app (`Contents/Resources/model/`):
  Kokoro int8 ONNX (~90MB), `voices.bin`, `tokens.txt`, `espeak-ng-data`.
  App download ≈ 150MB, works offline from first launch.
- **Outputs:** In-app playback preview, WAV export, M4A/AAC export
  (AVFoundation encoder). No MP3 in v1.
- **Distribution:** zip/DMG, ad-hoc codesigned. Notarization deferred.

## Layout

```
┌──────────────────────────────────────────────┐
│ Toolbar: [Generate ⌘↩] [Stop]    progress    │
├────────────────────────────┬─────────────────┤
│   Script editor            │ SETTINGS        │
│   (plain TextEditor,       │ Voice  [picker] │
│    char/word count)        │ Speed  [slider] │
│                            │ Format WAV/M4A  │
│                            │ Output folder   │
├────────────────────────────┴─────────────────┤
│ Player bar: ▶ ⏸ ───●──────   [Export ⌘S]    │
└──────────────────────────────────────────────┘
```

- Sidebar is collapsible.
- Player bar appears after a successful generation.
- Keyboard shortcuts: ⌘↩ generate, Space play/pause (guarded when focus is in
  the editor), ⌘S export. Shortcuts shown in tooltips.

## Components

1. **TTSEngine** — wraps sherpa-onnx `OfflineTts`. Loads the model once at
   launch on a background task (UI shows loading state). API:
   `synthesize(text:voiceID:speed:) async throws -> [Float]` (sample rate from
   model). Cancelable; reports progress per generated chunk.
2. **AudioExporter** — writes WAV (AVAudioFile, lossless) or M4A
   (AAC via AVAudioFile settings). Default filename derived from the first
   words of the script + timestamp.
3. **SettingsStore** — `@AppStorage`-backed: voice ID, speed, export format,
   output folder (security-scoped bookmark).
4. **Views** — `ContentView` (split layout), `EditorView`, `SidebarView`,
   `PlayerBar`.

## Data flow

Type script → Generate → TTSEngine synthesizes off the main thread
(progress bar, Stop button cancels) → samples held in memory →
PlayerBar plays via AVAudioPlayer → Export writes file to the chosen folder
and reveals it in Finder.

## Error handling

- Model fails to load → blocking alert with underlying error text.
- Empty script → Generate disabled.
- Export failure (permissions, disk) → alert; re-prompt for output folder if
  the bookmark is stale.

## Build & distribution

- Xcode project. A fetch script downloads the sherpa-onnx xcframework and the
  Kokoro model archive at build time; large binaries are not committed.
- Ad-hoc codesign; README notes right-click → Open for unsigned apps.

## Out of scope (v1)

MP3 export, batch file processing, SSML, multiple models, App Store
distribution.
