// Package wasmhost loads and executes dynamic-wasm plugins: WebAssembly
// modules (compiled from ordinary Go via `GOOS=wasip1 GOARCH=wasm go build
// -buildmode=c-shared`) that implement a small, fixed set of optional
// exported functions (render_screen, handle_event, poll, plus a handful of
// headless-capability exports -- see Manifest.Capabilities in
// client/pluginmgr) describing UI declaratively as JSON, rather than
// drawing anything themselves. Guest code is sandboxed by wazero: no
// filesystem access, no raw network/syscalls beyond the small set of host
// functions this package grants (fetch_url/fetch_url_ex, kv_get/kv_set,
// log_msg).
//
// # Wire format
//
// The go:wasmexport/go:wasmimport directives (Go 1.24+) marshal string PARAMETERS
// automatically into a raw (ptr uint32, len uint32) pair pointing into the
// calling side's own linear memory -- the caller is always responsible for
// placing the bytes, which is trivial when the caller already owns the data
// (e.g. the guest concatenating a Go string before calling an import).
// String/byte-slice RESULTS are not supported by either directive, so every
// function that needs to hand back variable-length data instead returns a
// single packed uint64 (see packPtrLen/unpackPtrLen) pointing into whichever
// side produced the data:
//   - Guest-produced results (render_screen/handle_event's ScreenUI JSON):
//     the guest allocates+writes in its own memory and returns the packed
//     value directly; the host unpacks and reads it.
//   - Host-produced results (fetch_url's response body, kv_get's value):
//     the host reentrantly calls the SAME plugin instance's own exported
//     alloc(size) to reserve space in the GUEST's memory, writes the bytes
//     there, and returns the packed value to the guest, which reads it out
//     of its own memory.
//
// Every dynamic-wasm plugin module MUST export `alloc(size int32) int32`
// (pinning the allocated buffer against GC until the call round-trip
// completes) as part of this ABI contract.
package wasmhost

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/decred/slog"
	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

const (
	// maxFetchBody caps how much of a plugin's fetch_url response body is
	// handed back to the guest.
	maxFetchBody = 2 * 1024 * 1024

	// maxKVValueBytes caps a single kv_set value.
	maxKVValueBytes = 1 * 1024 * 1024

	// maxLogMsgBytes caps a single log_msg call.
	maxLogMsgBytes = 4 * 1024

	// fetchTimeout bounds how long a guest's fetch_url call may block.
	fetchTimeout = 20 * time.Second

	// callTimeout bounds how long any single guest function invocation
	// (render_screen/handle_event/poll) may run before the host gives up --
	// guest code is untrusted and must not be able to hang the client. This
	// must stay short: render_screen/handle_event block a UI action.
	callTimeout = 10 * time.Second

	// linkCardCallTimeout bounds fetch_link_card specifically. Unlike
	// render_screen/handle_event, this call never blocks a UI action (the
	// card fetch runs in the background behind a plain-link placeholder --
	// see LinkCard's _loading state in the Dart UI) and a
	// CapabilityLinkCard plugin may need up to three sequential fetches
	// (oEmbed, an og:image scrape fallback, the thumbnail image itself),
	// each individually bounded by fetchTimeout -- callTimeout's 10s is too
	// tight a ceiling for that chain under real-world network jitter and
	// was observed truncating the thumbnail fetch specifically.
	linkCardCallTimeout = 30 * time.Second

	// MinPollInterval is the floor for a plugin-declared poll interval, so
	// a misbehaving/malicious manifest can't hammer feeds (or the host)
	// every few seconds.
	MinPollInterval = 60 * time.Second

	dataFileName = "data.json"
)

// ScreenUI is the declarative description of a single plugin screen that a
// dynamic-wasm plugin returns from render_screen/handle_event. The host UI
// interprets this data; the plugin itself never draws anything.
type ScreenUI struct {
	Title   string   `json:"title"`
	Widgets []Widget `json:"widgets"`
}

