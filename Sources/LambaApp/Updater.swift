import AppKit
import Combine
import Foundation
import Sparkle

/// Sparkle's standard updater, started once for the process. Exposes what the UI needs:
/// "check now" and the automatic-check switch.
///
/// It only starts inside a bundle that has a feed and public key (release builds); a debug binary
/// run from `.build` never hits the network or shows an update prompt.
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    private var cancellable: AnyCancellable?

    /// Release builds carry `SUFeedURL` and `SUPublicEDKey` in Info.plist.
    static var isConfigured: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
            && !((Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? "").isEmpty
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 && Self.isConfigured }
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
