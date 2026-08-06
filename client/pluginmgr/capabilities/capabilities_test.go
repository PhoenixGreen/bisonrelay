package capabilities

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
)

// stubManager reports a fixed set of manifests as enabled, ignoring which
// capability is asked for unless byCapability is populated.
type stubManager struct {
	byCapability map[string][]pluginmgr.Manifest
}

func (m stubManager) PluginsWithCapability(capability string) []pluginmgr.Manifest {
	return m.byCapability[capability]
}

// stubRuntime answers Call from a canned per-plugin result, so a capability
// can be exercised without building and loading a real wasm module.
type stubRuntime struct {
	results map[string]any    // plugin id -> value to marshal back
	errs    map[string]error  // plugin id -> error instead of a result
	empty   map[string]bool   // plugin id -> return zero bytes (the ABI's "can't answer")
	calls   []string          // plugin id + export, in call order
	lastArg map[string]string // plugin id -> arg it was called with
}

func (r *stubRuntime) Call(ctx context.Context, id, export string, arg []byte,
	timeout time.Duration) ([]byte, error) {

	r.calls = append(r.calls, id+"/"+export)
	if r.lastArg == nil {
		r.lastArg = map[string]string{}
	}
	r.lastArg[id] = string(arg)
	if err := r.errs[id]; err != nil {
		return nil, err
	}
	if r.empty[id] {
		return nil, nil
	}
	v, ok := r.results[id]
	if !ok {
		return nil, fmt.Errorf("no result for %s", id)
	}
	return json.Marshal(v)
}

func manifest(id string, capability string, domains ...string) pluginmgr.Manifest {
	return pluginmgr.Manifest{
		ID:           id,
		Capabilities: []string{capability},
		Domains:      domains,
	}
}

// TestMergedSpellcheckDataDeduplicates is the whole point of merging rather
// than concatenating: two dictionaries will overlap heavily, and the user
// would otherwise pay for every duplicate on every keystroke.
func TestMergedSpellcheckDataDeduplicates(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilitySpellcheckData: {
			manifest("a", pluginmgr.CapabilitySpellcheckData),
			manifest("b", pluginmgr.CapabilitySpellcheckData),
		},
	}}
	rt := &stubRuntime{results: map[string]any{
		"a": SpellcheckData{
			Words:        []string{"hello", "world"},
			GrammarRules: []GrammarRule{{Pattern: "foo"}},
		},
		"b": SpellcheckData{
			Words:        []string{"world", "again"},
			GrammarRules: []GrammarRule{{Pattern: "bar"}},
		},
	}}

	got := MergedSpellcheckData(context.Background(), mgr, rt, nil, "en-US")

	want := []string{"hello", "world", "again"}
	if len(got.Words) != len(want) {
		t.Fatalf("words = %v, want %v", got.Words, want)
	}
	for i, w := range want {
		if got.Words[i] != w {
			t.Errorf("words[%d] = %q, want %q", i, got.Words[i], w)
		}
	}
	// Rules are concatenated, not deduplicated: two plugins may legitimately
	// ship a similar-looking rule with different messages.
	if len(got.GrammarRules) != 2 {
		t.Errorf("grammarRules = %+v, want 2", got.GrammarRules)
	}
}

// TestMergedSpellcheckDataSkipsFailures covers the degrade-don't-abort rule:
// one plugin still loading must not cost the user the others' dictionaries.
func TestMergedSpellcheckDataSkipsFailures(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilitySpellcheckData: {
			manifest("broken", pluginmgr.CapabilitySpellcheckData),
			manifest("ok", pluginmgr.CapabilitySpellcheckData),
		},
	}}
	rt := &stubRuntime{
		errs:    map[string]error{"broken": fmt.Errorf("not loaded")},
		results: map[string]any{"ok": SpellcheckData{Words: []string{"fine"}}},
	}

	got := MergedSpellcheckData(context.Background(), mgr, rt, nil, "en-US")

	if len(got.Words) != 1 || got.Words[0] != "fine" {
		t.Errorf("words = %v, want [fine]", got.Words)
	}
}

// TestFetchLinkCardMatchesDomain checks host matching is normalized on both
// sides -- a manifest claiming "YouTube.com" must match "www.youtube.com" in
// a message, or a plugin silently never fires.
func TestFetchLinkCardMatchesDomain(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilityLinkCard: {
			manifest("cards", pluginmgr.CapabilityLinkCard, "YouTube.com"),
		},
	}}
	rt := &stubRuntime{results: map[string]any{
		"cards": LinkMetadata{Title: "a video", Player: "youtube"},
	}}

	got, err := FetchLinkCard(context.Background(), mgr, rt,
		"https://www.YouTube.com/watch?v=abc")
	if err != nil {
		t.Fatalf("FetchLinkCard: %v", err)
	}
	if got.Title != "a video" {
		t.Errorf("title = %q, want %q", got.Title, "a video")
	}
	// Player is the plugin's request that the host offer a player, and must
	// survive the round trip -- it is what replaced the host keeping its own
	// list of which hostnames are video sites.
	if got.Player != "youtube" {
		t.Errorf("player = %q, want %q", got.Player, "youtube")
	}
	if arg := rt.lastArg["cards"]; arg != "https://www.YouTube.com/watch?v=abc" {
		t.Errorf("plugin received url %q", arg)
	}
}

