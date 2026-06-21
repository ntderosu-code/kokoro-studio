import SwiftUI

/// Document tabs as a row of capsules floating above the editor card —
/// the active tab gets the Liquid Glass pill (material fallback before
/// macOS 26) and morphs between positions when selection moves. One tab
/// per open script; the script library lives in the toolbar Scripts menu.
struct ScriptTabBar: View {
    @EnvironmentObject private var state: AppState
    @State private var renameTarget: ScriptDocumentMeta?
    @State private var renameText = ""
    @State private var deleteTarget: ScriptDocumentMeta?
    @State private var hoveredTabID: UUID?
    @State private var hoveringNewTabButton = false
    @Namespace private var tabGlassNamespace

    private var openDocuments: [ScriptDocumentMeta] {
        state.openTabIDs.compactMap { id in
            state.documents.first(where: { $0.id == id })
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                BarGlassContainer(spacing: 6) {
                    HStack(spacing: 4) {
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
                                    in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hoveringNewTabButton = $0 }
                        .animation(.easeOut(duration: 0.12), value: hoveringNewTabButton)
                        .help("New script (⌘T)")
                    }
                    .padding(.horizontal, 2)
                }
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
            .accessibilityLabel("Close \(doc.title)")
            // A real button so tabs are focusable and operable from the
            // keyboard, not just clickable.
            Button {
                state.selectDocument(doc.id)
            } label: {
                Text(doc.title)
                    .lineLimit(1)
                    .font(.callout)
                    // Weight marks the active tab so state isn't conveyed
                    // by the pill alone; primary text keeps AA contrast.
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Script tab: \(doc.title)")
            .accessibilityAddTraits(isActive ? [.isSelected] : [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: 200)
        .background {
            if isHovered && !isActive {
                Capsule().fill(.quaternary)
            }
        }
        .modifier(ActiveTabPill(isActive: isActive,
                                namespace: tabGlassNamespace))
        .contentShape(Capsule())
        .onTapGesture { state.selectDocument(doc.id) }
        .onHover { hovering in
            if hovering {
                hoveredTabID = doc.id
            } else if hoveredTabID == doc.id {
                hoveredTabID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: hoveredTabID)
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
    }

}

/// Liquid Glass capsule behind the active tab (macOS 26+), with a
/// material-and-stroke capsule fallback on earlier systems. A shared
/// glassEffectID makes the pill morph when selection moves between tabs.
private struct ActiveTabPill: ViewModifier {
    let isActive: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isActive {
            content
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.32)),
                             in: .capsule)
                .glassEffectID("active-script-tab", in: namespace)
        } else {
            content
                .background(Color.accentColor.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.4)))
        }
    }
}
