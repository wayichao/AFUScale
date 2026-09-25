import XCTest
@testable import AFUScale

final class BodyMetricsTests: XCTestCase {
    func testCalculatesBmi() {
        XCTAssertEqual(BodyMetrics.bmi(weightKg: 68.65, heightCm: 172), 23.2, accuracy: 0.05)
    }
}
