import SwiftUI

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

            Text("\(ruleCount) rule\(ruleCount == 1 ? "" : "s") active")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
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
