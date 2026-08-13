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

	"github.com/companyzero/bisonrelay/client/pluginmgr/builtin"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/decred/slog"
)

const (
	installedDirName = "installed"
	builtinDirName   = "builtin"
	stateFileName    = "state.json"
	manifestFileName = "manifest.json"

	// builtinStampName records which build wrote the built-in plugin
	// currently on disk, so a launch that would write identical bytes can
	// skip decompressing an 8MB module instead.
	builtinStampName = ".builtin-stamp"

	// RendererKindDynamicWasm is the only renderer kind: Manifest.WasmFile
	// names a WebAssembly module (sandboxed by client/pluginmgr/wasmhost)
	// that Contributes UI to the host's slots, Provides headless services,
	// or both.
	RendererKindDynamicWasm = "dynamic-wasm"

	// The slots the host publishes. A slot is a named surface a plugin may
	// contribute UI to; the host draws whatever turns up, by rendering the
	// same declarative widget tree it already renders for screens.
	//
	// These are named here so the host can document and test them, NOT as an
	// allowlist. A contribution to a slot this build has never heard of is
	// kept and simply never drawn -- which is what lets a plugin target a
	// newer host and degrade on an older one, and what stops this list
	// becoming the gate that knownCapabilities used to be.
	SlotNav            = "nav"
	SlotSettingsPage   = "settingsPage"
	SlotComposerAction = "composerAction"
	SlotMessageAction  = "messageAction"
	SlotSidebarPanel   = "sidebarPanel"

	// The service names the app itself consumes. Again: documentation, not
	// an allowlist. A plugin may provide any service name it likes; one
	// nothing consumes is inert rather than rejected, which is the whole
	// difference between a namespace and a permission slip.
	ServiceSpellcheckData = "spellcheck-data"
	ServiceLinkCard       = "link-card"
	ServiceThesaurus      = "thesaurus"

	maxManifestSize = 64 * 1024

	// maxImportZipSize caps the archive file itself.
	//
	// It has to leave real room: Go's WebAssembly runtime costs about 1.8MB
	// before a plugin does anything at all, so a limit sized for "a bit of
	// code" rules out every plugin that ships data -- a dictionary, an icon
	// set, a model. This was 5MB, which the bundled RSS and link-card
	// plugins already sat at 80-86% of.
	maxImportZipSize = 32 * 1024 * 1024

	// maxImportUnpackedSize caps what the archive expands to. Separate from
	// the figure above, which it used to share: an archive is allowed to be
	// meaningfully larger unpacked than packed -- that is what compression
	// is -- and conflating the two capped every plugin at its compressed
	// size for no stated reason.
	maxImportUnpackedSize = 128 * 1024 * 1024

	// maxImportCompressionRatio is the real defence against a zip bomb,
	// which an absolute cap only ever approximates: a bomb is defined by
	// expanding wildly, not by being large. Legitimate plugin archives are
	// mostly an already-compact wasm module and come in far under 10:1.
	maxImportCompressionRatio = 100
)

var knownRendererKinds = map[string]bool{
	RendererKindDynamicWasm: true,
}

// CurrentSchema is the manifest/ABI generation this build implements. A
// plugin declares the one it was built against in Manifest.Schema so both
// sides can tell, rather than discovering the mismatch as a widget that
// silently fails to draw.
//
// Bumped only for a change a plugin can observe: a new widget type, a new
// slot, a new host import. A plugin declaring a HIGHER schema than this is
// still loaded -- it may well degrade perfectly well, and refusing it would
// make every host upgrade a flag day -- but the mismatch is logged.
const CurrentSchema = 1

// wasmFilenameRegexp restricts Manifest.WasmFile to a bare filename (no
// path separators or traversal).
var wasmFilenameRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+\.wasm$`)

// maxScreens caps how many screens (and therefore sub-nav entries) a single
// plugin may declare, as a basic sanity limit.
const maxScreens = 20

// maxContributionsPerSlot caps how many entries one plugin may put in a
// single slot, so a plugin cannot bury a menu under its own contributions.
const maxContributionsPerSlot = 20

// safeIDRegexp restricts plugin ids (and therefore their install directory
// names) to a conservative charset, precluding path traversal.
var safeIDRegexp = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)

// serviceNameRegexp restricts a provided service name. Loose on purpose --
// it exists to reject garbage, not to decide which services may exist.
var serviceNameRegexp = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]*$`)

