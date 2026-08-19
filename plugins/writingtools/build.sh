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
    gzip -9 -n -c "$name.txt" > "$name.txt.gz"
  fi
done

# Built to be reproducible, so that rebuilding without changing anything
# leaves the embedded copy byte-identical and git has nothing to report. The
# alternative is a 9MB binary diff on every build, which is noise in a review
# and, repeated, weight in the repository.
#
#   -trimpath        keeps the building machine's directory names out
#   -buildvcs=false  keeps the commit it happened to be built at out
#   -buildid=        drops the id Go derives from all of the above
GOOS=wasip1 GOARCH=wasm go build -trimpath -buildvcs=false \
  -ldflags=-buildid= -buildmode=c-shared -o plugin.wasm .

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
# -n: no name, no timestamp. Without it the gz carries plugin.wasm's mtime,
# which moves on every build even when the module itself has not.
gzip -9 -n -c plugin.wasm > "$builtin/writingtools.wasm.gz"
cp manifest.json "$builtin/writingtools.manifest.json"
echo "Embedded in $builtin -- rebuild bruig for it to take effect"
