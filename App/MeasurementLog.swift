import Foundation

/// 每次最终结果都追加到 Documents/measurements.csv，保留 Health 放不下的阻抗和原始包。
/// 开了文件共享，可在「文件」App → 我的 iPhone → AFUScale 里查看和导出。
enum MeasurementLog {
    static let url = URL.documentsDirectory.appending(path: "measurements.csv")
    private static let header = "time,weight_kg,impedance_a,impedance_b,app_state,raw_hex\n"

    static func append(_ m: ScaleMeasurement, weightKg: Double, rawHex: String, appState: String, date: Date = Date()) {
        let fields = [
            date.ISO8601Format(.iso8601.timeZone(separator: .omitted)),
            String(format: "%.2f", weightKg),
            m.impedance.map { String($0.a) } ?? "",
            m.impedance.map { String($0.b) } ?? "",
            appState,
            rawHex
        ]
        let line = Data((fields.joined(separator: ",") + "\n").utf8)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data(header.utf8))
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }
}