// Widget is one node of a ScreenUI's declarative widget tree. Only Type plus
// the fields relevant to it are expected to be populated.
type Widget struct {
	Type string `json:"type"` // "text","list","textfield","button","switch"

	// Text/Hint/Value are used by "text" (Text), "textfield" (Hint as
	// placeholder, Value as initial/current content), and "list" item rows
	// (Text as title, Hint as subtitle).
	Text  string `json:"text,omitempty"`
	Hint  string `json:"hint,omitempty"`
	Value string `json:"value,omitempty"`
	Bool  bool   `json:"bool,omitempty"`

	// Name identifies a textfield/switch's value in the payload map handed
	// to HandleEvent when a containing button's event fires.
	Name string `json:"name,omitempty"`

	// Event, if non-empty, is the event name sent to HandleEvent when this
	// widget (a button, or a list item itself) is activated.
	Event string `json:"event,omitempty"`

	// OpenURL, if non-empty, means activating this widget should open the
	// URL in the system browser client-side -- no round trip to the plugin.
	OpenURL string `json:"openUrl,omitempty"`

	// Danger styles a button/list-item action as destructive (e.g. red),
	// for things like "remove feed".
	Danger bool `json:"danger,omitempty"`

	// Muted de-emphasizes a text/list-item widget (e.g. a post already
	// read), styling it in a softer color rather than the default.
	Muted bool `json:"muted,omitempty"`

	// Bookmarkable/Bookmarked add a star toggle to a list item, activated
	// via the conventional "toggleBookmark" event (with the item's Value)
	// independent of the item's own primary Event/tap action.
	Bookmarkable bool `json:"bookmarkable,omitempty"`
	Bookmarked   bool `json:"bookmarked,omitempty"`

	// Items holds nested widgets for "list" (each item its own small widget
	// tree) and "section" (grouping) types.
	Items []Widget `json:"items,omitempty"`
}

// GrammarRule is a single regex-based writing-style check, supplied verbatim
// (never compiled/executed by Go) by a CapabilitySpellcheckData plugin.
// Pattern/Suggest are executed client-side in Dart, whose regex engine
// (unlike Go's RE2) supports the backreferences needed to express checks
// like "repeated word" (`\b(\w+)\s+\1\b`).
type GrammarRule struct {
	Pattern string `json:"pattern"`
	Message string `json:"message"`
	// Suggest is a replacement template that may reference Pattern's
	// capture groups as $1, $2, etc. An empty Suggest means the rule is
	// informational only (flagged, but with no proposed replacement).
	Suggest string `json:"suggest"`
}

// SpellcheckData is the wordlist + grammar rules a CapabilitySpellcheckData
// plugin's get_spellcheck_data export returns (and, once merged across all
// enabled such plugins, what golib hands to the Dart spellcheck UI).
type SpellcheckData struct {
	Words        []string      `json:"words"`
	GrammarRules []GrammarRule `json:"grammarRules"`
}

// LinkMetadata is what a CapabilityLinkCard plugin's fetch_link_card export
// returns for a URL it claims (via Manifest.Domains) to handle.
type LinkMetadata struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	Author       string `json:"author"`
	ThumbnailB64 string `json:"thumbnailB64"`
}

// Config configures a Runtime.
type Config struct {
	// Root is the plugin install root (the same directory
	// pluginmgr.Manager uses), i.e. <appdata>/plugins. Deliberately NOT
	// where a plugin's kv data lives (see dataDir) -- pluginmgr.Import
	// wholesale deletes and recreates Root/installed/<id>/ on every
	// import, including a same-ID update, so anything stored there
	// wouldn't survive a plugin update.
	Root string

	Log slog.Logger

	// HTTPClient is used for all guest fetch_url calls. Callers MUST pass
	// a client whose transport dials through the app's configured Tor
	// proxy, matching pluginmgr.Config.HTTPClient's contract -- wasmhost
	// does no proxy configuration of its own.
	HTTPClient *http.Client

	// OnPollComplete, if set, is called after every successful background
	// poll (see Load's pollInterval) with the plugin's id. Callers use
	// this to push a UI-visible notification (e.g. golib's NTDynPlugin
	// ScreenUpdated) so a currently-open screen can refresh -- there's no
	// pending request/response for a poll the way there is for
	// RenderScreen/HandleEvent, so without this hook the UI would have no
	// way to learn new data arrived short of polling itself.
	OnPollComplete func(pluginID string)
}

// Runtime loads and drives dynamic-wasm plugin instances.
type Runtime struct {
	cfg Config
	log slog.Logger
	wz  wazero.Runtime

	mtx      sync.Mutex
	byID     map[string]*pluginInst
	byModule map[api.Module]*pluginInst
}

