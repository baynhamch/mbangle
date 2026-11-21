# mbangle

An independent native macOS prototype that demonstrates discreet lid-angle alignment within a product-style interface. Alignment feedback appears only when you ask for it. This is a personal demonstration project, not an Apple product or an Apple-approved tool.

Hold **Option (`⌥`)** while the showcase window is focused. A muted red fill moves through “MacBook Air 15″” as the lid approaches its saved position, then turns fully green within tolerance. Release Option and the title returns to normal. A hidden calibration tray provides the live angle, target, and adjustment controls.

An optional quiet tick and a short trackpad tap can also confirm the position.
Rest a finger on the trackpad while adjusting the lid; macOS suppresses this
feedback when the trackpad is not being touched and may suppress it according
to the current input device or system settings.

![Examples of the title feedback in its normal, approaching-target, and on-target states](docs/title-feedback.png)

*Illustration rendered from the native view with example readings, not a live sensor capture.*

## Run locally

- **macOS 14 or later.**
- **Xcode 26 or later**, with a Swift toolchain supporting the project's main-actor isolation and concurrency settings.
- A MacBook with a compatible HID lid-angle sensor for live readings. Sensor availability depends on the machine; support is not guaranteed for every MacBook model. The showcase itself also runs without a sensor.

Open `mbangle.xcodeproj`, select the **mbangle** scheme and **My Mac** destination, then Run. If Xcode requests signing configuration, select your own team under **Signing & Capabilities**.

The project has been built and tested with Xcode 27.2.

The app opens a regular macOS window. Its controls and shortcuts operate inside that window; it does not overlay other apps or register a global shortcut.

## First use: 76° target

Fresh installations start with a **76° target** and **±0.5° tolerance**. Focus the showcase window, hold **Option (`⌥`)**, and move the lid until the title turns green. No calibration is needed to use the default target on a compatible MacBook.

Previously saved targets are preserved when updating the app. To choose a different target, use the optional calibration below.

### Optional calibration

1. Move the MacBook lid to the physical position you want to save.
2. Focus the showcase window and press **`⌃⌥⇧L`** to open the alignment tray. Alternatively, hold Option and click the small line at the bottom of the window.
3. Let the lid settle, then choose **Set current angle** or press **C**. Calibration rounds and saves the latest valid raw sensor reading, rather than the smoothed display value.
4. Press **Escape** to close the tray. Hold Option whenever you want to check alignment against that position.

The saved target persists across launches. The default and minimum tolerance is **±0.5°**. Targets use whole degrees, matching the raw readings from the observed Mac sensor profile. Red fill grows across a 10° approach range and retains a small 8% fill when farther away; green means the smoothed reading is within tolerance. The tray also gives written “Open lid” or “Close lid” guidance.

| Control | Action |
| --- | --- |
| Hold `⌥` alone | Show momentary title feedback and the bottom reveal line |
| Click the reveal line | Open the alignment tray |
| `⌃⌥⇧L` | Toggle the tray while the showcase is focused |
| **C** / **Set current angle** | Save the current reading while the tray is open |
| **↑ / ↓**, or the **− / +** buttons | Adjust the displayed target by 1° |
| **Escape** | Dismiss alignment feedback and the tray |
| **Done**, tray handle, or background | Close the tray |

Moving focus away from the showcase or opening a detail sheet clears alignment feedback. Polling runs only while the title feedback or calibration tray is active. Releasing Option keeps polling active if the tray is still open.

Open **mbangle → Settings…** (**⌘,**) to switch **Confirmation sound** and
**Trackpad tap** on or off independently. Both start enabled, and your choices
persist across launches. **Try feedback** previews only the enabled cues; it is
disabled when both are off. The sound is an original 80 ms tick played quietly
through the current audio output, following its volume and mute setting.
Turning either cue off leaves the visual alignment feedback available.

