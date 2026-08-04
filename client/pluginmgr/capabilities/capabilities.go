// Package capabilities holds the host side of every headless plugin
// capability: for each one, the exported function a plugin must provide, the
// shape of what crosses the wasm boundary, and how results from several
// plugins declaring the same capability combine.
//
// It exists so that neither layer beneath it has to know what a capability
// means:
//
//   - wasmhost is the generic runtime. It knows how to reach an export and
//     move bytes across the guest boundary (Runtime.Call) and nothing else.
//   - pluginmgr owns manifests and install state. It knows capability
//     *names*, because they are part of the manifest schema it validates,
//     but nothing about the calls behind them.
//
// Adding a capability is therefore one new file here, plus its name in
// pluginmgr's manifest schema. Neither the runtime nor the manager changes.
//
// Every function here takes the manager and the runtime rather than holding
// them, so a capability is a plain function over "the plugins currently
// enabled" -- there is no capability-specific state to keep anywhere.
package capabilities

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
	"github.com/decred/slog"
)

// Runtime is the part of *wasmhost.Runtime a capability call needs. Narrowed
// to an interface so a capability can be tested against a stub without
// standing up a real wasm runtime.
type Runtime interface {
	Call(ctx context.Context, id, export string, arg []byte, timeout time.Duration) ([]byte, error)
}

// Manager is the part of *pluginmgr.Manager a capability call needs.
type Manager interface {
	PluginsWithCapability(capability string) []pluginmgr.Manifest
}

// call invokes export on plugin id and decodes its JSON result into out.
// A plugin that doesn't export the function, fails, or returns something
// undecodable is reported to the caller, which decides whether that's fatal
// (a single-plugin call) or merely skippable (an aggregate over several).
func call(ctx context.Context, rt Runtime, id, export string, arg []byte,
	timeout time.Duration, out any) error {
	b, err := rt.Call(ctx, id, export, arg, timeout)
	if err != nil {
		return err
	}
	if len(b) == 0 {
		return nil
	}
	if err := json.Unmarshal(b, out); err != nil {
		return fmt.Errorf("capabilities: %s: decoding %s result: %w", id, export, err)
	}
	return nil
}

// logf reports a single plugin's failure without failing the whole call.
// Aggregates deliberately degrade rather than abort: one plugin that hasn't
// finished loading shouldn't cost the user the others' results.
func logf(log slog.Logger, format string, args ...any) {
	if log != nil {
		log.Warnf(format, args...)
	}
}