type pluginInst struct {
	id       string
	dataPath string

	mod      api.Module
	allocFn  api.Function
	renderFn api.Function
	eventFn  api.Function
	pollFn   api.Function

	stopPoll chan struct{}

	// callMtx serializes every guest function invocation (render_screen,
	// handle_event, poll, get_spellcheck_data, fetch_link_card) against
	// this instance. A single compiled wasm module instance has one
	// linear memory and one execution stack; wazero does not itself
	// serialize concurrent calls into the same instance, so two
	// goroutines calling into it at once (e.g. several LinkCard widgets
	// each fetching a preview when a chat scrolls into view) corrupts
	// shared module state -- observed in practice as a wasm trap
	// ("invalid table access") from fetch_link_card under concurrent load.
	callMtx sync.Mutex

	kvMtx sync.Mutex
	kv    map[string]string

	// fetchMtx guards lastStatus/lastContentType: the status code and
	// Content-Type header of this plugin's most recent fetch_url/
	// fetch_url_ex call, retrievable via the fetch_last_status/
	// fetch_last_content_type imports -- see CapabilityLinkCard plugins,
	// which need Content-Type to replicate pluginmgr's old thumbnail
	// content-type allowlist.
	fetchMtx        sync.Mutex
	lastStatus      int
	lastContentType string
}

// NewRuntime creates a Runtime with the "env" host module (fetch_url,
// fetch_url_ex, fetch_last_status, fetch_last_content_type, kv_get, kv_set,
// log_msg) registered, ready to have plugin modules Load-ed into it.
func NewRuntime(ctx context.Context, cfg Config) (*Runtime, error) {
	log := cfg.Log
	if log == nil {
		log = slog.Disabled
	}
	if cfg.Root == "" {
		return nil, fmt.Errorf("wasmhost: Config.Root must not be empty")
	}
	if cfg.HTTPClient == nil {
		return nil, fmt.Errorf("wasmhost: Config.HTTPClient must not be nil")
	}

	wz := wazero.NewRuntime(ctx)
	if _, err := wasi_snapshot_preview1.Instantiate(ctx, wz); err != nil {
		wz.Close(ctx)
		return nil, fmt.Errorf("wasmhost: unable to instantiate WASI: %w", err)
	}

	r := &Runtime{
		cfg:      cfg,
		log:      log,
		wz:       wz,
		byID:     make(map[string]*pluginInst),
		byModule: make(map[api.Module]*pluginInst),
	}

	if err := r.registerHostModule(ctx); err != nil {
		wz.Close(ctx)
		return nil, err
	}

	return r, nil
}

// Close tears down every loaded plugin and the underlying wazero runtime.
func (r *Runtime) Close(ctx context.Context) error {
	r.mtx.Lock()
	ids := make([]string, 0, len(r.byID))
	for id := range r.byID {
		ids = append(ids, id)
	}
	r.mtx.Unlock()

	for _, id := range ids {
		r.Unload(id)
	}
	return r.wz.Close(ctx)
}

func (r *Runtime) registerHostModule(ctx context.Context) error {
	builder := r.wz.NewHostModuleBuilder("env")
	builder.NewFunctionBuilder().WithFunc(r.hostFetchURL).Export("fetch_url")
	builder.NewFunctionBuilder().WithFunc(r.hostFetchURLEx).Export("fetch_url_ex")
	builder.NewFunctionBuilder().WithFunc(r.hostFetchLastStatus).Export("fetch_last_status")
	builder.NewFunctionBuilder().WithFunc(r.hostFetchLastContentType).Export("fetch_last_content_type")
	builder.NewFunctionBuilder().WithFunc(r.hostKVGet).Export("kv_get")
	builder.NewFunctionBuilder().WithFunc(r.hostKVSet).Export("kv_set")
	builder.NewFunctionBuilder().WithFunc(r.hostLogMsg).Export("log_msg")

	if _, err := builder.Instantiate(ctx); err != nil {
		return fmt.Errorf("wasmhost: unable to instantiate env host module: %w", err)
	}
	return nil
}

func (r *Runtime) instFor(mod api.Module) *pluginInst {
	r.mtx.Lock()
	defer r.mtx.Unlock()
	return r.byModule[mod]
}

// packPtrLen and unpackPtrLen implement the data-return convention described
// in the package doc: a single uint64 carrying a (ptr,len) pair into
// whichever side produced variable-length data.
func packPtrLen(ptr, length uint32) uint64 {
	return (uint64(ptr) << 32) | uint64(length)
}

func unpackPtrLen(packed uint64) (ptr, length uint32) {
	return uint32(packed >> 32), uint32(packed & 0xFFFFFFFF)
}

