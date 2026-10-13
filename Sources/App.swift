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
    @Published var devices: [Cooler] = []
    @Published var message = "准备蓝牙…"
    @Published var connected = false
    @Published var scanning = false
    @Published var telemetry: TVVTProtocol.Status?
    @Published var logs: [String] = []
    @Published var pending = false
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
    @Published var waterAccessory = false
    private var central: CBCentralManager!
    private var active: CBPeripheral?
    private var writer: CBCharacteristic?
    private var framer = TVVTProtocol.Framer()
    private var scanTimer: Timer?, connectTimer: Timer?, pendingTimer: Timer?, freshnessTimer: Timer?
    private var lastStatus: Date?
    private var pendingCommand: UInt8?
    private let logfile: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TVVTNative/session.log")
    var ready: Bool { connected && writer != nil && telemetry != nil && !pending && lastStatus.map { Date().timeIntervalSince($0) < 5 } == true }
    override init() {
        super.init()
        try? FileManager.default.createDirectory(at: logfile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: logfile)
        central = CBCentralManager(delegate: self, queue: .main)
        freshnessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.connected, let date = self.lastStatus, Date().timeIntervalSince(date) > 5 else { return }
            self.telemetry = nil
            self.message = "状态数据已超时，请断开后重新连接"
        }
    }
    func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)"
        logs.append(line); if logs.count > 150 { logs.removeFirst() }
        if let handle = try? FileHandle(forWritingTo: logfile) {
            defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data((line + "\n").utf8))
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("CoreBluetooth state=\(central.state.rawValue) authorization=\(CBManager.authorization.rawValue)")
        switch central.state {
        case .poweredOn: message = "蓝牙可用"; scan()
        case .poweredOff: message = "系统蓝牙已关闭"; clear()
        case .unauthorized: message = "请在系统设置 → 隐私与安全性 → 蓝牙中允许 TVVT 散热器"; clear()
        case .unsupported: message = "本机不支持 BLE"; clear()
        case .resetting: message = "蓝牙正在重置"; clear()
        default: message = "等待系统蓝牙…"
        }
    }
    func scan() {
        guard central.state == .poweredOn, active == nil else { return }
        devices = []; scanning = true; message = "正在搜索散热器（15 秒）…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self else { return }; self.stopScan()
            self.message = self.devices.isEmpty ? "未找到散热器，请确认它已通电，并断开手机上的蓝牙连接" : "请选择散热器连接"
        }
        log("BLE scan started (only matching TVVT devices shown)")
    }
    func stopScan() { central.stopScan(); scanning = false; scanTimer?.invalidate() }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard ["T23SS", "T23DD", "M2023-S", "M2023-D"].contains(name) || services.contains(where: { TVVTProtocol.services.contains($0.uuidString) }) else { return }
        if let i = devices.firstIndex(where: { $0.id == peripheral.identifier }) { devices[i].rssi = RSSI.intValue }
        else { devices.append(Cooler(peripheral: peripheral, name: name.isEmpty ? "TVVT" : name, rssi: RSSI.intValue)); log("Found \(name) RSSI=\(RSSI)") }
    }
    func connect(_ device: Cooler) {
        guard active == nil else { return }
        stopScan(); active = device.peripheral; active?.delegate = self
        message = "正在连接 \(device.name)…"; log(message); central.connect(device.peripheral)
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            guard let self, self.telemetry == nil else { return }
            self.log("Connection/telemetry timeout"); self.disconnect(); self.message = "连接超时，设备可能已被手机占用"
        }
    }
    func disconnect() { if let active { central.cancelPeripheralConnection(active) }; clear(); message = "已断开" }
    private func clear() {
        connectTimer?.invalidate(); pendingTimer?.invalidate(); scanTimer?.invalidate()
        active = nil; writer = nil; connected = false; scanning = false; telemetry = nil; lastStatus = nil
        pending = false; pendingCommand = nil; framer.reset()
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral == active else { return }; connected = true
        message = "已连接，正在读取服务…"; log(message)
        peripheral.discoverServices(TVVTProtocol.services.map { CBUUID(string: $0) })
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }; clear(); message = "连接失败：\(error?.localizedDescription ?? "未知错误")"; log(message)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral == active else { return }; clear(); message = "已断开：\(error?.localizedDescription ?? "连接结束")"; log(message)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral == active else { return }
        guard error == nil, let services = peripheral.services, !services.isEmpty else { log("TVVT service missing: \(String(describing: error))"); disconnect(); message = "设备未提供已知 TVVT 服务"; return }
        for service in services { log("Service \(service.uuid)"); peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral == active else { return }
        if let error { message = error.localizedDescription; log(message); return }
        for characteristic in service.characteristics ?? [] {
            log("Characteristic \(characteristic.uuid) properties=\(characteristic.properties.rawValue)")
            if characteristic.uuid.uuidString == TVVTProtocol.writeUUID && (characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse)) { writer = characteristic }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) { peripheral.setNotifyValue(true, for: characteristic) }
            if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
        }
        message = writer == nil ? "未找到 TVVT 写入通道" : "等待设备状态…"
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active else { return }; log("Notify \(characteristic.uuid): \(characteristic.isNotifying), \(error?.localizedDescription ?? "OK")")
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active else { return }
        if let error { log("Read failed: \(error.localizedDescription)"); return }
        guard let data = characteristic.value else { return }
        for frame in framer.append(data) {
            if let state = TVVTProtocol.Status(frame) {
                let first = telemetry == nil
                telemetry = state; lastStatus = Date(); connectTimer?.invalidate(); message = "已连接 · \(state.model == 2 ? "M2023-D" : "M2023-S")"
                if first { sync(state); log("Valid A0 telemetry: cold=\(state.cold), hot=\(state.hot), rpm=\(state.rpm)") }
            } else if frame[0] == pendingCommand && frame.count >= 4 {
                log("Device ACK " + frame.map { String(format: "%02X", $0) }.joined(separator: " "))
                pendingTimer?.invalidate(); pending = false; pendingCommand = nil
                message = frame[2] == 0x10 ? "设备已确认设置" : "设备拒绝设置（\(frame[2])）"
            }
        }
    }
    func sync(_ s: TVVTProtocol.Status) {
        mode = s.mode; power = s.power; fan = s.fan; cold = s.targetCold; hot = s.targetHot
        lightMode = s.lightMode; red = s.red; green = s.green; blue = s.blue
        fanLight = s.fanLight != 0; sideLight = s.sideLight != 0; brightness = s.brightness; speed = s.speed
    }
    func refreshSettings() { if let telemetry { sync(telemetry) } }
    func send(_ data: Data) {
        guard ready, let active, let writer else { message = "请先连接并等待有效状态"; return }
        let type: CBCharacteristicWriteType = writer.properties.contains(.write) ? .withResponse : .withoutResponse
        guard type != .withoutResponse || active.canSendWriteWithoutResponse else { message = "蓝牙通道忙，请稍后重试"; return }
        guard data.count <= active.maximumWriteValueLength(for: type) else { message = "指令超出蓝牙写入长度"; return }
        pending = true; pendingCommand = data.first; message = "正在发送，等待设备确认…"
        log("TX " + data.map { String(format: "%02X", $0) }.joined(separator: " "))
        active.writeValue(data, for: writer, type: type)
        pendingTimer?.invalidate()
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self else { return }; self.pending = false; self.pendingCommand = nil; self.message = "未收到设备确认，请检查实时状态"; self.log(self.message)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral == active else { return }
        if let error { pendingTimer?.invalidate(); pending = false; pendingCommand = nil; message = "写入失败：\(error.localizedDescription)"; log(message) }
        else { log("GATT write acknowledged; waiting for device protocol ACK") }
    }
    func applyControl() {
        guard (1...4).contains(mode), (1...3).contains(power), (0...10).contains(fan), (-20...30).contains(cold), (40...60).contains(hot) else { message = "设置超出支持范围"; return }
        guard power != 3 || (telemetry?.supply == 12 && waterAccessory) else { message = "36W 需要 12V 供电检测及水冷增强组件"; return }
        send(TVVTProtocol.control(mode: mode, power: power, fan: fan, cold: cold, hot: hot))
    }
    func applyLight() { send(TVVTProtocol.packet(0xB1, [UInt8(lightMode), UInt8(red), UInt8(green), UInt8(blue), UInt8(telemetry?.lightParameter ?? 0)])) }
    func applyLightOptions() { send(TVVTProtocol.packet(0xB8, [fanLight ? 1 : 0, sideLight ? 1 : 0, UInt8(brightness), UInt8(speed)])) }
}

