# App Icons Setup

## Adding App Icons to Life Wrapped

### Required Steps

1. **Prepare your icons** using IconKitchen or similar tool

   - Generate iOS app icon set with all required sizes
   - Output should include `Contents.json` and all PNG files

2. **Copy icons to the correct location**

   ```
   App/Resources/Assets.xcassets/AppIcon.appiconset/
   ```

3. **Ensure `Assets.xcassets` is in the Resources folder**

   - The asset catalog must be located at: `App/Resources/Assets.xcassets/`
   - Xcode looks for assets in this specific location based on `project.yml` configuration

4. **Regenerate the Xcode project**

   ```bash
   xcodegen generate
   ```

5. **Clean and rebuild**
   - Delete app from simulator
   - Product → Clean Build Folder (⇧⌘K)
   - Build and run (⌘R)

---

## Contents.json Format (iOS 18+)

For iOS 18+, include a universal 1024x1024 icon with `"platform": "ios"`:

```json
{
  "images": [
    {
      "filename": "AppIcon~ios-marketing.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

iOS automatically generates all other sizes from the 1024x1024 universal icon.

---

## Troubleshooting

### Icon not showing up?

1. **Verify file location**: Icons must be in `App/Resources/Assets.xcassets/AppIcon.appiconset/`

2. **Check project.yml**: Ensure resources are configured:

   ```yaml
   resources:
     - App/Resources/Assets.xcassets
   ```

3. **Verify build setting**: `ASSETCATALOG_COMPILER_APPICON_NAME` should be `AppIcon`

4. **Clean DerivedData**:

   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/LifeWrapped-*
   ```

5. **Delete and reinstall app** on simulator/device

---

## Icon Sizes Reference

| Size      | Scale  | Device       | Filename                              |
| --------- | ------ | ------------ | ------------------------------------- |
| 1024x1024 | 1x     | App Store    | AppIcon~ios-marketing.png             |
| 60x60     | 2x, 3x | iPhone       | AppIcon@2x.png, AppIcon@3x.png        |
| 76x76     | 1x, 2x | iPad         | AppIcon~ipad.png, AppIcon@2x~ipad.png |
| 83.5x83.5 | 2x     | iPad Pro     | AppIcon-83.5@2x~ipad.png              |
| 40x40     | 2x, 3x | Spotlight    | AppIcon-40@2x.png, AppIcon-40@3x.png  |
| 29x29     | 2x, 3x | Settings     | AppIcon-29@2x.png, AppIcon-29@3x.png  |
| 20x20     | 2x, 3x | Notification | AppIcon-20@2x.png, AppIcon-20@3x.png  |

---

## Key Insight

**The `Assets.xcassets` folder must be physically located in `App/Resources/`** for the build system to pick up the app icon. Simply having the files in the project isn't enough—the folder structure matters.
