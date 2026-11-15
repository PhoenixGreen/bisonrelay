#!/bin/sh
# build.sh builds the Go interpreter a Run panel runs Go with (Yaegi, as
# WebAssembly) into assets/code/: yaegi.wasm.gz and Go's wasm_exec.js.
#
# Only a teaching set of the standard library is given to programs (see
# PACKAGES): no os, no files, no network, no running other programs. Each
# package's symbols are Yaegi's own generated wrappers, copied from its
# module at build time rather than kept here.
set -e
cd "$(dirname "$0")"
YAEGI=v0.16.3
PACKAGES="bytes cmp container_heap container_list errors fmt math math_bits math_rand sort strconv strings sync time unicode unicode_utf8"
OUT=../../assets/code
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp main.go "$WORK/"
cd "$WORK"
go mod init yaegiwasm >/dev/null 2>&1
GOFLAGS=-mod=mod go get github.com/traefik/yaegi@$YAEGI >/dev/null 2>&1
SRC=$(go env GOMODCACHE)/github.com/traefik/yaegi@$YAEGI/stdlib
mkdir teach
cp "$SRC/stdlib.go" teach/
sed -i.bak '/go:generate/d' teach/stdlib.go
for p in $PACKAGES; do cp "$SRC/go1_22_$p.go" teach/; done
sed -i.bak 's/^package stdlib/package teach/' teach/*.go
sed -i.bak 's#"github.com/traefik/yaegi/stdlib/stdlib"#"yaegiwasm/teach/teach"#' teach/stdlib.go
rm teach/*.bak
GOOS=js GOARCH=wasm go build -trimpath -ldflags="-s -w" -o yaegi.wasm .
cd - >/dev/null
gzip -9 -n -c "$WORK/yaegi.wasm" > "$OUT/yaegi.wasm.gz"
cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" "$OUT/wasm_exec.js"
echo "built $OUT/yaegi.wasm.gz ($(wc -c < "$OUT/yaegi.wasm.gz") bytes) with $(go version)"
