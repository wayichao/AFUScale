import CoreBluetooth
import Foundation
import UIKit

@MainActor
final class ScaleController: NSObject, ObservableObject {
    @Published var status = "初始化"
    @Published var latest: ScaleMeasurement?
    @Published var latestRawHex = ""
    @Published var lastSavedText = "尚未写入"
    @Published var needsHealthAuthorization = false
    @Published var records: [SavedRecord] = []
    /// 最近一次发现秤时的广播内容，用来判断能否后台连接；持久保存，事后也能查看。
    @Published var advertisementReport = UserDefaults.standard.string(forKey: "AFUScale.advertisementReport") ?? "" {
        didSet { UserDefaults.standard.set(advertisementReport, forKey: "AFUScale.advertisementReport") }
    }
    /// 最近的蓝牙事件（带前后台标记），用来排查后台漏记卡在哪一步；持久保存。
    @Published var eventLog = UserDefaults.standard.stringArray(forKey: "AFUScale.eventLog") ?? [] {
        didSet { UserDefaults.standard.set(eventLog, forKey: "AFUScale.eventLog") }
    }

    private func logEvent(_ text: String) {
        let bg = UIApplication.shared.applicationState == .background ? "后台" : "前台"
        eventLog = Array(([Date().formatted(date: .numeric, time: .standard) + " [\(bg)] " + text] + eventLog).prefix(30))
    }

    /// 连上过的秤，下次直接挂待连接，不再依赖后台扫描。
    private static let knownScaleKey = "AFUScale.knownScaleID"

    private let health = HealthWriter()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var lastSavedAt: Date?

    private let targetName = "AFU-WL-TZ-A1"
    private let ffb0 = CBUUID(string: "0000FFB0-0000-1000-8000-00805F9B34FB")
    private let ffb2 = CBUUID(string: "0000FFB2-0000-1000-8000-00805F9B34FB")

    let heightCm = 177.0

    override init() {
        super.init()
        observeAppState()
        needsHealthAuthorization = !health.isWriteAuthorized
        loadRecords()
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "AFUScale.central"]
        )
    }

    func requestHealthAuthorization() {
        if health.isWriteAuthorized {
            healthAuthorized()
            return
        }
        Task {
            do {
                try await health.requestAuthorization()
                if health.isWriteAuthorized {
                    healthAuthorized()
                } else {
                    needsHealthAuthorization = true
                    status = "Health 未授权写入"
                }
            } catch {
                needsHealthAuthorization = true
                status = "Health 授权失败：\(error.localizedDescription)"
            }
        }
    }

    private func healthAuthorized() {
        needsHealthAuthorization = false
        status = "Health 已授权，等待秤"
        loadRecords()
        startScanningIfReady()
    }

    func loadRecords() {
        Task {
            records = Array(((try? await health.fetchRecords()) ?? []).prefix(5))
        }
    }

    private func startScanningIfReady() {
        guard central.state == .poweredOn else { return }
        status = "等待秤"
        armPendingConnection()
        central.stopScan()
        // 前台扫全部设备，靠名称/FFB0 过滤，不依赖广播里带服务 UUID。
        // iOS 后台不接受 nil 扫描，只能按 FFB0 过滤；秤广播里不带 FFB0 时后台就发现不了它。
        if UIApplication.shared.applicationState == .background {
            central.scanForPeripherals(withServices: [ffb0])
        } else {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    /// 秤只在被踩时短暂广播，后台扫描占空比低容易错过；对已知的秤挂一个不超时的
    /// connect，由系统蓝牙持续等它出现就直接连上。扫描仍保留，兜底首次配对和标识变化。
    private func armPendingConnection() {
        guard peripheral == nil,
              let raw = UserDefaults.standard.string(forKey: Self.knownScaleKey),
              let id = UUID(uuidString: raw),
              let known = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = known
        known.delegate = self
        central.connect(known, options: nil)
    }

    /// 前后台切换时按对应方式重新扫描；正在连着秤就不打断。
    private func observeAppState() {
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.peripheral?.state != .connected else { return }
                    self.startScanningIfReady()
                }
            }
        }
    }

    private func handle(_ measurement: ScaleMeasurement, rawHex: String) {
        latest = measurement
        latestRawHex = rawHex
        print("[AFUScale][parsed] weight=\(measurement.weightKg) stable=\(measurement.isStable) final=\(measurement.isFinal) impedance=\(String(describing: measurement.impedance))")
        // 只写最终结果包（byte[2] == 0x02）。阻抗可能为 0，体重仍有效。
        guard measurement.isFinal else {
            print("[AFUScale][skip] not final result packet")
            return
        }
        print("[AFUScale][save] final result packet")
        logEvent(String(format: "收到最终结果 %.2f kg", measurement.weightKg))
        save(measurement)
    }

    private func save(_ measurement: ScaleMeasurement) {
        if let lastSavedAt, Date().timeIntervalSince(lastSavedAt) < 90 {
            disconnectFromScale()
            return
        }
        lastSavedAt = Date()

        let weight = (measurement.weightKg * 100).rounded() / 100
        let bmi = BodyMetrics.bmi(weightKg: weight, heightCm: heightCm)
        MeasurementLog.append(
            measurement,
            weightKg: weight,
            rawHex: latestRawHex,
            appState: UIApplication.shared.applicationState == .background ? "background" : "foreground"
        )
        Task {
            do {
                // 体脂率只能用 BMI 和年龄估算，没有新信息，不写入，免得和真实测量混在一起。
                try await health.save(weightKg: weight, bmi: bmi, bodyFatPercent: nil)
                loadRecords()
                lastSavedText = String(format: "已写入：%.2f kg / BMI %.1f", weight, bmi)
                status = "写入完成，断开连接"
                logEvent(String(format: "已写入健康 %.2f kg", weight))
                disconnectFromScale()
            } catch {
                status = "Health 写入失败：\(error.localizedDescription)"
                logEvent("写入健康失败")
                disconnectFromScale()
            }
        }
    }

    private func disconnectFromScale() {
        guard let peripheral else {
            startScanningIfReady()
            return
        }
        central.cancelPeripheralConnection(peripheral)
    }
}

