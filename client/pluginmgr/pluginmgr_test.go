package pluginmgr

import (
	"archive/zip"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

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

func findPlugin(plugins []Plugin, id string) (Plugin, bool) {
	for _, p := range plugins {
		if p.Manifest.ID == id {
			return p, true
		}
	}
	return Plugin{}, false
}

// testManifest returns a minimal valid manifest with a nav item (one
// screen) -- the "has a UI" shape. Use testCapabilityManifest for the
// headless shape.
func testManifest(id string) Manifest {
	return Manifest{
		ID:               id,
		Name:             "Test Plugin " + id,
		Version:          "1.0.0",
		Description:      "a test plugin",
		EnabledByDefault: true,
		RendererKind:     RendererKindDynamicWasm,
		WasmFile:         "plugin.wasm",
		NavLabel:         "Test",
		Screens:          []ScreenDef{{ID: "main", Label: "Main"}},
	}
}

// testCapabilityManifest returns a minimal valid headless manifest (no nav
// item) declaring capability, plus domains if capability is
// CapabilityLinkCard.
func testCapabilityManifest(id, capability string, domains ...string) Manifest {
	return Manifest{
		ID:               id,
		Name:             "Test Plugin " + id,
		Version:          "1.0.0",
		Description:      "a test plugin",
		EnabledByDefault: true,
		RendererKind:     RendererKindDynamicWasm,
		WasmFile:         "plugin.wasm",
		Capabilities:     []string{capability},
		Domains:          domains,
	}
}

func newTestManager(t *testing.T, root string) *Manager {
	t.Helper()
	m, err := NewManager(Config{
		Root: root,
	})
	if err != nil {
		t.Fatalf("NewManager: %v", err)
	}
	return m
}

func TestLoadInstalledAndDefaults(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "myplugin"), testManifest("myplugin"))

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "myplugin")
	if !ok {
		t.Fatalf("expected myplugin to be loaded")
	}
	if !plugin.Enabled {
		t.Fatalf("expected plugin enabled by default")
	}
}

func TestFreshManagerHasNoPlugins(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)
	if got := m.List(); len(got) != 0 {
		t.Fatalf("expected a fresh manager to have no plugins, got %+v", got)
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
	writeManifest(t, filepath.Join(root, installedDirName, "dirname"), testManifest("differentid"))

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
	writeManifest(t, filepath.Join(root, installedDirName, "myplugin"), testManifest("myplugin"))

	m := newTestManager(t, root)
	if err := m.SetEnabled("myplugin", false); err != nil {
		t.Fatal(err)
	}

	m2 := newTestManager(t, root)
	plugin, ok := findPlugin(m2.List(), "myplugin")
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
	writeManifest(t, filepath.Join(root, installedDirName, "myplugin"), testManifest("myplugin"))

	m := newTestManager(t, root)
	if err := m.Remove("myplugin"); err != nil {
		t.Fatal(err)
	}
	if _, ok := findPlugin(m.List(), "myplugin"); ok {
		t.Fatalf("expected plugin removed")
	}
	if _, err := os.Stat(filepath.Join(root, installedDirName, "myplugin")); !os.IsNotExist(err) {
		t.Fatalf("expected plugin dir removed from disk")
	}
}

func TestImportFromDir(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	srcDir := t.TempDir()
	writeManifest(t, srcDir, testManifest("imported"))

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
	manifest := testManifest("zipped")
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

func TestManifestValidation(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	cases := []struct {
		name     string
		manifest Manifest
	}{
		{"missing wasmFile", func() Manifest { m := testManifest("t1"); m.WasmFile = ""; return m }()},
		{"wasmFile without .wasm suffix", func() Manifest { m := testManifest("t2"); m.WasmFile = "plugin.exe"; return m }()},
		{"screens without navLabel", func() Manifest { m := testManifest("t3"); m.NavLabel = ""; return m }()},
		{"neither screens nor capabilities", func() Manifest {
			m := testManifest("t4")
			m.Screens = nil
			return m
		}()},
		{"duplicate screen ids", func() Manifest {
			m := testManifest("t5")
			m.Screens = []ScreenDef{{ID: "a", Label: "A"}, {ID: "a", Label: "B"}}
			return m
		}()},
		{"unknown capability", testCapabilityManifest("t6", "not-a-real-capability")},
		{"link-card without domains", testCapabilityManifest("t7", CapabilityLinkCard)},
		{"link-card with invalid domain", testCapabilityManifest("t8", CapabilityLinkCard, "not a domain")},
		{"negative pollIntervalSeconds", func() Manifest {
			m := testManifest("t9")
			m.PollIntervalSeconds = -1
			return m
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

func TestHeadlessCapabilityOnlyManifestIsValid(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "headless"),
		testCapabilityManifest("headless", CapabilitySpellcheckData))

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "headless")
	if !ok {
		t.Fatalf("expected headless capability-only plugin to load")
	}
	if len(plugin.Manifest.Screens) != 0 || plugin.Manifest.NavLabel != "" {
		t.Fatalf("expected no nav item on a headless plugin, got %+v", plugin.Manifest)
	}
}

func TestPluginsWithCapability(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "sc1"),
		testCapabilityManifest("sc1", CapabilitySpellcheckData))
	writeManifest(t, filepath.Join(root, installedDirName, "sc2-disabled"), func() Manifest {
		m := testCapabilityManifest("sc2-disabled", CapabilitySpellcheckData)
		m.EnabledByDefault = false
		return m
	}())
	writeManifest(t, filepath.Join(root, installedDirName, "lc1"),
		testCapabilityManifest("lc1", CapabilityLinkCard, "example.com"))

	m := newTestManager(t, root)

	sc := m.PluginsWithCapability(CapabilitySpellcheckData)
	if len(sc) != 1 || sc[0].ID != "sc1" {
		t.Fatalf("PluginsWithCapability(spellcheck-data) = %+v, want just [sc1] (sc2 is disabled)", sc)
	}

	lc := m.PluginsWithCapability(CapabilityLinkCard)
	if len(lc) != 1 || lc[0].ID != "lc1" {
		t.Fatalf("PluginsWithCapability(link-card) = %+v, want just [lc1]", lc)
	}

	none := m.PluginsWithCapability("nonexistent-capability")
	if len(none) != 0 {
		t.Fatalf("PluginsWithCapability(nonexistent) = %+v, want empty", none)
	}
}

func TestNormalizeHost(t *testing.T) {
	cases := map[string]string{
		"example.com":     "example.com",
		"www.example.com": "example.com",
		"EXAMPLE.com":     "example.com",
		"WWW.Example.com": "example.com",
	}
	for in, want := range cases {
		if got := NormalizeHost(in); got != want {
			t.Errorf("NormalizeHost(%q) = %q, want %q", in, got, want)
		}
	}
}
