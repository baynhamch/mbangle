import Foundation
import IOKit.hid

/// Implementations are created, read, closed, and released on one serial worker.
/// A synchronous source makes slow reads and cancellation reproducible in tests.
nonisolated protocol NativeAngleSource: AnyObject {
    func readAngle() -> Double?
    func close()
}

@MainActor
final class NativeAngleSensor: AlignmentSensor {
    var onAngle: ((Double?) -> Void)?
    private(set) var isAvailable = false
    private(set) var latestRawAngle: Double?
    private(set) var latestSampleTime: TimeInterval?

    private let worker: NativeAngleWorker
    private let now: @Sendable () -> TimeInterval
    private var session: NativeAngleSession?
    private var average: Double?

    convenience init() {
        self.init(sourceFactory: { HIDAngleSource.discover() })
    }

    init(
        sourceFactory: @escaping @Sendable () -> (any NativeAngleSource)?,
        pollingInterval: TimeInterval = 1.0 / 30.0,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.now = now
        worker = NativeAngleWorker(factory: sourceFactory, interval: pollingInterval, now: now)
    }

    deinit {
        if let session {
            session.cancel()
            worker.stop(session)
        }
    }

    func start() {
        guard session == nil else { return }
        invalidate()
        let startedSession = NativeAngleSession()
        session = startedSession
        worker.start(startedSession) { [weak self] raw, attemptedAt in
            DispatchQueue.main.async { [weak self] in
                self?.receive(raw, attemptedAt: attemptedAt, session: startedSession)
            }
        }
    }

    func stop() {
        if let session {
            session.cancel()
            worker.stop(session)
        }
        session = nil
        invalidate()
        onAngle?(nil)
    }

    private func receive(_ raw: Double?, attemptedAt: TimeInterval, session: NativeAngleSession) {
        guard self.session === session, session.isActive else { return }
        let age = now() - attemptedAt
        guard let raw, raw.isFinite, (0...180).contains(raw),
              age.isFinite, age >= 0, age < 1 else {
            invalidate()
            onAngle?(nil)
            return
        }
        latestRawAngle = raw
        latestSampleTime = attemptedAt
        isAvailable = true
        average = average.map { $0 + 0.35 * (raw - $0) } ?? raw
        onAngle?(average)
    }

    private func invalidate() {
        isAvailable = false
        latestRawAngle = nil
        latestSampleTime = nil
        average = nil
    }
}

/// Only cancellation crosses queues; all device state stays on the worker.
nonisolated private final class NativeAngleSession: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func cancel() {
        lock.lock()
        active = false
        lock.unlock()
    }
}

/// The unchecked conformance covers queue confinement, not concurrent access.
nonisolated private final class NativeAngleWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "angle-sensor.io", qos: .userInitiated)
    private let factory: @Sendable () -> (any NativeAngleSource)?
    private let now: @Sendable () -> TimeInterval
    private let interval: TimeInterval
    private var session: NativeAngleSession?
    private var source: (any NativeAngleSource)?
    private var nextDiscoveryAt = -Double.infinity

    init(
        factory: @escaping @Sendable () -> (any NativeAngleSource)?,
        interval: TimeInterval,
        now: @escaping @Sendable () -> TimeInterval
    ) {
        self.factory = factory
        self.now = now
        self.interval = interval.isFinite && interval > 0 ? interval : 1.0 / 30.0
    }

    func start(_ session: NativeAngleSession, deliver: @escaping @Sendable (Double?, TimeInterval) -> Void) {
        queue.async {
            guard session.isActive else { return }
            self.closeSource()
            self.session = session
            self.poll(session, deliver: deliver)
        }
    }

    func stop(_ session: NativeAngleSession) {
        queue.async {
            guard self.session === session else { return }
            self.closeSource()
            self.session = nil
        }
    }

    private func poll(_ session: NativeAngleSession, deliver: @escaping @Sendable (Double?, TimeInterval) -> Void) {
        guard self.session === session, session.isActive else { return }
        let currentTime = now()
        if source == nil, currentTime >= nextDiscoveryAt {
            nextDiscoveryAt = currentTime + 1
            source = factory()
            if source != nil {
                // A healthy session may reopen immediately for another brief peek.
                nextDiscoveryAt = -Double.infinity
            }
            guard session.isActive else {
                closeSource()
                return
            }
            if source == nil { deliver(nil, currentTime) }
        }
        if let source {
            // Timestamp the attempt: unchanged HID values may retain an old HID timestamp.
            let attemptedAt = now()
            let raw = source.readAngle()
            guard session.isActive else {
                closeSource()
                return
            }
            if let raw, raw.isFinite, (0...180).contains(raw) {
                deliver(raw, attemptedAt)
            } else {
                closeSource()
                nextDiscoveryAt = max(nextDiscoveryAt, now() + 1)
                deliver(nil, attemptedAt)
            }
        }
        // Schedule only after the synchronous read finishes: no queued read backlog.
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.poll(session, deliver: deliver)
        }
    }

    private func closeSource() {
        source?.close()
        source = nil
    }
}

