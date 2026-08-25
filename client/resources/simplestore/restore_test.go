package simplestore

import (
	"github.com/decred/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// restore_test.go covers putting the shipped templates back.
//
// A store's templates are copied in once, when the store is made, and are
// the seller's own from then on -- so a template shipped or changed later
// never reaches a store that already exists. A shop can be running a front
// page written for a version of the app from a year ago with no sign that
// anything newer exists, which is exactly what happened when the shop front
// became a grid.

func TestRestoreReachesAStoreThatAlreadyExists(t *testing.T) {
	root := t.TempDir()
	// A store made before any of this, with its own front page.
	err := os.WriteFile(filepath.Join(root, "index.tmpl"),
		[]byte("# My Simple Store\n\nSee all the stuff I have.\n"), 0o600)
	if err != nil {
		t.Fatal(err)
	}
	// WriteTemplate refuses, which is what leaves a shop on old templates.
	if err := WriteTemplate(root); !os.IsExist(err) {
		t.Fatalf("WriteTemplate did not refuse a store with something in "+
			"it: %v", err)
	}

	if err := RestoreTemplates(root); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(root, "index.tmpl"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "--grid[") {
		t.Fatalf("the shop front is still the old one:\n%s", got)
	}
}

func TestRestoreBringsWhatTheStoreNeverHad(t *testing.T) {
	// A store made before products had pictures has no placeholder, and the
	// grid needs one: a cell that does not begin with a picture is not a
	// cell.
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "index.tmpl"),
		[]byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}

	if err := RestoreTemplates(root); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, AssetsDir, "placeholder.png")); err != nil {
		t.Fatalf("no placeholder after a restore: %v", err)
	}
}

func TestRestoreLeavesTheShopsOwnRecordsAlone(t *testing.T) {
	// products/ and carts/ are what the shop sells and who is buying it.
	// Nothing about restoring a template should touch either.
	root := t.TempDir()
	for _, dir := range []string{"products", "carts"} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
			t.Fatal(err)
		}
		// Named as the shipped files are, which is the whole point: a
		// name of its own would be left alone by a restore that copies
		// the template directory over wholesale, and this passed while
		// exactly that was happening.
		for _, name := range []string{"mine.toml", "first-type.toml",
			"second-type.toml"} {
			err := os.WriteFile(filepath.Join(root, dir, name),
				[]byte("kept"), 0o600)
			if err != nil {
				t.Fatal(err)
			}
		}
	}

	if err := RestoreTemplates(root); err != nil {
		t.Fatal(err)
	}
	for _, dir := range []string{"products", "carts"} {
		for _, name := range []string{"mine.toml", "first-type.toml",
			"second-type.toml"} {
			got, err := os.ReadFile(filepath.Join(root, dir, name))
			if err != nil || string(got) != "kept" {
				t.Errorf("%s/%s is %q, %v", dir, name, got, err)
			}
		}
	}
}

func TestRestoreTwiceIsNotAProblem(t *testing.T) {
	root := t.TempDir()
	for range 2 {
		if err := RestoreTemplates(root); err != nil {
			t.Fatal(err)
		}
	}
}

// TestANewShopHasNothingForSale covers what a shop opens with.
//
// The templates ship with example products, and they were on sale: no
// disabled flag, and a price of $659.99. So a seller set a shop up, a
// contact browsed it, and could place a real order for "First product" --
// a thing that does not exist, which the seller then cannot send and may
// already have been paid for.
//
// They stay in the file, because a worked example of the format is worth
// having. They are simply not for sale.
func TestANewShopHasNothingForSale(t *testing.T) {
	root := t.TempDir()
	if err := WriteTemplate(root); err != nil {
		t.Fatal(err)
	}

	s := &Store{root: root, log: slog.Disabled, tmpl: nil,
		products: map[string]*Product{}}
	if err := s.reloadStore(); err != nil {
		t.Fatal(err)
	}
	if len(s.products) != 0 {
		for sku, p := range s.products {
			t.Errorf("a new shop is selling %q (%s) at %v",
				p.Title, sku, p.Price)
		}
	}
}

func TestTheExampleProductsAreStillThereToRead(t *testing.T) {
	// Disabled, not deleted: somebody writing their first product file
	// needs to see what one looks like.
	root := t.TempDir()
	if err := WriteTemplate(root); err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(root, productsDir, "first-type.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "First product") {
		t.Error("the example products are gone from the file too")
	}
}

// TestATemplateThatWillNotRenderIsRefused covers editing a shop's pages.
//
// A shop serves these to everybody who visits, and a template with a typo in
// it takes that page down for all of them. The moment to find out is while
// the person who wrote it is still looking at it, not when somebody cannot
// buy anything.
func TestATemplateThatWillNotRenderIsRefused(t *testing.T) {
	s := testStore(t)
	if err := os.WriteFile(filepath.Join(s.root, "index.tmpl"),
		[]byte("# Shop\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	err := s.WriteTemplateFile("index.tmpl", "# Shop\n{{range .Products}}\n")
	if err == nil {
		t.Fatal("a template with no end was saved")
	}

	// And the old one is still there: a refused save must not take the
	// working page with it.
	got, readErr := os.ReadFile(filepath.Join(s.root, "index.tmpl"))
	if readErr != nil || string(got) != "# Shop\n" {
		t.Fatalf("the page was damaged: %q, %v", got, readErr)
	}
}

func TestOnlyAShopsOwnPagesCanBeEdited(t *testing.T) {
	s := testStore(t)
	for _, name := range []string{
		"../../.ssh/id_rsa", "products/first-type.toml", "index.md",
		".hidden.tmpl", "",
	} {
		if _, err := s.templatePath(name); err == nil {
			t.Errorf("%q was accepted as a page", name)
		}
	}
	if _, err := s.templatePath("index.tmpl"); err != nil {
		t.Errorf("index.tmpl was refused: %v", err)
	}
}

func TestAListingSaysWhichPagesAreShipped(t *testing.T) {
	// Which decides whether restoring would put something back over it.
	s := testStore(t)
	for _, name := range []string{"index.tmpl", "mine.tmpl"} {
		if err := os.WriteFile(filepath.Join(s.root, name),
			[]byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.ListTemplates()
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]StoreTemplate{}
	for _, tm := range got {
		byName[tm.Name] = tm
	}
	if !byName["index.tmpl"].Shipped {
		t.Error("index.tmpl is shipped and does not say so")
	}
	if byName["mine.tmpl"].Shipped {
		t.Error("mine.tmpl is the seller's own and claims to be shipped")
	}
}
