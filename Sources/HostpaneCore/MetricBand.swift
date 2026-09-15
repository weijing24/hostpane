import Foundation

public enum MetricBand: Equatable, Sendable {
    case low
    case medium
    case high

    /// SSH round-trip: LAN and nearby are low, trans-Pacific typically medium.
    public static func latency(_ seconds: Double) -> MetricBand {
        if seconds < 0.08 { return .low }
        if seconds < 0.20 { return .medium }
        return .high
    }

    /// CPU / memory / disk used ratio.
    public static func usage(_ ratio: Double) -> MetricBand {
        if ratio < 0.60 { return .low }
        if ratio < 0.85 { return .medium }
        return .high
    }
}
