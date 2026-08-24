package simplestore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/decred/slog"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, productsDir), 0o700); err != nil {
		t.Fatal(err)
	}
	return &Store{root: root, log: slog.Disabled}
}

func skus(prods []ManagedProduct) map[string]ManagedProduct {
	res := make(map[string]ManagedProduct, len(prods))
	for _, p := range prods {
		res[p.SKU] = p
	}
	return res
}

func TestSaveProductRoundTrip(t *testing.T) {
	s := testStore(t)

	prods, err := s.ListManagedProducts()
	if err != nil {
		t.Fatal(err)
	}
	if len(prods) != 0 {
		t.Fatalf("got %d products, want 0", len(prods))
	}

	err = s.SaveProduct(Product{
		Title:       "A guitar solo",
		SKU:         "solo-1",
		Description: "An mp3",
		Price:       0.99,
		Tags:        []string{"music"},
	}, "")
	if err != nil {
		t.Fatal(err)
	}

	prods, err = s.ListManagedProducts()
	if err != nil {
		t.Fatal(err)
	}
	got := skus(prods)
	if len(got) != 1 {
		t.Fatalf("got %d products, want 1", len(got))
	}
	if got["solo-1"].Price != 0.99 || got["solo-1"].File != "solo-1.toml" {
		t.Fatalf("got %+v", got["solo-1"])
	}

	// Editing in place keeps it in the same file.
	p := got["solo-1"].Product
	p.Price = 1.99
	if err := s.SaveProduct(p, got["solo-1"].File); err != nil {
		t.Fatal(err)
	}
	prods, _ = s.ListManagedProducts()
	if len(prods) != 1 || prods[0].Price != 1.99 {
		t.Fatalf("got %+v", prods)
	}
}

// TestSaveProductMovesRatherThanDuplicates covers the failure that would take
// the whole store down: a SKU defined in two files makes reloadStore refuse to
// load anything at all.
func TestSaveProductMovesRatherThanDuplicates(t *testing.T) {
	s := testStore(t)

	p := Product{Title: "Thing", SKU: "sku-1", Price: 1}
	if err := s.SaveProduct(p, "first.toml"); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveProduct(p, "second.toml"); err != nil {
		t.Fatal(err)
	}

	prods, err := s.ListManagedProducts()
	if err != nil {
		t.Fatal(err)
	}
	if len(prods) != 1 {
		t.Fatalf("got %d products, want 1: %+v", len(prods), prods)
	}
	if prods[0].File != "second.toml" {
		t.Fatalf("product stayed in %q", prods[0].File)
	}

	// The emptied file is gone, not left behind as an empty catalogue.
	if _, err := os.Stat(filepath.Join(s.root, productsDir, "first.toml")); !os.IsNotExist(err) {
		t.Errorf("first.toml still exists")
	}
}

func TestSaveProductRejectsBadInput(t *testing.T) {
	s := testStore(t)

	for name, p := range map[string]Product{
		"no sku":         {Title: "Thing", Price: 1},
		"blank sku":      {Title: "Thing", SKU: "   ", Price: 1},
		"no title":       {SKU: "sku-1", Price: 1},
		"negative price": {Title: "Thing", SKU: "sku-1", Price: -1},
	} {
		if err := s.SaveProduct(p, ""); err == nil {
			t.Errorf("%s was accepted", name)
		}
	}

	// A file name that walks out of the products directory must not be
	// writable: the store's directory is served to whoever asks.
	good := Product{Title: "Thing", SKU: "sku-1", Price: 1}
	for _, file := range []string{"../escape.toml", "sub/x.toml", ".hidden.toml", "notes.md"} {
		if err := s.SaveProduct(good, file); err == nil {
			t.Errorf("file %q was accepted", file)
		}
	}
}

func TestDeleteProduct(t *testing.T) {
	s := testStore(t)

	if err := s.SaveProduct(Product{Title: "A", SKU: "a", Price: 1}, "shared.toml"); err != nil {
		t.Fatal(err)
	}
	if err := s.SaveProduct(Product{Title: "B", SKU: "b", Price: 2}, "shared.toml"); err != nil {
		t.Fatal(err)
	}

	if err := s.DeleteProduct("a"); err != nil {
		t.Fatal(err)
	}

	prods, err := s.ListManagedProducts()
	if err != nil {
		t.Fatal(err)
	}
	// Deleting one product out of a shared file leaves the other alone.
	if len(prods) != 1 || prods[0].SKU != "b" {
		t.Fatalf("got %+v", prods)
	}

	// Deleting something that is not there is not an error.
	if err := s.DeleteProduct("nope"); err != nil {
		t.Fatal(err)
	}
}

