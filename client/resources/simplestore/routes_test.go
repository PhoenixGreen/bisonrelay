package simplestore

import (
	"context"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/rpc"
)

// routes_test.go covers where a store answers when a pages site holds the
// root, which is what decides what a page's navigation bar has to write to
// reach it.
//
// Which provider the router picks, rather than what it replies: the answer
// here is about routing, and asking a store to actually serve its front page
// needs a running client behind it.

type pagesRoot struct{}

func (pagesRoot) Fulfill(_ context.Context, _ clientintf.UserID,
	_ *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	return nil, nil
}

// boundTogether is a client hosting both: the site owns the root, the store
// is bound beside it.
func boundTogether() (*resources.Router, resources.Provider) {
	site := pagesRoot{}
	r := resources.NewRouter()
	// The order the app binds them in, and it matters: the store claims its
	// own path names first, and the site then takes everything left. Bound
	// the other way round the site would swallow /cart and /admin.
	//
	// withIndex false: the root is the site's, so the store's front page
	// moves aside rather than fighting it for the root.
	(&Store{}).BindRoutes(r, false)
	r.BindPrefixPath(nil, site)
	return r, site
}

func provides(r *resources.Router, path ...string) resources.Provider {
	return r.FindProvider(&rpc.RMFetchResource{Path: path})
}

func TestAPageReachesTheStoreAtStore(t *testing.T) {
	// The answer to "what does a navigation bar write to link the store":
	// [Store](store). One segment, and no .md -- it is not a file of the
	// site's, it is the store answering.
	if StoreIndexPath != "store" {
		t.Fatalf("a bar has to write %q", StoreIndexPath)
	}

	r, site := boundTogether()
	got := provides(r, StoreIndexPath)
	if got == nil {
		t.Fatal("nothing answers at the store's path")
	}
	if got == resources.Provider(site) {
		t.Fatal("the site answers there, not the store")
	}
}

func TestTheSiteKeepsTheRoot(t *testing.T) {
	// The other half: binding a store beside a site must not take the front
	// page away from it.
	r, site := boundTogether()
	for _, path := range [][]string{nil, {"index.md"}} {
		if provides(r, path...) != resources.Provider(site) {
			t.Errorf("%v is not the site's any more", path)
		}
	}
}

func TestTheStoresOwnPathsStayItsOwn(t *testing.T) {
	// A store's templates link to these absolutely, so they cannot move
	// aside the way its front page does: a prefix would break every
	// seller's customised template.
	r, site := boundTogether()
	for _, path := range [][]string{
		{"cart"}, {"orders"}, {"product", "x"}, {"placeOrder"},
		// The two that let a buyer change their mind. A cart that can
		// only be added to and emptied is where somebody stops buying.
		{"removeFromCart"}, {"setCartQty"},
	} {
		got := provides(r, path...)
		if got == nil || got == resources.Provider(site) {
			t.Errorf("%v does not reach the store", path)
		}
	}
}

func TestAPageOfTheSitesOwnIsStillTheSites(t *testing.T) {
	// A page called about.md is the site's, and naming one after a store
	// path is the only way to lose it -- worth knowing, and worth failing
	// here if the store ever claims more than it does today.
	r, site := boundTogether()
	if provides(r, "about.md") != resources.Provider(site) {
		t.Error("an ordinary page no longer reaches the site")
	}
}

// TestASitesPicturesAreStillTheSites covers the one path both a site and a
// shop want to call their own.
//
// A site keeps its pictures in assets/ and has since they stopped being
// written into pages. When the shop claimed the same word for its own
// pictures it took that path with it -- the store binds its names before the
// site takes what is left -- and every banner, logo and picture on the
// site's own pages started answering 404.
func TestASitesPicturesAreStillTheSites(t *testing.T) {
	r, site := boundTogether()
	for _, path := range [][]string{
		{"assets", "banner.jpg"},
		{"assets", "logo.svg"},
	} {
		if provides(r, path...) != resources.Provider(site) {
			t.Errorf("%v is served by the shop, not the site", path)
		}
	}
}

func TestAShopsPicturesAreTheShops(t *testing.T) {
	r, site := boundTogether()
	got := provides(r, AssetsDir, "guitar.jpg")
	if got == nil || got == resources.Provider(site) {
		t.Errorf("%s/guitar.jpg does not reach the shop", AssetsDir)
	}
}

func TestTheShopDoesNotCallItsPicturesWhatTheSiteCallsIts(t *testing.T) {
	// The names are in one path space once both are hosted, so one of them
	// has to give -- and the site had it first.
	if AssetsDir == "assets" {
		t.Fatalf("the shop and the site both want %q", AssetsDir)
	}
}