/// Metadata is explicit so acceptance and unit conversion can be tested without HID hardware.
nonisolated struct NativeAngleElementDescriptor: Sendable {
    var usagePage: UInt32
    var usage: UInt32
    var type: UInt32
    var reportID: UInt32
    var bitSize: UInt32
    var reportCount: UInt32
    var logicalMinimum: Int
    var logicalMaximum: Int
    var physicalMinimum: Int
    var physicalMaximum: Int
    var unit: UInt32
    var unitExponent: UInt32
    var isRelative: Bool
    var isArray: Bool

    func isRecognized(product: String?, primaryUsagePage: UInt32, primaryUsage: UInt32) -> Bool {
        guard usagePage == 0x20, primaryUsagePage == 0x20,
              !isRelative, !isArray, reportCount == 1, (1...32).contains(bitSize),
              hasValidLogicalRange, conversionFactor != nil,
              physicalMinimum < physicalMaximum || (physicalMinimum == 0 && physicalMaximum == 0) else {
            return false
        }
        // USB HUTRR92 identifies the interior hinge angle, in degrees, by these usages.
        // https://usb.org/sites/default/files/hutrr92_-_hinge_angle_sensor.pdf
        if primaryUsage == 0xE4, usage == 0x05E1, [1, 3, 257].contains(type) {
            return true
        }
        // Independently measured on this Mac. Generic orientation/tilt is insufficient.
        return product == "las" && primaryUsage == 0x8A && usage == 0x47F
            && type == 1 && reportID == 1 && bitSize == 9
            && logicalMinimum == 0 && logicalMaximum == 360
            && physicalMinimum == 0 && physicalMaximum == 360
            && unit == 0 && unitExponent == 0
    }

    func degrees(from logicalValue: Int) -> Double? {
        guard hasValidLogicalRange,
              (logicalMinimum...logicalMaximum).contains(logicalValue),
              let conversionFactor else { return nil }
        let logical = Double(logicalValue)
        let physical: Double
        if physicalMinimum == 0, physicalMaximum == 0 {
            physical = logical
        } else {
            guard physicalMinimum < physicalMaximum else { return nil }
            physical = Double(physicalMinimum)
                + (logical - Double(logicalMinimum))
                * (Double(physicalMaximum) - Double(physicalMinimum))
                / (Double(logicalMaximum) - Double(logicalMinimum))
        }
        let degrees = physical * conversionFactor
        return degrees.isFinite && (0...180).contains(degrees) ? degrees : nil
    }

    private var conversionFactor: Double? {
        let nibble = Int(unitExponent & 0xF)
        let exponent = nibble >= 8 ? nibble - 16 : nibble
        guard unitExponent <= 0xF || unitExponent == UInt32(bitPattern: Int32(exponent)) else { return nil }
        let units: Double
        switch unit {
        case 0, 0x14: units = 1 // Hinge usage default, or English rotation (degrees).
        case 0x12: units = 180 / .pi // SI rotation (radians).
        default: return nil
        }
        return pow(10, Double(exponent)) * units
    }

    private var hasValidLogicalRange: Bool {
        guard (1...32).contains(bitSize), logicalMinimum < logicalMaximum else { return false }
        let lowerBound = logicalMinimum < 0 ? -(1 << (bitSize - 1)) : 0
        let upperBound = logicalMinimum < 0 ? (1 << (bitSize - 1)) - 1 : (1 << bitSize) - 1
        return logicalMinimum >= lowerBound && logicalMaximum <= upperBound
    }

    fileprivate static func read(_ element: IOHIDElement) -> Self {
        Self(
            usagePage: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element),
            type: IOHIDElementGetType(element).rawValue, reportID: IOHIDElementGetReportID(element),
            bitSize: IOHIDElementGetReportSize(element), reportCount: IOHIDElementGetReportCount(element),
            logicalMinimum: IOHIDElementGetLogicalMin(element), logicalMaximum: IOHIDElementGetLogicalMax(element),
            physicalMinimum: IOHIDElementGetPhysicalMin(element), physicalMaximum: IOHIDElementGetPhysicalMax(element),
            unit: IOHIDElementGetUnit(element), unitExponent: IOHIDElementGetUnitExponent(element),
            isRelative: IOHIDElementIsRelative(element), isArray: IOHIDElementIsArray(element)
        )
    }
}

