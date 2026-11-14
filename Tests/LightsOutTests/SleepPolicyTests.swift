import LidAwakeShared
import XCTest

final class SleepPolicyTests: XCTestCase {
    private func decide(wanted: Bool, onAC: Bool, disabled: Bool, owned: Bool) -> SleepPolicy.Decision {
        SleepPolicy.decide(wanted: wanted, onAC: onAC, sleepDisabled: disabled, owned: owned)
    }

    func testEngagesOnACAndTakesOwnership() {
        XCTAssertEqual(decide(wanted: true, onAC: true, disabled: false, owned: false),
                       .init(setSleepDisabled: true, owned: true, state: .engaged))
    }

    func testHoldsWhatItAlreadyOwns() {
        XCTAssertEqual(decide(wanted: true, onAC: true, disabled: true, owned: true),
                       .init(setSleepDisabled: nil, owned: true, state: .engaged))
    }

    func testReleasesOnBattery() {
        XCTAssertEqual(decide(wanted: true, onAC: false, disabled: true, owned: true),
                       .init(setSleepDisabled: false, owned: false, state: .pausedOnBattery))
    }

    func testReleasesWhenNoLongerWanted() {
        XCTAssertEqual(decide(wanted: false, onAC: true, disabled: true, owned: true),
                       .init(setSleepDisabled: false, owned: false, state: .off))
    }

    func testNeverTouchesASettingTheUserMade() {
        XCTAssertEqual(decide(wanted: true, onAC: true, disabled: true, owned: false),
                       .init(setSleepDisabled: nil, owned: false, state: .disabledElsewhere))
        XCTAssertEqual(decide(wanted: false, onAC: true, disabled: true, owned: false),
                       .init(setSleepDisabled: nil, owned: false, state: .off))
        XCTAssertEqual(decide(wanted: true, onAC: false, disabled: true, owned: false),
                       .init(setSleepDisabled: nil, owned: false, state: .pausedOnBattery))
    }

    func testDropsStaleOwnershipWhenSomeoneElseCleared() {
        XCTAssertEqual(decide(wanted: false, onAC: true, disabled: false, owned: true),
                       .init(setSleepDisabled: nil, owned: false, state: .off))
    }

    func testRequirementPinsIdentifierAndTeam() {
        XCTAssertEqual(LidAwake.codeRequirement(identifier: "com.example.App", team: "ABCDE12345"),
                       #"identifier "com.example.App" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#)
    }
}