// allocInGuest reentrantly calls inst's own exported alloc(size) to reserve
// space in ITS linear memory, then writes data into it there -- see the
// package doc for why the guest must be the one to place its own bytes.
func allocInGuest(ctx context.Context, inst *pluginInst, data []byte) (ptr, length uint32, err error) {
	res, err := inst.allocFn.Call(ctx, uint64(len(data)))
	if err != nil {
		return 0, 0, fmt.Errorf("alloc(%d) failed: %w", len(data), err)
	}
	ptr = uint32(res[0])
	if len(data) > 0 && !inst.mod.Memory().Write(ptr, data) {
		return 0, 0, fmt.Errorf("writing %d bytes at %d failed", len(data), ptr)
	}
	return ptr, uint32(len(data)), nil
}

func readPacked(mod api.Module, packed uint64) ([]byte, error) {
	ptr, length := unpackPtrLen(packed)
	if length == 0 {
		return nil, nil
	}
	b, ok := mod.Memory().Read(ptr, length)
	if !ok {
		return nil, fmt.Errorf("reading %d bytes at %d failed", length, ptr)
	}
	// Copy out: the returned slice aliases wasm linear memory, which the
	// next guest call may reuse/overwrite.
	out := make([]byte, len(b))
	copy(out, b)
	return out, nil
}

// --- host functions exposed to guest modules as the "env" module ---

// hostFetchURL backs the guest import `fetch_url(url string) uint64`. It
// fetches url through cfg.HTTPClient (the app's Tor-proxied client),
// capped by fetchTimeout/maxFetchBody, and hands the response body back via
// the packed-pointer convention. Fetch failures are reported to the guest
// as an empty result rather than trapping the module -- a single broken
// feed shouldn't be fatal to the plugin instance.
func (r *Runtime) hostFetchURL(ctx context.Context, mod api.Module, urlPtr, urlLen uint32) uint64 {
	inst := r.instFor(mod)
	if inst == nil {
		return 0
	}
	url, ok := readGuestString(mod, urlPtr, urlLen)
	if !ok {
		return 0
	}
	return r.doFetch(ctx, inst, mod, "fetch_url", url, nil)
}

// hostFetchURLEx backs the guest import `fetch_url_ex(url string,
// headersJSON string) uint64`: identical to fetch_url, but headersJSON (a
// JSON object of string->string, e.g. `{"User-Agent":"..."}`) is applied as
// request headers -- needed by CapabilityLinkCard plugins replicating
// site-specific fetch quirks (e.g. a crawler User-Agent) that a plain GET
// can't express. The status/Content-Type of this call are retrievable
// afterward via fetch_last_status/fetch_last_content_type.
func (r *Runtime) hostFetchURLEx(ctx context.Context, mod api.Module, urlPtr, urlLen, headersPtr, headersLen uint32) uint64 {
	inst := r.instFor(mod)
	if inst == nil {
		return 0
	}
	url, ok := readGuestString(mod, urlPtr, urlLen)
	if !ok {
		return 0
	}
	headersJSON, ok := readGuestString(mod, headersPtr, headersLen)
	if !ok {
		return 0
	}
	var headers map[string]string
	if headersJSON != "" {
		if err := json.Unmarshal([]byte(headersJSON), &headers); err != nil {
			r.log.Debugf("wasmhost: %s: fetch_url_ex invalid headersJSON: %v", inst.id, err)
			return 0
		}
	}
	return r.doFetch(ctx, inst, mod, "fetch_url_ex", url, headers)
}

// doFetch is the shared implementation behind fetch_url/fetch_url_ex:
// performs the request, records its status/Content-Type on inst for later
// retrieval, and hands the body back via the packed-pointer convention.
func (r *Runtime) doFetch(ctx context.Context, inst *pluginInst, mod api.Module, logName, url string, headers map[string]string) uint64 {
	fetchCtx, cancel := context.WithTimeout(ctx, fetchTimeout)
	defer cancel()

	req, err := http.NewRequestWithContext(fetchCtx, http.MethodGet, url, nil)
	if err != nil {
		r.log.Debugf("wasmhost: %s: invalid %s %q: %v", inst.id, logName, url, err)
		return 0
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := r.cfg.HTTPClient.Do(req)
	if err != nil {
		r.log.Debugf("wasmhost: %s: %s %q failed: %v", inst.id, logName, url, err)
		return 0
	}
	defer resp.Body.Close()

	inst.fetchMtx.Lock()
	inst.lastStatus = resp.StatusCode
	inst.lastContentType = resp.Header.Get("Content-Type")
	inst.fetchMtx.Unlock()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		r.log.Debugf("wasmhost: %s: %s %q status %d", inst.id, logName, url, resp.StatusCode)
		return 0
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, maxFetchBody))
	if err != nil {
		r.log.Debugf("wasmhost: %s: %s %q read failed: %v", inst.id, logName, url, err)
		return 0
	}

	ptr, length, err := allocInGuest(ctx, inst, body)
	if err != nil {
		r.log.Warnf("wasmhost: %s: %s %q: %v", inst.id, logName, url, err)
		return 0
	}
	return packPtrLen(ptr, length)
}

