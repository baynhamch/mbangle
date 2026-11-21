import Foundation

/// Decides when fresh readings justify one alignment confirmation. Performing
/// the haptic and deciding whether feedback is visible belong to the caller.
@MainActor
struct AlignmentHapticGate {
    static let minimumPulseInterval: TimeInterval = 0.75
    private var candidateSince: TimeInterval?
    private var lastUpdateAt: TimeInterval?
    private var lastPulseAt: TimeInterval?
    private var latched = false
    private var lastTarget: Double?
    private var lastTolerance: Double?

    /// Clear the alignment session without allowing rapid reveals to bypass
    /// the minimum interval between pulses.
    mutating func reset() {
        candidateSince = nil
        lastUpdateAt = nil
        latched = false
        lastTarget = nil
        lastTolerance = nil
    }

    /// Raw input uses the sensor convention; target and displayedAngle use
    /// the app's complementary angle. Both must agree before confirmation.
    mutating func update(
        displayedAngle: Double,
        rawAngle: Double,
        target: Double,
        tolerance: Double,
        at time: TimeInterval
    ) -> Bool {
        guard displayedAngle.isFinite, (0...180).contains(displayedAngle),
              rawAngle.isFinite, (0...180).contains(rawAngle),
              target.isFinite, (0...180).contains(target),
              tolerance.isFinite, tolerance >= 0,
              time.isFinite, time >= 0 else {
            candidateSince = nil
            return false
        }
        if let previous = lastUpdateAt, time < previous {
            candidateSince = nil
            lastUpdateAt = time
            return false
        }
        lastUpdateAt = time

        if lastTarget != target || lastTolerance != tolerance {
            candidateSince = nil
            latched = false
            lastTarget = target
            lastTolerance = tolerance
        }

        let distance = max(abs(displayedAngle - target), abs((180 - rawAngle) - target))
        // A separate exit margin prevents small boundary fluctuations from
        // repeatedly rearming the feedback after one successful alignment.
        if distance > tolerance + 0.5 {
            candidateSince = nil
            latched = false
            return false
        }
        guard distance <= tolerance, !latched else {
            candidateSince = nil
            return false
        }
        guard let candidateSince else {
            self.candidateSince = time
            return false
        }
        guard time - candidateSince >= 0.15,
              lastPulseAt.map({ time - $0 >= Self.minimumPulseInterval }) ?? true else {
            return false
        }

        self.candidateSince = nil
        lastPulseAt = time
        latched = true
        return true
    }
}
