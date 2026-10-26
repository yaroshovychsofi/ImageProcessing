import Foundation

/// A softmax never returns exactly 1, so a displayed "100%" is always a rounding artefact of
/// something like 99.97% — and it reads as a promise the model cannot make. Percentages are
/// therefore rounded down rather than to nearest.
nonisolated enum ConfidenceText {
    static func percent(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        let tenths = (clamped * 1000).rounded(.down) / 10
        return "\(tenths.formatted(.number.precision(.fractionLength(1))))%"
    }
}
