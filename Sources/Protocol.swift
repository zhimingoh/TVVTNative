import Foundation

enum TVVTProtocol {
    static let services = ["00010203-0405-0607-0809-0A0B0C0D1910", "00010203-0405-0607-0809-0A0B0C0D1909"]
    static let statusUUID = "00010203-0405-0607-0809-0A0B0C0D2B10"
    static let writeUUID = "00010203-0405-0607-0809-0A0B0C0D2B11"
    static func packet(_ command: UInt8, _ payload: [UInt8]) -> Data {
        let bytes = [command, UInt8(payload.count)] + payload
        return Data(bytes + [bytes.reduce(0, ^)])
    }
    static func control(mode: Int, power: Int, fan: Int, cold: Int, hot: Int) -> Data {
        packet(0xB0, [UInt8(mode), UInt8(power), UInt8(fan), UInt8(abs(cold)) | (cold < 0 ? 0x80 : 0), UInt8(hot)])
    }
    static func valid(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 3 && bytes.count == Int(bytes[1]) + 3 && bytes.dropLast().reduce(0, ^) == bytes.last!
    }
    struct Status {
        let cold: Double, hot: Double, third: Double, volts1: Double, volts2: Double
        let rpm: Int, mode: Int, lightMode: Int, red: Int, green: Int, blue: Int, lightParameter: Int
        let fanLight: Int, sideLight: Int, brightness: Int, speed: Int
        let power: Int, fan: Int, targetCold: Int, targetHot: Int, supply: Int, model: Int, water: Int
        init?(_ b: [UInt8]) {
            guard TVVTProtocol.valid(b), b[0] == 0xA0, b.count >= 37 else { return nil }
            func word(_ i: Int) -> Int { Int(b[i]) * 256 + Int(b[i + 1]) }
            func temperature(_ i: Int) -> Double {
                Double(Int(b[i] & 0x7F) * 256 + Int(b[i + 1])) / 10 * (b[i] & 0x80 == 0 ? 1 : -1)
            }
            cold = temperature(2); hot = temperature(4); third = temperature(6)
            volts1 = Double(word(8)) / 1000; volts2 = Double(word(10)) / 1000; rpm = word(12)
            mode = Int(b[14] >> 4); lightMode = Int(b[14] & 0x0F)
            red = Int(b[15]); green = Int(b[16]); blue = Int(b[17]); lightParameter = Int(b[18])
            fanLight = Int(b[19]); sideLight = Int(b[20]); brightness = Int(b[21]); speed = Int(b[34])
            supply = Int(b[26]); power = Int(b[27]); fan = Int(b[28])
            targetCold = Int(b[29] & 0x7F) * (b[29] & 0x80 == 0 ? 1 : -1)
            targetHot = Int(b[30]); model = Int(b[31]); water = Int(b[35])
        }
    }
    struct Framer {
        private var buffer: [UInt8] = []
        mutating func reset() { buffer.removeAll() }
        mutating func append(_ data: Data) -> [[UInt8]] {
            buffer += data
            var frames: [[UInt8]] = []
            while buffer.count >= 3 {
                guard buffer[0] >= 0xA0, buffer[1] <= 37 else { buffer.removeFirst(); continue }
                let size = Int(buffer[1]) + 3
                guard buffer.count >= size else { break }
                let frame = Array(buffer.prefix(size))
                if TVVTProtocol.valid(frame) { frames.append(frame); buffer.removeFirst(size) }
                else { buffer.removeFirst() }
            }
            return frames
        }
    }
}
