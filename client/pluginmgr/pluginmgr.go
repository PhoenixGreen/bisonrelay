// Package pluginmgr implements a small, manifest-driven plugin system for
// bruig. Plugins are self-contained folders (installed under Config.Root)
// carrying a JSON manifest that configures one of a small, fixed set of
// built-in "renderer kinds" the app ships. No plugin-supplied code is ever
// executed: a manifest only declares data (URL match patterns and metadata
// endpoints) that the app itself interprets.
package pluginmgr

import (
	"archive/zip"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"

	"github.com/companyzero/bisonrelay/client/pluginmgr/builtin"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/decred/slog"
)

const (
	installedDirName = "installed"
	stateFileName    = "state.json"
	manifestFileName = "manifest.json"

	// RendererKindLinkCard renders a native "unfurl" card (thumbnail,
	// title, author) for a URL matched via Manifest.Matchers.
	RendererKindLinkCard = "link-card"

	// RendererKindSpellCheck supplies a dictionary wordlist and a set of
	// regex-based writing-style rules that the app's generic spellcheck
	// engine applies to text input areas (chat, posts, comments). Unlike
	// link-card, it has no URL matchers -- Manifest.Dictionary and
	// Manifest.GrammarRules are used instead.
	RendererKindSpellCheck = "spellcheck"

	// MetadataFormatOEmbedJSON is the only metadata format supported in
	// v1: a standard oEmbed JSON response.
	MetadataFormatOEmbedJSON = "oembed-json"

	maxManifestSize   = 64 * 1024
	maxImportZipSize  = 5 * 1024 * 1024
	maxMetadataBody   = 1024 * 1024
	maxThumbnailBytes = 2 * 1024 * 1024

	// maxDictionaryBytes caps how much of a spellcheck plugin's
	// dictionary file is read into memory.
	maxDictionaryBytes = 4 * 1024 * 1024

	// maxGrammarRules caps how many regex rules a single spellcheck
	// manifest may declare.
	maxGrammarRules = 500

	// maxGrammarRuleFieldLen caps the length of any single grammar rule
	// field (pattern/message/suggest), as a basic sanity limit.
	maxGrammarRuleFieldLen = 500
)

var knownRendererKinds = map[string]bool{
	RendererKindLinkCard:   true,
	RendererKindSpellCheck: true,
}

// dictionaryFilenameRegexp restricts Manifest.Dictionary to a bare filename
// (no path separators or traversal), matching safeIDRegexp's charset plus a
// single dot for the extension.
var dictionaryFilenameRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+$`)

var knownMetadataFormats = map[string]bool{
	MetadataFormatOEmbedJSON: true,
}

// safeIDRegexp restricts plugin ids (and therefore their install directory
// names) to a conservative charset, precluding path traversal.
var safeIDRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// hostnameRegexp is a loose sanity check for manifest-declared domains; it is
// not a full RFC validator, just enough to reject obvious garbage.
var hostnameRegexp = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$`)

// Matcher describes which URLs a plugin's manifest claims to handle, and
// where to fetch metadata for them.
type Matcher struct {
	Domains          []string `json:"domains"`
	MetadataEndpoint string   `json:"metadataEndpoint"`
	MetadataFormat   string   `json:"metadataFormat"`
}

// GrammarRule is a single regex-based writing-style check. Pattern and
// Suggest are plain data -- pluginmgr never compiles or executes them
// itself; it only validates their size. They are shipped to the Dart side
// as-is and executed there, since Dart's regex engine (unlike Go's RE2)
// supports backreferences, which are needed to express checks like
// "repeated word" (`\b(\w+)\s+\1\b`).
type GrammarRule struct {
	Pattern string `json:"pattern"`
	Message string `json:"message"`
	// Suggest is a replacement template that may reference Pattern's
	// capture groups as $1, $2, etc. An empty Suggest means the rule is
	// informational only (flagged, but with no proposed replacement).
	Suggest string `json:"suggest"`
}