// exportNameRegexp restricts the wasm export a service is answered by, since
// it is looked up by name in the guest module.
var exportNameRegexp = regexp.MustCompile(`^[a-zA-Z_][a-zA-Z0-9_]*$`)

// hostnameRegexp is a loose sanity check for manifest-declared domains; it is
// not a full RFC validator, just enough to reject obvious garbage.
var hostnameRegexp = regexp.MustCompile(`^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$`)

// Manifest is the on-disk, user-facing description of a plugin.
type Manifest struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Version     string `json:"version"`
	Description string `json:"description"`

	// Summary is one line for a list, where Description is the full account
	// shown once a plugin has been opened. Optional: a plugin that gives
	// only a Description still lists, on the opening of it.
	Summary string `json:"summary,omitempty"`

	// Schema is the manifest/ABI generation this plugin was built against --
	// see CurrentSchema. Absent means 0, which is every plugin written before
	// the field existed and is treated as "the original vocabulary".
	Schema int `json:"schema,omitempty"`

	EnabledByDefault bool   `json:"enabledByDefault"`
	RendererKind     string `json:"rendererKind"`

	// WasmFile is a bare filename (no path separators) of the compiled
	// plugin module, alongside manifest.json in the plugin's install
	// directory.
	WasmFile string `json:"wasmFile,omitempty"`

	// Contributes is the UI this plugin adds, keyed by the slot it goes in
	// (see the Slot* constants). Every contribution is rendered by asking the
	// module for a widget tree, exactly as a screen is -- a slot is a screen
	// with somewhere to be drawn.
	//
	// The host does not check the slot names. One it does not implement is
	// carried and never drawn, so a plugin can target a newer host without
	// failing to install on an older one.
	Contributes map[string][]Contribution `json:"contributes,omitempty"`

	// Provides is the headless services this plugin answers -- a dictionary,
	// a link unfurler, a translator. A service is a name and the export that
	// answers it; the host routes to it without knowing what it means, and a
	// service nothing consumes costs nothing.
	Provides []ServiceDef `json:"provides,omitempty"`

	// PollIntervalSeconds, if positive, schedules a recurring background
	// call into the plugin's poll() export (clamped to at least
	// wasmhost.MinPollInterval); zero/absent disables polling.
	PollIntervalSeconds int `json:"pollIntervalSeconds,omitempty"`

	// --- Superseded keys, still read ------------------------------------
	//
	// These are what a manifest said before Contributes and Provides
	// existed. They are still accepted and normalized into the two above by
	// normalize(), because plugins are installed artifacts built and shipped
	// independently of this repository: an installed copy that stopped
	// loading on upgrade would be this package breaking somebody else's
	// software. Nothing downstream reads them -- consult Contributes and
	// Provides, which are populated either way.

	// NavLabel, NavIcon and Screens described the plugin's top-level nav
	// item. Now one Contribution in the SlotNav slot.
	NavLabel string      `json:"navLabel,omitempty"`
	NavIcon  string      `json:"navIcon,omitempty"`
	Screens  []ScreenDef `json:"screens,omitempty"`

	// Capabilities was the fixed vocabulary of headless behaviours, gated by
	// an allowlist in this package. Now Provides, gated by nothing.
	Capabilities []string `json:"capabilities,omitempty"`

	// Domains was used only by the link-card capability. Now a field of the
	// ServiceDef that wants it, since which hostnames a provider claims is a
	// property of that service and not of the plugin.
	Domains []string `json:"domains,omitempty"`
}

