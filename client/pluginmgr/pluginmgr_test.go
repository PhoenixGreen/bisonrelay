package pluginmgr

import (
	"archive/zip"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
)

// testServerHost returns the bare hostname (no port) of an httptest.Server
// URL, for use as a manifest matcher domain so a test can point rawURL at
// the local test server instead of a real domain.
func testServerHost(t *testing.T, serverURL string) string {
	t.Helper()
	parsed, err := url.Parse(serverURL)
	if err != nil {
		t.Fatalf("parse test server url: %v", err)
	}
	return parsed.Hostname()
}

func writeManifest(t *testing.T, dir string, manifest Manifest) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	b, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, manifestFileName), b, 0o600); err != nil {
		t.Fatal(err)
	}
}

// findPlugin returns the plugin with the given id, if present. Tests use
// this instead of asserting on len(List()) because the manager always
// auto-installs the bundled "prettylinks" plugin (see
// installBuiltinsIfMissing), so a fresh manager's plugin count is never 0.
func findPlugin(plugins []Plugin, id string) (Plugin, bool) {
	for _, p := range plugins {
		if p.Manifest.ID == id {
			return p, true
		}
	}
	return Plugin{}, false
}

func testManifest(id string, domains ...string) Manifest {
	return Manifest{
		ID:               id,
		Name:             "Test Plugin " + id,
		Version:          "1.0.0",
		Description:      "a test plugin",
		EnabledByDefault: true,
		RendererKind:     RendererKindLinkCard,
		Matchers: []Matcher{{
			Domains:          domains,
			MetadataEndpoint: "https://example.invalid/oembed?url={url}",
			MetadataFormat:   MetadataFormatOEmbedJSON,
		}},
	}
}

func newTestManager(t *testing.T, root string) *Manager {
	t.Helper()
	m, err := NewManager(Config{
		Root:       root,
		HTTPClient: http.DefaultClient,
	})
	if err != nil {
		t.Fatalf("NewManager: %v", err)
	}
	return m
}

func TestLoadInstalledAndDefaults(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"),
		testManifest("prettylinks", "youtube.com"))

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "prettylinks")
	if !ok {
		t.Fatalf("expected prettylinks plugin to be loaded")
	}
	if !plugin.Enabled {
		t.Fatalf("expected plugin enabled by default")
	}
}

func TestBuiltinPrettyLinksAutoInstalled(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	plugin, ok := findPlugin(m.List(), "prettylinks")
	if !ok {
		t.Fatalf("expected bundled prettylinks plugin to be auto-installed")
	}
	if !plugin.Enabled {
		t.Fatalf("expected bundled prettylinks plugin to be enabled by default")
	}
	if _, err := os.Stat(filepath.Join(root, installedDirName, "prettylinks", manifestFileName)); err != nil {
		t.Fatalf("expected bundled manifest written to disk: %v", err)
	}

	// A second manager instance over the same root must not clobber a
	// user's choice to disable the bundled plugin.
	if err := m.SetEnabled("prettylinks", false); err != nil {
		t.Fatal(err)
	}
	m2 := newTestManager(t, root)
	plugin2, ok := findPlugin(m2.List(), "prettylinks")
	if !ok || plugin2.Enabled {
		t.Fatalf("expected disabled state to persist across restarts, got %+v", plugin2)
	}
}

func TestInvalidManifestSkipped(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "bad"),
		Manifest{ID: "bad", Name: "Bad", RendererKind: "unknown-kind"})

	m := newTestManager(t, root)
	if _, ok := findPlugin(m.List(), "bad"); ok {
		t.Fatalf("expected invalid manifest to be skipped")
	}
}

func TestManifestIDMustMatchDir(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "dirname"),
		testManifest("differentid", "youtube.com"))

	m := newTestManager(t, root)
	if _, ok := findPlugin(m.List(), "differentid"); ok {
		t.Fatalf("expected mismatched id/dir manifest to be skipped")
	}
	if _, ok := findPlugin(m.List(), "dirname"); ok {
		t.Fatalf("expected mismatched id/dir manifest to be skipped")
	}
}

