import Foundation
import XCTest
@testable import mbangle

@MainActor
final class NativeAngleSensorTests: XCTestCase {
    func testSmoothingPreservesRawSampleForCalibration() async {
        let clock = SensorTestClock(42)
        let source = SensorTestSource([.init(100), .init(120)])
        let sensor = NativeAngleSensor(sourceFactory: { source }, pollingInterval: 0.005, now: { clock.read() })
        let suite = "NativeAngleSensorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlignmentStore(defaults: defaults, sensor: sensor, now: { clock.read() }, automaticallyMonitorFreshness: false)
        let updateStore = sensor.onAngle
        let received = expectation(description: "two angle samples")
        var samples: [Double] = []
        var raw: Double?
        var sampledAt: TimeInterval?
        var calibratedTarget: Double?
        var displayedAngle: Double?
        sensor.onAngle = { value in
            XCTAssertTrue(Thread.isMainThread)
            updateStore?(value)
            guard let value else { return }
            samples.append(value)
            if samples.count == 2 {
                raw = sensor.latestRawAngle
                sampledAt = sensor.latestSampleTime
                displayedAngle = store.angle
                XCTAssertTrue(sensor.isAvailable)
                store.setCurrentAsTarget()
                calibratedTarget = store.target
                store.hide()
                received.fulfill()
            }
        }

        store.show()
        defer { store.dismiss() }
        await fulfillment(of: [received, source.closed], timeout: 2)

        XCTAssertEqual(samples, [100, 107])
        XCTAssertEqual(raw, 120)
        XCTAssertEqual(sampledAt, 42)
        XCTAssertEqual(displayedAngle, 73)
        XCTAssertEqual(calibratedTarget, 60)
        XCTAssertEqual(defaults.double(forKey: "targetAngle"), 120)
    }

    func testBlockedReadAllowsDismissalAndClosesOnlyAfterReadReturns() async {
        let journal = SensorOperationJournal()
        let gate = SensorReadGate()
        let source = SensorTestSource([.init(110, gate: gate)], journal: journal)
        let factory = SensorTestFactory([source], journal: journal)
        let sensor = NativeAngleSensor(sourceFactory: { factory.make() }, pollingInterval: 0.005)
        let suite = "NativeAngleSensorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlignmentStore(defaults: defaults, sensor: sensor, automaticallyMonitorFreshness: false)
        store.show()
        store.beginPeek()
        defer {
            gate.release()
            store.dismiss()
        }
        await fulfillment(of: [gate.started], timeout: 2)

        XCTAssertTrue(gate.isWaiting, "The main actor must remain available while the read is blocked.")
        store.dismiss()
        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isPeeking)
        XCTAssertNil(store.angle)
        XCTAssertNil(sensor.latestRawAngle)
        XCTAssertNil(sensor.latestSampleTime)
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(source.closeCount, 0, "Closing a device must not race its in-flight read.")

        gate.release()
        await fulfillment(of: [source.closed], timeout: 2)
        await mainQueueBarrier()

