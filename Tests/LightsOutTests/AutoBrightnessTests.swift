import XCTest
@testable import LightsOut

final class AutoBrightnessTests: XCTestCase {
    func testCurveSpansFloorToFull() {
        XCTAssertEqual(AutoBrightness.curve(logLux: log10(0.1)), 0.1, accuracy: 0.0001)
        XCTAssertEqual(AutoBrightness.curve(logLux: 0), 0.1, accuracy: 0.0001)
        XCTAssertEqual(AutoBrightness.curve(logLux: log10(2000)), 1, accuracy: 0.0001)
        XCTAssertEqual(AutoBrightness.curve(logLux: log10(100_000)), 1, accuracy: 0.0001)
    }

    func testCurveRisesWithLight() {
        let levels = [1.0, 10, 50, 300, 1000].map { AutoBrightness.curve(logLux: log10($0)) }
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertEqual(Set(levels).count, levels.count)
    }

    func testOffsetIsClamped() {
        XCTAssertEqual(AutoBrightness.level(logLux: log10(50), offset: -2), 0)
        XCTAssertEqual(AutoBrightness.level(logLux: log10(50), offset: 2), 1)
        let base = AutoBrightness.curve(logLux: log10(50))
        XCTAssertEqual(AutoBrightness.level(logLux: log10(50), offset: -0.2), base - 0.2, accuracy: 0.0001)
    }

    func testParsesSensorLines() {
        XCTAssertEqual(AutoBrightness.lux(fromLine: "1761900000 42.5"), 42.5)
        XCTAssertEqual(AutoBrightness.lux(fromLine: "63"), 63)
        XCTAssertEqual(AutoBrightness.lux(fromLine: "  1761900000\t0  "), 0)
        XCTAssertNil(AutoBrightness.lux(fromLine: ""))
        XCTAssertNil(AutoBrightness.lux(fromLine: "waiting for phone"))
        XCTAssertNil(AutoBrightness.lux(fromLine: "1761900000 -1"))
        XCTAssertNil(AutoBrightness.lux(fromLine: "1761900000 nan"))
    }
}
