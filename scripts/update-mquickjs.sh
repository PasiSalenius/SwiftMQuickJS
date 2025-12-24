#!/bin/bash
# Updates mquickjs source files from upstream repository
# Usage: ./scripts/update-mquickjs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=$(mktemp -d)
TARGET_DIR="$PROJECT_ROOT/Sources/CMQuickJS"

echo "Cloning latest mquickjs..."
git clone --depth 1 https://github.com/aspect-build/aspect-cli-mquickjs.git "$TEMP_DIR/mquickjs"

echo "Updating source files..."

# Core source files (overwrite)
cp "$TEMP_DIR/mquickjs/mquickjs.c" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/cutils.c" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/cutils.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/libm.c" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/libm.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/dtoa.c" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/dtoa.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/list.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/mquickjs_atom.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/mquickjs_priv.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/mquickjs_opcode.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/softfp_template.h" "$TARGET_DIR/"
cp "$TEMP_DIR/mquickjs/softfp_template_icvt.h" "$TARGET_DIR/"

# Public headers (to include/)
cp "$TEMP_DIR/mquickjs/mquickjs.h" "$TARGET_DIR/include/"
cp "$TEMP_DIR/mquickjs/libm.h" "$TARGET_DIR/include/"
cp "$TEMP_DIR/mquickjs/mquickjs_priv.h" "$TARGET_DIR/include/"

echo "Cleaning up..."
rm -rf "$TEMP_DIR"

echo ""
echo "Updated! You may need to:"
echo "  1. Regenerate mqjs_stdlib.h if the stdlib format changed"
echo "  2. Update mqjs_bridge.c if APIs changed"
echo "  3. Run 'swift build' to verify compilation"
echo "  4. Run 'swift test' to verify functionality"
