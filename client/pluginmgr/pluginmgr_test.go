package pluginmgr

import (
	"archive/zip"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr/builtin"
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
// ServiceLinkCard.
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

// A fresh manager has the plugins that ship with the client and nothing
// else. They are what the app's own features are written against -- a
// composer expects somebody to answer "spellcheck-data" -- so "no plugins at
// all" is no longer a state the client can be in.
func TestFreshManagerHasOnlyBuiltins(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	got := m.List()
	if len(got) != len(builtin.All()) {
		t.Fatalf("expected only the built-ins, got %d plugins", len(got))
	}
	for _, p := range got {
		if !p.Builtin {
			t.Fatalf("plugin %q is not marked built in", p.Manifest.ID)
		}
	}
	for _, bp := range builtin.All() {
		if _, ok := findPlugin(got, bp.ID); !ok {
			t.Fatalf("built-in %q is missing", bp.ID)
		}
	}
}

// The module has to actually be on disk under the directory wasmhost will
// look in, or the plugin is listed and then fails to load when consulted.
func TestBuiltinModuleIsWrittenOut(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	for _, bp := range builtin.All() {
		dir := m.InstallDir(bp.ID)
		manifest, err := m.readManifest(dir)
		if err != nil {
			t.Fatalf("built-in %q manifest: %v", bp.ID, err)
		}
		wasm := filepath.Join(dir, manifest.WasmFile)
		fi, err := os.Stat(wasm)
		if err != nil {
			t.Fatalf("built-in %q module: %v", bp.ID, err)
		}
		if fi.Size() == 0 {
			t.Fatalf("built-in %q module is empty", bp.ID)
		}
	}
}

// The second launch must not decompress several megabytes again.
func TestBuiltinIsNotRewrittenEveryLaunch(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	id := builtin.All()[0].ID
	manifest, err := m.readManifest(m.InstallDir(id))
	if err != nil {
		t.Fatalf("readManifest: %v", err)
	}
	wasm := filepath.Join(m.InstallDir(id), manifest.WasmFile)
	before, err := os.Stat(wasm)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}

	// Touch it to something recognisable, then start again over the same
	// root: an untouched file means the stamp did its job.
	stale := before.ModTime().Add(-time.Hour)
	if err := os.Chtimes(wasm, stale, stale); err != nil {
		t.Fatalf("chtimes: %v", err)
	}
	newTestManager(t, root)

	after, err := os.Stat(wasm)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if !after.ModTime().Equal(stale) {
		t.Fatalf("built-in %q was rewritten on the second launch", id)
	}
}

func TestBuiltinCannotBeRemoved(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	id := builtin.All()[0].ID
	if err := m.Remove(id); err == nil {
		t.Fatalf("expected removing a built-in to fail")
	}
	if _, ok := findPlugin(m.List(), id); !ok {
		t.Fatalf("built-in %q went missing after a refused remove", id)
	}
}

// Disabling is what removing means for a built-in, and it has to work.
func TestBuiltinCanBeDisabled(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	id := builtin.All()[0].ID
	if err := m.SetEnabled(id, true); err != nil {
		t.Fatalf("SetEnabled: %v", err)
	}
	if err := m.SetEnabled(id, false); err != nil {
		t.Fatalf("SetEnabled: %v", err)
	}
	p, ok := findPlugin(m.List(), id)
	if !ok || p.Enabled {
		t.Fatalf("expected built-in %q to be disabled", id)
	}
}

// An import claiming a built-in's id could otherwise replace a shipped
// feature with anything, under a name the settings page still shows once.
func TestImportCannotReplaceABuiltin(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	id := builtin.All()[0].ID
	src := filepath.Join(t.TempDir(), "evil")
	writeManifest(t, src, testManifest(id))

	if _, err := m.Import(src); err == nil {
		t.Fatalf("expected importing over a built-in to fail")
	}
	p, ok := findPlugin(m.List(), id)
	if !ok || !p.Builtin {
		t.Fatalf("built-in %q was replaced", id)
	}
}