func TestSetEnabledPersists(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"),
		testManifest("prettylinks", "youtube.com"))

	m := newTestManager(t, root)
	if err := m.SetEnabled("prettylinks", false); err != nil {
		t.Fatal(err)
	}

	m2 := newTestManager(t, root)
	plugin, ok := findPlugin(m2.List(), "prettylinks")
	if !ok || plugin.Enabled {
		t.Fatalf("expected persisted disabled state, got %+v", plugin)
	}
}

func TestSetEnabledUnknownID(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)
	if err := m.SetEnabled("doesnotexist", true); err == nil {
		t.Fatalf("expected error for unknown plugin id")
	}
}

func TestRemove(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"),
		testManifest("prettylinks", "youtube.com"))

	m := newTestManager(t, root)
	if err := m.Remove("prettylinks"); err != nil {
		t.Fatal(err)
	}
	if _, ok := findPlugin(m.List(), "prettylinks"); ok {
		t.Fatalf("expected plugin removed")
	}
	if _, err := os.Stat(filepath.Join(root, installedDirName, "prettylinks")); !os.IsNotExist(err) {
		t.Fatalf("expected plugin dir removed from disk")
	}
}

func TestImportFromDir(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	srcDir := t.TempDir()
	writeManifest(t, srcDir, testManifest("imported", "example.com"))

	plugin, err := m.Import(srcDir)
	if err != nil {
		t.Fatalf("Import: %v", err)
	}
	if plugin.Manifest.ID != "imported" {
		t.Fatalf("unexpected imported id: %s", plugin.Manifest.ID)
	}
	if _, ok := findPlugin(m.List(), "imported"); !ok {
		t.Fatalf("expected imported plugin present after import")
	}
}

func TestImportFromZip(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	zipPath := filepath.Join(t.TempDir(), "plugin.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	manifest := testManifest("zipped", "example.com")
	manifestBytes, _ := json.Marshal(manifest)
	w, err := zw.Create("zipped/manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(manifestBytes); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	plugin, err := m.Import(zipPath)
	if err != nil {
		t.Fatalf("Import: %v", err)
	}
	if plugin.Manifest.ID != "zipped" {
		t.Fatalf("unexpected imported id: %s", plugin.Manifest.ID)
	}
}

func TestImportRejectsZipSlip(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	zipPath := filepath.Join(t.TempDir(), "evil.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	w, err := zw.Create("../../evil.txt")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write([]byte("evil")); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	if _, err := m.Import(zipPath); err == nil {
		t.Fatalf("expected zip-slip import to be rejected")
	}
}

func TestFetchLinkMetadataNotHandled(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"),
		testManifest("prettylinks", "youtube.com"))
	m := newTestManager(t, root)

	_, err := m.FetchLinkMetadata(context.Background(), "https://example.com/foo")
	if err != ErrNotHandled {
		t.Fatalf("expected ErrNotHandled, got %v", err)
	}
}

func TestFetchLinkMetadataDisabledPluginNotHandled(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"),
		testManifest("prettylinks", "youtube.com"))
	m := newTestManager(t, root)
	if err := m.SetEnabled("prettylinks", false); err != nil {
		t.Fatal(err)
	}

	_, err := m.FetchLinkMetadata(context.Background(), "https://youtube.com/watch?v=abc")
	if err != ErrNotHandled {
		t.Fatalf("expected disabled plugin to not handle url, got %v", err)
	}
}

