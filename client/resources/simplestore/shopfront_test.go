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
	t.Helper()
	s := &Store{indexPath: "/", log: slog.Disabled}
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
	if !strings.Contains(got, "![](assets/guitar.jpg)") {
		t.Errorf("the product's own picture is missing:\n%s", got)
	}
	if !strings.Contains(got, "![](assets/placeholder.png)") {
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