        XCTAssertFalse(gate.didTimeOut)
        XCTAssertEqual(source.readCount, 1)
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(journal.events, ["factory.begin", "factory.end", "read.begin", "read.end", "close.begin", "close.end"])
        XCTAssertFalse(journal.usedMainThread)
        XCTAssertEqual(journal.maximumConcurrentOperations, 1)
    }

    func testLateResultCannotPopulateStoppedSensor() async {
        let gate = SensorReadGate()
        let source = SensorTestSource([.init(123, gate: gate)])
        let sensor = NativeAngleSensor(sourceFactory: { source }, pollingInterval: 0.005)
        var values: [Double] = []
        var nilCount = 0
        sensor.onAngle = { value in
            if let value { values.append(value) } else { nilCount += 1 }
        }
        sensor.start()
        defer {
            gate.release()
            sensor.stop()
        }
        await fulfillment(of: [gate.started], timeout: 2)

        sensor.stop()
        XCTAssertEqual(nilCount, 1, "Stop must synchronously invalidate the displayed reading.")
        gate.release()
        await fulfillment(of: [source.closed], timeout: 2)
        await mainQueueBarrier()

        XCTAssertTrue(values.isEmpty)
        XCTAssertNil(sensor.latestRawAngle)
        XCTAssertNil(sensor.latestSampleTime)
        XCTAssertFalse(sensor.isAvailable)
        XCTAssertEqual(source.readCount, 1, "Stopped polling must not begin another read.")
        XCTAssertFalse(gate.didTimeOut)
    }

    func testRapidRestartDiscardsOldSessionAndStartsWithUnsmoothedSample() async {
        let clock = SensorTestClock(10)
        let journal = SensorOperationJournal()
        let gate = SensorReadGate()
        let oldSource = SensorTestSource([.init(160, gate: gate)], journal: journal)
        let newSource = SensorTestSource([.init(20)], journal: journal)
        let factory = SensorTestFactory([oldSource, newSource], journal: journal)
        let sensor = NativeAngleSensor(sourceFactory: { factory.make() }, pollingInterval: 0.005, now: { clock.read() })
        let received = expectation(description: "new session value")
        var values: [Double] = []
        sensor.onAngle = { value in
            guard let value else { return }
            values.append(value)
            sensor.stop()
            received.fulfill()
        }
        sensor.start()
        defer {
            gate.release()
            sensor.stop()
        }
        await fulfillment(of: [gate.started], timeout: 2)

        sensor.stop()
        sensor.start()
        sensor.start() // Starting an active session must be idempotent.
        gate.release()
        await fulfillment(of: [received, oldSource.closed, newSource.closed], timeout: 2)

        XCTAssertEqual(values, [20])
        XCTAssertEqual(factory.attemptCount, 2)
        XCTAssertEqual(oldSource.readCount, 1)
        XCTAssertEqual(oldSource.closeCount, 1)
        XCTAssertEqual(newSource.closeCount, 1)
        XCTAssertFalse(journal.usedMainThread)
        XCTAssertEqual(journal.maximumConcurrentOperations, 1)
        XCTAssertFalse(gate.didTimeOut)
    }

    func testReadsNeverOverlapAndRepeatedStartDoesNotDuplicatePolling() async {
        let journal = SensorOperationJournal()
        let source = SensorTestSource(Array(repeating: .init(90), count: 20), journal: journal)
        let factory = SensorTestFactory([source], journal: journal)
        let sensor = NativeAngleSensor(sourceFactory: { factory.make() }, pollingInterval: 0.001)
        let received = expectation(description: "twenty serialized reads")
        var count = 0
        sensor.onAngle = { value in
            guard value != nil else { return }
            count += 1
            sensor.start()
            if count == 20 {
                sensor.stop()
                received.fulfill()
            }
        }
        sensor.start()
        defer { sensor.stop() }
        await fulfillment(of: [received, source.closed], timeout: 2)
        await mainQueueBarrier()

        XCTAssertEqual(count, 20)
        XCTAssertGreaterThanOrEqual(source.readCount, 20)
        XCTAssertEqual(factory.attemptCount, 1)
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertEqual(journal.maximumConcurrentOperations, 1)
        XCTAssertFalse(journal.usedMainThread)
    }

    func testInvalidReadFailsClosedAndRecoveryResetsSmoothing() async {
        let invalidValues: [Double?] = [nil, .nan, .infinity, -.infinity, -0.01, 180.01]
        for invalid in invalidValues {
            let clock = SensorTestClock(20)
            let brokenSource = SensorTestSource([.init(100), .init(invalid)])
            let recoveredSource = SensorTestSource([.init(140)])
            let factory = SensorTestFactory([brokenSource, recoveredSource])
            let sensor = NativeAngleSensor(sourceFactory: { factory.make() }, pollingInterval: 0.005, now: { clock.read() })
            let recovered = expectation(description: "recovery after \(String(describing: invalid))")
            var values: [Double] = []
            var sawInvalidation = false
            sensor.onAngle = { value in
                if let value {
                    values.append(value)
                    if values.count == 2 {
                        sensor.stop()
                        recovered.fulfill()
                    }
                } else if values.count == 1, !sawInvalidation {
                    sawInvalidation = true
                    XCTAssertFalse(sensor.isAvailable)
                    XCTAssertNil(sensor.latestRawAngle)
                    XCTAssertNil(sensor.latestSampleTime)
                    clock.set(21)
                }
            }
            sensor.start()
            await fulfillment(of: [recovered, brokenSource.closed, recoveredSource.closed], timeout: 2)
            sensor.stop()

            XCTAssertTrue(sawInvalidation)
            XCTAssertEqual(values, [100, 140], "Recovery must not reuse the old smoothing average.")
            XCTAssertEqual(factory.attemptCount, 2)
            XCTAssertEqual(brokenSource.closeCount, 1)
        }
    }

    func testUnavailableDiscoveryRetriesAtMostOncePerSecond() async {
        let clock = SensorTestClock(0)
        let source = SensorTestSource([.init(90)])
        let firstAttempt = expectation(description: "initial discovery")
        let factory = SensorTestFactory([nil, source], attempts: [1: firstAttempt])
        let sensor = NativeAngleSensor(sourceFactory: { factory.make() }, pollingInterval: 0.001, now: { clock.read() })
        let received = expectation(description: "discovery retry succeeds")
        sensor.onAngle = { value in
            guard value != nil else { return }
            sensor.stop()
            received.fulfill()
        }
        sensor.start()
        defer { sensor.stop() }
        await fulfillment(of: [firstAttempt], timeout: 2)

        let initialPolls = expectation(description: "polls while unavailable")
        clock.observeNextReads(6, fulfilling: initialPolls)
        await fulfillment(of: [initialPolls], timeout: 2)
        XCTAssertEqual(factory.attemptCount, 1)
        XCTAssertFalse(sensor.isAvailable)

        clock.set(0.999)
        let earlyPolls = expectation(description: "polls before retry deadline")
        clock.observeNextReads(6, fulfilling: earlyPolls)
        await fulfillment(of: [earlyPolls], timeout: 2)
        XCTAssertEqual(factory.attemptCount, 1)

        clock.set(1)
        await fulfillment(of: [received, source.closed], timeout: 2)
        XCTAssertEqual(factory.attemptCount, 2)
    }

    func testDelayedSampleUsesAcquisitionTimeAndResetsSmoothing() async {
        let clock = SensorTestClock(50)
        let gate = SensorReadGate()
        let source = SensorTestSource([.init(100), .init(120, gate: gate), .init(140)])
        let sensor = NativeAngleSensor(sourceFactory: { source }, pollingInterval: 0.005, now: { clock.read() })
        let first = expectation(description: "fresh first sample")
        let last = expectation(description: "fresh sample after stale read")
        var values: [Double] = []
        var invalidated = false
        var finalTimestamp: TimeInterval?
        sensor.onAngle = { value in
            if let value {
                values.append(value)
                if values.count == 1 {
                    first.fulfill()
                } else {
                    finalTimestamp = sensor.latestSampleTime
                    sensor.stop()
                    last.fulfill()
                }
            } else if values.count == 1 {
                invalidated = true
                XCTAssertNil(sensor.latestRawAngle)
                XCTAssertNil(sensor.latestSampleTime)
                XCTAssertFalse(sensor.isAvailable)
            }
        }
        sensor.start()
        defer {
            gate.release()
            sensor.stop()
        }
        await fulfillment(of: [first, gate.started], timeout: 2)

        clock.set(51) // Exactly the one-second lifetime is already stale.
        gate.release()
        await fulfillment(of: [last, source.closed], timeout: 2)

        XCTAssertTrue(invalidated)
        XCTAssertEqual(values, [100, 140])
        XCTAssertEqual(finalTimestamp, 51)
        XCTAssertFalse(gate.didTimeOut)
    }

    func testZeroAndOneHundredEightyAreValidRawAngles() async {
        let source = SensorTestSource([.init(0), .init(180)])
        let sensor = NativeAngleSensor(sourceFactory: { source }, pollingInterval: 0.005)
        let received = expectation(description: "both valid endpoints")
        var rawValues: [Double] = []
        sensor.onAngle = { value in
            guard value != nil, let raw = sensor.latestRawAngle else { return }
            rawValues.append(raw)
            if rawValues.count == 2 {
                sensor.stop()
                received.fulfill()
            }
        }
        sensor.start()
        defer { sensor.stop() }
        await fulfillment(of: [received, source.closed], timeout: 2)
        XCTAssertEqual(rawValues, [0, 180])
    }

    func testDescriptorAcceptsHingeUsageAndRejectsUnrelatedTilt() {
        let hinge = hingeDescriptor()
        XCTAssertTrue(hinge.isRecognized(product: nil, primaryUsagePage: 0x20, primaryUsage: 0xE4))
        XCTAssertFalse(hinge.isRecognized(product: nil, primaryUsagePage: 0x01, primaryUsage: 0xE4))
        var tilt = hinge
        tilt.usage = 0x47F
        tilt.type = 1
        tilt.reportID = 1
        tilt.bitSize = 9
        tilt.logicalMaximum = 360
        tilt.physicalMaximum = 360
        XCTAssertTrue(tilt.isRecognized(product: "las", primaryUsagePage: 0x20, primaryUsage: 0x8A))
        XCTAssertFalse(tilt.isRecognized(product: "USB inclinometer", primaryUsagePage: 0x20, primaryUsage: 0x8A))
        XCTAssertFalse(tilt.isRecognized(product: nil, primaryUsagePage: 0x20, primaryUsage: 0x8A))
        tilt.reportID = 2
        XCTAssertFalse(tilt.isRecognized(product: "las", primaryUsagePage: 0x20, primaryUsage: 0x8A))
    }

    func testDescriptorRejectsMalformedOrNonScalarMetadata() {
        let changes: [(inout NativeAngleElementDescriptor) -> Void] = [
            { $0.bitSize = 0 }, { $0.bitSize = 33 }, { $0.reportCount = 2 },
            { $0.isRelative = true }, { $0.isArray = true },
            { $0.logicalMaximum = $0.logicalMinimum },
            { $0.bitSize = 8; $0.logicalMaximum = 256 },
            { $0.physicalMinimum = 180; $0.physicalMaximum = 0 },
            { $0.unit = 0x11 }, { $0.unitExponent = 0x10 }
        ]
        for change in changes {
            var descriptor = hingeDescriptor()
            change(&descriptor)
            XCTAssertFalse(descriptor.isRecognized(product: nil, primaryUsagePage: 0x20, primaryUsage: 0xE4))
        }
    }

    func testDescriptorConvertsPhysicalDegreesAndRejectsOutOfRangeValues() {
        var descriptor = hingeDescriptor()
        descriptor.logicalMinimum = 100
        descriptor.logicalMaximum = 1_100
        descriptor.physicalMinimum = 0
        descriptor.physicalMaximum = 180
        descriptor.unit = 0x14
        XCTAssertEqual(descriptor.degrees(from: 600), 90)
        XCTAssertEqual(descriptor.degrees(from: 100), 0)
        XCTAssertEqual(descriptor.degrees(from: 1_100), 180)
        XCTAssertNil(descriptor.degrees(from: 99))
        XCTAssertNil(descriptor.degrees(from: 1_101))
        descriptor.physicalMaximum = 360
        XCTAssertNil(descriptor.degrees(from: 1_100))
    }

    func testDescriptorConvertsSignedDecimalExponentsAndRadians() {
        var descriptor = hingeDescriptor()
        descriptor.logicalMaximum = 18_000
        descriptor.physicalMaximum = 18_000
        descriptor.unitExponent = 0xE
        XCTAssertEqual(descriptor.degrees(from: 9_000), 90)
        descriptor.unitExponent = UInt32(bitPattern: -2)
        XCTAssertEqual(descriptor.degrees(from: 9_000), 90)
        descriptor.bitSize = 32
        descriptor.logicalMaximum = 314_159
        descriptor.physicalMaximum = 314_159
        descriptor.unit = 0x12
        descriptor.unitExponent = 0xB
        XCTAssertEqual(descriptor.degrees(from: 157_080) ?? .nan, 90, accuracy: 0.001)
    }

    private func hingeDescriptor() -> NativeAngleElementDescriptor {
        NativeAngleElementDescriptor(
            usagePage: 0x20, usage: 0x05E1, type: 257, reportID: 0,
            bitSize: 16, reportCount: 1, logicalMinimum: 0, logicalMaximum: 180,
            physicalMinimum: 0, physicalMaximum: 180, unit: 0, unitExponent: 0,
            isRelative: false, isArray: false
        )
    }

    private func mainQueueBarrier() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

