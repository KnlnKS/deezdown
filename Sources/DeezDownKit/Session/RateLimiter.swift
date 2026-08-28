import Foundation

actor RateLimiter {
    private let limit: Int
    private let window: Duration
    private var recent: [ContinuousClock.Instant] = []

    init(limit: Int, window: Duration) {
        self.limit = limit
        self.window = window
    }

    func acquire() async throws {
        while true {
            let now = ContinuousClock.now
            recent.removeAll { now - $0 >= window }
            if recent.count < limit {
                recent.append(now)
                return
            }
            guard let oldest = recent.first else { continue }
            try await Task.sleep(for: window - (now - oldest))
        }
    }
}
