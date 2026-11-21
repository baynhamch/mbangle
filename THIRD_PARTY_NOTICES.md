# Third-party notices

## Historical LidAngleSensor implementation

Earlier versions included `mbangle/LidAngleSensor.swift`, adapted from Sam Gold's
[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor).

The upstream project is licensed under the **Apache License, Version 2.0**.
The full upstream license is included in
[`licenses/LidAngleSensor-LICENSE.txt`](licenses/LidAngleSensor-LICENSE.txt).

That adaptation provided sensor discovery and angle reporting, with modifications
for smoothing, on-demand polling, and recovery. It is no longer part of the
current app sources. Earlier commits remain in Git history, so their provenance
and license are retained here.

The current `mbangle/NativeAngleSensor.swift` uses Apple HID element APIs and
descriptor metadata. Its implementation sources and hardware observations are
documented in [sensor design and provenance](docs/SENSOR_DESIGN.md). A new
implementation does not change the licensing of earlier versions.

The repository's existing [MIT license](LICENSE) is retained for original mbangle
code. Third-party code remains subject to its own license. The supplied showcase
reference, bundled Apple product photograph, and Apple product marks are not
relicensed by the source-code license. Image provenance is in [docs/ASSETS.md](docs/ASSETS.md).
