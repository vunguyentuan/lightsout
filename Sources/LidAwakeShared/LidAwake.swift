import Foundation
import Security

/// Names and signing rules shared by the app and its root helper.
public enum LidAwake {
    public static let appIdentifier = "com.vunguyen.LightsOut"
    public static let helperIdentifier = "com.vunguyen.LightsOut.helper"
    public static let machServiceName = "com.vunguyen.LightsOut.helper"
    public static let daemonPlistName = "com.vunguyen.LightsOut.helper.plist"

    /// Only code with this identifier, signed by Apple-issued certificates of the given team, satisfies it.
    public static func codeRequirement(identifier: String, team: String) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The team that signed the running process, or nil for ad hoc and unsigned builds.
    public static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// The helper's whole interface: one idempotent call that also reports where things stand.
@objc public protocol LidAwakeHelperProtocol {
    /// `reply` receives a `LidAwakeState` raw value.
    func setLidClosedAwake(_ wanted: Bool, reply: @escaping (Int) -> Void)
}

public enum LidAwakeState: Int {
    /// Nobody asked for it; normal sleep rules.
    case off
    /// Sleep is disabled, so a closed lid with no display doesn't sleep the Mac.
    case engaged
    /// Asked for, but the Mac is on battery, so sleep rules are normal.
    case pausedOnBattery
    /// Sleep was already disabled by someone else (`pmset disablesleep 1`); the helper leaves it alone.
    case disabledElsewhere
}

/// Decides what the helper does with `pmset disablesleep`. It only ever clears the setting when it was the
/// one that set it, so a `disablesleep 1` the user set by hand survives.
public enum SleepPolicy {
    public struct Decision: Equatable {
        /// The value to write, or nil to leave the setting alone.
        public var setSleepDisabled: Bool?
        /// Whether the helper owns the setting afterwards.
        public var owned: Bool
        public var state: LidAwakeState

        public init(setSleepDisabled: Bool?, owned: Bool, state: LidAwakeState) {
            self.setSleepDisabled = setSleepDisabled
            self.owned = owned
            self.state = state
        }
    }

    public static func decide(wanted: Bool, onAC: Bool, sleepDisabled: Bool, owned: Bool) -> Decision {
        guard wanted else {
            return Decision(setSleepDisabled: owned && sleepDisabled ? false : nil, owned: false, state: .off)
        }
        guard onAC else {
            return Decision(setSleepDisabled: owned && sleepDisabled ? false : nil, owned: false, state: .pausedOnBattery)
        }
        if !sleepDisabled {
            return Decision(setSleepDisabled: true, owned: true, state: .engaged)
        }
        return Decision(setSleepDisabled: nil, owned: owned, state: owned ? .engaged : .disabledElsewhere)
    }
}
