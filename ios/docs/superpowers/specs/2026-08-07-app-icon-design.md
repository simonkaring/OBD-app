# App Icon Replacement Design

## Goal

Use the user-supplied SVG as VoltLink's iOS app icon and include it in the distributable IPA.

## Design

Rasterize the supplied 128-by-128 SVG at 1024-by-1024 pixels without changing its artwork. Replace the existing `AppIcon.appiconset/icon-1024.png`; the asset catalog already declares that universal iOS icon rendition. Rebuild the existing `build/VoltLink.ipa` from the Xcode project.

## Constraints

- Do not alter the supplied logo, colors, corner radius, or proportions.
- Do not add icon packages or dependencies.
- Verify the generated PNG dimensions and the IPA contents after archiving.