// A folder put there by hand, or left over from before the plugin shipped,
// must not win over what the app was built against.
func TestInstalledDoesNotShadowABuiltin(t *testing.T) {
	root := t.TempDir()
	id := builtin.All()[0].ID
	writeManifest(t, filepath.Join(root, installedDirName, id), testManifest(id))

	m := newTestManager(t, root)
	p, ok := findPlugin(m.List(), id)
	if !ok {
		t.Fatalf("built-in %q is missing", id)
	}
	if !p.Builtin {
		t.Fatalf("the installed copy shadowed the built-in")
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
		{"contributes nothing and provides nothing", func() Manifest {
			m := testManifest("t4")
			m.Screens = nil
			m.NavLabel = ""
			return m
		}()},
		{"duplicate screen ids", func() Manifest {
			m := testManifest("t5")
			m.Screens = []ScreenDef{{ID: "a", Label: "A"}, {ID: "a", Label: "B"}}
			return m
		}()},
		{"service name with disallowed characters",
			testCapabilityManifest("t6", "not a real service")},
		{"link-card with invalid domain", testCapabilityManifest("t8", ServiceLinkCard, "not a domain")},
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
		testCapabilityManifest("headless", ServiceSpellcheckData))

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "headless")
	if !ok {
		t.Fatalf("expected headless capability-only plugin to load")
	}
	if len(plugin.Manifest.Screens) != 0 || plugin.Manifest.NavLabel != "" {
		t.Fatalf("expected no nav item on a headless plugin, got %+v", plugin.Manifest)
	}
}

