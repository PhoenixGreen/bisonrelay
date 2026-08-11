package golib

import (
	"context"
	"path/filepath"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
	"github.com/companyzero/bisonrelay/client/pluginmgr/wasmhost"
	"github.com/decred/slog"
)

// plugins.go is golib's whole plugin surface: keeping the wasm runtime in
// step with the plugin manager's install/enable state. Everything a plugin
// actually *does* reaches the app through client/pluginmgr/capabilities
// (headless services) or the runtime's screen calls (plugin-drawn UI), so
// nothing here has to know what any capability means.

// syncDynPlugin loads or unloads p to match its current enabled state and
// renderer kind. It's a no-op for a plugin the runtime doesn't drive.
//
// Load errors -- a corrupt wasm file, say -- are logged rather than
// returned: the manager's own state is already authoritative and shouldn't
// be rolled back over a runtime that failed to start. The plugin simply
// isn't running, and the next enable or import retries it.
func syncDynPlugin(ctx context.Context, mgr *pluginmgr.Manager,
	rt *wasmhost.Runtime, log slog.Logger, p pluginmgr.Plugin) {

	if p.Manifest.RendererKind != pluginmgr.RendererKindDynamicWasm {
		return
	}
	if !p.Enabled {
		rt.Unload(p.Manifest.ID)
		return
	}

	wasmPath := filepath.Join(mgr.InstallDir(p.Manifest.ID), p.Manifest.WasmFile)
	pollInterval := time.Duration(p.Manifest.PollIntervalSeconds) * time.Second
	if err := rt.Load(ctx, p.Manifest.ID, wasmPath, pollInterval); err != nil {
		log.Warnf("unable to load plugin %s: %v", p.Manifest.ID, err)
	}
}

// syncPlugin is syncDynPlugin against this client's own manager, runtime and
// log, for the Import/SetEnabled/Remove paths that may have changed either
// of the states it reconciles.
func (cc *clientCtx) syncPlugin(p pluginmgr.Plugin) {
	syncDynPlugin(cc.ctx, cc.pluginMgr, cc.dynRuntime, cc.log, p)
}
