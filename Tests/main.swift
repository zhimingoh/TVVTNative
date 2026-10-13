import Foundation
struct Vector: Decodable { let mode: Int; let cold: Int; let bytes: [UInt8] }
let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: URL(fileURLWithPath: "Tests/reference.json")))
for v in vectors {
    precondition(Array(TVVTProtocol.control(mode: v.mode, power: 1, fan: 5, cold: v.cold, hot: 50)) == v.bytes)
}
// Independent status fixture: negative cold, positive hot, 12V supply, 2500RPM.
var payload = [UInt8](repeating: 0, count: 34)
payload[0] = 0x80; payload[1] = 123; payload[2] = 1; payload[3] = 194
payload[6] = 0x2E; payload[7] = 0xE0; payload[10] = 9; payload[11] = 196
payload[12] = 0x37; payload[24] = 12; payload[25] = 2; payload[26] = 5
payload[27] = 0x8A; payload[28] = 50; payload[29] = 1
let frame = TVVTProtocol.packet(0xA0, payload)
let state = TVVTProtocol.Status(Array(frame))!
precondition(state.cold == -12.3 && state.hot == 45 && state.volts1 == 12 && state.rpm == 2500)
precondition(state.mode == 3 && state.lightMode == 7 && state.targetCold == -10 && state.supply == 12)
var bad = Array(frame); bad[5] ^= 1
precondition(TVVTProtocol.Status(bad) == nil)
precondition(TVVTProtocol.Status([0xA0,0,0xA0]) == nil)
var framer = TVVTProtocol.Framer()
precondition(framer.append(frame.prefix(20)).isEmpty)
precondition(framer.append(frame.dropFirst(20)) == [Array(frame)])
let ack = TVVTProtocol.packet(0xB0, [0x10])
precondition(framer.append(frame + ack) == [Array(frame),Array(ack)])
precondition(framer.append(Data([0,1,2]) + ack) == [Array(ack)])
print("PASS: \(vectors.count) original-JS control vectors; telemetry fields; checksum rejection; short frames; fragmented/coalesced BLE packets")
