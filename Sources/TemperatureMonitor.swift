import Foundation
import IOKit

struct SensorReading {
    let key: String
    let value: Double
}

final class SMCTemperatureReader {
    private var connection: io_connect_t = 0
    // These keys identify CPU and GPU die sensors on M2. Other chips need their own mapping.
    private let keys = ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tg0f", "Tg0j"]
    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        if IOServiceOpen(service, mach_task_self_, 0, &connection) != KERN_SUCCESS { connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    private func call(_ input: [UInt8]) -> [UInt8]? {
        guard connection != 0 else { return nil }
        var output = [UInt8](repeating: 0, count: 80)
        var count = 80
        let result = input.withUnsafeBytes { i in
            output.withUnsafeMutableBytes { o in
                IOConnectCallStructMethod(connection, 2, i.baseAddress, 80, o.baseAddress, &count)
            }
        }
        return result == KERN_SUCCESS && count == 80 && output[40] == 0 ? output : nil
    }
    private func read(_ key: String) -> Double? {
        var input = [UInt8](repeating: 0, count: 80)
        let keyValue = key.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        withUnsafeBytes(of: keyValue.littleEndian) { input.replaceSubrange(0..<4, with: $0) }
        input[42] = 9
        guard let info = call(input) else { return nil }
        let size = UInt32(info[28]) | UInt32(info[29]) << 8 | UInt32(info[30]) << 16 | UInt32(info[31]) << 24
        guard size == 4, Array(info[32..<36]) == [0x20, 0x74, 0x6c, 0x66] else { return nil }
        input.replaceSubrange(28..<40, with: info[28..<40]); input[42] = 5
        guard let data = call(input) else { return nil }
        let bits = UInt32(data[48]) | UInt32(data[49]) << 8 | UInt32(data[50]) << 16 | UInt32(data[51]) << 24
        let value = Double(Float(bitPattern: bits))
        return value.isFinite && value > 0 && value < 130 ? value : nil
    }
    static var supportedChip: Bool {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var name = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0) == 0 else { return false }
        return String(cString: name).hasPrefix("Apple M2")
    }
    func readings() -> [SensorReading] {
        guard Self.supportedChip else { return [] }
        return keys.compactMap { key in read(key).map { SensorReading(key: key, value: $0) } }
    }
}

final class TemperatureMonitor: ObservableObject {
    @Published private(set) var sample: TemperatureSample?
    @Published private(set) var readings: [SensorReading] = []
    @Published private(set) var source = "正在读取本机温度…"
    private let queue = DispatchQueue(label: "local.ouou.tvvt.temperature", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var reader: SMCTemperatureReader?
    init() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 2)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            if self.reader == nil { self.reader = SMCTemperatureReader() }
            let values = self.reader?.readings() ?? []
            let date = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.readings = values
                if let maximum = values.max(by: { $0.value < $1.value }) {
                    self.sample = TemperatureSample(value: maximum.value, date: date)
                    self.source = "芯片传感器最高值 · \(maximum.key)"
                } else {
                    self.sample = nil; self.source = "本机温度不可用"
                }
            }
            if values.isEmpty { self.reader = nil }
        }
        timer = t; t.resume()
    }
    deinit { timer?.cancel() }
}
