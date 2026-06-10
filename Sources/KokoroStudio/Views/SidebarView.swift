import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    private var outputFolderName: String {
        state.outputFolderPath.isEmpty
            ? "Ask on export"
            : URL(fileURLWithPath: state.outputFolderPath).lastPathComponent
    }

    var body: some View {
        Form {
            Section("Voice") {
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

            Section("Made with") {
                Link("Kokoro model — hexgrad (Apache-2.0)",
                     destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
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
    }
}
