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

// PartialsDir is where a site keeps the fragments its pages share, and
// AssetsDir the pictures they show.
const PartialsDir = "partials"
const AssetsDir = "assets"

// MaxPartialsPerPage bounds how many fragments one page may reach through
// others. A page needing more than this has stopped being a page with shared
// furniture and become something the reader should not be made to fetch in
// one go.
const MaxPartialsPerPage = 32

// MaxBundleBytes bounds what is sent with a page.
//
// A reply has to fit one message, and a fragment can be large -- a banner
// with a picture in it is most of a megabyte before anything else. Past this
// the fragments are left out rather than the page failing: the client asks
// for what is missing and gets it in replies of its own, which is slower and
// works, where an oversized reply is refused by the sending side and the
// reader is left waiting for a page that will never come.
const MaxBundleBytes = 512 * 1024

// includeRegexp matches a reference to a shared fragment: --include[name]--.
//
// Deliberately not Go's {{...}}, which a store's templates already use and
// which is expanded before anything is sent. These are the opposite: they
// survive being sent, and are filled in by the reader's client out of what it
// has already been given. Two mechanisms that look alike would be two
// mechanisms nobody could tell apart.
var includeRegexp = regexp.MustCompile(`--include\[([\w-]{1,64})\]--`)

// PartialNames returns the fragments a page refers to, in the order they
// first appear, without repeats and no more than MaxPartialsPerPage of them.
//
// Capped here as well as in the walk below, so that the cap holds wherever
// the question is asked. A page is a megabyte at most and an include is some
// fifteen bytes, so a page that is nothing else names seventy thousand of
// them -- and on the reading side each one is a message somebody pays for.
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
		if len(names) >= MaxPartialsPerPage {
			break
		}
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
	//
	// A picture is deliberately never bundled with the page that shows it.
	// It is asked for on its own and kept, so a banner behind every page of
	// a site crosses the wire once -- which is the whole reason a picture
	// is a file here rather than something written into the page.
	if filepath.Ext(pr.filename(req.Path)) != ".md" {
		return page, nil
	}
	wanted := PartialNames(string(data))
	if len(wanted) == 0 {
		return page, nil
	}

	have := haveSet(req.Meta)
	requestPath := strescape.ResourcesPath(req.Path)
	bundled := len(data)
	bundle := rpc.RMResourceBundle{
		Resources: map[string]rpc.RMFetchResourceReply{},
	}

	// Fragments may refer to other fragments -- a header holding a
	// navigation bar is the ordinary case -- so this walks what is
	// reachable from the page rather than only its first level.
	//
	// A fragment the client already holds is still read here, and still
	// not sent: what it refers to may be something the client does not
	// have, and stopping at it would leave that hole unfilled forever.
	queue := append([]string(nil), wanted...)
	seen := make(map[string]struct{}, len(queue))
	for _, n := range queue {
		seen[n] = struct{}{}
	}
	for i := 0; i < len(queue); i++ {
		if len(seen) > MaxPartialsPerPage {
			pr.log.Warnf("Page %s reaches more than %d fragments; "+
				"the rest are not sent", requestPath, MaxPartialsPerPage)
			break
		}
		name := queue[i]
		path := PartialPath(name)
		pdata, pfound, err := pr.read(path)
		if err != nil {
			return nil, err
		}
		if !pfound {
			// A page may refer to a fragment that is not there; the
			// reader is shown nothing where it would have gone rather
			// than the whole page failing.
			continue
		}

		for _, nested := range PartialNames(string(pdata)) {
			if _, ok := seen[nested]; ok {
				// Already queued, or a cycle -- header including
				// itself, or two including each other. Either way
				// there is nothing further to collect.
				continue
			}
			seen[nested] = struct{}{}
			queue = append(queue, nested)
		}

		if _, ok := have[name]; ok {
			continue
		}
		if bundled+len(pdata) > MaxBundleBytes {
			// Left for the client to ask for. Not break: a later
			// fragment may be small enough to fit, and sending it
			// saves a round trip that leaving it would cost.
			pr.log.Debugf("Not bundling %s with %s: %d bytes would "+
				"pass the bundle limit", name, requestPath,
				len(pdata))
			continue
		}
		bundled += len(pdata)
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
