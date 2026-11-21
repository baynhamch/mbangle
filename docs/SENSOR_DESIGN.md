# Live sensor implementation

The current reader uses macOS HID **elements**: the operating system parses the
device's report descriptor and provides a typed value for the selected element.
The application does not contain a fixed report-buffer or byte-offset decoder.

## Sources and scope

The replacement was developed from the Apple SDK interfaces, USB HID
specifications, and direct inspection of the presentation Mac's sensor:

- [Apple: HID element metadata](https://developer.apple.com/documentation/iokit/iohidelement_h)
- [Apple: copying matching elements](https://developer.apple.com/documentation/iokit/1588671-iohiddevicecopymatchingelements)
- [Apple: getting an element value](https://developer.apple.com/documentation/iokit/1588657-iohiddevicegetvalue)
- The installed SDK's `IOKit/hid/IOHIDDevice.h`, which documents
  `IOHIDDeviceGetValueWithOptions` and its force-update option.
- [USB HID 1.11](https://usb.org/sites/default/files/hid1_11.pdf), for descriptor
  bounds, units, and exponents.
- [USB HUTRR92](https://usb.org/sites/default/files/hutrr92_-_hinge_angle_sensor.pdf),
  for the standardized hinge-angle collection and data usages.

The input-element API normally allows cached values. This reader explicitly
requests an update; it does not turn an arbitrary cached value into a fresh
measurement. Acquisition time is recorded before the hardware call, then
checked again when the result reaches the interface.

## Observed Mac profile

On November 21, 2026, direct inspection of a **Mac16,8 running macOS 27.2.1**
returned the following metadata. These observations are a compatibility profile,
not a documented Apple guarantee for other models.

| Property | Observed value |
| --- | --- |
| Product name | `las` |
| Collection | Sensor page `0x20`, Device Orientation `0x8A` |
| Angle element | Sensor page `0x20`, X-axis tilt `0x047F` |
| Element type | Input miscellaneous |
| Report identifier | 1 |
| Field size/count | 9 bits / 1 value |
| Logical and physical bounds | 0–360 |
| Unit and exponent | 0 / 0 |

This complete profile distinguishes the observed lid sensor from unrelated
orientation devices. A generic tilt element alone is not enough to identify a
lid sensor. The standardized hinge collection `0xE4` and angle field `0x05E1`
have their own semantics. The recognized standard profile requires that hinge
collection as the device's primary usage; nested hinge collections under another
primary usage are not currently supported. That path still needs validation on
actual hardware. Ambiguous or unsupported devices produce an unavailable state.

## Responsiveness and data validity

One serial worker owns discovery, device access, polling, and cleanup. Hardware
calls never run on the UI thread and reads do not overlap. Closing feedback
immediately clears published readings and invalidates the session. An already
running device call may finish before cleanup, but its old result cannot revive
feedback or enter a new session.

The interface accepts raw angles from 0–180° and displays their complement.
Calibration uses the latest raw value, while the visible reading is smoothed.
The freshness deadline follows acquisition time, including time spent waiting
for hardware or delivery. A stale, invalid, or failed reading clears feedback.

## Replacement validation

Checks on November 21, 2026, using Xcode 27.2:

- All 39 model and sensor unit tests passed, including blocked reads, immediate
  dismissal, stale acquisition times, rapid restarts, and descriptor conversion.
- The Release build and strict code-signature verification passed. The Release
  binary contains the replacement reader and excludes the old reader and
  Debug-only UI-test fixtures. Signature verification is not notarization.
- A headless probe using the replacement reader received 50 real samples in two
  seconds on the observed Mac, then cleared its state on stop. The stationary
  raw reading was 98°. This is a connectivity check, not a sensor-accuracy or
  performance benchmark.
- The current working-tree credential scan reported no findings.

UI tests compiled, but were not executed for this replacement because the Mac
was locked. Physical lid movement, Option-hold feedback, and sleep/wake recovery
still need a hands-on check with the replacement. Earlier checks of the old
reader do not establish those results for the new one.

## Prototype history

Earlier commits used an adaptation of Sam Gold's `LidAngleSensor` project. That
component has been replaced in the current app sources. The earlier commits
remain in Git history, with their attribution and Apache 2.0 license retained
in [third-party notices](../THIRD_PARTY_NOTICES.md).

This document records implementation provenance. It is not a legal ownership
determination or approval to deploy the app at Apple.
