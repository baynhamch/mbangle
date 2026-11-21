import XCTest
@testable import mbangle

@MainActor
final class mbangleTests: XCTestCase {
    private func withStore(
        _ body: (AlignmentStore, TestSensor, UserDefaults) throws -> Void
    ) rethrows {
        let suiteName = "mbangle.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sensor = TestSensor()
        let store = AlignmentStore(defaults: defaults, sensor: sensor)
        defer { store.dismiss() }
        try body(store, sensor, defaults)
    }

    private func withClockedStore(
        _ body: (AlignmentStore, TestSensor, TestClock, UserDefaults) -> Void
    ) {
        let suiteName = "mbangle.freshness-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sensor = TestSensor()
        let clock = TestClock()
        let store = AlignmentStore(
            defaults: defaults, sensor: sensor, now: { clock.time },
            automaticallyMonitorFreshness: false
        )
        defer { store.dismiss() }
        body(store, sensor, clock, defaults)
    }

    func testReadFailureImmediatelyClearsGreenFeedbackAndBlocksCalibration() {
        withClockedStore { store, sensor, _, defaults in
            store.show()
            store.beginPeek()
            sensor.send(130)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 1)
            sensor.fail()
            XCTAssertNil(store.angle)
            XCTAssertFalse(store.hasReading)
            XCTAssertFalse(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 0)
            XCTAssertEqual(store.correction, "Sensor unavailable")
            store.setCurrentAsTarget()
            XCTAssertNil(defaults.object(forKey: "targetAngle"))
        }
    }

    func testSilenceExpiresTheReadingAndClearsPublishedAngle() {
        withClockedStore { store, sensor, clock, _ in
            store.beginPeek()
            sensor.send(130)
            clock.time += 0.99
            store.refreshReadingValidity()
            XCTAssertTrue(store.isOnTarget)
            clock.time += 0.02
            // Computed feedback is already invalid even before the timer fires.
            XCTAssertFalse(store.hasReading)
            XCTAssertFalse(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 0)
            store.refreshReadingValidity()
            XCTAssertNil(store.angle)
            XCTAssertFalse(store.isSensorAvailable)
        }
    }

    func testCalibrationCannotSaveAnExpiredReadingBeforeWatchdogFires() {
        withClockedStore { store, sensor, clock, defaults in
            store.show()
            sensor.send(104)
            clock.time += AlignmentStore.readingLifetime
            store.setCurrentAsTarget()
            XCTAssertEqual(store.target, 50)
            XCTAssertNil(defaults.object(forKey: "targetAngle"))
            XCTAssertNil(store.angle)
        }
    }

    func testRecoveredSensorRestoresFeedbackWithoutReopeningTray() {
        withClockedStore { store, sensor, clock, _ in
            store.show()
            store.beginPeek()
            sensor.send(130)
            sensor.fail()
            clock.time += 3
            sensor.isAvailable = true
            sensor.send(130)
            XCTAssertTrue(store.isExpanded)
            XCTAssertTrue(store.isSensorAvailable)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 1)
            XCTAssertEqual(sensor.starts, 1)
        }
    }

    func testEachValidReadingRefreshesTheFreshnessDeadline() {
        withClockedStore { store, sensor, clock, _ in
            store.beginPeek()
            sensor.send(130)
            clock.time += 0.8
            sensor.send(130)
            clock.time += 0.8
            store.refreshReadingValidity()
            XCTAssertTrue(store.isOnTarget)
            clock.time += 0.3
            store.refreshReadingValidity()
            XCTAssertFalse(store.isOnTarget)
        }
    }

    func testStoredZeroIsAValidTargetAcrossLaunches() {
        withStore { store, sensor, defaults in
            store.show()
            sensor.send(0)
            store.setCurrentAsTarget()
            let restored = AlignmentStore(defaults: defaults, sensor: TestSensor())
            XCTAssertEqual(restored.target, 180)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 0)
            XCTAssertNotNil(defaults.object(forKey: "targetAngle"))
        }
    }

    func testTargetAdjustmentsClampAndPersist() {
        withStore { store, _, defaults in
            XCTAssertEqual(store.target, 50)
            store.adjustTarget(by: 200)
            XCTAssertEqual(store.target, 180)
            store.adjustTarget(by: -200)
            XCTAssertEqual(store.target, 0)
            store.adjustTarget(by: 1)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 179)
            let restored = AlignmentStore(defaults: defaults, sensor: TestSensor())
            XCTAssertEqual(restored.target, 1)
        }
    }

    func testMissingPreferencesUseDefaultsWithoutWritingCalibrationOrTolerance() {
        withStore { store, _, defaults in
            XCTAssertEqual(store.target, 50)
            XCTAssertEqual(store.tolerance, 0.5)
            XCTAssertNil(defaults.object(forKey: "targetAngle"))
            XCTAssertNil(defaults.object(forKey: "toleranceDegrees"))
        }
    }

    func testFractionalTargetsMigrateOnceInRawSpaceIncludingTiesAndBounds() {
        withStore { _, _, defaults in
            let cases: [(saved: Double, raw: Double)] = [
                (103.65, 104), (104.35, 104), (104.5, 105), (104, 104),
                (0.5, 1), (179.5, 180), (0, 0), (180, 180), (-10, 0), (200, 180)
            ]
            for value in cases {
                defaults.set(value.saved, forKey: "targetAngle")
                let migrated = AlignmentStore(defaults: defaults, sensor: TestSensor())
                XCTAssertEqual(migrated.target, 180 - value.raw)
                XCTAssertEqual(defaults.double(forKey: "targetAngle"), value.raw)
                if (0...180).contains(value.saved) {
                    XCTAssertLessThanOrEqual(abs(value.raw - value.saved), 0.5)
                }
                let relaunched = AlignmentStore(defaults: defaults, sensor: TestSensor())
                XCTAssertEqual(relaunched.target, migrated.target)
                XCTAssertEqual(defaults.double(forKey: "targetAngle"), value.raw)
            }
        }
    }

    func testInvalidSavedTargetsAreRepairedToTheDefaultRawCalibration() {
        withStore { _, _, defaults in
            let invalidValues: [Any] = [Double.nan, Double.infinity, "invalid"]
            for invalid in invalidValues {
                defaults.set(invalid, forKey: "targetAngle")
                let restored = AlignmentStore(defaults: defaults, sensor: TestSensor())
                XCTAssertEqual(restored.target, 50)
                XCTAssertEqual(defaults.double(forKey: "targetAngle"), 130)
            }
        }
    }

    func testFractionalAdjustmentsCannotStoreFractionalTargetsAndTiesUseRawSpace() {
        withStore { _, _, defaults in
            defaults.set(104, forKey: "targetAngle")
            let store = AlignmentStore(defaults: defaults, sensor: TestSensor())
            store.adjustTarget(by: 0.1)
            XCTAssertEqual(store.target, 76)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 104)
            // Displayed 75.5 corresponds to raw 104.5, which rounds up to 105.
            store.adjustTarget(by: -0.5)
            XCTAssertEqual(store.target, 75)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 105)
            store.adjustTarget(by: 0.6)
            XCTAssertEqual(store.target, 76)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 104)
        }
    }

    func testExisting104DegreeCalibrationDisplays76WithCorrectDirections() {
        withStore { _, sensor, defaults in
            defaults.set(104, forKey: "targetAngle")
            let store = AlignmentStore(defaults: defaults, sensor: sensor)
            XCTAssertEqual(store.target, 76)
            store.show()
            sensor.send(104)
            XCTAssertEqual(store.angle, 76)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.correction, "On target")
            sensor.send(103)
            XCTAssertEqual(store.angle, 77)
            XCTAssertEqual(store.correction, "Open lid 1.0°")
            sensor.send(105)
            XCTAssertEqual(store.angle, 75)
            XCTAssertEqual(store.correction, "Close lid 1.0°")
        }
    }

    func testCalibrationStoresRawAngleAndRestoresComplementaryDisplay() {
        withStore { store, sensor, defaults in
            store.show()
            sensor.send(104)
            store.setCurrentAsTarget()
            XCTAssertEqual(store.target, 76)
            XCTAssertEqual(defaults.double(forKey: "targetAngle"), 104)
            let restored = AlignmentStore(defaults: defaults, sensor: TestSensor())
            XCTAssertEqual(restored.target, 76)
        }
    }

    func testSensorRunsOnlyWhileTrayIsExpandedAndOldReadingsAreCleared() {
        withStore { store, sensor, _ in
            XCTAssertFalse(store.isExpanded)
            XCTAssertEqual(sensor.starts, 0)
            store.show()
            store.show()
            XCTAssertEqual(sensor.starts, 1)
            sensor.send(127)
            XCTAssertEqual(store.angle, 53)
            store.hide()
            store.hide()
            XCTAssertEqual(sensor.stops, 1)
            XCTAssertNil(store.angle)
            sensor.send(128)
            XCTAssertNil(store.angle)
            store.show()
            XCTAssertNil(store.angle)
            XCTAssertEqual(sensor.starts, 2)
        }
    }

    func testToleranceBoundaryAndDirection() {
        withStore { store, sensor, _ in
            store.show()
            sensor.send(129.5)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.correction, "On target")
            sensor.send(129.4)
            XCTAssertFalse(store.isOnTarget)
            XCTAssertEqual(store.correction, "Open lid 0.6°")
            sensor.send(130.6)
            XCTAssertEqual(store.correction, "Close lid 0.6°")
        }
    }

    func testUnavailableSensorDoesNotInventOrSaveAnAngle() {
        withStore { store, sensor, defaults in
            sensor.isAvailable = false
            store.show()
            XCTAssertFalse(store.hasReading)
            XCTAssertFalse(store.isOnTarget)
            XCTAssertEqual(store.correction, "Sensor unavailable")
            store.setCurrentAsTarget()
            XCTAssertEqual(store.target, 50)
            XCTAssertNil(defaults.object(forKey: "targetAngle"))
        }
    }

    func testSubminimumAndInvalidTolerancesAreRepairedAndPersisted() {
        withStore { _, _, defaults in
            let invalidValues: [Any] = [0.3, 0.2, 0, -1, Double.nan, Double.infinity, "invalid"]
            for invalid in invalidValues {
                defaults.set(invalid, forKey: "toleranceDegrees")
                let repaired = AlignmentStore(defaults: defaults, sensor: TestSensor())
                XCTAssertEqual(repaired.tolerance, 0.5)
                XCTAssertEqual(defaults.double(forKey: "toleranceDegrees"), 0.5)
            }
            for valid in [0.5, 1.25] {
                defaults.set(valid, forKey: "toleranceDegrees")
                let restored = AlignmentStore(defaults: defaults, sensor: TestSensor())
                XCTAssertEqual(restored.tolerance, valid)
                XCTAssertEqual(defaults.double(forKey: "toleranceDegrees"), valid)
            }
        }
    }

    func testCalibrationRequiresAValidRawSampleEvenWhenDisplayIsFresh() {
        withStore { store, sensor, defaults in
            store.show()
            let invalidSamples: [Double?] = [nil, Double.nan, Double.infinity, -1, 181]
            for invalid in invalidSamples {
                sensor.send(104, rawAngle: invalid)
                XCTAssertTrue(store.hasReading)
                store.setCurrentAsTarget()
                XCTAssertEqual(store.target, 50)
                XCTAssertNil(defaults.object(forKey: "targetAngle"))
            }
        }
    }

    func testInvalidReadingsAndAdjustmentDoNotCorruptCalibration() {
        withStore { store, sensor, _ in
            store.show()
            sensor.send(.nan)
            sensor.send(65535)
            XCTAssertNil(store.angle)
            store.adjustTarget(by: .infinity)
            XCTAssertEqual(store.target, 50)
        }
    }

    func testPeekPollsWithoutOpeningTrayAndReleaseClearsFeedback() {
        withStore { store, sensor, defaults in
            store.beginPeek()
            store.beginPeek()
            XCTAssertTrue(store.isPeeking)
            XCTAssertFalse(store.isExpanded)
            XCTAssertEqual(sensor.starts, 1)
            sensor.send(128)
            XCTAssertEqual(store.angle, 52)
            XCTAssertGreaterThan(store.titleFillFraction, 0)
            store.setCurrentAsTarget()
            XCTAssertNil(defaults.object(forKey: "targetAngle"))
            store.endPeek()
            store.endPeek()
            XCTAssertFalse(store.isPeeking)
            XCTAssertEqual(sensor.stops, 1)
            XCTAssertNil(store.angle)
            XCTAssertEqual(store.titleFillFraction, 0)
            sensor.send(130)
            XCTAssertNil(store.angle)
        }
    }

    func testOpeningTrayDuringPeekKeepsSensorRunningAfterKeyRelease() {
        withStore { store, sensor, _ in
            store.beginPeek()
            sensor.send(129)
            store.show()
            XCTAssertEqual(sensor.starts, 1)
            XCTAssertEqual(store.angle, 51)
            store.endPeek()
            XCTAssertTrue(store.isExpanded)
            XCTAssertEqual(sensor.stops, 0)
            XCTAssertEqual(store.angle, 51)
            XCTAssertEqual(store.titleFillFraction, 0)
            store.hide()
            XCTAssertEqual(sensor.stops, 1)
            XCTAssertNil(store.angle)
        }
    }

    func testClosingTrayDuringPeekKeepsTitleFeedbackLive() {
        withStore { store, sensor, _ in
            store.show()
            sensor.send(129)
            store.beginPeek()
            XCTAssertEqual(sensor.starts, 1)
            store.hide()
            XCTAssertTrue(store.isPeeking)
            XCTAssertEqual(sensor.stops, 0)
            XCTAssertEqual(store.angle, 51)
            sensor.send(130)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 1)
            store.endPeek()
            XCTAssertEqual(sensor.stops, 1)
            XCTAssertNil(store.angle)
        }
    }

    func testDismissStopsBothPresentationsOnce() {
        withStore { store, sensor, _ in
            store.show()
            store.beginPeek()
            sensor.send(130)
            store.dismiss()
            store.dismiss()
            XCTAssertFalse(store.isExpanded)
            XCTAssertFalse(store.isPeeking)
            XCTAssertNil(store.angle)
            XCTAssertEqual(store.titleFillFraction, 0)
            XCTAssertEqual(sensor.starts, 1)
            XCTAssertEqual(sensor.stops, 1)
        }
    }

    func testTitleFillApproachesTargetSymmetricallyAndFillsWithinTolerance() {
        withStore { store, sensor, _ in
            store.beginPeek()
            XCTAssertEqual(store.titleFillFraction, 0)
            sensor.send(120)
            let distantFill = store.titleFillFraction
            sensor.send(124.5)
            XCTAssertEqual(store.titleFillFraction, 0.5, accuracy: 0.0001)
            XCTAssertGreaterThan(store.titleFillFraction, distantFill)
            sensor.send(135.5)
            XCTAssertEqual(store.titleFillFraction, 0.5, accuracy: 0.0001)
            sensor.send(129.5)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 1)
            sensor.send(130.5)
            XCTAssertTrue(store.isOnTarget)
            XCTAssertEqual(store.titleFillFraction, 1)
            sensor.send(180)
            XCTAssertEqual(store.titleFillFraction, 0.08)
        }
    }

    func testTitleFeedbackIsAbsentForUnavailableOrInvalidReadings() {
        withStore { store, sensor, _ in
            sensor.isAvailable = false
            store.beginPeek()
            sensor.send(130)
            XCTAssertEqual(store.titleFillFraction, 0)
            XCTAssertNil(store.angle)
            store.endPeek()
            sensor.isAvailable = true
            store.beginPeek()
            sensor.send(130)
            XCTAssertEqual(store.titleFillFraction, 1)
            sensor.send(.nan)
            XCTAssertEqual(store.titleFillFraction, 0)
            XCTAssertNil(store.angle)
            sensor.send(65535)
            XCTAssertEqual(store.titleFillFraction, 0)
        }
    }
}

@MainActor
private final class TestClock {
    var time: TimeInterval = 100
}

@MainActor
private final class TestSensor: AlignmentSensor {
    var onAngle: ((Double?) -> Void)?
    var isAvailable = true
    private(set) var latestRawAngle: Double?
    private(set) var starts = 0
    private(set) var stops = 0

    func start() {
        starts += 1
        latestRawAngle = nil
    }
    func stop() {
        stops += 1
        latestRawAngle = nil
    }
    func send(_ reading: Double) { send(reading, rawAngle: reading) }
    func send(_ reading: Double, rawAngle: Double?) {
        latestRawAngle = rawAngle
        onAngle?(reading)
    }
    func fail() {
        isAvailable = false
        latestRawAngle = nil
        onAngle?(nil)
    }
}
