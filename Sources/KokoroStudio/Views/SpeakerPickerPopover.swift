import SwiftUI

/// Liquid-Glass speaker picker shown when a gutter icon is clicked.
/// Two panes: assign an existing speaker, or create a new one with a
/// name, voice, and palette color.
struct SpeakerPickerPopover: View {
    let knownSpeakers: [String]
    let currentSpeaker: String
    let colorOverrides: [String: Int]
    let symbolOverrides: [String: Int]
    let voiceGroups: [(label: String, voices: [Voice])]
    let defaultVoiceID: Int
    let onPick: (String) -> Void
    let onCreate: (_ name: String, _ voiceID: Int,
                   _ colorIndex: Int, _ symbolIndex: Int) -> Void

    @State private var creating = false
    @State private var newName = ""
    @State private var newVoiceID: Int = 0
    @State private var chosenColorIndex: Int?

    private var rows: [String] {
        var names = [SpeakerIdentity.narratorName]
        names.append(contentsOf: knownSpeakers.filter { $0 != SpeakerIdentity.narratorName })
        return names
    }

    /// Auto slot used when the user doesn't tap a swatch.
    private var autoStyle: SpeakerIdentity.Style {
        SpeakerIdentity.nextFreeStyle(
            usedColors: Array(colorOverrides.values),
            usedSymbols: Array(symbolOverrides.values))
    }

    var body: some View {
        if creating {
            createPane
        } else {
            assignPane
        }
    }

    private var assignPane: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Assign speaker").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(rows, id: \.self) { name in
                Button { onPick(name) } label: {
                    HStack(spacing: 8) {
                        swatch(for: name)
                        Text(name)
                        Spacer()
                        if name == currentSpeaker {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 5)
            }
            Divider().padding(.vertical, 4)
            Button {
                newVoiceID = defaultVoiceID
                creating = true
            } label: {
                Label("New speaker…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(width: 220)
    }

    private var createPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New speaker").font(.caption).foregroundStyle(.secondary)

            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)

            Picker("Voice", selection: $newVoiceID) {
                ForEach(voiceGroups, id: \.label) { group in
                    Section(group.label) {
                        ForEach(group.voices) { voice in
                            Text(voice.humanName).tag(voice.id)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<SpeakerIdentity.paletteCount, id: \.self) { index in
                    let selected = (chosenColorIndex ?? autoStyle.colorIndex) == index
                    Button {
                        chosenColorIndex = index
                    } label: {
                        Circle()
                            .fill(Color(nsColor: SpeakerIdentity.displayColor(colorIndex: index)))
                            .frame(width: 16, height: 16)
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(index + 1)")
                }
            }

            HStack {
                Button("Back") { creating = false }
                Spacer()
                Button("Add") {
                    let colorIndex = chosenColorIndex ?? autoStyle.colorIndex
                    // Symbol follows the color slot unless the color slot is
                    // taken; the auto symbol keeps icons distinct either way.
                    let symbolIndex = chosenColorIndex ?? autoStyle.symbolIndex
                    onCreate(newName, newVoiceID, colorIndex, symbolIndex)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                          || newName.trimmingCharacters(in: .whitespaces)
                              == SpeakerIdentity.narratorName)
            }
        }
        .padding(10)
        .frame(width: 240)
    }

    private func swatch(for name: String) -> some View {
        let style = SpeakerIdentity.style(for: name,
                                          colorOverrides: colorOverrides,
                                          symbolOverrides: symbolOverrides)
        return Image(systemName: SpeakerIdentity.displaySymbol(symbolIndex: style.symbolIndex))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color(nsColor: SpeakerIdentity.displayColor(colorIndex: style.colorIndex)))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
