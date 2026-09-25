import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scale: ScaleController
    @State private var showsRawData = false

    private enum Palette {
        static let blue = Color(red: 0, green: 0.4, blue: 0.8)
        static let ink = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
        static let muted = Color(red: 122 / 255, green: 122 / 255, blue: 122 / 255)
        static let parchment = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
        static let dark = Color(red: 39 / 255, green: 39 / 255, blue: 41 / 255)
        static let hairline = Color(red: 224 / 255, green: 224 / 255, blue: 224 / 255)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    measurement
                    profile
                    history
                    diagnostics
                    footer
                }
            }
            .background(Palette.parchment)
            .foregroundStyle(Palette.ink)
        }
        .tint(Palette.blue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AFU 体脂秤")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.37)

            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.blue)
                    .frame(width: 8, height: 8)
                Text(scale.status)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 32)
        .background(Palette.parchment)
    }

    private var measurement: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("当前体重")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scale.latest.map { String(format: "%.2f", $0.weightKg) } ?? "— —")
                        .font(.system(size: 56, weight: .semibold))
                        .tracking(-0.28)
                    Text("kg")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            if let measurement = scale.latest {
                HStack(spacing: 24) {
                    Label(measurement.isStable ? "已稳定" : "测量中", systemImage: measurement.isStable ? "checkmark.circle.fill" : "waveform")
                    if let impedance = measurement.impedance {
                        Label("\(impedance.a) · \(impedance.b)", systemImage: "bolt.fill")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.75))
            } else {
                Text("站上体脂秤后，测量结果会显示在这里。")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 48)
        .foregroundStyle(.white)
        .background(Palette.dark)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("个人参数")
                    .font(.system(size: 21, weight: .semibold))
                    .tracking(-0.23)
                Text("身高 \(Int(scale.heightCm)) cm，用于计算 BMI。")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }

            HStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(Palette.blue)
                    .frame(width: 24)
                Text(scale.lastSavedText)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
            }

            writeSection
        }
        .padding(24)
        .background(Palette.parchment)
    }

    @ViewBuilder
    private var writeSection: some View {
        if scale.needsHealthAuthorization {
            Button {
                scale.requestHealthAuthorization()
            } label: {
                Text("允许写入 Apple 健康")
                    .font(.system(size: 17))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Palette.blue)
            .clipShape(Capsule())
            .accessibilityHint("打开 Apple 健康授权请求")
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近 5 条写入")
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.23)
                .padding(.bottom, 16)

            if scale.records.isEmpty {
                Text("还没有记录")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ForEach(Array(scale.records.enumerated()), id: \.element.id) { index, record in
                    recordRow(record)

                    if index < scale.records.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(24)
        .background(.white)
    }

    private func recordRow(_ record: SavedRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", record.weightKg))
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.26)
                    Text("kg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }

                HStack(spacing: 8) {
                    chip("BMI " + String(format: "%.1f", record.bmi))
                    chip("体脂 " + (record.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "—"))
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 14, weight: .semibold))
                Text(record.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
            }
            .foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 16)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.parchment)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var diagnostics: some View {
        if !scale.advertisementReport.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("秤广播诊断")
                    .font(.system(size: 14, weight: .semibold))
                Text(scale.advertisementReport)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !scale.eventLog.isEmpty {
                    Text("蓝牙事件（最近 30 条）")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 8)
                    Text(scale.eventLog.joined(separator: "\n"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .background(.white)
        }
        if !scale.latestRawHex.isEmpty {
            DisclosureGroup("原始测量数据", isExpanded: $showsRawData) {
                Text(scale.latestRawHex)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(24)
            .background(Palette.parchment)
        }
    }

    private var footer: some View {
        Text("首次使用请允许蓝牙与健康权限。之后 iOS 会在称重广播出现时通过蓝牙后台模式唤醒 App。")
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .background(Palette.parchment)
    }
}
