package simplestore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
)

// cartedit_test.go covers changing your mind about a cart.
//
// A cart could be added to and emptied, and nothing else. Adding two of
// something by mistake left one way out: throw the whole cart away and put
// every other item back one at a time. That is the point at which somebody
// stops buying and does something else instead, so these two are the only
// part of the shop's presentation work that was really a missing feature.

func cartOf(items ...*CartItem) *Cart { return &Cart{Items: items} }

func line(sku string, qty uint32) *CartItem {
	return &CartItem{Product: &Product{SKU: sku, Price: 10}, Quantity: qty}
}

func cartSKUs(cart *Cart) []string {
	out := make([]string, 0, len(cart.Items))
	for _, item := range cart.Items {
		out = append(out, item.Product.SKU)
	}
	return out
}

func TestRemovingALineTakesThatLineOnly(t *testing.T) {
	cart := cartOf(line("a", 1), line("b", 2), line("c", 3))
	if !removeFromCart(cart, "b", 0) {
		t.Fatal("nothing was removed")
	}
	got := cartSKUs(cart)
	if len(got) != 2 || got[0] != "a" || got[1] != "c" {
		t.Fatalf("got %v", got)
	}
}

func TestRemovingTheLastLineLeavesAnEmptyCart(t *testing.T) {
	cart := cartOf(line("a", 1))
	if !removeFromCart(cart, "a", 0) {
		t.Fatal("nothing was removed")
	}
	if len(cart.Items) != 0 {
		t.Fatalf("got %v", cartSKUs(cart))
	}
}

func TestRemovingSomethingNotInTheCartChangesNothing(t *testing.T) {
	// Says so, rather than writing the cart back untouched: a cart written
	// on every request is a timestamp that moves for no reason.
	cart := cartOf(line("a", 1))
	if removeFromCart(cart, "b", 0) {
		t.Error("removing an item that is not there reported a change")
	}
	if len(cart.Items) != 1 {
		t.Fatalf("got %v", cartSKUs(cart))
	}
}

func TestSettingAQuantitySetsIt(t *testing.T) {
	cart := cartOf(line("a", 1), line("b", 2))
	if !setCartQuantity(cart, "a", 5) {
		t.Fatal("nothing changed")
	}
	if cart.Items[0].Quantity != 5 {
		t.Fatalf("got %d", cart.Items[0].Quantity)
	}
	if cart.Items[1].Quantity != 2 {
		t.Error("the other line changed too")
	}
}

func TestSettingAQuantityToNoughtRemovesTheLine(t *testing.T) {
	// Somebody clearing the box and submitting means they do not want it.
	// A line sitting at nought would be a row that is there and is not.
	cart := cartOf(line("a", 1), line("b", 2))
	if !setCartQuantity(cart, "a", 0) {
		t.Fatal("nothing changed")
	}
	if got := cartSKUs(cart); len(got) != 1 || got[0] != "b" {
		t.Fatalf("got %v", got)
	}
}

func TestSettingAQuantityToWhatItAlreadyIsChangesNothing(t *testing.T) {
	cart := cartOf(line("a", 3))
	if setCartQuantity(cart, "a", 3) {
		t.Error("setting a quantity to itself reported a change")
	}
}

func TestSettingAQuantityOnSomethingNotInTheCartAddsNothing(t *testing.T) {
	// Quantity is for what is in the cart. Adding is what the product page
	// is for, and a cart that could grow from here would let a buyer put
	// something in it without ever seeing its price.
	cart := cartOf(line("a", 1))
	if setCartQuantity(cart, "b", 4) {
		t.Error("a product not in the cart was changed")
	}
	if len(cart.Items) != 1 {
		t.Fatalf("got %v", cartSKUs(cart))
	}
}

// TestAddingToTheCartAnswersWithTheCart covers the page that is no longer
// there.
//
// Every page of this shop is a round trip to somebody else's client, which
// may be slow or off. "Adding To Cart" cost a whole one to say four words
// and then show the cart underneath anyway, so a buyer waited twice to reach
// the same place.
func TestAddingToTheCartAnswersWithTheCart(t *testing.T) {
	if _, err := storeTemplate.ReadFile("template/addtocart.tmpl"); err == nil {
		t.Error("the interstitial is back: adding to a cart should answer " +
			"with the cart, which is what the buyer asks next anyway")
	}
}

var orderUID = clientintf.UserID{0xab}

const orderID = OrderID(1)

// storeWithAnOrder is a shop with one order already placed, which is what
// there has to be before anybody can say anything about it.
func storeWithAnOrder(t *testing.T) *Store {
	t.Helper()
	s := testStore(t)
	order := &Order{ID: orderID, User: orderUID, Status: StatusPlaced}
	fname := s.orderFilename(orderUID, orderID)
	if err := os.MkdirAll(filepath.Dir(fname), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := jsonfile.Write(fname, order, s.log); err != nil {
		t.Fatal(err)
	}
	return s
}

// TestTheBuyerIsToldWhenTheSellerAnswers covers the message that goes with a
// reply.
//
// The seller's answer has nobody watching for it: a buyer is not sitting on
// the order page waiting, so without a message a reply is written into a
// file they never open. A buyer's own comment needs none -- it arrives on
// the seller's client, which is the one running this, and their order list
// marks it.
func TestTheBuyerIsToldWhenTheSellerAnswers(t *testing.T) {
	s := storeWithAnOrder(t)
	var told []string
	s.cfg.CommentAdded = func(_ *Order, msg string) { told = append(told, msg) }

	if _, err := s.AddOrderComment(orderUID, orderID, "Ships tomorrow", true); err != nil {
		t.Fatal(err)
	}
	if len(told) != 1 {
		t.Fatalf("the buyer was told %d times", len(told))
	}
	if !strings.Contains(told[0], "Ships tomorrow") {
		t.Errorf("the message does not carry the answer: %q", told[0])
	}
}

func TestTheBuyersOwnCommentSendsNoMessage(t *testing.T) {
	s := storeWithAnOrder(t)
	var told int
	s.cfg.CommentAdded = func(_ *Order, _ string) { told++ }

	if _, err := s.AddOrderComment(orderUID, orderID, "When does this ship?", false); err != nil {
		t.Fatal(err)
	}
	if told != 0 {
		t.Errorf("the buyer was sent their own comment back")
	}
}

func TestACommentIsRecordedEvenWithNobodyToTell(t *testing.T) {
	// The callback is optional, and a shop whose comment is lost because
	// nothing was listening would be worse than one that cannot send.
	s := storeWithAnOrder(t)
	s.cfg.CommentAdded = nil
	order, err := s.AddOrderComment(orderUID, orderID, "Ships tomorrow", true)
	if err != nil {
		t.Fatal(err)
	}
	if len(order.Comments) != 1 {
		t.Fatalf("got %d comments", len(order.Comments))
	}
}