// Contribution is one piece of UI a plugin adds to a slot.
type Contribution struct {
	// ID is the screen id passed back to the module's render_screen when
	// this contribution is drawn, and to handle_event when it is used.
	ID string `json:"id"`

	// Label names it wherever the slot shows a name -- a nav item, a menu
	// entry, a tab.
	Label string `json:"label"`

	// Icon is a name from the host's icon set. Optional, and an unknown one
	// falls back rather than failing, so the set can grow.
	Icon string `json:"icon,omitempty"`

	// Screens are sub-pages under this contribution, for a slot that can
	// show more than one (the nav item and its side menu). Empty means the
	// contribution is the single screen named by ID.
	Screens []ScreenDef `json:"screens,omitempty"`
}

// ServiceDef is one headless service a plugin answers.
type ServiceDef struct {
	// Service is the name consumers ask for. Any string; the host neither
	// validates it against a list nor needs to know what it means.
	Service string `json:"service"`

	// Export is the module function that answers it. Defaults to Service
	// with dashes turned to underscores, which is the convention every
	// existing plugin already follows.
	Export string `json:"export,omitempty"`

	// Domains narrows which hostnames this provider claims, for a service
	// that is about URLs. Empty means "any", which is correct for every
	// service that is not.
	Domains []string `json:"domains,omitempty"`
}

// legacyCapabilityExports maps the three capability names that predate
// ServiceDef to the exports their plugins already implement, so a manifest
// written before Provides existed routes to the same function it always did.
var legacyCapabilityExports = map[string]string{
	ServiceSpellcheckData: "get_spellcheck_data",
	ServiceLinkCard:       "fetch_link_card",
	ServiceThesaurus:      "lookup_synonyms",
}

// defaultExportFor is the export a service is answered by when a ServiceDef
// does not name one: the service with dashes turned to underscores.
func defaultExportFor(service string) string {
	if export, ok := legacyCapabilityExports[service]; ok {
		return export
	}
	return strings.ReplaceAll(service, "-", "_")
}

// Normalize folds the superseded manifest keys into Contributes and Provides,
// so everything downstream reads one shape whatever the plugin wrote.
//
// Called once, on the way out of readManifest, rather than at each point of
// use: a reader that has to remember to check two fields will eventually be
// written by somebody who does not. Exported because anything building a
// Manifest by hand rather than reading one -- a test, a fixture -- has to
// call it too, and a manifest that skipped it looks empty rather than wrong.
//
// Idempotent: running it twice adds nothing, so a caller unsure whether a
// manifest has been through it can simply call it.
func (m *Manifest) Normalize() {
	if len(m.Screens) > 0 || m.NavLabel != "" {
		if _, already := m.Contributes[SlotNav]; !already {
			if m.Contributes == nil {
				m.Contributes = map[string][]Contribution{}
			}
			id := "main"
			if len(m.Screens) > 0 {
				id = m.Screens[0].ID
			}
			m.Contributes[SlotNav] = []Contribution{{
				ID:      id,
				Label:   m.NavLabel,
				Icon:    m.NavIcon,
				Screens: m.Screens,
			}}
		}
	}

	for _, capability := range m.Capabilities {
		if m.providesService(capability) {
			continue
		}
		def := ServiceDef{
			Service: capability,
			Export:  defaultExportFor(capability),
		}
		// Domains was only ever meaningful for link-card, and belongs to
		// that service rather than to the plugin.
		if capability == ServiceLinkCard {
			def.Domains = m.Domains
		}
		m.Provides = append(m.Provides, def)
	}

	// Fill in the export for anything that declared a service without one.
	for i := range m.Provides {
		if m.Provides[i].Export == "" {
			m.Provides[i].Export = defaultExportFor(m.Provides[i].Service)
		}
	}
}

// providesService reports whether Provides already names service.
func (m *Manifest) providesService(service string) bool {
	for _, p := range m.Provides {
		if p.Service == service {
			return true
		}
	}
	return false
}

// ServiceExport returns the export answering service, and whether this plugin
// provides it at all.
func (m Manifest) ServiceExport(service string) (string, bool) {
	for _, p := range m.Provides {
		if p.Service == service {
			return p.Export, true
		}
	}
	return "", false
}

