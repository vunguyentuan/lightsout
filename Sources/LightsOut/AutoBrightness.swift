import Foundation

/// Drives display brightness from an external ambient light sensor.
///
/// The sensor is any executable that streams one reading per line to stdout, either `<lux>` or
/// `<unix_epoch> <lux>` (the last number on the line is used). It's run as a long-lived child process and
/// restarted if it exits.
///
/// Lux maps to brightness on a log curve, smoothed so a hand passing over the sensor doesn't flicker the screen.
/// Moving a slider while auto brightness is on records an offset for that display, so the curve follows the
/// user's preference from then on.
final class AutoBrightness {
    enum Status: Equatable {
        case off
        case waiting
        case reading(lux: Double)
    }

    /// Called on the main thread with every smoothed reading; return false to skip applying it (e.g. while dark).
    var shouldApply: () -> Bool = { true }
    /// Called on the main thread after levels were changed.
    var onApplied: (() -> Void)?
    /// Called on the main thread when `status` changes.
    var onStatusChange: (() -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onStatusChange?() } }
    }

    private let brightness: BrightnessController
    private let settings = Settings.shared
    private var process: Process?
    private var buffer = Data()
    private var smoothedLogLux: Double?
    /// Readings since the sensor (re)started or went stale. The first one after the phone's screen wakes can be
    /// far off, so nothing is applied until a few have been averaged.
    private var freshReadings = 0
    private static let warmUpReadings = 3
    private var lastReadingAt = Date.distantPast
    private var staleTimer: Timer?
    private var restartWork: DispatchWorkItem?
    private var restartDelay: TimeInterval = 2

    /// Below `darkLux` the curve sits at its floor, above `brightLux` at full brightness.
    private static let darkLux = 1.0
    private static let brightLux = 2000.0
    private static let floor = 0.1
    /// Weight of each new reading in the exponential moving average (readings arrive about once a second).
    private static let smoothing = 0.3
    /// Levels move only when the target is at least this far from the current level, so the screen doesn't creep.
    private static let threshold = 0.03
    private static let staleAfter: TimeInterval = 10

    init(brightness: BrightnessController) {
        self.brightness = brightness
    }

    /// The sensor command, if one is configured and executable.
    var command: String? {
        guard let path = settings.luxCommand.map({ NSString(string: $0).expandingTildeInPath }),
              FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return path
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, command != nil {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        restartWork?.cancel()
        restartWork = nil
        staleTimer?.invalidate()
        staleTimer = nil
        if let process {
            self.process = nil
            process.terminationHandler = nil
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }
        smoothedLogLux = nil
        freshReadings = 0
        status = .off
    }

    /// Records the user's manual level for a display as an offset from the curve at the current light level.
    func userSetLevel(_ level: Double, forDisplayNamed name: String) {
        guard process != nil, freshReadings >= Self.warmUpReadings, let smoothedLogLux else { return }
        var offsets = settings.autoBrightnessOffsets
        offsets[name] = level - Self.curve(logLux: smoothedLogLux)
        settings.autoBrightnessOffsets = offsets
    }

    // MARK: - Mapping

    static func curve(logLux: Double) -> Double {
        let low = log10(darkLux), high = log10(brightLux)
        let t = min(max((logLux - low) / (high - low), 0), 1)
        return floor + (1 - floor) * t
    }

    static func level(logLux: Double, offset: Double) -> Double {
        min(max(curve(logLux: logLux) + offset, 0), 1)
    }

    /// Parses `<lux>` or `<unix_epoch> <lux>`.
    static func lux(fromLine line: String) -> Double? {
        guard let value = line.split(whereSeparator: \.isWhitespace).last.flatMap({ Double($0) }),
              value.isFinite, value >= 0 else { return nil }
        return value
    }

    // MARK: - Process

    private func start() {
        guard process == nil, let command else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                // End of file: stop the handler, or it fires continuously until the process is reaped.
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.received(data, from: process) }
        }
        process.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async { self?.processExited(exited) }
        }
        do {
            try process.run()
        } catch {
            NSLog("Lights Out: couldn't start light sensor command \(command): \(error.localizedDescription)")
            scheduleRestart()
            return
        }
        self.process = process
        status = .waiting
        staleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkStale() }
    }

    private func processExited(_ exited: Process) {
        guard exited === process else { return }
        process = nil
        staleTimer?.invalidate()
        staleTimer = nil
        status = .waiting
        NSLog("Lights Out: light sensor command exited with status \(exited.terminationStatus)")
        scheduleRestart()
    }

    private func scheduleRestart() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.settings.autoBrightness else { return }
            self.restartWork = nil
            self.start()
        }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay, execute: work)
        restartDelay = min(restartDelay * 2, 60)
    }

    private func received(_ data: Data, from source: Process) {
        guard source === process, !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let lux = Self.lux(fromLine: line) {
                handle(lux: lux)
            }
        }
    }

    private func checkStale() {
        if Date().timeIntervalSince(lastReadingAt) > Self.staleAfter {
            // Keep the current brightness; jumping to a default would be worse than holding still.
            status = .waiting
            smoothedLogLux = nil
            freshReadings = 0
        }
    }

    // MARK: - Applying

    private func handle(lux: Double) {
        restartDelay = 2
        lastReadingAt = Date()
        status = .reading(lux: lux)

        // Smooth in log space, which is how perceived brightness scales. 0 lux would be -infinity.
        let logLux = log10(max(lux, 0.1))
        // During warm-up only the latest reading counts, so an early outlier doesn't linger in the average.
        let warmedUp = freshReadings >= Self.warmUpReadings
        let smoothed = warmedUp ? smoothedLogLux.map { $0 + Self.smoothing * (logLux - $0) } ?? logLux : logLux
        smoothedLogLux = smoothed
        freshReadings += 1

        guard freshReadings >= Self.warmUpReadings, shouldApply() else { return }
        var offsets = settings.autoBrightnessOffsets
        // A display seen for the first time keeps its current level, so turning auto brightness on never makes the
        // screen jump; from then on it follows changes in the light.
        let unseen = brightness.displays.filter { offsets[$0.name] == nil }
        if !unseen.isEmpty {
            for display in unseen {
                offsets[display.name] = display.level - Self.curve(logLux: smoothed)
            }
            settings.autoBrightnessOffsets = offsets
        }
        var changed = false
        for display in brightness.displays {
            let target = Self.level(logLux: smoothed, offset: offsets[display.name] ?? 0)
            // Always land exactly on the ends, so a small offset can still reach 0% or 100%.
            let reachesEnd = (target == 0 || target == 1) && target != display.level
            if abs(target - display.level) >= Self.threshold || reachesEnd {
                brightness.setLevel(target, for: display.id)
                changed = true
            }
        }
        if changed {
            onApplied?()
        }
    }
}
