import SwiftUI
import AppKit

/// App preferences (⌘,): General behavior and the voice list manager.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView(selection: Binding(get: { state.settingsTab },
                                   set: { state.settingsTab = $0 })) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            VoicesSettingsTab()
                .tabItem { Label("Voices", systemImage: "person.wave.2") }
                .tag("voices")
            DictionarySettingsTab()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
                .tag("dictionary")
        }
        .frame(width: 480, height: 420)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Editor") {
                LabeledContent("Font size") {
                    Text("\(Int(state.editorFontSize)) pt")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $state.editorFontSize, in: 11...20, step: 1) {
                    Text("Editor font size")
                }
                .labelsHidden()
            }

            Section("Playback") {
                Toggle("Play automatically after generating",
                       isOn: $state.autoplayAfterGenerate)
            }

            Section("Export") {
                Toggle("Reveal file in Finder after export",
                       isOn: $state.revealInFinderAfterExport)
                Toggle("Include timestamp in filenames",
                       isOn: $state.timestampInFilenames)
                    .help("Off: files are named from the script's first words only, and re-exports overwrite")
            }

            Section("Duration estimate") {
                LabeledContent("Calibrated rate") {
                    Text(String(format: "%.2f words/sec",
                                state.calibratedWordsPerSecond))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Button("Reset Calibration") {
                    state.calibratedWordsPerSecond
                        = DurationEstimator.defaultWordsPerSecond
                }
                .help("Returns the estimate to the default narration rate; it re-learns from your next generations")
            }
        }
        .formStyle(.grouped)
    }
}

struct DictionarySettingsTab: View {
    @EnvironmentObject private var state: AppState

    private var ruleCount: Int {
        PronunciationDictionary.parse(state.pronunciationRulesText).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
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
            .padding(12)

            Divider()

            TextEditor(text: $state.pronunciationRulesText)
                .font(.body.monospaced())
                .padding(8)

            Divider()

            HStack {
                Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s") active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import…") { importCSV() }
                    .help("Merge rules from a CSV file (term,replacement,mode)")
                Button("Export…") { exportCSV() }
                    .help("Save all rules to a CSV file you can share")
                    .disabled(ruleCount == 0)
            }
            .padding(8)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "pronunciation-dictionary.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DictionaryCSV.export(rulesText: state.pronunciationRulesText)
                .write(to: url, atomically: true, encoding: .utf8)
        } catch {
            state.errorMessage = "Could not export dictionary: \(error.localizedDescription)"
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let csv = try? String(contentsOf: url, encoding: .utf8) else { return }
        let imported = DictionaryCSV.parse(csv)
        guard !imported.isEmpty else {
            state.errorMessage = "No dictionary rules found in that file."
            return
        }
        // Dry run finds conflicts before asking how to resolve them.
        let dryRun = DictionaryCSV.merge(imported: imported,
                                         into: state.pronunciationRulesText,
                                         preferImported: false)
        if dryRun.conflictTerms.isEmpty {
            state.pronunciationRulesText = dryRun.mergedText
            return
        }
        let alert = NSAlert()
        alert.messageText = dryRun.conflictTerms.count == 1
            ? "1 term already has a different rule"
            : "\(dryRun.conflictTerms.count) terms already have different rules"
        alert.informativeText = "Conflicting: "
            + dryRun.conflictTerms.joined(separator: ", ")
        alert.addButton(withTitle: "Keep Existing")
        alert.addButton(withTitle: "Use Imported")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            state.pronunciationRulesText = dryRun.mergedText
        case .alertSecondButtonReturn:
            state.pronunciationRulesText = DictionaryCSV.merge(
                imported: imported, into: state.pronunciationRulesText,
                preferImported: true).mergedText
        default:
            break
        }
    }
}

struct VoicesSettingsTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("★ favorites pin to the top of the voice picker. Unchecked voices are hidden from it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)

            Divider()

            List {
                ForEach(VoiceCatalog.grouped, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.voices) { voice in
                            HStack(spacing: 10) {
                                VoicePreviewButton(voiceID: voice.id)

                                Button {
                                    var favorites = state.favoriteVoiceIDs
                                    if favorites.contains(voice.id) {
                                        favorites.remove(voice.id)
                                    } else {
                                        favorites.insert(voice.id)
                                    }
                                    state.favoriteVoiceIDs = favorites
                                } label: {
                                    Image(systemName: state.favoriteVoiceIDs.contains(voice.id)
                                          ? "star.fill" : "star")
                                        .foregroundStyle(
                                            state.favoriteVoiceIDs.contains(voice.id)
                                            ? .yellow : .secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(
                                    state.favoriteVoiceIDs.contains(voice.id)
                                    ? "Unfavorite \(voice.humanName)"
                                    : "Favorite \(voice.humanName)")

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(voice.humanName
                                         + (voice.languageLabel.map { " (\($0))" } ?? ""))
                                    if let tagline = voice.tagline {
                                        Text(tagline)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Toggle("Visible", isOn: Binding(
                                    get: { !state.hiddenVoiceIDs.contains(voice.id) },
                                    set: { visible in
                                        var hidden = state.hiddenVoiceIDs
                                        if visible {
                                            hidden.remove(voice.id)
                                        } else {
                                            hidden.insert(voice.id)
                                        }
                                        state.hiddenVoiceIDs = hidden
                                    }))
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                    .accessibilityLabel("Show \(voice.humanName) in picker")
                            }
                        }
                    }
                }
            }
        }
    }
}
