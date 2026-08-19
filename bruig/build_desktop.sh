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

# The same trap one layer down. The writing tools plugin is a wasm module the
# client embeds from client/pluginmgr/builtin, and that .gz is a build output:
# nothing in the Go build produces it from the sources under plugins/, so a
# changed rule reaches the app only if somebody remembered to run the plugin's
# build script. When they did not, the app runs the previous rules and says
# nothing -- a rule that does not fire looks exactly like a rule that was
# never written, and that is an hour of anybody's afternoon.
embedded="$repo_root/client/pluginmgr/builtin/writingtools.wasm.gz"
plugin_src="$repo_root/plugins/writingtools"
if [ -d "$plugin_src" ]; then
  # Sources only: the corpora under data/ are inputs to the generators rather
  # than to the module, and plugin.wasm is an artefact of the last build.
  newer=$(find "$plugin_src" \
    \( -name "*.go" -o -name "go.mod" -o -name "*.txt.gz" -o -name "manifest.json" \) \
    -newer "$embedded" -print -quit 2>/dev/null || true)
  if [ -n "$newer" ]; then
    echo "==> Rebuilding the writing tools plugin ($(basename "$newer") is newer)"
    "$plugin_src/build.sh"
  fi
fi

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
