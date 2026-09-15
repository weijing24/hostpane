import Foundation

/// Rolling median of short SSH round-trips. Ignores one-off stalls from
/// heavy remote commands or a slow first channel open.
public struct LatencyWindow: Equatable, Sendable {
    public private(set) var samples: [Double] = []
    public var capacity: Int

    public init(capacity: Int = 7) {
        self.capacity = max(1, capacity)
    }

    public var medianSeconds: Double? {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    @discardableResult
    public mutating func push(_ seconds: Double) -> Double? {
        guard seconds.isFinite, seconds > 0, seconds < 10 else { return medianSeconds }
        samples.append(seconds)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
        return medianSeconds
    }

    public mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

public func durationToSeconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
}
