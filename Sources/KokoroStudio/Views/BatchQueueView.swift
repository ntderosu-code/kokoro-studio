import SwiftUI

/// Pick library scripts, render and export them unattended (#37).
struct BatchQueueView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()

    private var settingsSummary: String {
        var parts = [state.exportFormat.label,
                     state.loudnessPreset.label]
        if state.captionFormat != .off {
            parts.append("\(state.captionFormat.label) captions")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Batch Export").font(.headline)
                Text(state.batchRunning
                     ? "Rendering — you can close this window; the queue keeps going."
                     : "Each script renders with its own profile. Export settings: \(settingsSummary).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            if state.batchRunning || !state.batchItems.isEmpty {
                List(state.batchItems) { item in
                    HStack {
                        statusIcon(item.state)
                        Text(item.title).lineLimit(1)
                        Spacer()
                        statusDetail(item)
                    }
                }
            } else {
                List(state.documents, selection: $selection) { doc in
                    Text(doc.title).tag(doc.id)
                }
            }

            Divider()

            HStack {
                if state.batchRunning {
                    Button("Cancel Batch", role: .destructive) {
                        state.cancelBatch()
                    }
                } else if !state.batchItems.isEmpty {
                    Button("New Batch") {
                        state.batchItems = []
                        selection = []
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                if !state.batchRunning, state.batchItems.isEmpty {
                    Button("Start (\(selection.count))") {
                        state.startBatch(documentIDs: state.documents
                            .map(\.id).filter { selection.contains($0) })
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || state.phase != .ready)
                }
            }
            .padding(12)
        }
        .frame(width: 440, height: 420)
    }

    @ViewBuilder
    private func statusIcon(_ itemState: AppState.BatchItem.State) -> some View {
        switch itemState {
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .rendering:
            ProgressView().controlSize(.small)
        case .exported:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func statusDetail(_ item: AppState.BatchItem) -> some View {
        switch item.state {
        case .rendering(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        case .failed(let message):
            HStack(spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Retry") { state.retryBatchItem(item.id) }
                    .controlSize(.small)
                    .disabled(state.batchRunning)
            }
        default:
            EmptyView()
        }
    }
}
