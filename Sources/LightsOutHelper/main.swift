import Foundation
import IOKit
import IOKit.ps
import IOKit.pwr_mgt
import LidAwakeShared
import os

/// Root helper that keeps a lid-closed Mac awake on AC power by holding `pmset disablesleep 1`.
///
/// It's on demand: launchd starts it at boot (to undo anything left over from a crash) and whenever Lights Out
/// connects. The setting is on only while a connected Lights Out asks for it and the Mac is on AC. It's
/// cleared on battery and as soon as the app disconnects, quits or crashes, and the helper exits when idle.

let log = Logger(subsystem: LidAwake.helperIdentifier, category: "helper")

enum Power {
    static func onAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMACPowerKey
    }

    static func sleepDisabled() -> Bool { rootDomainFlag("SleepDisabled") }

    /// The lid is closed and, with sleep allowed, that alone would put the Mac to sleep (no usable display).
    static func lidClosedWouldSleep() -> Bool {
        rootDomainFlag("AppleClamshellState") && rootDomainFlag("AppleClamshellCausesSleep")
    }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        do {
            try pmset.run()
            pmset.waitUntilExit()
        } catch {
            log.error("pmset failed to run: \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard pmset.terminationStatus == 0 else {
            log.error("pmset disablesleep exited with \(pmset.terminationStatus)")
            return false
        }
        return true
    }

    static func sleepNow() {
        let port = IOPMFindPowerManagement(kIOMainPortDefault)
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    private static func rootDomainFlag(_ key: String) -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(rootDomain, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        return (value as? Bool) ?? false
    }
}

final class Helper: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener(machServiceName: LidAwake.machServiceName)
    /// Survives helper crashes and reboots, so a setting we turned on is always turned back off.
    private let ownershipMarker = URL(fileURLWithPath: "/Library/Application Support/Lights Out/sleep-disabled-by-lights-out")
    private var sessions = Set<ObjectIdentifier>()
    private var wanting = Set<ObjectIdentifier>()
    private var state = LidAwakeState.off
    private var idleExit: DispatchWorkItem?
    private var powerSource: CFRunLoopSource?

    func run(team: String) {
        listener.setConnectionCodeSigningRequirement(
            LidAwake.codeRequirement(identifier: LidAwake.appIdentifier, team: team))
        listener.delegate = self
        listener.resume()
        watchPowerSource()
        evaluate()
        scheduleIdleExit()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let session = Session(helper: self)
        let id = ObjectIdentifier(session)
        connection.exportedInterface = NSXPCInterface(with: LidAwakeHelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.sessionEnded(id) }
        }
        DispatchQueue.main.async {
            self.sessions.insert(id)
            self.idleExit?.cancel()
        }
        connection.resume()
        return true
    }

    fileprivate func set(_ wanted: Bool, for id: ObjectIdentifier) -> LidAwakeState {
        guard sessions.contains(id) else { return .off }
        if wanted { wanting.insert(id) } else { wanting.remove(id) }
        evaluate()
        return state
    }

    private func sessionEnded(_ id: ObjectIdentifier) {
        sessions.remove(id)
        wanting.remove(id)
        evaluate()
        scheduleIdleExit()
    }

    private func evaluate() {
        let decision = SleepPolicy.decide(
            wanted: !wanting.isEmpty, onAC: Power.onAC(),
            sleepDisabled: Power.sleepDisabled(), owned: FileManager.default.fileExists(atPath: ownershipMarker.path))

        if decision.owned { markOwned(true) }
        if let disable = decision.setSleepDisabled {
            log.notice("Setting disablesleep \(disable ? 1 : 0) (\(String(describing: decision.state), privacy: .public))")
            Power.setSleepDisabled(disable)
        }
        if !decision.owned { markOwned(false) }
        state = decision.state

        if decision.setSleepDisabled == false {
            // Clearing the setting doesn't by itself make powerd re-check a lid that's already closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if !Power.sleepDisabled(), Power.lidClosedWouldSleep() {
                    log.notice("Lid is closed with no display; sleeping now")
                    Power.sleepNow()
                }
            }
        }
    }

    private func markOwned(_ owned: Bool) {
        let fm = FileManager.default
        if owned {
            guard !fm.fileExists(atPath: ownershipMarker.path) else { return }
            try? fm.createDirectory(at: ownershipMarker.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: ownershipMarker.path, contents: nil)
        } else {
            try? fm.removeItem(at: ownershipMarker)
        }
    }

    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<Helper>.fromOpaque(context).takeUnretainedValue().evaluate()
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func scheduleIdleExit() {
        idleExit?.cancel()
        guard sessions.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sessions.isEmpty else { return }
            log.info("No clients; exiting")
            exit(0)
        }
        idleExit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }
}

final class Session: NSObject, LidAwakeHelperProtocol {
    private weak var helper: Helper?

    init(helper: Helper) {
        self.helper = helper
    }

    func setLidClosedAwake(_ wanted: Bool, reply: @escaping (Int) -> Void) {
        let id = ObjectIdentifier(self)
        DispatchQueue.main.async { [helper] in
            reply(helper?.set(wanted, for: id).rawValue ?? LidAwakeState.off.rawValue)
        }
    }
}

guard getuid() == 0 else {
    log.error("Must run as root")
    exit(1)
}
guard let team = LidAwake.ownTeamIdentifier() else {
    log.error("Helper isn't signed by a team; refusing to accept connections")
    exit(1)
}

let helper = Helper()
helper.run(team: team)
RunLoop.main.run()
