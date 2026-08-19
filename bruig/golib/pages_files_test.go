package golib

import (
	"os"
	"path/filepath"
	"testing"
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
		cfg := parseUpstream(tc.upstream, "ln", "", 0)
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

	// The upstream modes are not the UI's to change.
	if parseUpstream("clientrpc", "", "", 0).editable() {
		t.Error("clientrpc reported as editable")
	}
	if !parseUpstream("pages:/tmp/site", "", "", 0).editable() {
		t.Error("pages reported as not editable")
	}
}