// Manifest is the on-disk, user-facing description of a plugin.
type Manifest struct {
	ID               string    `json:"id"`
	Name             string    `json:"name"`
	Version          string    `json:"version"`
	Description      string    `json:"description"`
	EnabledByDefault bool      `json:"enabledByDefault"`
	RendererKind     string    `json:"rendererKind"`
	Matchers         []Matcher `json:"matchers,omitempty"`

	// Dictionary and GrammarRules are used only when RendererKind is
	// RendererKindSpellCheck. Dictionary is a bare filename (no path
	// separators) of a newline-delimited wordlist file that must sit
	// alongside manifest.json in the plugin's install directory.
	Dictionary   string        `json:"dictionary,omitempty"`
	GrammarRules []GrammarRule `json:"grammarRules,omitempty"`
}

// SpellcheckData is the merged dictionary and rule set from all currently
// enabled spellcheck plugins.
type SpellcheckData struct {
	Words        []string      `json:"words"`
	GrammarRules []GrammarRule `json:"grammarRules"`
}

// Plugin is an installed manifest plus its current enabled state.
type Plugin struct {
	Manifest Manifest `json:"manifest"`
	Enabled  bool     `json:"enabled"`
}

// LinkMetadata is the result of resolving a URL against an enabled plugin's
// matchers.
type LinkMetadata struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	Author       string `json:"author"`
	ThumbnailB64 string `json:"thumbnailB64"`
}

// ErrNotHandled is returned by FetchLinkMetadata when no enabled plugin's
// matcher covers the given URL. Callers should fall back to plain-link
// rendering in this case, not treat it as a hard error.
var ErrNotHandled = fmt.Errorf("no enabled plugin handles this url")

// Config configures a Manager.
type Config struct {
	// Root is the directory plugins are installed under (typically
	// <appdata>/plugins). installed/ and state.json live here.
	Root string

	Log slog.Logger

	// HTTPClient is used for all metadata/thumbnail fetches. Callers MUST
	// pass a client whose transport dials through the app's configured
	// proxy (Tor/SOCKS5) -- pluginmgr does no proxy configuration of its
	// own, by design, to avoid a second, possibly inconsistent, proxy
	// code path.
	HTTPClient *http.Client
}

// Manager loads, validates, and tracks installed plugins, and resolves
// chat URLs to rendering metadata via enabled plugins' matchers.
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
	if cfg.HTTPClient == nil {
		return nil, fmt.Errorf("pluginmgr: Config.HTTPClient must not be nil")
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
	if err := m.installBuiltinsIfMissing(); err != nil {
		return nil, err
	}
	if err := m.loadState(); err != nil {
		return nil, err
	}

	return m, nil
}

// builtinFile is a single file to write into a builtin plugin's install
// directory (its manifest.json, plus any companion assets like a
// dictionary wordlist).
type builtinFile struct {
	name string
	data []byte
}

// installBuiltinsIfMissing writes the files of plugins bundled with the app
// (see the builtin package) into the installed/ directory the first time
// they're not already present, so flagship plugins like "Pretty Links"
// don't require the user to manually import them. It reuses the same
// validation path as a user-driven Import.
func (m *Manager) installBuiltinsIfMissing() error {
	if err := m.installBuiltinIfMissing("prettylinks", func() ([]builtinFile, error) {
		data, err := builtin.PrettyLinksManifestJSON()
		if err != nil {
			return nil, err
		}
		return []builtinFile{{manifestFileName, data}}, nil
	}); err != nil {
		return err
	}

	return m.installBuiltinIfMissing("spellcheck", func() ([]builtinFile, error) {
		manifest, err := builtin.SpellcheckManifestJSON()
		if err != nil {
			return nil, err
		}
		words, err := builtin.SpellcheckWordsTXT()
		if err != nil {
			return nil, err
		}
		return []builtinFile{{manifestFileName, manifest}, {"words.txt", words}}, nil
	})
}