func TestFetchLinkMetadataSuccess(t *testing.T) {
	var thumbSrv *httptest.Server
	oembedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(oEmbedResponse{
			Title:        "A Video",
			AuthorName:   "Someone",
			ThumbnailURL: thumbSrv.URL + "/thumb.jpg",
		})
	}))
	defer oembedSrv.Close()

	thumbSrv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		w.Write([]byte("fake-jpeg-bytes"))
	}))
	defer thumbSrv.Close()

	root := t.TempDir()
	manifest := testManifest("prettylinks", "youtube.com")
	manifest.Matchers[0].MetadataEndpoint = oembedSrv.URL + "/oembed?url={url}"
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"), manifest)

	m := newTestManager(t, root)
	metadata, err := m.FetchLinkMetadata(context.Background(), "https://youtube.com/watch?v=abc")
	if err != nil {
		t.Fatalf("FetchLinkMetadata: %v", err)
	}
	if metadata.Title != "A Video" || metadata.Author != "Someone" {
		t.Fatalf("unexpected metadata: %+v", metadata)
	}
	if metadata.ThumbnailB64 == "" {
		t.Fatalf("expected thumbnail bytes to be populated")
	}
}

func TestFetchLinkMetadataDescriptionFallback(t *testing.T) {
	oembedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(oEmbedResponse{
			Title:      "A Tweet",
			AuthorName: "Someone",
			HTML: `<blockquote class="twitter-tweet"><p lang="en" dir="ltr">Hello &amp; welcome ` +
				`<a href="https://t.co/xyz">https://t.co/xyz</a></p>&mdash; Someone (@someone)</blockquote>`,
		})
	}))
	defer oembedSrv.Close()

	// The oEmbed response has no thumbnail, so FetchLinkMetadata will try
	// an og:image fallback fetch against rawURL itself -- point rawURL at
	// this same local test server (rather than a real domain) so that
	// fallback request doesn't hit the network.
	host := testServerHost(t, oembedSrv.URL)
	root := t.TempDir()
	manifest := testManifest("prettylinks", host)
	manifest.Matchers[0].MetadataEndpoint = oembedSrv.URL + "/oembed?url={url}"
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"), manifest)

	m := newTestManager(t, root)
	metadata, err := m.FetchLinkMetadata(context.Background(), oembedSrv.URL+"/watch?v=abc")
	if err != nil {
		t.Fatalf("FetchLinkMetadata: %v", err)
	}
	wantDesc := "Hello & welcome https://t.co/xyz"
	if metadata.Description != wantDesc {
		t.Fatalf("unexpected description: got %q, want %q", metadata.Description, wantDesc)
	}
}

// TestFetchLinkMetadataDescriptionNoRunOnWords covers stripping tags that
// have no surrounding whitespace of their own in the source HTML (as
// Twitter/X's embed HTML does around @mentions) -- naively dropping such a
// tag would run the two sides together. It also covers that a <br> is
// preserved as a line break (paragraph structure) rather than flattened
// into a space.
func TestFetchLinkMetadataDescriptionNoRunOnWords(t *testing.T) {
	oembedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(oEmbedResponse{
			Title:      "A Tweet",
			AuthorName: "Someone",
			HTML: `<p lang="en" dir="ltr">Hello <a href="https://twitter.com/Mining_Dutch">@Mining_Dutch</a> and ` +
				`<a href="https://twitter.com/DigiByteCoin">@DigiByteCoin</a> team.<br>Second line here.</p>`,
		})
	}))
	defer oembedSrv.Close()

	// No thumbnail in the oEmbed response here either -- same reasoning as
	// TestFetchLinkMetadataDescriptionFallback for pointing rawURL at the
	// local server.
	host := testServerHost(t, oembedSrv.URL)
	root := t.TempDir()
	manifest := testManifest("prettylinks", host)
	manifest.Matchers[0].MetadataEndpoint = oembedSrv.URL + "/oembed?url={url}"
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"), manifest)

	m := newTestManager(t, root)
	metadata, err := m.FetchLinkMetadata(context.Background(), oembedSrv.URL+"/watch?v=abc")
	if err != nil {
		t.Fatalf("FetchLinkMetadata: %v", err)
	}
	wantDesc := "Hello @Mining_Dutch and @DigiByteCoin team.\nSecond line here."
	if metadata.Description != wantDesc {
		t.Fatalf("unexpected description: got %q, want %q", metadata.Description, wantDesc)
	}
}

