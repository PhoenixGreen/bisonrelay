package capabilities

import (
	"context"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
)

// services.go is the generic path: calling a named service on whichever
// plugins provide it, without this package knowing what the service means.
//
// It is what makes a new service cost nothing. The three files beside this
// one exist because their results have to be *merged*, and how to merge two
// dictionaries is a fact about dictionaries -- but a service whose results do
// not need combining, or whose consumer can combine them itself, needs no
// file here at all. It is declared by the plugin, routed by name, and decoded
// by whoever asked.
//
// Nothing here validates a service name. A plugin may provide any name it
// likes; one nothing consumes is never called.

// Providers lists the enabled plugins answering service, in id order.
func Providers(mgr Manager, service string) []pluginmgr.Manifest {
	return mgr.PluginsProviding(service)
}

// Result is one provider's answer, still encoded.
//
// The plugin id rides along because a caller merging several answers usually
// needs to know whose is whose -- to order them stably, to attribute a
// failure, or to prefer a particular provider.
type Result struct {
	PluginID string
	Data     []byte
}

// CallAll asks every enabled provider of service and returns the answers that
// arrived, in plugin-id order.
//
// A provider that fails is skipped rather than failing the batch: one plugin
// still loading should not cost the user the others' results. Callers that
// need to know take the length -- an empty slice means nobody answered.
func CallAll(ctx context.Context, mgr Manager, rt Runtime, service string,
	arg []byte, timeout time.Duration) []Result {

	providers := mgr.PluginsProviding(service)
	out := make([]Result, 0, len(providers))
	for _, manifest := range providers {
		export, ok := manifest.ServiceExport(service)
		if !ok {
			continue
		}
		data, err := rt.Call(ctx, manifest.ID, export, arg, timeout)
		if err != nil || len(data) == 0 {
			continue
		}
		out = append(out, Result{PluginID: manifest.ID, Data: data})
	}
	return out
}

// CallFirst asks each provider in turn and returns the first non-empty
// answer, which is the right policy for a service where any one provider's
// answer is complete -- a lookup, a conversion, an unfurl.
//
// Returns nil when nobody answered, which a caller reads the same way it
// reads "no provider is enabled": by offering nothing.
func CallFirst(ctx context.Context, mgr Manager, rt Runtime, service string,
	arg []byte, timeout time.Duration) []byte {

	for _, manifest := range mgr.PluginsProviding(service) {
		export, ok := manifest.ServiceExport(service)
		if !ok {
			continue
		}
		data, err := rt.Call(ctx, manifest.ID, export, arg, timeout)
		if err == nil && len(data) > 0 {
			return data
		}
	}
	return nil
}

// ClaimsHost reports whether a provider's declaration of service claims host.
//
// A provider that declares no domains claims NOTHING here, which is the
// opposite of the usual "unset means any" and is deliberate. This is only
// asked for services that are handed a URL, and being handed a URL means
// being told what somebody is reading. A provider has to say which hosts it
// wants before it is told about any of them.
//
// pluginmgr does not enforce that at import, and should not: whether an empty
// domain list is meaningful is a fact about the service, which the manager is
// built not to know. It is enforced here, by the consumer that does -- so a
// plugin declaring a URL service with no domains still installs, and simply
// is never asked.
func ClaimsHost(manifest pluginmgr.Manifest, service, host string) bool {
	for _, provided := range manifest.Provides {
		if provided.Service != service {
			continue
		}
		for _, domain := range provided.Domains {
			if pluginmgr.NormalizeHost(domain) == host {
				return true
			}
		}
	}
	return false
}
