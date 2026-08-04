// Package pluginmgr implements a small, manifest-driven plugin system for
// bruig. Plugins are self-contained folders (installed under Config.Root)
// carrying a JSON manifest. There is exactly one renderer kind,
// RendererKindDynamicWasm: the manifest names a WebAssembly module
// (sandboxed by client/pluginmgr/wasmhost, see that package's doc for the
// execution model) that contributes its own top-level nav item + screens,
// or one or more headless "capabilities" (data the plugin supplies without
// any UI of its own -- see Manifest.Capabilities), or both. pluginmgr
// itself only manages the manifest lifecycle (install/enable/remove) and
// validation; wasmhost is what actually loads and calls into a plugin's
// code.
package pluginmgr

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"

	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/decred/slog"
)

const (
	installedDirName = "installed"
	stateFileName    = "state.json"
	manifestFileName = "manifest.json"

	// RendererKindDynamicWasm is the only renderer kind: Manifest.WasmFile
	// names a WebAssembly module (sandboxed by client/pluginmgr/wasmhost)
	// that contributes its own top-level nav item (Manifest.NavLabel/
	// NavIcon) and screens (Manifest.Screens), a set of headless
	// Capabilities, or both.
	RendererKindDynamicWasm = "dynamic-wasm"

	// CapabilitySpellcheckData means this plugin supplies a wordlist and
	// grammar-rule set, merged with every other enabled spellcheck-data
	// plugin's. See client/pluginmgr/capabilities for the contract.
	CapabilitySpellcheckData = "spellcheck-data"

	// CapabilityLinkCard means this plugin turns a URL into a preview card,
	// using Manifest.Domains to claim which hostnames it handles. See
	// client/pluginmgr/capabilities for the contract.
	CapabilityLinkCard = "link-card"

	maxManifestSize  = 64 * 1024
	maxImportZipSize = 5 * 1024 * 1024
)

var knownRendererKinds = map[string]bool{
	RendererKindDynamicWasm: true,
}

// knownCapabilities gates what a manifest may declare. Capability names are
// part of the manifest schema, so they live here; the calls behind them live
// in client/pluginmgr/capabilities, which is the only other place adding a
// capability touches.
var knownCapabilities = map[string]bool{
	CapabilitySpellcheckData: true,
	CapabilityLinkCard:       true,
}

// wasmFilenameRegexp restricts Manifest.WasmFile to a bare filename (no
// path separators or traversal).
var wasmFilenameRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+\.wasm$`)

// maxScreens caps how many screens (and therefore sub-nav entries) a single
// plugin may declare, as a basic sanity limit.
const maxScreens = 20

// safeIDRegexp restricts plugin ids (and therefore their install directory
// names) to a conservative charset, precluding path traversal.
var safeIDRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// hostnameRegexp is a loose sanity check for manifest-declared domains; it is
// not a full RFC validator, just enough to reject obvious garbage.
var hostnameRegexp = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$`)

// Manifest is the on-disk, user-facing description of a plugin.
type Manifest struct {
	ID               string `json:"id"`
	Name             string `json:"name"`
	Version          string `json:"version"`
	Description      string `json:"description"`
	EnabledByDefault bool   `json:"enabledByDefault"`
	RendererKind     string `json:"rendererKind"`

	// WasmFile is a bare filename (no path separators) of the compiled
	// plugin module, alongside manifest.json in the plugin's install
	// directory.
	WasmFile string `json:"wasmFile,omitempty"`

	// NavLabel, NavIcon, and Screens describe the plugin's contributed
	// top-level nav item (if any -- a headless, Capabilities-only plugin
	// has none). Screens lists its sub-pages, rendered via
	// wasmhost.Runtime's RenderScreen.
	NavLabel string      `json:"navLabel,omitempty"`
	NavIcon  string      `json:"navIcon,omitempty"`
	Screens  []ScreenDef `json:"screens,omitempty"`

	// PollIntervalSeconds, if positive, schedules a recurring background
	// call into the plugin's poll() export (clamped to at least
	// wasmhost.MinPollInterval); zero/absent disables polling.
	PollIntervalSeconds int `json:"pollIntervalSeconds,omitempty"`

	// Capabilities declares optional headless behaviors this plugin
	// implements, independent of (and possibly in addition to) having a
	// nav item -- see the Capability* constants.
	Capabilities []string `json:"capabilities,omitempty"`

	// Domains is used only when Capabilities includes CapabilityLinkCard:
	// which hostnames this plugin wants FetchLinkCard tried for.
	Domains []string `json:"domains,omitempty"`
}

