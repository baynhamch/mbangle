# mbangle

A native macOS showcase concept for internal MacBook demos, with discreet lid-angle alignment built into the product title. The interface stays focused on the MacBook; alignment feedback appears only when you ask for it.

Hold **Option (`⌥`)** while the showcase window is focused. A muted red fill moves through “MacBook Air 15″” as the lid approaches its saved position, then turns fully green within tolerance. Release Option and the title returns to normal. A hidden calibration tray provides the live angle, target, and adjustment controls.

![Examples of the title feedback in its normal, approaching-target, and on-target states](docs/title-feedback.png)

*Illustration rendered from the native view with example readings, not a live sensor capture.*

## Run locally

- **macOS 14 or later.**
- **Xcode 26 or later**, with a Swift toolchain supporting the project's main-actor isolation and concurrency settings.
- A MacBook with a compatible HID lid-angle sensor for live readings. Sensor availability depends on the machine; support is not guaranteed for every MacBook model. The showcase itself also runs without a sensor.

Open `mbangle.xcodeproj`, select the **mbangle** scheme and **My Mac** destination, then Run. If Xcode requests signing configuration, select your own team under **Signing & Capabilities**.

The project has been built and tested with Xcode 27.2.

The app opens a regular macOS window. Its controls and shortcuts operate inside that window; it does not overlay other apps or register a global shortcut.

## First-use calibration

1. Move the MacBook lid to the physical position you want to save.
2. Focus the showcase window and press **`⌃⌥⇧L`** to open the alignment tray. Alternatively, hold Option and click the small line at the bottom of the window.
3. Wait for a live reading, then choose **Set current angle** or press **C**.
4. Press **Escape** to close the tray. Hold Option whenever you want to check alignment against that position.

The saved target persists across launches. The default tolerance is **±0.5°**. Red fill grows across a 10° approach range and retains a small 8% fill when farther away; green means the lid is within tolerance. The tray also gives written “Open lid” or “Close lid” guidance.

| Control | Action |
| --- | --- |
| Hold `⌥` alone | Show momentary title feedback and the bottom reveal line |
| Click the reveal line | Open the alignment tray |
| `⌃⌥⇧L` | Toggle the tray while the showcase is focused |
| **C** / **Set current angle** | Save the current reading while the tray is open |
| **↑ / ↓** | Adjust the displayed target by 0.1° |
| **⇧↑ / ⇧↓** | Adjust the displayed target by 1.0° |
| **Escape** | Dismiss alignment feedback and the tray |
| **Done**, tray handle, or background | Close the tray |

Moving focus away from the showcase or opening a detail sheet clears alignment feedback. Polling runs only while the title feedback or calibration tray is active. Releasing Option keeps polling active if the tray is still open.

## Angle convention and settings

The displayed angle is **180° minus the raw sensor angle**: a sensor reading of **104° displays as 76°**. Target adjustments use these displayed degrees.

Existing calibration is preserved. The `targetAngle` preference remains stored in raw sensor degrees, and the app converts it when displaying or saving a target. An existing raw target of 104° therefore becomes a displayed target of 76° without changing the desired physical lid position. Before calibration, the default raw target is 130°, displayed as 50°.

Settings are stored locally in macOS `UserDefaults` under `com.nconanthiley.mbangle`:

| Key | Meaning | Default |
| --- | --- | --- |
| `targetAngle` | Saved target in raw sensor degrees | 130° raw / 50° displayed |
| `toleranceDegrees` | Allowed difference from the target | 0.5° |

To change tolerance, quit the app, run the following, then reopen it:

```sh
defaults write com.nconanthiley.mbangle toleranceDegrees -float 0.3
```

When no supported sensor is found, the tray shows **Sensor unavailable**. A failed or invalid read immediately clears the angle and green feedback. If samples stop arriving, a one-second freshness limit prevents the old reading from being used for alignment or calibration.

While feedback is open, the app retries sensor discovery at most once per second. Recovery starts with a new reading, without blending in the pre-failure angle. Closing all feedback stops polling and retries and closes the sensor connection. Sleep dismisses feedback; the next reveal after waking reconnects from scratch. Missing readings never become simulated values.

The decimal display and 0.1° target steps are interface precision, not a claim of 0.1° hardware measurement accuracy.

## Showcase content

The layout uses native SwiftUI text, cards, detail sheets, and controls. The main card uses bundled, higher-resolution Apple product photography. The app icon is an original angle mark. See [asset sources](docs/ASSETS.md).

Product descriptions, prices, and lease wording are **demonstration content from the supplied reference**, not a live offer or catalog. Pricing, comparison, upgrade, and disclaimer cards open local detail sheets. The finish dots are a static legend. There is no checkout, account, networking, or telemetry; sensor readings and calibration stay on the Mac.

## Source map

| File | Responsibility |
| --- | --- |
| [`mbangleApp.swift`](mbangle/mbangleApp.swift) | App entry point and showcase window |
| [`ShowcaseView.swift`](mbangle/ShowcaseView.swift) | Product layout, detail sheets, hidden handle, and calibration tray |
| [`AlignmentTitleView.swift`](mbangle/AlignmentTitleView.swift) | Title-masked red/green feedback |
| [`AlignmentStore.swift`](mbangle/AlignmentStore.swift) | Calibration, angle conversion, feedback state, and polling lifecycle |
| [`LidAngleSensor.swift`](mbangle/LidAngleSensor.swift) | IOKit HID discovery and smoothed sensor readings |
| [`AppDelegate.swift`](mbangle/AppDelegate.swift) | Window-local keyboard handling and lifecycle cleanup |
| [`mbangleTests.swift`](mbangleTests/mbangleTests.swift) | Hardware-independent model tests |

`HUDPanel.swift` and `GlobalHotKey.swift` are retained from the earlier floating-HUD implementation, but are not instantiated by the current app.

## Tests

The tests use injected sensors, HID transports, clocks, and isolated preferences. They cover calibration persistence, the 104° → 76° conversion, adjustment bounds, direction and tolerance, title fill, and overlapping tray/Option-hold lifetimes. Failure tests cover stale readings, blocked stale calibration, unavailable devices, throttled reconnection, smoothing reset, and stopping all work when feedback closes.

Run the `mbangleTests` target in Xcode, or from the repository root:

```sh
xcodebuild \
  -project mbangle.xcodeproj \
  -scheme mbangle \
  -destination 'platform=macOS' \
  -only-testing:mbangleTests \
  test
```

These tests exercise the app's logic without requiring a lid-angle sensor. Before presenting, rehearse on the intended MacBook: calibrate, move the lid away and back while holding Option, release it, switch apps, and repeat after sleep/wake. A passing automated test does not verify physical sensor accuracy.

## Acknowledgments

The sensor implementation is adapted from Sam Gold's [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor). See [third-party notices](THIRD_PARTY_NOTICES.md) for attribution and license details.
