import SwiftUI
import CoreBluetooth
import AppKit

struct Cooler: Identifiable {
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
    var id: UUID { peripheral.identifier }
}

final class BluetoothController: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BluetoothController()
    @Published var devices: [Cooler] = []
    @Published var message = "准备蓝牙…"
    @Published var connected = false
    @Published var scanning = false
    @Published var telemetry: TVVTProtocol.Status?
    @Published var logs: [String] = []
    @Published var pending = false
    @Published private(set) var needsBluetoothAuthorization = false
    @Published var mode = 2
    @Published var power = 1
    @Published var fan = 5
    @Published var cold = -10
    @Published var hot = 50
    @Published var lightMode = 1
    @Published var red = 255
    @Published var green = 0
    @Published var blue = 0
    @Published var fanLight = true
    @Published var sideLight = true
    @Published var brightness = 50
    @Published var speed = 50
    @Published private(set) var coolingMode: CoolingMode
    @Published private(set) var controlStatus = "等待设备连接"
    @Published private(set) var demand: CoolingDemand?
    @Published private(set) var temperatureText = "—℃"
    @Published private(set) var autoPaused = false
    let temperature = TemperatureMonitor()
    let login = LoginItemController()
    private let defaults: UserDefaults
    private var policy = CoolingPolicy()
    private var gate = CoolingCommandGate()
    private var connection: ConnectionCoordinator
    private var central: CBCentralManager!
    private var active: CBPeripheral?
    private var cancelling = false
    private var framer = TVVTProtocol.Framer()
    private var writer: CBCharacteristic?
    private var scanTimer: Timer?, connectTimer: Timer?, pendingTimer: Timer?, ticker: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastStatus: Date?
    private var pendingCommand: UInt8?
    private var quietUntil = Date.distantPast
    private var automaticCold = -10
    private var automaticHot = 50
    private var connectionName = "TVVT"
    private let logfile: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TVVTNative/session.log")
    var ready: Bool { connected && !cancelling && writer != nil && telemetry != nil && !pending && lastStatus.map { Date().timeIntervalSince($0) < 5 } == true }
    var isConnecting: Bool { active != nil && !connected }
    var menuTitle: String { "\(temperatureText) · \(connected ? coolingMode.title : autoPaused ? "已暂停" : "未连接")" }
    override convenience init() { self.init(defaults: .standard) }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        coolingMode = CoolingMode(rawValue: defaults.string(forKey: "coolingMode") ?? "") ?? .automatic
        connection = ConnectionCoordinator(target: defaults.string(forKey: "coolerIdentifier").flatMap(UUID.init(uuidString:)))
        super.init()
        try? FileManager.default.createDirectory(at: logfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: logfile)
        log("Controller started, restored mode=\(coolingMode.rawValue), rememberedDevice=\(connection.target != nil)")
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.connection.sleep(); self.temperatureInvalidated = true; self.cancelConnection(reason: "睡眠中")
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.connection.wake(); self.resumedAfter = Date(); self.policy.reset(); self.tick()
        })
    }
    func startBluetooth() {
        guard central == nil else { return }
        needsBluetoothAuthorization = CBManager.authorization == .notDetermined || CBManager.authorization == .denied
        if needsBluetoothAuthorization { message = "等待系统蓝牙授权，请允许 TVVT 散热器访问蓝牙" }
        central = CBCentralManager(delegate: self, queue: .main)
        log("Bluetooth initialized, authorization=\(CBManager.authorization.rawValue)")
    }
    private var temperatureInvalidated = false
    private var resumedAfter = Date.distantPast
    deinit {
        ticker?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)"
        logs.append(line); if logs.count > 150 { logs.removeFirst() }
        if let handle = try? FileHandle(forWritingTo: logfile) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data((line + "\n").utf8))
        }
    }
    func selectMode(_ selected: CoolingMode) {
        coolingMode = selected; defaults.set(selected.rawValue, forKey: "coolingMode")
        policy.reset(); gate.allowExplicitRetry(); tick()
    }
    private func tick() {
        let now = Date()
        autoPaused = connection.paused
        if temperatureInvalidated { resumedAfter = now; temperatureInvalidated = false }
        let sample = temperature.sample.flatMap { $0.date >= resumedAfter && $0.isFresh(at: now) ? $0 : nil }
        temperatureText = sample.map { String(format: "%.0f℃", $0.value) } ?? "—℃"
        if connection.sleeping { controlStatus = "睡眠中"; return }
        if connected, let date = lastStatus, now.timeIntervalSince(date) > 5 {
            telemetry = nil; cancelConnection(reason: "设备状态超时，等待重连")
        }
        if connection.shouldAttempt(at: now, available: central?.state == .poweredOn, busy: active != nil || scanning) {
            if let id = connection.target, let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
                beginConnect(peripheral, name: peripheral.name ?? "TVVT")
            } else { scan() }
        }
        switch coolingMode {
        case .fullSpeed: demand = .full
        case .automatic: demand = policy.demand(sample: sample, at: now)
        case .manual: demand = nil
        }
        guard connected else {
            controlStatus = connection.paused ? "已主动断开，自动重连暂停" : "等待设备连接"
            return
        }
        guard coolingMode != .manual else { controlStatus = "手动设置，自动调节已退出"; return }
        guard let demand else { controlStatus = "温度不可用，自动调节暂停 · 保留最后设置"; return }
        if pending { return }
        guard ready, now >= quietUntil else { return }
        if gate.canSend(demand, at: now) {
            if send(TVVTProtocol.control(mode: demand.mode, power: demand.power, fan: demand.fan, cold: automaticCold, hot: automaticHot)) {
                gate.sent(demand, at: now)
                controlStatus = "请求 \(demand.watts)W · 风扇 \(demand.fan)，等待设备确认"
            }
        } else if !gate.failed {
            controlStatus = "设备已确认请求（实际以设备报告为准）"
        }
    }
    func openBluetoothAuthorization() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        needsBluetoothAuthorization = CBManager.authorization == .notDetermined || CBManager.authorization == .denied
        log("CoreBluetooth state=\(central.state.rawValue) authorization=\(CBManager.authorization.rawValue)")
        switch central.state {
        case .poweredOn:
            message = "蓝牙可用"
            if connection.enabled { tick() } else if !connection.paused { scan() }
        case .poweredOff: abandonConnection(); message = "系统蓝牙已关闭"
        case .unauthorized: abandonConnection(); message = "请在系统设置 → 隐私与安全性 → 蓝牙中允许 TVVT 散热器"
        case .unsupported: abandonConnection(); message = "本机不支持 BLE"
        case .resetting: abandonConnection(); message = "蓝牙正在重置"
        default: message = needsBluetoothAuthorization ? "等待系统蓝牙授权，请在系统设置中允许访问" : "等待系统蓝牙…"
        }
    }
    func scan() {
        guard central?.state == .poweredOn, active == nil, !connection.sleeping else { return }
        central.stopScan(); scanTimer?.invalidate()
        devices = []; scanning = true; message = "正在搜索散热器（15 秒）…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }; self.stopScan(); self.connection.failed(at: Date())
            self.message = self.devices.isEmpty ? "未找到散热器，等待重试；请确认通电且未被手机占用" : "请选择散热器连接，或等待记住的设备"
        }
        log("BLE scan started")
    }
    func stopScan() { central?.stopScan(); scanning = false; scanTimer?.invalidate() }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard ["T23SS", "T23DD", "M2023-S", "M2023-D"].contains(name) || services.contains(where: { TVVTProtocol.services.contains($0.uuidString) }) else { return }
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) { devices[i].rssi = RSSI.intValue }
        else { devices.append(Cooler(peripheral: peripheral, name: name.isEmpty ? "TVVT" : name, rssi: RSSI.intValue)); log("Found \(name) RSSI=\(RSSI)") }
        if connection.shouldConnectDiscovered(peripheral.identifier), active == nil { beginConnect(peripheral, name: name) }
    }
    func connect(_ device: Cooler) { connection.resume(); beginConnect(device.peripheral, name: device.name) }
    func reconnect() {
        connection.resume(); autoPaused = false
        if connection.target == nil { scan() } else { tick() }
    }
    private func beginConnect(_ peripheral: CBPeripheral, name: String) {
        guard active == nil, central?.state == .poweredOn, !connection.sleeping else { return }
        stopScan(); active = peripheral; cancelling = false; active?.delegate = self; connectionName = name
        message = "正在连接 \(name)…"; log(message); central.connect(peripheral)
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, self.telemetry == nil else { return }
            self.cancelConnection(reason: "连接或状态读取超时，等待重试")
        }
    }
    func disconnect() { connection.pause(); autoPaused = true; stopScan(); cancelConnection(reason: "已主动断开，自动重连暂停") }
    private func cancelConnection(reason: String) {
        stopScan(); connectTimer?.invalidate(); resetControl(); connected = false
        if let active {
            cancelling = true
            central.cancelPeripheralConnection(active)
        }
        message = reason; log(reason)
    }
    private func resetControl() {
        pendingTimer?.invalidate(); pending = false; pendingCommand = nil
        writer = nil; telemetry = nil; lastStatus = nil; framer.reset(); gate.reset(); policy.reset()
    }
    private func abandonConnection() {
        stopScan(); connectTimer?.invalidate(); resetControl()
        active = nil; cancelling = false; connected = false
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == active, !cancelling else { return }
        connected = true; message = "已连接，正在读取服务…"; log(message)
        peripheral.discoverServices(TVVTProtocol.services.map { CBUUID(string: $0) })
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }
        abandonConnection(); connection.failed(at: Date()); message = "连接失败：\(error?.localizedDescription ?? "未知错误")"; log(message)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }
        abandonConnection(); connection.failed(at: Date())
        message = connection.paused ? "已主动断开，自动重连暂停" : "已断开，等待重连：\(error?.localizedDescription ?? "连接结束")"; log(message)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == active, !cancelling else { return }
        guard error == nil, let services = peripheral.services, !services.isEmpty else { cancelConnection(reason: "设备未提供已知 TVVT 服务"); return }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == active, !cancelling else { return }
        if let error { cancelConnection(reason: "读取特征失败：\(error.localizedDescription)"); return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid.uuidString == TVVTProtocol.writeUUID && (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)) { writer = characteristic }
            if characteristic.uuid.uuidString == TVVTProtocol.statusUUID {
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: characteristic) }
                if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
            }
        }
        message = writer == nil ? "未找到 TVVT 写入通道" : "等待设备状态…"
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active, !cancelling else { return }
        log("Notify \(characteristic.uuid): \(characteristic.isNotifying), \(error?.localizedDescription ?? "OK")")
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active, !cancelling else { return }
        if let error { log("Read failed: \(error.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        for frame in framer.append(data) {
            if let state = TVVTProtocol.Status(frame) {
                let first = lastStatus == nil
                telemetry = state; lastStatus = Date(); connectTimer?.invalidate(); connection.succeeded()
                connection.remember(peripheral.identifier); defaults.set(peripheral.identifier.uuidString, forKey: "coolerIdentifier")
                message = "已连接 · \(connectionName)"
                if first { automaticCold = max(-20, min(30, state.targetCold)); automaticHot = max(40, min(60, state.targetHot)); sync(state); log("Valid A0: cold=\(state.cold), hot=\(state.hot), rpm=\(state.rpm)") }
            } else if frame[0] == pendingCommand && frame.count == 4 && frame[1] == 1 {
                finishCommand(success: frame[2] == 0x10, text: frame[2] == 0x10 ? "设备已确认请求（实际以设备报告为准）" : "设备拒绝请求（\(frame[2])）")
            }
        }
    }
    private func finishCommand(success: Bool, text: String) {
        pendingTimer?.invalidate(); pending = false; pendingCommand = nil
        gate.completed(success: success); message = text; controlStatus = text; log(text)
        quietUntil = Date().addingTimeInterval(success ? 0.5 : 2)
    }
    func sync(_ s: TVVTProtocol.Status) {
        mode = s.mode; power = s.power; fan = s.fan; cold = s.targetCold; hot = s.targetHot
        lightMode = s.lightMode; red = s.red; green = s.green; blue = s.blue
        fanLight = s.fanLight != 0; sideLight = s.sideLight != 0; brightness = s.brightness; speed = s.speed
    }
    func refreshSettings() { if let telemetry { sync(telemetry) } }
    @discardableResult private func send(_ data: Data) -> Bool {
        guard ready, Date() >= quietUntil, let active, let writer else { message = "请等待设备就绪或上一条请求完成"; return false }
        let type: CBCharacteristicWriteType = writer.properties.contains(.write) ? .withResponse : .withoutResponse
        guard type != .withoutResponse || active.canSendWriteWithoutResponse else { message = "蓝牙通道忙，请稍后重试"; return false }
        guard data.count <= active.maximumWriteValueLength(for: type) else { message = "指令超出蓝牙写入长度"; return false }
        pending = true; pendingCommand = data.first; message = "正在发送，等待设备确认…"
        log("TX " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        active.writeValue(data, for: writer, type: type)
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.finishCommand(success: false, text: "未收到设备确认；请求结果未知")
        }
        return true
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active, !cancelling, pending else { return }
        if let error { finishCommand(success: false, text: "写入失败：\(error.localizedDescription)") }
        else { log("GATT write acknowledged; waiting for device protocol ACK") }
    }
    func applyControl() {
        guard ready, Date() >= quietUntil else { message = "请等待设备就绪或上一条请求完成"; return }
        guard (1...4).contains(mode), (1...3).contains(power), (0...10).contains(fan), (-20...30).contains(cold), (40...60).contains(hot) else { message = "设置超出支持范围"; return }
        coolingMode = .manual; defaults.set(coolingMode.rawValue, forKey: "coolingMode"); policy.reset(); gate.reset()
        send(TVVTProtocol.control(mode: mode, power: power, fan: fan, cold: cold, hot: hot))
    }
    func applyLight() { send(TVVTProtocol.packet(0xB1, [UInt8(lightMode), UInt8(red), UInt8(green), UInt8(blue), UInt8(telemetry?.lightParameter ?? 0)])) }
    func applyLightOptions() { send(TVVTProtocol.packet(0xB8, [fanLight ? 1 : 0, sideLight ? 1 : 0, UInt8(brightness), UInt8(speed)])) }
}

