package wasmhost

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

// buildFixture compiles testdata/fixture into a plugin.wasm under a fresh
// temp "installed/<id>/" directory, the same layout pluginmgr.Manager uses,
// and returns the wasm file's path.
func buildFixture(t *testing.T, root, id string) string {
	t.Helper()
	return buildFixtureFrom(t, root, id, "testdata/fixture")
}

// buildFixtureFrom is buildFixture with an explicit fixture source
// directory, for tests exercising a fixture other than the default (e.g.
// testdata/fixture_headless).
func buildFixtureFrom(t *testing.T, root, id, fixtureRelDir string) string {
	t.Helper()

	pluginDir := filepath.Join(root, "installed", id)
	if err := os.MkdirAll(pluginDir, 0o700); err != nil {
		t.Fatalf("mkdir %s: %v", pluginDir, err)
	}

	wasmPath := filepath.Join(pluginDir, "plugin.wasm")
	fixtureDir, err := filepath.Abs(fixtureRelDir)
	if err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("go", "build", "-buildmode=c-shared", "-o", wasmPath, ".")
	cmd.Dir = fixtureDir
	cmd.Env = append(cmd.Environ(), "GOOS=wasip1", "GOARCH=wasm")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("building fixture wasm: %v\n%s", err, out)
	}
	return wasmPath
}

func newTestRuntime(t *testing.T) (*Runtime, string) {
	t.Helper()
	ctx := context.Background()
	root := t.TempDir()

	r, err := NewRuntime(ctx, Config{
		Root:       root,
		HTTPClient: http.DefaultClient,
	})
	if err != nil {
		t.Fatalf("NewRuntime: %v", err)
	}
	t.Cleanup(func() { r.Close(ctx) })
	return r, root
}

func TestLoadRenderScreenHandleEvent(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "fixture1")
	if err := r.Load(ctx, "fixture1", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	ui, err := r.RenderScreen(ctx, "fixture1", "feeds")
	if err != nil {
		t.Fatalf("RenderScreen: %v", err)
	}
	if ui.Title != "feeds" {
		t.Errorf("Title = %q, want %q", ui.Title, "feeds")
	}
	if len(ui.Widgets) != 1 || ui.Widgets[0].Type != "text" {
		t.Errorf("unexpected widgets: %+v", ui.Widgets)
	}
	wantText := "hello from feeds"
	if ui.Widgets[0].Text != wantText {
		t.Errorf("Widgets[0].Text = %q, want %q", ui.Widgets[0].Text, wantText)
	}

	ui, err = r.HandleEvent(ctx, "fixture1", "add", "addFeed", map[string]any{"url": "https://example.com/rss"})
	if err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}
	if ui.Title != "handled addFeed" {
		t.Errorf("Title = %q, want %q", ui.Title, "handled addFeed")
	}

	// The event handler persists the event name and payload via kv_set;
	// confirm it landed in the plugin's data.json on disk.
	dataPath := filepath.Join(root, "data", "fixture1", "data.json")
	var kv map[string]string
	readJSONFile(t, dataPath, &kv)
	if kv["last_event"] != "addFeed" {
		t.Errorf("persisted last_event = %q, want %q", kv["last_event"], "addFeed")
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(kv["last_payload"]), &payload); err != nil {
		t.Fatalf("last_payload not valid json: %v", err)
	}
	if payload["url"] != "https://example.com/rss" {
		t.Errorf("persisted payload url = %v, want %q", payload["url"], "https://example.com/rss")
	}
}

