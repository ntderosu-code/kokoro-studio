import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingDictionaryEditor = false

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
                                    Text(voice.name).tag(voice.id)
                                }
                            }
                        }
                    }
                    .labelsHidden()
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

            Section("Made with") {
                Link("Kokoro model — hexgrad (Apache-2.0)",
                     destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
                Link("Pocket TTS — Kyutai (CC-BY-4.0)",
                     destination: URL(string: "https://github.com/kyutai-labs/pocket-tts")!)
                Link("sherpa-onnx — k2-fsa (Apache-2.0)",
                     destination: URL(string: "https://github.com/k2-fsa/sherpa-onnx")!)
                Link("ONNX Runtime — Microsoft (MIT)",
                     destination: URL(string: "https://github.com/microsoft/onnxruntime")!)
                Link("eSpeak NG data (GPL-3.0)",
                     destination: URL(string: "https://github.com/espeak-ng/espeak-ng")!)
            }
            .font(.caption)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingDictionaryEditor) {
            DictionaryEditorView(rulesText: $state.pronunciationRulesText)
        }
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
                Text("One rule per line: word = how it should sound. " +
                     "Applied to whole words, ignoring case, before synthesis. " +
                     "Lines starting with # are comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Example:  kokoro = koh koh roh")
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
