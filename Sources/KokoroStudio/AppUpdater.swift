import Combine
import Foundation
import Sparkle
import SwiftUI

struct AppUpdateConfiguration: Equatable {
    let feedURL: URL?
    let publicEDKey: String

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        feedURL = Self.validFeedURL(from: infoDictionary["SUFeedURL"])
        publicEDKey = (infoDictionary["SUPublicEDKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var isConfigured: Bool {
        feedURL != nil && !publicEDKey.isEmpty
    }

    private static func validFeedURL(from value: Any?) -> URL? {
        guard let string = (value as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string),
              url.scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}

final class AppUpdater {
    private let updaterController: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let configuration = AppUpdateConfiguration(bundle: bundle)
        updaterController = configuration.isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true,
                                           updaterDelegate: nil,
                                           userDriverDelegate: nil)
            : nil
    }

    var updater: SPUUpdater? {
        updaterController?.updater
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = ObservedObject(
            wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
