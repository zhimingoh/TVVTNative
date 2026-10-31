import Foundation

struct ConnectionCoordinator {
    var target: UUID?
    private(set) var paused = false
    private(set) var sleeping = false
    private(set) var attempts = 0
    private(set) var nextAttempt: Date?
    init(target: UUID? = nil) { self.target = target }
    var enabled: Bool { target != nil && !paused && !sleeping }
    mutating func remember(_ id: UUID) { target = id; attempts = 0; nextAttempt = nil }
    mutating func resume() { paused = false; attempts = 0; nextAttempt = nil }
    mutating func pause() { paused = true; nextAttempt = nil }
    mutating func sleep() { sleeping = true; nextAttempt = nil }
    mutating func wake() { sleeping = false; nextAttempt = nil }
    mutating func succeeded() { attempts = 0; nextAttempt = nil }
    mutating func failed(at now: Date) {
        guard enabled else { return }
        let delay = min(60.0, pow(2, Double(min(attempts, 6))) * 2)
        attempts += 1; nextAttempt = now.addingTimeInterval(delay)
    }
    func shouldAttempt(at now: Date, available: Bool, busy: Bool) -> Bool {
        enabled && available && !busy && (nextAttempt == nil || now >= nextAttempt!)
    }
    func shouldConnectDiscovered(_ id: UUID) -> Bool { enabled && target == id }
}
