import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingDictionaryEditor = false
    @State private var showingCredits = false
    @State private var showingSpeakers = false

    private func pauseLabel(_ ms: Int) -> String {
        ms == 0 ? "Model default" : "\(ms) ms"
    }

    @ViewBuilder
    private func pauseSlider(_ label: String, value: Binding<Int>,
                             range: ClosedRange<Double>, help: String) -> some View {
        LabeledContent(label) {
            Text(pauseLabel(value.wrappedValue))
                .monospacedDigit().foregroundStyle(.secondary)
        }
        Slider(value: Binding(get: { Double(value.wrappedValue) },
                              set: { value.wrappedValue = Int($0) }),
               in: range, step: 25) {
            Text(label)
        }
        .help(help)
    }

    private func chooseVoiceSample() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a short, clean voice recording (5–15s) to clone"
        if panel.runModal() == .OK, let url = panel.url {
            state.pocketVoicePath = url.path
        }
    }

    private var pocketVoiceName: String {
        guard let url = state.pocketVoiceURL else { return "None" }
        return url.deletingPathExtension().lastPathComponent.capitalized
    }

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Engine", selection: Binding(
                    get: { state.engineKind },
                    set: { state.engineKind = $0 })) {
                    ForEach(TTSEngineKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if state.engineKind == .pocket {
                    Text("Pocket TTS clones the voice from a short audio sample.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Voice") {
                if state.engineKind == .kokoro {
                    Picker("Voice", selection: $state.voiceID) {
                        ForEach(VoiceCatalog.grouped, id: \.label) { group in
                            Section(group.label) {
                                ForEach(group.voices) { voice in
                                    Text(voice.displayName).tag(voice.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .help("★ = recommended starting points")
                    Button("Speakers…") {
                        showingSpeakers = true
                    }
                    .help("Map @Name: script tags to voices for dialogue")
                } else {
                    LabeledContent("Sample") {
                        Text(pocketVoiceName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(state.pocketVoiceURL?.path ?? "")
                    }
                    Button("Choose Voice Sample…") {
                        chooseVoiceSample()
                    }
                    Button("Use Built-in Voice (Bria)") {
                        state.pocketVoicePath = ""
                    }
                    .disabled(state.pocketVoicePath.isEmpty)
                    Text("5–15 seconds of clean speech works best.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Speed") {
                    Text(String(format: "%.2f×", state.speed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $state.speed, in: 0.5...2.0, step: 0.05) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text("0.5×").font(.caption2)
                } maximumValueLabel: {
                    Text("2×").font(.caption2)
                }
            }

            Section("Pauses") {
                pauseSlider("Paragraph", value: Binding(
                    get: { state.paragraphPauseMs },
                    set: { state.paragraphPauseMs = $0 }), range: 0...1500,
                    help: "Extra silence between lines/paragraphs")
                pauseSlider("Sentence", value: Binding(
                    get: { state.sentencePauseMs },
                    set: { state.sentencePauseMs = $0 }), range: 0...800,
                    help: "Extra silence after . ! ? — 0 keeps natural rhythm")
                pauseSlider("Clause", value: Binding(
                    get: { state.clausePauseMs },
                    set: { state.clausePauseMs = $0 }), range: 0...800,
                    help: "Extra silence after , ; : — 0 keeps natural rhythm")
                pauseSlider("Heading", value: Binding(
                    get: { state.headingPauseMs },
                    set: { state.headingPauseMs = $0 }), range: 0...2000,
                    help: "Pause after lines starting with # — gives learners a beat at section breaks")
                Text("Tip: type [pause:800] anywhere in the script for a deliberate beat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pronunciation") {
                Picker("Numbers", selection: Binding(
                    get: { state.numberPreset },
                    set: { state.numberPreset = $0 })) {
                    ForEach(NumberPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .help("Natural expands symbols for reading: $5.50, 25%, 1–2, v1.2, x², °C. Literal reads text as written.")

                Button("Edit Dictionary…") {
                    showingDictionaryEditor = true
                }
                let ruleCount = PronunciationDictionary.parse(state.pronunciationRulesText).count
                if ruleCount > 0 {
                    Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s") active")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    showingCredits = true
                } label: {
                    Label("Proudly built upon open source software",
                          systemImage: "heart")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("View credits")
            }
        }
        .formStyle(.grouped)
        // Let the inspector's translucent material show through instead of
        // the form's opaque background.
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showingDictionaryEditor) {
            DictionaryEditorView(rulesText: $state.pronunciationRulesText)
        }
        .sheet(isPresented: $showingCredits) {
            CreditsView()
        }
        .sheet(isPresented: $showingSpeakers) {
            SpeakersEditorView()
        }
    }
}

/// Maps @Name: speaker tags found in the script to Kokoro voices.
struct SpeakersEditorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var detectedSpeakers: [String] {
        ScriptSegmenter.speakerNames(in: state.script)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speakers").font(.headline)
                Text("Start a line with @Name: to give it a speaker. " +
                     "Lines without a tag use the main voice. Kokoro engine only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            if detectedSpeakers.isEmpty {
                VStack(spacing: 6) {
                    Text("No speaker tags found in the script.")
                        .foregroundStyle(.secondary)
                    Text("Example:\n@Maya: Welcome to the clinic.\n@Sam: Thanks — first day!")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    ForEach(detectedSpeakers, id: \.self) { name in
                        Picker(name, selection: Binding(
                            get: { state.speakerVoices[name] ?? state.voiceID },
                            set: { state.speakerVoices[name] = $0 })) {
                            ForEach(VoiceCatalog.all) { voice in
                                Text(voice.displayName).tag(voice.id)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 360)
    }
}

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let url: String
    }

    private let credits: [Credit] = [
        Credit(name: "Kokoro-82M", detail: "TTS model by hexgrad · Apache-2.0",
               url: "https://huggingface.co/hexgrad/Kokoro-82M"),
        Credit(name: "Pocket TTS", detail: "Voice-cloning model by Kyutai · CC-BY-4.0",
               url: "https://github.com/kyutai-labs/pocket-tts"),
        Credit(name: "sherpa-onnx", detail: "On-device inference runtime by k2-fsa · Apache-2.0",
               url: "https://github.com/k2-fsa/sherpa-onnx"),
        Credit(name: "ONNX Runtime", detail: "Inference engine by Microsoft · MIT",
               url: "https://github.com/microsoft/onnxruntime"),
        Credit(name: "eSpeak NG", detail: "Phonemization data · GPL-3.0",
               url: "https://github.com/espeak-ng/espeak-ng"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                Text("Built on open source")
                    .font(.headline)
                Text("Kokoro Studio is a thin GUI over excellent open source work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            List(credits) { credit in
                VStack(alignment: .leading, spacing: 2) {
                    Link(credit.name, destination: URL(string: credit.url)!)
                        .font(.body.weight(.medium))
                    Text(credit.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 400, height: 380)
    }
}

/// Fixed header, scrollable editor body, fixed footer.
struct DictionaryEditorView: View {
    @Binding var rulesText: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pronunciation Dictionary")
                    .font(.headline)
                Text("One rule per line. Applied to whole words, ignoring case, " +
                     "before synthesis. Lines starting with # are comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("""
                kokoro = koh koh roh      (respell)
                APA = @letters            (spell out: A-P-A)
                NASA = @word              (say as written)
                IEP = @letters-first      (spell out first use only)
                """)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            TextEditor(text: $rulesText)
                .font(.body.monospaced())
                .frame(minHeight: 220)
                .padding(8)

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 400)
    }
}
