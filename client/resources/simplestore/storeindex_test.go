package simplestore

import (
	"strings"
	"testing"
	"text/template"

	"github.com/companyzero/bisonrelay/client/resources"
)

// storeindex_test.go covers where a store's own links point.
//
// A store used to own the root, so a template writing "/" was writing the
// shop's front page. With a pages site hosted the root is the site's, and
// those links sent a visitor browsing products out of the shop and onto
// somebody's home page -- which is the arrangement this branch made the
// normal one.

func TestTemplatesLinkToTheShopAndNotTheSite(t *testing.T) {
	// The templates as shipped: no "/" or "/index.md" left in a link, since
	// both are the site's front page when a site is hosted.
	for _, name := range []string{
		"index.tmpl", "product.tmpl", "cart.tmpl",
		"orders.tmpl", "order.tmpl", "orderplaced.tmpl",
	} {
		raw, err := storeTemplate.ReadFile("template/" + name)
		if err != nil {
			t.Fatal(err)
		}
		for _, bad := range []string{"](/)", "](/index.md)"} {
			if strings.Contains(string(raw), bad) {
				t.Errorf("%s links to %s, which is the site's front page "+
					"when one is hosted", name, bad)
			}
		}
	}
}

func TestStoreIndexIsTheRootWhenTheStoreHasIt(t *testing.T) {
	s := &Store{indexPath: "/"}
	if got := render(t, s, "{{storeIndex}}"); got != "/" {
		t.Fatalf("got %q", got)
	}
}

func TestStoreIndexMovesAsideForASite(t *testing.T) {
	r := resources.NewRouter()
	s := &Store{indexPath: "/"}
	s.BindRoutes(r, false)
	if got := render(t, s, "{{storeIndex}}"); got != "/"+StoreIndexPath {
		t.Fatalf("got %q, want /%s", got, StoreIndexPath)
	}
}

func TestStoreKeepsTheRootWhenItHasNoSiteBesideIt(t *testing.T) {
	r := resources.NewRouter()
	s := &Store{indexPath: "/"}
	s.BindRoutes(r, true)
	if got := render(t, s, "{{storeIndex}}"); got != "/" {
		t.Fatalf("a store alone lost its own root: %q", got)
	}
}

func render(t *testing.T, s *Store, src string) string {
	t.Helper()
	tmpl, err := template.New("t").Funcs(s.templateFuncs()).Parse(src)
	if err != nil {
		t.Fatal(err)
	}
	var out strings.Builder
	if err := tmpl.Execute(&out, nil); err != nil {
		t.Fatal(err)
	}
	return out.String()
}
