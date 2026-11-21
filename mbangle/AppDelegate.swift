import AppKit
import Carbon.HIToolbox

/// All shortcuts and hold-to-peek feedback are confined to the showcase window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let alignment = AlignmentStore()
    private var keyMonitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            // A release can arrive at another window or a sheet. Always process
            // it before the key-window guard, and preserve AppKit's modifiers.
            if event.type == .flagsChanged {
                self.updatePeek(for: event)
                return event
            }
            self.alignment.endPeek() // An Option shortcut is not a held preview.
            guard self.isShowcaseWindow(event.window),
                  self.handle(event) else { return event }
            return nil
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.alignment.dismiss() }
        })
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willBeginSheetNotification] {
            lifecycleObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, self.isShowcaseWindow(notification.object as? NSWindow) else { return }
                    self.alignment.dismiss()
                }
            })
        }
        // Drop pre-sleep values and close the HID device. The next deliberate
        // reveal after wake starts a new discovery/read session.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.alignment.dismiss() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        alignment.dismiss()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
    }

    private func isShowcaseWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue == "mbangle-showcase"
    }

    private func updatePeek(for event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .option,
           NSApp.isActive,
           isShowcaseWindow(NSApp.keyWindow),
           NSApp.keyWindow?.attachedSheet == nil {
            alignment.beginPeek()
        } else {
            alignment.endPeek()
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window?.attachedSheet == nil else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if Int(event.keyCode) == kVK_ANSI_L,
           modifiers == [.control, .option, .shift] {
            if !event.isARepeat { alignment.toggle() }
            return true
        }
        guard alignment.isExpanded,
              modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape: alignment.dismiss()
        case kVK_ANSI_C: alignment.setCurrentAsTarget()
        case kVK_UpArrow: alignment.adjustTarget(by: modifiers.contains(.shift) ? 1 : 0.1)
        case kVK_DownArrow: alignment.adjustTarget(by: modifiers.contains(.shift) ? -1 : -0.1)
        default: return false
        }
        return true
    }
}
