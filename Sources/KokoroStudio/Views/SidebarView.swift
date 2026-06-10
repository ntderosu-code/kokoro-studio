import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingDictionaryEditor = false
    @State private var showingCredits = false

    private func pauseLabel(_ ms: Int) -> String {
        ms == 0 ? "Model default" : "\(ms) ms"
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

    private var outputFolderName: String {
        state.outputFolderPath.isEmpty
            ? "Ask on export"
            : URL(fileURLWithPath: state.outputFolderPath).lastPathComponent
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

            Section("Output") {
                Picker("Format", selection: Binding(
                    get: { state.exportFormat },
                    set: { state.exportFormat = $0 })) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Captions", selection: Binding(
                    get: { state.captionFormat },
                    set: { state.captionFormat = $0 })) {
                    ForEach(CaptionFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .help("Export a synced caption file next to the audio — cues follow sentences and pauses")

                Toggle("Normalize loudness", isOn: $state.normalizeLoudness)
                    .help("Trim silence, level volume to -1 dBFS, and add micro fades — keeps every clip at the same loudness")

                LabeledContent("Folder") {
                    Text(outputFolderName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(state.outputFolderPath.isEmpty
                              ? "You'll be asked where to save on first export"
                              : state.outputFolderPath)
                }
                Button("Choose Folder…") {
                    state.chooseOutputFolder()
                }
            }

            Section("Pauses") {
                LabeledContent("Paragraph") {
                    Text(pauseLabel(state.paragraphPauseMs))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(state.paragraphPauseMs) },
                                      set: { state.paragraphPauseMs = Int($0) }),
                       in: 0...1500, step: 50) {
                    Text("Paragraph pause")
                }
                .help("Extra silence between paragraphs (blank or new lines)")

                LabeledContent("Punctuation") {
                    Text(pauseLabel(state.punctuationPauseMs))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { Double(state.punctuationPauseMs) },
                                      set: { state.punctuationPauseMs = Int($0) }),
                       in: 0...800, step: 25) {
                    Text("Punctuation pause")
                }
                .help("Extra silence after . ! ? ; : , — 0 keeps the voice's natural rhythm")
            }

            Section("Pronunciation") {
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
        .sheet(isPresented: $showingDictionaryEditor) {
            DictionaryEditorView(rulesText: $state.pronunciationRulesText)
        }
        .sheet(isPresented: $showingCredits) {
            CreditsView()
        }
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
