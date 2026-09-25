# AFUScale

AFUScale 是一款适用于 **AFU-WL-TZ-A1** 体脂秤的 iOS 应用。它通过蓝牙读取称重数据，将体重和 BMI 保存到 Apple 健康，并把阻抗与原始数据包记录到本地文件。

## 主要功能

- 自动发现并连接 AFU-WL-TZ-A1 体脂秤；连接过一次后对该秤保持待连接，App 在后台时站上秤即可自动记录
- 显示体重、测量状态与阻抗数据
- 将体重和 BMI 写入 Apple 健康（身高固定为 177 cm，见 `ScaleController.heightCm`）
- 每次最终结果追加到 `Documents/measurements.csv`（时间、体重、阻抗 a/b、前后台、原始包 hex），可在「文件」App → 我的 iPhone → AFUScale 中查看
- 查看最近 5 条写入记录
- 诊断区显示秤的广播内容和最近 30 条蓝牙事件，用于排查后台漏记

## 系统要求

- iPhone，iOS 17 或更高
- AFU-WL-TZ-A1 体脂秤
- 装有 Xcode 的 Mac，以及一个 Apple ID（免费即可）

## 安装

用 Xcode 的免费 Personal Team 签名会保留 HealthKit 权限；Sideloadly 等重签工具会剥掉它，装上后无法写入 Apple 健康。

1. 把 `project.yml` 里的 `DEVELOPMENT_TEAM` 和 `PRODUCT_BUNDLE_IDENTIFIER` 改成自己的（Xcode → Settings → Accounts 登录 Apple ID 后可在 Signing & Capabilities 查看 Team ID），然后运行 `xcodegen generate`。
2. iPhone 连接 Mac 并信任此电脑，构建并安装：
   ```
   xcodebuild -project AFUScale.xcodeproj -scheme AFUScale -configuration Debug \
     -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates \
     -allowProvisioningDeviceRegistration build
   ideviceinstaller install build/Build/Products/Debug-iphoneos/AFUScale.app   # brew install ideviceinstaller
   ```
   也可以直接在 Xcode 中选中设备后 Run。
3. 在 iPhone 上开启 **设置 → 隐私与安全性 → 开发者模式**，并在 **设置 → 通用 → VPN 与设备管理** 中信任开发者。
4. 打开 AFUScale，允许蓝牙和 Apple 健康权限。

> 免费 Apple ID 签名 7 天后失效，需重新构建安装；已写入 Apple 健康的数据和 `measurements.csv` 不受影响。

## 使用方法

1. 首次打开 App 后站上秤，让它连上并记住这台秤。
2. 之后 App 在后台（未被手动划掉）时站上秤，会自动连接、写入 Apple 健康并记录阻抗。
3. 漏记时查看诊断区「蓝牙事件」：没有任何事件说明未赶上秤的广播窗口；有「已连接」无「收到最终结果」说明测量未完成。

## 隐私

AFUScale 不需要注册账号，不包含任何网络请求代码，数据不离开设备。测量结果由 Apple 健康管理，阻抗记录保存在 App 的 Documents 目录。

## 注意事项

- 秤只提供体重和阻抗，BMI 由体重和身高计算。App 不估算体脂率：仅凭 BMI 和年龄套公式得出的体脂没有新信息，写入 Health 会与真实测量混在一起。
- 称重时未测到阻抗（未踩实电极、隔着袜子等），`measurements.csv` 中阻抗列为空。
- 手动划掉 App 后 iOS 不会在后台唤醒它，需重新打开一次。
