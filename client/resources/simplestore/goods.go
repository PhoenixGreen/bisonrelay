package simplestore

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
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

// sendOrderGoods sends the file for every line of an order that has one, and
// gives back what to tell the buyer.
//
// One path, used by payment landing and by a seller sending again. Two
// copies of this would be two sets of answers to the awkward cases -- a name
// the shop will not send, a file that is not there -- and the awkward cases
// are the whole of it: the happy path is one line.
// Anything that stops a file going out is returned as well as told to the
// buyer. A seller pressing Send and being shown nothing learns only that
// something happened; the reason was going to the log, which is the one
// place they were not looking.
//
// [wait] decides whether to see the sending through before returning.
//
// Payment does not wait: it is a notification arriving, and a file that
// takes a minute to push should not hold that up. A seller pressing Send
// does wait, because they are standing there and the answer they need is
// whether it went -- reporting success and logging the failure somewhere
// they will not look is worse than saying nothing.
func (s *Store) sendOrderGoods(order *Order, wait bool) (string, error) {
	var b strings.Builder
	var failed error

	// An order placed with your own shop can do everything but deliver.
	//
	// Sending a file is a transfer between two clients, and your own
	// identity is not a remote user -- so this send cannot work, and until
	// now it was attempted anyway: the buyer was told "Sending you the file"
	// and the failure went to the log. A seller testing their own shop saw a
	// paid order, a promise, and nothing arriving, with the reason in the
	// one place they were not looking.
	//
	// Checked here rather than only in SendOrderGoods, because payment
	// landing is the path that actually runs in that situation.
	if s.orderHasGoods(order) && s.isSelf(order.User) {
		s.log.Warnf("Order %s/%s is the shop owner's own; its files cannot "+
			"be delivered", order.User.ShortLogID(), order.ID)
		fmt.Fprintf(&b, "\n%s", ErrCannotSendToSelf.Error())
		return b.String(), ErrCannotSendToSelf
	}

	for _, item := range order.Cart.Items {
		if item.Product.SendFilename == "" {
			continue
		}
		name := item.Product.SendFilename

		path, err := s.checkGood(name)
		if err != nil {
			// Saved before the goods directory existed, or edited by hand.
			// Said rather than sent: the alternative is sending whatever
			// that name happens to reach.
			s.log.Errorf("Order %s/%s names a file this shop will not send "+
				"(%v); telling the buyer instead", order.User.ShortLogID(),
				order.ID, err)
			fmt.Fprintf(&b, "\nThe file for %q could not be sent. Ask the "+
				"seller for it.", item.Product.Title)
			if failed == nil {
				failed = fmt.Errorf("%q: %v", item.Product.Title, err)
			}
			continue
		}
		if _, err := os.Stat(path); err != nil {
			// Promising a file and then not sending one is worse than
			// saying so: the buyer has paid and is waiting for something.
			s.log.Errorf("Order %s/%s names %q, which is not there: %v",
				order.User.ShortLogID(), order.ID, name, err)
			fmt.Fprintf(&b, "\nThe file for %q could not be sent. Ask the "+
				"seller for it.", item.Product.Title)
			if failed == nil {
				failed = fmt.Errorf("the file for %q is not in %s/",
					item.Product.Title, GoodsDir)
			}
			continue
		}

		fmt.Fprintf(&b, "\nSending you the file %s included in your order",
			filepath.Base(path))
		attrs := goodAttributes(order, item)
		user, id := order.User, order.ID
		send := func() error {
			err := s.c.SendFileWithAttributes(user, 0, path, attrs, nil)
			if err != nil {
				s.log.Errorf("Unable to send %s for order %s/%s: %v",
					path, user.ShortLogID(), id, err)
			} else {
				s.log.Infof("Sent %s for order %s/%s", path,
					user.ShortLogID(), id)
			}
			return err
		}
		if !wait {
			go func() { _ = send() }()
			continue
		}
		if err := send(); err != nil && failed == nil {
			failed = err
		}
	}
	return b.String(), failed
}

// orderHasGoods is whether anything in this order is delivered as a file.
func (s *Store) orderHasGoods(order *Order) bool {
	for _, item := range order.Cart.Items {
		if item.Product != nil && item.Product.SendFilename != "" {
			return true
		}
	}
	return false
}

// ErrCannotSendToSelf is an order somebody placed with their own shop.
var ErrCannotSendToSelf = errors.New("this order is your own, and a file " +
	"cannot be sent to yourself -- delivery needs a second client")

