import SwiftUI

/// Liquid-Glass speaker picker shown when a gutter icon is clicked.
struct SpeakerPickerPopover: View {
    let knownSpeakers: [String]
    let currentSpeaker: String
    let colorOverrides: [String: Int]
    let symbolOverrides: [String: Int]
    let onPick: (String) -> Void
    let onNew: () -> Void

    private var rows: [String] {
        var names = [SpeakerIdentity.narratorName]
        names.append(contentsOf: knownSpeakers.filter { $0 != SpeakerIdentity.narratorName })
        return names
    }

    var body: some View {
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
            Button { onNew() } label: {
                Label("New speaker…", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8).padding(.bottom, 8)
        }
        .frame(width: 220)
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
