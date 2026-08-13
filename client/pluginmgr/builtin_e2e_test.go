package pluginmgr

import (
	"context"
	"encoding/json"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr/wasmhost"
)

// TestBuiltinAnswersEndToEnd loads the module that actually ships and asks it
// a question, through the whole chain: embedded bytes, decompressed, written
// to disk, compiled by wasmhost, called over the plugin's own ABI.
//
// It exists because the vendored .wasm.gz is a build artifact of another
// repository and nothing enforces that the two are in step. A plugin change
// that is not re-vendored ships the old data silently, and comparing hashes
// cannot catch it: a Go wasm build is not byte-reproducible, so rebuilding
// the same commit gives a different file. Behaviour is the only thing that
// can be compared, so this asks the shipped module questions whose answers
// changed recently and fails if it gives the old ones.
//
// Each word below is a feature that was added at a known point:
//
//	take off    a phrase at all -- these were discarded before
//	go          leads with the verb, from cntlist.rev, not a noun sense
//	blockchain  hand-written vocabulary WordNet is too old to have
func TestBuiltinAnswersEndToEnd(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)
	if err := m.SetEnabled("spellcheck", true); err != nil {
		t.Fatal(err)
	}

	manifest, err := m.readManifest(m.InstallDir("spellcheck"))
	if err != nil {
		t.Fatal(err)
	}
	export, ok := manifest.ServiceExport("thesaurus")
	if !ok {
		t.Fatal("the built-in does not export a thesaurus")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 180*time.Second)
	defer cancel()

	rt, err := wasmhost.NewRuntime(ctx, wasmhost.Config{
		Root:       root,
		HTTPClient: http.DefaultClient,
	})
	if err != nil {
		t.Skipf("wasmhost unavailable: %v", err)
	}
	defer rt.Close(context.Background())

	if err := rt.Load(ctx, "spellcheck",
		filepath.Join(m.InstallDir("spellcheck"), manifest.WasmFile), 0); err != nil {
		t.Fatalf("load: %v", err)
	}

	for _, word := range []string{"take off", "go", "blockchain"} {
		// The bare word, which is what capabilities.LookupSynonyms sends.
		out, err := rt.Call(ctx, "spellcheck", export, []byte(word), 60*time.Second)
		if err != nil {
			t.Errorf("%q: %v", word, err)
			continue
		}
		var entry struct {
			Word        string `json:"word"`
			Definitions []struct {
				Pos     string `json:"pos"`
				Text    string `json:"text"`
				Example string `json:"example"`
			} `json:"definitions"`
			Inflections []string `json:"inflections"`
		}
		if err := json.Unmarshal(out, &entry); err != nil {
			t.Errorf("%q: bad JSON: %v", word, err)
			continue
		}
		if len(entry.Definitions) == 0 {
			t.Errorf("%q: no definitions from the shipped module", word)
			continue
		}
		d := entry.Definitions[0]
		t.Logf("%-12q -> %-12q [%s] %.48s | infl:%v",
			word, entry.Word, d.Pos, d.Text, entry.Inflections)

		switch word {
		case "go":
			if d.Pos != "verb" {
				t.Errorf("go leads with a %s: the shipped module predates "+
					"the part-of-speech ordering", d.Pos)
			}
			if len(entry.Inflections) == 0 {
				t.Error("go has no inflections: the shipped module predates them")
			}
		case "take off":
			if entry.Word != "take off" {
				t.Errorf("take off answered as %q: the shipped module "+
					"predates phrase lookup", entry.Word)
			}
		}
	}
}
