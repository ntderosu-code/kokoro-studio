# Kokoro Studio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Self-contained macOS app (SwiftUI) that turns typed text into speech with the Kokoro 1.0 model via sherpa-onnx, with in-app playback and WAV/M4A export.

**Architecture:** Swift Package executable (no Xcode project file). A `CSherpaOnnx` system-library target exposes the vendored sherpa-onnx C API; `KokoroEngine` wraps it. SwiftUI views talk to a `@MainActor` `AppState`. A shell script assembles the final `.app` bundle (binary + dylibs + model) and codesigns it.

**Tech Stack:** Swift 5.9+/SwiftUI (macOS 14+), sherpa-onnx v1.13.2 prebuilt `osx-universal2-shared` dylibs, kokoro-multi-lang-v1_0 model (53 voices, 24kHz), AVFoundation for playback/export, XCTest.

**Key facts (verified 2026-06-10):**
- sherpa-onnx release v1.13.2 asset: `sherpa-onnx-v1.13.2-osx-universal2-shared.tar.bz2` (contains `lib/libsherpa-onnx-c-api.dylib`, `lib/libonnxruntime*.dylib`, `include/sherpa-onnx/c-api/c-api.h`).
- Model: `https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2` → `model.onnx` (~310MB), `voices.bin`, `tokens.txt`, `lexicon-us-en.txt`, `lexicon-gb-en.txt`, `lexicon-zh.txt`, `espeak-ng-data/`, `dict/`, `date-zh.fst`, `number-zh.fst`, `phone-zh.fst`. Sample rate 24000. 53 speakers, IDs 0–52.
- Speaker IDs: af 0–10 (alloy, aoede, bella, heart, jessica, kore, nicole, nova, river, sarah, sky), am 11–19 (adam, echo, eric, fenrir, liam, michael, onyx, puck, santa), bf 20–23 (alice, emma, isabella, lily), bm 24–27 (daniel, fable, george, lewis), 28 ef_dora, 29 em_alex, 30 ff_siwis, 31 hf_alpha, 32 hf_beta, 33 hm_omega, 34 hm_psi, 35 if_sara, 36 im_nicola, 37–41 jf/jm, 42–44 pf/pm, 45–52 zf/zm.
  Verify the 37–52 names against `vendor/model/README` or the sherpa docs table during Task 3; English IDs 0–27 are confirmed.

---

### Task 1: Scaffolding + dependency fetch

**Files:**
- Create: `.gitignore`
- Create: `scripts/fetch-deps.sh`

- [ ] **Step 1: .gitignore**

```gitignore
.build/
build/
vendor/
.DS_Store
*.xcodeproj
```

- [ ] **Step 2: fetch script**

```bash
#!/bin/bash
# scripts/fetch-deps.sh — download sherpa-onnx libs + Kokoro model into vendor/ (gitignored)
set -euo pipefail
cd "$(dirname "$0")/.."

SHERPA_VERSION="1.13.2"
SHERPA_ARCHIVE="sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-shared.tar.bz2"
MODEL_ARCHIVE="kokoro-multi-lang-v1_0.tar.bz2"

mkdir -p vendor

if [ ! -d "vendor/sherpa-onnx/lib" ]; then
  echo "Fetching sherpa-onnx v${SHERPA_VERSION}..."
  curl -L -o "vendor/${SHERPA_ARCHIVE}" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v${SHERPA_VERSION}/${SHERPA_ARCHIVE}"
  tar xf "vendor/${SHERPA_ARCHIVE}" -C vendor
  mv "vendor/sherpa-onnx-v${SHERPA_VERSION}-osx-universal2-shared" vendor/sherpa-onnx
  rm "vendor/${SHERPA_ARCHIVE}"
fi

if [ ! -d "vendor/model" ]; then
  echo "Fetching Kokoro model (~360MB compressed, be patient)..."
  curl -L -o "vendor/${MODEL_ARCHIVE}" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/${MODEL_ARCHIVE}"
  tar xf "vendor/${MODEL_ARCHIVE}" -C vendor
  mv vendor/kokoro-multi-lang-v1_0 vendor/model
  rm "vendor/${MODEL_ARCHIVE}"
fi

echo "Done. vendor/sherpa-onnx and vendor/model ready."
```