private final class SensorTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval
    private var reads = 0
    private var observers: [(Int, XCTestExpectation)] = []

    init(_ value: TimeInterval) { self.value = value }

    func read() -> TimeInterval {
        lock.lock()
        reads += 1
        let due = observers.filter { $0.0 <= reads }.map(\.1)
        observers.removeAll { $0.0 <= reads }
        let result = value
        lock.unlock()
        due.forEach { $0.fulfill() }
        return result
    }

    func set(_ value: TimeInterval) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func observeNextReads(_ count: Int, fulfilling expectation: XCTestExpectation) {
        lock.lock()
        observers.append((reads + count, expectation))
        lock.unlock()
    }
}

private final class SensorReadGate: @unchecked Sendable {
    let started = XCTestExpectation(description: "blocking read entered")
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var waiting = false
    private var released = false
    private var timedOut = false

    var isWaiting: Bool { lock.withLock { waiting } }
    var didTimeOut: Bool { lock.withLock { timedOut } }

    func wait() -> Bool {
        lock.withLock { waiting = true }
        started.fulfill()
        let result = semaphore.wait(timeout: .now() + 3)
        lock.withLock {
            waiting = false
            timedOut = result == .timedOut
        }
        return result == .success
    }

    func release() {
        let shouldSignal = lock.withLock {
            if released { return false }
            released = true
            return true
        }
        if shouldSignal { semaphore.signal() }
    }
}

