import SwiftUI

/// Document tabs fused to the editor card's top edge. One tab per open
/// script; the script library lives in the toolbar Scripts menu.
struct ScriptTabBar: View {
    @EnvironmentObject private var state: AppState
    @State private var renameTarget: ScriptDocumentMeta?
    @State private var renameText = ""
    @State private var deleteTarget: ScriptDocumentMeta?

    private var openDocuments: [ScriptDocumentMeta] {
        state.openTabIDs.compactMap { id in
            state.documents.first(where: { $0.id == id })
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(openDocuments) { doc in
                        tab(for: doc)
                            .id(doc.id)
                    }
                    Button {
                        state.createDocument()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New script (⌘T)")
                }
                .padding(.horizontal, 6)
            }
            .onChange(of: state.currentDocumentID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id) } }
            }
        }
        .alert("Rename Script", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let doc = renameTarget {
                    state.renameDocument(doc.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete \"\(deleteTarget?.title ?? "")\"?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Delete Script", role: .destructive) {
                if let doc = deleteTarget { state.deleteDocument(doc.id) }
                deleteTarget = nil
            }
        } message: {
            Text("Removes it from the library. Exported audio is not affected.")
        }
    }

    private func tab(for doc: ScriptDocumentMeta) -> some View {
        let isActive = doc.id == state.currentDocumentID
        return HStack(spacing: 4) {
            Button {
                state.closeTab(doc.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive ? 1 : 0.4)
            .help("Close tab (⇧⌘W)")
            Text(doc.title)
                .lineLimit(1)
                .font(.callout)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 180)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                .fill(isActive
                      ? Color(nsColor: .textBackgroundColor)
                      : Color(nsColor: .windowBackgroundColor).opacity(0.6))
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectDocument(doc.id) }
        .contextMenu {
            Button("Rename…") {
                renameText = doc.title
                renameTarget = doc
            }
            Button("Duplicate") { state.duplicateDocument(doc.id) }
            Divider()
            Button("Close Tab") { state.closeTab(doc.id) }
            Button("Close Other Tabs") { state.closeOtherTabs(keeping: doc.id) }
            Divider()
            Button("Delete…", role: .destructive) { deleteTarget = doc }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Script tab: \(doc.title)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
