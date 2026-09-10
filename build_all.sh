#!/usr/bin/env bash
# Builds and renames all apks and the app bundle.
# Linux/macOS counterpart of build_all.cmd — keep the two in sync.
#
# Set GOOGLE_FONTS_API_KEY before running to enable Google Fonts search
# in the built app (get a key at
# https://developers.google.com/fonts/docs/developer_api). Without it the
# build still succeeds, it just ships without the font list downloader.
#
# Usage:
#   ./build_all.sh
#   GOOGLE_FONTS_API_KEY=<your-key> ./build_all.sh
set -euo pipefail

cd "$(dirname "$0")"

FONTS_KEY_ARG=""
if [ -n "${GOOGLE_FONTS_API_KEY:-}" ]; then
  FONTS_KEY_ARG="--dart-define=GOOGLE_FONTS_API_KEY=$GOOGLE_FONTS_API_KEY"
else
  echo "GOOGLE_FONTS_API_KEY is not set: the Google Fonts list download will be disabled."
fi

echo "Cleaning..."
flutter clean

# $FONTS_KEY_ARG is intentionally unquoted: a single argument when set, nothing when empty.
echo "Building split per abi..."
flutter build apk --split-per-abi $FONTS_KEY_ARG

echo "Building combined apk..."
flutter build apk $FONTS_KEY_ARG

echo "Building bundle..."
flutter build appbundle $FONTS_KEY_ARG

echo "Renaming files..."
sha=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
apk_dir="build/app/outputs/flutter-apk"

mv "$apk_dir/app-arm64-v8a-release.apk" "$apk_dir/stickers-$sha-arm64-v8a.apk"
mv "$apk_dir/app-armeabi-v7a-release.apk" "$apk_dir/stickers-$sha-armeabi-v7a.apk"
mv "$apk_dir/app-x86_64-release.apk" "$apk_dir/stickers-$sha-x86_64.apk"
mv "$apk_dir/app-release.apk" "$apk_dir/stickers-$sha.apk"

echo "Done"
