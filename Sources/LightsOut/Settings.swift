import Foundation

/// User preferences, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.keepAwake: true,
            Key.autoDarkMinutes: 10,
            Key.wakeOnPhysicalInput: true,
            Key.dimBacklight: true,
            Key.simulateActivity: false,
        ])
    }

    private enum Key {
        static let keepAwake = "keepAwake"
        static let autoDarkMinutes = "autoDarkMinutes"
        static let wakeOnPhysicalInput = "wakeOnPhysicalInput"
        static let dimBacklight = "dimBacklight"
        static let simulateActivity = "simulateActivity"
    }

    /// Hold power assertions so the Mac never idles into display sleep, screen saver, or lock.
    var keepAwake: Bool {
        get { defaults.bool(forKey: Key.keepAwake) }
        set { defaults.set(newValue, forKey: Key.keepAwake) }
    }

    /// Black out the screen after this many minutes without physical input. 0 disables it.
    var autoDarkMinutes: Int {
        get { defaults.integer(forKey: Key.autoDarkMinutes) }
        set { defaults.set(newValue, forKey: Key.autoDarkMinutes) }
    }

    /// Bring the screen back when a human touches the mouse, trackpad, or keyboard.
    var wakeOnPhysicalInput: Bool {
        get { defaults.bool(forKey: Key.wakeOnPhysicalInput) }
        set { defaults.set(newValue, forKey: Key.wakeOnPhysicalInput) }
    }

    /// Also drop backlight brightness to zero (built-in/Apple displays and DDC monitors), not just the pixels.
    var dimBacklight: Bool {
        get { defaults.bool(forKey: Key.dimBacklight) }
        set { defaults.set(newValue, forKey: Key.dimBacklight) }
    }

    /// Periodically post a zero-distance mouse move so HID idle timers (e.g. MDM-enforced screen savers) never fire.
    var simulateActivity: Bool {
        get { defaults.bool(forKey: Key.simulateActivity) }
        set { defaults.set(newValue, forKey: Key.simulateActivity) }
    }
}