// installBuiltinIfMissing installs a single builtin plugin (identified by
// id) if it isn't already present in byID, writing whatever files filesFn
// returns into its install directory and then validating/loading the
// result through the normal manifest path.
func (m *Manager) installBuiltinIfMissing(id string, filesFn func() ([]builtinFile, error)) error {
	m.mtx.Lock()
	_, alreadyInstalled := m.byID[id]
	m.mtx.Unlock()
	if alreadyInstalled {
		return nil
	}

	files, err := filesFn()
	if err != nil {
		return fmt.Errorf("unable to read builtin %s files: %w", id, err)
	}

	destDir := filepath.Join(m.installedDir(), id)
	if err := os.MkdirAll(destDir, 0o700); err != nil {
		return fmt.Errorf("unable to create builtin plugin dir: %w", err)
	}
	for _, f := range files {
		if err := os.WriteFile(filepath.Join(destDir, f.name), f.data, 0o600); err != nil {
			return fmt.Errorf("unable to write builtin %s file %q: %w", id, f.name, err)
		}
	}

	manifest, err := m.readManifest(destDir)
	if err != nil {
		return fmt.Errorf("bundled %s manifest is invalid: %w", id, err)
	}

	m.mtx.Lock()
	m.byID[manifest.ID] = manifest
	m.mtx.Unlock()
	return nil
}

func (m *Manager) installedDir() string {
	return filepath.Join(m.cfg.Root, installedDirName)
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

	if manifest.RendererKind == RendererKindSpellCheck {
		return validateSpellCheckManifest(manifest)
	}

	if len(manifest.Matchers) == 0 {
		return fmt.Errorf("manifest declares no matchers")
	}
	for i, matcher := range manifest.Matchers {
		if len(matcher.Domains) == 0 {
			return fmt.Errorf("matcher %d declares no domains", i)
		}
		for _, domain := range matcher.Domains {
			if !hostnameRegexp.MatchString(domain) {
				return fmt.Errorf("matcher %d declares invalid domain %q", i, domain)
			}
		}
		if !knownMetadataFormats[matcher.MetadataFormat] {
			return fmt.Errorf("matcher %d declares unknown metadataFormat %q", i, matcher.MetadataFormat)
		}
		if matcher.MetadataEndpoint == "" || !strings.Contains(matcher.MetadataEndpoint, "{url}") {
			return fmt.Errorf("matcher %d has an invalid metadataEndpoint template", i)
		}
	}
	return nil
}

func validateSpellCheckManifest(manifest Manifest) error {
	if manifest.Dictionary == "" {
		return fmt.Errorf("spellcheck manifest is missing dictionary")
	}
	if !dictionaryFilenameRegexp.MatchString(manifest.Dictionary) {
		return fmt.Errorf("spellcheck manifest declares invalid dictionary filename %q", manifest.Dictionary)
	}
	if len(manifest.GrammarRules) > maxGrammarRules {
		return fmt.Errorf("spellcheck manifest declares too many grammar rules (%d)", len(manifest.GrammarRules))
	}
	for i, rule := range manifest.GrammarRules {
		if rule.Pattern == "" {
			return fmt.Errorf("grammar rule %d is missing a pattern", i)
		}
		if len(rule.Pattern) > maxGrammarRuleFieldLen ||
			len(rule.Message) > maxGrammarRuleFieldLen ||
			len(rule.Suggest) > maxGrammarRuleFieldLen {
			return fmt.Errorf("grammar rule %d has a field exceeding %d bytes", i, maxGrammarRuleFieldLen)
		}
	}
	return nil
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

// findMatcher returns the matcher (and owning manifest) of an enabled
// plugin whose domains cover host, if any.
func (m *Manager) findMatcher(host string) (Matcher, bool) {
	host = normalizeHost(host)

	m.mtx.Lock()
	defer m.mtx.Unlock()

	for id, manifest := range m.byID {
		if !m.enabled[id] {
			continue
		}
		for _, matcher := range manifest.Matchers {
			for _, domain := range matcher.Domains {
				if normalizeHost(domain) == host {
					return matcher, true
				}
			}
		}
	}
	return Matcher{}, false
}

func normalizeHost(host string) string {
	return strings.ToLower(strings.TrimPrefix(host, "www."))
}

// SpellcheckData returns the merged dictionary wordlist and grammar rules
// from all currently enabled RendererKindSpellCheck plugins. It never
// errors on a single plugin's bad/missing dictionary file -- that plugin's
// contribution is just skipped -- since a partial result is still useful
// and one broken plugin shouldn't take down spellcheck for the rest.
func (m *Manager) SpellcheckData() SpellcheckData {
	m.mtx.Lock()
	type enabledSpellCheck struct {
		id       string
		manifest Manifest
	}
	var plugins []enabledSpellCheck
	for id, manifest := range m.byID {
		if m.enabled[id] && manifest.RendererKind == RendererKindSpellCheck {
			plugins = append(plugins, enabledSpellCheck{id, manifest})
		}
	}
	m.mtx.Unlock()

	seenWords := make(map[string]bool)
	var data SpellcheckData
	for _, p := range plugins {
		words, err := m.readDictionary(p.id, p.manifest.Dictionary)
		if err != nil {
			m.log.Warnf("pluginmgr: unable to read dictionary for %q: %v", p.id, err)
		}
		for _, w := range words {
			if !seenWords[w] {
				seenWords[w] = true
				data.Words = append(data.Words, w)
			}
		}
		data.GrammarRules = append(data.GrammarRules, p.manifest.GrammarRules...)
	}
	return data
}

// readDictionary reads and tokenizes a spellcheck plugin's dictionary file:
// one lowercase word per line, blank lines and "#"-prefixed comment lines
// ignored.
func (m *Manager) readDictionary(pluginID, filename string) ([]string, error) {
	path := filepath.Join(m.installedDir(), pluginID, filename)
	fi, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("unable to stat dictionary: %w", err)
	}
	if fi.Size() > maxDictionaryBytes {
		return nil, fmt.Errorf("dictionary too large (%d bytes)", fi.Size())
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("unable to read dictionary: %w", err)
	}

	var words []string
	for _, line := range strings.Split(string(b), "\n") {
		line = strings.ToLower(strings.TrimSpace(line))
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		words = append(words, line)
	}
	return words, nil
}

