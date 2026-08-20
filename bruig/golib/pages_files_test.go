package golib

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/decred/slog"
)

// TestPageFileNameRejectsEscapes is the check that keeps the pages directory
// from publishing anything the author did not put there: the directory is
// served to whoever asks, so a name that walks out of it, hides, or is not
// markdown must not be writable or readable through the UI.
func TestPageFileNameRejectsEscapes(t *testing.T) {
	root := t.TempDir()

	bad := []string{
		"", "   ",
		"../secret.md",
		"sub/page.md",
		filepath.Join(root, "abs.md"),
		".hidden.md",
		"products.toml",
		"index",
		"index.tmpl",
	}
	for _, name := range bad {
		if _, err := pageFileName(root, name); err == nil {
			t.Errorf("name %q was accepted, want rejected", name)
		}
	}

	good, err := pageFileName(root, "about.md")
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(root, "about.md"); good != want {
		t.Fatalf("got %q, want %q", good, want)
	}
}

func TestLocalPageRoundTrip(t *testing.T) {
	root := filepath.Join(t.TempDir(), "pages")

	// A directory that does not exist yet lists as empty rather than
	// failing: hosting can be configured before anything is written.
	pages, err := listLocalPages(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(pages) != 0 {
		t.Fatalf("got %d pages, want 0", len(pages))
	}

	for _, name := range []string{"about.md", "index.md", "Contact.md"} {
		if err := writeLocalPage(root, name, "# "+name); err != nil {
			t.Fatal(err)
		}
	}

	pages, err = listLocalPages(root)
	if err != nil {
		t.Fatal(err)
	}
	// Index first, then case-insensitive alphabetical.
	var got []string
	for _, p := range pages {
		got = append(got, p.Name)
	}
	want := []string{"index.md", "about.md", "Contact.md"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
	if !pages[0].IsIndex {
		t.Error("index.md not flagged as the index")
	}

	content, err := readLocalPage(root, "about.md")
	if err != nil {
		t.Fatal(err)
	}
	if content != "# about.md" {
		t.Fatalf("got %q", content)
	}

	// Writing leaves no temp files behind for a visitor to fetch.
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Fatalf("got %d entries in %s, want 3", len(entries), root)
	}

	if err := deleteLocalPage(root, "about.md"); err != nil {
		t.Fatal(err)
	}
	// Deleting twice is not an error: the UI may be a list behind.
	if err := deleteLocalPage(root, "about.md"); err != nil {
		t.Fatal(err)
	}
	if content, err = readLocalPage(root, "about.md"); err != nil || content != "" {
		t.Fatalf("got %q, %v after delete", content, err)
	}
}

func TestParseUpstream(t *testing.T) {
	for _, tc := range []struct {
		upstream string
		wantMode string
		wantPath string
	}{
		{"", hostModeOff, ""},
		{"pages:/tmp/site", hostModePages, "/tmp/site"},
		{"simplestore:/tmp/shop", hostModeStore, "/tmp/shop"},
		{"https://example.com", hostModeHTTP, ""},
		{"clientrpc", hostModeClientRPC, ""},
	} {
		cfg := parseUpstream(tc.upstream, "", "ln", "", 0)
		if cfg.Mode != tc.wantMode {
			t.Errorf("%q: mode %q, want %q", tc.upstream, cfg.Mode, tc.wantMode)
		}
		got := cfg.PagesPath
		if cfg.Mode == hostModeStore {
			got = cfg.StorePath
		}
		if got != tc.wantPath {
			t.Errorf("%q: path %q, want %q", tc.upstream, got, tc.wantPath)
		}
	}

	// A store path beside a pages upstream is a site with a shop in it,
	// which the legacy single-line form cannot express.
	both := parseUpstream("pages:/tmp/site", "/tmp/shop", "ln", "", 0)
	if both.Mode != hostModePagesAndStore {
		t.Errorf("mode %q, want %q", both.Mode, hostModePagesAndStore)
	}
	if both.PagesPath != "/tmp/site" || both.StorePath != "/tmp/shop" {
		t.Errorf("paths %q / %q", both.PagesPath, both.StorePath)
	}

	// A store path alone is a store, same as the legacy form.
	if m := parseUpstream("", "/tmp/shop", "", "", 0).Mode; m != hostModeStore {
		t.Errorf("store-path-only mode %q, want %q", m, hostModeStore)
	}

	// It must not override a mode the app does not own.
	if m := parseUpstream("clientrpc", "/tmp/shop", "", "", 0).Mode; m != hostModeClientRPC {
		t.Errorf("clientrpc with store path became %q", m)
	}

	// The upstream modes are not the UI's to change.
	if parseUpstream("clientrpc", "", "", "", 0).editable() {
		t.Error("clientrpc reported as editable")
	}
	if !parseUpstream("pages:/tmp/site", "", "", "", 0).editable() {
		t.Error("pages reported as not editable")
	}
}

// TestDefaultPathsFollowTheApp guards the thing that would quietly serve an
// empty directory: bruig and brclient keep their data in different places, so
// the offered default has to come from the running app rather than from a
// hardcoded application name.
func TestDefaultPathsFollowTheApp(t *testing.T) {
	ph := newPagesHost(slog.Disabled, "/home/someone/.bruig")

	if got, want := ph.defaultPagesPath(), "/home/someone/.bruig/pages"; got != want {
		t.Errorf("pages path %q, want %q", got, want)
	}
	if got, want := ph.defaultStorePath(), "/home/someone/.bruig/store"; got != want {
		t.Errorf("store path %q, want %q", got, want)
	}
}

// TestPartialsLiveInTheirOwnDirectory covers the one subdirectory a site has.
//
// Fragments have to be somewhere the serving side will read them from, and
// "partials/" is that place -- but widening the name check is exactly how a
// path traversal gets in, so what is allowed is one known prefix and nothing
// else.
func TestPartialsLiveInTheirOwnDirectory(t *testing.T) {
	root := t.TempDir()

	fname, err := pageFileName(root, "partials/nav.md")
	if err != nil {
		t.Fatalf("a fragment is a valid name: %v", err)
	}
	if want := filepath.Join(root, "partials", "nav.md"); fname != want {
		t.Fatalf("got %q, want %q", fname, want)
	}

	// Everything else is still refused.
	for _, bad := range []string{
		"../escape.md",
		"partials/../escape.md",
		"partials/sub/deep.md",
		"other/nav.md",
		"partials/nav.txt",
		"partials/.hidden.md",
	} {
		if _, err := pageFileName(root, bad); err == nil {
			t.Fatalf("%q should not be a valid page name", bad)
		}
	}
}

func TestListIncludesPartialsByPath(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "partials"), 0o700); err != nil {
		t.Fatal(err)
	}
	write := func(rel, body string) {
		if err := os.WriteFile(filepath.Join(root, rel), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("index.md", "# Home")
	write(filepath.Join("partials", "nav.md"), "[Home](index.md)")

	pages, err := listLocalPages(root)
	if err != nil {
		t.Fatal(err)
	}

	var names []string
	for _, p := range pages {
		names = append(names, p.Name)
	}
	// Named by path, so the two kinds are told apart by what they are
	// called rather than by a second listing.
	if len(names) != 2 {
		t.Fatalf("got %v", names)
	}
	found := false
	for _, n := range names {
		if n == "partials/nav.md" {
			found = true
		}
	}
	if !found {
		t.Fatalf("the fragment is missing: %v", names)
	}
}
