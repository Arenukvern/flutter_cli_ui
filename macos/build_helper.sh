#!/bin/bash

# Exit on any error
set -e

# Navigate to the macOS directory
cd "$(dirname "$0")"

echo "Building FlutterHelper..."
xcodebuild -workspace Runner.xcworkspace -scheme FlutterHelper -configuration Release build

echo "Searching for FlutterHelper..."
DERIVED_DATA_PATH=$(xcodebuild -workspace Runner.xcworkspace -scheme FlutterHelper -showBuildSettings | grep "BUILD_ROOT" | awk '{print $3}')
echo "Derived data path: $DERIVED_DATA_PATH"

HELPER_PATH=$(find "${DERIVED_DATA_PATH}" -name "FlutterHelper" -type f | grep -v "\.dSYM" | head -n 1)

if [ -z "$HELPER_PATH" ]; then
    echo "Error: FlutterHelper not found in derived data"
    echo "Searching in products directory..."
    PRODUCTS_DIR=$(xcodebuild -workspace Runner.xcworkspace -scheme FlutterHelper -showBuildSettings | grep "BUILT_PRODUCTS_DIR" | awk '{print $3}')
    HELPER_PATH=$(find "${PRODUCTS_DIR}" -name "FlutterHelper" -type f | grep -v "\.dSYM" | head -n 1)
    
    if [ -z "$HELPER_PATH" ]; then
        echo "Error: FlutterHelper not found in products directory"
        exit 1
    fi
fi

echo "FlutterHelper found at: $HELPER_PATH"

# Create the directory for the helper in the Flutter assets
ASSET_DIR="../assets/macos"
mkdir -p "$ASSET_DIR"

# Copy the FlutterHelper to the assets directory
cp "$HELPER_PATH" "$ASSET_DIR/FlutterHelper"

echo "FlutterHelper has been built and copied to $ASSET_DIR/FlutterHelper"

# Update pubspec.yaml
PUBSPEC_PATH="../pubspec.yaml"
if ! grep -q "assets/macos/FlutterHelper" "$PUBSPEC_PATH"; then
    sed -i '' '/assets:/a\
    - assets/macos/FlutterHelper' "$PUBSPEC_PATH"
    echo "Updated pubspec.yaml with new asset"
else
    echo "pubspec.yaml already contains the FlutterHelper asset"
fi

# Run flutter pub get
flutter pub get

echo "Process completed successfully"