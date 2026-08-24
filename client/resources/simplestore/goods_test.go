package simplestore

import (
	"os"
	"path/filepath"
	"testing"
)

// goods_test.go covers what a shop is allowed to send.
//
// A product's file used to be a path -- relative to the store, or absolute,
// with nothing checking either -- and when payment landed it was pushed to
// the buyer automatically and unattended. So a name that walked out of the
// store reached whatever it named, and a typo was discovered by the buyer
// receiving the wrong thing.

func TestOnlyAFileInTheGoodsDirectoryCanBeSent(t *testing.T) {
	s := testStore(t)
	for _, bad := range []string{
		"../../.ssh/id_rsa",
		"/etc/passwd",
		"goods/../../secret.txt",
		"goods/sub/deep.md",
		"manual.md",
		"goods/.hidden",
	} {
		if _, err := s.checkGood(bad); err == nil {
			t.Errorf("%q would have been sent", bad)
		}
	}
}

func TestAFileInTheGoodsDirectoryIsFine(t *testing.T) {
	s := testStore(t)
	got, err := s.checkGood("goods/manual.md")
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(s.root, "goods", "manual.md"); got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestNoFileAtAllIsAllowed(t *testing.T) {
	// Most products are not a download.
	s := testStore(t)
	got, err := s.checkGood("")
	if err != nil || got != "" {
		t.Fatalf("got %q, %v", got, err)
	}
}

func TestAProductCannotBeSavedNamingAFileThatIsNotThere(t *testing.T) {
	// The last moment anybody is watching. After this it is sent when
	// payment lands, and a wrong name is discovered by the buyer receiving
	// nothing.
	s := testStore(t)
	err := s.SaveProduct(Product{
		Title: "A guide", SKU: "g1", Price: 1.0,
		SendFilename: "goods/missing.md",
	}, "")
	if err == nil {
		t.Fatal("a product naming a file that is not there was saved")
	}
}

func TestAProductWithItsFileInPlaceSaves(t *testing.T) {
	s := testStore(t)
	recorded, err := s.writeGood("manual.md", []byte("# Manual"))
	if err != nil {
		t.Fatal(err)
	}
	if recorded != "goods/manual.md" {
		t.Fatalf("recorded as %q", recorded)
	}
	err = s.SaveProduct(Product{
		Title: "A guide", SKU: "g1", Price: 1.0, SendFilename: recorded,
	}, "")
	if err != nil {
		t.Fatalf("save: %v", err)
	}
}

func TestWritingAGoodCannotEscapeTheDirectory(t *testing.T) {
	s := testStore(t)
	if _, err := s.writeGood("../escape.md", []byte("x")); err == nil {
		if _, statErr := os.Stat(filepath.Join(s.root, "..", "escape.md")); statErr == nil {
			t.Fatal("a file was written outside the store")
		}
	}
}