func TestPollFetchesAndPersists(t *testing.T) {
	ctx := context.Background()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("<rss>fake feed body</rss>"))
	}))
	defer srv.Close()

	root := t.TempDir()
	r, err := NewRuntime(ctx, Config{Root: root, HTTPClient: srv.Client()})
	if err != nil {
		t.Fatalf("NewRuntime: %v", err)
	}
	defer r.Close(ctx)

	// The fixture always fetches a fixed (unreachable) URL rather than one
	// we control, so instead we point the test's http.Client's transport
	// at the test server via DefaultTransport override is unnecessary --
	// the fixture's fetch_url call goes through Config.HTTPClient
	// regardless of hostname since hostFetchURL does a plain http.Get.
	// Redirect all requests to our test server by using its client with a
	// custom transport that rewrites the URL.
	r.cfg.HTTPClient = &http.Client{
		Transport: rewriteToTransport{target: srv.URL},
	}

	wasmPath := buildFixture(t, root, "fixture2")
	if err := r.Load(ctx, "fixture2", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	if err := r.Poll(ctx, "fixture2"); err != nil {
		t.Fatalf("Poll: %v", err)
	}

	dataPath := filepath.Join(root, "data", "fixture2", "data.json")
	var kv map[string]string
	readJSONFile(t, dataPath, &kv)
	if kv["last_poll_body"] != "<rss>fake feed body</rss>" {
		t.Errorf("last_poll_body = %q, want the fake feed body", kv["last_poll_body"])
	}
	if kv["poll_count"] != "1" {
		t.Errorf("poll_count = %q, want %q", kv["poll_count"], "1")
	}

	// Regression check for a real bug: wazero defaults every module's
	// time.Now() to a FAKE clock (fixed epoch, +1ms per read) unless the
	// host opts into WithSysWalltime. Confirm the guest's clock is within
	// a generous window of the real time, not near wazero's fake epoch.
	pollTimeUnix, err := strconv.ParseInt(kv["poll_time_unix"], 10, 64)
	if err != nil {
		t.Fatalf("poll_time_unix = %q, not a valid unix timestamp: %v", kv["poll_time_unix"], err)
	}
	if delta := time.Since(time.Unix(pollTimeUnix, 0)); delta < -time.Minute || delta > time.Minute {
		t.Errorf("guest's time.Now() during poll() was %v off real time -- "+
			"is the wazero module missing WithSysWalltime()?", delta)
	}

	// A second poll should observe the kv_get'd previous count and bump it,
	// proving kv_get (host->guest data return) round-trips correctly too.
	if err := r.Poll(ctx, "fixture2"); err != nil {
		t.Fatalf("second Poll: %v", err)
	}
	readJSONFile(t, dataPath, &kv)
	if kv["poll_count"] != "2" {
		t.Errorf("poll_count after second poll = %q, want %q", kv["poll_count"], "2")
	}
}

func TestUnloadStopsPollingAndFreesModule(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "fixture3")
	if err := r.Load(ctx, "fixture3", wasmPath, MinPollInterval); err != nil {
		t.Fatalf("Load: %v", err)
	}

	r.Unload("fixture3")

	if _, err := r.RenderScreen(ctx, "fixture3", "feeds"); err == nil {
		t.Errorf("RenderScreen after Unload succeeded, want error")
	}

	// Unloading twice, or unloading something never loaded, must not panic.
	r.Unload("fixture3")
	r.Unload("never-loaded")
}

// TestDataSurvivesReinstall is the regression test for a real reported
// bug: pluginmgr.Manager.Import wholesale os.RemoveAll's and recreates
// installed/<id>/ on every import, including a same-ID update -- so data
// stored under that directory (the original design) was silently wiped
// every time a user updated a plugin to a newer version. Data now lives
// under Root/data/<id>/, entirely outside the directory Import replaces.
func TestDataSurvivesReinstall(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "fixture4")
	if err := r.Load(ctx, "fixture4", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if _, err := r.HandleEvent(ctx, "fixture4", "add", "addFeed", map[string]any{"url": "https://example.com/rss"}); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}

	// Simulate pluginmgr.Manager.Import's update path: wipe and recreate
	// installed/<id>/ (a fresh wasm build stands in for "a newer version"),
	// then Load the same id again -- exactly what happens on a plugin
	// update/re-import.
	installedDir := filepath.Join(root, "installed", "fixture4")
	if err := os.RemoveAll(installedDir); err != nil {
		t.Fatalf("removing installed dir: %v", err)
	}
	newWasmPath := buildFixture(t, root, "fixture4")
	if err := r.Load(ctx, "fixture4", newWasmPath, 0); err != nil {
		t.Fatalf("Load (reinstall): %v", err)
	}

	dataPath := filepath.Join(root, "data", "fixture4", "data.json")
	var kv map[string]string
	readJSONFile(t, dataPath, &kv)
	if kv["last_event"] != "addFeed" {
		t.Errorf("data lost across reinstall: last_event = %q, want %q", kv["last_event"], "addFeed")
	}
}

