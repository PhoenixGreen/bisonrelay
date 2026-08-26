package simplestore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/decred/slog"
)

// storenav_test.go covers where the shop's links go.
//
// A shop inside a site has two bars otherwise -- the site's pages and the
// shop's -- stacked one above the other, each saying half of where you can
// go. The seller can put the shop's into the site's instead, as words or as
// icons.
//
// The rule that matters is the one at the bottom: a setting about where the
// links go must never be able to mean "nowhere".

// dressedWith is a store page as a visitor reads it, for a shop whose links
// go where [mode] says. siteWith and dress are dress_test.go's.
func dressedWith(t *testing.T, header, mode string) string {
	t.Helper()
	layout := DefaultIndexLayout()
	layout.StoreNav = mode

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, cartsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	s := &Store{
		root:      root,
		siteRoot:  siteWith(t, map[string]string{"header": header}),
		header:    "header",
		indexPath: "/store",
		log:       slog.Disabled,
		layout:    layout,
	}
	return dress(s, "index.md", "# Shop")
}

const siteBar = "--nav[pills]--\n[Home](index.md)\n[About](about.md)\n--/nav--\n"

func TestTheShopsLinksJoinTheSitesBar(t *testing.T) {
	got := dressedWith(t, siteBar, NavLinks)

	// Inside the bar, after what the site wrote: outside it they are four
	// ordinary lines of markdown under a bar.
	bar := got[strings.Index(got, "--nav["):strings.Index(got, "--/nav--")]
	for _, want := range []string{"[Home](index.md)", "--right--",
		"[Shop](/store)", "[Cart](/cart)", "[Orders](/orders)"} {
		if !strings.Contains(bar, want) {
			t.Errorf("%q is not in the bar:\n%s", want, got)
		}
	}
	// And the shop's own bar is not drawn as well, or the page has two.
	if strings.Count(got, "--nav[") != 1 {
		t.Errorf("the page has more than one bar:\n%s", got)
	}
}

func TestTheIconsOptionKeepsTheWordsAsWhatTheyAreCalled(t *testing.T) {
	got := dressedWith(t, siteBar, NavIcons)

	if !strings.Contains(got, "[Cart](/cart)[icon=cart, label=off]") {
		t.Errorf("the cart is not an icon:\n%s", got)
	}
	// The words are still written, so a client that draws no icons -- and a
	// reader looking at the markup -- still has the link.
	if !strings.Contains(got, "[Orders](/orders)") {
		t.Errorf("the words were thrown away:\n%s", got)
	}
}

func TestWordsAndPicturesAreNotBoth(t *testing.T) {
	// An icon next to each word is a second alphabet in the same row, which
	// is neither of the two things a seller asked for.
	got := dressedWith(t, siteBar, NavLinks)
	if strings.Contains(got, "icon=") {
		t.Errorf("the words came with icons too:\n%s", got)
	}
}

func TestTheShopsHalfOfTheBarCanBeSetApart(t *testing.T) {
	// Icons want to sit closer together than words do, and a row of icons in
	// boxes is a row of buttons rather than a row of icons -- both of which
	// are true of the shop's half and not of the site's.
	layout := DefaultIndexLayout()
	layout.StoreNav = NavIcons
	layout.NavPlain = true
	layout.NavGap = 4

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, cartsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	s := &Store{
		root:      root,
		siteRoot:  siteWith(t, map[string]string{"header": siteBar}),
		header:    "header",
		indexPath: "/store",
		log:       slog.Disabled,
		layout:    layout,
	}
	got := dress(s, "index.md", "# Shop")

	if !strings.Contains(got, "gap=4") {
		t.Errorf("the shop's links keep the bar's own spacing:\n%s", got)
	}
	if !strings.Contains(got, "plain=on") {
		t.Errorf("the shop's links still have a box round them:\n%s", got)
	}
	// The site's own links are untouched: this is about the half that was
	// added, not about the bar.
	if strings.Contains(got, "[Home](index.md)[") {
		t.Errorf("the site's own links were changed:\n%s", got)
	}
}

func TestAShopThatHasAskedForNothingWritesABareMarker(t *testing.T) {
	// The same rule the grid keeps: a setting whose default changes what
	// every shop renders is a setting that arrives as a bug.
	got := dressedWith(t, siteBar, NavLinks)
	if !strings.Contains(got, "--right--") {
		t.Errorf("the marker carries settings nobody asked for:\n%s", got)
	}
}

func TestTheCartIsAtTheEndOfTheBar(t *testing.T) {
	// The one of these somebody is on their way to rather than browsing, and
	// the end of a bar is where a cart is looked for -- which is also where
	// its count has room to sit.
	got := dressedWith(t, siteBar, NavIcons)

	cart := strings.Index(got, "[Cart]")
	for _, before := range []string{"[Shop]", "[Orders]"} {
		if at := strings.Index(got, before); at == -1 || at > cart {
			t.Errorf("%s is not before the cart:\n%s", before, got)
		}
	}
}