- [ ] **Step 3: run it** — `chmod +x scripts/fetch-deps.sh && ./scripts/fetch-deps.sh`. Expected: both vendor dirs exist; `ls vendor/sherpa-onnx/lib` shows `libsherpa-onnx-c-api.dylib`; `ls vendor/model` shows `model.onnx voices.bin tokens.txt espeak-ng-data ...`. If the extracted archive's top-level dir name differs, adjust the `mv`.

- [ ] **Step 4: commit** — `git add .gitignore scripts && git commit -m "chore: scaffolding and dependency fetch script"`

### Task 2: Swift package + C module, smoke build

**Files:**
- Create: `Package.swift`
- Create: `Sources/CSherpaOnnx/module.modulemap`, `Sources/CSherpaOnnx/shim.h`
- Create: `Sources/KokoroStudio/KokoroStudioApp.swift` (placeholder)

- [ ] **Step 1: Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KokoroStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CSherpaOnnx", path: "Sources/CSherpaOnnx"),
        .executableTarget(
            name: "KokoroStudio",
            dependencies: ["CSherpaOnnx"],
            linkerSettings: [
                .unsafeFlags([
                    "-Lvendor/sherpa-onnx/lib",
                    "-lsherpa-onnx-c-api",
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                    "-Xlinker", "-rpath", "-Xlinker", "vendor/sherpa-onnx/lib",
                ])
            ]
        ),
        .testTarget(name: "KokoroStudioTests", dependencies: ["KokoroStudio"]),
    ]
)
```

- [ ] **Step 2: C module** — `Sources/CSherpaOnnx/module.modulemap`:

```
module CSherpaOnnx {
    header "shim.h"
    export *
}
```

`Sources/CSherpaOnnx/shim.h`:

```c
#include "../../vendor/sherpa-onnx/include/sherpa-onnx/c-api/c-api.h"
```

- [ ] **Step 3: placeholder app** — `Sources/KokoroStudio/KokoroStudioApp.swift`:

```swift
import SwiftUI
import CSherpaOnnx

@main
struct KokoroStudioApp: App {
    var body: some Scene {
        WindowGroup("Kokoro Studio") { Text("Kokoro Studio") }
    }
}
```

- [ ] **Step 4: smoke build** — `swift build`. Expected: success. If link fails on `libonnxruntime`, check `otool -L vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib` and add the onnxruntime dylib dir/flag as needed.
- [ ] **Step 5: grep the real C API names** — `grep -n "OfflineTtsKokoroModelConfig\|GenerateWithProgressCallbackWithArg\|SherpaOnnxCreateOfflineTts" vendor/sherpa-onnx/include/sherpa-onnx/c-api/c-api.h`. Confirm field names used in Task 4 (`model, voices, tokens, data_dir, dict_dir, lexicon, length_scale`); adjust Task 4 code if they differ.
- [ ] **Step 6: commit** — `git commit -m "feat: SPM package with sherpa-onnx C bindings, smoke build"`

### Task 3: VoiceCatalog (TDD)

**Files:**
- Create: `Sources/KokoroStudio/VoiceCatalog.swift`
- Test: `Tests/KokoroStudioTests/VoiceCatalogTests.swift`

- [ ] **Step 1: failing test**

```swift
import XCTest
@testable import KokoroStudio

