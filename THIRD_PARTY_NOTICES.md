# Third-party notices

## LidAngleSensor

`mbangle/LidAngleSensor.swift` is adapted from Sam Gold's
[LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor).

The upstream project is licensed under the **Apache License, Version 2.0**.
The full upstream license is included in
[`licenses/LidAngleSensor-LICENSE.txt`](licenses/LidAngleSensor-LICENSE.txt).

This adaptation keeps sensor discovery and angle reporting, removes the original
sound-related application behavior, adds lightweight smoothing, and polls only
while alignment feedback or calibration is active.

The repository's existing [MIT license](LICENSE) is retained for original mbangle
code. Third-party code remains subject to its own license. The supplied showcase
image and Apple product marks are not relicensed by the source-code license.
