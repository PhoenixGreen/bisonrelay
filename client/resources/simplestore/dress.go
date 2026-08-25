package simplestore

import (
	"bytes"
	"os"
	"path/filepath"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
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
func (s *Store) dressed(uid clientintf.UserID, request *rpc.RMFetchResource,
	res *rpc.RMFetchResourceReply) *rpc.RMFetchResourceReply {

	if res == nil || res.Status != rpc.ResourceStatusOk {
		return res
	}
	// static/ and assets/ are served for things a page wants rather than
	// for somebody to read. A banner wrapped round a picture would be a
	// picture nothing can draw.
	if len(request.Path) > 0 &&
		(request.Path[0] == "static" || request.Path[0] == AssetsDir) {
		return res
	}

	// The site's frame is only for a shop that sits in a site. The shop's own
	// bar of links is for every shop.
	//
	// It was inside the same guard until a shop hosted on its own turned out
	// to have no navigation at all: no banner, which is right, and no way to
	// reach the cart or the orders either, which is not. That was survivable
	// only because each template ended with a couple of bare links -- and
	// those went when the bar was supposed to have replaced them.
	framed := s.siteRoot != "" && (s.header != "" || s.footer != "")

	var out string
	if framed && s.header != "" {
		out += "--include[" + s.header + "]--\n\n"
	}
	// The shop's own bar, under the site's banner and above the page. Its
	// links are the shop's -- the front, the cart, the orders -- which the
	// site's own bar has no reason to carry.
	nav := s.shopNav(uid)
	if nav != "" {
		out += nav + "\n\n"
	}
	if nav == "" && !framed {
		// Nothing to add: no frame, and no bar to put on either.
		return res
	}

	out += string(res.Data)
	if framed && s.footer != "" {
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

// navContext is what the shop's bar of links is drawn from.
type navContext struct {
	ShopIndex string
	CartItems int
	IsAdmin   bool
}

// shopNav is the bar of links put at the top of every page the shop renders.
//
// One bar, drawn in one place, rather than each template ending with its own
// arrangement of bare links. That is what it was: [Cart] and [Orders] here,
// [Clear cart] and [Back to the shop] there, in a different order and
// wording on every page and always at the bottom, under the content, where a
// bar is no use for deciding where to go next.
//
// Drawn from a template so a seller can change it, but emitted from here so
// no template has to remember to. A page that forgets the bar is a page the
// buyer is stranded on.
func (s *Store) shopNav(uid clientintf.UserID) string {
	// A store with no templates parsed is a real state -- it is what one
	// looks like before reloadStore has run -- and asking a nil template
	// set what it holds panics rather than answering.
	if s.tmpl == nil || s.tmpl.Lookup(navTmplFile) == nil {
		return ""
	}
	// How many things are in the cart, so the bar can say. A buyer who has
	// to open the cart to find out whether anything is in it opens it every
	// time.
	items := 0
	var cart Cart
	s.mtx.Lock()
	err := jsonfile.Read(filepath.Join(s.root, cartsDir, uid.String()), &cart)
	s.mtx.Unlock()
	if err == nil {
		for _, item := range cart.Items {
			items += int(item.Quantity)
		}
	}
	w := &bytes.Buffer{}
	err = s.tmpl.ExecuteTemplate(w, navTmplFile, &navContext{
		ShopIndex: s.indexPath,
		CartItems: items,
		IsAdmin:   s.isSelf(uid),
	})
	if err != nil {
		// The bar is chrome. A shop with no bar can still be bought from,
		// and refusing the page over it would be the wrong trade.
		s.log.Warnf("Unable to draw the shop's bar of links: %v", err)
		return ""
	}
	return w.String()
}
