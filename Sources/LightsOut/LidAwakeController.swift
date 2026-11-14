import Foundation
import LidAwakeShared
import ServiceManagement

/// Keeps the Mac awake with the lid closed on AC power, through the root helper (`LightsOutHelper`).
///
/// A closed MacBook lid sleeps the system whenever no display is active (for example, the external monitor
/// is switched off), and no power assertion prevents that. Only `pmset disablesleep 1` does, which needs root.
/// The helper holds it while this app is connected and asking, and drops it on battery or when the app goes away.
final class LidAwakeController {
    enum Status: Equatable {
        case off
        case needsApproval
        case engaged
        case pausedOnBattery
        case disabledElsewhere
        case unavailable(String)
    }

    private let service = SMAppService.daemon(plistName: LidAwake.daemonPlistName)
    private let team = LidAwake.ownTeamIdentifier()
    private var connection: NSXPCConnection?
    private(set) var wanted = false
    private(set) var status = Status.off

    func setWanted(_ on: Bool) {
        wanted = on
        sync()
    }

    /// Registers the helper if needed and re-sends the request. Cheap; called periodically to pick up approval
    /// in System Settings, power-source changes and helper restarts.
    func sync() {
        guard wanted else {
            connection?.invalidate()
            connection = nil
            status = .off
            return
        }
        guard team != nil else {
            status = .unavailable("This build isn't signed with a developer certificate, so the helper can't run.")
            return
        }
        if service.status != .enabled {
            if service.status != .requiresApproval {
                do {
                    try service.register()
                } catch {
                    if service.status != .requiresApproval {
                        status = .unavailable(error.localizedDescription)
                        return
                    }
                }
            }
            if service.status == .requiresApproval {
                status = .needsApproval
                return
            }
        }
        let proxy = helperConnection().remoteObjectProxyWithErrorHandler { [weak self] error in
            DispatchQueue.main.async {
                guard self?.wanted == true else { return }
                self?.status = .unavailable(error.localizedDescription)
            }
        } as? LidAwakeHelperProtocol
        proxy?.setLidClosedAwake(true) { [weak self] raw in
            DispatchQueue.main.async {
                guard let self, self.wanted else { return }
                switch LidAwakeState(rawValue: raw) ?? .off {
                case .off: self.status = .off
                case .engaged: self.status = .engaged
                case .pausedOnBattery: self.status = .pausedOnBattery
                case .disabledElsewhere: self.status = .disabledElsewhere
                }
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func helperConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: LidAwake.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: LidAwakeHelperProtocol.self)
        if let team {
            connection.setCodeSigningRequirement(LidAwake.codeRequirement(identifier: LidAwake.helperIdentifier, team: team))
        }
        // The helper restarted (crash, or idle exit racing a request). It forgets us, so ask again.
        connection.interruptionHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, self.connection === connection else { return }
                self.connection?.invalidate()
                self.connection = nil
                self.sync()
            }
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, self.connection === connection else { return }
                self.connection = nil
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }
}