extension ScaleController: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                self.startScanningIfReady()
            } else {
                self.status = "蓝牙不可用：\(central.state.rawValue)"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        Task { @MainActor in
            self.status = "系统恢复后台蓝牙状态"
            self.logEvent("系统唤醒恢复")
            if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
                self.peripheral = restored
                restored.delegate = self
            }
            self.startScanningIfReady()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name
        let nameForDisplay = localName ?? peripheralName ?? ""
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        Task { @MainActor in
            let hasFFB0 = serviceUUIDs.contains(self.ffb0)
            let isTargetLocalName = localName == self.targetName
            let isClone = nameForDisplay.contains("Clone")
            guard (isTargetLocalName || hasFFB0), !isClone else { return }
            // 已经对这台秤挂着待连接，交给它，不重复发起。
            if self.peripheral?.identifier == peripheral.identifier { return }
            self.logEvent("扫描发现秤")
            self.status = "发现 AFU-WL-TZ-A1，连接中"
            self.advertisementReport = [
                Date().formatted(date: .abbreviated, time: .standard),
                "名称：\(nameForDisplay)",
                "广播服务：" + (serviceUUIDs.isEmpty ? "无" : serviceUUIDs.map(\.uuidString).joined(separator: ", ")),
                hasFFB0 ? "含 FFB0：是，可以后台自动连接" : "含 FFB0：否，后台发现不了秤，需开着 App 称重"
            ].joined(separator: "\n")
            self.peripheral = peripheral
            peripheral.delegate = self
            central.stopScan()
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.status = "已连接，发现服务"
            self.logEvent("已连接")
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.knownScaleKey)
            peripheral.discoverServices([self.ffb0])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.logEvent("连接失败：\(error?.localizedDescription ?? "未知")")
            self.peripheral = nil
            self.startScanningIfReady()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.logEvent("已断开")
            self.peripheral = nil
            self.status = "已断开，等待秤"
            self.startScanningIfReady()
        }
    }
}

extension ScaleController: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for service in services where service.uuid == self.ffb0 {
                peripheral.discoverCharacteristics([self.ffb2], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let chars = service.characteristics else { return }
            for ch in chars where ch.uuid == self.ffb2 {
                self.status = "订阅称重数据"
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: "0000FFB2-0000-1000-8000-00805F9B34FB"),
              let data = characteristic.value else { return }
        let rawHex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("[AFUScale][raw] \(rawHex)")
        guard let measurement = ScalePacketParser.parse(data) else {
            print("[AFUScale][skip] parse failed")
            return
        }
        Task { @MainActor in
            self.handle(measurement, rawHex: rawHex)
        }
    }
}
