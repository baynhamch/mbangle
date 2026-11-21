//
//  LidAngleSensor.swift
//  mbangle
//
//  Reads the MacBook lid angle sensor over IOKit HID.
//  Adapted from Sam Gold's LidAngleSensor (Apache-2.0).
//  Modified for angle-only reporting, smoothing, on-demand polling, and recovery.
//  See THIRD_PARTY_NOTICES.md and licenses/LidAngleSensor-LICENSE.txt.
//

import Foundation
import IOKit
import IOKit.hid

/// Owns one connection. A failed connection or read must never produce a sample.
@MainActor
protocol LidAngleTransport: AnyObject {
    func connect() -> Bool
    func readAngle() -> Double?
    func disconnect()
}

/// Polls only while requested, and retries unavailable hardware at a bounded rate.
@MainActor
final class LidAngleSensor: NSObject {
    /// Availability is updated before every callback. Nil invalidates the last sample.
    var onAngle: ((Double?) -> Void)?
    private(set) var isAvailable = false
    /// Calibration uses this sample rather than the lagging display average.
    private(set) var latestRawAngle: Double?

    private let transport: any LidAngleTransport
    private let clock: () -> TimeInterval
    private let schedulesTimer: Bool
    private var timer: Timer?
    private var isRunning = false
    private var isConnected = false
    private var nextRetryAt: TimeInterval = 0
    private var smoothedAngle: Double?

    private static let smoothingFactor = 0.35
    private static let pollInterval = 1.0 / 30.0
    private static let retryInterval: TimeInterval = 1

    init(
        transport: (any LidAngleTransport)? = nil,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedulesTimer: Bool = true
    ) {
        self.transport = transport ?? IOKitLidAngleTransport()
        self.clock = clock
        self.schedulesTimer = schedulesTimer
        super.init()
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        nextRetryAt = clock()
        smoothedAngle = nil
        latestRawAngle = nil

        if schedulesTimer {
            // Weak capture avoids a Timer -> sensor -> Timer ownership cycle.
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        poll()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        transport.disconnect()
        isConnected = false
        smoothedAngle = nil
        nextRetryAt = 0
        publish(nil)
    }

    /// Internal so transport failures and retry timing can be checked deterministically.
    func poll() {
        guard isRunning else { return }
        let now = clock()

        if !isConnected {
            guard now >= nextRetryAt else { return }
            guard transport.connect() else {
                fail(at: now)
                return
            }
            isConnected = true
        }

        guard let raw = transport.readAngle(), raw.isFinite, (0...180).contains(raw) else {
            fail(at: now)
            return
        }

        let smoothed = smoothedAngle.map {
            Self.smoothingFactor * raw + (1 - Self.smoothingFactor) * $0
        } ?? raw
        smoothedAngle = smoothed
        publish(smoothed, rawAngle: raw)
    }

    private func fail(at time: TimeInterval) {
        transport.disconnect()
        isConnected = false
        smoothedAngle = nil
        nextRetryAt = time + Self.retryInterval
        publish(nil)
    }

    private func publish(_ sample: Double?, rawAngle: Double? = nil) {
        isAvailable = sample != nil
        latestRawAngle = rawAngle
        onAngle?(sample)
    }
}

/// The supported feature report carries its little-endian angle in bytes 1 and 2.
/// Keep this boundary separate from smoothing so malformed reports cannot enter it.
@MainActor
enum LidAngleReport {
    static func decode(_ report: [UInt8], length: Int) -> Double? {
        guard length >= 3, length <= report.count else { return nil }
        let angle = Double(UInt16(report[2]) << 8 | UInt16(report[1]))
        return (0...180).contains(angle) ? angle : nil
    }
}

@MainActor
private final class IOKitLidAngleTransport: LidAngleTransport {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var probeSample: Double?
    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    deinit {
        if let device { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
    }

    func connect() -> Bool {
        disconnect()
        let candidateManager = IOHIDManagerCreate(kCFAllocatorDefault, Self.noOptions)
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": 0x0020,
            "Usage": 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(candidateManager, matching as CFDictionary)
        guard IOHIDManagerOpen(candidateManager, Self.noOptions) == kIOReturnSuccess else {
            return false
        }
        guard let devices = IOHIDManagerCopyDevices(candidateManager) as? Set<IOHIDDevice> else {
            IOHIDManagerClose(candidateManager, Self.noOptions)
            return false
        }

        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, Self.noOptions) == kIOReturnSuccess else { continue }
            if let sample = Self.readReport(from: candidate) {
                // Retain the successful open connection and probe sample. Closing
                // and reopening here would create another point of failure.
                manager = candidateManager
                device = candidate
                probeSample = sample
                return true
            }
            IOHIDDeviceClose(candidate, Self.noOptions)
        }
        IOHIDManagerClose(candidateManager, Self.noOptions)
        return false
    }

    func readAngle() -> Double? {
        if let sample = probeSample {
            probeSample = nil
            return sample
        }
        guard let device else { return nil }
        return Self.readReport(from: device)
    }

    func disconnect() {
        probeSample = nil
        if let device { IOHIDDeviceClose(device, Self.noOptions) }
        if let manager { IOHIDManagerClose(manager, Self.noOptions) }
        device = nil
        manager = nil
    }

    private static func readReport(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess else { return nil }
        return LidAngleReport.decode(report, length: length)
    }
}
