import XCTest
@testable import mbangle

@MainActor
final class AlignmentHapticGateTests: XCTestCase {
    func testRequiresStableAlignmentBeforeOnePulse() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        XCTAssertFalse(update(&gate, at: 0.149))
        XCTAssertTrue(update(&gate, at: 0.15))
        XCTAssertFalse(update(&gate, at: 0.3))
        XCTAssertFalse(update(&gate, at: 2))
    }

    func testBothRawAndDisplayedAnglesMustAgreeWithTarget() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, raw: 102, at: 0))
        XCTAssertFalse(update(&gate, raw: 102, at: 0.2))
        XCTAssertFalse(update(&gate, at: 0.3))
        XCTAssertFalse(update(&gate, displayed: 78, at: 0.5))
        XCTAssertFalse(update(&gate, at: 0.6))
        XCTAssertFalse(update(&gate, at: 0.74))
        XCTAssertTrue(update(&gate, at: 0.76))
    }

    func testBriefPassThroughTargetDoesNotPulse() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        XCTAssertFalse(update(&gate, displayed: 77, raw: 103, at: 0.1))
        XCTAssertFalse(update(&gate, at: 0.2))
        XCTAssertFalse(update(&gate, at: 0.34))
        XCTAssertTrue(update(&gate, at: 0.36))
    }

    func testBoundaryJitterDoesNotRearmUntilClearDeparture() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        XCTAssertTrue(update(&gate, at: 0.16))

        // Outside the green range but still inside the extra half-degree margin.
        XCTAssertFalse(update(&gate, displayed: 76.8, raw: 103.2, at: 1))
        XCTAssertFalse(update(&gate, at: 1.1))
        XCTAssertFalse(update(&gate, at: 1.3))
        // The release boundary is strict: tolerance + 0.5° is not yet a departure.
        XCTAssertFalse(update(&gate, displayed: 77, raw: 103, at: 2))
        XCTAssertFalse(update(&gate, at: 2.1))
        XCTAssertFalse(update(&gate, at: 2.3))

        XCTAssertFalse(update(&gate, displayed: 77.1, raw: 102.9, at: 3))
        XCTAssertFalse(update(&gate, at: 3.1))
        XCTAssertTrue(update(&gate, at: 3.26))
    }

    func testEitherRawOrDisplayedDepartureCanRearm() {
        for departure in [(displayed: 77.1, raw: 104.0), (displayed: 76.0, raw: 102.9)] {
            var gate = AlignmentHapticGate()
            XCTAssertFalse(update(&gate, at: 0))
            XCTAssertTrue(update(&gate, at: 0.16))
            XCTAssertFalse(update(&gate, displayed: departure.displayed, raw: departure.raw, at: 1))
            XCTAssertFalse(update(&gate, at: 1.1))
            XCTAssertTrue(update(&gate, at: 1.26))
        }
    }

    func testCooldownLimitsRapidDeparturesAndReentries() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        XCTAssertTrue(update(&gate, at: 0.16))
        XCTAssertFalse(update(&gate, displayed: 78, raw: 102, at: 0.2))
        XCTAssertFalse(update(&gate, at: 0.3))
        XCTAssertFalse(update(&gate, at: 0.5), "Stable again, but the previous pulse was too recent.")
        XCTAssertFalse(update(&gate, at: 0.9))
        XCTAssertTrue(update(&gate, at: 0.92))
        XCTAssertFalse(update(&gate, at: 1.2))
    }

    func testResetClearsDwellAndLatchButPreservesCooldown() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        gate.reset()
        XCTAssertFalse(update(&gate, at: 0.1))
        XCTAssertFalse(update(&gate, at: 0.2))
        XCTAssertTrue(update(&gate, at: 0.26))

        gate.reset()
        XCTAssertFalse(update(&gate, at: 0.3))
        XCTAssertFalse(update(&gate, at: 0.5))
        XCTAssertFalse(update(&gate, at: 1))
        XCTAssertTrue(update(&gate, at: 1.02))
    }

    func testInvalidInputsCannotCompleteAnAlignmentCandidate() {
        let invalidSamples: [(Double, Double, Double, Double, Double)] = [
            (.nan, 104, 76, 0.5, 0.1),
            (.infinity, 104, 76, 0.5, 0.1),
            (-0.1, 104, 76, 0.5, 0.1),
            (180.1, 104, 76, 0.5, 0.1),
            (76, .nan, 76, 0.5, 0.1),
            (76, -.infinity, 76, 0.5, 0.1),
            (76, -0.1, 76, 0.5, 0.1),
            (76, 180.1, 76, 0.5, 0.1),
            (76, 104, .nan, 0.5, 0.1),
            (76, 104, -1, 0.5, 0.1),
            (76, 104, 181, 0.5, 0.1),
            (76, 104, 76, .nan, 0.1),
            (76, 104, 76, .infinity, 0.1),
            (76, 104, 76, -0.5, 0.1),
            (76, 104, 76, 0.5, .nan),
            (76, 104, 76, 0.5, .infinity),
            (76, 104, 76, 0.5, -0.1)
        ]
        for (displayed, raw, target, tolerance, time) in invalidSamples {
            var gate = AlignmentHapticGate()
            XCTAssertFalse(update(&gate, at: 0))
            XCTAssertFalse(gate.update(displayedAngle: displayed, rawAngle: raw,
                                       target: target, tolerance: tolerance, at: time))
            XCTAssertFalse(update(&gate, at: 0.2))
            XCTAssertFalse(update(&gate, at: 0.34))
            XCTAssertTrue(update(&gate, at: 0.36))
        }
    }

    func testBackwardClockRestartsTheStabilityWindow() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 1))
        XCTAssertFalse(update(&gate, at: 0.8))
        XCTAssertFalse(update(&gate, at: 1.05))
        XCTAssertFalse(update(&gate, at: 1.19))
        XCTAssertTrue(update(&gate, at: 1.21))
    }

    func testChangingTargetStartsANewStabilityWindowAndKeepsCooldown() {
        var gate = AlignmentHapticGate()
        XCTAssertFalse(update(&gate, at: 0))
        XCTAssertTrue(update(&gate, at: 0.16))
        XCTAssertFalse(gate.update(displayedAngle: 80, rawAngle: 100,
                                   target: 80, tolerance: 0.5, at: 0.2))
        XCTAssertFalse(gate.update(displayedAngle: 80, rawAngle: 100,
                                   target: 80, tolerance: 0.5, at: 0.4))
        XCTAssertTrue(gate.update(displayedAngle: 80, rawAngle: 100,
                                  target: 80, tolerance: 0.5, at: 0.92))
    }

    private func update(
        _ gate: inout AlignmentHapticGate,
        displayed: Double = 76,
        raw: Double = 104,
        at time: TimeInterval
    ) -> Bool {
        gate.update(displayedAngle: displayed, rawAngle: raw,
                    target: 76, tolerance: 0.5, at: time)
    }
}
