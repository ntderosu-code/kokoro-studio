import SwiftUI

/// Preview of an imported document after conversion to script syntax
/// (#33), with explicit Replace / Insert actions so an import can never
/// silently overwrite editor content.
struct ImportPreviewView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Preview").font(.headline)
                Text("Headings became # lines, bold became *emphasis*, and smart punctuation was cleaned up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Insert at Cursor") {
                    insertAtCaret()
                    dismiss()
                }
                Button("Replace Script") {
                    state.script = text
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 440)
    }

    private func insertAtCaret() {
        if let textView = EditorTextAccess.focusTextView(in: NSApp.keyWindow) {
            textView.insertText(text, replacementRange: textView.selectedRange())
        } else {
            state.script += (state.script.isEmpty ? "" : "\n") + text
        }
    }
}
