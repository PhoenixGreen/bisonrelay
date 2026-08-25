package golib

import (
	"github.com/companyzero/bisonrelay/client/resources/simplestore"
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
		cfg := parseUpstream(tc.upstream, "", "ln", "", 0, "", "", "", "")
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
	both := parseUpstream("pages:/tmp/site", "/tmp/shop", "ln", "", 0, "", "", "", "")
	if both.Mode != hostModePagesAndStore {
		t.Errorf("mode %q, want %q", both.Mode, hostModePagesAndStore)
	}
	if both.PagesPath != "/tmp/site" || both.StorePath != "/tmp/shop" {
		t.Errorf("paths %q / %q", both.PagesPath, both.StorePath)
	}

	// A store path alone is a store, same as the legacy form.
	if m := parseUpstream("", "/tmp/shop", "", "", 0, "", "", "", "").Mode; m != hostModeStore {
		t.Errorf("store-path-only mode %q, want %q", m, hostModeStore)
	}

	// It must not override a mode the app does not own.
	if m := parseUpstream("clientrpc", "/tmp/shop", "", "", 0, "", "", "", "").Mode; m != hostModeClientRPC {
		t.Errorf("clientrpc with store path became %q", m)
	}

	// The upstream modes are not the UI's to change.
	if parseUpstream("clientrpc", "", "", "", 0, "", "", "", "").editable() {
		t.Error("clientrpc reported as editable")
	}
	if !parseUpstream("pages:/tmp/site", "", "", "", 0, "", "", "", "").editable() {
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

	fname, err := pageFileName(root, partialsDir+"/nav.md")
	if err != nil {
		t.Fatalf("a fragment is a valid name: %v", err)
	}
	if want := filepath.Join(root, partialsDir, "nav.md"); fname != want {
		t.Fatalf("got %q, want %q", fname, want)
	}

	// Everything else is still refused.
	for _, bad := range []string{
		"../escape.md",
		partialsDir + "/../escape.md",
		partialsDir + "/sub/deep.md",
		"other/nav.md",
		partialsDir + "/nav.txt",
		partialsDir + "/.hidden.md",
	} {
		if _, err := pageFileName(root, bad); err == nil {
			t.Fatalf("%q should not be a valid page name", bad)
		}
	}
}

func TestListIncludesPartialsByPath(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, partialsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	write := func(rel, body string) {
		if err := os.WriteFile(filepath.Join(root, rel), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("index.md", "# Home")
	write(filepath.Join(partialsDir, "nav.md"), "[Home](index.md)")

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
		if n == partialsDir+"/nav.md" {
			found = true
		}
	}
	if !found {
		t.Fatalf("the fragment is missing: %v", names)
	}
}

// TestWriteCreatesThePartialsDirectory covers the first fragment written.
//
// partials/ does not exist until then, and the writer used to create only
// the root -- so writing the first fragment failed on a directory nothing
// had made, which is what "error creating the navigation partial" was.
func TestWriteCreatesThePartialsDirectory(t *testing.T) {
	root := filepath.Join(t.TempDir(), "pages")

	if err := writeLocalPage(root, partialsDir+"/nav.md", "[Home](index.md)"); err != nil {
		t.Fatalf("writing the first fragment: %v", err)
	}

	got, err := readLocalPage(root, partialsDir+"/nav.md")
	if err != nil {
		t.Fatal(err)
	}
	if got != "[Home](index.md)" {
		t.Fatalf("got %q", got)
	}

	// And the temp file it was written through is not left behind next to
	// it, which a rename across directories would have done.
	entries, err := os.ReadDir(filepath.Join(root, partialsDir))
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "nav.md" {
		var names []string
		for _, e := range entries {
			names = append(names, e.Name())
		}
		t.Fatalf("partials/ holds %v", names)
	}

	if err := deleteLocalPage(root, partialsDir+"/nav.md"); err != nil {
		t.Fatalf("deleting it: %v", err)
	}
}

// TestAssetsAreTheirOwnDirectoryAndKind covers the second subdirectory a
// site has. It is served to whoever asks, so what may be written into it is
// a closed list of what a page has a use for.
func TestAssetsAreTheirOwnDirectoryAndKind(t *testing.T) {
	root := t.TempDir()

	for _, good := range []string{
		"assets/banner.png", "assets/logo.SVG", "assets/photo.jpeg",
		"assets/a.gif", "assets/b.webp",
	} {
		if _, err := pageFileName(root, good); err != nil {
			t.Errorf("%q should be allowed: %v", good, err)
		}
	}

	for _, bad := range []string{
		"assets/notes.md",
		"assets/script.sh",
		"assets/passwd",
		"assets/../escape.png",
		"assets/sub/deep.png",
		"assets/.hidden.png",
		"other/banner.png",
		"banner.png", // the root is for pages
	} {
		if _, err := pageFileName(root, bad); err == nil {
			t.Errorf("%q should not be allowed", bad)
		}
	}
}

func TestAddAndListAssets(t *testing.T) {
	root := filepath.Join(t.TempDir(), "pages")

	path, err := addLocalAssetBytes(root, "banner.png", []byte("pretend png"))
	if err != nil {
		t.Fatal(err)
	}
	// The path is what a page writes, which is not the name it was given.
	if path != "assets/banner.png" {
		t.Fatalf("got %q", path)
	}

	got, err := listLocalAssets(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Path != "assets/banner.png" ||
		got[0].Size != int64(len("pretend png")) {
		t.Fatalf("got %+v", got)
	}

	// A site with no pictures is not an error.
	if empty, err := listLocalAssets(filepath.Join(t.TempDir(), "none")); err != nil ||
		len(empty) != 0 {
		t.Fatalf("got %v, %v", empty, err)
	}
}

func TestAddingSomethingThatIsNotAPictureIsRefused(t *testing.T) {
	root := filepath.Join(t.TempDir(), "pages")
	if _, err := addLocalAssetBytes(root, "secrets.txt", []byte("no")); err == nil {
		t.Fatal("a text file was written into the site")
	}
}

// A page reaches a picture by writing ![](assets/name.jpg), and a Markdown
// link stops at the first space. A file called "my banner.jpg" would be
// written, listed and served perfectly, and the only thing that would not
// work is the one thing it is for.
func TestAPictureNameAPageCannotLinkToIsRefused(t *testing.T) {
	root := filepath.Join(t.TempDir(), "pages")
	for _, bad := range []string{
		"my banner.png",
		"banner (1).png",
		"it's mine.png",
		"a\tb.png",
		`say "hi".png`,
		"<banner>.png",
	} {
		if _, err := addLocalAssetBytes(root, bad, []byte("x")); err == nil {
			t.Errorf("%q should not be allowed", bad)
		}
	}
}

func TestAnOrdinaryPictureNameIsStillAllowed(t *testing.T) {
	// The guard above is easy to write too widely, and a site that cannot
	// hold a file called banner-2.png is worse than one that can hold a
	// file with a space in it.
	root := filepath.Join(t.TempDir(), "pages")
	for _, ok := range []string{
		"banner.png", "banner-2.png", "banner_2.png", "a.b.png", "BANNER.PNG",
	} {
		if _, err := addLocalAssetBytes(root, ok, []byte("x")); err != nil {
			t.Errorf("%q should be allowed: %v", ok, err)
		}
	}
}

// TestAShopOnlyWearsAFrameWhenThereIsASite covers where the store reads its
// header and footer from.
//
// A store hosted alone has no site beside it, so naming a fragment would put
// markers round every page that expand to nothing -- which is worse than no
// frame, because the reader sees the marker.
func TestAShopOnlyWearsAFrameWhenThereIsASite(t *testing.T) {
	both := parseUpstream("pages:/tmp/site", "/tmp/shop", "ln", "", 0,
		"header", "footer", "", "")
	if got := siteRootFor(both); got != "/tmp/site" {
		t.Errorf("a shop beside a site reads from %q", got)
	}

	alone := parseUpstream("", "/tmp/shop", "ln", "", 0, "header", "footer", "", "")
	if got := siteRootFor(alone); got != "" {
		t.Errorf("a shop on its own reads from %q", got)
	}

	// Named or not, the names survive the trip -- what decides whether they
	// are used is whether there is a site to read them from.
	if both.StoreHeader != "header" || both.StoreFooter != "footer" {
		t.Errorf("got %q and %q", both.StoreHeader, both.StoreFooter)
	}
}

// TestAShopPictureCanGoInAFolder covers organising a shop's pictures.
//
// One level, matching what the shop will serve: covers/ and screenshots/ is
// somebody organising, and anything deeper would be written where nothing
// can ask for it.
func TestAShopPictureCanGoInAFolder(t *testing.T) {
	root := t.TempDir()
	got, err := addStoreAssetBytes(root, "covers", "dm0004.jpg", []byte("x"))
	if err != nil {
		t.Fatal(err)
	}
	if got != "covers/dm0004.jpg" {
		t.Fatalf("recorded as %q", got)
	}
	if _, err := os.Stat(filepath.Join(root, simplestore.AssetsDir,
		"covers", "dm0004.jpg")); err != nil {
		t.Fatalf("not written where it says: %v", err)
	}
}

func TestAShopPictureWithNoFolderGoesAtTheTop(t *testing.T) {
	root := t.TempDir()
	got, err := addStoreAssetBytes(root, "", "banner.jpg", []byte("x"))
	if err != nil {
		t.Fatal(err)
	}
	if got != "banner.jpg" {
		t.Fatalf("recorded as %q", got)
	}
}

func TestAFolderCannotReachOutOfTheShop(t *testing.T) {
	root := t.TempDir()
	for _, folder := range []string{
		"..", "../..", "a/b", ".hidden", "my covers", "co(vers)",
	} {
		if _, err := addStoreAssetBytes(root, folder, "x.jpg", []byte("x")); err == nil {
			t.Errorf("folder %q was accepted", folder)
		}
	}
}

func TestAFolderIsWrittenTheWayAPageWouldLinkIt(t *testing.T) {
	// A picture is reached by writing ![](shopassets/covers/x.jpg), and a
	// Markdown link stops at the first space -- the same reason a picture's
	// own name cannot have one.
	root := t.TempDir()
	got, err := addStoreAssetBytes(root, "/covers/", "dm0004.jpg", []byte("x"))
	if err != nil {
		t.Fatal(err)
	}
	if got != "covers/dm0004.jpg" {
		t.Fatalf("recorded as %q", got)
	}
}