// TestFetchLinkMetadataOpenGraphImageFallback covers a photo tweet: the
// oEmbed response carries no thumbnail_url at all (the oEmbed spec has no
// image field for a plain link/photo response), so FetchLinkMetadata should
// fall back to scraping og:image (and, since the oEmbed response here also
// has no description, og:description) from the linked page itself.
func TestFetchLinkMetadataOpenGraphImageFallback(t *testing.T) {
	var pageSrv *httptest.Server
	pageSrv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/photo.jpg" {
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write([]byte("fake-jpeg-bytes"))
			return
		}
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte(`<html><head>` +
			`<meta property="og:title" content="A Tweet">` +
			`<meta property="og:description" content="Tweet body from OG tags">` +
			`<meta property="og:image" content="` + pageSrv.URL + `/photo.jpg">` +
			`</head><body></body></html>`))
	}))
	defer pageSrv.Close()

	oembedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(oEmbedResponse{
			Title:      "A Tweet",
			AuthorName: "Someone",
			HTML:       `<p lang="en" dir="ltr"></p>`,
		})
	}))
	defer oembedSrv.Close()

	host := testServerHost(t, pageSrv.URL)
	root := t.TempDir()
	manifest := testManifest("prettylinks", host)
	manifest.Matchers[0].MetadataEndpoint = oembedSrv.URL + "/oembed?url={url}"
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"), manifest)

	m := newTestManager(t, root)
	metadata, err := m.FetchLinkMetadata(context.Background(), pageSrv.URL+"/status/123")
	if err != nil {
		t.Fatalf("FetchLinkMetadata: %v", err)
	}
	if metadata.ThumbnailB64 == "" {
		t.Fatalf("expected og:image to be fetched as the thumbnail")
	}
	if metadata.Description != "Tweet body from OG tags" {
		t.Fatalf("unexpected description: got %q", metadata.Description)
	}
}

func TestBuiltinSpellcheckAutoInstalledDisabledByDefault(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	plugin, ok := findPlugin(m.List(), "spellcheck")
	if !ok {
		t.Fatalf("expected bundled spellcheck plugin to be auto-installed")
	}
	if plugin.Enabled {
		t.Fatalf("expected bundled spellcheck plugin to be disabled by default")
	}
	if _, err := os.Stat(filepath.Join(root, installedDirName, "spellcheck", "words.txt")); err != nil {
		t.Fatalf("expected bundled dictionary written to disk: %v", err)
	}
}

func TestSpellcheckDataDisabledByDefault(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	data := m.SpellcheckData()
	if len(data.Words) != 0 || len(data.GrammarRules) != 0 {
		t.Fatalf("expected no spellcheck data while plugin disabled, got %+v", data)
	}
}

func TestSpellcheckDataOnceEnabled(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	if err := m.SetEnabled("spellcheck", true); err != nil {
		t.Fatal(err)
	}
	data := m.SpellcheckData()
	if len(data.Words) == 0 {
		t.Fatalf("expected non-empty dictionary once spellcheck is enabled")
	}
	if len(data.GrammarRules) == 0 {
		t.Fatalf("expected non-empty grammar rules once spellcheck is enabled")
	}
}

func spellcheckManifest(id, dictionary string, rules []GrammarRule) Manifest {
	return Manifest{
		ID:               id,
		Name:             "Test Spellcheck " + id,
		Version:          "1.0.0",
		Description:      "a test spellcheck plugin",
		EnabledByDefault: true,
		RendererKind:     RendererKindSpellCheck,
		Dictionary:       dictionary,
		GrammarRules:     rules,
	}
}