// oEmbedResponse covers the subset of the standard oEmbed JSON response
// fields pluginmgr uses. description is not part of the oEmbed spec, but a
// few providers include it anyway; it's mapped here on a best-effort basis
// and left empty (never a hard error) for providers that don't. html is
// used as a fallback description source for rich/video oEmbed responses
// (e.g. Twitter/X embeds the tweet text as the first <p> of html) that
// carry no separate description field.
type oEmbedResponse struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	AuthorName   string `json:"author_name"`
	ThumbnailURL string `json:"thumbnail_url"`
	HTML         string `json:"html"`
}

var (
	htmlFirstParaRegexp    = regexp.MustCompile(`(?s)<p[^>]*>(.*?)</p>`)
	htmlBreakRegexp        = regexp.MustCompile(`(?i)<br\s*/?>`)
	htmlTagRegexp          = regexp.MustCompile(`(?s)<[^>]*>`)
	spaceRunRegexp         = regexp.MustCompile(`[ \t]+`)
	spaceBeforePunctRegexp = regexp.MustCompile(`[ \t]+([,.:;!?])`)
	excessBlankLinesRegexp = regexp.MustCompile(`\n{3,}`)
)

// descriptionFromOEmbed picks the best available short-description text for
// an oEmbed response: the (non-standard) description field if present,
// otherwise a plain-text extraction of html's first paragraph.
func descriptionFromOEmbed(oembed oEmbedResponse) string {
	if oembed.Description != "" {
		return oembed.Description
	}
	match := htmlFirstParaRegexp.FindStringSubmatch(oembed.HTML)
	if match == nil {
		return ""
	}
	// <br> is a line break, not a word separator -- turn it into one before
	// the generic tag strip below so paragraph structure survives. Other
	// tags (e.g. the <a>...</a> wrapping a @mention) are replaced with a
	// space rather than dropped outright -- providers like Twitter/X often
	// have no literal whitespace around them in the source HTML, so
	// removing them outright runs adjacent words together (e.g.
	// "@Mining_Dutch,The"). The extra spacing this introduces is tidied up
	// below without touching the line breaks themselves.
	text := htmlBreakRegexp.ReplaceAllString(match[1], "\n")
	text = htmlTagRegexp.ReplaceAllString(text, " ")
	text = html.UnescapeString(text)
	text = spaceRunRegexp.ReplaceAllString(text, " ")
	text = spaceBeforePunctRegexp.ReplaceAllString(text, "$1")
	text = excessBlankLinesRegexp.ReplaceAllString(text, "\n\n")
	lines := strings.Split(text, "\n")
	for i, line := range lines {
		lines[i] = strings.TrimSpace(line)
	}
	return strings.TrimSpace(strings.Join(lines, "\n"))
}

