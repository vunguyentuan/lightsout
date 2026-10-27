import CoreGraphics
import Foundation

/// Turns the screens visually off while keeping them logically on.
///
/// Pixels are blacked out with an all-zero gamma table. Gamma is applied by the display pipeline *after* the
/// framebuffer, so screenshots and screen recordings taken by automation agents still see the real content.
/// Optionally the backlight is driven to zero as well, which is where most of the energy goes.
///
/// macOS restores gamma automatically when the process exits, even on a crash. Backlight values are persisted
/// while dark so the next launch can restore them if the app died without cleaning up.
final class DisplayDarkener {
    private(set) var isDark = false

    private var savedBuiltinBrightness: [CGDirectDisplayID: Float] = [:]
    /// Only touched on `ddcQueue`.
    private var savedDDCBrightness: [UInt64: Int] = [:]
    private let ddcQueue = DispatchQueue(label: "LightsOut.ddc")
    private var enforcer: Timer?
    private var dimsBacklight = false

    private static let pendingBuiltinKey = "pendingRestore.builtin"
    private static let pendingDDCKey = "pendingRestore.ddc"

    func darken(dimBacklight: Bool) {
        guard !isDark else { return }
        isDark = true
        dimsBacklight = dimBacklight
        enforce()
        if dimBacklight {
            dimDDCMonitors()
        }
        // Night Shift, ColorSync, display reconfiguration, or auto-brightness can undo our changes; keep reasserting.
        enforcer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.enforce()
        }
    }

    func restore() {
        guard isDark else { return }
        isDark = false
        enforcer?.invalidate()
        enforcer = nil
        CGDisplayRestoreColorSyncSettings()
        restoreBuiltinBrightness()
        ddcQueue.async { self.restoreDDCBrightness() }
    }

    /// Synchronous restore for app termination, so DDC writes finish before the process exits.
    func restoreForTermination() {
        guard isDark else { return }
        restore()
        ddcQueue.sync {}
    }

    /// Re-applies darkness after displays are added, removed, or reconfigured.
    func displaysChanged() {
        guard isDark else { return }
        enforce()
        if dimsBacklight {
            dimDDCMonitors()
        }
    }

    /// Restores backlight values left behind by a previous run that exited while dark.
    func recoverFromPreviousRun() {
        let defaults = UserDefaults.standard
        if let builtin = defaults.dictionary(forKey: Self.pendingBuiltinKey) as? [String: Float] {
            for (key, value) in builtin {
                if let id = CGDirectDisplayID(key) {
                    DisplayServices.setBrightness(id, value)
                }
            }
            defaults.removeObject(forKey: Self.pendingBuiltinKey)
        }
        if let ddc = defaults.dictionary(forKey: Self.pendingDDCKey) as? [String: Int], !ddc.isEmpty {
            ddcQueue.async {
                let fallback = ddc.values.max() ?? 100
                for monitor in DDC.externalMonitors() {
                    // Registry IDs change across reboots; fall back to the brightest saved value.
                    DDC.write(monitor, vcp: DDC.brightnessVCP, value: ddc[String(monitor.id)] ?? fallback)
                }
                defaults.removeObject(forKey: Self.pendingDDCKey)
            }
        }
    }

    // MARK: - Gamma and built-in brightness

    private func enforce() {
        for display in activeDisplays() {
            if !gammaIsBlack(display) {
                let zeros = [CGGammaValue](repeating: 0, count: 256)
                CGSetDisplayTransferByTable(display, 256, zeros, zeros, zeros)
            }
            guard dimsBacklight, DisplayServices.canChangeBrightness(display),
                  let current = DisplayServices.brightness(display) else { continue }
            if savedBuiltinBrightness[display] == nil {
                savedBuiltinBrightness[display] = current
                persistBuiltin()
            }
            if current > 0.001 {
                DisplayServices.setBrightness(display, 0)
            }
        }
    }

    private func restoreBuiltinBrightness() {
        for (display, value) in savedBuiltinBrightness {
            DisplayServices.setBrightness(display, value)
        }
        savedBuiltinBrightness.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.pendingBuiltinKey)
    }

    private func persistBuiltin() {
        let dict = Dictionary(uniqueKeysWithValues: savedBuiltinBrightness.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(dict, forKey: Self.pendingBuiltinKey)
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func gammaIsBlack(_ display: CGDirectDisplayID) -> Bool {
        let capacity = Int(CGDisplayGammaTableCapacity(display))
        guard capacity > 0 else { return false }
        var red = [CGGammaValue](repeating: 1, count: capacity)
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(display, UInt32(capacity), &red, &green, &blue, &count) == .success else {
            return false
        }
        let n = Int(count)
        return n > 0 && (red.prefix(n) + green.prefix(n) + blue.prefix(n)).allSatisfy { $0 < 0.001 }
    }

    // MARK: - DDC monitors

    private func dimDDCMonitors() {
        ddcQueue.async {
            for monitor in DDC.externalMonitors() {
                if self.savedDDCBrightness[monitor.id] == nil {
                    // Never zero a monitor whose current brightness we couldn't read; we'd have nothing to restore.
                    guard let reading = DDC.read(monitor, vcp: DDC.brightnessVCP) else { continue }
                    self.savedDDCBrightness[monitor.id] = reading.current
                    self.persistDDC()
                }
                DDC.write(monitor, vcp: DDC.brightnessVCP, value: 0)
            }
        }
    }

    private func restoreDDCBrightness() {
        guard !savedDDCBrightness.isEmpty else { return }
        for monitor in DDC.externalMonitors() {
            if let value = savedDDCBrightness[monitor.id] {
                DDC.write(monitor, vcp: DDC.brightnessVCP, value: value)
            }
        }
        savedDDCBrightness.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.pendingDDCKey)
    }

    private func persistDDC() {
        let dict = Dictionary(uniqueKeysWithValues: savedDDCBrightness.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(dict, forKey: Self.pendingDDCKey)
    }
}