// hostFetchLastStatus backs `fetch_last_status() int32`: the HTTP status
// code of this plugin's most recent fetch_url/fetch_url_ex call (0 if none
// yet).
func (r *Runtime) hostFetchLastStatus(ctx context.Context, mod api.Module) int32 {
	inst := r.instFor(mod)
	if inst == nil {
		return 0
	}
	inst.fetchMtx.Lock()
	defer inst.fetchMtx.Unlock()
	return int32(inst.lastStatus)
}

// hostFetchLastContentType backs `fetch_last_content_type() uint64`: the
// Content-Type header of this plugin's most recent fetch_url/fetch_url_ex
// call, via the packed-pointer convention (empty if none yet).
func (r *Runtime) hostFetchLastContentType(ctx context.Context, mod api.Module) uint64 {
	inst := r.instFor(mod)
	if inst == nil {
		return 0
	}
	inst.fetchMtx.Lock()
	ct := inst.lastContentType
	inst.fetchMtx.Unlock()
	if ct == "" {
		return 0
	}
	ptr, length, err := allocInGuest(ctx, inst, []byte(ct))
	if err != nil {
		r.log.Warnf("wasmhost: %s: fetch_last_content_type: %v", inst.id, err)
		return 0
	}
	return packPtrLen(ptr, length)
}

// readGuestString reads length bytes at ptr from mod's memory as a string,
// the common first step of every host function taking a string parameter.
func readGuestString(mod api.Module, ptr, length uint32) (string, bool) {
	b, ok := mod.Memory().Read(ptr, length)
	if !ok {
		return "", false
	}
	return string(b), true
}

// hostKVGet backs `kv_get(key string) uint64`, returning the persisted
// value for key (empty if absent) via the packed-pointer convention.
func (r *Runtime) hostKVGet(ctx context.Context, mod api.Module, keyPtr, keyLen uint32) uint64 {
	inst := r.instFor(mod)
	if inst == nil {
		return 0
	}
	keyBytes, ok := mod.Memory().Read(keyPtr, keyLen)
	if !ok {
		return 0
	}

	inst.kvMtx.Lock()
	value := inst.kv[string(keyBytes)]
	inst.kvMtx.Unlock()
	if value == "" {
		return 0
	}

	ptr, length, err := allocInGuest(ctx, inst, []byte(value))
	if err != nil {
		r.log.Warnf("wasmhost: %s: kv_get: %v", inst.id, err)
		return 0
	}
	return packPtrLen(ptr, length)
}

// hostKVSet backs `kv_set(key string, value string)`, persisting the value
// to the plugin's data.json (via internal/jsonfile, same pattern
// pluginmgr.Manager uses for its own state.json).
func (r *Runtime) hostKVSet(ctx context.Context, mod api.Module, keyPtr, keyLen, valPtr, valLen uint32) {
	inst := r.instFor(mod)
	if inst == nil {
		return
	}
	if valLen > maxKVValueBytes {
		r.log.Warnf("wasmhost: %s: kv_set value too large (%d bytes), ignoring", inst.id, valLen)
		return
	}
	keyBytes, ok := mod.Memory().Read(keyPtr, keyLen)
	if !ok {
		return
	}
	valBytes, ok := mod.Memory().Read(valPtr, valLen)
	if !ok {
		return
	}

	inst.kvMtx.Lock()
	inst.kv[string(keyBytes)] = string(valBytes)
	kvCopy := make(map[string]string, len(inst.kv))
	for k, v := range inst.kv {
		kvCopy[k] = v
	}
	inst.kvMtx.Unlock()

	if err := jsonfile.Write(inst.dataPath, kvCopy, r.log); err != nil {
		r.log.Warnf("wasmhost: %s: unable to persist kv data: %v", inst.id, err)
	}
}

// hostLogMsg backs `log_msg(msg string)`, routing guest log output to the
// app's own logger at debug level, capped to maxLogMsgBytes.
func (r *Runtime) hostLogMsg(ctx context.Context, mod api.Module, msgPtr, msgLen uint32) {
	inst := r.instFor(mod)
	if inst == nil {
		return
	}
	if msgLen > maxLogMsgBytes {
		msgLen = maxLogMsgBytes
	}
	msgBytes, ok := mod.Memory().Read(msgPtr, msgLen)
	if !ok {
		return
	}
	r.log.Debugf("wasmhost: %s: %s", inst.id, string(msgBytes))
}

