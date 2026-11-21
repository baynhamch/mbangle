import Combine
import Foundation

/// A small seam for exercising calibration without depending on MacBook hardware.
@MainActor
protocol AlignmentSensor: AnyObject {
    var onAngle: ((Double) -> Void)? { get set }
    var isAvailable: Bool { get }
    func start()
    func stop()
}

extension LidAngleSensor: AlignmentSensor {}

/// Shared state for the alignment tray and momentary title feedback.
/// The sensor runs only while at least one of those presentations is active.
@MainActor
final class AlignmentStore: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var isPeeking = false
    @Published private(set) var angle: Double?
    @Published private(set) var target: Double
    @Published private(set) var tolerance: Double
    @Published private(set) var isSensorAvailable: Bool

    private let defaults: UserDefaults
    private let sensor: any AlignmentSensor

    init(defaults: UserDefaults = .standard, sensor: (any AlignmentSensor)? = nil) {
        self.defaults = defaults
        self.sensor = sensor ?? LidAngleSensor()
        isSensorAvailable = self.sensor.isAvailable

        // Preserve the saved target in the original sensor convention so existing
        // calibrations still identify the same physical lid position. Display the
        // complementary angle: a raw reading of 104° is shown as 76°.
        // Zero is a valid saved target, not a missing preference.
        let savedTarget = (defaults.object(forKey: "targetAngle") as? NSNumber)?.doubleValue
        target = 180 - Self.normalizedTarget(savedTarget ?? 130)
        let savedTolerance = defaults.double(forKey: "toleranceDegrees")
        tolerance = savedTolerance.isFinite && savedTolerance > 0 ? savedTolerance : 0.5

        self.sensor.onAngle = { [weak self] reading in
            guard let self, self.needsReadings else { return }
            guard self.isSensorAvailable, reading.isFinite,
                  (0...180).contains(reading) else {
                self.angle = nil
                return
            }
            self.angle = 180 - reading
        }
    }

    var hasReading: Bool { angle != nil }

    var isOnTarget: Bool {
        guard let angle else { return false }
        return abs(angle - target) <= tolerance
    }

    /// The title fills as the lid approaches its saved target, reaching full width
    /// anywhere inside tolerance. It is absent unless the peek key is held.
    var titleFillFraction: Double {
        guard isPeeking, isSensorAvailable, let angle else { return 0 }
        if isOnTarget { return 1 }
        let distanceOutsideTolerance = max(0, abs(angle - target) - tolerance)
        return min(1, max(0.08, 1 - distanceOutsideTolerance / 10))
    }

    var correction: String {
        guard let angle else {
            return isSensorAvailable ? "Waiting for sensor…" : "Sensor unavailable"
        }
        if isOnTarget { return "On target" }
        // Opening the lid increases its raw sensor angle and decreases the
        // complementary angle shown by this interface.
        let direction = angle > target ? "Open lid" : "Close lid"
        return String(format: "%@ %.1f°", direction, abs(angle - target))
    }

    func show() {
        guard !isExpanded else { return }
        let wasActive = needsReadings
        isExpanded = true
        startIfNeeded(wasActive: wasActive)
    }

    func hide() {
        guard isExpanded else { return }
        isExpanded = false
        stopIfInactive()
    }

    func toggle() {
        isExpanded ? hide() : show()
    }

    func beginPeek() {
        guard !isPeeking else { return }
        let wasActive = needsReadings
        isPeeking = true
        startIfNeeded(wasActive: wasActive)
    }

    func endPeek() {
        guard isPeeking else { return }
        isPeeking = false
        stopIfInactive()
    }

    /// Clear both presentations when the app loses focus or the window closes.
    func dismiss() {
        guard needsReadings else { return }
        isExpanded = false
        isPeeking = false
        stopIfInactive()
    }

    func adjustTarget(by step: Double) {
        guard step.isFinite else { return }
        saveTarget(target + step)
    }

    func setCurrentAsTarget() {
        guard isExpanded, let angle else { return }
        saveTarget(angle)
    }

    private var needsReadings: Bool { isExpanded || isPeeking }

    private func startIfNeeded(wasActive: Bool) {
        guard !wasActive else { return }
        angle = nil
        isSensorAvailable = sensor.isAvailable
        sensor.start()
    }

    private func stopIfInactive() {
        guard !needsReadings else { return }
        sensor.stop()
        angle = nil
    }

    private func saveTarget(_ value: Double) {
        target = Self.normalizedTarget(value)
        defaults.set(180 - target, forKey: "targetAngle")
    }

    private static func normalizedTarget(_ value: Double) -> Double {
        guard value.isFinite else { return 130 }
        return min(max(value, 0), 180)
    }
}
