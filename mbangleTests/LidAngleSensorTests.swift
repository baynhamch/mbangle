import XCTest
@testable import mbangle

@MainActor
final class LidAngleSensorTests: XCTestCase {
    func testCalibrationUsesLatestIntegerSampleAndReacquiresAfterRelaunch() {
        let suiteName = "mbangle.precision-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Reproduce the formerly unreachable fractional calibration at ±0.3°.
        defaults.set(0.3, forKey: "toleranceDegrees")
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [true], readings: [104, 103, 103])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        let store = AlignmentStore(
            defaults: defaults, sensor: sensor, now: { clock.now },
            automaticallyMonitorFreshness: false
        )
        defer { store.dismiss() }
        store.show()
        XCTAssertEqual(store.angle, 76)
        sensor.poll()
        XCTAssertEqual(store.angle!, 76.35, accuracy: 0.0001)
        XCTAssertEqual(sensor.latestRawAngle, 103)

        store.setCurrentAsTarget()
        XCTAssertEqual(store.target, 77)
        XCTAssertEqual(defaults.double(forKey: "targetAngle"), 103)
        XCTAssertEqual(store.tolerance, 0.5)
        XCTAssertEqual(defaults.double(forKey: "toleranceDegrees"), 0.5)
        // Saving does not snap the animated display or report success too early.
        XCTAssertEqual(store.angle!, 76.35, accuracy: 0.0001)
        XCTAssertFalse(store.isOnTarget)
        sensor.poll()
        XCTAssertTrue(store.isOnTarget)
        store.hide()
        XCTAssertNil(sensor.latestRawAngle)

