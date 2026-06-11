import AppKit

/// Receives macOS Services invocations (#38). Methods are looked up by
/// name from the NSServices entries in Info.plist; the bare binary has
/// no Info.plist, so Services only function in the assembled .app.
final class ServiceProvider: NSObject {
    static let shared = ServiceProvider()
    @MainActor weak var state: AppState?

    @objc func speakText(_ pasteboard: NSPasteboard, userData: String,
                         error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text in the selection."
            return
        }
        Task { @MainActor in
            self.state?.handleSpeakService(text: text)
        }
    }

    @objc func newScriptFromText(_ pasteboard: NSPasteboard, userData: String,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "No text in the selection."
            return
        }
        Task { @MainActor in
            self.state?.handleNewScriptService(text: text)
        }
    }
}