// ScreenDef is one sub-page a plugin contributes under its nav item.
type ScreenDef struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// Plugin is an installed manifest plus its current enabled state.
type Plugin struct {
	Manifest Manifest `json:"manifest"`
	Enabled  bool     `json:"enabled"`
}

// Config configures a Manager.
type Config struct {
	// Root is the directory plugins are installed under (typically
	// <appdata>/plugins). installed/ and state.json live here.
	Root string

	Log slog.Logger
}

// Manager loads, validates, and tracks installed plugins.
type Manager struct {
	cfg Config
	log slog.Logger

	mtx     sync.Mutex
	byID    map[string]Manifest
	enabled map[string]bool
}

// NewManager creates a Manager, loading any already-installed plugins and
// persisted enabled/disabled state from cfg.Root.
func NewManager(cfg Config) (*Manager, error) {
	log := cfg.Log
	if log == nil {
		log = slog.Disabled
	}
	if cfg.Root == "" {
		return nil, fmt.Errorf("pluginmgr: Config.Root must not be empty")
	}

	m := &Manager{
		cfg:     cfg,
		log:     log,
		byID:    make(map[string]Manifest),
		enabled: make(map[string]bool),
	}

	if err := os.MkdirAll(m.installedDir(), 0o700); err != nil {
		return nil, fmt.Errorf("unable to create installed dir: %w", err)
	}

	if err := m.loadInstalled(); err != nil {
		return nil, err
	}
	if err := m.loadState(); err != nil {
		return nil, err
	}

	return m, nil
}

func (m *Manager) installedDir() string {
	return filepath.Join(m.cfg.Root, installedDirName)
}

// InstallDir returns the on-disk directory a plugin with the given id is
// installed under (whether or not that id is actually installed). Callers
// that need to reach files alongside a plugin's manifest.json -- e.g.
// wasmhost loading Manifest.WasmFile -- use this rather than reconstructing
// Config.Root themselves.
func (m *Manager) InstallDir(id string) string {
	return filepath.Join(m.installedDir(), id)
}

func (m *Manager) stateFile() string {
	return filepath.Join(m.cfg.Root, stateFileName)
}

// loadInstalled scans installedDir for plugin subfolders and loads/validates
// their manifest.json. Invalid plugin folders are logged and skipped rather
// than failing manager startup entirely.
func (m *Manager) loadInstalled() error {
	entries, err := os.ReadDir(m.installedDir())
	if err != nil {
		return fmt.Errorf("unable to read installed dir: %w", err)
	}

	m.mtx.Lock()
	defer m.mtx.Unlock()

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		id := entry.Name()
		manifest, err := m.readManifest(filepath.Join(m.installedDir(), id))
		if err != nil {
			m.log.Warnf("pluginmgr: skipping invalid plugin dir %q: %v", id, err)
			continue
		}
		if manifest.ID != id {
			m.log.Warnf("pluginmgr: skipping plugin dir %q: manifest id %q does not match dir name",
				id, manifest.ID)
			continue
		}
		m.byID[id] = manifest
	}
	return nil
}

// loadState reads persisted enabled/disabled overrides. Plugins with no
// entry in state.json use their manifest's EnabledByDefault.
func (m *Manager) loadState() error {
	var state map[string]bool
	err := jsonfile.Read(m.stateFile(), &state)
	if err != nil && err != jsonfile.ErrNotFound {
		return fmt.Errorf("unable to read plugin state: %w", err)
	}

	m.mtx.Lock()
	defer m.mtx.Unlock()

	for id, manifest := range m.byID {
		if v, ok := state[id]; ok {
			m.enabled[id] = v
		} else {
			m.enabled[id] = manifest.EnabledByDefault
		}
	}
	return nil
}

