import SwiftUI

struct QuickAddTarget: Identifiable {
    let word: String
    var id: String { word }
}

/// Small form for adding a selected word/phrase to the pronunciation
/// dictionary without opening the full editor.
struct QuickAddDictionaryView: View {
    let word: String
    @Binding var rulesText: String
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case respell, letters, word, lettersFirst
        var id: String { rawValue }
        var label: String {
            switch self {
            case .respell: return "Respell"
            case .letters: return "Spell out (A-P-A)"
            case .word: return "Say as written"
            case .lettersFirst: return "Spell out first time only"
            }
        }
    }

    @State private var editedWord: String
    @State private var mode: Mode = .respell
    @State private var respelling = ""

    init(word: String, rulesText: Binding<String>) {
        self.word = word
        self._rulesText = rulesText
        self._editedWord = State(initialValue: word)
    }

    private var ruleLine: String {
        switch mode {
        case .respell: return "\(editedWord) = \(respelling)"
        case .letters: return "\(editedWord) = @letters"
        case .word: return "\(editedWord) = @word"
        case .lettersFirst: return "\(editedWord) = @letters-first"
        }
    }

    private var canAdd: Bool {
        !editedWord.trimmingCharacters(in: .whitespaces).isEmpty
            && (mode != .respell
                || !respelling.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to Pronunciation Dictionary")
                .font(.headline)

            Form {
                TextField("Word or phrase", text: $editedWord)
                Picker("Read as", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if mode == .respell {
                    TextField("Sounds like", text: $respelling,
                              prompt: Text("e.g. koh koh roh"))
                }
            }

            Text(ruleLine)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    if !rulesText.isEmpty, !rulesText.hasSuffix("\n") {
                        rulesText += "\n"
                    }
                    rulesText += ruleLine + "\n"
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding()
        .frame(width: 380)
    }
}