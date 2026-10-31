# TVVTNative

**用 Mac 直接控制 TVVT 蓝牙散热器。 / Control a TVVT Bluetooth cooler directly from your Mac.**

[中文](#中文) · [English](#english)

## 中文

### 为什么做这个项目

我的 **MacBook Air 正在使用这款 TVVT 散热器**。我希望直接在 Mac 上调整制冷、风扇和灯光，并查看温度、转速，而不必每次拿起手机打开微信小程序。

最初尝试在 Mac 微信中使用「TVVT散热器」小程序时，遇到了蓝牙初始化失败的提示。该提示把不同的初始化错误统一显示为“请打开蓝牙”，并不能准确说明问题。当前桌面微信是否开放了这个小程序需要的 BLE 接口，尚未完全确认。

因此，我分析了小程序的 BLE 通信协议，用 **SwiftUI + CoreBluetooth** 实现了这个独立的 macOS 原生控制器。实测已经能够在 Mac 上连接散热器、读取状态、发送制冷设置并收到成功确认。

### 最新版本：0.2.1

新增菜单栏温度与双模式控制、设备记忆和自动重连、系统登录启动，以及固定本机签名与安装流程。已在 M2 Mac 和 T23SS 上验证更新后保留蓝牙授权、自动重连和控制确认；实际注销登录、睡眠恢复及完整异常界面验证仍待完成。

### 功能

- Mac 顶部菜单栏显示本机芯片温度、连接状态和当前模式，点击即可切换“全速前进 / 自动模式”。
- 全速前进请求 36W、最高风扇；自动模式按本机温度调整 10W / 18W / 36W。
- 首次选定散热器后记住设备，启动、意外断连及睡眠唤醒后自动重连；主动断开会暂停重连。
- 首次启动尝试注册系统登录项，支持查看注册状态和进入系统登录项设置。
- 搜索并连接已知 TVVT 名称或服务的 BLE 设备。
- 实时显示冷面温度、热面温度、风扇转速、核芯电压和当前模式。
- 设置手动、低功耗、智能、强冷模式，以及功率、风扇档位和智能温度。
- 设置灯效、RGB 颜色、亮度、速度、风扇灯和侧灯开关。
- 显示连接和控制日志；分别处理蓝牙写入与设备协议确认。
- 应用运行无需微信、浏览器、Python、云服务或账号；首次本机签名配置使用 Python 3 和 OpenSSL 3+。

### 支持与验证范围

| 设备 / 环境 | 状态 |
| --- | --- |
| MacBook Air、Apple Silicon、macOS 26 | 已实测构建、启动、蓝牙扫描和连接 |
| T23SS / M2023-S | 已实测状态读取和制冷指令成功确认 |
| T23DD / M2023-D | 已实现服务匹配，尚未实测 |
| M2 本机温度与双模式 | 已实测温度采集、全速与自动控制确认 |
| 固定签名更新与自动重连 | 已实测 0.2.0 → 0.2.1 更新后无需再次蓝牙授权并重连 |
| 登录启动 / 睡眠唤醒恢复 | 已实现；实际注销登录与睡眠恢复尚未验证 |
| 灯光控制 | 已实现，尚未逐项验证实际灯效 |
| 其他 Mac / macOS 版本 | 尚未验证 |

这是个人项目，与 TVVT 厂商没有隶属关系。设备支持范围来自协议分析和上述实测，不代表所有型号都兼容。

### 构建与测试

需要 macOS 14 或更新版本和 Xcode Command Line Tools。当前脚本使用本机架构与本机 SDK 构建；已验证的环境为 Apple Silicon + macOS 26。

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

首次本机签名配置还需要 Python 3 和 OpenSSL 3+（`openssl version` 应显示 3 或更新版本；macOS 自带的 LibreSSL 不适用）。

未配置本机证书时，构建使用临时签名（ad hoc），重新构建可能触发再次授权。日常使用建议配置固定的本机代码签名证书并安装到固定位置：

```sh
# 首次执行：按系统提示由本人完成钥匙串授权
python3 scripts/setup-signing.py
# 后续更新均执行此命令，复用同一证书和安装路径
./install.sh
open '/Applications/TVVT 散热器.app'
```

本机证书仅在用户级信任设置中用于代码签名，不添加 HTTPS 信任。私钥导入钥匙串时设为不可导出并限定 codesign 访问；公开证书及指纹配置保存在 `~/Library/Application Support/TVVTNative/Signing/`，不会提交仓库。已配置的证书不可用时构建会报错，不静默退回临时签名；请保留原证书，不为每次更新重新生成。`TVVT_SIGN_IDENTITY` 可显式选择其他已有签名身份，显式设为 `-` 仅用于临时调试，不用于日常安装。

从旧的临时签名切换到固定证书后，macOS 可能还需要授权一次。固定证书通常能让后续更新保留授权，但系统重置权限、证书到期/更换、重装系统等仍可能要求重新允许。这不是 Apple Developer ID 签名或 Apple 公证，适合在自己的 Mac 上从源码构建自用。

### 使用

1. 启动应用，允许 macOS 蓝牙访问。
2. 给散热器通电；若手机或其他应用已经连接，请先断开。
3. 首次运行会显示控制面板，点击“搜索散热器”，找到你的 `T23SS` 或 `T23DD` 后点击“连接”。成功收到状态后才记住此设备；以后自动连接同一设备，不按型号盲选其他设备。
4. 点击顶部菜单栏风扇图标选择“全速前进”或“自动模式”。关闭控制窗口不退出应用；退出请使用菜单栏面板的“退出”。
5. 等待温度、转速等有效状态出现，再调整设置并点击相应的“应用”按钮。应用手动制冷设置会退出自动接管；编辑设置不会立即发送。
6. “从设备读取设置”会把最近收到的设备状态同步到编辑项，不会主动发送查询指令。

应用允许发送 36W 请求，供电与附件限制交由设备固件处理；请求成功不代表实际物理输出已达到 36W。面板分别显示请求、协议确认和设备报告的档位，不将档位当作实测功率。温度编辑范围：冷面目标 −20…30℃，热面上限 40…60℃。

自动模式每 2 秒采集 M2 芯片传感器温度，使用有效 CPU/GPU 读数的最高值：低于 55℃ 请求 10W / 风扇 4，55～不足 70℃ 请求 18W / 风扇 7，70℃起请求 36W / 风扇 10。降档需低于对应阈值 5℃并持续 20 秒。读数无效或超过 6 秒时暂停新自动请求、保留设备最后设置并提示；全速不依赖本机温度。

本机摄氏温度映射目前仅支持 M2 系列；其他芯片显示不可用，仍可使用全速和原手动控制。不会用散热器温度、电池温度或系统热压力冒充芯片温度。

登录启动使用系统 `SMAppService`。从固定位置运行应用，菜单栏可查看是否“已启用 / 等待系统批准 / 注册失败”；需要时在“登录项设置”允许。仅注册成功不代表实际注销后启动已验证。固定签名版本安装到 `/Applications` 后会迁移登录项路径；应用路径或证书变化仍可能影响系统批准状态。主动断开会跨睡眠唤醒保持暂停，手动恢复连接或重新启动应用后解除。

### 蓝牙故障排查

- **权限被拒绝或一直等待授权**：在系统设置 → 隐私与安全性 → 蓝牙中允许应用。重新构建的 ad hoc 签名可能需要重新授权，建议按上文配置固定证书；若列表已开启但仍卡住，需由本机用户解锁设置、刷新该应用权限后重新打开。应用不会自行绕过系统授权。
- **搜索不到设备**：确认散热器通电，并断开手机小程序或其他客户端。
- **`Peer removed pairing information`**：Mac 的旧配对信息与设备不一致。在系统设置 → 蓝牙 → 对应散热器的详情中选择“忽略此设备”，然后重新搜索连接。本项目在 T23SS 上已验证此方法有效。
- **未收到设备确认**：3 秒内没有协议 ACK 会显示未确认；这与系统接受了蓝牙写入不是同一个结果。
- **状态超时**：5 秒没有新状态会停止控制并重连；意外断连按 2～60 秒退避重试，手机占用、蓝牙关闭或权限拒绝时不会假报已连接。

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
Sources/App.swift        共享控制模型、原控制窗口与 BLE 管理
Sources/MenuBar.swift    原生菜单栏与弹出面板、窗口生命周期
Sources/CoolingPolicy.swift 温控回差、双模式与请求去重
Sources/TemperatureMonitor.swift M2 只读温度采集
Sources/ConnectionCoordinator.swift 设备身份、暂停和重试状态机
Sources/LoginItemController.swift 系统登录项状态与注册
Sources/Protocol.swift   控制帧、状态解析与 BLE 分片处理
Tests/main.swift         协议测试
Tests/reference.json     原序列化函数生成的协议测试向量
build.sh                 构建并签名本机应用
install.sh               固定签名构建并更新 /Applications 中的应用
scripts/setup-signing.py 首次创建并复用本机签名身份
test.sh                  运行协议、温控及连接状态机测试
```

## English

### Why this project exists

**I use this TVVT cooler with my MacBook Air.** I wanted to adjust cooling, fan settings and lighting, and read temperature and fan speed directly on my Mac, without reaching for my phone and opening a WeChat Mini Program each time.

My initial attempt to use the “TVVT散热器” Mini Program in WeChat for Mac produced a Bluetooth initialization error. The Mini Program displays the same “please turn on Bluetooth” message for different initialization failures, so that message does not identify the actual cause. Whether the current desktop WeChat exposes the BLE interfaces required by this Mini Program has not been fully established.

I therefore analyzed its BLE protocol and built an independent native macOS controller using **SwiftUI and CoreBluetooth**. Testing on real hardware confirmed that the Mac can connect to the cooler, read status, send cooling settings and receive a successful device acknowledgement.

### Latest version: 0.2.1

Adds menu bar temperature and two-mode cooling control, device persistence and automatic reconnect, login startup, and a stable local-signing and installation workflow. On an M2 Mac with T23SS, updating preserved Bluetooth permission and the app reconnected and received a control acknowledgement. Actual logout/login startup, sleep/wake recovery and the complete error-UI matrix remain unverified.

### Features

- Menu bar shows host temperature, connection state and selected mode; choose **Full speed** or **Automatic**.
- Full speed requests 36W and fan level 10; automatic mode selects 10W/4, 18W/7 or 36W/10 based on host temperature.
- Remember the selected peripheral and reconnect after launch, unexpected disconnect and wake. Explicit disconnect pauses reconnection until manual resume or app restart.
- Register a macOS login item and expose its enabled, approval-pending or failed state.
- Discover and connect to BLE peripherals matching known TVVT names or services.
- Display cold-side and hot-side temperature, fan RPM, core voltage and current mode.
- Configure manual, low-power, smart and strong-cooling modes, power, fan level and smart temperature settings.
- Configure lighting effects, RGB, brightness, effect speed, fan lighting and side lighting.
- View connection and control logs, with separate handling of GATT writes and device protocol acknowledgements.
- No WeChat, browser, Python, cloud service or account required at runtime. Initial local signing setup uses Python 3 and OpenSSL 3+.

### Compatibility and validation

| Device / environment | Status |
| --- | --- |
| MacBook Air, Apple Silicon, macOS 26 | Build, launch, Bluetooth discovery and connection tested |
| T23SS / M2023-S | Live status and successful cooling-command acknowledgement tested |
| T23DD / M2023-D | Service matching implemented; hardware not yet tested |
| M2 host temperature and two-mode control | Sensor readings, full-speed and automatic control acknowledgements tested |
| Stable-signing update and automatic reconnect | 0.2.0 → 0.2.1 update retained Bluetooth permission and reconnected |
| Login startup / sleep-wake recovery | Implemented; actual logout/login and sleep-wake recovery not yet verified |
| Lighting controls | Implemented; individual physical effects not yet verified |
| Other Macs / macOS versions | Not yet tested |

This is a personal project with no affiliation to TVVT. Compatibility is based on protocol analysis and the tests above, not a guarantee for every cooler model.

### Build and test

Requires macOS 14 or later and Xcode Command Line Tools. The scripts build for the local machine architecture using the installed SDK. The tested environment is Apple Silicon running macOS 26.

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

Initial local signing setup also requires Python 3 and OpenSSL 3+ (`openssl version` must report version 3 or later; the macOS-bundled LibreSSL is not suitable).

Without local signing setup, builds use ad hoc signatures and may prompt for Bluetooth again after rebuilding. For daily use, run `python3 scripts/setup-signing.py` once, approve the Keychain prompt locally, then use `./install.sh` for every update. Launch `/Applications/TVVT 散热器.app`.

Setup creates a reusable local certificate trusted only for code signing in the user trust domain. The private key is imported into Keychain as non-extractable with codesign access; no signing secrets are committed. A missing configured identity fails the build instead of silently switching to ad hoc. The first migration from ad hoc signing may require one more Bluetooth grant. Stable identity normally preserves permissions across updates; OS resets, certificate replacement or expiry can still require approval. This is local self-signing, not Apple Developer ID signing or notarization.

### Usage

1. Launch the app and allow Bluetooth access in macOS.
2. Power on the cooler. Disconnect any phone Mini Program or other client currently using it.
3. On first launch, click “搜索散热器” (Search), then “连接” (Connect) next to your `T23SS` or `T23DD`. The app remembers the device only after receiving valid status; future launches reconnect to that device rather than choosing another of the same model.
4. Click the menu bar fan icon and choose “全速前进” (Full speed) or “自动模式” (Automatic). Closing the control window keeps the app running; use “退出” (Quit) in the menu bar panel to exit.
5. Wait for valid temperature and fan readings. Edit settings and click the corresponding “应用” (Apply) button; editing alone does not send a command. Applying manual cooling settings exits automatic control.
6. “从设备读取设置” (Read settings from device) copies the latest received status into the editable fields. It does not send an active query.

The app permits 36W requests and leaves hardware limits to the cooler firmware. A request, protocol ACK and reported setting are separate from measured physical output. Editable temperatures: −20…30°C cold-side and 40…60°C hot-side.

Automatic mode uses the maximum valid M2 CPU/GPU sensor reading, sampled every two seconds: below 55°C requests 10W/fan 4, 55–below 70°C requests 18W/fan 7, and 70°C or above requests 36W/fan 10. Downshifts require a 5°C margin sustained for 20 seconds. Invalid or stale readings (over six seconds) pause automatic writes and retain the last device setting. Full speed operates independently of host temperature. Host sensor mapping currently supports M2-family chips only.

The app runs in the menu bar; its panel opens the existing control window. Applying manual cooling settings exits automatic control. Closing the window keeps the app running. Login startup uses SMAppService; check the panel for system approval or registration failures. Keep the app at a stable path. Actual logout/login startup requires separate verification; moving the app or replacing its signing certificate may affect approval. Installation migrates the login item to the fixed /Applications path.

The interface is currently in Chinese; this README documents it in both languages.

### Bluetooth troubleshooting

- **Permission denied:** allow the app under System Settings → Privacy & Security → Bluetooth.
- **No device found:** check cooler power and disconnect other clients.
- **`Peer removed pairing information`:** the Mac holds pairing information that no longer matches the device. Open the cooler’s details under System Settings → Bluetooth, select “Forget This Device”, then search and connect again. This recovery was verified with T23SS.
- **No device acknowledgement:** a missing protocol ACK after three seconds is reported as unconfirmed. A GATT write being accepted by the OS is a separate result.
- **Stale status:** after five seconds without fresh status, controls stop and the app reconnects. Unexpected disconnects retry with bounded backoff (2–60 seconds).

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
Sources/App.swift        Shared control model, window and BLE management
Sources/MenuBar.swift    Native menu bar, popover and window lifecycle
Sources/CoolingPolicy.swift Temperature policy and command gate
Sources/TemperatureMonitor.swift Read-only M2 sensor sampling
Sources/ConnectionCoordinator.swift Reconnect identity, pause and backoff
Sources/LoginItemController.swift System login item registration
Sources/Protocol.swift   Command framing, status parsing and BLE reassembly
Tests/main.swift         Protocol tests
Tests/reference.json     Reference vectors generated by the original serializer
build.sh                 Build and locally sign the app
install.sh               Build and update the app in /Applications
scripts/setup-signing.py Create and reuse a local signing identity
test.sh                  Run protocol, cooling policy and connection tests
```