func TestValidOrderStatus(t *testing.T) {
	for _, s := range []OrderStatus{StatusPlaced, StatusPaid, StatusShipped,
		StatusCompleted, StatusCanceled} {
		if !ValidOrderStatus(s) {
			t.Errorf("%q rejected", s)
		}
	}
	// An unknown status would be written to the order and shown to the
	// buyer as-is.
	for _, s := range []OrderStatus{"", "shipped ", "deleted", "PAID"} {
		if ValidOrderStatus(s) {
			t.Errorf("%q accepted", s)
		}
	}
}

// TestASKUAPageCannotLinkToIsRefused covers the identifier a shop links by.
//
// A shop writes [Title](product/SKU), and a Markdown link stops at the first
// space. A SKU of "this is a test" is written, loaded and served perfectly,
// and the shop front then shows the raw text of the link instead of the
// product -- because the link ended at "this".
func TestASKUAPageCannotLinkToIsRefused(t *testing.T) {
	s := testStore(t)
	for _, bad := range []string{
		"this is a test",
		"a(b)",
		"a/b",
		`say "hi"`,
		"a\tb",
	} {
		err := s.SaveProduct(Product{Title: "T", SKU: bad, Price: 1}, "")
		if err == nil {
			t.Errorf("SKU %q was accepted", bad)
		}
	}
}

func TestAnOrdinarySKUIsStillAccepted(t *testing.T) {
	// The guard is easy to write too widely, and a shop that cannot hold
	// SKU-001 is worse than one that can hold a SKU with a space in it.
	s := testStore(t)
	for _, ok := range []string{"1209391282", "SKU-001", "a_b.c", "Widget2"} {
		if err := s.SaveProduct(Product{Title: "T", SKU: ok, Price: 1}, ""); err != nil {
			t.Errorf("SKU %q was refused: %v", ok, err)
		}
	}
}

// TestADuplicateSKUCostsOneProductNotTheShop covers a catalogue with the same
// SKU in two files.
//
// It used to refuse the whole catalogue, which takes every product off the
// shop front at once -- and silently, because the seller's own product list
// reads the files directly and goes on showing all of them. A healthy list
// beside an empty shop is the hardest possible thing to work out from the
// outside, and it is what a seller actually got.
func TestADuplicateSKUCostsOneProductNotTheShop(t *testing.T) {
	s := testStore(t)
	write := func(file, body string) {
		t.Helper()
		path := filepath.Join(s.root, productsDir, file)
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	write("a.toml", "[[products]]\ntitle = \"Kept\"\nsku = \"dup\"\nprice = 1.0\n")
	write("b.toml", "[[products]]\ntitle = \"Ignored\"\nsku = \"dup\"\nprice = 2.0\n"+
		"\n[[products]]\ntitle = \"Also kept\"\nsku = \"other\"\nprice = 3.0\n")

	if err := s.reloadStore(); err != nil {
		t.Fatalf("a duplicate SKU stopped the catalogue loading: %v", err)
	}
	if len(s.products) != 2 {
		t.Fatalf("catalogue holds %d products, want 2", len(s.products))
	}
	if s.products["dup"].Title != "Kept" {
		t.Errorf("the second claim on the SKU won: %q", s.products["dup"].Title)
	}
	if _, ok := s.products["other"]; !ok {
		t.Error("a product sharing a file with a duplicate was lost with it")
	}
}

// TestASellersOwnOrderIsNamed covers an order somebody placed with their own
// shop.
//
// There is no remote user to ask for a nick, so the seller's own orders
// showed a bare sixty-four character identity -- the same one on every row,
// which reads as every order being the same order rather than as four
// orders from the same person.
func TestASellersOwnOrderIsNamed(t *testing.T) {
	// handlePlaceOrder already calls this case "(local client)"; the order
	// book has to know it too, or the two disagree about the same order.
	if !strings.Contains(sellerOwnOrderNick, "you") {
		t.Fatalf("a seller's own order is called %q", sellerOwnOrderNick)
	}
}
