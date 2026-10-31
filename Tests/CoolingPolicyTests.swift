import Foundation

@main struct CoolingPolicyTests {
    static func main() {
        let origin = Date(timeIntervalSince1970: 1000)
        func sample(_ value: Double, _ seconds: Double) -> TemperatureSample {
            TemperatureSample(value: value, date: origin.addingTimeInterval(seconds))
        }
        var policy = CoolingPolicy()
        func evaluate(_ value: Double, _ seconds: Double) -> CoolingDemand? {
            policy.demand(sample: sample(value, seconds), at: origin.addingTimeInterval(seconds))
        }
        precondition(evaluate(50, 0) == CoolingDemand.levels[0])
        precondition(evaluate(55, 1) == CoolingDemand.levels[1])
        precondition(evaluate(70, 2) == CoolingDemand.levels[2])
        precondition(evaluate(64, 3) == CoolingDemand.levels[2])
        precondition(evaluate(65, 10) == CoolingDemand.levels[2])
        precondition(evaluate(64, 11) == CoolingDemand.levels[2])
        precondition(evaluate(64, 30) == CoolingDemand.levels[2])
        precondition(evaluate(64, 31) == CoolingDemand.levels[1])
        precondition(evaluate(49, 32) == CoolingDemand.levels[1])
        precondition(evaluate(49, 52) == CoolingDemand.levels[0])
        precondition(evaluate(75, 53) == CoolingDemand.levels[2])
        precondition(policy.demand(sample: sample(20, 53), at: origin.addingTimeInterval(60)) == nil)
        precondition(policy.demand(sample: sample(.nan, 61), at: origin.addingTimeInterval(61)) == nil)
        precondition(policy.demand(sample: sample(140, 61), at: origin.addingTimeInterval(61)) == nil)
        precondition(policy.demand(sample: sample(20, 70), at: origin.addingTimeInterval(61)) == nil)
        precondition(evaluate(40, 61) == CoolingDemand.levels[2])
        precondition(evaluate(40, 80) == CoolingDemand.levels[2])
        precondition(evaluate(40, 81) == CoolingDemand.levels[0])
        policy.reset()
        precondition(evaluate(60, 82) == CoolingDemand.levels[1])
        var gate = CoolingCommandGate()
        precondition(gate.canSend(.full, at: origin))
        gate.sent(.full, at: origin)
        precondition(!gate.canSend(CoolingDemand.levels[0], at: origin))
        gate.completed(success: true)
        precondition(!gate.canSend(.full, at: origin))
        precondition(gate.canSend(CoolingDemand.levels[0], at: origin))
        gate.sent(CoolingDemand.levels[0], at: origin)
        gate.completed(success: false)
        precondition(!gate.canSend(.full, at: origin.addingTimeInterval(14)))
        precondition(gate.canSend(.full, at: origin.addingTimeInterval(15)))
        gate.allowExplicitRetry()
        precondition(gate.canSend(.full, at: origin))
        gate.reset()
        precondition(gate.canSend(.full, at: origin))
        let full = Array(TVVTProtocol.control(mode: 4, power: 3, fan: 10, cold: -10, hot: 50))
        precondition(full[2] == 4 && full[3] == 3 && full[4] == 10 && TVVTProtocol.valid(full))
        print("PASS: temperature boundaries, rise/fall hysteresis, sustained cooldown, invalid/stale/future samples, command serialization/deduplication/failure retry, full-speed frame")
    }
}
