package resources

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"syscall"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/strescape"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// PartialsDir is where a site keeps the fragments its pages share, and
// AssetsDir the pictures they show.
const PartialsDir = "fragments"

// OldPartialsDir is what that directory used to be called, and is only ever
// used to find one left over and move it. See golib's renameOldPartialsDir.
const OldPartialsDir = "partials"
const AssetsDir = "assets"

// MaxPartialsPerPage bounds how many fragments one page may reach through
// others. A page needing more than this has stopped being a page with shared
// furniture and become something the reader should not be made to fetch in
// one go.
const MaxPartialsPerPage = 32

// MaxPartialDepth is how far a fragment may reach through others. A header
// holding a navigation bar is two.
const MaxPartialDepth = 8

// MaxExpandedBytes is how large a page may become once its fragments are in
// it.
//
// A reply has to fit one message. Past this the page is sent as it was
// written, markers and all: what arrives is then visibly wrong in a way that
// says which page and which fragment, where an oversized reply is refused by
// the sending side and the reader waits for a page that never comes.
const MaxExpandedBytes = 768 * 1024

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

// IndexPage is the file a site serves when nothing in particular is asked
// for.
//
// A request with no path is the site's front page, which is what a link
// written "/" means and what opening a site with no page named means. It has
// to be spelled the same everywhere, because a site whose root and whose
// index.md are different pages is one where half the links go somewhere else.
const IndexPage = "index.md"

// PagesResource serves a directory of Markdown pages.
//
// The same as FilesystemResource, and one thing more: a page that refers to
// shared fragments is sent with them already in it, so a reader makes one
// request and gets one page. See expand.
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
	} else if errors.Is(err, syscall.EISDIR) {
		// A directory is not a page. Answered as "no such page" rather than
		// as an error, because the error is about this client's disk and the
		// reader asked about a page: what they can act on is that it is not
		// there.
		return nil, false, nil
	} else if err != nil {
		return nil, false, err
	}
	if filepath.Ext(fname) == ".md" {
		data = []byte(ProcessEmbeds(string(data), pr.root, pr.log))
	}
	return data, true, nil
}

// Fulfill is part of the Provider interface.
func (pr *PagesResource) Fulfill(ctx context.Context, uid clientintf.UserID,
	req *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	// Nothing asked for is the front page. Without this the root resolved to
	// the directory being served, and a reader following a link written "/"
	// was shown the error from trying to read a directory as a file --
	// "read /path/to/pages: is a directory", which names this client's own
	// filesystem and says nothing about the page they wanted.
	path := req.Path
	if len(path) == 0 {
		path = []string{IndexPage}
	}

	data, found, err := pr.read(path)
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

	// Only Markdown carries fragments.
	//
	// A picture is deliberately never touched here. It is a file of its own
	// and is asked for on its own, so a banner behind every page of a site
	// crosses the wire once -- which is the whole reason a picture is a file
	// rather than something written into the page.
	if filepath.Ext(pr.filename(path)) != ".md" {
		return page, nil
	}

	expanded, err := pr.expand(string(data))
	if err != nil {
		return nil, err
	}
	page.Data = []byte(expanded)
	return page, nil
}

// expand fills in the fragments a page refers to, and the fragments those
// refer to, and sends one page.
//
// On this side rather than the reader's. Expanding here costs the fragment's
// bytes on every page that shows it, which for text is a few hundred; the
// alternative was for the page to arrive with the markers still in it and
// the reader to fetch what it was missing, which saved those bytes and made
// the reader do work chosen by whoever wrote the page. One request, one
// reply, is worth more than the bytes -- the more so now that a picture is a
// file of its own, which is where the bytes actually were.
// ReadFragment is how ExpandIncludes gets at one fragment: its body, whether
// there is one, and any trouble reading it.
type ReadFragment func(name string) ([]byte, bool, error)

// ExpandIncludes fills a page's --include[name]-- markers in from [read].
//
// Shared, because two things serve pages made of fragments now: a site, and
// a store wearing that site's header and footer. Two copies of this would be
// two sets of limits to keep in step, and the limits are the whole of what
// makes it safe.
//
// A fragment is read once however often it is named. A fragment that reaches
// itself is left as written, so the writer can see the loop rather than
// wonder where it went. One that is not there leaves nothing, since the
// marker itself is not writing. Past MaxExpandedBytes the page is sent as it
// was written: a page too large to fill in is still a page.
func ExpandIncludes(page string, read ReadFragment, log slog.Logger) (string, error) {
	// held is what has been read already, so a fragment used twice is read
	// once and a cycle is answered from what is in hand rather than by
	// walking round again.
	held := make(map[string]string)
	var readOnce func(name string) (string, bool, error)
	readOnce = func(name string) (string, bool, error) {
		if body, ok := held[name]; ok {
			return body, true, nil
		}
		if len(held) >= MaxPartialsPerPage {
			return "", false, nil
		}
		data, found, err := read(name)
		if err != nil {
			return "", false, err
		}
		if !found {
			// Remembered as empty, so a page naming a fragment that is
			// not there does not go looking for it again on every
			// mention.
			held[name] = ""
			return "", false, nil
		}
		held[name] = string(data)
		return held[name], true, nil
	}

	var failed error
	var fill func(text string, depth int, active map[string]bool) string
	fill = func(text string, depth int, active map[string]bool) string {
		if depth >= MaxPartialDepth {
			return text
		}
		return includeRegexp.ReplaceAllStringFunc(text, func(marker string) string {
			name := includeRegexp.FindStringSubmatch(marker)[1]
			if active[name] {
				// A fragment that reaches itself. Left as written, so
				// the writer can see they have made a loop rather than
				// wondering where it went.
				return marker
			}
			body, ok, err := readOnce(name)
			if err != nil {
				failed = err
				return ""
			}
			if !ok {
				// Not there, or past what one page may pull in. Shown
				// as nothing, since the marker itself is not writing.
				return ""
			}
			active[name] = true
			out := fill(body, depth+1, active)
			delete(active, name)
			return out
		})
	}

	out := fill(page, 0, map[string]bool{})
	if failed != nil {
		return "", failed
	}
	if len(out) > MaxExpandedBytes {
		if log != nil {
			log.Warnf("A page expanded to %d bytes, past the %d a page may "+
				"be; sending it unexpanded", len(out), MaxExpandedBytes)
		}
		return page, nil
	}
	return out, nil
}

func (pr *PagesResource) expand(page string) (string, error) {
	return ExpandIncludes(page, func(name string) ([]byte, bool, error) {
		return pr.read(PartialPath(name))
	}, pr.log)
}
