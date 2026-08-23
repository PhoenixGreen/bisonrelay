package simplestore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// dress_test.go covers a shop wearing the site's frame.
//
// Every store template emits a page body with no banner of its own, so the
// frame goes on in one place. What matters is that it goes on every page a
// visitor reads, that a shop with no site beside it is untouched, and that a
// failure to dress a page never costs the page itself.

func siteWith(t *testing.T, fragments map[string]string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, resources.PartialsDir)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	for name, body := range fragments {
		err := os.WriteFile(filepath.Join(dir, name+".md"), []byte(body), 0o600)
		if err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func dress(s *Store, path string, body string) string {
	req := &rpc.RMFetchResource{Path: strings.Split(path, "/")}
	res := &rpc.RMFetchResourceReply{
		Data:   []byte(body),
		Status: rpc.ResourceStatusOk,
	}
	return string(s.dressed(req, res).Data)
}

func shopIn(root, header, footer string) *Store {
	return &Store{
		log:      slog.Disabled,
		siteRoot: root,
		header:   header,
		footer:   footer,
	}
}

func TestAShopWearsTheSitesFrame(t *testing.T) {
	root := siteWith(t, map[string]string{
		"header": "# My Site",
		"footer": "[Home](index.md)",
	})
	got := dress(shopIn(root, "header", "footer"), "index.md", "# My Shop")

	for _, want := range []string{"# My Site", "# My Shop", "[Home](index.md)"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q is not on the page:\n%s", want, got)
		}
	}
	// In that order: the banner above the shop, the footer below it.
	if strings.Index(got, "# My Site") > strings.Index(got, "# My Shop") {
		t.Error("the banner is below the shop")
	}
	if strings.Index(got, "[Home](index.md)") < strings.Index(got, "# My Shop") {
		t.Error("the footer is above the shop")
	}
}

func TestTheFrameIsFilledInAndNotLeftAsMarkers(t *testing.T) {
	// The store is not the pages provider, and nothing else would do it: a
	// marker reaching a reader is drawn as the words it is made of.
	root := siteWith(t, map[string]string{"header": "# My Site"})
	got := dress(shopIn(root, "header", ""), "index.md", "# My Shop")
	if strings.Contains(got, "--include[") {
		t.Fatalf("a marker reached the reader:\n%s", got)
	}
}

func TestEveryPageAVisitorReadsIsDressed(t *testing.T) {
	// Seven pages, and the ones nobody thinks to style -- the cart, the
	// confirmation -- are exactly the ones a seller would miss.
	root := siteWith(t, map[string]string{"header": "# My Site"})
	s := shopIn(root, "header", "")
	for _, path := range []string{
		"index.md", "product/abc", "cart", "orders", "order/1",
		"addToCart", "placeOrder",
	} {
		if !strings.Contains(dress(s, path, "body"), "# My Site") {
			t.Errorf("%s is not dressed", path)
		}
	}
}

func TestStaticIsLeftAlone(t *testing.T) {
	// Served for something a template wants rather than for somebody to
	// read.
	root := siteWith(t, map[string]string{"header": "# My Site"})
	got := dress(shopIn(root, "header", ""), "static/thing", "raw")
	if got != "raw" {
		t.Fatalf("got %q", got)
	}
}

func TestAShopWithNoSiteIsUntouched(t *testing.T) {
	// A store hosted on its own has no fragments to read, so naming one
	// would put markers round every page that expand to nothing.
	got := dress(shopIn("", "header", "footer"), "index.md", "# My Shop")
	if got != "# My Shop" {
		t.Fatalf("got %q", got)
	}
}

func TestAShopThatNamesNothingIsUntouched(t *testing.T) {
	root := siteWith(t, map[string]string{"header": "# My Site"})
	got := dress(shopIn(root, "", ""), "index.md", "# My Shop")
	if got != "# My Shop" {
		t.Fatalf("got %q", got)
	}
}

func TestOnlyOneOfTheTwoIsFine(t *testing.T) {
	root := siteWith(t, map[string]string{"header": "# My Site"})
	got := dress(shopIn(root, "header", ""), "index.md", "# My Shop")
	if !strings.Contains(got, "# My Site") || !strings.Contains(got, "# My Shop") {
		t.Fatalf("got %q", got)
	}
}

func TestANamedFragmentThatIsNotThereCostsNothing(t *testing.T) {
	// The shop still sells things. A missing banner is a missing banner.
	root := siteWith(t, map[string]string{})
	got := dress(shopIn(root, "nosuch", ""), "index.md", "# My Shop")
	if !strings.Contains(got, "# My Shop") {
		t.Fatalf("the shop went with the banner: %q", got)
	}
	if strings.Contains(got, "--include[") {
		t.Fatalf("a marker was left behind: %q", got)
	}
}

func TestAReplyThatIsNotOkIsNotDressed(t *testing.T) {
	// A 404 with a banner on it is still a 404, and dressing one only makes
	// the failure look deliberate.
	root := siteWith(t, map[string]string{"header": "# My Site"})
	s := shopIn(root, "header", "")
	res := &rpc.RMFetchResourceReply{
		Data:   []byte("not found"),
		Status: rpc.ResourceStatusNotFound,
	}
	got := s.dressed(&rpc.RMFetchResource{Path: []string{"nope"}}, res)
	if string(got.Data) != "not found" {
		t.Fatalf("got %q", got.Data)
	}
}
