// Package builtin holds the plugins that ship inside the client.
//
// A built-in plugin is an ordinary plugin in every respect that matters --
// same manifest, same wasm module, same capability contract, same wasmhost
// sandbox -- and differs only in where it comes from and what may be done to
// it. It is present without being imported, and it cannot be removed.
//
// That distinction is the whole point. Two of these ship because the app's
// own features are written against the services they provide: the composers
// expect somebody to answer "spellcheck-data", and a link card expects
// somebody to answer "link-card". A user who had to find and import a file
// before the app worked as described would reasonably call that a broken
// install. RSS, by contrast, is a screen a user may or may not want, and
// stays an import.
//
// They are not privileged. Being built in buys presence, not trust: they run
// in the same sandbox, reach the network through the same Tor-proxied client,
// and are subject to the same manifest validation as anything imported. This
// package only carries the bytes.
package builtin

import (
	"bytes"
	"compress/gzip"
	_ "embed"
	"fmt"
	"io"
)

// The modules are embedded gzipped and written out decompressed on first
// run. Uncompressed they are a little over 12MB between them, against 6.3MB
// like this -- a meaningful difference to a repository, a build and a
// download, and the cost is one decompression the first time a given build
// starts.
//
//go:embed writingtools.wasm.gz
var writingToolsWasmGz []byte

//go:embed writingtools.manifest.json
var writingToolsManifest []byte

//go:embed prettylinks.wasm.gz
var prettyLinksWasmGz []byte

//go:embed prettylinks.manifest.json
var prettyLinksManifest []byte

// Plugin is one shipped plugin: the manifest exactly as its own repository
// declares it, and its module.
//
// The manifest is embedded verbatim rather than rewritten here, so a built-in
// is described by its author and validated by the same code that validates an
// imported one. Nothing about being built in changes what it may declare.
type Plugin struct {
	// ID must equal the id inside Manifest; it is here so callers can name a
	// plugin without parsing the manifest first.
	ID string

	Manifest []byte

	// WasmGz is the module, gzipped. Use Wasm to get the bytes to write.
	WasmGz []byte
}

// Wasm decompresses the module.
func (p Plugin) Wasm() ([]byte, error) {
	r, err := gzip.NewReader(bytes.NewReader(p.WasmGz))
	if err != nil {
		return nil, fmt.Errorf("builtin %s: %w", p.ID, err)
	}
	defer r.Close()
	out, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("builtin %s: %w", p.ID, err)
	}
	return out, nil
}

// All is every plugin that ships with the client.
//
// The ids are the ones the plugins' own manifests declare, and must stay that
// way: install state, per-plugin settings and any post that named a style are
// all keyed on the id, so "spellcheck" stays "spellcheck" even though the
// plugin has been called Writing Tools for some time.
func All() []Plugin {
	return []Plugin{
		{
			ID:       "spellcheck",
			Manifest: writingToolsManifest,
			WasmGz:   writingToolsWasmGz,
		},
		{
			ID:       "prettylinks",
			Manifest: prettyLinksManifest,
			WasmGz:   prettyLinksWasmGz,
		},
	}
}

// IsBuiltin reports whether id names a plugin that ships with the client.
func IsBuiltin(id string) bool {
	for _, p := range All() {
		if p.ID == id {
			return true
		}
	}
	return false
}
