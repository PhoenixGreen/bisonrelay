package simplestore

import (
	"bytes"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"

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
	//
	// Unless the seller would rather they went in the site's bar -- and
	// only if there is one to go in.
	//
	// Which means expanding the header on its own first, because up here it
	// is still a marker naming a fragment, and whether that fragment holds a
	// bar is the whole question. A shop that meant to merge into a bar that
	// is not there must still have its own: a setting about where the links
	// go can never be allowed to mean "nowhere".
	merging := framed && s.header != "" &&
		s.IndexLayout().StoreNav != NavOwn && s.headerHasBar()

	nav := ""
	if !merging {
		nav = s.shopNav(uid)
		if nav != "" {
			out += nav + "\n\n"
		}
	}
	if nav == "" && !merging && !framed {
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

	// The shop's links into the site's own bar, now that there is a bar to
	// put them in.
	if merging {
		if merged, ok := s.mergedNav(uid, expanded); ok {
			expanded = merged
		}
	}

	dressed := *res
	dressed.Data = []byte(expanded)
	return &dressed
}

// headerHasBar is whether the site's header holds a bar of links for the
// shop's own to join.
//
// The header expanded on its own, because a header is a fragment and the bar
// may be in a fragment it includes -- a banner that names a nav fragment is
// how several of these are written.
func (s *Store) headerHasBar() bool {
	expanded, err := resources.ExpandIncludes("--include["+s.header+"]--",
		s.readSiteFragment, s.log)
	if err != nil {
		return false
	}
	return navBarPattern.MatchString(expanded)
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

// navBarPattern finds the bar of links in a site's header: the marker that
// opens one, everything up to the marker that closes it.
//
// The first bar rather than any of them. A header holding two is a header
// with a bar in its banner and another under it, and the one somebody means
// by "the navigation" is the one they wrote first.
var navBarPattern = regexp.MustCompile(`(?s)(--nav(?:\[[^\]]*\])?--
)(.*?)(
--/nav--)`)

// mergedNav is the site's header with the shop's links added to the end of
// its bar, or false for a shop that is not doing that.
//
// False rather than an empty header for three real cases: a seller who wants
// the shop's own bar, a shop hosted without a site, and a site whose header
// has no bar to join. In all three the shop draws its own bar, because the
// alternative is a shop with no navigation at all -- and a setting about
// where the links go should never be able to mean "nowhere".
func (s *Store) mergedNav(uid clientintf.UserID, header string) (string, bool) {
	layout := s.IndexLayout()
	if layout.StoreNav == NavOwn || header == "" {
		return "", false
	}
	where := navBarPattern.FindStringSubmatchIndex(header)
	if where == nil {
		return "", false
	}

	links := s.navLinks(uid, layout)
	if links == "" {
		return "", false
	}

	var said []string
	if layout.NavGap >= 0 {
		said = append(said, fmt.Sprintf("gap=%d", layout.NavGap))
	}
	if layout.NavIconSize >= 0 {
		said = append(said, fmt.Sprintf("size=%d", layout.NavIconSize))
	}
	if layout.NavInset > 0 {
		said = append(said, fmt.Sprintf("inset=%d", layout.NavInset))
	}
	marker := "--right--"
	if len(said) > 0 {
		marker = fmt.Sprintf("--right[%s]--", strings.Join(said, ", "))
	}

	// The site's own link to the shop, marked as the page being read.
	//
	// A bar marks the link to the page it is on by comparing paths, which
	// cannot work for a section: a shop is a dozen paths -- the front, a
	// product, the cart, an order -- and only one of them is what the link
	// says. The shop is the one thing that knows, and it is dressing the
	// page, so it says.
	header = s.markShopLink(header[:where[6]]) + header[where[6]:]
	where = navBarPattern.FindStringSubmatchIndex(header)
	if where == nil {
		return "", false
	}

	// Inside the bar, after what the site wrote and before the line that
	// closes it, behind the marker that pushes what follows to the far end.
	//
	// where[6] is where the closing marker begins. Ending up one group later
	// -- after the marker -- puts the shop's links outside the bar, where
	// they are four ordinary lines of markdown under it.
	var out strings.Builder
	out.WriteString(header[:where[6]])
	out.WriteString("\n" + marker + "\n")
	out.WriteString(strings.TrimRight(links, "\n"))
	out.WriteString(header[where[6]:])
	return out.String(), true
}

// shopLinkPattern is a link in the site's own bar, with whatever it says
// about itself after it.
var shopLinkPattern = regexp.MustCompile(`(?m)^(\s*\[[^\]]*\]\(([^)]*)\))(\[([^\]]*)\])?\s*$`)

// markShopLink marks the site's own link to the shop as the page being read.
//
// The site's, not the shop's: the seller wrote [Store](store) in their
// navigation, and while a shop page is open that is the section being read
// however deep into it the reader has gone.
func (s *Store) markShopLink(bar string) string {
	want := path.Base(strings.Trim(s.indexPath, "/"))
	if want == "" || want == "." {
		return bar
	}

	return shopLinkPattern.ReplaceAllStringFunc(bar, func(line string) string {
		m := shopLinkPattern.FindStringSubmatch(line)
		if path.Base(strings.Trim(m[2], "/")) != want {
			return line
		}
		// Onto whatever it already said, rather than instead of it.
		says := strings.TrimSpace(m[4])
		if says == "" {
			says = "active=on"
		} else if !strings.Contains(says, "active=") {
			says += ", active=on"
		}
		return m[1] + "[" + says + "]"
	})
}

// navLinks are the shop's links, written for a bar the site owns.
//
// Written here rather than taken from shopnav.tmpl, because these carry what
// that template has no way to say: the count over the cart, an icon, and
// whether the words are drawn at all. The template is still what draws the
// shop's own bar, so a seller who has rewritten it keeps their bar.
func (s *Store) navLinks(uid clientintf.UserID, layout IndexLayout) string {
	icons := layout.StoreNav == NavIcons
	// Words or pictures, not both. Words beside the site's own words read as
	// one bar; an icon next to each of them is a second alphabet in the same
	// row, which is neither of the two things a seller asked for.
	var out strings.Builder
	link := func(label, target, icon string, badge int) {
		var says []string
		if badge > 0 {
			says = append(says, fmt.Sprintf("badge=%d", badge))
		}
		if icons {
			// The words stay as what the icon is called when hovered: an
			// icon on its own is a guess until somebody hovers it.
			says = append(says, "icon="+icon, "label=off")
		}
		if layout.NavPlain {
			says = append(says, "plain=on")
		}

		fmt.Fprintf(&out, "[%s](%s)", label, target)
		if len(says) > 0 {
			fmt.Fprintf(&out, "[%s]", strings.Join(says, ", "))
		}
		out.WriteString("\n")
	}

	// The cart last, at the end of the bar. It is the one of these somebody
	// is on their way to rather than browsing, and the end of a bar is where
	// a cart is looked for -- which is also where its count has room to sit.
	if layout.NavShop {
		link("Shop", s.indexPath, "shop", 0)
	}
	link("Orders", "/orders", "orders", 0)
	if s.isSelf(uid) && layout.NavAdmin {
		link("Admin", "/admin", "admin", 0)
	}
	link("Cart", "/cart", "cart", s.cartCount(uid))
	return out.String()
}

// cartCount is how many things this buyer has in their cart.
//
// A buyer who has to open the cart to find out whether anything is in it
// opens it every time.
func (s *Store) cartCount(uid clientintf.UserID) int {
	var cart Cart
	s.mtx.Lock()
	err := jsonfile.Read(filepath.Join(s.root, cartsDir, uid.String()), &cart)
	s.mtx.Unlock()
	if err != nil {
		return 0
	}
	items := 0
	for _, item := range cart.Items {
		items += int(item.Quantity)
	}
	return items
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
	w := &bytes.Buffer{}
	err := s.tmpl.ExecuteTemplate(w, navTmplFile, &navContext{
		ShopIndex: s.indexPath,
		CartItems: s.cartCount(uid),
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
