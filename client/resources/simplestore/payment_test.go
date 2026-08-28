package simplestore

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// payment_test.go covers how an order gets paid for: what the shop offers,
// what it does when the way it offers will not work, and what it must never
// do -- which is take an order it cannot be paid for.

func TestWhatAShopOffers(t *testing.T) {
	for _, c := range []struct {
		pay       PayType
		ln, chain bool
	}{
		{PayTypeLN, true, false},
		{PayTypeOnChain, false, true},
		{PayTypeBoth, true, true},
		{"", false, false},
	} {
		s := &Store{log: slog.Disabled}
		s.cfg.PayType = c.pay
		got := s.payMethods()
		if got.LN != c.ln || got.OnChain != c.chain {
			t.Errorf("%q offers %+v", c.pay, got)
		}
	}

	// A shop that takes neither is a real arrangement -- the seller settles
	// up in chat -- and everything else asks Any() before offering anything.
	if (PayMethods{}).Any() {
		t.Error("a shop offering nothing thinks it offers something")
	}
	if !(PayMethods{LN: true, OnChain: true}).Both() {
		t.Error("a shop taking both has no choice to offer")
	}
}

// TestAnOrderIsNotPlacedWithNoWayToPayIt is the rule the rest of this rests
// on.
//
// Every failure in the old payment section was a log line the code fell
// through: no invoice, no address, nothing said. The order was written, the
// cart was cleared, and the buyer was handed an order they could not pay and
// no way to find out why.
func TestAnOrderIsNotPlacedWithNoWayToPayIt(t *testing.T) {
	// A shop that takes Lightning and has no Lightning to take it with.
	s := &Store{log: slog.Disabled}
	s.cfg.PayType = PayTypeLN

	order := &Order{ID: 3, ExchangeRate: 25, Cart: Cart{Items: []*CartItem{
		{Product: &Product{Title: "A guitar", Price: 20}, Quantity: 1},
	}}}

	pay, err := s.preparePayment(context.Background(), order, "")
	if pay != nil {
		t.Fatalf("prepared %+v for a shop with no way to take it", pay)
	}
	var cannot *cannotTakePayment
	if !asCannot(err, &cannot) {
		t.Fatalf("got %v, want a refusal", err)
	}
	if len(cannot.Says()) == 0 {
		t.Error("a refusal that does not say why")
	}
}

func TestAShopThatTakesNothingSaysSoRatherThanRefusing(t *testing.T) {
	// The seller arranges payment themselves, which is what the shop did
	// before it could raise an invoice at all.
	s := &Store{log: slog.Disabled}
	order := &Order{ID: 3, ExchangeRate: 25}

	pay, err := s.preparePayment(context.Background(), order, "")
	if pay != nil || err != nil {
		t.Fatalf("got %+v, %v; want nothing at all", pay, err)
	}
}

func TestTheRefusalPageSaysWhatHappenedToTheCart(t *testing.T) {
	// The one moment where the buyer has done everything right and the shop
	// has not. What they need to know is that nothing has been taken and
	// their cart is still there.
	s := &Store{log: slog.Disabled}
	res, err := s.cannotPayPage(&cannotTakePayment{
		why: []string{"this shop cannot receive 1.6 DCR over Lightning at the moment"},
	})
	if err != nil {
		t.Fatal(err)
	}
	got := string(res.Data)
	for _, want := range []string{"has not been placed", "still there",
		"cannot receive 1.6 DCR"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from:\n%s", want, got)
		}
	}
	if res.Status != rpc.ResourceStatusOk {
		t.Errorf("status %v: a page that explains is not an error page", res.Status)
	}
}

func TestTheBuyersChoiceIsReadOffTheForm(t *testing.T) {
	for _, c := range []struct {
		data string
		want PayType
	}{
		{`{"method":"ln"}`, PayTypeLN},
		{`{"method":"onchain"}`, PayTypeOnChain},
		{`{"method":"something"}`, ""},
		{`{}`, ""},
		{`not json`, ""},
	} {
		got := wantPayType(&rpc.RMFetchResource{Data: []byte(c.data)})
		if got != c.want {
			t.Errorf("%s gave %q, want %q", c.data, got, c.want)
		}
	}
}

// TestAPaymentInFlightIsNotExpired covers the hour a quote holds for meeting
// a payment that is already on its way.
//
// The hour exists so a quoted amount does not go stale. A transaction in the
// mempool is somebody who paid the quote they were given inside the time they
// were given -- timing that out would take the money and cancel the order.
func TestAPaymentInFlightIsNotExpired(t *testing.T) {
	seen := time.Now()
	order := &Order{
		Status:    StatusPlaced,
		ExpiresTS: time.Now().Add(-time.Hour),
		SeenTS:    &seen,
	}
	if order.Expired() {
		t.Error("an order whose payment is in flight was called lapsed")
	}
	if !order.PaymentSeen() {
		t.Error("a payment that has been seen is not being reported")
	}
	if orderSays(*order) != "Payment seen — waiting for a confirmation" {
		t.Errorf("says %q", orderSays(*order))
	}

	// And nothing to pay: an address beside "we have seen your payment" is an
	// invitation to pay twice.
	order.PayType = PayTypeOnChain
	order.Invoice = "DsAddr"
	if order.PayURI() != "" {
		t.Errorf("still offering %q to pay", order.PayURI())
	}
}

func TestWhatAnOrderSays(t *testing.T) {
	for _, c := range []struct {
		order Order
		want  string
	}{{
		order: Order{Status: StatusPlaced, ExpiresTS: time.Now().Add(time.Hour)},
		want:  "Waiting for payment",
	}, {
		order: Order{Status: StatusPlaced, ExpiresTS: time.Now().Add(-time.Minute)},
		want:  "Waiting for payment — the quoted amount has lapsed",
	}, {
		order: Order{Status: StatusPaid},
		want:  "Paid — the seller is preparing it",
	}, {
		order: Order{Status: StatusShipped},
		want:  "On its way",
	}} {
		if got := orderSays(c.order); got != c.want {
			t.Errorf("got %q, want %q", got, c.want)
		}
	}
}

// asCannot is errors.As without the import dance in every case above.
func asCannot(err error, target **cannotTakePayment) bool {
	if err == nil {
		return false
	}
	c, ok := err.(*cannotTakePayment)
	if ok {
		*target = c
	}
	return ok
}
