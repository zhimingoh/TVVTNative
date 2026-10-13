# TVVTNative

**用 Mac 直接控制 TVVT 蓝牙散热器。 / Control a TVVT Bluetooth cooler directly from your Mac.**

[中文](#中文) · [English](#english)

## 中文

### 为什么做这个项目

我的 **MacBook Air 正在使用这款 TVVT 散热器**。我希望直接在 Mac 上调整制冷、风扇和灯光，并查看温度、转速，而不必每次拿起手机打开微信小程序。

最初尝试在 Mac 微信中使用「TVVT散热器」小程序时，遇到了蓝牙初始化失败的提示。该提示把不同的初始化错误统一显示为“请打开蓝牙”，并不能准确说明问题。当前桌面微信是否开放了这个小程序需要的 BLE 接口，尚未完全确认。

因此，我分析了小程序的 BLE 通信协议，用 **SwiftUI + CoreBluetooth** 实现了这个独立的 macOS 原生控制器。实测已经能够在 Mac 上连接散热器、读取状态、发送制冷设置并收到成功确认。

### 功能

- 搜索并连接已知 TVVT 名称或服务的 BLE 设备。
- 实时显示冷面温度、热面温度、风扇转速、核芯电压和当前模式。
- 设置手动、低功耗、智能、强冷模式，以及功率、风扇档位和智能温度。
- 设置灯效、RGB 颜色、亮度、速度、风扇灯和侧灯开关。
- 显示连接和控制日志；分别处理蓝牙写入与设备协议确认。
- 无需微信、浏览器、Python、云服务或账号。

### 支持与验证范围

| 设备 / 环境 | 状态 |
| --- | --- |
| MacBook Air、Apple Silicon、macOS 26 | 已实测构建、启动、蓝牙扫描和连接 |
| T23SS / M2023-S | 已实测状态读取和制冷指令成功确认 |
| T23DD / M2023-D | 已实现服务匹配，尚未实测 |
| 灯光控制 | 已实现，尚未逐项验证实际灯效 |
| 其他 Mac / macOS 版本 | 尚未验证 |

这是个人项目，与 TVVT 厂商没有隶属关系。设备支持范围来自协议分析和上述实测，不代表所有型号都兼容。

### 构建与测试

需要 macOS 和 Xcode Command Line Tools。当前脚本使用本机架构与本机 SDK 构建；已验证的环境为 Apple Silicon + macOS 26。

```sh
# 若尚未安装命令行工具
xcode-select --install

# 获取源码
git clone https://github.com/zhimingoh/TVVTNative.git
cd TVVTNative

# 构建、测试、启动
./build.sh
./test.sh
open 'build/TVVT 散热器.app'
```

应用采用本机临时签名（ad hoc），没有开发者证书或 Apple 公证。建议在自己的 Mac 上从源码构建；构建产物不纳入源码仓库。

### 使用

1. 启动应用，允许 macOS 蓝牙访问。
2. 给散热器通电；若手机或其他应用已经连接，请先断开。
3. 点击“搜索散热器”，找到 `T23SS` 或 `T23DD` 后点击“连接”。
4. 等待温度、转速等有效状态出现，再调整设置并点击相应的“应用”按钮。编辑设置不会立即发送。
5. “从设备读取设置”会把最近收到的设备状态同步到编辑项，不会主动发送查询指令。

36W 保留了原小程序的供电条件：设备须报告 12V 供电检测结果，并勾选已安装水冷增强组件。温度编辑范围采用保守设计：冷面目标 −20…30℃，热面上限 40…60℃。

### 蓝牙故障排查

- **权限被拒绝**：在系统设置 → 隐私与安全性 → 蓝牙中允许应用。
- **搜索不到设备**：确认散热器通电，并断开手机小程序或其他客户端。
- **`Peer removed pairing information`**：Mac 的旧配对信息与设备不一致。在系统设置 → 蓝牙 → 对应散热器的详情中选择“忽略此设备”，然后重新搜索连接。本项目在 T23SS 上已验证此方法有效。
- **未收到设备确认**：3 秒内没有协议 ACK 会显示未确认；这与系统接受了蓝牙写入不是同一个结果。
- **状态超时**：5 秒没有新状态会禁用控制，请重新连接。

日志位于 `~/Library/Application Support/TVVTNative/session.log`，每次启动重新建立。日志可能包含设备标识与控制设置，提交问题时请先检查内容。

### BLE 协议概要

| 用途 | UUID / 帧 |
| --- | --- |
| M2023-S 服务 | `00010203-0405-0607-0809-0A0B0C0D1910` |
| M2023-D 服务 | `00010203-0405-0607-0809-0A0B0C0D1909` |
| 状态读取与通知 | `00010203-0405-0607-0809-0A0B0C0D2B10` |
| 控制写入 | `00010203-0405-0607-0809-0A0B0C0D2B11` |
| 普通控制帧 | `命令 + 负载长度 + 负载 + XOR 校验` |
| 状态 / 制冷 / 灯效 / 灯光开关 | `A0` / `B0` / `B1` / `B8` |

T23SS 实测通知特征支持 `read + notify`，控制特征支持 `read + writeWithoutResponse`。应用兼容有响应与无响应写入，控制帧只发送一次。

测试包含 12 个从原小程序 JavaScript 序列化函数得到的控制包向量，以及状态字段、负温、坏校验、短包、分片和合包检查。实测控制包 `B0 05 03 02 05 05 28 9C` 收到 `B0 01 10 A1`，其中 `0x10` 表示设备确认成功。

### 当前边界

此版本实现主要控制功能，不是整个小程序的完整复制。未实现 OTA、固件回退、恢复出厂、设备配色持久配置、水冷开关或自动关机配置。成功 ACK 证明设备接受指令，不代表已经测量验证每项物理制冷效果。

源码仓库包含独立的 Swift 实现与协议测试向量，不包含原小程序缓存、解包代码、厂商图片、固件或本机运行日志。

### 项目结构

```text
Sources/App.swift        SwiftUI 界面与 CoreBluetooth 连接管理
Sources/Protocol.swift   控制帧、状态解析与 BLE 分片处理
Tests/main.swift         协议测试
Tests/reference.json     原序列化函数生成的协议测试向量
build.sh                 构建并签名本机应用
test.sh                  编译并运行协议测试
```

## English

### Why this project exists

**I use this TVVT cooler with my MacBook Air.** I wanted to adjust cooling, fan settings and lighting, and read temperature and fan speed directly on my Mac, without reaching for my phone and opening a WeChat Mini Program each time.

My initial attempt to use the “TVVT散热器” Mini Program in WeChat for Mac produced a Bluetooth initialization error. The Mini Program displays the same “please turn on Bluetooth” message for different initialization failures, so that message does not identify the actual cause. Whether the current desktop WeChat exposes the BLE interfaces required by this Mini Program has not been fully established.

I therefore analyzed its BLE protocol and built an independent native macOS controller using **SwiftUI and CoreBluetooth**. Testing on real hardware confirmed that the Mac can connect to the cooler, read status, send cooling settings and receive a successful device acknowledgement.

### Features

- Discover and connect to BLE peripherals matching known TVVT names or services.
- Display cold-side and hot-side temperature, fan RPM, core voltage and current mode.
- Configure manual, low-power, smart and strong-cooling modes, power, fan level and smart temperature settings.
- Configure lighting effects, RGB, brightness, effect speed, fan lighting and side lighting.
- View connection and control logs, with separate handling of GATT writes and device protocol acknowledgements.
- No WeChat, browser, Python, cloud service or account required.

### Compatibility and validation

| Device / environment | Status |
| --- | --- |
| MacBook Air, Apple Silicon, macOS 26 | Build, launch, Bluetooth discovery and connection tested |
| T23SS / M2023-S | Live status and successful cooling-command acknowledgement tested |
| T23DD / M2023-D | Service matching implemented; hardware not yet tested |
| Lighting controls | Implemented; individual physical effects not yet verified |
| Other Macs / macOS versions | Not yet tested |

This is a personal project with no affiliation to TVVT. Compatibility is based on protocol analysis and the tests above, not a guarantee for every cooler model.

### Build and test

Requires macOS and Xcode Command Line Tools. The scripts build for the local machine architecture using the installed SDK. The tested environment is Apple Silicon running macOS 26.

```sh
# If Command Line Tools are not installed
xcode-select --install

# Clone the source
git clone https://github.com/zhimingoh/TVVTNative.git
cd TVVTNative

# Build, test and launch
./build.sh
./test.sh
open 'build/TVVT 散热器.app'
```

The app is signed ad hoc locally, without a developer certificate or Apple notarization. Building from source on your own Mac is recommended. Build artifacts are excluded from the source repository.

### Usage

1. Launch the app and allow Bluetooth access in macOS.
2. Power on the cooler. Disconnect any phone Mini Program or other client currently using it.
3. Click “搜索散热器” (Search), then “连接” (Connect) next to `T23SS` or `T23DD`.
4. Wait for valid temperature and fan readings. Edit settings and click the corresponding “应用” (Apply) button; editing alone does not send a command.
5. “从设备读取设置” (Read settings from device) copies the latest received status into the editable fields. It does not send an active query.

36W retains the original supply requirement: the cooler must report a 12V supply-detection result, and the water-cooling accessory checkbox must be selected. Editable temperatures use conservative ranges: −20…30°C for the cold-side target and 40…60°C for the hot-side limit.

The interface is currently in Chinese; this README documents it in both languages.

### Bluetooth troubleshooting

- **Permission denied:** allow the app under System Settings → Privacy & Security → Bluetooth.
- **No device found:** check cooler power and disconnect other clients.
- **`Peer removed pairing information`:** the Mac holds pairing information that no longer matches the device. Open the cooler’s details under System Settings → Bluetooth, select “Forget This Device”, then search and connect again. This recovery was verified with T23SS.
- **No device acknowledgement:** a missing protocol ACK after three seconds is reported as unconfirmed. A GATT write being accepted by the OS is a separate result.
- **Stale status:** controls are disabled after five seconds without fresh status; reconnect the cooler.

Logs are stored at `~/Library/Application Support/TVVTNative/session.log` and recreated on each launch. Check for device identifiers and control settings before attaching logs to an issue.

### BLE protocol overview

| Purpose | UUID / frame |
| --- | --- |
| M2023-S service | `00010203-0405-0607-0809-0A0B0C0D1910` |
| M2023-D service | `00010203-0405-0607-0809-0A0B0C0D1909` |
| Status reads and notifications | `00010203-0405-0607-0809-0A0B0C0D2B10` |
| Control writes | `00010203-0405-0607-0809-0A0B0C0D2B11` |
| Normal control frame | `command + payload length + payload + XOR checksum` |
| Status / cooling / lighting effect / lighting switches | `A0` / `B0` / `B1` / `B8` |

On the tested T23SS, the status characteristic supports `read + notify` and the control characteristic supports `read + writeWithoutResponse`. The app handles both write types and sends each control frame once.

Tests cover 12 reference control frames generated by the original Mini Program’s JavaScript serializer, telemetry fields, negative temperatures, checksum rejection, short packets, fragmentation and coalesced frames. A real-device write of `B0 05 03 02 05 05 28 9C` received `B0 01 10 A1`; `0x10` indicates success.

### Current limitations

This version implements the main controls rather than reproducing the complete Mini Program. OTA updates, firmware rollback, factory reset, persistent device-color configuration, the water-cooling switch and automatic shutdown configuration are not implemented. A successful ACK confirms command acceptance; it does not establish measured cooling performance for every setting.

The repository contains the independent Swift implementation and protocol test vectors. It excludes the original Mini Program cache, extracted vendor code, vendor images, firmware and local runtime logs.

### Project layout

```text
Sources/App.swift        SwiftUI interface and CoreBluetooth connection management
Sources/Protocol.swift   Command framing, status parsing and BLE reassembly
Tests/main.swift         Protocol tests
Tests/reference.json     Reference vectors generated by the original serializer
build.sh                 Build and locally sign the app
test.sh                  Compile and run protocol tests
```
