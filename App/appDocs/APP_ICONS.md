# App Icons

## The icon

A white document with a microphone on a near-black rounded square, drawn with the same strokes as the app's graphite design. The same mark appears in the website header (as inline SVG in `docs/index.html` and `docs/_layouts/default.html`).

## Where the files live

| Folder | What it holds |
| --- | --- |
| `Logo/ios/` | The exported iOS icon set: 21 PNGs and `Contents.json` |
| `App/Resources/Assets.xcassets/AppIcon.appiconset/` | The copy the app builds with. Identical to `Logo/ios/` |
| `Logo/web/` | Website icons: `favicon.ico`, `apple-touch-icon.png` (180), `icon-192.png`, `icon-512.png` and maskable versions |
| `docs/assets/icons/` | The website's copy of `favicon.ico`, `apple-touch-icon.png`, `icon-192.png` and `icon-512.png`. `icon-512.png` is also the link-preview image |

As of September 27, 2026, the app icon and the website icons match pixel for pixel.

## Changing the icon

1. Export the new set into `Logo/ios/` and `Logo/web/`.
2. Copy `Logo/ios/*` into `App/Resources/Assets.xcassets/AppIcon.appiconset/`, replacing what's there.
3. Copy the four website files from `Logo/web/` into `docs/assets/icons/`.
4. In Xcode: Product, then Clean Build Folder, then run. Delete the app from the simulator first if the old icon sticks.

Don't run `xcodegen generate`. `project.yml` is out of date, and regenerating would overwrite the real project; build from `LifeWrapped.xcodeproj`.

## Icon sizes in the set

| Size | Scale | Used for | Files |
| --- | --- | --- | --- |
| 1024 × 1024 | 1x | App Store | `AppIcon~ios-marketing.png` |
| 60 × 60 | 2x, 3x | iPhone Home Screen | `AppIcon@2x.png`, `AppIcon@3x.png` |
| 76 × 76 | 1x, 2x | iPad Home Screen | `AppIcon~ipad.png`, `AppIcon@2x~ipad.png` |
| 83.5 × 83.5 | 2x | iPad Pro Home Screen | `AppIcon-83.5@2x~ipad.png` |
| 60 × 60 | 2x, 3x | CarPlay | `AppIcon-60@2x~car.png`, `AppIcon-60@3x~car.png` |
| 40 × 40 | 1x, 2x, 3x | Spotlight | `AppIcon-40*.png` |
| 29 × 29 | 1x, 2x, 3x | Settings | `AppIcon-29*.png` |
| 20 × 20 | 1x, 2x, 3x | Notifications | `AppIcon-20*.png` |

## If the icon doesn't show

1. Check the build setting `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon`.
2. Clean DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/LifeWrapped-*`
3. Delete and reinstall the app on the simulator or device.