// ContributionsTo returns what this plugin adds to slot, if anything.
func (m Manifest) ContributionsTo(slot string) []Contribution {
	return m.Contributes[slot]
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

	// Builtin reports that this plugin ships inside the client rather than
	// having been imported. It may be enabled and disabled like any other,
	// but it cannot be removed and nothing imported may take its id.
	Builtin bool `json:"builtin"`
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

	// builtin is the ids that ship with the client. Held separately from
	// byID because it decides what may be done to a plugin, not what it is.
	builtin map[string]bool
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
		builtin: make(map[string]bool),
	}

	if err := os.MkdirAll(m.installedDir(), 0o700); err != nil {
		return nil, fmt.Errorf("unable to create installed dir: %w", err)
	}

	// Built-ins first, so an imported plugin that somehow shares an id is
	// the one that loses -- see loadInstalled. Their failure is not fatal:
	// a client that cannot write them out is still a working client with
	// two features missing, which beats one that will not start.
	if err := m.loadBuiltins(); err != nil {
		m.log.Errorf("pluginmgr: unable to install built-in plugins: %v", err)
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

// builtinDir is where the plugins that ship with the client are written out.
//
// Separate from installed/ so the two can never be confused: nothing here
// was imported, removing a folder here achieves nothing (the next launch
// writes it back), and a user reading their own app data can see at a glance
// which plugins they chose and which came with the app.
func (m *Manager) builtinDir() string {
	return filepath.Join(m.cfg.Root, builtinDirName)
}

// loadBuiltins writes the embedded plugins out and registers them.
//
// They are written to disk rather than run from memory because a wasm module
// is loaded by path (see wasmhost and InstallDir), and because a plugin's
// manifest.json is read by exactly one piece of code, which should not need
// to care where the bytes came from.
//
// One built-in failing does not stop the others: a missing feature is worth
// reporting, but not worth taking the rest of the plugin system down for.
func (m *Manager) loadBuiltins() error {
	var firstErr error
	for _, bp := range builtin.All() {
		if err := m.installBuiltin(bp); err != nil {
			m.log.Errorf("pluginmgr: built-in %q unavailable: %v", bp.ID, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}

		manifest, err := m.readManifest(m.builtinPluginDir(bp.ID))
		if err != nil {
			m.log.Errorf("pluginmgr: built-in %q has an unreadable manifest: %v",
				bp.ID, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if manifest.ID != bp.ID {
			err := fmt.Errorf("manifest id %q does not match %q", manifest.ID, bp.ID)
			m.log.Errorf("pluginmgr: built-in %q: %v", bp.ID, err)
			if firstErr == nil {
				firstErr = err
			}
			continue
		}

		m.mtx.Lock()
		m.byID[bp.ID] = manifest
		m.builtin[bp.ID] = true
		m.mtx.Unlock()
	}
	return firstErr
}

func (m *Manager) builtinPluginDir(id string) string {
	return filepath.Join(m.builtinDir(), id)
}

// installBuiltin writes one built-in out, skipping the work when what is
// already there came from the same build.
//
// The stamp is the size of the compressed module and of the manifest, which
// is enough: the bytes are baked into the binary, so they only change when
// the binary does, and a rebuild that changed neither length changed nothing
// a user can see. Hashing 5MB on every launch to be certain of that would
// cost more than it could ever save.
func (m *Manager) installBuiltin(bp builtin.Plugin) error {
	dir := m.builtinPluginDir(bp.ID)
	stampPath := filepath.Join(dir, builtinStampName)
	stamp := fmt.Sprintf("%d %d\n", len(bp.WasmGz), len(bp.Manifest))

	if have, err := os.ReadFile(stampPath); err == nil && string(have) == stamp {
		return nil
	}

	if err := os.MkdirAll(dir, 0o700); err != nil {
		return fmt.Errorf("unable to create built-in dir: %w", err)
	}

	var manifest Manifest
	if err := json.Unmarshal(bp.Manifest, &manifest); err != nil {
		return fmt.Errorf("unable to parse embedded manifest: %w", err)
	}
	manifest.Normalize()
	// Validated like anything imported. Being shipped is not a reason to
	// skip the check -- it is a reason for the check to have been run
	// before anyone shipped it.
	if err := validateManifest(manifest); err != nil {
		return fmt.Errorf("embedded manifest is invalid: %w", err)
	}

	wasm, err := bp.Wasm()
	if err != nil {
		return err
	}

	wasmName := manifest.WasmFile
	if wasmName == "" {
		return fmt.Errorf("embedded manifest names no wasm file")
	}
	if err := os.WriteFile(filepath.Join(dir, wasmName), wasm, 0o600); err != nil {
		return fmt.Errorf("unable to write built-in module: %w", err)
	}
	if err := os.WriteFile(filepath.Join(dir, manifestFileName), bp.Manifest, 0o600); err != nil {
		return fmt.Errorf("unable to write built-in manifest: %w", err)
	}
	// Stamped last, so an interrupted write is retried next launch rather
	// than being taken for a finished one.
	if err := os.WriteFile(stampPath, []byte(stamp), 0o600); err != nil {
		return fmt.Errorf("unable to write built-in stamp: %w", err)
	}
	return nil
}

// InstallDir returns the on-disk directory a plugin with the given id is
// installed under (whether or not that id is actually installed). Callers
// that need to reach files alongside a plugin's manifest.json -- e.g.
// wasmhost loading Manifest.WasmFile -- use this rather than reconstructing
// Config.Root themselves.
func (m *Manager) InstallDir(id string) string {
	m.mtx.Lock()
	isBuiltin := m.builtin[id]
	m.mtx.Unlock()
	if isBuiltin {
		return m.builtinPluginDir(id)
	}
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
		// A built-in of the same id wins. Import refuses to create this
		// case, so reaching it means the folder was put there by hand or
		// predates the plugin becoming built in -- either way the shipped
		// one is the one the app's own features were written against.
		if m.builtin[id] {
			m.log.Warnf("pluginmgr: ignoring installed plugin %q: shadowed by the built-in of the same id", id)
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

	// Fold the superseded keys into Contributes/Provides before anything
	// else looks at the manifest, so validation and every reader downstream
	// see one shape regardless of which generation wrote it.
	manifest.Normalize()

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

	if len(manifest.Contributes) == 0 && len(manifest.Provides) == 0 {
		return fmt.Errorf("manifest contributes no UI and provides no services")
	}

	for slot, contributions := range manifest.Contributes {
		if !safeIDRegexp.MatchString(slot) {
			return fmt.Errorf("slot name %q contains disallowed characters", slot)
		}
		// Deliberately no check that this build implements the slot: an
		// unknown one is carried and never drawn, which is how a plugin
		// targets a newer host without failing to install on this one.
		if err := validateContributions(slot, contributions); err != nil {
			return err
		}
	}

	for i, service := range manifest.Provides {
		if service.Service == "" {
			return fmt.Errorf("provides %d is missing a service name", i)
		}
		// Structural only. There is no list of permitted service names, by
		// design -- a service nothing consumes is inert, not invalid.
		if !serviceNameRegexp.MatchString(service.Service) {
			return fmt.Errorf("provides %d service %q contains disallowed characters",
				i, service.Service)
		}
		if !exportNameRegexp.MatchString(service.Export) {
			return fmt.Errorf("provides %d export %q is not a valid export name",
				i, service.Export)
		}
		for j, domain := range service.Domains {
			if !hostnameRegexp.MatchString(domain) {
				return fmt.Errorf("provides %d domain %d is invalid: %q", i, j, domain)
			}
		}
	}

	if manifest.PollIntervalSeconds < 0 {
		return fmt.Errorf("pollIntervalSeconds must not be negative")
	}
	return nil
}

// validateContributions checks one slot's worth of contributions.
func validateContributions(slot string, contributions []Contribution) error {
	if len(contributions) > maxContributionsPerSlot {
		return fmt.Errorf("slot %q declares too many contributions (%d)",
			slot, len(contributions))
	}
	seen := make(map[string]bool, len(contributions))
	for i, c := range contributions {
		if c.ID == "" {
			return fmt.Errorf("slot %q contribution %d is missing an id", slot, i)
		}
		if !safeIDRegexp.MatchString(c.ID) {
			return fmt.Errorf("slot %q contribution %d id %q contains disallowed characters",
				slot, i, c.ID)
		}
		if c.Label == "" {
			return fmt.Errorf("slot %q contribution %d is missing a label", slot, i)
		}
		if seen[c.ID] {
			return fmt.Errorf("slot %q contribution %d id %q is a duplicate", slot, i, c.ID)
		}
		seen[c.ID] = true

		if len(c.Screens) > maxScreens {
			return fmt.Errorf("slot %q contribution %q declares too many screens (%d)",
				slot, c.ID, len(c.Screens))
		}
		screenIDs := make(map[string]bool, len(c.Screens))
		for j, screen := range c.Screens {
			if screen.ID == "" {
				return fmt.Errorf("slot %q contribution %q screen %d is missing an id",
					slot, c.ID, j)
			}
			if !safeIDRegexp.MatchString(screen.ID) {
				return fmt.Errorf("slot %q contribution %q screen %d id %q contains disallowed characters",
					slot, c.ID, j, screen.ID)
			}
			if screen.Label == "" {
				return fmt.Errorf("slot %q contribution %q screen %d is missing a label",
					slot, c.ID, j)
			}
			if screenIDs[screen.ID] {
				return fmt.Errorf("slot %q contribution %q screen %d id %q is a duplicate",
					slot, c.ID, j, screen.ID)
			}
			screenIDs[screen.ID] = true
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
		out = append(out, Plugin{
			Manifest: manifest,
			Enabled:  m.enabled[id],
			Builtin:  m.builtin[id],
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Manifest.ID < out[j].Manifest.ID })
	return out
}

// PluginsProviding returns the manifests of all currently ENABLED plugins
// that provide service, sorted by ID. It is how a consumer finds which
// plugins to ask; this package itself never calls one, and never needs to
// know what any service name means.
func (m *Manager) PluginsProviding(service string) []Manifest {
	m.mtx.Lock()
	defer m.mtx.Unlock()

	var out []Manifest
	for id, manifest := range m.byID {
		if !m.enabled[id] {
			continue
		}
		if _, ok := manifest.ServiceExport(service); ok {
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
	// A built-in was never installed, so there is nothing to uninstall --
	// and the next launch would write it straight back. Disabling is what
	// this means for one of them.
	if m.builtin[id] {
		return fmt.Errorf("plugin %q ships with the app and cannot be removed; disable it instead", id)
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

	// Importing over a built-in is refused rather than shadowed. The app's
	// own features are written against the services these provide, so a
	// file that claimed one of their ids could replace a shipped feature
	// with anything at all -- and the user would have no way to tell, since
	// the settings page would still show one plugin under that name.
	if m.builtin[manifest.ID] {
		return Plugin{}, fmt.Errorf("plugin id %q ships with the app and cannot be replaced", manifest.ID)
	}

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
		return Manifest{}, "", nil, fmt.Errorf("plugin zip is %s, over the %s limit",
			humanSize(fi.Size()), humanSize(maxImportZipSize))
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
		if totalSize > maxImportUnpackedSize {
			cleanup()
			return Manifest{}, "", nil, fmt.Errorf(
				"plugin contents unpack to over %s", humanSize(maxImportUnpackedSize))
		}
		// Checked as we go rather than at the end, so a bomb is refused
		// before the rest of it is written to disk.
		if fi.Size() > 0 && totalSize/fi.Size() > maxImportCompressionRatio {
			cleanup()
			return Manifest{}, "", nil, fmt.Errorf(
				"plugin contents expand more than %dx, which is not a plugin",
				maxImportCompressionRatio)
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

	_, err = io.Copy(out, io.LimitReader(rc, maxImportUnpackedSize))
	return err
}

// humanSize renders a byte count for an error a user will read.
func humanSize(n int64) string {
	switch {
	case n >= 1024*1024:
		return fmt.Sprintf("%.1fMB", float64(n)/(1024*1024))
	case n >= 1024:
		return fmt.Sprintf("%.1fKB", float64(n)/1024)
	default:
		return fmt.Sprintf("%d bytes", n)
	}
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