private struct SensorReadStep: Sendable {
    let value: Double?
    let gate: SensorReadGate?
    init(_ value: Double?, gate: SensorReadGate? = nil) {
        self.value = value
        self.gate = gate
    }
}

private final class SensorTestSource: NativeAngleSource, @unchecked Sendable {
    let closed = XCTestExpectation(description: "source closed")
    private let lock = NSLock()
    private let steps: [SensorReadStep]
    private let journal: SensorOperationJournal
    private var reads = 0
    private var closes = 0

    init(_ steps: [SensorReadStep], journal: SensorOperationJournal = .init()) {
        self.steps = steps
        self.journal = journal
    }

    var readCount: Int { lock.withLock { reads } }
    var closeCount: Int { lock.withLock { closes } }

    func readAngle() -> Double? {
        journal.begin("read")
        defer { journal.end("read") }
        let step: SensorReadStep? = lock.withLock {
            let index = reads
            reads += 1
            return steps.indices.contains(index) ? steps[index] : nil
        }
        guard let step else { return nil }
        if let gate = step.gate, !gate.wait() { return nil }
        return step.value
    }

    func close() {
        journal.begin("close")
        let firstClose = lock.withLock {
            closes += 1
            return closes == 1
        }
        journal.end("close")
        if firstClose { closed.fulfill() }
    }
}