The trackpad confirmation uses Apple's public
[`NSHapticFeedbackManager` alignment pattern](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager/feedbackpattern/alignment).
Automatic sound and trackpad feedback share one confirmation event after both the raw and smoothed readings stay within
tolerance for at least 150 ms. It rearms after moving more than 0.5° beyond the
tolerance boundary, or starting a new feedback session, with a 750 ms minimum
interval between requests. This prevents repeated cues from small fluctuations.
Feedback is limited to the focused showcase while Option feedback or the tray
is active. The system decides whether to deliver a request; see Apple's
[trackpad-contact limitation](https://developer.apple.com/documentation/appkit/nshapticfeedbackperformer/perform(_:performancetime:)).

## Angle convention and settings

The displayed angle is **180° minus the raw sensor angle**: a sensor reading of **104° displays as 76°**. Target adjustments use these displayed degrees.

The `targetAngle` preference remains stored in raw sensor degrees, and the app converts it when displaying or saving a target. An existing raw target of 104° remains a displayed target of 76°. Older fractional targets are rounded to the nearest whole raw degree and saved back on launch; exact half-degree ties round upward in raw degrees. This changes an in-range fractional target by at most 0.5°. The default raw target is 104°, displayed as 76°. An existing saved target takes precedence, including an older 130° raw / 50° displayed target.

Settings are stored locally in macOS `UserDefaults` under `com.nconanthiley.mbangle`:

| Key | Meaning | Default |
| --- | --- | --- |
| `targetAngle` | Saved target in whole raw sensor degrees | 104° raw / 76° displayed |
| `toleranceDegrees` | Allowed difference from the target, minimum 0.5° | 0.5° |
| `alignmentSoundEnabled` | Play the confirmation tick | On |
| `alignmentHapticsEnabled` | Request the trackpad alignment tap | On |

To change tolerance, quit the app, run the following, then reopen it:

```sh
defaults write com.nconanthiley.mbangle toleranceDegrees -float 1.0
```

Previously saved tolerances below 0.5°, or invalid values, are repaired to 0.5° on launch. A tolerance is an acceptance threshold, not a claim about physical measurement accuracy.

When no supported sensor is found, the tray shows **Sensor unavailable**. A failed or invalid read immediately clears the angle and green feedback. If samples stop arriving, a one-second freshness limit prevents the old reading from being used for alignment or calibration.

While feedback is open, failed sensor discovery is retried at most once per second. Recovery starts with a new reading, without blending in the pre-failure angle. Hardware discovery, reads, and cleanup run on a dedicated serial worker. Closing all feedback immediately clears the interface and stops new polling and retries; any already-running read can finish before cleanup, but its result is discarded. Sleep dismisses feedback; the next reveal after waking starts a new session. Missing readings never become simulated values.

The live reader uses macOS HID element metadata and a forced value update, with no fixed report-buffer decoder. It recognizes the measured `las` sensor profile and a limited standardized hinge-angle profile; support on additional Mac models still needs hardware verification. See [sensor design and provenance](docs/SENSOR_DESIGN.md).

On the observed Mac sensor profile, the live decimal display comes from smoothing whole-degree samples; it does not add sensor resolution. Other recognized descriptors can express fractional degrees through unit conversion. Target adjustments and saved calibration use whole degrees, rounding the latest raw reading when saving.

## Showcase content

The layout uses native SwiftUI text, cards, detail sheets, and controls. The main card uses bundled Apple product photography. The app icon is an original angle mark. See [asset sources](docs/ASSETS.md) and [third-party notices](THIRD_PARTY_NOTICES.md). The source-code license does not grant rights to Apple's photographs, product marks, or the supplied reference image; this repository does not establish permission for their redistribution or approval under an employer's policies.

Product descriptions, prices, and lease wording are **demonstration content from the supplied reference**, not a live offer or catalog. Pricing, comparison, upgrade, and disclaimer cards open local detail sheets. The finish dots are a static legend. There is no checkout, account, networking, or telemetry; sensor readings and calibration stay on the Mac.

## Source map

| File | Responsibility |
| --- | --- |
| [`mbangleApp.swift`](mbangle/mbangleApp.swift) | App entry point and showcase window |
| [`ShowcaseView.swift`](mbangle/ShowcaseView.swift) | Product layout, detail sheets, hidden handle, and calibration tray |
| [`AlignmentTitleView.swift`](mbangle/AlignmentTitleView.swift) | Title-masked red/green feedback |
| [`AlignmentStore.swift`](mbangle/AlignmentStore.swift) | Calibration, angle conversion, feedback state, and polling lifecycle |
| [`AlignmentHapticGate.swift`](mbangle/AlignmentHapticGate.swift) | Stable alignment confirmation, repeat suppression, and haptic cooldown |
| [`AlignmentFeedback.swift`](mbangle/AlignmentFeedback.swift) | Saved sound/trackpad preferences and output routing |
| [`FeedbackSettingsView.swift`](mbangle/FeedbackSettingsView.swift) | Native Settings switches and feedback preview |
| [`NativeAngleSensor.swift`](mbangle/NativeAngleSensor.swift) | Background HID element discovery, reading, unit conversion, and session handling |
| [`AppDelegate.swift`](mbangle/AppDelegate.swift) | Window-local keyboard handling and lifecycle cleanup |
| [`mbangleTests.swift`](mbangleTests/mbangleTests.swift) | Hardware-independent model tests |

## Tests

The model tests use injected sensors, source factories, clocks, and isolated preferences. They cover calibration persistence, the 104° → 76° conversion, whole-degree target migration, raw-sample calibration, adjustment bounds, direction and tolerance, title fill, and overlapping tray/Option-hold lifetimes. Haptic tests cover stable raw/display agreement, jitter suppression, cooldown, target changes, and cancellation across stale readings or closed feedback. These tests verify when a tap is requested, not whether hardware physically delivers it. Worker tests exercise delayed and failed reads, session cancellation, reconnection, serialization, and metadata conversion. Freshness follows the acquisition time, so delayed delivery cannot renew an old reading's calibration deadline.

The UI tests launch explicit Debug-only sensor fixtures with isolated preferences. They exercise the first-launch 76° target, unavailable hardware, calibration, keyboard controls, tray dismissal, and accessible title feedback during Option hold/release without depending on the host Mac's sensor. A relaunch check verifies that fixture target changes do not persist. Normal launches always use real sensor discovery; Release builds do not include the UI-test fixtures.

Run the scheme's tests in Xcode, or from the repository root:

```sh
xcodebuild \
  -project mbangle.xcodeproj \
  -scheme mbangle \
  -destination 'platform=macOS' \
  test
```

These tests exercise the app's logic without requiring a lid-angle sensor. Before presenting, rehearse on the intended MacBook: calibrate, move the lid away and back while holding Option, release it, switch apps, and repeat after sleep/wake. A passing automated test does not verify physical sensor accuracy.

## Acknowledgments

Sam Gold's [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) inspired the initial prototype, which included an adapted reader. The current app uses a replacement developed from Apple SDK interfaces, USB HID specifications, and direct device inspection. The old reader has been removed from the current app sources; earlier versions remain credited in Git history. This acknowledgment does not imply collaboration or endorsement.

The showcase interface, calibration controls, and title feedback were developed for mbangle. See [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license details.
