package resources

import (
	"context"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/strescape"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// PartialsDir is where a site keeps the fragments its pages share.
const PartialsDir = "partials"

// includeRegexp matches a reference to a shared fragment: --include[name]--.
//
// Deliberately not Go's {{...}}, which a store's templates already use and
// which is expanded before anything is sent. These are the opposite: they
// survive being sent, and are filled in by the reader's client out of what it
// has already been given. Two mechanisms that look alike would be two
// mechanisms nobody could tell apart.
var includeRegexp = regexp.MustCompile(`--include\[([\w-]{1,64})\]--`)

// PartialNames returns the fragments a page refers to, in the order they
// first appear and without repeats.
func PartialNames(page string) []string {
	var names []string
	seen := make(map[string]struct{})
	for _, m := range includeRegexp.FindAllStringSubmatch(page, -1) {
		name := m[1]
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}
		names = append(names, name)
	}
	return names
}

// PartialPath is where a fragment lives, as a request path.
func PartialPath(name string) []string {
	return []string{PartialsDir, name + ".md"}
}

// PagesResource serves a directory of Markdown pages.
//
// The same as FilesystemResource, and one thing more: when a page refers to
// fragments the asking client does not say it already has, they are sent with
// it in a single bundle. The client stores what a bundle carries and serves
// later requests for it without another message, so a navigation bar shared
// by twenty pages crosses the wire once.
//
// Bundling rather than expanding the fragments into the page is what makes
// that possible. Expanding would be simpler and would cost the same as having
// no fragments at all -- the shared part would be in every page, every time.
type PagesResource struct {
	root string
	log  slog.Logger
}

func NewPagesResource(root string, log slog.Logger) *PagesResource {
	if log == nil {
		log = slog.Disabled
	}
	return &PagesResource{root: root, log: log}
}

// filename maps a request path to a file inside the root, escaping every
// element so a path cannot walk out of the directory being served.
func (pr *PagesResource) filename(path []string) string {
	parts := make([]string, 0, 1+len(path))
	parts = append(parts, pr.root)
	for _, e := range path {
		parts = append(parts, strescape.PathElement(e))
	}
	return filepath.Join(parts...)
}

func (pr *PagesResource) read(path []string) ([]byte, bool, error) {
	fname := pr.filename(path)
	data, err := os.ReadFile(fname)
	if os.IsNotExist(err) {
		return nil, false, nil
	} else if err != nil {
		return nil, false, err
	}
	if filepath.Ext(fname) == ".md" {
		data = []byte(ProcessEmbeds(string(data), pr.root, pr.log))
	}
	return data, true, nil
}

// haveSet reads the fragments the client says it already holds.
func haveSet(meta map[string]string) map[string]struct{} {
	out := make(map[string]struct{})
	for _, name := range strings.Split(meta[rpc.ResourceMetaHavePartials], ",") {
		name = strings.TrimSpace(name)
		if name != "" {
			out[name] = struct{}{}
		}
	}
	return out
}

// Fulfill is part of the Provider interface.
func (pr *PagesResource) Fulfill(ctx context.Context, uid clientintf.UserID,
	req *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	data, found, err := pr.read(req.Path)
	if err != nil {
		return nil, err
	}
	if !found {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusNotFound,
		}, nil
	}

	page := &rpc.RMFetchResourceReply{
		Data:   data,
		Status: rpc.ResourceStatusOk,
	}

	// Only Markdown carries fragments, and only a page the client is
	// missing something for needs a bundle.
	if filepath.Ext(pr.filename(req.Path)) != ".md" {
		return page, nil
	}
	wanted := PartialNames(string(data))
	if len(wanted) == 0 {
		return page, nil
	}

	have := haveSet(req.Meta)
	requestPath := strescape.ResourcesPath(req.Path)
	bundle := rpc.RMResourceBundle{
		Resources: map[string]rpc.RMFetchResourceReply{},
	}
	for _, name := range wanted {
		if _, ok := have[name]; ok {
			continue
		}
		path := PartialPath(name)
		pdata, pfound, err := pr.read(path)
		if err != nil {
			return nil, err
		}
		if !pfound {
			// A page may refer to a fragment that is not there; the
			// reader is told so where it would have gone rather than
			// the whole page failing.
			continue
		}
		bundle.Resources[strescape.ResourcesPath(path)] =
			rpc.RMFetchResourceReply{
				Data:   pdata,
				Status: rpc.ResourceStatusOk,
			}
	}

	if len(bundle.Resources) == 0 {
		return page, nil
	}

	// The page itself has to be in the bundle: the client looks the
	// original request path up in it to find what it asked for.
	bundle.Resources[requestPath] = *page
	pr.log.Debugf("Bundling %d partials with %s", len(bundle.Resources)-1,
		requestPath)

	br := &BundledResource{Bundle: bundle}
	return br.Fulfill(ctx, uid, req)
}