private final class SensorTestFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let sources: [SensorTestSource?]
    private let journal: SensorOperationJournal
    private let attempts: [Int: XCTestExpectation]
    private var count = 0

    init(_ sources: [SensorTestSource?], journal: SensorOperationJournal = .init(), attempts: [Int: XCTestExpectation] = [:]) {
        self.sources = sources
        self.journal = journal
        self.attempts = attempts
    }

    var attemptCount: Int { lock.withLock { count } }

    func make() -> (any NativeAngleSource)? {
        journal.begin("factory")
        let (source, notification): (SensorTestSource?, XCTestExpectation?) = lock.withLock {
            let index = count
            count += 1
            return (sources.indices.contains(index) ? sources[index] : nil, attempts[count])
        }
        journal.end("factory")
        notification?.fulfill()
        return source
    }
}

private final class SensorOperationJournal: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [String] = []
    private var active = 0
    private var maximumActive = 0
    private var ranOnMain = false

    var events: [String] { lock.withLock { recordedEvents } }
    var usedMainThread: Bool { lock.withLock { ranOnMain } }
    var maximumConcurrentOperations: Int { lock.withLock { maximumActive } }

    func begin(_ operation: String) {
        lock.withLock {
            active += 1
            maximumActive = max(maximumActive, active)
            ranOnMain = ranOnMain || Thread.isMainThread
            recordedEvents.append("\(operation).begin")
        }
    }

    func end(_ operation: String) {
        lock.withLock {
            recordedEvents.append("\(operation).end")
            active -= 1
        }
    }
}
