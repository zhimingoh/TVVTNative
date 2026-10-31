import Foundation

@main struct ConnectionCoordinatorTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        let a = UUID(), b = UUID()
        var state = ConnectionCoordinator()
        precondition(!state.shouldAttempt(at: now, available: true, busy: false))
        state.remember(a)
        precondition(state.shouldAttempt(at: now, available: true, busy: false))
        precondition(!state.shouldAttempt(at: now, available: true, busy: true))
        precondition(!state.shouldAttempt(at: now, available: false, busy: false))
        precondition(state.shouldConnectDiscovered(a) && !state.shouldConnectDiscovered(b))
        state.failed(at: now)
        precondition(!state.shouldAttempt(at: now.addingTimeInterval(1), available: true, busy: false))
        precondition(state.shouldAttempt(at: now.addingTimeInterval(2), available: true, busy: false))
        state.failed(at: now)
        precondition(state.nextAttempt == now.addingTimeInterval(4))
        for _ in 0..<100 { state.failed(at: now) }
        precondition(state.nextAttempt == now.addingTimeInterval(60))
        state.pause(); state.sleep(); state.wake()
        precondition(state.paused && !state.shouldAttempt(at: now, available: true, busy: false))
        precondition(!state.shouldConnectDiscovered(a))
        state.resume(); state.sleep()
        precondition(!state.shouldAttempt(at: now, available: true, busy: false))
        state.wake()
        precondition(state.shouldAttempt(at: now, available: true, busy: false))
        state.succeeded()
        precondition(state.attempts == 0)
        let restored = ConnectionCoordinator(target: a)
        precondition(restored.shouldAttempt(at: now, available: true, busy: false))
        print("PASS: first selection, remembered identity, nearby device exclusion, one-attempt gate, bounded backoff, manual pause across sleep/wake, explicit resume and restart")
    }
}
