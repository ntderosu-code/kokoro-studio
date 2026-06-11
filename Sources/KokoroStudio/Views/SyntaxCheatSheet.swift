import SwiftUI

/// Quick reference for the script syntax the segmenter and preprocessor
/// understand — these powers are invisible without it.
struct SyntaxCheatSheet: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let syntax: String
        let meaning: String
    }

    private let entries: [Entry] = [
        Entry(syntax: "[pause:800]", meaning: "Deliberate beat (ms) anywhere in text — [pause] alone is 600ms"),
        Entry(syntax: "# Section title", meaning: "Heading: spoken, then the Heading pause"),
        Entry(syntax: "@Maya: Hello!", meaning: "Speaker line — map names to voices in Speakers…"),
        Entry(syntax: "{Roush|rowsh}", meaning: "One-off pronunciation, right where it's written"),
        Entry(syntax: "kokoro = koh koh roh", meaning: "Dictionary: respell a word everywhere"),
        Entry(syntax: "APA = @letters", meaning: "Dictionary: spell out (A-P-A)"),
        Entry(syntax: "IEP = @letters-first", meaning: "Spell out first use, say normally after"),
        Entry(syntax: "NASA = @word", meaning: "Dictionary: say as written"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Script Syntax")
                .font(.headline)
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.syntax)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 4))
                        .frame(width: 170, alignment: .leading)
                    Text(entry.meaning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Numbers, URLs, $, %, ranges and dates are read naturally when Numbers is set to Natural.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 440)
    }
}