final class VoiceCatalogTests: XCTestCase {
    func testCatalogHas53Voices() { XCTAssertEqual(VoiceCatalog.all.count, 53) }
    func testIDsAreUniqueAndSequential() {
        XCTAssertEqual(VoiceCatalog.all.map(\.id), Array(0...52))
    }
    func testKnownVoices() {
        XCTAssertEqual(VoiceCatalog.all[3].name, "af_heart")
        XCTAssertEqual(VoiceCatalog.all[26].name, "bm_george")
    }
    func testEnglishGroupFirst() {
        XCTAssertEqual(VoiceCatalog.grouped.first?.label, "English (US female)")
    }
}
```

- [ ] **Step 2: run, verify fails** — `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test 2>&1 | tail -5`. Expected: compile error (VoiceCatalog undefined).
- [ ] **Step 3: implement** — struct `Voice { let id: Int; let name: String }`, `VoiceCatalog.all` literal table of all 53 (IDs/names from the "Key facts" section; verify 37–52 against `vendor/model/README.md` or sherpa docs), `VoiceCatalog.grouped` returning `[(label: String, voices: [Voice])]` ordered: English US female, US male, GB female, GB male, then Other languages.
- [ ] **Step 4: run, verify passes.**
- [ ] **Step 5: commit** — `git commit -m "feat: voice catalog for kokoro-multi-lang-v1_0"`

### Task 4: KokoroEngine wrapper + integration test

**Files:**
- Create: `Sources/KokoroStudio/KokoroEngine.swift`
- Test: `Tests/KokoroStudioTests/KokoroEngineTests.swift`

- [ ] **Step 1: failing test** (integration; uses real model via env var, skips if absent)

```swift
import XCTest
@testable import KokoroStudio

final class KokoroEngineTests: XCTestCase {
    func modelDir() throws -> URL {
        let path = ProcessInfo.processInfo.environment["KOKORO_MODEL_DIR"] ?? "vendor/model"
        guard FileManager.default.fileExists(atPath: path + "/model.onnx") else {
            throw XCTSkip("model not present; run scripts/fetch-deps.sh")
        }
        return URL(fileURLWithPath: path)
    }

    func testSynthesizeProducesAudio() throws {
        let engine = try KokoroEngine(modelDirectory: try modelDir())
        XCTAssertEqual(engine.sampleRate, 24000)
        XCTAssertEqual(engine.numberOfSpeakers, 53)
        var progressValues: [Float] = []
        let samples = try engine.synthesize(text: "Hello from Kokoro Studio.",
                                            voiceID: 3, speed: 1.0,
                                            progress: { p in progressValues.append(p); return true })
        XCTAssertGreaterThan(samples.count, 10_000)
        XCTAssertFalse(progressValues.isEmpty)
    }

    func testCancelStopsEarly() throws {
        let engine = try KokoroEngine(modelDirectory: try modelDir())
        let longText = Array(repeating: "This is a sentence to synthesize.", count: 30).joined(separator: " ")
        let samples = try engine.synthesize(text: longText, voiceID: 3, speed: 1.0,
                                            progress: { _ in false }) // cancel immediately
        // cancelled generation returns whatever was produced before the stop
        XCTAssertLessThan(samples.count, 24000 * 60)
    }
}
```

- [ ] **Step 2: run, verify fails** (compile error).
- [ ] **Step 3: implement** `KokoroEngine.swift`:

```swift
import Foundation
import CSherpaOnnx

enum KokoroEngineError: Error, LocalizedError {
    case modelLoadFailed(String)
    var errorDescription: String? {
        switch self { case .modelLoadFailed(let detail): return "Could not load the Kokoro model: \(detail)" }
    }
}

/// Thin wrapper around the sherpa-onnx offline TTS C API.
/// Not thread-safe; call synthesize from one queue/task at a time.
final class KokoroEngine {
    private let tts: OpaquePointer
    let sampleRate: Int
    let numberOfSpeakers: Int

