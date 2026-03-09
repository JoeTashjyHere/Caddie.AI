#!/bin/bash

# App Icon Generator Script
# This script generates all required iOS app icon sizes from a 1024x1024 source image

SOURCE_IMAGE="$1"
OUTPUT_DIR="Assets.xcassets/AppIcon.appiconset"

if [ -z "$SOURCE_IMAGE" ]; then
    echo "Usage: $0 <path-to-1024x1024-source-image.png>"
    echo "Example: $0 ~/Downloads/Caddie-app-icon-1024.png"
    exit 1
fi

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "Error: Source image not found: $SOURCE_IMAGE"
    exit 1
fi

# Check if source is 1024x1024
WIDTH=$(sips -g pixelWidth "$SOURCE_IMAGE" | tail -1 | awk '{print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE_IMAGE" | tail -1 | awk '{print $2}')

if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
    echo "Warning: Source image is ${WIDTH}x${HEIGHT}, expected 1024x1024"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Generating app icon sizes from: $SOURCE_IMAGE"
echo "Output directory: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

# iPhone sizes
echo "Generating iPhone icons..."
sips -z 40 40 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-20@2x.png" 2>/dev/null  # 20pt @2x
sips -z 60 60 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-20@3x.png" 2>/dev/null  # 20pt @3x
sips -z 58 58 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-29@2x.png" 2>/dev/null  # 29pt @2x
sips -z 87 87 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-29@3x.png" 2>/dev/null  # 29pt @3x
sips -z 80 80 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-40@2x.png" 2>/dev/null  # 40pt @2x
sips -z 120 120 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-40@3x.png" 2>/dev/null # 40pt @3x
sips -z 120 120 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-60@2x.png" 2>/dev/null # 60pt @2x
sips -z 180 180 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-60@3x.png" 2>/dev/null # 60pt @3x

# iPad sizes
echo "Generating iPad icons..."
sips -z 20 20 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-20@1x~ipad.png" 2>/dev/null
sips -z 40 40 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-20@2x~ipad.png" 2>/dev/null
sips -z 29 29 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-29@1x~ipad.png" 2>/dev/null
sips -z 58 58 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-29@2x~ipad.png" 2>/dev/null
sips -z 40 40 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-40@1x~ipad.png" 2>/dev/null
sips -z 80 80 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-40@2x~ipad.png" 2>/dev/null
sips -z 152 152 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-76@2x~ipad.png" 2>/dev/null
sips -z 167 167 "$SOURCE_IMAGE" --out "$OUTPUT_DIR/icon-83.5@2x~ipad.png" 2>/dev/null

# App Store (1024x1024)
echo "Copying App Store icon..."
cp "$SOURCE_IMAGE" "$OUTPUT_DIR/icon-1024.png"

# Remove alpha channel from App Store icon if present
sips -s format png "$OUTPUT_DIR/icon-1024.png" --out "$OUTPUT_DIR/icon-1024-noalpha.png" 2>/dev/null
if [ -f "$OUTPUT_DIR/icon-1024-noalpha.png" ]; then
    mv "$OUTPUT_DIR/icon-1024-noalpha.png" "$OUTPUT_DIR/icon-1024.png"
fi

echo ""
echo "✅ All icon sizes generated successfully!"
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. Navigate to Assets.xcassets > AppIcon"
echo "3. The icons should appear automatically, or drag them into the slots"
echo "4. Build and run to see your icon on the home screen"