func TestSpellcheckDataMergesMultipleEnabledPlugins(t *testing.T) {
	root := t.TempDir()

	dir1 := filepath.Join(root, installedDirName, "custom1")
	writeManifest(t, dir1, spellcheckManifest("custom1", "words.txt",
		[]GrammarRule{{Pattern: "foo", Message: "m1", Suggest: "bar"}}))
	if err := os.WriteFile(filepath.Join(dir1, "words.txt"), []byte("hello\nworld\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	dir2 := filepath.Join(root, installedDirName, "custom2")
	writeManifest(t, dir2, spellcheckManifest("custom2", "words.txt", nil))
	if err := os.WriteFile(filepath.Join(dir2, "words.txt"), []byte("world\nagain\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	m := newTestManager(t, root)
	data := m.SpellcheckData()

	seen := make(map[string]bool)
	for _, w := range data.Words {
		seen[w] = true
	}
	if !seen["hello"] || !seen["world"] || !seen["again"] {
		t.Fatalf("expected merged words from both plugins, got %v", data.Words)
	}
	// "world" is declared by both plugins; it must not appear twice.
	count := 0
	for _, w := range data.Words {
		if w == "world" {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected deduplicated word list, \"world\" appeared %d times", count)
	}
	if len(data.GrammarRules) != 1 {
		t.Fatalf("expected 1 merged grammar rule, got %d", len(data.GrammarRules))
	}
}

func TestSpellcheckDataSkipsMissingDictionary(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "broken"),
		spellcheckManifest("broken", "missing.txt", nil))
	// Deliberately do not write missing.txt.

	m := newTestManager(t, root)
	data := m.SpellcheckData() // must not panic, just skip this plugin's words.
	if len(data.Words) != 0 {
		t.Fatalf("expected no words from a plugin with a missing dictionary file, got %v", data.Words)
	}
}

func TestSpellcheckManifestValidation(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	cases := []struct {
		name     string
		manifest Manifest
	}{
		{"missing dictionary", spellcheckManifest("t1", "", nil)},
		{"path traversal dictionary", spellcheckManifest("t2", "../../etc/passwd", nil)},
		{"dictionary with path separator", spellcheckManifest("t3", "sub/words.txt", nil)},
		{"too many grammar rules", func() Manifest {
			rules := make([]GrammarRule, maxGrammarRules+1)
			for i := range rules {
				rules[i] = GrammarRule{Pattern: "x", Message: "m"}
			}
			return spellcheckManifest("t4", "words.txt", rules)
		}()},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), c.manifest.ID)
			writeManifest(t, dir, c.manifest)
			if _, err := m.readManifest(dir); err == nil {
				t.Fatalf("expected validation error for %s", c.name)
			}
		})
	}
}

func TestFetchLinkMetadataRejectsBadContentType(t *testing.T) {
	var thumbSrv *httptest.Server
	oembedSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(oEmbedResponse{
			Title:        "A Video",
			ThumbnailURL: thumbSrv.URL + "/thumb.html",
		})
	}))
	defer oembedSrv.Close()

	thumbSrv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<html>not an image</html>"))
	}))
	defer thumbSrv.Close()

	root := t.TempDir()
	manifest := testManifest("prettylinks", "youtube.com")
	manifest.Matchers[0].MetadataEndpoint = oembedSrv.URL + "/oembed?url={url}"
	writeManifest(t, filepath.Join(root, installedDirName, "prettylinks"), manifest)

	m := newTestManager(t, root)
	metadata, err := m.FetchLinkMetadata(context.Background(), "https://youtube.com/watch?v=abc")
	if err != nil {
		t.Fatalf("FetchLinkMetadata should still succeed with degraded thumbnail: %v", err)
	}
	if metadata.ThumbnailB64 != "" {
		t.Fatalf("expected thumbnail to be rejected for bad content type")
	}
	if metadata.Title != "A Video" {
		t.Fatalf("expected text metadata to still be returned")
	}
}