// --- lifecycle ---

// Load compiles and instantiates the plugin at wasmPath, identified by id,
// loads any previously-persisted kv data, and (if pollInterval > 0, clamped
// to MinPollInterval) starts a background ticker calling the guest's poll
// export. Loading the same id twice first Unloads the previous instance.
func (r *Runtime) Load(ctx context.Context, id, wasmPath string, pollInterval time.Duration) error {
	r.Unload(id) // no-op if not already loaded

	wasmBytes, err := readFileCapped(wasmPath, 32*1024*1024)
	if err != nil {
		return fmt.Errorf("wasmhost: unable to read %s: %w", wasmPath, err)
	}

	compiled, err := r.wz.CompileModule(ctx, wasmBytes)
	if err != nil {
		return fmt.Errorf("wasmhost: unable to compile %s: %w", wasmPath, err)
	}

	if err := os.MkdirAll(r.dataDir(id), 0o700); err != nil {
		compiled.Close(ctx)
		return fmt.Errorf("wasmhost: unable to create data dir for %s: %w", id, err)
	}
	dataPath := filepath.Join(r.dataDir(id), dataFileName)
	migrateLegacyData(wasmPath, dataPath)
	inst := &pluginInst{
		id:       id,
		dataPath: dataPath,
		stopPoll: make(chan struct{}),
		kv:       make(map[string]string),
	}
	if err := jsonfile.Read(dataPath, &inst.kv); err != nil && err != jsonfile.ErrNotFound {
		compiled.Close(ctx)
		return fmt.Errorf("wasmhost: unable to read persisted data for %s: %w", id, err)
	}

	// Register the (as yet module-less) instance so host functions called
	// during instantiation (_initialize) can already resolve it.
	// WithSysWalltime is required: wazero otherwise defaults every
	// module's time.Now() to a FAKE clock (a fixed epoch incrementing 1ms
	// per read), which would make every guest-computed timestamp (feed
	// item dates, LastFetched staleness checks) meaningless. WithSysNanotime
	// is the monotonic-clock equivalent (Go's runtime also consults it).
	modCfg := wazero.NewModuleConfig().
		WithStartFunctions("_initialize").
		WithSysWalltime().
		WithSysNanotime()
	mod, err := r.wz.InstantiateModule(ctx, compiled, modCfg)
	if err != nil {
		compiled.Close(ctx)
		return fmt.Errorf("wasmhost: unable to instantiate %s: %w", id, err)
	}
	inst.mod = mod

	inst.allocFn = mod.ExportedFunction("alloc")
	if inst.allocFn == nil {
		mod.Close(ctx)
		return fmt.Errorf("wasmhost: %s: plugin module missing required export \"alloc\"", id)
	}
	// render_screen/handle_event/poll are all optional: a headless plugin
	// (Manifest.Capabilities only, no Screens -- e.g. one implementing
	// get_spellcheck_data or fetch_link_card) legitimately has none of
	// them. Each accessor below nil-checks its function and errors
	// clearly if the plugin doesn't implement it.
	inst.renderFn = mod.ExportedFunction("render_screen")
	inst.eventFn = mod.ExportedFunction("handle_event")
	inst.pollFn = mod.ExportedFunction("poll")

	r.mtx.Lock()
	r.byID[id] = inst
	r.byModule[mod] = inst
	r.mtx.Unlock()

	if pollInterval > 0 && inst.pollFn != nil {
		if pollInterval < MinPollInterval {
			pollInterval = MinPollInterval
		}
		go r.runPollLoop(id, pollInterval)
	}

	return nil
}

// Unload stops id's poll loop (if any) and closes its module instance. A
// no-op if id isn't currently loaded.
func (r *Runtime) Unload(id string) {
	r.mtx.Lock()
	inst, ok := r.byID[id]
	if ok {
		delete(r.byID, id)
		delete(r.byModule, inst.mod)
	}
	r.mtx.Unlock()
	if !ok {
		return
	}

	close(inst.stopPoll)
	_ = inst.mod.Close(context.Background())
}