// saveState persists the current enabled/disabled map. Caller must hold mtx.
func (m *Manager) saveStateLocked() error {
	state := make(map[string]bool, len(m.enabled))
	for id, v := range m.enabled {
		state[id] = v
	}
	return jsonfile.Write(m.stateFile(), state, m.log)
}

// readManifest reads and validates manifest.json inside pluginDir.
func (m *Manager) readManifest(pluginDir string) (Manifest, error) {
	fname := filepath.Join(pluginDir, manifestFileName)
	fi, err := os.Stat(fname)
	if err != nil {
		return Manifest{}, fmt.Errorf("unable to stat manifest: %w", err)
	}
	if fi.Size() > maxManifestSize {
		return Manifest{}, fmt.Errorf("manifest.json too large (%d bytes)", fi.Size())
	}

	b, err := os.ReadFile(fname)
	if err != nil {
		return Manifest{}, fmt.Errorf("unable to read manifest: %w", err)
	}

	var manifest Manifest
	if err := json.Unmarshal(b, &manifest); err != nil {
		return Manifest{}, fmt.Errorf("invalid manifest json: %w", err)
	}

	if err := validateManifest(manifest); err != nil {
		return Manifest{}, err
	}

	return manifest, nil
}

func validateManifest(manifest Manifest) error {
	if manifest.ID == "" {
		return fmt.Errorf("manifest is missing id")
	}
	if !safeIDRegexp.MatchString(manifest.ID) {
		return fmt.Errorf("manifest id %q contains disallowed characters", manifest.ID)
	}
	if manifest.Name == "" {
		return fmt.Errorf("manifest is missing name")
	}
	if !knownRendererKinds[manifest.RendererKind] {
		return fmt.Errorf("manifest declares unknown rendererKind %q", manifest.RendererKind)
	}
	return validateDynamicWasmManifest(manifest)
}

func validateDynamicWasmManifest(manifest Manifest) error {
	if manifest.WasmFile == "" {
		return fmt.Errorf("manifest is missing wasmFile")
	}
	if !wasmFilenameRegexp.MatchString(manifest.WasmFile) {
		return fmt.Errorf("manifest declares invalid wasmFile filename %q", manifest.WasmFile)
	}

	hasScreens := len(manifest.Screens) > 0
	hasCapabilities := len(manifest.Capabilities) > 0
	if !hasScreens && !hasCapabilities {
		return fmt.Errorf("manifest declares neither screens nor capabilities")
	}

	if hasScreens {
		if manifest.NavLabel == "" {
			return fmt.Errorf("manifest declares screens but is missing navLabel")
		}
		if len(manifest.Screens) > maxScreens {
			return fmt.Errorf("manifest declares too many screens (%d)", len(manifest.Screens))
		}
		seenIDs := make(map[string]bool, len(manifest.Screens))
		for i, screen := range manifest.Screens {
			if screen.ID == "" {
				return fmt.Errorf("screen %d is missing an id", i)
			}
			if !safeIDRegexp.MatchString(screen.ID) {
				return fmt.Errorf("screen %d id %q contains disallowed characters", i, screen.ID)
			}
			if screen.Label == "" {
				return fmt.Errorf("screen %d is missing a label", i)
			}
			if seenIDs[screen.ID] {
				return fmt.Errorf("screen %d id %q is a duplicate", i, screen.ID)
			}
			seenIDs[screen.ID] = true
		}
	}

	for i, capability := range manifest.Capabilities {
		if !knownCapabilities[capability] {
			return fmt.Errorf("capability %d is unknown: %q", i, capability)
		}
	}
	if hasCapability(manifest, CapabilityLinkCard) {
		if len(manifest.Domains) == 0 {
			return fmt.Errorf("%s capability requires at least one domain", CapabilityLinkCard)
		}
		for i, domain := range manifest.Domains {
			if !hostnameRegexp.MatchString(domain) {
				return fmt.Errorf("domain %d is invalid: %q", i, domain)
			}
		}
	}

	if manifest.PollIntervalSeconds < 0 {
		return fmt.Errorf("pollIntervalSeconds must not be negative")
	}
	return nil
}

func hasCapability(manifest Manifest, capability string) bool {
	for _, c := range manifest.Capabilities {
		if c == capability {
			return true
		}
	}
	return false
}

