# App Icon Setup Instructions

## Current Status
✅ Assets.xcassets/AppIcon.appiconset structure has been created
✅ Contents.json template is ready

## Next Steps

### 1. Prepare Your Icon Image
- Source image should be 1024x1024 pixels
- PNG format, no transparency (RGB, not RGBA)
- No rounded corners (iOS applies them automatically)
- Fill the entire frame edge-to-edge (no padding/margins)
- Recommended: Save as `AppIcon-1024.png`

### 2. Add Image to Xcode
**Option A: Use Xcode's Automatic Generation (Recommended)**
1. Open Xcode
2. Navigate to `Assets.xcassets` in the project navigator
3. Click on `AppIcon`
4. Drag your 1024x1024 image into the "App Store" slot (1024x1024)
5. Xcode will automatically generate all other sizes if "Preserve Vector Data" is enabled

**Option B: Generate All Sizes Manually**
If you need to generate all sizes manually, use this script:

```bash
#!/bin/bash
SOURCE="AppIcon-1024.png"
OUTPUT_DIR="ios/Assets.xcassets/AppIcon.appiconset"

# iPhone sizes
sips -z 40 40 "$SOURCE" --out "$OUTPUT_DIR/icon-20@2x.png"  # 20pt @2x
sips -z 60 60 "$SOURCE" --out "$OUTPUT_DIR/icon-20@3x.png"  # 20pt @3x
sips -z 58 58 "$SOURCE" --out "$OUTPUT_DIR/icon-29@2x.png"  # 29pt @2x
sips -z 87 87 "$SOURCE" --out "$OUTPUT_DIR/icon-29@3x.png"  # 29pt @3x
sips -z 80 80 "$SOURCE" --out "$OUTPUT_DIR/icon-40@2x.png"  # 40pt @2x
sips -z 120 120 "$SOURCE" --out "$OUTPUT_DIR/icon-40@3x.png" # 40pt @3x
sips -z 120 120 "$SOURCE" --out "$OUTPUT_DIR/icon-60@2x.png" # 60pt @2x
sips -z 180 180 "$SOURCE" --out "$OUTPUT_DIR/icon-60@3x.png" # 60pt @3x

# iPad sizes
sips -z 20 20 "$SOURCE" --out "$OUTPUT_DIR/icon-20@1x~ipad.png"
sips -z 40 40 "$SOURCE" --out "$OUTPUT_DIR/icon-20@2x~ipad.png"
sips -z 29 29 "$SOURCE" --out "$OUTPUT_DIR/icon-29@1x~ipad.png"
sips -z 58 58 "$SOURCE" --out "$OUTPUT_DIR/icon-29@2x~ipad.png"
sips -z 40 40 "$SOURCE" --out "$OUTPUT_DIR/icon-40@1x~ipad.png"
sips -z 80 80 "$SOURCE" --out "$OUTPUT_DIR/icon-40@2x~ipad.png"
sips -z 152 152 "$SOURCE" --out "$OUTPUT_DIR/icon-76@2x~ipad.png"
sips -z 167 167 "$SOURCE" --out "$OUTPUT_DIR/icon-83.5@2x~ipad.png"

# App Store
cp "$SOURCE" "$OUTPUT_DIR/icon-1024.png"
```

### 3. Update Contents.json
After adding images, update Contents.json with the correct filenames.

### 4. Verify in Xcode
1. Select the project in Xcode
2. Select the target "Caddie.ai"
3. Go to "General" tab
4. Under "App Icons and Launch Images", verify "AppIcon" is selected
5. Build and run to see the icon on the home screen

## Important Notes
- ❌ NO transparency/alpha channel for App Store icon (1024x1024)
- ❌ NO white padding or margins
- ❌ NO rounded corners baked into the image
- ✅ Fill the entire 1024x1024 frame edge-to-edge
- ✅ iOS will automatically apply rounded corners and shadows

## Testing
After adding the icon, test on:
- Home screen (all sizes)
- App switcher
- Settings app
- App Store build
