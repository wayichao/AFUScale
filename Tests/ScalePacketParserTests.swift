import XCTest
@testable import AFUScale

final class ScalePacketParserTests: XCTestCase {
    func testParsesRealtimeWeightPacket() throws {
        let data = Data(hex: "ac 29 80 69 0f e0 02 00 05 40 00 64 00 00 00 00 00 29 d5 06")
        let result = try XCTUnwrap(ScalePacketParser.parse(data))
        XCTAssertEqual(result.weightKg, 69.6, accuracy: 0.001)
        XCTAssertTrue(result.isStable)
        XCTAssertFalse(result.isFinal)
        XCTAssertNil(result.impedance)
    }

    func testParsesFinalResultPacketWithImpedance() throws {
        let data = Data(hex: "ac 29 02 00 01 e2 01 b0 01 80 69 0f e0 00 00 00 00 29 d6 0e")
        let result = try XCTUnwrap(ScalePacketParser.parse(data))
        XCTAssertEqual(result.weightKg, 69.6, accuracy: 0.001)
        XCTAssertTrue(result.isStable)
        XCTAssertTrue(result.isFinal)
        XCTAssertEqual(result.impedance?.a, 482)
        XCTAssertEqual(result.impedance?.b, 432)
    }

    func testParsesFinalResultPacketWithoutImpedance() throws {
        let data = Data(hex: "ac 29 02 00 00 00 00 00 01 80 68 13 ec 00 00 00 00 29 d6 09")
        let result = try XCTUnwrap(ScalePacketParser.parse(data))
        XCTAssertEqual(result.weightKg, 5.1, accuracy: 0.001)
        XCTAssertTrue(result.isStable)
        XCTAssertTrue(result.isFinal)
        XCTAssertNil(result.impedance)
    }

    func testIgnoresInvalidPacket() {
        XCTAssertNil(ScalePacketParser.parse(Data([0x00, 0x01])))
    }
}

private extension Data {
    init(hex: String) {
        self.init(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }
}

final class MeasurementLogTests: XCTestCase {
    func testAppendsImpedanceAndRawHex() throws {
        try? FileManager.default.removeItem(at: MeasurementLog.url)
        let m = ScaleMeasurement(weightKg: 69.6, isStable: true, isFinal: true, impedance: Impedance(a: 482, b: 432))
        MeasurementLog.append(m, weightKg: 69.6, rawHex: "ac 29 02", appState: "foreground", date: Date(timeIntervalSince1970: 0))
        MeasurementLog.append(ScaleMeasurement(weightKg: 5.1, isStable: true, isFinal: true, impedance: nil),
                              weightKg: 5.1, rawHex: "ac", appState: "background", date: Date(timeIntervalSince1970: 60))
        let lines = try String(contentsOf: MeasurementLog.url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], "1970-01-01T00:00:00Z,69.60,482,432,foreground,ac 29 02")
        XCTAssertEqual(lines[2], "1970-01-01T00:01:00Z,5.10,,,background,ac")
    }
}
