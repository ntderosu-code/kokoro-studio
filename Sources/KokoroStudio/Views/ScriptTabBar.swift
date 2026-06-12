import SwiftUI

/// Document tabs fused to the editor card's top edge. One tab per open
/// script; the script library lives in the toolbar Scripts menu.
struct ScriptTabBar: View {
    @EnvironmentObject private var state: AppState
    @State private var renameTarget: ScriptDocumentMeta?
    @State private var renameText = ""
    @State private var deleteTarget: ScriptDocumentMeta?
    @State private var hoveredTabID: UUID?
    @State private var hoveringNewTabButton = false

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
                            .background(
                                hoveringNewTabButton ? AnyShapeStyle(.quaternary)
                                                     : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveringNewTabButton = $0 }
                    .animation(.easeOut(duration: 0.12), value: hoveringNewTabButton)
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
        let isHovered = doc.id == hoveredTabID
        let shape = UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
        return HStack(spacing: 4) {
            Button {
                state.closeTab(doc.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 1 : 0.4)
            .help("Close tab (⇧⌘W)")
            // A real button so tabs are focusable and operable from the
            // keyboard, not just clickable.
            Button {
                state.selectDocument(doc.id)
            } label: {
                Text(doc.title)
                    .lineLimit(1)
                    .font(.callout)
                    // Primary on every tab: secondary text on the recessed
                    // gray fill falls below 4.5:1. Weight marks the active
                    // tab so state isn't conveyed by fill alone.
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 180)
        .background(shape.fill(tabFill(isActive: isActive, isHovered: isHovered)))
        .overlay {
            // Hairline keeps inactive tabs legible against the pane; the
            // active tab stays borderless so it fuses with the editor card.
            if !isActive {
                shape.strokeBorder(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectDocument(doc.id) }
        .onHover { hovering in
            if hovering {
                hoveredTabID = doc.id
            } else if hoveredTabID == doc.id {
                hoveredTabID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredTabID)
        .animation(.easeOut(duration: 0.15), value: state.currentDocumentID)
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

    /// Active fuses with the editor card; inactive sits recessed against
    /// the pane; hover lifts an inactive tab partway toward active.
    private func tabFill(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return Color(nsColor: .textBackgroundColor) }
        let recessed = NSColor.underPageBackgroundColor
        guard isHovered else { return Color(nsColor: recessed) }
        let lifted = recessed.blended(withFraction: 0.4, of: .textBackgroundColor)
        return Color(nsColor: lifted ?? recessed)
    }
}
