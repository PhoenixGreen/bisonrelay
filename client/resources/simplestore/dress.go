package simplestore

import (
	"os"
	"path/filepath"

	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/rpc"
)

// dress.go puts a shop inside the site it belongs to.
//
// Every template the store renders emits a page body: it opens with a
// heading and carries no banner, no bar of links and no page settings of its
// own. So the frame goes on in one place here rather than being pasted into
// each of the seven, where changing it would mean changing seven files and
// remembering the next one somebody adds.
//
// What goes round it is named, not written: the seller says "header" and
// "footer", and those are fragments of their own site. Changing the site's
// banner changes the shop's with it, which is the whole point -- a shop that
// has to be restyled separately is a shop that ends up looking like a
// different website.

// dressed puts the header and footer round a rendered page.
//
// Left alone when there is nothing to put round it, when the reply is not a
// page anybody reads, or when it did not come out well: a 404 with a banner
// on it is still a 404, and wrapping one only makes the failure look
// deliberate.
func (s *Store) dressed(request *rpc.RMFetchResource,
	res *rpc.RMFetchResourceReply) *rpc.RMFetchResourceReply {

	if res == nil || res.Status != rpc.ResourceStatusOk {
		return res
	}
	if s.siteRoot == "" || (s.header == "" && s.footer == "") {
		return res
	}
	// static/ is served for things a template wants rather than for
	// somebody to read, so it is left as it is.
	if len(request.Path) > 0 && request.Path[0] == "static" {
		return res
	}

	var out string
	if s.header != "" {
		out += "--include[" + s.header + "]--\n\n"
	}
	out += string(res.Data)
	if s.footer != "" {
		out += "\n\n--include[" + s.footer + "]--"
	}

	// Filled in here, because the store is not the pages provider and
	// nothing else will do it: a marker that reached a reader unexpanded
	// would be drawn as the words it is made of.
	expanded, err := resources.ExpandIncludes(out, s.readSiteFragment, s.log)
	if err != nil {
		// The page itself is fine; only its frame is not. Sent bare rather
		// than not at all, because a shop nobody can buy from is worse than
		// a shop without a banner.
		s.log.Warnf("Unable to put the site's frame round a store page: %v", err)
		return res
	}

	dressed := *res
	dressed.Data = []byte(expanded)
	return &dressed
}

// readSiteFragment reads one of the site's fragments.
//
// Through the same path the pages provider uses, so a fragment means the
// same file to both and a name that is refused there is refused here.
func (s *Store) readSiteFragment(name string) ([]byte, bool, error) {
	if s.siteRoot == "" {
		return nil, false, nil
	}
	parts := append([]string{s.siteRoot}, resources.PartialPath(name)...)
	data, err := os.ReadFile(filepath.Join(parts...))
	if os.IsNotExist(err) {
		return nil, false, nil
	} else if err != nil {
		return nil, false, err
	}
	return data, true, nil
}
