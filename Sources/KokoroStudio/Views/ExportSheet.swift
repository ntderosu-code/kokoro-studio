import SwiftUI

/// Export options: fixed header, options body, fixed footer with the action.
struct ExportSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private var moduleCount: Int {
        ModuleSplitter.split(state.script).count
    }

    private var folderName: String {
        state.outputFolderPath.isEmpty
            ? "Ask when exporting"
            : URL(fileURLWithPath: state.outputFolderPath).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Export Audio")
                    .font(.headline)
                Text(AudioExporter.defaultFilename(for: state.script) + "."
                     + state.exportFormat.fileExtension)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            Form {
                Picker("Format", selection: Binding(
                    get: { state.exportFormat },
                    set: { state.exportFormat = $0 })) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Captions", selection: Binding(
                    get: { state.captionFormat },
                    set: { state.captionFormat = $0 })) {
                    ForEach(CaptionFormat.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .help("Writes a synced caption file next to the audio. Takes effect on the next Generate if cue boundaries changed.")

                Toggle("Normalize loudness", isOn: $state.normalizeLoudness)
                    .help("Applied during generation: silence trim, -1 dBFS leveling, micro fades")

                LabeledContent("Lead-in / out") {
                    HStack(spacing: 6) {
                        Stepper(value: $state.leadInMs, in: 0...3000, step: 250) {
                            Text("\(Double(state.leadInMs) / 1000, specifier: "%.2g")s")
                                .monospacedDigit()
                        }
                        Stepper(value: $state.leadOutMs, in: 0...3000, step: 250) {
                            Text("\(Double(state.leadOutMs) / 1000, specifier: "%.2g")s")
                                .monospacedDigit()
                        }
                    }
                }
                .help("Silence padding before/after the exported audio — for players that clip the first moments. Captions shift to match.")

                LabeledContent("Folder") {
                    HStack {
                        Text(folderName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { state.chooseOutputFolder() }
                            .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                if moduleCount > 1 {
                    Text("\(moduleCount) modules detected (## file: markers)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                if moduleCount > 1 {
                    Button("Export \(moduleCount) Modules") {
                        state.exportModules()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Export") {
                        state.export()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.lastAudio == nil)
                }
            }
            .padding(12)
        }
        .frame(width: 420, height: 360)
    }
}
