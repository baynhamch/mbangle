import AppKit
import Combine

/// User preferences and output routing for an already-confirmed alignment.
/// Stability, cooldown, and showcase focus are checked before this is called.
@MainActor
final class AlignmentFeedback: ObservableObject {
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "alignmentSoundEnabled") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "alignmentHapticsEnabled") }
    }

    private let defaults: UserDefaults
    private let playSound: () -> Void
    private let performHaptic: () -> Void

    init(
        defaults: UserDefaults = .standard,
        playSound: (() -> Void)? = nil,
        performHaptic: (() -> Void)? = nil
    ) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: "alignmentSoundEnabled") as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: "alignmentHapticsEnabled") as? Bool ?? true

        if let playSound {
            self.playSound = playSound
        } else {
            // Load the small original sound once; playback itself is asynchronous.
            let sound = Bundle.main.url(forResource: "AlignmentTick", withExtension: "wav")
                .flatMap { NSSound(contentsOf: $0, byReference: false) }
            sound?.volume = 0.45
            self.playSound = {
                guard let sound, !sound.isPlaying else { return }
                sound.currentTime = 0
                sound.play()
            }
        }
        self.performHaptic = performHaptic ?? {
            // The current input device and settings can change between requests.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    var isAnyEnabled: Bool { soundEnabled || hapticsEnabled }

    func confirmAlignment() {
        if soundEnabled { playSound() }
        if hapticsEnabled { performHaptic() }
    }

    /// An explicit Settings button press tests exactly the enabled outputs.
    func preview() {
        confirmAlignment()
    }
}
