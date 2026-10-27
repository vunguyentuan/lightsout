import AppKit

/// Detects input from a human, as opposed to events synthesized by automation agents.
///
/// Every event posted with `CGEvent.post` (automation agents, remote-control tools, Lights Out itself) carries
/// the poster's PID in `eventSourceUnixProcessID`; events from real hardware carry 0. That lets an agent drive
/// the mouse and keyboard in the dark without turning the screen back on.
final class InputWatcher {
    var onPhysicalInput: (() -> Void)?

    private(set) var lastPhysicalInput = Date()
    private var monitors: [Any] = []
    private var monitorsHaveKeyboard = false

    private static let mask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .scrollWheel, .keyDown, .flagsChanged,
    ]

    /// Global key events are only delivered to Accessibility-trusted apps.
    var canSeeKeyboard: Bool { AXIsProcessTrusted() }

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.mask, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
        monitorsHaveKeyboard = canSeeKeyboard
    }

    /// Reinstalls the monitors once Accessibility is granted so they start receiving key events.
    func refreshIfTrustChanged() {
        if canSeeKeyboard != monitorsHaveKeyboard {
            start()
        }
    }

    func noteActivity() {
        lastPhysicalInput = Date()
    }

    var physicalIdleSeconds: TimeInterval {
        let idle = Date().timeIntervalSince(lastPhysicalInput)
        guard !canSeeKeyboard else { return idle }
        // Without Accessibility we can't see physical key presses, so don't black out someone who is typing.
        return min(idle, CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown))
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handle(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent, cgEvent.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return }
        noteActivity()
        onPhysicalInput?()
    }
}