// FetchLinkMetadata resolves rawURL against the matchers of all currently
// enabled plugins. If none match, it returns ErrNotHandled and callers
// should fall back to plain-link rendering without making any network
// request. If a matcher is found, it fetches oEmbed metadata (and, if
// present, the thumbnail image bytes) through cfg.HTTPClient -- the same
// proxied client used for all other client network traffic.
func (m *Manager) FetchLinkMetadata(ctx context.Context, rawURL string) (LinkMetadata, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return LinkMetadata{}, fmt.Errorf("invalid url")
	}

	matcher, ok := m.findMatcher(parsed.Hostname())
	if !ok {
		return LinkMetadata{}, ErrNotHandled
	}

	endpoint := strings.Replace(matcher.MetadataEndpoint, "{url}", url.QueryEscape(rawURL), 1)

	var oembed oEmbedResponse
	if err := m.fetchJSON(ctx, endpoint, &oembed); err != nil {
		return LinkMetadata{}, fmt.Errorf("unable to fetch link metadata: %w", err)
	}

	metadata := LinkMetadata{
		Title:       oembed.Title,
		Description: descriptionFromOEmbed(oembed),
		Author:      oembed.AuthorName,
	}

	thumbnailURL := oembed.ThumbnailURL
	if thumbnailURL == "" {
		// The oEmbed spec has no image field for a plain link/photo
		// response (as opposed to a video's thumbnail_url), which is
		// exactly the case for e.g. a tweet with an attached photo.
		// Fall back to scraping the og:image (and, if we still have no
		// description, og:description) meta tags from the linked page
		// itself -- the same technique other chat apps' unfurlers use,
		// and one most sites (including X) serve in the page's raw HTML
		// without needing JS.
		og, err := m.fetchOpenGraphTags(ctx, rawURL)
		if err != nil {
			m.log.Debugf("pluginmgr: unable to fetch og tags for %q: %v", rawURL, err)
		} else {
			thumbnailURL = og.Image
			if metadata.Description == "" {
				metadata.Description = og.Description
			}
		}
	}

	if isTwitterNonMediaImage(thumbnailURL) {
		// Neither X's generic placeholder graphic nor the post author's
		// avatar is the post's actual attached media -- showing either
		// is worse than showing no image at all, so degrade to a
		// text-only card instead.
		thumbnailURL = ""
	}

	if thumbnailURL != "" {
		thumb, err := m.fetchImage(ctx, thumbnailURL)
		if err != nil {
			// A missing/failed thumbnail is not fatal to the whole
			// preview -- degrade to a text-only card.
			m.log.Warnf("pluginmgr: unable to fetch thumbnail %q: %v", thumbnailURL, err)
		} else {
			metadata.ThumbnailB64 = thumb
		}
	}

	return metadata, nil
}

// twitterNonMediaImagePrefixes are og:image URL prefixes X uses for anything
// that isn't the post's own attached photo/video, so none of them should be
// shown as the link card's thumbnail:
//   - abs.twimg.com/rweb/ssr/default/... is a fixed placeholder graphic X
//     serves on every post it declines to render real preview data for
//     (e.g. to an unrecognized user agent); it is never post-specific.
//   - pbs.twimg.com/profile_images/... is the post author's avatar, which X
//     serves as og:image on any text-only post that has no attached media
//     of its own.
//
// Real attached photos/videos are served from pbs.twimg.com/media/... (or
// pbs.twimg.com/ext_tw_video_thumb/... for video posters), which are left
// alone.
var twitterNonMediaImagePrefixes = []string{
	"https://abs.twimg.com/rweb/ssr/default/",
	"https://pbs.twimg.com/profile_images/",
}

func isTwitterNonMediaImage(imgURL string) bool {
	for _, prefix := range twitterNonMediaImagePrefixes {
		if strings.HasPrefix(imgURL, prefix) {
			return true
		}
	}
	return false
}

