# Visual assets

## App icon

`mbangle/Assets.xcassets/AppIcon.appiconset` contains original vector artwork
created for mbangle: a silver lid/base profile and green alignment arc on a
graphite rounded tile. The profile's 104° interior angle corresponds to the
app's displayed 76° default target. It contains no Apple logo or copied app mark.

The PNG files are rendered directly from AppKit paths and gradients, rather than
scaled from a small bitmap. The asset catalog includes all ten macOS 1×/2× slots
from 16 pt through 512 pt (16–1024 pixels). Small variants use slightly heavier
strokes to keep the mark legible.

Regenerate from the repository root with:

```sh
swift tools/generate-app-icon.swift
```

The 1024-, 128-, 32-, and 16-pixel outputs were visually inspected after generation.
Both Debug and Release use this `AppIcon` asset set for the app bundle's icon.

## MacBook Air photograph

`mbangle/Assets.xcassets/MacBookAir.imageset/MacBookAir.jpg` is an unmodified
1808 × 1680 JPEG downloaded from Apple's image CDN on November 21, 2026.
It shows a front-facing 15-inch MacBook Air in starlight with the gold/yellow
wallpaper and white background, matching the supplied showcase reference.

- [Original Apple image](https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mba15-starlight-select-202306?wid=1808&hei=1680&fmt=jpeg&qlt=95)
- [Current MacBook Air product page](https://www.apple.com/macbook-air/)
- Apple asset identifier: `mba15-starlight-select-202306` (2023 photography;
  this file is not represented as a new M5-specific photograph).
- SHA-256: `e216776f1181ef2039034eac4e0e6194043ae807f7f8f0aabae17b0aa36b46f2`

The bundled image has not been retouched, regenerated, or enlarged locally.
Whitespace may be cropped by the native SwiftUI view. The visible product bounds
are approximately x 388–1423 and y 527–1156 in the original image's top-left
coordinate system. A view crop of x 330, y 455, width 1145, height 773 leaves a
small white margin around the full laptop.

Apple owns the product photograph. It is included as a visual reference for this
independent demonstration, separately from the original app icon and app code.
Attribution does not establish permission to redistribute the photograph, and
the source-code license does not cover it or Apple's product marks.

## Supplied reference

`ShowcaseReference.imageset/ShowcaseReference.jpg` preserves the user's original
reference image. The interface's typography, cards, sheets, and controls are
native SwiftUI views, not a flattened screenshot.