        let restoredSensor = LidAngleSensor(
            transport: SensorTestTransport(connections: [true], readings: [103]),
            clock: { clock.now }, schedulesTimer: false
        )
        let restored = AlignmentStore(
            defaults: defaults, sensor: restoredSensor, now: { clock.now },
            automaticallyMonitorFreshness: false
        )
        defer { restored.dismiss() }
        restored.show()
        restored.beginPeek()
        XCTAssertEqual(restored.target, 77)
        XCTAssertEqual(restored.angle, 77)
        XCTAssertTrue(restored.isOnTarget)
        XCTAssertEqual(restored.titleFillFraction, 1)
    }

    func testTransportFailureAndRecoveryReachTheLiveAlignmentStore() {
        let suiteName = "mbangle.transport-store-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [true, true], readings: [104, nil, 104])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        let store = AlignmentStore(
            defaults: defaults, sensor: sensor, now: { clock.now },
            automaticallyMonitorFreshness: false
        )
        defer { store.dismiss() }
        store.show()
        store.beginPeek()
        XCTAssertTrue(store.isOnTarget)
        XCTAssertEqual(store.titleFillFraction, 1)
        clock.now = 0.1
        sensor.poll()
        XCTAssertNil(store.angle)
        XCTAssertFalse(store.isSensorAvailable)
        XCTAssertFalse(store.isOnTarget)
        XCTAssertEqual(store.titleFillFraction, 0)
        store.setCurrentAsTarget()
        XCTAssertNil(defaults.object(forKey: "targetAngle"))
        clock.now = 1.1
        sensor.poll()
        XCTAssertTrue(store.isSensorAvailable)
        XCTAssertTrue(store.isOnTarget)
        XCTAssertEqual(store.titleFillFraction, 1)
    }

    func testMissingSensorRecoversWithoutRestartingAndRetriesAreThrottled() {
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [false, true], readings: [104])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        var samples: [Double?] = []
        sensor.onAngle = { samples.append($0) }

        XCTAssertEqual(transport.connectionAttempts, 0)
        sensor.start()
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(samples.count, 1)
        XCTAssertNil(samples[0])
        clock.now = 0.99
        sensor.poll()
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 1)
        clock.now = 1
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 2)
        XCTAssertTrue(sensor.isAvailable)
        XCTAssertEqual(samples.last!, 104)
        sensor.stop()
    }

    func testReadFailureImmediatelyInvalidatesSampleAndAvailabilityBeforeCallback() {
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [true], readings: [104, nil])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        var samples: [Double?] = []
        var availability: [Bool] = []
        var rawSamples: [Double?] = []
        sensor.onAngle = { [weak sensor] sample in
            samples.append(sample)
            availability.append(sensor?.isAvailable ?? false)
            rawSamples.append(sensor?.latestRawAngle)
        }

        sensor.start()
        XCTAssertEqual(samples[0], 104)
        XCTAssertEqual(availability, [true])
        XCTAssertEqual(rawSamples[0], 104)
        clock.now = 0.1
        sensor.poll()
        XCTAssertNil(samples[1])
        XCTAssertEqual(availability, [true, false])
        XCTAssertNil(rawSamples[1])
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(transport.disconnections, 1)
        XCTAssertFalse(transport.isConnected)
        sensor.stop()
    }

    func testRecoveryResetsSmoothingAndRespectsRetryDeadlineAfterReadFailure() {
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [true, true], readings: [100, 110, nil, 140])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        var latest: Double?
        sensor.onAngle = { latest = $0 }
        sensor.start()
        sensor.poll()
        XCTAssertEqual(latest!, 103.5, accuracy: 0.0001)
        XCTAssertEqual(sensor.latestRawAngle, 110)
        clock.now = 0.2
        sensor.poll()
        XCTAssertNil(latest)
        XCTAssertNil(sensor.latestRawAngle)
        clock.now = 1.19
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 1)
        clock.now = 1.2
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 2)
        XCTAssertEqual(latest, 140)
        XCTAssertEqual(sensor.latestRawAngle, 140)
        sensor.stop()
    }

    func testInvalidSamplesClearStateBeforeTheyCanContaminateSmoothing() {
        for invalid in [Double.nan, .infinity, -1, 181, 65535] {
            let clock = SensorTestClock()
            let transport = SensorTestTransport(connections: [true, true], readings: [104, invalid, 110])
            let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
            var latest: Double?
            sensor.onAngle = { latest = $0 }
            sensor.start()
            XCTAssertEqual(latest, 104)
            sensor.poll()
            XCTAssertNil(latest)
            XCTAssertNil(sensor.latestRawAngle)
            XCTAssertFalse(sensor.isAvailable)
            XCTAssertFalse(transport.isConnected)
            clock.now = 1
            sensor.poll()
            XCTAssertEqual(latest, 110)
            sensor.stop()
        }
    }

    func testStopCancelsRetriesAndClosesConnectionUntilAnExplicitRestart() {
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [true, true], readings: [104, 120])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        var latest: Double?
        sensor.onAngle = { latest = $0 }
        sensor.start()
        sensor.start()
        XCTAssertEqual(transport.connectionAttempts, 1)
        sensor.stop()
        sensor.stop()
        XCTAssertNil(latest)
        XCTAssertNil(sensor.latestRawAngle)
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertFalse(transport.isConnected)
        XCTAssertEqual(transport.disconnections, 1)
        clock.now = 100
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 1)
        XCTAssertEqual(transport.readAttempts, 1)
        sensor.start()
        XCTAssertEqual(transport.connectionAttempts, 2)
        XCTAssertEqual(latest, 120)
        XCTAssertEqual(sensor.latestRawAngle, 120)
        sensor.stop()
    }

    func testStoppingDuringFailureBackoffPreventsFurtherDiscovery() {
        let clock = SensorTestClock()
        let transport = SensorTestTransport(connections: [false, true], readings: [104])
        let sensor = LidAngleSensor(transport: transport, clock: { clock.now }, schedulesTimer: false)
        sensor.start()
        sensor.stop()
        clock.now = 100
        sensor.poll()
        XCTAssertEqual(transport.connectionAttempts, 1)
        XCTAssertEqual(transport.readAttempts, 0)
        XCTAssertFalse(sensor.isAvailable)
    }

    func testConnectionFailureDoesNotAttemptAReadOrReportAvailability() {
        let transport = SensorTestTransport(connections: [false], readings: [104])
        let sensor = LidAngleSensor(transport: transport, clock: { 0 }, schedulesTimer: false)
        var samples: [Double?] = []
        sensor.onAngle = { samples.append($0) }
        sensor.start()
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(transport.readAttempts, 0)
        XCTAssertEqual(transport.disconnections, 1)
        XCTAssertEqual(samples.count, 1)
        XCTAssertNil(samples[0])
        sensor.stop()
    }

    func testFirstReadFailureAfterConnectionNeverPublishesAnAvailableState() {
        let transport = SensorTestTransport(connections: [true], readings: [nil])
        let sensor = LidAngleSensor(transport: transport, clock: { 0 }, schedulesTimer: false)
        var availability: [Bool] = []
        sensor.onAngle = { [weak sensor] _ in availability.append(sensor?.isAvailable ?? true) }
        sensor.start()
        XCTAssertEqual(availability, [false])
        XCTAssertFalse(transport.isConnected)
        sensor.stop()
    }

    func testReportDecoderRejectsShortInvalidLengthsAndOutOfRangeAngles() {
        XCTAssertNil(LidAngleReport.decode([], length: 0))
        XCTAssertNil(LidAngleReport.decode([1, 104], length: 2))
        XCTAssertNil(LidAngleReport.decode([1, 104, 0], length: -1))
        XCTAssertNil(LidAngleReport.decode([1, 104, 0], length: 4))
        XCTAssertNil(LidAngleReport.decode([1, 181, 0], length: 3))
        XCTAssertNil(LidAngleReport.decode([1, 255, 255], length: 3))
        XCTAssertEqual(LidAngleReport.decode([1, 104, 0], length: 3), 104)
        XCTAssertEqual(LidAngleReport.decode([1, 0, 0], length: 3), 0)
        XCTAssertEqual(LidAngleReport.decode([1, 180, 0], length: 3), 180)
    }
}

@MainActor
private final class SensorTestClock {
    var now: TimeInterval = 0
}

@MainActor
private final class SensorTestTransport: LidAngleTransport {
    private var connections: [Bool]
    private var readings: [Double?]
    private(set) var connectionAttempts = 0
    private(set) var readAttempts = 0
    private(set) var disconnections = 0
    private(set) var isConnected = false

    init(connections: [Bool], readings: [Double?]) {
        self.connections = connections
        self.readings = readings
    }

    func connect() -> Bool {
        connectionAttempts += 1
        isConnected = connections.isEmpty ? false : connections.removeFirst()
        return isConnected
    }

    func readAngle() -> Double? {
        readAttempts += 1
        return readings.isEmpty ? nil : readings.removeFirst()
    }

    func disconnect() {
        disconnections += 1
        isConnected = false
    }
}
