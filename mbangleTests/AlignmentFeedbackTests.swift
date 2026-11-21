import AppKit
import Foundation
import XCTest
@testable import mbangle

@MainActor
final class AlignmentFeedbackTests: XCTestCase {
    func testBundledConfirmationTickDecodesWithShortDuration() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "AlignmentTick", withExtension: "wav"),
                                "The host app must bundle the confirmation sound.")
        let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: false),
                                  "The bundled tick must be decodable by its runtime player.")
        XCTAssertGreaterThanOrEqual(sound.duration, 0.05)
        XCTAssertLessThanOrEqual(sound.duration, 0.12)
        XCTAssertFalse(sound.isPlaying)
    }

    func testNewPreferencesEnableBothWithoutPlayingOrWritingDefaults() {
        withDefaults { defaults in
            var sounds = 0
            var haptics = 0
            let feedback = AlignmentFeedback(
                defaults: defaults,
                playSound: { sounds += 1 },
                performHaptic: { haptics += 1 }
            )

            XCTAssertTrue(feedback.soundEnabled)
            XCTAssertTrue(feedback.hapticsEnabled)
            XCTAssertTrue(feedback.isAnyEnabled)
            XCTAssertEqual(sounds, 0)
            XCTAssertEqual(haptics, 0)
            XCTAssertNil(defaults.object(forKey: "alignmentSoundEnabled"))
            XCTAssertNil(defaults.object(forKey: "alignmentHapticsEnabled"))
        }
    }

    func testConfirmationRoutesEachOutputIndependently() {
        withDefaults { defaults in
            var sounds = 0
            var haptics = 0
            let feedback = AlignmentFeedback(
                defaults: defaults,
                playSound: { sounds += 1 },
                performHaptic: { haptics += 1 }
            )

            feedback.confirmAlignment()
            XCTAssertEqual(sounds, 1)
            XCTAssertEqual(haptics, 1)

            feedback.soundEnabled = false
            XCTAssertTrue(feedback.isAnyEnabled)
            feedback.confirmAlignment()
            XCTAssertEqual(sounds, 1)
            XCTAssertEqual(haptics, 2)

            feedback.soundEnabled = true
            feedback.hapticsEnabled = false
            XCTAssertTrue(feedback.isAnyEnabled)
            feedback.confirmAlignment()
            XCTAssertEqual(sounds, 2)
            XCTAssertEqual(haptics, 2)
        }
    }

    func testBothDisabledStaySilentForConfirmationAndPreview() {
        withDefaults { defaults in
            var requests = 0
            let feedback = AlignmentFeedback(
                defaults: defaults,
                playSound: { requests += 1 },
                performHaptic: { requests += 1 }
            )
            feedback.soundEnabled = false
            feedback.hapticsEnabled = false

            XCTAssertFalse(feedback.isAnyEnabled)
            feedback.confirmAlignment()
            feedback.preview()
            XCTAssertEqual(requests, 0)
        }
    }

    func testExplicitFalsePreferencesSurviveRecreation() {
        withDefaults { defaults in
            let first = AlignmentFeedback(defaults: defaults, playSound: {}, performHaptic: {})
            first.soundEnabled = false
            first.hapticsEnabled = false
            XCTAssertEqual(defaults.object(forKey: "alignmentSoundEnabled") as? Bool, false)
            XCTAssertEqual(defaults.object(forKey: "alignmentHapticsEnabled") as? Bool, false)

            var requests = 0
            let restored = AlignmentFeedback(
                defaults: defaults,
                playSound: { requests += 1 },
                performHaptic: { requests += 1 }
            )
            XCTAssertFalse(restored.soundEnabled)
            XCTAssertFalse(restored.hapticsEnabled)
            XCTAssertFalse(restored.isAnyEnabled)
            restored.confirmAlignment()
            XCTAssertEqual(requests, 0)

            restored.soundEnabled = true
            let soundOnly = AlignmentFeedback(defaults: defaults, playSound: {}, performHaptic: {})
            XCTAssertTrue(soundOnly.soundEnabled)
            XCTAssertFalse(soundOnly.hapticsEnabled)
        }
    }

    func testExistingPreferencesAreRespectedWithoutFeedbackDuringLoad() {
        for soundEnabled in [false, true] {
            for hapticsEnabled in [false, true] {
                withDefaults { defaults in
                    defaults.set(soundEnabled, forKey: "alignmentSoundEnabled")
                    defaults.set(hapticsEnabled, forKey: "alignmentHapticsEnabled")
                    defaults.set(104.0, forKey: "targetAngle")
                    var requests = 0
                    let feedback = AlignmentFeedback(
                        defaults: defaults,
                        playSound: { requests += 1 },
                        performHaptic: { requests += 1 }
                    )

                    XCTAssertEqual(feedback.soundEnabled, soundEnabled)
                    XCTAssertEqual(feedback.hapticsEnabled, hapticsEnabled)
                    XCTAssertEqual(feedback.isAnyEnabled, soundEnabled || hapticsEnabled)
                    XCTAssertEqual(defaults.object(forKey: "alignmentSoundEnabled") as? Bool, soundEnabled)
                    XCTAssertEqual(defaults.object(forKey: "alignmentHapticsEnabled") as? Bool, hapticsEnabled)
                    XCTAssertEqual(defaults.double(forKey: "targetAngle"), 104)
                    XCTAssertEqual(requests, 0)
                }
            }
        }
    }

    func testPreviewUsesOnlyTheEnabledOutputs() {
        withDefaults { defaults in
            var sounds = 0
            var haptics = 0
            let feedback = AlignmentFeedback(
                defaults: defaults,
                playSound: { sounds += 1 },
                performHaptic: { haptics += 1 }
            )

            feedback.preview()
            XCTAssertEqual(sounds, 1)
            XCTAssertEqual(haptics, 1)
            feedback.hapticsEnabled = false
            feedback.preview()
            XCTAssertEqual(sounds, 2)
            XCTAssertEqual(haptics, 1)
            feedback.soundEnabled = false
            feedback.hapticsEnabled = true
            feedback.preview()
            XCTAssertEqual(sounds, 2)
            XCTAssertEqual(haptics, 2)
        }
    }

    func testChangingSettingsNeverPlaysFeedbackByItself() {
        withDefaults { defaults in
            var requests = 0
            let feedback = AlignmentFeedback(
                defaults: defaults,
                playSound: { requests += 1 },
                performHaptic: { requests += 1 }
            )

            feedback.soundEnabled = false
            feedback.hapticsEnabled = false
            feedback.soundEnabled = true
            feedback.hapticsEnabled = true

            XCTAssertEqual(requests, 0)
            XCTAssertEqual(defaults.object(forKey: "alignmentSoundEnabled") as? Bool, true)
            XCTAssertEqual(defaults.object(forKey: "alignmentHapticsEnabled") as? Bool, true)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "AlignmentFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
