import Foundation

/// Transitions for the open-tab list. Pure logic: AppState feeds in the
/// current state and the recency-ordered library, and applies the result.
enum ScriptTabs {
    struct State: Equatable {
        var openIDs: [UUID]
        var activeID: UUID?
    }

    /// Open (or re-activate) a script as a tab.
    static func open(_ id: UUID, in state: State) -> State {
        var openIDs = state.openIDs
        if !openIDs.contains(id) { openIDs.append(id) }
        return State(openIDs: openIDs, activeID: id)
    }

    /// Close a tab. The script stays in the library. Closing the active tab
    /// selects its right neighbor (else left); closing the last tab falls
    /// back to the most recent library script, or empty if none exist.
    static func close(_ id: UUID, in state: State, library: [UUID]) -> State {
        guard let index = state.openIDs.firstIndex(of: id) else { return state }
        var openIDs = state.openIDs
        openIDs.remove(at: index)

        if openIDs.isEmpty {
            guard let fallback = library.first(where: { $0 != id })
            else { return State(openIDs: [], activeID: nil) }
            return State(openIDs: [fallback], activeID: fallback)
        }
        guard state.activeID == id else {
            return State(openIDs: openIDs, activeID: state.activeID)
        }
        let neighbor = openIDs[min(index, openIDs.count - 1)]
        return State(openIDs: openIDs, activeID: neighbor)
    }

    static func closeOthers(keeping id: UUID, in state: State) -> State {
        guard state.openIDs.contains(id) else { return state }
        return State(openIDs: [id], activeID: id)
    }

    /// Launch-time cleanup: drop tabs whose documents vanished, seed from the
    /// library when empty, and force the active tab into the open set.
    static func reconcile(_ state: State, library: [UUID]) -> State {
        var openIDs = state.openIDs.filter(library.contains)
        if openIDs.isEmpty, let first = library.first { openIDs = [first] }
        let activeID = state.activeID.flatMap { openIDs.contains($0) ? $0 : nil }
            ?? openIDs.first
        return State(openIDs: openIDs, activeID: activeID)
    }
}
