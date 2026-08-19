#!/usr/bin/env bash
# Builds plugin.wasm from this module's Go source. Requires Go 1.24+
# (go:wasmexport); no other toolchain (no TinyGo, no cgo).
set -euo pipefail
cd "$(dirname "$0")"

# The datasets are embedded compressed; see main.go. Only the .gz files are
# committed, so this regenerates them when a fresh .txt has been produced by
# tools/mkwords or tools/mkthesaurus.
for name in words-en-US common-en-US words-en-GB common-en-GB \
            thesaurus definitions exceptions; do
  if [ -f "$name.txt" ] && [ "$name.txt" -nt "$name.txt.gz" ]; then
    echo "Recompressing $name.txt"
    gzip -9 -c "$name.txt" > "$name.txt.gz"
  fi
done

GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o plugin.wasm .

echo "Built plugin.wasm ($(du -h plugin.wasm | cut -f1))"

# The client ships this plugin inside itself, as
# client/pluginmgr/builtin/writingtools.wasm.gz, and unpacks it into its data
# directory on first run. plugin.wasm here is a build artefact and is read by
# nothing -- so a build that stopped at it would reach nobody.
#
# The failure that makes this worth doing automatically is a silent one: the
# build succeeds, the tests pass, and the running app goes on using whatever
# was embedded the last time somebody remembered to copy it across. A rule
# that does not fire looks exactly like a rule that was never written, and
# that cost an hour of puzzlement the first time it happened.
#
# The client is Go, so a new rule still needs bruig/build_desktop.sh before it
# reaches a running copy. See the top of client/pluginmgr/builtin/builtin.go.
builtin="../../client/pluginmgr/builtin"
gzip -9 -c plugin.wasm > "$builtin/writingtools.wasm.gz"
cp manifest.json "$builtin/writingtools.manifest.json"
echo "Embedded in $builtin -- rebuild bruig for it to take effect"
