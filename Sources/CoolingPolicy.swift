import Foundation

enum CoolingMode: String, CaseIterable {
    case automatic, fullSpeed, manual
    var title: String {
        switch self {
        case .automatic: return "自动模式"
        case .fullSpeed: return "全速前进"
        case .manual: return "手动设置"
        }
    }
}

struct CoolingDemand: Equatable {
    let mode: Int
    let power: Int
    let fan: Int
    static let full = CoolingDemand(mode: 4, power: 3, fan: 10)
    static let levels = [CoolingDemand(mode: 1, power: 1, fan: 4),
                         CoolingDemand(mode: 1, power: 2, fan: 7),
                         CoolingDemand(mode: 1, power: 3, fan: 10)]
    var watts: Int { [10, 18, 36][power - 1] }
}

struct TemperatureSample {
    let value: Double
    let date: Date
    func isFresh(at now: Date) -> Bool {
        value.isFinite && value > 0 && value < 130 && (0...6).contains(now.timeIntervalSince(date))
    }
}

struct CoolingPolicy {
    private(set) var level: Int?
    private var lowerSince: Date?
    mutating func reset() { level = nil; lowerSince = nil }
    mutating func demand(sample: TemperatureSample?, at now: Date) -> CoolingDemand? {
        guard let sample, sample.isFresh(at: now) else { lowerSince = nil; return nil }
        let value = sample.value
        let requested = value >= 70 ? 2 : value >= 55 ? 1 : 0
        guard let current = level else { level = requested; return CoolingDemand.levels[requested] }
        if requested > current {
            level = requested; lowerSince = nil
        } else if requested < current && value < (current == 2 ? 65 : 50) {
            if let since = lowerSince, now.timeIntervalSince(since) >= 20 {
                level = requested; lowerSince = nil
            } else if lowerSince == nil { lowerSince = now }
        } else { lowerSince = nil }
        return CoolingDemand.levels[level!]
    }
}

struct CoolingCommandGate {
    private(set) var lastAcknowledged: CoolingDemand?
    private(set) var inFlight: CoolingDemand?
    private(set) var lastAttempt: Date?
    private(set) var failed = false
    mutating func reset() { self = CoolingCommandGate() }
    mutating func allowExplicitRetry() {
        if failed { lastAcknowledged = nil }
        failed = false; lastAttempt = nil
    }
    func canSend(_ demand: CoolingDemand, at now: Date) -> Bool {
        guard inFlight == nil else { return false }
        if failed, let lastAttempt, now.timeIntervalSince(lastAttempt) < 15 { return false }
        return failed || demand != lastAcknowledged
    }
    mutating func sent(_ demand: CoolingDemand, at now: Date) {
        inFlight = demand; lastAttempt = now
    }
    mutating func completed(success: Bool) {
        guard let sent = inFlight else { return }
        if success { lastAcknowledged = sent }
        failed = !success; inFlight = nil
    }
}