// TestMigrateLegacyData confirms upgrading wasmhost itself (which moved
// data.json's location) doesn't look like a data-losing update to a user
// who already has a plugin installed under the old layout.
func TestMigrateLegacyData(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "fixture6")
	// Simulate a pre-migration install: data.json alongside the plugin's
	// own files, written before Load ever runs (i.e. as if by an older
	// wasmhost version).
	legacyPath := filepath.Join(filepath.Dir(wasmPath), "data.json")
	if err := os.WriteFile(legacyPath, []byte(`{"last_event":"legacyValue"}`), 0o600); err != nil {
		t.Fatalf("writing legacy data.json: %v", err)
	}

	if err := r.Load(ctx, "fixture6", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	dataPath := filepath.Join(root, "data", "fixture6", "data.json")
	var kv map[string]string
	readJSONFile(t, dataPath, &kv)
	if kv["last_event"] != "legacyValue" {
		t.Errorf("legacy data not migrated: kv = %+v", kv)
	}
}

func TestDeleteDataRemovesPersistedData(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "fixture5")
	if err := r.Load(ctx, "fixture5", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}
	if _, err := r.HandleEvent(ctx, "fixture5", "add", "addFeed", nil); err != nil {
		t.Fatalf("HandleEvent: %v", err)
	}

	dataPath := filepath.Join(root, "data", "fixture5", "data.json")
	if _, err := os.Stat(dataPath); err != nil {
		t.Fatalf("data.json missing before DeleteData: %v", err)
	}

	if err := r.DeleteData("fixture5"); err != nil {
		t.Fatalf("DeleteData: %v", err)
	}
	if _, err := os.Stat(dataPath); !os.IsNotExist(err) {
		t.Errorf("data.json still present after DeleteData (err=%v)", err)
	}
}

// rewriteToTransport is a http.RoundTripper that redirects every request to
// target, used so the fixture's hardcoded fetch_url("https://example.invalid/feed")
// call actually reaches our httptest server.
type rewriteToTransport struct {
	target string
}

func (t rewriteToTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	newURL, err := req.URL.Parse(t.target)
	if err != nil {
		return nil, err
	}
	req = req.Clone(req.Context())
	req.URL = newURL
	req.Host = newURL.Host
	return http.DefaultTransport.RoundTrip(req)
}

func readJSONFile(t *testing.T, path string, out any) {
	t.Helper()
	b, err := readFileCapped(path, 1024*1024)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	if err := json.Unmarshal(b, out); err != nil {
		t.Fatalf("unmarshaling %s: %v", path, err)
	}
}

// TestHeadlessPluginLoadsAndServesCapabilities confirms a plugin exporting
// only alloc + get_spellcheck_data + fetch_link_card (no
// render_screen/handle_event/poll -- i.e. a Capabilities-only, no-nav-item
// plugin) loads successfully and its capability exports work. fetch_link_card in the
// fixture is implemented via fetch_url_ex plus fetch_last_status/
// fetch_last_content_type (not plain fetch_url), so this also exercises
// those three host functions end-to-end through the real
// Runtime.FetchLinkCard path.
func TestHeadlessPluginLoadsAndServesCapabilities(t *testing.T) {
	ctx := context.Background()

	var gotHeader string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		gotHeader = req.Header.Get("X-Test-Header")
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.Write([]byte("fetched body"))
	}))
	defer srv.Close()

	root := t.TempDir()
	r, err := NewRuntime(ctx, Config{
		Root:       root,
		HTTPClient: &http.Client{Transport: rewriteToTransport{target: srv.URL}},
	})
	if err != nil {
		t.Fatalf("NewRuntime: %v", err)
	}
	defer r.Close(ctx)

	wasmPath := buildFixtureFrom(t, root, "headless1", "testdata/fixture_headless")
	if err := r.Load(ctx, "headless1", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	data, err := r.GetSpellcheckData(ctx, "headless1")
	if err != nil {
		t.Fatalf("GetSpellcheckData: %v", err)
	}
	if len(data.Words) != 2 || data.Words[0] != "hello" || data.Words[1] != "world" {
		t.Errorf("GetSpellcheckData words = %v, want [hello world]", data.Words)
	}
	if len(data.GrammarRules) != 1 || data.GrammarRules[0].Pattern != "foo" {
		t.Errorf("GetSpellcheckData grammarRules = %+v", data.GrammarRules)
	}

	metadata, err := r.FetchLinkCard(ctx, "headless1", "https://example.invalid/thing")
	if err != nil {
		t.Fatalf("FetchLinkCard: %v", err)
	}
	want := "body=fetched body status=200 contentType=text/plain; charset=utf-8"
	if metadata.Title != want {
		t.Errorf("FetchLinkCard title = %q, want %q", metadata.Title, want)
	}
	if gotHeader != "custom-value" {
		t.Errorf("server saw X-Test-Header = %q, want %q", gotHeader, "custom-value")
	}
}

