#!/bin/bash
set -e

# Configuration
PACKAGE="com.sage.ide"
APP_NAME="Sage IDE"
OUTPUT_DIR="sage_ide_gen"

# 1. Build the Sage compiler for the host (to run the transpiler)
echo "Ensuring Sage compiler is built..."
make -C core

# 2. Transpile app.sage to Kotlin and generate Android project
echo "Transpiling app.sage to Android project..."
./core/sage --compile-android sage_ide/app.sage -o "$OUTPUT_DIR" --package "$PACKAGE" --app-name "$APP_NAME"

# 3. Copy our custom NativeBridge.kt if it exists
if [ -f sage_ide/src/NativeBridge.kt ]; then
    cp sage_ide/src/NativeBridge.kt "$OUTPUT_DIR/app/src/main/kotlin/com/sage/ide/NativeBridge.kt"
fi

# 4. Copy prebuilt Sage compiler for ARM64 to assets
# (Assuming we have one or will build one)
echo "Bundling prebuilt Sage compiler..."
mkdir -p "$OUTPUT_DIR/app/src/main/assets"
# cp path/to/sage-arm64 "$OUTPUT_DIR/app/src/main/assets/sage"

echo "Done. Android project generated in $OUTPUT_DIR"
echo "To build APK: cd $OUTPUT_DIR && ./gradlew assembleDebug"
