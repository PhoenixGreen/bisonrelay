package simplestore

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// goods.go is where a shop keeps what it sells.
//
// A product's file was a path: relative to the store, or absolute, with
// nothing checking either. So a product could name any file on the seller's
// machine -- ../../.ssh/id_rsa reaches as readily as a manual does -- and
// when payment landed it was pushed to the buyer automatically, unattended,
// with nothing asking whether that was really the file meant.
//
// It is a name inside one directory now, the way a shop's pictures are. The
// point is not tidiness: putting a file in the goods directory is a
// deliberate act, and it is the confirmation an automatic send does not have.
//
// What was already saved goes on working. Relative paths have always
// resolved inside the store, so a product saying goods/manual.md is the same
// product either way -- the rule is enforced when a product is saved, so a
// seller is told the next time they touch it rather than having it stop
// working underneath them.

// GoodsDir is the directory a shop's deliverable files live in.
const GoodsDir = "goods"

// GoodPath is what a product records to name a file in there.
func GoodPath(name string) string {
	if strings.TrimSpace(name) == "" {
		return ""
	}
	return GoodsDir + "/" + name
}

// checkGood is whether a product's file is one this shop may send, and where
// it is.
//
// The whole of the guard, in one place, because the two callers want
// different halves of it: saving wants to refuse a bad name, and sending
// wants the path. A name that walks out of the directory, hides itself, or
// is not in the directory at all is refused -- so what can be sent is what
// the seller put where the shop keeps its goods.
func (s *Store) checkGood(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", nil
	}
	rest, ok := strings.CutPrefix(name, GoodsDir+"/")
	if !ok {
		return "", fmt.Errorf("a product's file lives in %s/: %q does not",
			GoodsDir, name)
	}
	if rest != filepath.Base(rest) || strings.HasPrefix(rest, ".") {
		return "", fmt.Errorf("%q is not a plain file name", rest)
	}
	return filepath.Join(s.root, GoodsDir, rest), nil
}

// writeGood puts a file into the shop's goods, and gives back what a product
// records to name it.
func (s *Store) writeGood(name string, data []byte) (string, error) {
	recorded := GoodPath(filepath.Base(name))
	path, err := s.checkGood(recorded)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return "", err
	}
	return recorded, nil
}

// removeGood takes a file out of the shop's goods.
func (s *Store) removeGood(recorded string) error {
	path, err := s.checkGood(recorded)
	if err != nil || path == "" {
		return err
	}
	err = os.Remove(path)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

// PublishGood writes a file into the shop's goods and gives back the name a
// product records for it.
//
// Named for what it is: the same relationship a page has with the document
// it was written from. The document stays in the library and goes on being
// edited; this is the copy the shop sends, and it changes when somebody says
// so.
func (s *Store) PublishGood(name string, data []byte) (string, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()
	return s.writeGood(name, data)
}

// RemoveGood takes a published file out of the shop's goods.
func (s *Store) RemoveGood(recorded string) error {
	s.mtx.Lock()
	defer s.mtx.Unlock()
	return s.removeGood(recorded)
}

// ReadGood is what the shop is currently sending for a product, or nil when
// there is nothing there.
//
// Read back rather than remembered, because the file on disk is the thing
// buyers get: a note saying what was published would be a second record of
// it, and the two would eventually disagree about which is true.
func (s *Store) ReadGood(recorded string) ([]byte, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	path, err := s.checkGood(recorded)
	if err != nil || path == "" {
		return nil, err
	}
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	return data, err
}

// The attributes a file carries when a shop sends it.
//
// They travel with the file and are kept beside it by whoever receives it,
// so a download that is a thing somebody bought can say so rather than being
// another file from somebody. Prefixed, because the bag is shared with
// anything else that ever wants to say something about a file.
//
// There is no version among them on purpose. The metadata already carries a
// hash of the contents, so the same SKU arriving with a different hash is a
// new version of that product -- a version field beside it would be a second
// answer to the same question, and the two would drift.
const (
	AttrOrderID      = "simplestore.order"
	AttrProductSKU   = "simplestore.sku"
	AttrProductTitle = "simplestore.product"
)

// goodAttributes is what to send with the file for one line of an order.
func goodAttributes(order *Order, item *CartItem) map[string]string {
	return map[string]string{
		AttrOrderID:      order.ID.String(),
		AttrProductSKU:   item.Product.SKU,
		AttrProductTitle: item.Product.Title,
	}
}