struct ContentView: View {
    @StateObject var ble = BluetoothController()
    @State private var tab = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("TVVT 散热器").font(.largeTitle.bold()); Spacer(); Text("macOS 蓝牙直连").foregroundStyle(.secondary) }
            HStack { Circle().fill(ble.connected ? Color.green : Color.orange).frame(width: 9, height: 9); Text(ble.message); Spacer()
                if ble.connected { Button("断开", action: ble.disconnect) }
                else { Button(ble.scanning ? "重新搜索" : "搜索散热器", action: ble.scan) }
            }
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
                    Picker("制冷功率", selection: $ble.power) { Text("10W").tag(1); Text("18W").tag(2); Text("36W（水冷）").tag(3) }
                    Stepper("风扇档位：\(ble.fan)", value: $ble.fan, in: 0...10)
                    Stepper("智能冷面目标：\(ble.cold) ℃", value: $ble.cold, in: -20...30)
                    Stepper("智能热面上限：\(ble.hot) ℃", value: $ble.hot, in: 40...60)
                    Toggle("已安装水冷增强组件（36W）", isOn: $ble.waterAccessory)
                    HStack { Button("应用制冷设置", action: ble.applyControl); Button("从设备读取设置", action: ble.refreshSettings) }
                    Text("设置仅在点击应用后发送。风扇档位 0 会关闭风扇；强冷模式对应原小程序的强冷控制。").font(.caption).foregroundStyle(.secondary)
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

@main struct TVVTApp: App {
    var body: some Scene { WindowGroup { ContentView() }.windowStyle(.titleBar).defaultSize(width: 750, height: 640) }
}
