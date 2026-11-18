package wasmhost

import (
	"bytes"
	"compress/gzip"
	"context"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr/builtin"
)

// TestBuiltinWritingToolsAnswers loads the Writing Tools module the client
// actually ships and asks it for its data, through the same runtime the
// client uses.
//
// Everything else that tests that plugin tests its source. This is the copy
// embedded in the binary -- which is a file somebody has to remember to
// rebuild -- answering inside the limits a real call is held to: the module
// has to fit under the loader's cap, and fifteen megabytes of reply has to
// come back before the call times out. Both were comfortable when the reply
// was a word list, and are worth watching now that it carries a lexicon and
// a million counted contexts.
func TestBuiltinWritingToolsAnswers(t *testing.T) {
	var plugin *builtin.Plugin
	for _, p := range builtin.All() {
		if p.ID == "spellcheck" {
			p := p
			plugin = &p
		}
	}
	if plugin == nil {
		t.Skip("no built-in with the id spellcheck")
	}
	wasm, err := plugin.Wasm()
	if err != nil {
		t.Fatalf("unpacking the built-in: %v", err)
	}

	ctx := context.Background()
	root := t.TempDir()
	// It has no network access and asks for none; the client is required
	// of every runtime all the same.
	r, err := NewRuntime(ctx, Config{Root: root, HTTPClient: &http.Client{}})
	if err != nil {
		t.Fatalf("NewRuntime: %v", err)
	}
	defer r.Close(ctx)

	dir := filepath.Join(root, "installed", plugin.ID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	wasmPath := filepath.Join(dir, "plugin.wasm")
	if err := os.WriteFile(wasmPath, wasm, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := r.Load(ctx, plugin.ID, wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	var data struct {
		Words        []string `json:"words"`
		GrammarRules []struct {
			Pattern      string   `json:"pattern"`
			Alternatives []string `json:"alternatives"`
		} `json:"grammarRules"`
		Grammar *struct {
			Lexicon       []byte   `json:"lexicon"`
			Transitions   string   `json:"transitions"`
			ConfusionSets []string `json:"confusionSets"`
			Ngrams        []byte   `json:"ngrams"`
			PairWords     string   `json:"pairWords"`
			PairBits      []byte   `json:"pairBits"`
			Rules         []struct {
				ID string `json:"id"`
			} `json:"rules"`
		} `json:"grammar"`
	}
	start := time.Now()
	if err := callJSON(ctx, r, plugin.ID, "get_spellcheck_data", []byte("en-US"), &data); err != nil {
		t.Fatalf("get_spellcheck_data: %v", err)
	}
	t.Logf("answered in %v", time.Since(start))

	if len(data.Words) < 100000 {
		t.Errorf("%d words; the dictionary is over a hundred thousand", len(data.Words))
	}
	if len(data.GrammarRules) < 500 {
		t.Errorf("%d rules", len(data.GrammarRules))
	}
	g := data.Grammar
	if g == nil {
		t.Fatal("no grammar: the embedded module predates it -- run plugins/writingtools/build.sh")
	}
	if len(g.Rules) < 100 || len(g.ConfusionSets) < 100 || g.Transitions == "" || g.PairWords == "" {
		t.Errorf("grammar is incomplete: %d rules, %d sets", len(g.Rules), len(g.ConfusionSets))
	}
	// The tables are sent as they are stored. That they inflate, and into
	// something of the right shape, is the least that can be asked of them
	// here; what is in them is the app's to test.
	for name, gz := range map[string][]byte{
		"lexicon": g.Lexicon, "ngrams": g.Ngrams, "pairBits": g.PairBits,
	} {
		zr, err := gzip.NewReader(bytes.NewReader(gz))
		if err != nil {
			t.Errorf("%s is not gzip: %v", name, err)
			continue
		}
		raw, err := io.ReadAll(zr)
		if err != nil || len(raw) == 0 {
			t.Errorf("%s does not inflate: %v", name, err)
		}
	}
}
