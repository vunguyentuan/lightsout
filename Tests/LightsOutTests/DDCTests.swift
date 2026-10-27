import XCTest
@testable import LightsOut

final class DDCTests: XCTestCase {
    func testGetRequestChecksum() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10
        XCTAssertEqual(DDC.getRequest(vcp: 0x10), [0x82, 0x01, 0x10, 0xAC])
    }

    func testSetRequestEncodesValueBigEndian() {
        let packet = DDC.setRequest(vcp: 0x10, value: 0x0150)
        XCTAssertEqual(Array(packet.prefix(5)), [0x84, 0x03, 0x10, 0x01, 0x50])
        XCTAssertEqual(packet[5], packet.prefix(5).reduce(0x6E ^ 0x51, ^))
    }

    func testParsesBrightnessReply() {
        // Captured from an LG 27UP850: brightness 80 of 100.
        let reply: [UInt8] = [0x6E, 0x51, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x50, 0x90, 0xD4]
        let reading = DDC.parseReply(reply, vcp: 0x10)
        XCTAssertEqual(reading?.current, 80)
        XCTAssertEqual(reading?.max, 100)
    }

    func testRejectsNullMessage() {
        // What the same monitor returns when a request is sent only once.
        let reply: [UInt8] = [0x6E, 0x80, 0xBE, 0x00, 0xE6, 0xD2, 0xD0, 0xA4, 0x0A, 0xF9, 0xAB, 0x2F]
        XCTAssertNil(DDC.parseReply(reply, vcp: 0x10))
    }

    func testRejectsReplyForAnotherFeature() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x46, 0x00]
        XCTAssertNil(DDC.parseReply(reply, vcp: 0x10))
    }

    func testRejectsUnsupportedFeatureResult() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertNil(DDC.parseReply(reply, vcp: 0x10))
    }
}
