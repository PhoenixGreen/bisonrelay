#!/usr/bin/env bash
# Builds the desktop app the only way that is actually correct: the Go shared
# library first, then Flutter.
#
# This script exists because `flutter run` and `flutter build` do neither of
# the two things people assume. They rebuild the Dart, and they COPY
# golib.dylib into the bundle -- but nothing rebuilds golib itself. Change
# anything under client/ or bruig/golib/, run flutter, and you get new Dart
# talking to a stale Go library, with no warning at all. The failures that
# produces look like application bugs: a field that is always empty, a
# capability the manifest declares being rejected as unknown.
#
# Usage, from anywhere:
#
#   bruig/build_desktop.sh            # build
#   bruig/build_desktop.sh run        # build, then flutter run
#
set -euo pipefail

cd "$(dirname "$0")/.."
repo_root=$(pwd)

case "$(uname -s)" in
  Darwin) platform=macos ;;
  Linux)  platform=linux ;;
  *)      platform=windows ;;
esac

echo "==> Rebuilding golib for $platform"
# go generate picks the golibbuilder file matching this GOOS/GOARCH. If none
# matches it exits 0 having silently done nothing, which is its own trap --
# so check the artifact actually moved rather than trusting the exit code.
before=""
lib="$repo_root/bruig/flutterui/plugin/$platform/libs/golib.dylib"
[ "$platform" = macos ] || lib=""
[ -n "$lib" ] && [ -f "$lib" ] && before=$(stat -f%m "$lib" 2>/dev/null || echo "")

go generate ./bruig/golibbuilder

if [ -n "$lib" ]; then
  if [ ! -f "$lib" ]; then
    echo "error: $lib was not produced." >&2
    echo "       There is probably no golibbuilder file for this GOOS/GOARCH." >&2
    exit 1
  fi
  after=$(stat -f%m "$lib")
  if [ -n "$before" ] && [ "$before" = "$after" ]; then
    echo "warning: golib.dylib was not rewritten; it may be stale." >&2
  fi
fi

cd bruig/flutterui/bruig
if [ "${1:-}" = "run" ]; then
  echo "==> flutter run -d $platform"
  exec flutter run -d "$platform"
fi

echo "==> flutter build $platform --debug"
flutter build "$platform" --debug
echo "==> Done. Built from Go sources as of now."
