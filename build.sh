#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASES="$ROOT/releases"

echo "==> Building frontend..."
cd "$ROOT/frontend"
yarn install --silent
yarn build

# Create release directories
mkdir -p "$RELEASES/macOS"
mkdir -p "$RELEASES/Linux"
mkdir -p "$RELEASES/Windows"

build_target() {
  local TARGET="$1" DIR="$2" NAME="$3" EXT="${4:-}"
  echo "==> Building $TARGET..."
  cd "$ROOT/backend"
  zig build -Dtarget="$TARGET" -Doptimize=ReleaseSafe
  cp "zig-out/bin/ops_vpn${EXT}" "$RELEASES/$DIR/$NAME${EXT}"
  echo "    → releases/$DIR/$NAME${EXT}"
}

# macOS — both chips supported
build_target "aarch64-macos"  "macOS"    "ops_vpn-M1"        # Apple Silicon (M1/M2/M3)
build_target "x86_64-macos"   "macOS"    "ops_vpn-Intel"     # Intel Mac

# Linux (64-bit only)
build_target "x86_64-linux"   "Linux"    "ops_vpn"

# Windows (64-bit only)
build_target "x86_64-windows" "Windows"  "ops_vpn" ".exe"

echo ""
echo "✓ Done! releases/:"
echo ""
echo "  macOS/"
ls -lh "$RELEASES/macOS"
echo ""
echo "  Linux/"
ls -lh "$RELEASES/Linux"
echo ""
echo "  Windows/"
ls -lh "$RELEASES/Windows"
echo ""
echo "Share the releases/ folder — users just run the binary for their platform."