    init(modelDirectory: URL) throws {
        let dir = modelDirectory.path
        func p(_ name: String) -> UnsafePointer<CChar> {
            UnsafePointer(strdup(dir + "/" + name)!) // lives as long as the process; created once
        }
        var kokoro = SherpaOnnxOfflineTtsKokoroModelConfig()
        kokoro.model = p("model.onnx")
        kokoro.voices = p("voices.bin")
        kokoro.tokens = p("tokens.txt")
        kokoro.data_dir = p("espeak-ng-data")
        kokoro.dict_dir = p("dict")
        kokoro.lexicon = UnsafePointer(strdup("\(dir)/lexicon-us-en.txt,\(dir)/lexicon-zh.txt")!)
        kokoro.length_scale = 1.0

        var modelConfig = SherpaOnnxOfflineTtsModelConfig()
        modelConfig.kokoro = kokoro
        modelConfig.num_threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        modelConfig.provider = UnsafePointer(strdup("cpu")!)

        var config = SherpaOnnxOfflineTtsConfig()
        config.model = modelConfig
        config.rule_fsts = UnsafePointer(strdup("\(dir)/date-zh.fst,\(dir)/number-zh.fst,\(dir)/phone-zh.fst")!)
        config.max_num_sentences = 1 // chunk per sentence so progress callbacks are frequent

        guard let handle = SherpaOnnxCreateOfflineTts(&config) else {
            throw KokoroEngineError.modelLoadFailed("SherpaOnnxCreateOfflineTts returned NULL — check model files in \(dir)")
        }
        tts = OpaquePointer(handle)
        sampleRate = Int(SherpaOnnxOfflineTtsSampleRate(handle))
        numberOfSpeakers = Int(SherpaOnnxOfflineTtsNumSpeakers(handle))
    }

    deinit { SherpaOnnxDestroyOfflineTts(UnsafePointer(tts)) }

    /// progress receives 0...1; return false to cancel.
    func synthesize(text: String, voiceID: Int, speed: Float,
                    progress: @escaping (Float) -> Bool) throws -> [Float] {
        final class Box { let cb: (Float) -> Bool; init(_ cb: @escaping (Float) -> Bool) { self.cb = cb } }
        let box = Box(progress)
        let arg = Unmanaged.passUnretained(box).toOpaque()

        let cCallback: SherpaOnnxGeneratedAudioProgressCallbackWithArg = { _, _, prog, arg in
            let box = Unmanaged<Box>.fromOpaque(arg!).takeUnretainedValue()
            return box.cb(prog) ? 1 : 0
        }

        guard let audio = SherpaOnnxOfflineTtsGenerateWithProgressCallbackWithArg(
            UnsafePointer(tts), text, Int32(voiceID), speed, cCallback, arg) else {
            return []
        }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let n = Int(audio.pointee.n)
        guard n > 0, let samplesPtr = audio.pointee.samples else { return [] }
        return Array(UnsafeBufferPointer(start: samplesPtr, count: n))
    }
}
```

Note: exact C type/field names must match the grep from Task 2 Step 5 — fix here if sherpa renamed anything.

- [ ] **Step 4: run, verify passes** — `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test --filter KokoroEngineTests`. First run loads a 310MB model — allow ~30s.
- [ ] **Step 5: commit** — `git commit -m "feat: KokoroEngine wrapper with progress and cancel"`

### Task 5: AudioExporter (TDD)

**Files:**
- Create: `Sources/KokoroStudio/AudioExporter.swift`
- Test: `Tests/KokoroStudioTests/AudioExporterTests.swift`

- [ ] **Step 1: failing tests**

```swift
import XCTest
import AVFoundation
@testable import KokoroStudio