struct ContentView: View {
    @ObservedObject var ble: BluetoothController
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("TVVT 散热器").font(.largeTitle.bold()); Spacer(); Button("菜单栏面板") { AppDelegate.current?.toggleMenu() }; Text(ble.coolingMode.title).foregroundStyle(.secondary) }
            HStack { Circle().fill(ble.connected ? Color.green : Color.orange).frame(width: 9, height: 9); Text(ble.message); Spacer()
                if ble.connected { Button("断开", action: ble.disconnect) }
                else { Button("自动连接", action: ble.reconnect); Button(ble.scanning ? "重新搜索" : "搜索散热器", action: ble.scan) }
            }
            HStack { Text("本机 \(ble.temperatureText)"); Text(ble.controlStatus).font(.callout).foregroundStyle(.secondary) }
            if !ble.connected {
                List(ble.devices) { d in HStack { Text(d.name); Text("\(d.rssi) dBm").foregroundStyle(.secondary); Spacer(); Button("连接") { ble.connect(d) } } }.frame(height: 100)
                Text("散热器需通电；若手机已连接，请先在手机小程序里断开。首次运行请允许蓝牙访问。").font(.callout).foregroundStyle(.secondary)
            }
            if let s = ble.telemetry {
                HStack(spacing: 25) {
                    metric("冷面", String(format: "%.1f ℃", s.cold)); metric("热面", String(format: "%.1f ℃", s.hot)); metric("风扇", "\(s.rpm) RPM"); metric("核芯电压", String(format: "%.1f V", s.volts1)); metric("当前模式", [1:"手动",2:"低功耗",3:"智能",4:"强冷"][s.mode] ?? "\(s.mode)")
                }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
            Picker("控制面板", selection: $tab) { Text("制冷与风扇").tag(0); Text("灯光").tag(1); Text("连接日志").tag(2) }.pickerStyle(.segmented)
            Group {
                if tab == 0 { Form {
                    Picker("运行模式", selection: $ble.mode) { Text("手动").tag(1); Text("低功耗").tag(2); Text("智能").tag(3); Text("强冷").tag(4) }
                    Picker("制冷功率", selection: $ble.power) { Text("10W").tag(1); Text("18W").tag(2); Text("36W").tag(3) }
                    Stepper("风扇档位：\(ble.fan)", value: $ble.fan, in: 0...10)
                    Stepper("智能冷面目标：\(ble.cold) ℃", value: $ble.cold, in: -20...30)
                    Stepper("智能热面上限：\(ble.hot) ℃", value: $ble.hot, in: 40...60)
                    HStack { Button("应用制冷设置", action: ble.applyControl); Button("从设备读取设置", action: ble.refreshSettings) }
                    Text("应用手动设置会退出自动调节。36W 请求由设备自行限制；风扇档位 0 会关闭风扇。").font(.caption).foregroundStyle(.secondary)
                }.padding().disabled(!ble.ready) }
                else if tab == 1 { Form {
                    Picker("灯效", selection: $ble.lightMode) { ForEach(Array(["幻彩","流光","流水","积木","跳动","呼吸","固定"].enumerated()), id: \.offset) { i, s in Text(s).tag(i + 1) } }
                    Stepper("红：\(ble.red)", value: $ble.red, in: 0...255); Stepper("绿：\(ble.green)", value: $ble.green, in: 0...255); Stepper("蓝：\(ble.blue)", value: $ble.blue, in: 0...255)
                    Button("应用灯效与颜色", action: ble.applyLight)
                    Divider(); Toggle("风扇灯", isOn: $ble.fanLight); Toggle("侧灯", isOn: $ble.sideLight)
                    Stepper("亮度：\(ble.brightness)%", value: $ble.brightness, in: 10...100, step: 10)
                    Stepper("灯效速度：\(ble.speed)%", value: $ble.speed, in: 10...100, step: 10)
                    Button("应用灯光开关与亮度", action: ble.applyLightOptions)
                }.padding().disabled(!ble.ready) }
                else { ScrollView { Text(ble.logs.joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding() } }
            }.frame(minHeight: 330)
        }.padding(22).frame(minWidth: 690, minHeight: 540)
    }
    func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.monospacedDigit()) } }
}
