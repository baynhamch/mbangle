import Combine
import Foundation

/// A small seam for exercising calibration without depending on MacBook hardware.
@MainActor
protocol AlignmentSensor: AnyObject {
    /// A nil sample immediately invalidates the previous reading.
    var onAngle: ((Double?) -> Void)? { get set }
    var isAvailable: Bool { get }
    /// The unsmoothed sample associated with the latest valid callback.
    /// Cleared when the sensor stops or a read fails.
    var latestRawAngle: Double? { get }
    /// Monotonic time when acquisition began, so delayed delivery cannot refresh old data.
    var latestSampleTime: TimeInterval? { get }
    func start()
    func stop()
}

extension AlignmentSensor {
    /// Synchronous test inputs can use the receiving store's injected clock.
    var latestSampleTime: TimeInterval? { nil }
}

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

    /// Emitted once when fresh raw and displayed readings settle on target.
    /// The app decides whether its current window can deliver sound or a haptic.
    var onAlignmentReached: (() -> Void)?

    private let defaults: UserDefaults
    private let sensor: any AlignmentSensor
    private let now: () -> TimeInterval
    private let automaticallyMonitorFreshness: Bool
    private var lastReadingAt: TimeInterval?
    private var freshnessTimer: Timer?
    private var hapticGate = AlignmentHapticGate()
    /// Delivery time is separate from acquisition time: queued samples must
    /// never cause back-to-back requests when the main thread becomes available.
    private var lastHapticRequestAt: TimeInterval?
    static let readingLifetime: TimeInterval = 1
    private static let defaultRawTarget = 104.0 // Displayed target: 76°.
    private static let minimumTolerance = 0.5

    init(
        defaults: UserDefaults = .standard,
        sensor: (any AlignmentSensor)? = nil,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        automaticallyMonitorFreshness: Bool = true
    ) {
        self.defaults = defaults
        self.sensor = sensor ?? NativeAngleSensor()
        self.now = now
        self.automaticallyMonitorFreshness = automaticallyMonitorFreshness
        isSensorAvailable = self.sensor.isAvailable

        // Store whole degrees in the original sensor convention. Round in raw
        // space on both load and save so half-degree ties migrate consistently.
        // A raw target of 104° is still displayed as 76°; zero remains valid.
        let targetPreference = defaults.object(forKey: "targetAngle")
        let savedTarget = (targetPreference as? NSNumber)?.doubleValue
        let rawTarget = Self.normalizedRawTarget(savedTarget ?? Self.defaultRawTarget)
        target = 180 - rawTarget
        if targetPreference != nil, savedTarget != rawTarget {
            defaults.set(rawTarget, forKey: "targetAngle")
        }

        let tolerancePreference = defaults.object(forKey: "toleranceDegrees")
        let savedTolerance = (tolerancePreference as? NSNumber)?.doubleValue
        tolerance = Self.normalizedTolerance(savedTolerance ?? Self.minimumTolerance)
        if tolerancePreference != nil, savedTolerance != tolerance {
            defaults.set(tolerance, forKey: "toleranceDegrees")
        }

        self.sensor.onAngle = { [weak self] reading in
            guard let self, self.needsReadings else { return }
            guard self.sensor.isAvailable, let reading, reading.isFinite,
                  (0...180).contains(reading) else {
                self.invalidateReading()
                return
            }
            let receivedAt = self.now()
            let sampledAt = self.sensor.latestSampleTime ?? receivedAt
            guard sampledAt.isFinite, sampledAt <= receivedAt,
                  receivedAt - sampledAt < Self.readingLifetime else {
                self.invalidateReading()
                return
            }
            if let lastReadingAt = self.lastReadingAt,
               sampledAt - lastReadingAt >= Self.readingLifetime {
                self.hapticGate.reset()
            }
            self.lastReadingAt = sampledAt
            self.isSensorAvailable = true
            let displayedAngle = 180 - reading
            self.angle = displayedAngle
            guard let rawAngle = self.sensor.latestRawAngle else {
                self.hapticGate.reset()
                return
            }
            if self.hapticGate.update(
                displayedAngle: displayedAngle, rawAngle: rawAngle,
                target: self.target, tolerance: self.tolerance, at: sampledAt
            ), self.lastHapticRequestAt.map({
                receivedAt - $0 >= AlignmentHapticGate.minimumPulseInterval
            }) ?? true {
                self.lastHapticRequestAt = receivedAt
                self.onAlignmentReached?()
            }
        }
    }

    deinit {
        freshnessTimer?.invalidate()
    }

    var hasReading: Bool {
        guard angle != nil, isSensorAvailable, let lastReadingAt else { return false }
        return now() - lastReadingAt < Self.readingLifetime
    }

    var isOnTarget: Bool {
        guard hasReading, let angle else { return false }
        return abs(angle - target) <= tolerance
    }

    /// The title fills as the lid approaches its saved target, reaching full width
    /// anywhere inside tolerance. It is absent unless the peek key is held.
    var titleFillFraction: Double {
        guard isPeeking, hasReading, let angle else { return 0 }
        if isOnTarget { return 1 }
        let distanceOutsideTolerance = max(0, abs(angle - target) - tolerance)
        return min(1, max(0.08, 1 - distanceOutsideTolerance / 10))
    }

    var correction: String {
        guard hasReading, let angle else {
            return isSensorAvailable && lastReadingAt == nil ? "Waiting for sensor…" : "Sensor unavailable"
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
        refreshReadingValidity()
        guard isExpanded, hasReading, sensor.isAvailable,
              let rawAngle = sensor.latestRawAngle, rawAngle.isFinite,
              (0...180).contains(rawAngle) else { return }
        saveRawTarget(rawAngle)
    }

    /// Also checked synchronously before calibration, so a delayed timer can
    /// never make an old reading eligible to save.
    func refreshReadingValidity() {
        guard needsReadings, let lastReadingAt,
              now() - lastReadingAt >= Self.readingLifetime else { return }
        invalidateReading()
    }

    private var needsReadings: Bool { isExpanded || isPeeking }

    private func startIfNeeded(wasActive: Bool) {
        guard !wasActive else { return }
        hapticGate.reset()
        angle = nil
        lastReadingAt = nil
        isSensorAvailable = sensor.isAvailable
        if automaticallyMonitorFreshness {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshReadingValidity() }
            }
            RunLoop.main.add(timer, forMode: .common)
            freshnessTimer = timer
        }
        sensor.start()
    }

    private func stopIfInactive() {
        guard !needsReadings else { return }
        hapticGate.reset()
        freshnessTimer?.invalidate()
        freshnessTimer = nil
        sensor.stop()
        angle = nil
        lastReadingAt = nil
    }

    private func invalidateReading() {
        hapticGate.reset()
        angle = nil
        lastReadingAt = nil
        isSensorAvailable = false
    }

    private func saveTarget(_ value: Double) {
        saveRawTarget(180 - value)
    }

    private func saveRawTarget(_ value: Double) {
        let rawTarget = Self.normalizedRawTarget(value)
        let displayedTarget = 180 - rawTarget
        if displayedTarget != target {
            hapticGate.reset()
        }
        target = displayedTarget
        defaults.set(rawTarget, forKey: "targetAngle")
    }

    private static func normalizedRawTarget(_ value: Double) -> Double {
        guard value.isFinite else { return defaultRawTarget }
        return min(max(value, 0), 180).rounded()
    }

    private static func normalizedTolerance(_ value: Double) -> Double {
        guard value.isFinite else { return minimumTolerance }
        return max(minimumTolerance, value)
    }
}
