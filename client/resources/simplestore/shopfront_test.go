package simplestore

import (
	"bytes"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"text/template"

	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// shopfront_test.go covers the shop front: a grid of products, each cell led
// by a picture.
//
// The grid reads a cell as starting at a picture, so every product must
// contribute one. A product with none gets the placeholder -- not for
// decoration, but because a cell that does not start with a picture is not a
// cell, and its writing joins the one before it.

func renderIndex(t *testing.T, products []*Product) string {
	return renderIndexAs(t, &Store{indexPath: "/", log: slog.Disabled}, products)
}

func renderIndexAs(t *testing.T, s *Store, products []*Product) string {
	t.Helper()
	raw, err := storeTemplate.ReadFile("template/index.tmpl")
	if err != nil {
		t.Fatal(err)
	}
	tmpl, err := template.New("index").Funcs(s.templateFuncs()).Parse(string(raw))
	if err != nil {
		t.Fatal(err)
	}
	byKey := make(map[string]*Product, len(products))
	for _, p := range products {
		byKey[p.SKU] = p
	}
	var out bytes.Buffer
	if err := tmpl.Execute(&out, indexContext{Products: byKey}); err != nil {
		t.Fatal(err)
	}
	return out.String()
}

var cellStart = regexp.MustCompile(`(?m)^!\[\]\(`)

func TestEveryProductLeadsWithAPicture(t *testing.T) {
	got := renderIndex(t, []*Product{
		{Title: "A guitar", SKU: "gtr", Image: "guitar.jpg"},
		{Title: "A drum", SKU: "drm"}, // no picture of its own
	})

	if n := len(cellStart.FindAllString(got, -1)); n != 2 {
		t.Fatalf("two products gave %d cells:\n%s", n, got)
	}
	if !strings.Contains(got, "![]("+ProductImagePath("guitar.jpg")+")") {
		t.Errorf("the product's own picture is missing:\n%s", got)
	}
	if !strings.Contains(got, "![]("+ProductImagePath("placeholder.png")+")") {
		t.Errorf("a product without one gets no placeholder:\n%s", got)
	}
}

func TestTheCellsAreInsideTheGrid(t *testing.T) {
	got := renderIndex(t, []*Product{{Title: "A guitar", SKU: "gtr"}})
	open, close := strings.Index(got, "--grid["), strings.Index(got, "--/grid--")
	if open == -1 || close == -1 || open > close {
		t.Fatalf("no grid round the products:\n%s", got)
	}
	if at := strings.Index(got, "![]("); at < open || at > close {
		t.Errorf("a product is outside the grid:\n%s", got)
	}
}

func TestAProductLinksToItsOwnPage(t *testing.T) {
	got := renderIndex(t, []*Product{{Title: "A guitar", SKU: "gtr"}})
	if !strings.Contains(got, "[A guitar](product/gtr)") {
		t.Errorf("no link to the product:\n%s", got)
	}
}

func TestThePlaceholderIsAFileThatExists(t *testing.T) {
	// It is load-bearing: without it a product with no picture leaves a
	// cell that does not start with one, and its writing joins the cell
	// before it. A link to a file nothing serves would look like a working
	// grid until somebody added a product without a picture.
	root := t.TempDir()
	dest := filepath.Join(root, "store")
	if err := WriteTemplate(dest); err != nil {
		t.Fatal(err)
	}
	named := strings.TrimPrefix(ProductImagePath("placeholder.png"), AssetsDir+"/")
	if _, err := os.Stat(filepath.Join(dest, AssetsDir, named)); err != nil {
		t.Fatalf("a new store has no placeholder: %v", err)
	}
}

func TestAShopServesItsPictures(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, AssetsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	err := os.WriteFile(filepath.Join(root, AssetsDir, "guitar.jpg"),
		[]byte("pretend jpeg"), 0o600)
	if err != nil {
		t.Fatal(err)
	}
	s := &Store{root: root, log: slog.Disabled}

	res, err := s.handleAsset(t.Context(), [32]byte{},
		&rpc.RMFetchResource{Path: []string{AssetsDir, "guitar.jpg"}})
	if err != nil {
		t.Fatal(err)
	}
	if string(res.Data) != "pretend jpeg" {
		t.Fatalf("got %q", res.Data)
	}
}

func TestAShopWillNotServeAnythingElse(t *testing.T) {
	// The directory is served to anyone who can reach the shop, so a name
	// that walks out of it, hides itself, or is not a picture is refused
	// before anything is opened.
	s := &Store{root: t.TempDir(), log: slog.Disabled}
	for _, bad := range [][]string{
		{AssetsDir, "../products.toml"},
		{AssetsDir, "sub/deep.png"},
		{AssetsDir, ".hidden.png"},
		{AssetsDir, "secrets.txt"},
		{AssetsDir},
		{AssetsDir, "a", "b"},
	} {
		if _, err := s.assetPath(bad); err == nil {
			t.Errorf("%v would have been served", bad)
		}
	}
}

// TestTheShopFrontNamesItselfOnlyWhenAsked covers the setting that replaced a
// line in a template.
//
// "My Shop" was written into index.tmpl, so naming your own shop meant
// editing one -- and a shop whose owner never did would be called My Shop
// for ever.
func TestTheShopFrontNamesItselfOnlyWhenAsked(t *testing.T) {
	named := &Store{indexPath: "/", log: slog.Disabled,
		shopName: "Leeds Records", shopTagline: "Vinyl since 1919"}
	got := renderIndexAs(t, named, []*Product{{Title: "A record", SKU: "r1"}})
	for _, want := range []string{"# Leeds Records", "Vinyl since 1919"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from:\n%s", want, got)
		}
	}

	// Both empty: the front page opens with the products, which is right
	// when the site's own banner already says whose shop this is.
	quiet := renderIndexAs(t, &Store{indexPath: "/", log: slog.Disabled},
		[]*Product{{Title: "A record", SKU: "r1"}})
	if strings.Contains(quiet, "My Shop") {
		t.Errorf("a shop that said nothing is still called My Shop:\n%s", quiet)
	}
	if strings.HasPrefix(strings.TrimSpace(quiet), "#") {
		t.Errorf("a shop that said nothing still has a heading:\n%s", quiet)
	}
}

// TestAPriceIsShownInBothCurrencies covers the two figures a shop can stand
// behind.
func TestAPriceIsShownInBothCurrencies(t *testing.T) {
	s := &Store{indexPath: "/", log: slog.Disabled}
	s.cfg.ExchangeRateProvider = func() float64 { return 25 }
	got := renderIndexAs(t, s, []*Product{{Title: "A record", SKU: "r1",
		Price: 50}})

	if !strings.Contains(got, "$50.00") {
		t.Errorf("no price:\n%s", got)
	}
	if !strings.Contains(got, "2.0000 DCR") {
		t.Errorf("no DCR figure:\n%s", got)
	}
	if !strings.Contains(got, "≈") {
		t.Error("the DCR figure is not marked approximate, and it is: the " +
			"rate moves and the binding amount is struck at checkout")
	}
}

func TestWithNoRateTheShopShowsOnlyThePrice(t *testing.T) {
	// Not "0 DCR", which is a price and a wrong one.
	got := renderIndex(t, []*Product{{Title: "A record", SKU: "r1", Price: 50}})
	if !strings.Contains(got, "$50.00") {
		t.Errorf("no price:\n%s", got)
	}
	if strings.Contains(got, "DCR") {
		t.Errorf("a DCR figure with no rate behind it:\n%s", got)
	}
}
