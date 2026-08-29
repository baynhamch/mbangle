//
//  LidAngleSensor.swift
//  mbangle
//
//  Reads the MacBook lid angle sensor over IOKit HID.
//  Derived from Sam Gold's LidAngleSensor (MIT), trimmed to angle reporting only.
//

import Foundation
import IOKit
import IOKit.hid

/// Polls the lid angle sensor and reports smoothed angle readings to a callback.
///
/// Polling only runs between `start()` and `stop()` so the app is completely
/// idle while the HUD is hidden.
final class LidAngleSensor: NSObject {

    /// Called on the main thread with each new smoothed angle, in degrees.
    var onAngle: ((Double) -> Void)?

    private(set) var isAvailable = false

    private var hidDevice: IOHIDDevice?
    private var timer: Timer?

    /// Light exponential smoothing to settle the last-digit jitter in the raw
    /// report. Heavier smoothing would lag the lid while you are moving it.
    private var smoothedAngle: Double?
    private static let smoothingFactor = 0.35
    private static let pollInterval = 1.0 / 30.0
    private static let noOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    override init() {
        hidDevice = Self.findSensor()
        super.init()
        if let hidDevice {
            IOHIDDeviceOpen(hidDevice, Self.noOptions)
        }
        isAvailable = hidDevice != nil
    }

    deinit {
        timer?.invalidate()
        if let hidDevice {
            IOHIDDeviceClose(hidDevice, Self.noOptions)
        }
    }

    // MARK: - Control

    func start() {
        guard isAvailable, timer == nil else { return }
        smoothedAngle = nil
        // Target/selector rather than a closure: Timer's block variant is
        // @Sendable and would force this non-Sendable class across an isolation
        // boundary it never actually crosses (the timer is main-run-loop only).
        let timer = Timer(
            timeInterval: Self.pollInterval,
            target: self,
            selector: #selector(poll),
            userInfo: nil,
            repeats: true
        )
        // .common so the reading keeps updating while a menu or drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    @objc private func poll() {
        guard let hidDevice, let raw = Self.readAngle(from: hidDevice) else { return }

        let smoothed: Double
        if let previous = smoothedAngle {
            smoothed = Self.smoothingFactor * raw + (1 - Self.smoothingFactor) * previous
        } else {
            smoothed = raw
        }
        smoothedAngle = smoothed
        onAngle?(smoothed)
    }

    private static func readAngle(from device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)

        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else { return nil }

        return Double(UInt16(report[2]) << 8 | UInt16(report[1]))
    }

    // MARK: - Discovery

    private static func findSensor() -> IOHIDDevice? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, noOptions)
        guard IOHIDManagerOpen(manager, noOptions) == kIOReturnSuccess else { return nil }
        defer { IOHIDManagerClose(manager, noOptions) }

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            "UsagePage": 0x0020,
            "Usage": 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }

        // Several devices can match; keep the first that actually answers a report.
        for device in devices {
            guard IOHIDDeviceOpen(device, noOptions) == kIOReturnSuccess else { continue }
            defer { IOHIDDeviceClose(device, noOptions) }
            if readAngle(from: device) != nil { return device }
        }

        return nil
    }
}
