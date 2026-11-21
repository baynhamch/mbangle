#if DEBUG
import Foundation

/// Explicit automation fixtures. This entire implementation is absent from Release builds.
@MainActor
enum UITestConfiguration {
    static func makeStoreIfRequested() -> AlignmentStore? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--mbangle-ui-testing") else { return nil }
        guard let mode = SensorMode(rawValue: process.environment["MBANGLE_UI_TEST_SENSOR"] ?? "") else {
            preconditionFailure("UI tests must explicitly select an unavailable or raw104 sensor fixture.")
        }
        return AlignmentStore(
            defaults: MemoryUITestDefaults(),
            sensor: FixtureSensor(mode: mode),
            // A frozen test clock makes a static fixture fresh without timers or hardware.
            now: { 0 },
            automaticallyMonitorFreshness: false
        )
    }

    private enum SensorMode: String {
        case unavailable, raw104
    }

    private final class FixtureSensor: AlignmentSensor {
        var onAngle: ((Double?) -> Void)?
        private(set) var isAvailable = false
        private(set) var latestRawAngle: Double?
        private let mode: SensorMode

        init(mode: SensorMode) {
            self.mode = mode
        }

        func start() {
            latestRawAngle = mode == .raw104 ? 104 : nil
            isAvailable = latestRawAngle != nil
            onAngle?(latestRawAngle)
        }

        func stop() {
            latestRawAngle = nil
            isAvailable = false
            onAngle?(nil)
        }
    }
}

/// Only this test store's dictionary is read or written; calibration never reaches a defaults domain.
private nonisolated final class MemoryUITestDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    // Empty preferences exercise the same first-launch defaults as the real app.
    private var values: [String: Any] = [:]

    init() {
        // Even inherited operations are isolated from the application's standard defaults.
        super.init(suiteName: "mbangle.ui-tests.\(UUID().uuidString)")!
    }

    override func object(forKey defaultName: String) -> Any? {
        lock.withLock { values[defaultName] }
    }

    override func double(forKey defaultName: String) -> Double {
        lock.withLock { (values[defaultName] as? NSNumber)?.doubleValue ?? 0 }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func set(_ value: Double, forKey defaultName: String) {
        lock.withLock { values[defaultName] = value }
    }

    override func removeObject(forKey defaultName: String) {
        lock.withLock { _ = values.removeValue(forKey: defaultName) }
    }
}
#endif