// TestTheSitesOwnShopLinkIsMarkedOnEveryShopPage covers the link a bar
// cannot mark for itself.
//
// A bar marks the link to the page it is on by comparing paths. That works
// for a site's own pages and cannot work for a section: a shop is a dozen
// paths -- the front, a product, the cart, an order -- and only one of them
// is what the site's link says. The shop knows, and it is dressing the page.
func TestTheSitesOwnShopLinkIsMarkedOnEveryShopPage(t *testing.T) {
	bar := "--nav[pills]--\n[Home](index.md)\n[Store](store)\n--/nav--\n"

	layout := DefaultIndexLayout()
	layout.StoreNav = NavIcons
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, cartsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	s := &Store{
		root:      root,
		siteRoot:  siteWith(t, map[string]string{"header": bar}),
		header:    "header",
		indexPath: "/store",
		log:       slog.Disabled,
		layout:    layout,
	}

	// Not the front page: a product, which is where the comparison fails.
	got := dress(s, "product/gtr", "# A guitar")
	if !strings.Contains(got, "[Store](store)[active=on]") {
		t.Errorf("the site's link to the shop is not marked:\n%s", got)
	}
	if strings.Contains(got, "[Home](index.md)[") {
		t.Errorf("a link that is not the shop was marked:\n%s", got)
	}
}

func TestTheShopLinkCanBeLeftOut(t *testing.T) {
	// The ordinary answer for a site whose own bar already links to the shop,
	// which is how a visitor got there. Two links to one page in one bar is
	// one of them wasted.
	layout := DefaultIndexLayout()
	layout.StoreNav = NavIcons
	layout.NavShop = false

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, cartsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	s := &Store{
		root:      root,
		siteRoot:  siteWith(t, map[string]string{"header": siteBar}),
		header:    "header",
		indexPath: "/store",
		log:       slog.Disabled,
		layout:    layout,
	}
	got := dress(s, "index.md", "# Shop")

	if strings.Contains(got, "[Shop](/store)") {
		t.Errorf("the shop's own link is still there:\n%s", got)
	}
	// The rest of the shop's links are not: this is one link, not the group.
	for _, want := range []string{"[Orders]", "[Cart]"} {
		if !strings.Contains(got, want) {
			t.Errorf("%s went with it:\n%s", want, got)
		}
	}
}

func TestTheAdminLinkCanBeLeftOut(t *testing.T) {
	// The seller's own link and nobody else's, so this is about their bar
	// being tidy. The pages stay where they are.
	layout := DefaultIndexLayout()
	layout.StoreNav = NavLinks
	layout.NavAdmin = false

	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, cartsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	s := &Store{
		root:      root,
		siteRoot:  siteWith(t, map[string]string{"header": siteBar}),
		header:    "header",
		indexPath: "/store",
		log:       slog.Disabled,
		layout:    layout,
	}
	// isSelf is false without a client, so this only proves the link is
	// absent; the seller's own case is the one below.
	if got := dress(s, "index.md", "# Shop"); strings.Contains(got, "[Admin]") {
		t.Errorf("the admin link is still there:\n%s", got)
	}
}

func TestTheDefaultIsTheShopsOwnBar(t *testing.T) {
	got := dressedWith(t, siteBar, NavOwn)
	if strings.Contains(got, "--right") {
		t.Errorf("a shop that asked for its own bar was merged:\n%s", got)
	}
}

// TestASiteWithNoBarStillLeavesTheShopOne is the rule the rest of this rests
// on.
//
// The bar the shop merges into is the site's, and a site is under no
// obligation to have one. Merging into a bar that is not there would leave
// the shop with no navigation at all -- no cart, no orders, no way back --
// from a setting that only claimed to move them.
func TestASiteWithNoBarStillLeavesTheShopOne(t *testing.T) {
	site := siteWith(t, map[string]string{
		"header": "![](assets/banner.png)\n",
	})

	for _, mode := range []string{NavLinks, NavIcons} {
		layout := DefaultIndexLayout()
		layout.StoreNav = mode

		root := t.TempDir()
		if err := WriteTemplate(root); err != nil {
			t.Fatal(err)
		}
		s := &Store{root: root, siteRoot: site, header: "header",
			indexPath: "/store", log: slog.Disabled, layout: layout,
			products: map[string]*Product{}}
		if err := s.reloadStore(); err != nil {
			t.Fatal(err)
		}
		s.layout = layout

		if got := dress(s, "index.md", "# Shop"); !strings.Contains(got, "[Cart") {
			t.Errorf("%s: the shop has no way to its cart:\n%s", mode, got)
		}
	}
}