final class AudioExporterTests: XCTestCase {
    // one second of 440Hz sine at 24kHz
    var sine: [Float] { (0..<24000).map { sin(Float($0) * 2 * .pi * 440 / 24000) * 0.5 } }
    func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    func testWAVRoundTrip() throws {
        let url = tempURL("wav")
        try AudioExporter.write(samples: sine, sampleRate: 24000, to: url, format: .wav)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 24000)
        XCTAssertEqual(Int(file.length), 24000)
    }

    func testM4AWrites() throws {
        let url = tempURL("m4a")
        try AudioExporter.write(samples: sine, sampleRate: 24000, to: url, format: .m4a)
        let file = try AVAudioFile(forReading: url)
        // AAC may pad with priming frames; duration within 15%
        XCTAssertEqual(Double(file.length) / file.fileFormat.sampleRate, 1.0, accuracy: 0.15)
    }

    func testDefaultFilename() {
        let name = AudioExporter.defaultFilename(for: "Hello, world! This is a   test script that goes on.")
        XCTAssertTrue(name.hasPrefix("Hello-world-This-is"))
        XCTAssertFalse(name.contains(" "))
        XCTAssertFalse(name.contains("/"))
    }
}
```

- [ ] **Step 2: run, verify fails.**
- [ ] **Step 3: implement**

```swift
import Foundation
import AVFoundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case wav, m4a
    var id: String { rawValue }
    var label: String { self == .wav ? "WAV (lossless)" : "M4A (AAC)" }
}

enum AudioExporter {
    static func write(samples: [Float], sampleRate: Int, to url: URL, format: ExportFormat) throws {
        let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: Double(sampleRate),
                                             channels: 1, interleaved: false)!
        let settings: [String: Any]
        switch format {
        case .wav:
            settings = [AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false]
        case .m4a:
            settings = [AVFormatIDKey: kAudioFormatMPEG4AAC,
                        AVSampleRateKey: sampleRate,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderBitRateKey: 96_000]
        }
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }

    static func defaultFilename(for script: String) -> String {
        let words = script.split { !$0.isLetter && !$0.isNumber }.prefix(5)
        let stem = words.joined(separator: "-")
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        return stem.isEmpty ? "kokoro-\(timestamp)" : "\(stem)-\(timestamp)"
    }
}
```

- [ ] **Step 4: run, verify passes.**
- [ ] **Step 5: commit** — `git commit -m "feat: WAV/M4A audio exporter"`

### Task 6: AppState + UI

**Files:**
- Create: `Sources/KokoroStudio/AppState.swift`
- Create: `Sources/KokoroStudio/Views/ContentView.swift`, `SidebarView.swift`, `PlayerBar.swift`
- Modify: `Sources/KokoroStudio/KokoroStudioApp.swift`

- [ ] **Step 1: AppState** — `@MainActor final class AppState: ObservableObject`:
  - `@Published var script = ""`, `@Published var phase: Phase` (`enum Phase { case loadingModel, ready, generating(Float), failed(String) }`), `@Published var lastAudio: GeneratedAudio?` (`struct GeneratedAudio { let samples: [Float]; let sampleRate: Int; let tempWAV: URL }`).
  - `@AppStorage("voiceID") var voiceID = 3` (af_heart), `@AppStorage("speed") var speed = 1.0`, `@AppStorage("format") var format = ExportFormat.wav.rawValue`, `@AppStorage("outputFolderBookmark") var bookmarkData: Data?` via separate helper.
  - `loadModel()` — Task.detached: find model dir (`Bundle.main.resourceURL/model` if exists, else `vendor/model` for dev runs), build `KokoroEngine`, set phase.
  - `generate()` — guard non-empty script; phase = .generating(0); detached task calls `engine.synthesize` with progress closure that hops to main to update phase and reads a `cancelRequested` flag (return !cancelled); on success writes temp WAV (AudioExporter) and sets `lastAudio`, phase .ready.
  - `cancel()` sets the flag.
  - `export(to folder: URL)` — writes chosen format with `defaultFilename`, then `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- [ ] **Step 2: ContentView** — `NavigationSplitView` reversed is for leading sidebars; instead use `HSplitView { editor; sidebar }` with sidebar collapsible via toolbar button. Toolbar: Generate button (`⌘↩`, disabled when script empty or not ready), Stop (visible while generating), `ProgressView(value:)` while generating. Editor: `TextEditor` monospaced-ish body font, word/char count footer. PlayerBar at bottom when `lastAudio != nil`: AVAudioPlayer wrapper (`PlayerController: NSObject, ObservableObject, AVAudioPlayerDelegate` with play/pause/seek + timer-driven currentTime), Slider scrubber, Export button (`⌘S`) → `NSOpenPanel` directory chooser (or saved folder).
