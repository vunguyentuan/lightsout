import AppKit
import CoreGraphics
import Foundation

/// Manual brightness for every display whose backlight the app can drive: built-in and Apple displays through
/// DisplayServices, external monitors through DDC/CI.
///
/// Levels are cached so the menu can show them instantly; `refresh()` re-reads them in the background because a
/// DDC read takes around 100 ms per monitor.
final class BrightnessController {
    struct Display {
        enum Backend {
            case displayServices(CGDirectDisplayID)
            case ddc(monitorID: UInt64, max: Int)
        }

        let id: String
        let name: String
        let backend: Backend
        /// 0...1
        var level: Double
    }

    private(set) var displays: [Display] = []
    /// Called on the main thread after a refresh or a level change.
    var onChange: (() -> Void)?

    /// Bumped on every manual change, so a read that started before the change can't snap the level back.
    private var edits: [String: Int] = [:]
    private var refreshing = false
    private var refreshAgain = false
    private let pendingWrites = PendingWrites()
    /// Only touched on `DDC.queue`.
    private var monitors: [UInt64: DDC.Monitor] = [:]

    func refresh() {
        guard !refreshing else {
            refreshAgain = true
            return
        }
        refreshing = true
        let editsAtStart = edits
        DDC.queue.async {
            let monitors = DDC.externalMonitors()
            self.monitors = Dictionary(monitors.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let readings = monitors.map { ($0, DDC.read($0, vcp: DDC.brightnessVCP)) }
            DispatchQueue.main.async {
                self.finishRefresh(readings, editsAtStart: editsAtStart)
            }
        }
    }

    func setLevel(_ level: Double, for id: String) {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return }
        let level = min(max(level, 0), 1)
        displays[index].level = level
        edits[id, default: 0] += 1
        switch displays[index].backend {
        case .displayServices(let display):
            DisplayServices.setBrightness(display, Float(level))
        case .ddc(let monitorID, let max):
            // Slider drags fire far faster than DDC can keep up with, so only the latest value per monitor is sent.
            if pendingWrites.set(Int((level * Double(max)).rounded()), for: monitorID) {
                DDC.queue.async { self.flushWrites() }
            }
        }
    }

    func setAllLevels(_ level: Double) {
        if displays.isEmpty {
            // Launched by the URL itself: wait for the first refresh to discover the displays.
            refreshThen { [weak self] in
                guard let self, !self.displays.isEmpty else { return }
                self.setAllLevels(level)
            }
            return
        }
        for display in displays {
            setLevel(level, for: display.id)
        }
        onChange?()
    }

    // MARK: - Private

    private var afterRefresh: [() -> Void] = []

    private func refreshThen(_ work: @escaping () -> Void) {
        afterRefresh.append(work)
        refresh()
    }

    private func finishRefresh(_ readings: [(DDC.Monitor, (current: Int, max: Int)?)], editsAtStart: [String: Int]) {
        var found: [Display] = []
        let screens = screenNames()
        let active = activeDisplays()
        let builtins = active.filter { DisplayServices.canChangeBrightness($0) }
        for display in builtins {
            guard let level = DisplayServices.brightness(display) else { continue }
            let name = screens[display] ?? (CGDisplayIsBuiltin(display) != 0 ? "Built-in Display" : "Display")
            found.append(Display(id: "ds.\(display)", name: name, backend: .displayServices(display), level: Double(level)))
        }

        var unnamed = 0
        for (monitor, reading) in readings {
            let match = monitor.identity.flatMap { identity in active.first(where: identity.matches) }
            // Apple displays answer DDC too; DisplayServices already covers them.
            if let match, builtins.contains(match) { continue }
            let id = "ddc.\(monitor.id)"
            let previous = displays.first(where: { $0.id == id })
            let display: Display
            if let reading, reading.max > 0 {
                let name = match.flatMap { screens[$0] } ?? monitor.identity?.name ?? {
                    unnamed += 1
                    return "External Display \(unnamed)"
                }()
                display = Display(id: id, name: name, backend: .ddc(monitorID: monitor.id, max: reading.max),
                                  level: Double(reading.current) / Double(reading.max))
            } else if let previous {
                // DDC reads fail now and then; keep the monitor rather than making its slider vanish.
                display = previous
            } else {
                continue
            }
            found.append(display)
        }

        for index in found.indices where edits[found[index].id] != editsAtStart[found[index].id] {
            if let current = displays.first(where: { $0.id == found[index].id }) {
                found[index].level = current.level
            }
        }
        displays = found
        refreshing = false
        onChange?()

        let work = afterRefresh
        afterRefresh.removeAll()
        work.forEach { $0() }
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    private func flushWrites() {
        for (monitorID, value) in pendingWrites.take() {
            if let monitor = monitors[monitorID] {
                DDC.write(monitor, vcp: DDC.brightnessVCP, value: value)
            }
        }
    }

    private func activeDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }
}

/// Latest unsent DDC value per monitor, shared between the main thread and `DDC.queue`.
private final class PendingWrites {
    private let lock = NSLock()
    private var values: [UInt64: Int] = [:]

    /// Returns true when nothing was pending, meaning the caller needs to schedule a flush.
    func set(_ value: Int, for monitorID: UInt64) -> Bool {
        lock.withLock {
            let wasEmpty = values.isEmpty
            values[monitorID] = value
            return wasEmpty
        }
    }

    func take() -> [UInt64: Int] {
        lock.withLock {
            defer { values.removeAll() }
            return values
        }
    }
}
