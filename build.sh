#!/usr/bin/env bash
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
RELEASES="$ROOT/releases"

echo "==> Building frontend..."
cd "$ROOT/frontend"
yarn install --silent
yarn build

# Clean and recreate release directories
echo "==> Cleaning releases/..."
rm -rf "$RELEASES"
mkdir -p "$RELEASES/macOS"
mkdir -p "$RELEASES/Linux"
mkdir -p "$RELEASES/Windows"

build_target() {
  local TARGET="$1" DIR="$2" NAME="$3" ZIP="$4" EXT="${5:-}"
  echo "==> Building $TARGET..."
  cd "$ROOT/backend"
  zig build -Dtarget="$TARGET" -Doptimize=ReleaseSafe
  cp "zig-out/bin/ops_vpn${EXT}" "$RELEASES/$DIR/$NAME${EXT}"
  # Compress — GitHub/GitLab don't accept raw executables
  cd "$RELEASES/$DIR"
  zip "$ZIP" "$NAME${EXT}"
  rm "$NAME${EXT}"   # keep only the zip
  echo "    → releases/$DIR/$ZIP"
  cd "$ROOT"
}

# macOS — both chips supported
build_target "aarch64-macos"  "macOS"   "ops_vpn-M1"     "ops_vpn-macOS-M1.zip"
build_target "x86_64-macos"   "macOS"   "ops_vpn-Intel"  "ops_vpn-macOS-Intel.zip"

# Linux (64-bit only)
build_target "x86_64-linux"   "Linux"   "ops_vpn"        "ops_vpn-Linux.zip"

# Windows (64-bit only)
build_target "x86_64-windows" "Windows" "ops_vpn"        "ops_vpn-Windows.zip" ".exe"

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
echo "Upload these zips to GitLab Releases: https://git.ringcentral.com/rc-ai-learning/francis-peng-vpn/-/releases/new"
