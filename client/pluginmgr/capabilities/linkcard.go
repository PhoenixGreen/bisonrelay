package capabilities

import (
	"context"
	"fmt"
	"net/url"
	"time"

	"github.com/companyzero/bisonrelay/client/pluginmgr"
)

// linkCardExport is the function a pluginmgr.CapabilityLinkCard plugin must
// export. It takes the URL and returns LinkMetadata.
const linkCardExport = "fetch_link_card"

// linkCardTimeout bounds one fetch_link_card call. Deliberately longer than
// the runtime's default: this call never blocks a UI action (the card is
// fetched in the background behind a plain-link placeholder) and a plugin
// may need several sequential fetches to answer -- an oEmbed lookup, an
// og:image scrape fallback, then the thumbnail image itself.
const linkCardTimeout = 30 * time.Second

// LinkMetadata is what a link-card plugin returns for a URL it claims (via
// Manifest.Domains) to handle.
type LinkMetadata struct {
	Title        string `json:"title"`
	Description  string `json:"description"`
	Author       string `json:"author"`
	ThumbnailB64 string `json:"thumbnailB64"`

	// Player names a client-side player the host should offer for this
	// link instead of a still thumbnail, or "" for an ordinary card.
	//
	// This is a *request*, not a guarantee: the host maps the name to
	// whichever players it actually ships and falls back to the plain card
	// for anything it doesn't recognise. It exists so the decision "this
	// link is playable" belongs to the plugin that claimed the domain,
	// rather than the host keeping its own list of which hostnames are
	// video sites.
	Player string `json:"player,omitempty"`
}

// FetchLinkCard resolves linkURL against the Domains of every enabled
// link-card plugin and, on the first match, calls that plugin's
// fetch_link_card. Domains are matched host-wise after NormalizeHost, so
// "www." and letter case never matter.
//
// Returns an error when no plugin claims the URL's host, which callers
// treat the same as an empty result: the link renders as a plain link.
func FetchLinkCard(ctx context.Context, mgr Manager, rt Runtime,
	linkURL string) (LinkMetadata, error) {

	parsed, err := url.Parse(linkURL)
	if err != nil || parsed.Host == "" ||
		(parsed.Scheme != "http" && parsed.Scheme != "https") {
		return LinkMetadata{}, fmt.Errorf("capabilities: not a fetchable url: %q", linkURL)
	}
	host := pluginmgr.NormalizeHost(parsed.Hostname())

	for _, manifest := range mgr.PluginsProviding(pluginmgr.ServiceLinkCard) {
		if !ClaimsHost(manifest, pluginmgr.ServiceLinkCard, host) {
			continue
		}
		export, _ := manifest.ServiceExport(pluginmgr.ServiceLinkCard)
		var metadata LinkMetadata
		err := call(ctx, rt, manifest.ID, export, []byte(linkURL),
			linkCardTimeout, &metadata)
		return metadata, err
	}
	return LinkMetadata{}, fmt.Errorf("capabilities: no plugin handles %q", host)
}
