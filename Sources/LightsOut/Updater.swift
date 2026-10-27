import AppKit
import Sparkle

/// Sparkle updates, fed from lightsout.madebyvu.com/appcast.xml (written by scripts/release.sh).
final class Updater {
    static let shared = Updater()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func check() {
        // A menu-bar app is usually in the background, which would bury Sparkle's window.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
