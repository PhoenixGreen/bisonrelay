package simplestore

import (
	"os"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"path/filepath"
	"strings"
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

// TestASentGoodSaysWhereItCameFrom covers what travels with a file a shop
// sends.
//
// Without it a bought file is another file from somebody: the buyer's client
// keeps the sender and the name and nothing else, so there is no way to
// gather what somebody has bought, or to notice that one of them has been
// sent again.
func TestASentGoodSaysWhereItCameFrom(t *testing.T) {
	order := &Order{ID: OrderID(7)}
	item := &CartItem{Product: &Product{SKU: "g1", Title: "A guide"}}

	attrs := goodAttributes(order, item)
	if attrs[AttrProductSKU] != "g1" {
		t.Errorf("SKU is %q", attrs[AttrProductSKU])
	}
	if attrs[AttrProductTitle] != "A guide" {
		t.Errorf("title is %q", attrs[AttrProductTitle])
	}
	if attrs[AttrOrderID] == "" {
		t.Error("the order is not named")
	}
}

func TestTheAttributesAreNamespaced(t *testing.T) {
	// The bag is shared with anything else that wants to say something
	// about a file, so a bare "order" or "sku" would be a collision waiting
	// to happen.
	for _, key := range []string{AttrOrderID, AttrProductSKU, AttrProductTitle} {
		if !strings.HasPrefix(key, "simplestore.") {
			t.Errorf("%q is not namespaced", key)
		}
	}
}

func TestThereIsNoVersionAttribute(t *testing.T) {
	// The metadata already carries a hash of the contents, so the same SKU
	// arriving with a different hash is a new version of that product. A
	// version field beside it would be a second answer to one question, and
	// the two would drift.
	attrs := goodAttributes(&Order{ID: OrderID(1)},
		&CartItem{Product: &Product{SKU: "g1"}})
	for key := range attrs {
		if strings.Contains(strings.ToLower(key), "version") {
			t.Errorf("%q duplicates what the file hash already says", key)
		}
	}
}

// TestNoShippedProductPromisesAFileThatIsNotThere covers the demo catalogue.
//
// One of them said sendfilename = "test.png" long after test.png stopped
// being shipped, so every shop restored from the defaults had a product
// that could not send what it promised -- and the seller found out from a
// buyer, because the refusal went to a log.
func TestNoShippedProductPromisesAFileThatIsNotThere(t *testing.T) {
	entries, err := storeTemplate.ReadDir("template/products")
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		body, err := storeTemplate.ReadFile("template/products/" + e.Name())
		if err != nil {
			t.Fatal(err)
		}
		for _, line := range strings.Split(string(body), "\n") {
			if !strings.HasPrefix(strings.TrimSpace(line), "sendfilename") {
				continue
			}
			named := strings.Trim(strings.SplitN(line, "=", 2)[1], ` "`)
			if named == "" {
				continue
			}
			rest, ok := strings.CutPrefix(named, GoodsDir+"/")
			if !ok {
				t.Errorf("%s promises %q, which is not in %s/",
					e.Name(), named, GoodsDir)
				continue
			}
			if _, err := storeTemplate.ReadFile(
				"template/" + GoodsDir + "/" + rest); err != nil {
				t.Errorf("%s promises %q, which is not shipped",
					e.Name(), named)
			}
		}
	}
}

// TestAnOrderWithYourselfCannotDeliver covers the shop a seller orders from
// themselves.
//
// Everything else about such an order works -- browsing, the cart, placing
// it, the messages, the status -- so it is a good way to try the shop. The
// one thing it cannot do is deliver, because sending is between two clients
// and your own identity is not a remote user. Better said here than left to
// surface as "user not found", which is a sentence about somebody who is
// standing right there.
func TestAnOrderWithYourselfCannotDeliver(t *testing.T) {
	if !strings.Contains(ErrCannotSendToSelf.Error(), "second client") {
		t.Errorf("the reason a seller needs is not in %q", ErrCannotSendToSelf)
	}
	// Said in the seller's terms rather than the transfer's. "user not
	// found" is a sentence about somebody who is standing right there.
	if strings.Contains(ErrCannotSendToSelf.Error(), "not found") {
		t.Error("the message reads as somebody being missing")
	}
}

func TestAShopWithNoClientDoesNotFallOver(t *testing.T) {
	// A Store without a client is a real state: it is what one looks like
	// in a test, and what one is briefly before it is running. Asking a nil
	// client who it is brought the shop down rather than answering.
	s := testStore(t)
	if s.isSelf(clientintf.UserID{}) {
		t.Error("a shop with no client thinks it is everybody")
	}
}
