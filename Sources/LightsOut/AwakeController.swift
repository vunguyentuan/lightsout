import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac and its login session awake.
///
/// The key is `PreventUserIdleDisplaySleep`: as long as the display is never idle-slept, macOS never starts
/// the screen saver or the display-sleep lock, so the session stays unlocked for UI automation. The light is
/// turned off separately by `DisplayDarkener`, which leaves the display logically "on".
final class AwakeController {
    private static let reason = "Lights Out keeps the session awake and unlocked for automation" as CFString

    private var displayAssertion: IOPMAssertionID = 0
    private var systemAssertion: IOPMAssertionID = 0
    private var activityAssertion: IOPMAssertionID = 0
    private var heartbeat: Timer?

    private(set) var isActive = false

    func setActive(_ active: Bool) {
        active ? start() : stop()
    }

    private func start() {
        guard !isActive else { return }
        let level = IOPMAssertionLevel(kIOPMAssertionLevelOn)
        IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, level, Self.reason, &displayAssertion)
        IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString, level, Self.reason, &systemAssertion)
        declareUserActivity()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.declareUserActivity()
        }
        isActive = true
    }

    private func stop() {
        guard isActive else { return }
        heartbeat?.invalidate()
        heartbeat = nil
        for id in [displayAssertion, systemAssertion, activityAssertion] where id != 0 {
            IOPMAssertionRelease(id)
        }
        displayAssertion = 0
        systemAssertion = 0
        activityAssertion = 0
        isActive = false
    }

    /// Tells powerd the user is present, which resets its user-idle state (dimming, idle lock policies).
    private func declareUserActivity() {
        IOPMAssertionDeclareUserActivity(Self.reason, kIOPMUserActiveLocal, &activityAssertion)
    }
}
