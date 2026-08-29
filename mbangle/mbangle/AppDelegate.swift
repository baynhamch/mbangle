//
//  AppDelegate.swift
//  mbangle
//
//  Accessory app: no Dock tile, no menu bar item, no window until summoned.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let sensor = LidAngleSensor()
    private let panel = HUDPanel()
    private var hotKey: GlobalHotKey?

    private var latestAngle: Double?
    private var isVisible = false

    // MARK: Settings

    private enum Key {
        static let target = "targetAngle"
        static let tolerance = "toleranceDegrees"
    }

    /// The angle you are aligning to. Persists across launches and reboots.
    private var target: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.target)
            return stored == 0 ? 130.0 : stored
        }
        set {
            UserDefaults.standard.set(newValue.clamped(to: 0...180), forKey: Key.target)
        }
    }

    /// How close counts as "on target". Override with:
    ///   defaults write com.nick.mbangle toleranceDegrees -float 0.3
    private var tolerance: Double {
        let stored = UserDefaults.standard.double(forKey: Key.tolerance)
        return stored == 0 ? 0.5 : stored
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sensor.onAngle = { [weak self] angle in
            guard let self else { return }
            latestAngle = angle
            refresh()
        }

        panel.onKeyDown = { [weak self] event in
            self?.handle(event) ?? false
        }

        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(controlKey | optionKey | shiftKey)
        ) { [weak self] in
            self?.toggle()
        }

        if hotKey == nil {
            // Nothing else in the app is visible, so a silent failure here would
            // look identical to a working install that never responds.
            NSLog("mbangle: failed to register hotkey ⌃⌥⇧L — another app may own it")
        }
    }

    // MARK: Show / hide

    private func toggle() {
        isVisible ? hide() : show()
    }

    private func show() {
        isVisible = true
        latestAngle = nil
        refresh()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.showCentered()
        sensor.start()
    }

    private func hide() {
        isVisible = false
        sensor.stop()
        panel.orderOut(nil)
        // Hand focus back to whatever the machine was showing.
        NSApp.hide(nil)
    }

    private func refresh() {
        panel.update(angle: sensor.isAvailable ? latestAngle : nil,
                     target: target,
                     tolerance: tolerance)
    }

    // MARK: Keys

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let hasCommand = event.modifierFlags.contains(.command)
        let fineStep = event.modifierFlags.contains(.shift) ? 1.0 : 0.1

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_ANSI_C:
            // Level the lid by hand, then press C to make that the target.
            guard let latestAngle else { return true }
            target = latestAngle
            refresh()
        case kVK_UpArrow:
            target += fineStep
            refresh()
        case kVK_DownArrow:
            target -= fineStep
            refresh()
        case kVK_ANSI_Q where hasCommand:
            NSApp.terminate(nil)
        default:
            return false
        }
        return true
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
