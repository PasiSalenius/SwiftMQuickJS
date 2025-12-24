#!/bin/bash
# Updates mquickjs source files from upstream repository
# Usage: ./scripts/update-mquickjs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMP_DIR=$(mktemp -d)
TARGET_DIR="$PROJECT_ROOT/Sources/CMQuickJS"
SRC_DIR="$TEMP_DIR/mquickjs"

echo "Cloning latest mquickjs..."
git clone --depth 1 https://github.com/bellard/mquickjs.git "$SRC_DIR"

echo "Updating source files..."

# Core source files from upstream
cp "$SRC_DIR/mquickjs.c" "$TARGET_DIR/"
cp "$SRC_DIR/cutils.c" "$TARGET_DIR/"
cp "$SRC_DIR/cutils.h" "$TARGET_DIR/"
cp "$SRC_DIR/libm.c" "$TARGET_DIR/"
cp "$SRC_DIR/libm.h" "$TARGET_DIR/"
cp "$SRC_DIR/dtoa.c" "$TARGET_DIR/"
cp "$SRC_DIR/dtoa.h" "$TARGET_DIR/"
cp "$SRC_DIR/list.h" "$TARGET_DIR/"
cp "$SRC_DIR/mquickjs_priv.h" "$TARGET_DIR/"
cp "$SRC_DIR/mquickjs_opcode.h" "$TARGET_DIR/"
cp "$SRC_DIR/softfp_template.h" "$TARGET_DIR/"
cp "$SRC_DIR/softfp_template_icvt.h" "$TARGET_DIR/"

# Public headers (to include/)
cp "$SRC_DIR/mquickjs.h" "$TARGET_DIR/include/"
cp "$SRC_DIR/libm.h" "$TARGET_DIR/include/"
cp "$SRC_DIR/mquickjs_priv.h" "$TARGET_DIR/include/"

echo "Cleaning up..."
rm -rf "$TEMP_DIR"

echo ""
echo "Updated mquickjs to latest version!"
echo ""
echo "Note: The following files are NOT updated (local customizations):"
echo "  - mqjs_bridge.c (Swift bridge code)"
echo "  - mquickjs_atom.h (may need manual update if atoms changed)"
echo ""
echo "Next steps:"
echo "  1. Run 'swift build' to verify compilation"
echo "  2. Run 'swift test' to verify functionality"
echo "  3. Check Changelog for breaking changes"