nonisolated private final class HIDAngleSource: NativeAngleSource {
    private var device: IOHIDDevice?
    private let element: IOHIDElement
    private let descriptor: NativeAngleElementDescriptor

    private init(device: IOHIDDevice, element: IOHIDElement, descriptor: NativeAngleElementDescriptor) {
        self.device = device
        self.element = element
        self.descriptor = descriptor
    }

    static func discover() -> HIDAngleSource? {
        // IOHIDManager.h: independent devices retain their own open/close lifecycle.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0x8)
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0x20] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return nil }
        defer { IOHIDManagerClose(manager, 0) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        var matches: [(IOHIDDevice, IOHIDElement, NativeAngleElementDescriptor)] = []
        for device in devices {
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.uint32Value ?? 0
            let usage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.uint32Value ?? 0
            // https://developer.apple.com/documentation/iokit/1588671-iohiddevicecopymatchingelements
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else { continue }
            for element in elements {
                let descriptor = NativeAngleElementDescriptor.read(element)
                if descriptor.isRecognized(product: product, primaryUsagePage: page, primaryUsage: usage) {
                    matches.append((device, element, descriptor))
                }
            }
        }
        // Ambiguous hardware is unavailable, rather than dependent on enumeration order.
        guard matches.count == 1, let (device, element, descriptor) = matches.first,
              IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { return nil }
        return HIDAngleSource(device: device, element: element, descriptor: descriptor)
    }

    func readAngle() -> Double? {
        guard let device else { return nil }
        let result = UnsafeMutablePointer<Unmanaged<IOHIDValue>>.allocate(capacity: 1)
        defer { result.deallocate() }
        // IOHIDDevice.h: 0x00020000 is GetValueWithUpdate, forcing an actual report read.
        // The ordinary input GetValue path may return only a cached value.
        // https://developer.apple.com/documentation/iokit/1588657-iohiddevicegetvalue
        let status = IOHIDDeviceGetValueWithOptions(device, element, result, 0x00020000)
        guard status == kIOReturnSuccess else { return nil }
        let value = result.pointee.takeUnretainedValue()
        guard IOHIDValueGetLength(value) >= Int((descriptor.bitSize + 7) / 8) else { return nil }
        return descriptor.degrees(from: IOHIDValueGetIntegerValue(value))
    }

    func close() {
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
    }
}