// migrateLegacyData is a one-time compatibility shim for plugins installed
// before data.json moved out of installed/<id>/ (alongside wasmPath) to its
// own directory (see dataDir): if dataPath doesn't exist yet but a
// same-named file sits next to wasmPath, copy it over so upgrading to this
// version of wasmhost doesn't itself look like a data-losing plugin update.
// A no-op once the new path exists, so it costs nothing on every other
// Load.
func migrateLegacyData(wasmPath, dataPath string) {
	if _, err := os.Stat(dataPath); !os.IsNotExist(err) {
		return
	}
	legacyPath := filepath.Join(filepath.Dir(wasmPath), dataFileName)
	legacyBytes, err := os.ReadFile(legacyPath)
	if err != nil {
		return
	}
	_ = os.WriteFile(dataPath, legacyBytes, 0o600)
}

// dataDir is where id's kv data.json lives: deliberately outside
// pluginmgr's installed/<id>/ tree (see Config.Root's doc), keyed only by
// plugin id so it's unaffected by that directory being wholesale replaced
// on every Import (including a same-ID update).
func (r *Runtime) dataDir(id string) string {
	return filepath.Join(r.cfg.Root, "data", id)
}

// DeleteData permanently removes id's persisted kv data. Callers should
// call this on an actual plugin removal (not an update/re-import) --
// pairs with pluginmgr.Manager.Remove, which the update path never calls.
func (r *Runtime) DeleteData(id string) error {
	return os.RemoveAll(r.dataDir(id))
}

func (r *Runtime) runPollLoop(id string, interval time.Duration) {
	r.mtx.Lock()
	inst := r.byID[id]
	r.mtx.Unlock()
	if inst == nil {
		return
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-inst.stopPoll:
			return
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), callTimeout)
			err := r.Poll(ctx, id)
			cancel()
			if err != nil {
				r.log.Debugf("wasmhost: %s: poll failed: %v", id, err)
			} else if r.cfg.OnPollComplete != nil {
				r.cfg.OnPollComplete(id)
			}
		}
	}
}

// --- guest calls ---

func (r *Runtime) inst(id string) (*pluginInst, error) {
	r.mtx.Lock()
	inst, ok := r.byID[id]
	r.mtx.Unlock()
	if !ok {
		return nil, fmt.Errorf("wasmhost: no loaded plugin %q", id)
	}
	return inst, nil
}

func callWithTimeout(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, callTimeout)
}

// RenderScreen calls the plugin's render_screen(screenID string) export and
// decodes its packed-pointer JSON result into a ScreenUI.
func (r *Runtime) RenderScreen(ctx context.Context, id, screenID string) (ScreenUI, error) {
	inst, err := r.inst(id)
	if err != nil {
		return ScreenUI{}, err
	}
	if inst.renderFn == nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: plugin does not export render_screen", id)
	}

	inst.callMtx.Lock()
	defer inst.callMtx.Unlock()

	ctx, cancel := callWithTimeout(ctx)
	defer cancel()

	ptr, length, err := allocInGuest(ctx, inst, []byte(screenID))
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: render_screen arg: %w", id, err)
	}

	res, err := inst.renderFn.Call(ctx, uint64(ptr), uint64(length))
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: render_screen(%q): %w", id, screenID, err)
	}
	return decodeScreenUI(inst.mod, res[0])
}

// HandleEvent calls the plugin's handle_event(screenID, event, payloadJSON
// string) export and decodes its packed-pointer JSON result into a
// ScreenUI.
func (r *Runtime) HandleEvent(ctx context.Context, id, screenID, event string, payload map[string]any) (ScreenUI, error) {
	inst, err := r.inst(id)
	if err != nil {
		return ScreenUI{}, err
	}
	if inst.eventFn == nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: plugin does not export handle_event", id)
	}

	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: encoding event payload: %w", id, err)
	}

	inst.callMtx.Lock()
	defer inst.callMtx.Unlock()

	ctx, cancel := callWithTimeout(ctx)
	defer cancel()

	screenPtr, screenLen, err := allocInGuest(ctx, inst, []byte(screenID))
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: handle_event screenID arg: %w", id, err)
	}
	eventPtr, eventLen, err := allocInGuest(ctx, inst, []byte(event))
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: handle_event event arg: %w", id, err)
	}
	payloadPtr, payloadLen, err := allocInGuest(ctx, inst, payloadJSON)
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: handle_event payload arg: %w", id, err)
	}

	res, err := inst.eventFn.Call(ctx,
		uint64(screenPtr), uint64(screenLen),
		uint64(eventPtr), uint64(eventLen),
		uint64(payloadPtr), uint64(payloadLen),
	)
	if err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: %s: handle_event(%q,%q): %w", id, screenID, event, err)
	}
	return decodeScreenUI(inst.mod, res[0])
}