// isSelf is whether a user is this client.
//
// Nil-safe because a Store without a client is a real state -- it is what
// one looks like in a test, and what one is briefly before it is running --
// and asking a nil client who it is brings the shop down rather than
// answering.
func (s *Store) isSelf(uid clientintf.UserID) bool {
	return s.c != nil && uid == s.c.PublicID()
}

// SendOrderGoods sends an order's files again.
//
// A seller's own action, for when a buyer says nothing arrived. The files
// are sent on payment already; this is the same send, asked for deliberately
// -- which also makes the whole path testable without a payment, since
// paying yourself is not a thing Lightning will do.
func (s *Store) SendOrderGoods(uid clientintf.UserID, oid OrderID) error {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	order, _, err := s.loadOrderLocked(uid, oid)
	if err != nil {
		return err
	}

	// Sending is between two clients: the file goes to a remote user, and
	// your own identity is not one. So an order placed with your own shop
	// can be browsed, carted, placed, answered and marked paid, and the one
	// thing it can never do is deliver -- which is worth saying here rather
	// than letting the transfer fail with "user not found", a sentence
	// about somebody who is standing right there.
	if s.isSelf(uid) {
		return ErrCannotSendToSelf
	}
	said, err := s.sendOrderGoods(order, true)
	if err != nil {
		return err
	}
	if said == "" {
		return fmt.Errorf("nothing in order #%d has a file to send", oid)
	}
	return nil
}

// digitalOnly is whether everything in this order is a file the shop sends by
// itself.
//
// Nothing posted, and every line with a file of its own. An order like that
// is finished the moment the files land: there is no packing, no address and
// nothing for the seller to decide, so asking them to mark it sent is asking
// them to confirm something that has already happened.
//
// A line with neither a file nor an address is not this. That is the third
// kind of delivery -- the seller arranges it in the order's messages -- and
// it genuinely wants them.
func digitalOnly(order *Order) bool {
	if len(order.Cart.Items) == 0 {
		return false
	}
	for _, item := range order.Cart.Items {
		if item.Product == nil || item.Product.Shipping ||
			item.Product.SendFilename == "" {
			return false
		}
	}
	return true
}

// finishDigitalOrder sends a file-only order's goods and marks it done.
//
// Waited on, unlike the send that happens beside a payment notification: the
// point here is the answer. An order marked completed before its file went
// would be a shop telling a buyer they have something they have not been
// sent, and the seller would never hear about it -- the failure went to a log
// nobody was reading.
//
// So a send that fails leaves the order paid, which is where the seller's own
// list picks it up as needing them. That is the honest outcome: something did
// not go, and a person has to look at it.
func (s *Store) finishDigitalOrder(ctx context.Context, uid clientintf.UserID,
	oid OrderID) {

	s.mtx.Lock()
	order, fname, err := s.loadOrderLocked(uid, oid)
	s.mtx.Unlock()
	if err != nil {
		s.log.Warnf("Unable to read order %s/%s to finish it: %v",
			uid.ShortLogID(), oid, err)
		return
	}

	// Outside the lock. Pushing a file is a transfer that can take a minute,
	// and the whole shop would be waiting behind it.
	said, err := s.sendOrderGoods(order, true)
	if err != nil {
		s.log.Errorf("Order %s/%s was paid but its files did not go (%v); "+
			"leaving it for the seller", uid.ShortLogID(), oid, err)
		if s.cfg.StatusChanged != nil {
			s.cfg.StatusChanged(order, said)
		}
		return
	}

	s.mtx.Lock()
	// Read again: the seller may have moved it on in the time the file took.
	order, fname, err = s.loadOrderLocked(uid, oid)
	if err != nil || order.Status != StatusPaid {
		s.mtx.Unlock()
		return
	}
	order.Status = StatusCompleted
	err = jsonfile.Write(fname, order, s.log)
	s.mtx.Unlock()
	if err != nil {
		s.log.Warnf("Unable to write order %s/%s: %v", uid.ShortLogID(), oid, err)
		return
	}

	s.log.Infof("Order %s/%s was paid for and delivered, and is finished",
		uid.ShortLogID(), oid)

	if s.cfg.StatusChanged != nil {
		s.cfg.StatusChanged(order, said+
			"\nThat is everything in this order, so it is complete.")
	}
}