// openGraphTags covers the small subset of Open Graph (and Twitter Card,
// which mirrors it) meta tags used as a fallback source of preview data for
// pages whose oEmbed response carries no image of its own.
type openGraphTags struct {
	Description string
	Image       string
}

var (
	metaTagRegexp      = regexp.MustCompile(`(?i)<meta\s+[^>]*>`)
	metaPropertyRegexp = regexp.MustCompile(`(?i)(?:property|name)\s*=\s*"([^"]*)"`)
	metaContentRegexp  = regexp.MustCompile(`(?i)content\s*=\s*"([^"]*)"`)
)

// twitterCardCrawlerHosts are the hosts for which X only server-renders the
// real per-post og:image (actual attached media, or the author's avatar as a
// fallback) to a small allowlist of recognized embed-crawler user agents.
// Any other user agent, including a descriptive custom one, gets served a
// fixed generic placeholder graphic as og:image regardless of the post's
// content -- see isTwitterDefaultCardImage.
var twitterCardCrawlerHosts = map[string]bool{
	"twitter.com": true,
	"x.com":       true,
}

// fetchOpenGraphTags fetches pageURL's raw HTML and extracts the handful of
// og:*/twitter:* meta tags used as fallback preview data. It never returns a
// hard error for missing tags -- only for outright fetch failures -- since
// an incomplete result (e.g. no image) is still useful to the caller.
func (m *Manager) fetchOpenGraphTags(ctx context.Context, pageURL string) (openGraphTags, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, pageURL, nil)
	if err != nil {
		return openGraphTags{}, err
	}
	// Some sites only server-render meta tags (skipping the JS-driven
	// app shell) for what looks like a link-preview crawler.
	userAgent := "Mozilla/5.0 (compatible; BisonRelayLinkPreview/1.0; +https://bisonrelay.org)"
	if parsed, err := url.Parse(pageURL); err == nil && twitterCardCrawlerHosts[normalizeHost(parsed.Hostname())] {
		// X's server-rendered og:image is only the real post media (or
		// the author's avatar for a text-only post) for a small
		// allowlist of known embed-crawler user agents; every other
		// request, including our own descriptive one above, gets a
		// fixed generic placeholder image instead.
		userAgent = "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)"
	}
	req.Header.Set("User-Agent", userAgent)

	resp, err := m.cfg.HTTPClient.Do(req)
	if err != nil {
		return openGraphTags{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return openGraphTags{}, fmt.Errorf("unexpected status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxMetadataBody))
	if err != nil {
		return openGraphTags{}, err
	}

	var tags openGraphTags
	for _, tag := range metaTagRegexp.FindAllString(string(body), -1) {
		prop := metaPropertyRegexp.FindStringSubmatch(tag)
		content := metaContentRegexp.FindStringSubmatch(tag)
		if prop == nil || content == nil {
			continue
		}
		value := html.UnescapeString(content[1])
		switch strings.ToLower(prop[1]) {
		case "og:image", "og:image:secure_url", "twitter:image":
			if tags.Image == "" {
				tags.Image = value
			}
		case "og:description", "twitter:description":
			if tags.Description == "" {
				tags.Description = value
			}
		}
	}
	return tags, nil
}

func (m *Manager) fetchJSON(ctx context.Context, endpoint string, out interface{}) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	resp, err := m.cfg.HTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	body := io.LimitReader(resp.Body, maxMetadataBody)
	return json.NewDecoder(body).Decode(out)
}

var allowedImageContentTypes = map[string]bool{
	"image/jpeg": true,
	"image/png":  true,
	"image/webp": true,
	"image/gif":  true,
}

func (m *Manager) fetchImage(ctx context.Context, imgURL string) (string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, imgURL, nil)
	if err != nil {
		return "", err
	}
	resp, err := m.cfg.HTTPClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return "", fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	ct := resp.Header.Get("Content-Type")
	// Some servers include a charset/etc suffix; only compare the base type.
	if idx := strings.IndexByte(ct, ';'); idx >= 0 {
		ct = ct[:idx]
	}
	ct = strings.TrimSpace(ct)
	if !allowedImageContentTypes[ct] {
		return "", fmt.Errorf("unsupported thumbnail content type %q", ct)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maxThumbnailBytes))
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(data), nil
}