// Poll calls the plugin's poll() export, which fetches/refreshes whatever
// background data the plugin maintains (e.g. RSS feed items) and persists
// it via kv_set itself; Poll doesn't interpret poll()'s return value beyond
// treating a nonzero result as an error signal.
func (r *Runtime) Poll(ctx context.Context, id string) error {
	inst, err := r.inst(id)
	if err != nil {
		return err
	}
	if inst.pollFn == nil {
		return fmt.Errorf("wasmhost: %s: plugin does not export poll", id)
	}

	inst.callMtx.Lock()
	defer inst.callMtx.Unlock()

	ctx, cancel := callWithTimeout(ctx)
	defer cancel()

	res, err := inst.pollFn.Call(ctx)
	if err != nil {
		return fmt.Errorf("wasmhost: %s: poll(): %w", id, err)
	}
	if len(res) > 0 && int32(res[0]) != 0 {
		return fmt.Errorf("wasmhost: %s: poll() returned error code %d", id, int32(res[0]))
	}
	return nil
}

// GetSpellcheckData calls the plugin's optional get_spellcheck_data()
// export (no arguments) and decodes its packed-pointer JSON result. Returns
// an error if the plugin doesn't implement it -- callers should only call
// this for plugins whose manifest declares CapabilitySpellcheckData.
func (r *Runtime) GetSpellcheckData(ctx context.Context, id string) (SpellcheckData, error) {
	inst, err := r.inst(id)
	if err != nil {
		return SpellcheckData{}, err
	}
	fn := inst.mod.ExportedFunction("get_spellcheck_data")
	if fn == nil {
		return SpellcheckData{}, fmt.Errorf("wasmhost: %s: plugin does not export get_spellcheck_data", id)
	}

	inst.callMtx.Lock()
	defer inst.callMtx.Unlock()

	ctx, cancel := callWithTimeout(ctx)
	defer cancel()

	res, err := fn.Call(ctx)
	if err != nil {
		return SpellcheckData{}, fmt.Errorf("wasmhost: %s: get_spellcheck_data(): %w", id, err)
	}
	b, err := readPacked(inst.mod, res[0])
	if err != nil {
		return SpellcheckData{}, err
	}
	var data SpellcheckData
	if err := json.Unmarshal(b, &data); err != nil {
		return SpellcheckData{}, fmt.Errorf("wasmhost: %s: decoding SpellcheckData: %w", id, err)
	}
	return data, nil
}

// FetchLinkCard calls the plugin's optional fetch_link_card(url string)
// export and decodes its packed-pointer JSON result. Returns an error if
// the plugin doesn't implement it -- callers should only call this for
// plugins whose manifest declares CapabilityLinkCard.
func (r *Runtime) FetchLinkCard(ctx context.Context, id, url string) (LinkMetadata, error) {
	inst, err := r.inst(id)
	if err != nil {
		return LinkMetadata{}, err
	}
	fn := inst.mod.ExportedFunction("fetch_link_card")
	if fn == nil {
		return LinkMetadata{}, fmt.Errorf("wasmhost: %s: plugin does not export fetch_link_card", id)
	}

	inst.callMtx.Lock()
	defer inst.callMtx.Unlock()

	ctx, cancel := context.WithTimeout(ctx, linkCardCallTimeout)
	defer cancel()

	ptr, length, err := allocInGuest(ctx, inst, []byte(url))
	if err != nil {
		return LinkMetadata{}, fmt.Errorf("wasmhost: %s: fetch_link_card arg: %w", id, err)
	}

	res, err := fn.Call(ctx, uint64(ptr), uint64(length))
	if err != nil {
		return LinkMetadata{}, fmt.Errorf("wasmhost: %s: fetch_link_card(%q): %w", id, url, err)
	}
	b, err := readPacked(inst.mod, res[0])
	if err != nil {
		return LinkMetadata{}, err
	}
	var metadata LinkMetadata
	if err := json.Unmarshal(b, &metadata); err != nil {
		return LinkMetadata{}, fmt.Errorf("wasmhost: %s: decoding LinkMetadata: %w", id, err)
	}
	return metadata, nil
}

func decodeScreenUI(mod api.Module, packed uint64) (ScreenUI, error) {
	b, err := readPacked(mod, packed)
	if err != nil {
		return ScreenUI{}, err
	}
	var ui ScreenUI
	if err := json.Unmarshal(b, &ui); err != nil {
		return ScreenUI{}, fmt.Errorf("wasmhost: decoding ScreenUI: %w", err)
	}
	return ui, nil
}
