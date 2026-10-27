import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let awake = AwakeController()
    private let darkener = DisplayDarkener()
    private let input = InputWatcher()

    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var tickTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var darkenedAt = Date.distantPast

    /// Ignore physical input for a moment after going dark, so the hand that clicked the menu doesn't undo it.
    private static let wakeGracePeriod: TimeInterval = 1.5
    private static let autoDarkChoices = [0, 1, 2, 5, 10, 15, 30, 60]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        darkener.recoverFromPreviousRun()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        awake.setActive(settings.keepAwake)

        input.onPhysicalInput = { [weak self] in self?.physicalInputDetected() }
        input.start()

        hotKey = HotKey(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey | cmdKey) { [weak self] in
            self?.toggleDark()
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displaysChanged),
            name: NSWorkspace.screensDidWakeNotification, object: nil)

        installSignalHandlers()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        darkener.restoreForTermination()
        awake.setActive(false)
    }

    /// `lightsout://dark`, `lightsout://light`, `lightsout://toggle`, `lightsout://awake/on`, `lightsout://awake/off`
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "lightsout" {
            switch (url.host?.lowercased(), url.path.lowercased()) {
            case ("dark", _): setDark(true)
            case ("light", _): setDark(false)
            case ("toggle", _): toggleDark()
            case ("awake", "/on"): setKeepAwake(true)
            case ("awake", "/off"): setKeepAwake(false)
            default: NSLog("Lights Out: unrecognized URL \(url)")
            }
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.darkener.restoreForTermination()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: - Behavior

    private func setDark(_ dark: Bool) {
        if dark {
            darkener.darken(dimBacklight: settings.dimBacklight)
            darkenedAt = Date()
        } else {
            darkener.restore()
            input.noteActivity()
        }
        updateIcon()
    }

    private func toggleDark() {
        setDark(!darkener.isDark)
    }

    private func setKeepAwake(_ on: Bool) {
        settings.keepAwake = on
        awake.setActive(on)
        updateIcon()
    }

    private func physicalInputDetected() {
        guard darkener.isDark, settings.wakeOnPhysicalInput,
              Date().timeIntervalSince(darkenedAt) > Self.wakeGracePeriod else { return }
        setDark(false)
    }

    private func tick() {
        input.refreshIfTrustChanged()

        let minutes = settings.autoDarkMinutes
        if minutes > 0, !darkener.isDark, input.physicalIdleSeconds >= TimeInterval(minutes * 60) {
            setDark(true)
        }

        if settings.simulateActivity, awake.isActive {
            nudgeIdleTimer()
        }
    }

    /// Posts a zero-distance mouse move, which resets the HID idle timer that some managed-Mac screen-saver
    /// policies key off. Skipped while a button is held so we never interfere with an agent's drag.
    private func nudgeIdleTimer() {
        guard AXIsProcessTrusted() else { return }
        let anyInput = CGEventType(rawValue: ~0)!
        guard CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput) > 50 else { return }
        for button in [CGMouseButton.left, .right, .center] where CGEventSource.buttonState(.combinedSessionState, button: button) {
            return
        }
        guard let location = CGEvent(source: nil)?.location else { return }
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved,
                mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    @objc private func displaysChanged() {
        darkener.displaysChanged()
    }

    // MARK: - Menu

    private func updateIcon() {
        let (symbol, description): (String, String)
        if darkener.isDark {
            (symbol, description) = ("moon.fill", "Lights Out: screen off, Mac awake")
        } else if awake.isActive {
            (symbol, description) = ("cup.and.saucer.fill", "Lights Out: keeping Mac awake")
        } else {
            (symbol, description) = ("moon.zzz", "Lights Out: inactive")
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = description
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state = (awake.isActive ? "Awake & unlocked" : "Normal sleep rules")
            + " · " + (darkener.isDark ? "screen off" : "screen on")
        menu.addItem(disabledItem(state))
        menu.addItem(disabledItem("No physical input for \(formatDuration(input.physicalIdleSeconds))"))
        menu.addItem(.separator())

        menu.addItem(item("Keep Mac Awake & Unlocked", #selector(menuToggleAwake), checked: awake.isActive))
        let darkItem = item(darkener.isDark ? "Turn Screen Back On" : "Lights Out Now", #selector(menuToggleDark))
        darkItem.keyEquivalent = "l"
        darkItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(darkItem)

        let autoItem = NSMenuItem(title: "Auto Lights Out", action: nil, keyEquivalent: "")
        let autoMenu = NSMenu()
        for minutes in Self.autoDarkChoices {
            let title = minutes == 0 ? "Never" : "After \(minutes) min without physical input"
            let choice = item(title, #selector(menuSetAutoDark(_:)), checked: settings.autoDarkMinutes == minutes)
            choice.tag = minutes
            autoMenu.addItem(choice)
        }
        autoItem.submenu = autoMenu
        menu.addItem(autoItem)
        menu.addItem(.separator())

        menu.addItem(item("Wake Screen on Physical Mouse/Keyboard", #selector(menuToggleWakeOnInput), checked: settings.wakeOnPhysicalInput))
        menu.addItem(item("Turn Off Backlight Too", #selector(menuToggleBacklight), checked: settings.dimBacklight))
        menu.addItem(item("Simulate Activity (Managed Macs)", #selector(menuToggleSimulate), checked: settings.simulateActivity))
        if !input.canSeeKeyboard {
            menu.addItem(item("Allow Keyboard Detection…", #selector(menuRequestAccessibility)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Launch at Login", #selector(menuToggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("How It Works…", #selector(menuShowHelp)))
        let quit = NSMenuItem(title: "Quit Lights Out", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    @objc private func menuToggleAwake() {
        setKeepAwake(!awake.isActive)
    }

    @objc private func menuToggleDark() {
        toggleDark()
    }

    @objc private func menuSetAutoDark(_ sender: NSMenuItem) {
        settings.autoDarkMinutes = sender.tag
        input.noteActivity()
    }

    @objc private func menuToggleWakeOnInput() {
        settings.wakeOnPhysicalInput.toggle()
    }

    @objc private func menuToggleBacklight() {
        settings.dimBacklight.toggle()
    }

    @objc private func menuToggleSimulate() {
        settings.simulateActivity.toggle()
        if settings.simulateActivity && !AXIsProcessTrusted() {
            menuRequestAccessibility()
        }
    }

    @objc private func menuRequestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc private func menuToggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change Launch at Login", error.localizedDescription)
        }
    }

    @objc private func menuShowHelp() {
        showAlert("How Lights Out works", """
        Keep Mac Awake & Unlocked holds a "prevent display sleep" power assertion. Because the display never idles \
        to sleep, macOS never starts the screen saver or the display-sleep lock, so UI automation keeps running.

        Lights Out turns the light off without telling macOS the display is off: every pixel is blacked out with \
        the gamma table and the backlight goes to zero (built-in/Apple displays, plus DDC monitors). Screenshots \
        and screen recordings still see the real desktop.

        Moving the real mouse or pressing a key brings the screen back; input synthesized by agents does not. \
        Toggle anytime with ⌃⌥⌘L, or from scripts: open -g lightsout://dark (or light, toggle, awake/on, awake/off).

        Note: the session is unlocked while dark. Anyone at the keyboard can use it.
        """)
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