// List returns all installed plugins with their current enabled state,
// sorted by ID for a stable ordering in the UI.
func (m *Manager) List() []Plugin {
	m.mtx.Lock()
	defer m.mtx.Unlock()

	out := make([]Plugin, 0, len(m.byID))
	for id, manifest := range m.byID {
		out = append(out, Plugin{Manifest: manifest, Enabled: m.enabled[id]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Manifest.ID < out[j].Manifest.ID })
	return out
}

// PluginsWithCapability returns the manifests of all currently ENABLED
// plugins that declare capability, sorted by ID. It is how
// client/pluginmgr/capabilities finds which plugins to ask; this package
// itself never calls one.
func (m *Manager) PluginsWithCapability(capability string) []Manifest {
	m.mtx.Lock()
	defer m.mtx.Unlock()

	var out []Manifest
	for id, manifest := range m.byID {
		if m.enabled[id] && hasCapability(manifest, capability) {
			out = append(out, manifest)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// SetEnabled sets the enabled state of an installed plugin and persists it.
func (m *Manager) SetEnabled(id string, enabled bool) error {
	m.mtx.Lock()
	defer m.mtx.Unlock()

	if _, ok := m.byID[id]; !ok {
		return fmt.Errorf("no installed plugin with id %q", id)
	}
	m.enabled[id] = enabled
	return m.saveStateLocked()
}

// Remove uninstalls a plugin: deletes its folder and forgets its state.
func (m *Manager) Remove(id string) error {
	if !safeIDRegexp.MatchString(id) {
		return fmt.Errorf("invalid plugin id %q", id)
	}

	m.mtx.Lock()
	defer m.mtx.Unlock()

	if _, ok := m.byID[id]; !ok {
		return fmt.Errorf("no installed plugin with id %q", id)
	}
	if err := os.RemoveAll(filepath.Join(m.installedDir(), id)); err != nil {
		return fmt.Errorf("unable to remove plugin dir: %w", err)
	}
	delete(m.byID, id)
	delete(m.enabled, id)
	return m.saveStateLocked()
}

// Import installs a plugin from srcPath, which may be either a directory
// containing manifest.json directly, or a .zip archive whose single
// top-level folder contains manifest.json. The plugin is validated before
// anything is written to the installed/ directory.
func (m *Manager) Import(srcPath string) (Plugin, error) {
	fi, err := os.Stat(srcPath)
	if err != nil {
		return Plugin{}, fmt.Errorf("unable to stat import source: %w", err)
	}

	var manifest Manifest
	var stageDir string
	var cleanupStage func()

	if fi.IsDir() {
		manifest, err = m.readManifest(srcPath)
		if err != nil {
			return Plugin{}, err
		}
		stageDir = srcPath
		cleanupStage = func() {}
	} else {
		manifest, stageDir, cleanupStage, err = m.extractZipForImport(srcPath)
		if err != nil {
			return Plugin{}, err
		}
	}
	defer cleanupStage()

	m.mtx.Lock()
	defer m.mtx.Unlock()

	destDir := filepath.Join(m.installedDir(), manifest.ID)
	if err := os.RemoveAll(destDir); err != nil {
		return Plugin{}, fmt.Errorf("unable to clear previous install: %w", err)
	}
	if err := copyDir(stageDir, destDir); err != nil {
		os.RemoveAll(destDir)
		return Plugin{}, fmt.Errorf("unable to install plugin: %w", err)
	}

	m.byID[manifest.ID] = manifest
	if _, ok := m.enabled[manifest.ID]; !ok {
		m.enabled[manifest.ID] = manifest.EnabledByDefault
	}
	if err := m.saveStateLocked(); err != nil {
		return Plugin{}, err
	}

	return Plugin{Manifest: manifest, Enabled: m.enabled[manifest.ID]}, nil
}

// extractZipForImport validates size limits, extracts a zip archive into a
// temp staging directory, reads+validates its manifest, and returns the
// staging dir (caller must call the returned cleanup func).
func (m *Manager) extractZipForImport(zipPath string) (Manifest, string, func(), error) {
	fi, err := os.Stat(zipPath)
	if err != nil {
		return Manifest{}, "", nil, fmt.Errorf("unable to stat zip: %w", err)
	}
	if fi.Size() > maxImportZipSize {
		return Manifest{}, "", nil, fmt.Errorf("plugin zip too large (%d bytes)", fi.Size())
	}

	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return Manifest{}, "", nil, fmt.Errorf("unable to open zip: %w", err)
	}
	defer r.Close()

	stageDir, err := os.MkdirTemp("", "brplugin-import-*")
	if err != nil {
		return Manifest{}, "", nil, fmt.Errorf("unable to create staging dir: %w", err)
	}
	cleanup := func() { os.RemoveAll(stageDir) }

	var totalSize int64
	for _, f := range r.File {
		cleanPath := filepath.Clean(f.Name)
		if strings.HasPrefix(cleanPath, "..") || filepath.IsAbs(cleanPath) {
			cleanup()
			return Manifest{}, "", nil, fmt.Errorf("zip entry %q escapes archive root", f.Name)
		}
		destPath := filepath.Join(stageDir, cleanPath)

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(destPath, 0o700); err != nil {
				cleanup()
				return Manifest{}, "", nil, err
			}
			continue
		}

		totalSize += int64(f.UncompressedSize64)
		if totalSize > maxImportZipSize {
			cleanup()
			return Manifest{}, "", nil, fmt.Errorf("plugin zip contents exceed size limit")
		}

		if err := os.MkdirAll(filepath.Dir(destPath), 0o700); err != nil {
			cleanup()
			return Manifest{}, "", nil, err
		}
		if err := extractZipFile(f, destPath); err != nil {
			cleanup()
			return Manifest{}, "", nil, err
		}
	}

	// The archive is expected to contain exactly one top-level folder
	// with manifest.json inside it (matching how a user would zip up a
	// plugin folder from their file manager).
	root, err := findManifestRoot(stageDir)
	if err != nil {
		cleanup()
		return Manifest{}, "", nil, err
	}

	manifest, err := m.readManifest(root)
	if err != nil {
		cleanup()
		return Manifest{}, "", nil, err
	}

	return manifest, root, cleanup, nil
}

func extractZipFile(f *zip.File, destPath string) error {
	rc, err := f.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	out, err := os.OpenFile(destPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer out.Close()

	_, err = io.Copy(out, io.LimitReader(rc, maxImportZipSize))
	return err
}

// findManifestRoot locates the directory within stageDir that directly
// contains manifest.json: either stageDir itself, or its single top-level
// subdirectory.
func findManifestRoot(stageDir string) (string, error) {
	if _, err := os.Stat(filepath.Join(stageDir, manifestFileName)); err == nil {
		return stageDir, nil
	}

	entries, err := os.ReadDir(stageDir)
	if err != nil {
		return "", fmt.Errorf("unable to read staged zip contents: %w", err)
	}
	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}
	if len(dirs) != 1 {
		return "", fmt.Errorf("zip must contain a single top-level plugin folder with manifest.json")
	}
	candidate := filepath.Join(stageDir, dirs[0])
	if _, err := os.Stat(filepath.Join(candidate, manifestFileName)); err != nil {
		return "", fmt.Errorf("manifest.json not found in zip")
	}
	return candidate, nil
}

func copyDir(src, dst string) error {
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(dst, 0o700); err != nil {
		return err
	}
	for _, entry := range entries {
		srcPath := filepath.Join(src, entry.Name())
		dstPath := filepath.Join(dst, entry.Name())
		if entry.IsDir() {
			if err := copyDir(srcPath, dstPath); err != nil {
				return err
			}
			continue
		}
		if err := copyFile(srcPath, dstPath); err != nil {
			return err
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

// NormalizeHost lowercases host and strips a leading "www.", the same
// normalization applied on both sides of a CapabilityLinkCard domain match
// (a manifest's Domains entries, and the host of a URL being resolved) so
// "www.Example.com" and "example.com" are treated as equivalent.
func NormalizeHost(host string) string {
	// Lowercase FIRST: TrimPrefix is case-sensitive, so a host with an
	// uppercase "WWW." prefix would otherwise pass through unstripped.
	return strings.TrimPrefix(strings.ToLower(host), "www.")
}