func TestPluginsProviding(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "sc1"),
		testCapabilityManifest("sc1", ServiceSpellcheckData))
	writeManifest(t, filepath.Join(root, installedDirName, "sc2-disabled"), func() Manifest {
		m := testCapabilityManifest("sc2-disabled", ServiceSpellcheckData)
		m.EnabledByDefault = false
		return m
	}())
	writeManifest(t, filepath.Join(root, installedDirName, "lc1"),
		testCapabilityManifest("lc1", ServiceLinkCard, "example.com"))

	m := newTestManager(t, root)

	sc := m.PluginsProviding(ServiceSpellcheckData)
	if len(sc) != 1 || sc[0].ID != "sc1" {
		t.Fatalf("PluginsProviding(spellcheck-data) = %+v, want just [sc1] (sc2 is disabled)", sc)
	}

	lc := m.PluginsProviding(ServiceLinkCard)
	if len(lc) != 1 || lc[0].ID != "lc1" {
		t.Fatalf("PluginsProviding(link-card) = %+v, want just [lc1]", lc)
	}

	none := m.PluginsProviding("nonexistent-capability")
	if len(none) != 0 {
		t.Fatalf("PluginsProviding(nonexistent) = %+v, want empty", none)
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

// TestImportRejectsZipBomb covers the guard that replaced a blanket size
// cap. A bomb is defined by how far it expands, not by how big it is: this
// archive is a few KB on disk and would write 40MB of zeros, which no
// absolute limit small enough to be useful would catch without also
// rejecting legitimate plugins that merely ship data.
func TestImportRejectsZipBomb(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	zipPath := filepath.Join(t.TempDir(), "bomb.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	manifestBytes, _ := json.Marshal(testManifest("bomb"))
	w, err := zw.Create("bomb/manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(manifestBytes); err != nil {
		t.Fatal(err)
	}
	// Zeros compress to almost nothing, which is the whole trick.
	w, err = zw.Create("bomb/payload.bin")
	if err != nil {
		t.Fatal(err)
	}
	zeros := make([]byte, 1024*1024)
	for i := 0; i < 40; i++ {
		if _, err := w.Write(zeros); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	fi, err := os.Stat(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("bomb is %d bytes on disk, expands to ~40MB", fi.Size())

	if _, err := m.Import(zipPath); err == nil {
		t.Error("expected a zip bomb to be rejected")
	} else {
		t.Logf("rejected: %v", err)
	}
}

// TestImportAllowsADataBearingPlugin is the other half of the same change:
// the limit must not reject a plugin that is simply large. This one carries
// 8MB of incompressible content -- roughly what a dictionary costs -- at a
// ratio no bomb detector should object to.
func TestImportAllowsADataBearingPlugin(t *testing.T) {
	root := t.TempDir()
	m := newTestManager(t, root)

	zipPath := filepath.Join(t.TempDir(), "big.zip")
	f, err := os.Create(zipPath)
	if err != nil {
		t.Fatal(err)
	}
	zw := zip.NewWriter(f)
	manifestBytes, _ := json.Marshal(testManifest("big"))
	w, err := zw.Create("big/manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := w.Write(manifestBytes); err != nil {
		t.Fatal(err)
	}
	w, err = zw.Create("big/plugin.wasm")
	if err != nil {
		t.Fatal(err)
	}
	// Pseudo-random bytes so the archive cannot compress meaningfully,
	// which is what a real wasm module looks like to a zip.
	payload := make([]byte, 8*1024*1024)
	seed := uint32(1)
	for i := range payload {
		seed = seed*1664525 + 1013904223
		payload[i] = byte(seed >> 24)
	}
	if _, err := w.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}

	if _, err := m.Import(zipPath); err != nil {
		t.Errorf("a large but honest plugin was rejected: %v", err)
	}
}

// TestUnknownServiceIsAccepted is the point of Provides replacing the old
// capability allowlist: a plugin may declare a service this build has never
// heard of, and it installs.
//
// It was previously rejected at import, which meant a third party could not
// ship a new kind of plugin at all without a change to this package. A
// service nothing consumes is inert -- nobody ever calls it -- which is a
// cost of nothing, against the cost of being the gatekeeper for every idea
// anyone else has.
func TestUnknownServiceIsAccepted(t *testing.T) {
	root := t.TempDir()
	writeManifest(t, filepath.Join(root, installedDirName, "novel"),
		testCapabilityManifest("novel", "nobody-has-heard-of-this"))

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "novel")
	if !ok {
		t.Fatal("a plugin providing an unknown service should still install")
	}
	if got, _ := plugin.Manifest.ServiceExport("nobody-has-heard-of-this"); got !=
		"nobody_has_heard_of_this" {
		t.Errorf("export = %q, want the dashes-to-underscores default", got)
	}
	if len(m.PluginsProviding("nobody-has-heard-of-this")) != 1 {
		t.Error("an unknown service should still be routable to its provider")
	}
}

// TestLegacyManifestKeysStillLoad is the compatibility promise: a plugin
// built and shipped before Contributes/Provides existed is an artifact
// somebody else owns, and upgrading this package must not stop it loading.
func TestLegacyManifestKeysStillLoad(t *testing.T) {
	root := t.TempDir()
	legacy := testManifest("legacy")
	legacy.Capabilities = []string{ServiceThesaurus}
	writeManifest(t, filepath.Join(root, installedDirName, "legacy"), legacy)

	m := newTestManager(t, root)
	plugin, ok := findPlugin(m.List(), "legacy")
	if !ok {
		t.Fatal("a legacy manifest should still load")
	}

	nav := plugin.Manifest.ContributionsTo(SlotNav)
	if len(nav) != 1 {
		t.Fatalf("navLabel/screens should become one %s contribution, got %d",
			SlotNav, len(nav))
	}
	if nav[0].Label != legacy.NavLabel {
		t.Errorf("nav label = %q, want %q", nav[0].Label, legacy.NavLabel)
	}
	if len(nav[0].Screens) != len(legacy.Screens) {
		t.Errorf("nav screens = %d, want %d", len(nav[0].Screens), len(legacy.Screens))
	}
	if export, ok := plugin.Manifest.ServiceExport(ServiceThesaurus); !ok ||
		export != "lookup_synonyms" {
		t.Errorf("thesaurus export = %q (%v), want lookup_synonyms", export, ok)
	}
}

// TestSlotManifestLoads is the other half of the compatibility promise: a
// manifest written natively in the new style, with contributions to several
// slots and no nav item at all.
//
// The last case is the one worth having. Before slots, a plugin's only way to
// offer a settings page was to make it a sub-page of a top-level nav tab --
// so a plugin that wanted to configure itself had to take a place in the main
// navigation whether it wanted one or not.
func TestSlotManifestLoads(t *testing.T) {
	root := t.TempDir()
	m := Manifest{
		ID:               "slots",
		Name:             "Slotted",
		Version:          "1.0.0",
		Description:      "a plugin that appears in two places and owns no tab",
		Schema:           CurrentSchema,
		EnabledByDefault: true,
		RendererKind:     RendererKindDynamicWasm,
		WasmFile:         "plugin.wasm",
		Contributes: map[string][]Contribution{
			SlotSettingsPage: {{ID: "prefs", Label: "Slotted Settings", Icon: "settings"}},
			SlotComposerAction: {
				{ID: "insert", Label: "Insert something", Icon: "link"},
			},
			// A slot this build has never drawn. It must survive import and
			// simply never be asked for -- the property that lets a plugin
			// target a later host without failing to install on this one.
			"someSlotFromALaterVersion": {{ID: "x", Label: "X"}},
		},
	}
	writeManifest(t, filepath.Join(root, installedDirName, "slots"), m)

	mgr := newTestManager(t, root)
	plugin, ok := findPlugin(mgr.List(), "slots")
	if !ok {
		t.Fatal("a manifest with no nav item but real contributions should load")
	}

	settings := plugin.Manifest.ContributionsTo(SlotSettingsPage)
	if len(settings) != 1 || settings[0].Label != "Slotted Settings" {
		t.Errorf("settingsPage contributions = %+v", settings)
	}
	if len(plugin.Manifest.ContributionsTo(SlotComposerAction)) != 1 {
		t.Error("composerAction contribution did not survive")
	}
	if len(plugin.Manifest.ContributionsTo("someSlotFromALaterVersion")) != 1 {
		t.Error("a contribution to an unimplemented slot should be kept, not dropped")
	}
	if len(plugin.Manifest.ContributionsTo(SlotNav)) != 0 {
		t.Error("nothing should have invented a nav item")
	}
}