- [ ] **Step 3: SidebarView** — Form: Voice `Picker` using `VoiceCatalog.grouped` (sections), Speed `Slider` 0.5–2.0 with value label, Format `Picker` (segmented), Output folder row (current folder name + Choose… button). All labeled.
- [ ] **Step 4: App entry** — `@StateObject var state = AppState()`, `.task { state.loadModel() }`, alert binding on `.failed`. Window default size 900×600, `windowResizability(.contentSize)` not needed.
- [ ] **Step 5: build + manual run** — `swift build && DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib .build/debug/KokoroStudio`. Verify: window appears, model loads, generate produces playable audio, export writes file.
- [ ] **Step 6: commit** — `git commit -m "feat: full UI — editor, sidebar, player, export"`

### Task 7: App bundling script

**Files:**
- Create: `scripts/build-app.sh`

- [ ] **Step 1: script**

```bash
#!/bin/bash
# scripts/build-app.sh — build release binary and assemble self-contained Kokoro Studio.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Kokoro Studio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/model"

cp .build/release/KokoroStudio "$APP/Contents/MacOS/Kokoro Studio"
cp vendor/sherpa-onnx/lib/*.dylib "$APP/Contents/Frameworks/"
cp -R vendor/model/ "$APP/Contents/Resources/model/"

# point the binary at bundled dylibs
for dylib in "$APP/Contents/Frameworks/"*.dylib; do
  name=$(basename "$dylib")
  install_name_tool -change "@rpath/$name" "@rpath/$name" "$APP/Contents/MacOS/Kokoro Studio" 2>/dev/null || true
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Kokoro Studio</string>
  <key>CFBundleDisplayName</key><string>Kokoro Studio</string>
  <key>CFBundleIdentifier</key><string>com.byron.KokoroStudio</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>Kokoro Studio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local Kokoro TTS</string>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
du -sh "$APP"
```

- [ ] **Step 2: dylib audit** — after building, `otool -L "$APP/Contents/MacOS/Kokoro Studio"` must show sherpa libs at `@rpath/...` and rpath `@executable_path/../Frameworks` (set by Package.swift linker flags). If the binary references absolute `vendor/...` paths, add explicit `install_name_tool -change` lines for each.
- [ ] **Step 3: run the bundle** — `open "build/Kokoro Studio.app"`; full manual pass: load → generate → play → export both formats.
- [ ] **Step 4: commit** — `git commit -m "feat: self-contained .app bundling script"`

### Task 8: README + wrap-up

**Files:**
- Create: `README.md`

- [ ] **Step 1: README** — what it is, screenshot placeholder, build steps (`scripts/fetch-deps.sh`, `scripts/build-app.sh`), right-click→Open note for ad-hoc signed apps, voice list pointer, license note (model weights Apache-2.0 via sherpa-onnx).
- [ ] **Step 2: full test pass** — `DYLD_LIBRARY_PATH=vendor/sherpa-onnx/lib swift test`. All green.
- [ ] **Step 3: commit** — `git commit -m "docs: README with build and distribution notes"`

## Self-review notes

- Spec coverage: editor+toolbar (T6), sidebar (T6), playback (T6), WAV/M4A (T5), bundled model + self-contained app (T1, T7), error alerts (T4 error type, T6 alert), keyboard shortcuts (T6), Finder reveal (T6). Out-of-scope items untouched. ✔
- Names consistent: `KokoroEngine`, `AudioExporter.write(samples:sampleRate:to:format:)`, `ExportFormat`, `VoiceCatalog.all/.grouped`, `AppState.generate/cancel/export`. ✔
- Known risk: exact sherpa C field names — mitigated by Task 2 Step 5 grep before Task 4.