// TestFetchLinkCardUnclaimedHost covers the common case: most links in a
// chat belong to no plugin at all, and must not reach one.
func TestFetchLinkCardUnclaimedHost(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilityLinkCard: {
			manifest("cards", pluginmgr.CapabilityLinkCard, "youtube.com"),
		},
	}}
	rt := &stubRuntime{}

	if _, err := FetchLinkCard(context.Background(), mgr, rt,
		"https://example.com/thing"); err == nil {
		t.Error("FetchLinkCard on an unclaimed host succeeded, want error")
	}
	if len(rt.calls) != 0 {
		t.Errorf("plugin was called for an unclaimed host: %v", rt.calls)
	}
}

// TestFetchLinkCardRejectsNonHTTP keeps non-web schemes away from plugins --
// a "file://" or "javascript:" link in a message must never be handed to
// guest code as something to fetch.
func TestFetchLinkCardRejectsNonHTTP(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilityLinkCard: {
			manifest("cards", pluginmgr.CapabilityLinkCard, "example.com"),
		},
	}}
	rt := &stubRuntime{}

	for _, u := range []string{
		"file:///etc/passwd",
		"javascript:alert(1)",
		"ftp://example.com/x",
		"not a url at all",
	} {
		if _, err := FetchLinkCard(context.Background(), mgr, rt, u); err == nil {
			t.Errorf("FetchLinkCard(%q) succeeded, want error", u)
		}
	}
	if len(rt.calls) != 0 {
		t.Errorf("plugin was called for a non-http url: %v", rt.calls)
	}
}

// TestFetchLinkCardEmptyResultIsError pins the failure signal the wasm ABI
// actually uses. A guest that can't answer returns a packed zero, which the
// runtime surfaces as zero bytes -- not as an error. Treating that as a
// successful empty LinkMetadata gave the UI a blank card it could not
// distinguish from a real one, in place of the plain-link fallback.
func TestFetchLinkCardEmptyResultIsError(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilityLinkCard: {
			manifest("cards", pluginmgr.CapabilityLinkCard, "example.com"),
		},
	}}
	rt := &stubRuntime{empty: map[string]bool{"cards": true}}

	if _, err := FetchLinkCard(context.Background(), mgr, rt,
		"https://example.com/thing"); err == nil {
		t.Error("FetchLinkCard on an empty guest result succeeded, want error")
	}
}

// TestMergedSpellcheckDataSkipsEmptyResult is the same signal on the
// aggregate side: a provider that answers with nothing is skipped, and must
// not abort the merge for the providers that did answer.
func TestMergedSpellcheckDataSkipsEmptyResult(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilitySpellcheckData: {
			manifest("silent", pluginmgr.CapabilitySpellcheckData),
			manifest("ok", pluginmgr.CapabilitySpellcheckData),
		},
	}}
	rt := &stubRuntime{
		empty:   map[string]bool{"silent": true},
		results: map[string]any{"ok": SpellcheckData{Words: []string{"fine"}}},
	}

	got := MergedSpellcheckData(context.Background(), mgr, rt, nil, "en-US")
	if len(got.Words) != 1 || got.Words[0] != "fine" {
		t.Errorf("words = %v, want [fine]", got.Words)
	}
}

// TestMergedSpellcheckDataCollectsLanguages: the UI offers whichever
// languages the enabled providers between them can serve, so it has to know
// what those are without being told in advance.
func TestMergedSpellcheckDataCollectsLanguages(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilitySpellcheckData: {
			manifest("a", pluginmgr.CapabilitySpellcheckData),
			manifest("b", pluginmgr.CapabilitySpellcheckData),
		},
	}}
	rt := &stubRuntime{results: map[string]any{
		"a": SpellcheckData{
			Words:    []string{"colour"},
			Language: "en-GB",
			Languages: []Language{
				{Code: "en-US", Name: "English (US)"},
				{Code: "en-GB", Name: "English (UK)"},
			},
		},
		"b": SpellcheckData{
			Words:    []string{"jargon"},
			Language: "en-GB",
			// Overlaps with the first provider's list, and adds one.
			Languages: []Language{
				{Code: "en-GB", Name: "English (UK)"},
				{Code: "fr-FR", Name: "French"},
			},
		},
	}}

	got := MergedSpellcheckData(context.Background(), mgr, rt, nil, "en-GB")

	if got.Language != "en-GB" {
		t.Errorf("language = %q, want en-GB", got.Language)
	}
	var codes []string
	for _, l := range got.Languages {
		codes = append(codes, l.Code)
	}
	want := []string{"en-US", "en-GB", "fr-FR"}
	if len(codes) != len(want) {
		t.Fatalf("languages = %v, want %v (deduplicated by code)", codes, want)
	}
	for i := range want {
		if codes[i] != want[i] {
			t.Errorf("languages = %v, want %v", codes, want)
			break
		}
	}
}

// The language reaches the plugin: without it a provider serving several
// would always answer with its default, and the setting would do nothing.
func TestMergedSpellcheckDataPassesTheLanguage(t *testing.T) {
	mgr := stubManager{byCapability: map[string][]pluginmgr.Manifest{
		pluginmgr.CapabilitySpellcheckData: {
			manifest("a", pluginmgr.CapabilitySpellcheckData),
		},
	}}
	rt := &stubRuntime{results: map[string]any{
		"a": SpellcheckData{Words: []string{"colour"}},
	}}

	MergedSpellcheckData(context.Background(), mgr, rt, nil, "en-GB")

	if got := rt.lastArg["a"]; got != "en-GB" {
		t.Errorf("plugin was asked for %q, want en-GB", got)
	}
}
