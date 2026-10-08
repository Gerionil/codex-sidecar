# Codex Sidecar identity

The owner selected Companion (concept A) on 2026-10-08. An open C surrounds a
small detached companion. The mark was constructed for this project; remote
logo-design skill references informed the process, not the geometry.

## Assets and usage

- `sidecar-symbol.svg`: flat graphite vector master.
- `sidecar-dock.svg`: light rounded tile, graphite mark and blue companion.
- `sidecar-menu.svg`: black/transparent symbol with a tighter viewBox for 18 pt.
- `dock-preview.png`: native source-art preview.
- `system-dock-preview.png`: current-Mac NSWorkspace icon lookup rendering.
- `menu-light-preview.png` / `menu-dark-preview.png`: native SwiftUI template
  rendering on light/dark sample backgrounds, not captures of the system bar.

Palette: graphite #202123, accent #0285FF, tile #F5F5F3, edge #DCDDD9. Keep
brand colour confined to the Dock artwork; the menu-bar version is a template
and adopts the system's foreground. Keep the shape upright and proportions
fixed. No text belongs inside the app icon. Leave at least one wall thickness
of clear space around the standalone mark. Minimum standalone size: 18 pt;
menu-bar bitmaps have 18/36 pixel representations with a shared 18 pt size.
The Dock ICNS contains standard 16–512 pt sizes at 1x/2x, up to 1024 pixels.

## Regeneration and integration

From the repository root:

```sh
swift scripts/generate-icons.swift
scripts/package-app.sh
```

The native generator mirrors the SVG geometry using AppKit paths. It writes
committed assets to `Sources/CodexSidecar/Resources/Icons` and ignored intermediate
PNGs to `build/Sidecar.iconset`; iconutil produces the ICNS. The package embeds
SwiftPM's resource bundle under Contents/Resources and copies AppIcon.icns to
the application resource root for CFBundleIconFile. The menu-bar NSImage loads
both bitmap representations from Bundle.module and sets isTemplate.

Assets were audited, viewed at small sizes, and checked with native bitmap
and packaged-bundle loading probes. No third-party runtime or remote skill
installation is required. Native system rendering may add platform treatments
around the Dock tile. Limited reference-library comparisons do not establish
trademark clearance or guarantees of exclusivity.