// TestHeadlessPluginRejectsScreenCalls confirms calling RenderScreen/
// HandleEvent/Poll against a plugin that doesn't export them fails cleanly
// (a clear error) rather than panicking/crashing the host.
func TestHeadlessPluginRejectsScreenCalls(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixtureFrom(t, root, "headless2", "testdata/fixture_headless")
	if err := r.Load(ctx, "headless2", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	if _, err := r.RenderScreen(ctx, "headless2", "feeds"); err == nil {
		t.Error("RenderScreen against a headless plugin succeeded, want error")
	}
	if _, err := r.HandleEvent(ctx, "headless2", "feeds", "someEvent", nil); err == nil {
		t.Error("HandleEvent against a headless plugin succeeded, want error")
	}
	if err := r.Poll(ctx, "headless2"); err == nil {
		t.Error("Poll against a headless plugin succeeded, want error")
	}
}

// TestScreenedPluginRejectsCapabilityCalls is the mirror image: the
// existing screened fixture doesn't export get_spellcheck_data/
// fetch_link_card, so those should also fail cleanly.
func TestScreenedPluginRejectsCapabilityCalls(t *testing.T) {
	ctx := context.Background()
	r, root := newTestRuntime(t)

	wasmPath := buildFixture(t, root, "screened1")
	if err := r.Load(ctx, "screened1", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	if _, err := r.GetSpellcheckData(ctx, "screened1"); err == nil {
		t.Error("GetSpellcheckData against a screened-only plugin succeeded, want error")
	}
	if _, err := r.FetchLinkCard(ctx, "screened1", "https://example.com"); err == nil {
		t.Error("FetchLinkCard against a screened-only plugin succeeded, want error")
	}
}

// TestConcurrentCallsDoNotCorruptInstance guards against a real bug found in
// production: a single wasm module instance has one linear memory and one
// execution stack, and wazero does not itself serialize concurrent calls
// into the same instance. Several LinkCard widgets fetching previews
// concurrently (e.g. a chat scrolling into view with multiple links at
// once) drove this to a wasm trap ("invalid table access") before
// pluginInst grew a callMtx serializing every guest call. This fires many
// concurrent FetchLinkCard calls against one instance and requires all of
// them to succeed with the expected result, not merely "not panic".
func TestConcurrentCallsDoNotCorruptInstance(t *testing.T) {
	ctx := context.Background()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		w.Write([]byte("fetched body"))
	}))
	defer srv.Close()

	root := t.TempDir()
	r, err := NewRuntime(ctx, Config{
		Root:       root,
		HTTPClient: &http.Client{Transport: rewriteToTransport{target: srv.URL}},
	})
	if err != nil {
		t.Fatalf("NewRuntime: %v", err)
	}
	defer r.Close(ctx)

	wasmPath := buildFixtureFrom(t, root, "concurrent1", "testdata/fixture_headless")
	if err := r.Load(ctx, "concurrent1", wasmPath, 0); err != nil {
		t.Fatalf("Load: %v", err)
	}

	const n = 20
	errs := make(chan error, n)
	for i := 0; i < n; i++ {
		go func() {
			metadata, err := r.FetchLinkCard(ctx, "concurrent1", "https://example.invalid/thing")
			if err != nil {
				errs <- err
				return
			}
			want := "body=fetched body status=200 contentType="
			if len(metadata.Title) < len(want) || metadata.Title[:len(want)] != want {
				errs <- fmt.Errorf("unexpected title %q", metadata.Title)
				return
			}
			errs <- nil
		}()
	}
	for i := 0; i < n; i++ {
		if err := <-errs; err != nil {
			t.Errorf("concurrent FetchLinkCard call %d failed: %v", i, err)
		}
	}
}
