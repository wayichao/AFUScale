import Foundation

enum BodyMetrics {
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let h = heightCm / 100
        return weightKg / (h * h)
    }
}
