//
//  HUDPanel.swift
//  mbangle
//
//  The floating readout. Borderless, above full-screen apps, and only on screen
//  while it is being used.
//

import AppKit

// MARK: - Panel

final class HUDPanel: NSPanel {

    /// Return true to swallow the event.
    var onKeyDown: ((NSEvent) -> Bool)?

    private let readout = HUDContentView()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Above full-screen apps and other floating windows, so it is usable no
        // matter what the machine is showing.
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        // Keep it out of screen recordings and screenshots of the demo machine.
        sharingType = .none

        contentView = readout
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    func update(angle: Double?, target: Double, tolerance: Double) {
        readout.update(angle: angle, target: target, tolerance: tolerance)
    }

    /// Centers horizontally on the active screen, slightly above center.
    func showCentered() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            let size = self.frame.size
            setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.62
            ))
        }
        orderFrontRegardless()
        makeKey()
    }
}

// MARK: - Content

private final class HUDContentView: NSView {

    private let angleLabel = HUDContentView.label(size: 46, weight: .semibold)
    private let statusLabel = HUDContentView.label(size: 15, weight: .medium)
    private let targetLabel = HUDContentView.label(size: 12, weight: .regular)
    private let hintLabel = HUDContentView.label(size: 10, weight: .regular)

    init() {
        super.init(frame: .zero)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.cornerCurve = .continuous
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        targetLabel.textColor = .secondaryLabelColor
        hintLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [angleLabel, statusLabel, targetLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.setCustomSpacing(6, after: angleLabel)
        stack.setCustomSpacing(10, after: targetLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        hintLabel.stringValue = "C set target · ↑↓ adjust · esc hide"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(angle: Double?, target: Double, tolerance: Double) {
        targetLabel.stringValue = String(format: "target %.1f°", target)

        guard let angle else {
            angleLabel.stringValue = "—"
            angleLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "sensor unavailable"
            statusLabel.textColor = .secondaryLabelColor
            return
        }

        angleLabel.stringValue = String(format: "%.1f°", angle)

        let delta = angle - target
        if abs(delta) <= tolerance {
            angleLabel.textColor = .systemGreen
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "ON TARGET"
        } else {
            angleLabel.textColor = .labelColor
            statusLabel.textColor = .systemOrange
            // Angle grows as the lid opens, so a reading below target means open further.
            let direction = delta < 0 ? "▲ open" : "▼ close"
            statusLabel.stringValue = String(format: "%@ %.1f°", direction, abs(delta))
        }
    }

    private static func label(size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
        field.alignment = .center
        return field
    }
}
