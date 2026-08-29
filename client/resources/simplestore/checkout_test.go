package simplestore

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/rpc"
)

// checkout_test.go walks the way from a full cart to a placed order.
//
// The thing worth testing here is not any one page: it is that an answer
// given on one step is still there on the next. The checkout keeps what the
// buyer has said on their cart precisely so that stepping back to change one
// thing does not cost the others, and every way that could break -- a reload,
// a second post, a change of mind about how to pay -- looks fine from inside
// a single handler.

// shopTaking is a store that takes the given kinds of payment.
// onCheckout and onReview are how a page says which step it is: the trail
// block at the top marks the current one, and it is the same marker whatever
// the page happens to be titled.
const (
	onCheckout = "--steps[on=checkout]--"
	onReview   = "--steps[on=review]--"
)

func shopTaking(t *testing.T, pay PayType) *Store {
	t.Helper()
	s := storeForHandlers(t)
	s.cfg.PayType = pay
	return s
}

// shipping makes the store's one product something that has to be posted.
func shipping(s *Store) { s.products["r1"].Shipping = true }

func fullCart(t *testing.T, s *Store, uid clientintf.UserID) {
	t.Helper()
	answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid, addToCartRequest("r1", 1))
	})
}

func setCheckout(t *testing.T, s *Store, uid clientintf.UserID,
	fields map[string]any) string {

	t.Helper()
	data, _ := json.Marshal(fields)
	res := answers(t, "setCheckout", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleSetCheckout(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"setCheckout"}, Data: data})
	})
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("setCheckout: status %d: %s", res.Status, res.Data)
	}
	return string(res.Data)
}

func savedCart(t *testing.T, s *Store, uid clientintf.UserID) *Cart {
	t.Helper()
	s.mtx.Lock()
	defer s.mtx.Unlock()
	cart, _, err := s.loadCart(uid)
	if err != nil {
		t.Fatal(err)
	}
	return cart
}

// TestTheCartSendsYouToTheCheckout is the relabelled button: the cart no
// longer places anything.
func TestTheCartSendsYouToTheCheckout(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "cart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleCart(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"cart"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "/checkout") {
		t.Errorf("the cart does not offer the checkout:\n%s", page)
	}
	if strings.Contains(page, "/placeOrder") {
		t.Errorf("the cart still places orders itself:\n%s", page)
	}
}

// TestChoosingHowToPayStaysOnTheCheckout is the difference between the two
// things this route does. Pressing a payment card must not count as
// finishing the step -- if it did, a buyer with a delivery address still to
// give would be carried past the page that asks for it.
func TestChoosingHowToPayStaysOnTheCheckout(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	page := setCheckout(t, s, uid, map[string]any{
		"doing": "method", "method": "onchain",
	})
	if !strings.Contains(page, onCheckout) {
		t.Fatalf("choosing a method left the checkout:\n%s", page)
	}
	if got := savedCart(t, s, uid).Checkout.Method; got != PayTypeOnChain {
		t.Errorf("the choice was not kept: got %q", got)
	}
}

// TestTheCheckoutSaysWhatIsMissing is the old bare "incomplete shipping
// address" status, which arrived after the order with no page and no way
// back.
func TestTheCheckoutSaysWhatIsMissing(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	page := setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "name": "Ada",
	})
	if !strings.Contains(page, onCheckout) {
		t.Fatalf("an incomplete address moved on:\n%s", page)
	}
	for _, want := range []string{"an address", "a city", "a postal code"} {
		if !strings.Contains(page, want) {
			t.Errorf("the page does not say it needs %s:\n%s", want, page)
		}
	}
}

// TestAnAnsweredCheckoutReachesTheReview is the whole step done.
func TestAnAnsweredCheckoutReachesTheReview(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{"doing": "method", "method": "ln"})
	page := setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "method": "ln",
		"name": "Ada", "address1": "1 Long Road", "city": "Kent",
		"state": "Kent", "postalCode": "CT1 1AA",
	})
	if !strings.Contains(page, onReview) {
		t.Fatalf("a fully answered checkout did not reach the review:\n%s", page)
	}
	if !strings.Contains(page, "1 Long Road") {
		t.Errorf("the review does not show where it is going:\n%s", page)
	}
	if !strings.Contains(page, "Lightning") {
		t.Errorf("the review does not say how it is being paid:\n%s", page)
	}
	if !strings.Contains(page, "/placeOrder") {
		t.Errorf("the review has no way to place the order:\n%s", page)
	}
}

// TestGoingBackKeepsWhatWasAnswered is the reason any of this is on the cart
// rather than in hidden fields.
func TestGoingBackKeepsWhatWasAnswered(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{"doing": "method", "method": "onchain"})
	setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "method": "onchain", "refund_addr": "DsRefund",
		"name": "Ada", "address1": "1 Long Road", "city": "Kent",
		"state": "Kent", "postalCode": "CT1 1AA",
	})

	res := answers(t, "checkout", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleCheckout(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"checkout"}})
	})
	page := string(res.Data)
	for _, want := range []string{"1 Long Road", "CT1 1AA"} {
		if !strings.Contains(page, want) {
			t.Errorf("coming back to the checkout lost %q:\n%s", want, page)
		}
	}
	if got := savedCart(t, s, uid).Checkout.RefundAddr; got != "DsRefund" {
		t.Errorf("coming back to the checkout lost the refund address: %q", got)
	}
}

// TestGoingBackDoesNotWipeTheRefundAddress is why the form's refund field is
// a pointer.
//
// It is asked for on the review page, so the checkout's own form does not
// send it. Read as a plain string, a buyer who gave a refund address and then
// stepped back to fix a typo in their postcode would have it quietly erased
// by the page that never asked about it.
func TestGoingBackDoesNotWipeTheRefundAddress(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{
		"doing": "method", "method": "onchain", "refund_addr": "DsRefund",
	})
	// The checkout's continue form, exactly as it is written: no refund
	// field at all.
	setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "method": "onchain",
		"name": "Ada", "address1": "1 Long Road", "city": "Kent",
		"state": "Kent", "postalCode": "CT1 1AA",
	})
	if got := savedCart(t, s, uid).Checkout.RefundAddr; got != "DsRefund" {
		t.Errorf("the checkout wiped a refund address it never asked for: %q", got)
	}
}

// TestTheReviewDoesNotAskForARefundAddress.
//
// It has moved again, and for the same reason it left the checkout: it read
// as "this might go wrong" while the buyer was still deciding. Between the
// review and the payment there is nothing to refund yet, so it now lives on
// the order once the money has actually arrived -- see handleSetRefund.
func TestTheReviewDoesNotAskForARefundAddress(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{"doing": "method", "method": "onchain"})
	page := setCheckout(t, s, uid, map[string]any{"doing": "continue", "method": "onchain"})
	if strings.Contains(page, "refund_addr") {
		t.Errorf("the review still asks for a refund address:\n%s", page)
	}
}

// TestPlacingAnOrderIsOnePress: the review page had a confirmation dialog on
// it, which asked the buyer to agree to the amount a second time on a page
// whose whole purpose is checking the amount.
func TestPlacingAnOrderIsOnePress(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, `value="/placeOrder"`) {
		t.Fatalf("the review has no way to place the order:\n%s", page)
	}
	if strings.Contains(page, "confirm=") {
		t.Errorf("placing the order still asks twice:\n%s", page)
	}
}

// TestTheReviewSaysWhereItIsGoing is the panel that used to read "Nothing in
// this order is posted, so there is nowhere for it to go" -- true, and an
// answer to a question nobody asked. What a buyer wants to know is where the
// thing they just bought turns up.
func TestTheReviewSaysWhereItIsGoing(t *testing.T) {
	tests := []struct {
		name    string
		product func(*Product)
		want    string
	}{{
		name:    "posted",
		product: func(p *Product) { p.Shipping = true },
		want:    "Posted to",
	}, {
		name:    "sent as a file",
		product: func(p *Product) { p.SendFilename = "goods/guide.md" },
		want:    "Delivered here",
	}, {
		name:    "arranged with the seller",
		product: func(p *Product) {},
		want:    "How you get it",
	}}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := shopTaking(t, PayTypeLN)
			tc.product(s.products["r1"])
			uid := clientintf.UserID{}
			fullCart(t, s, uid)

			if s.products["r1"].Shipping {
				setCheckout(t, s, uid, map[string]any{
					"doing": "continue", "method": "ln",
					"name": "Ada", "address1": "1 Long Road", "city": "Kent",
					"state": "Kent", "postalCode": "CT1 1AA",
				})
			}

			res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
				return s.handleReview(context.Background(), uid,
					&rpc.RMFetchResource{Path: []string{"review"}})
			})
			page := string(res.Data)
			if !strings.Contains(page, tc.want) {
				t.Errorf("the review does not say %q:\n%s", tc.want, page)
			}
		})
	}
}

// TestTheReviewSaysWhatThePriceIsGoodFor is the surprise this removes: the
// one-hour quote used only to be mentioned after the order existed, so
// somebody who sat on the review page for ninety minutes found out late.
func TestTheReviewSaysWhatThePriceIsGoodFor(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	s.cfg.ExchangeRateProvider = func() float64 { return 20 }
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "holds for 25 minutes") {
		t.Errorf("the review does not say how long the price is good for:\n%s", page)
	}
}

// TestTheOnChainCardSaysHowLongItTakes: "a block or two" is honest and is not
// a number, and a buyer choosing between two ways to pay is choosing on time.
func TestTheOnChainCardSaysHowLongItTakes(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "checkout", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleCheckout(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"checkout"}})
	})
	page := string(res.Data)
	for _, want := range []string{"one confirmation", "five minutes"} {
		if !strings.Contains(page, want) {
			t.Errorf("the on-chain card does not say %q:\n%s", want, page)
		}
	}
}

// TestALightningOrderKeepsNoRefundAddress: an address kept against a
// Lightning order is a promise the shop cannot keep, since there is nowhere
// for a Lightning payment to go back to.
func TestALightningOrderKeepsNoRefundAddress(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{
		"doing": "method", "method": "onchain", "refund_addr": "DsRefund",
	})
	if got := savedCart(t, s, uid).Checkout.RefundAddr; got != "DsRefund" {
		t.Fatalf("the refund address was not kept: %q", got)
	}

	setCheckout(t, s, uid, map[string]any{
		"doing": "method", "method": "ln", "refund_addr": "DsRefund",
	})
	if got := savedCart(t, s, uid).Checkout.RefundAddr; got != "" {
		t.Errorf("a Lightning order kept a refund address: %q", got)
	}
}

// TestTheReviewNeedsAChoice: a shop offering both must not be able to reach
// the review with no way to pay decided.
func TestTheReviewNeedsAChoice(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "Choose how you would like to pay") {
		t.Fatalf("the review was reached with no way to pay chosen:\n%s", page)
	}
}

// TestOneWayToPayIsNotAQuestion: a shop that takes one kind of payment goes
// straight through, with no card to press.
func TestOneWayToPayIsNotAQuestion(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, onReview) {
		t.Fatalf("a one-method shop was asked to choose:\n%s", page)
	}
	if !strings.Contains(page, "Lightning") {
		t.Errorf("the review does not say how it is being paid:\n%s", page)
	}
}

// TestAnEmptyCartIsAPageNotAnError: reachable by going back a step after
// emptying the cart, which is not an error worth a status code.
func TestAnEmptyCartIsAPageNotAnError(t *testing.T) {
	s := shopTaking(t, PayTypeBoth)
	uid := clientintf.UserID{}

	for _, step := range []struct {
		name string
		call func() (*rpc.RMFetchResourceReply, error)
	}{
		{"checkout", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleCheckout(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"checkout"}})
		}},
		{"review", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleReview(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"review"}})
		}},
	} {
		res := answers(t, step.name, step.call)
		if res.Status != rpc.ResourceStatusOk {
			t.Errorf("%s: status %d", step.name, res.Status)
		}
		if !strings.Contains(string(res.Data), "empty") {
			t.Errorf("%s does not say the cart is empty:\n%s", step.name, res.Data)
		}
	}
}

// TestEveryStepSaysWhereItIs is the trail across the top. It is the answer to
// "how much more of this is there", and a step that does not draw it is a
// step where the buyer cannot tell.
func TestEveryStepSaysWhereItIs(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	for _, step := range []struct {
		name string
		call func() (*rpc.RMFetchResourceReply, error)
	}{
		{"cart", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleCart(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"cart"}})
		}},
		{"checkout", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleCheckout(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"checkout"}})
		}},
		{"review", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleReview(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"review"}})
		}},
	} {
		page := string(answers(t, step.name, step.call).Data)
		for _, want := range []string{
			"[Cart](/cart) | [Checkout](/checkout) | [Review](/review) | Pay",
		} {
			if !strings.Contains(page, want) {
				t.Errorf("%s does not draw %q in its trail:\n%s",
					step.name, want, page)
			}
		}
	}
}

// TestTheRefundAddressReachesTheOrder is the last hop: the field is typed on
// the review page, in the form that places the order, so it arrives on that
// request rather than on the cart.
func TestTheRefundAddressReachesTheOrder(t *testing.T) {
	typed := func(v string) *rpc.RMFetchResource {
		data, _ := json.Marshal(map[string]any{"refund_addr": v})
		return &rpc.RMFetchResource{Data: data}
	}
	none := &rpc.RMFetchResource{Data: []byte(`{}`)}

	tests := []struct {
		name    string
		cart    Cart
		request *rpc.RMFetchResource
		want    string
	}{{
		name:    "typed on the review page",
		cart:    Cart{Checkout: Checkout{Method: PayTypeOnChain}},
		request: typed(" DsTyped "),
		want:    "DsTyped",
	}, {
		name:    "kept from an earlier pass",
		cart:    Cart{Checkout: Checkout{Method: PayTypeOnChain, RefundAddr: "DsEarlier"}},
		request: none,
		want:    "DsEarlier",
	}, {
		name:    "the review wins over the cart",
		cart:    Cart{Checkout: Checkout{Method: PayTypeOnChain, RefundAddr: "DsEarlier"}},
		request: typed("DsChanged"),
		want:    "DsChanged",
	}, {
		name:    "cleared on the review page",
		cart:    Cart{Checkout: Checkout{Method: PayTypeOnChain, RefundAddr: "DsEarlier"}},
		request: typed(""),
		want:    "",
	}, {
		// Lightning has nowhere to send one, so an address stored against
		// one is a refund route the seller can see and cannot use.
		name:    "never for a Lightning order",
		cart:    Cart{Checkout: Checkout{Method: PayTypeLN, RefundAddr: "DsEarlier"}},
		request: typed("DsTyped"),
		want:    "",
	}}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := placedRefundAddr(&tc.cart, tc.request)
			if got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// asHandlersDo renders one of the order pages with the context its handler
// actually passes.
//
// Which is not the same for both, and that is the point of going through
// here. handleOrderStatus builds an orderContext; handlePlaceOrder passes the
// order itself. A template that reaches for a field one of them has and the
// other does not renders on one page and fails on the other -- which is
// exactly what shipped: paypanel.tmpl was handed ".Order", the order page
// drew it, and placing an order came back as "can't evaluate field Order in
// type **simplestore.Order".
func asHandlersDo(t *testing.T, s *Store, page string, order Order) string {
	t.Helper()
	var data any = &orderContext{Order: order}
	if page == orderPlacedTmplFile {
		copied := order
		ptr := &copied
		data = &ptr
	}

	s.mtx.Lock()
	res, err := s.renderPage(page, data)
	s.mtx.Unlock()
	if err != nil {
		t.Fatalf("%s: %v", page, err)
	}
	return string(res.Data)
}

// payingOrder is an order sitting on its pay page, one way or the other.
func payingOrder(payType PayType, invoice string) Order {
	return Order{
		ID:           OrderID(1),
		Status:       StatusPlaced,
		PlacedTS:     time.Now(),
		ExpiresTS:    time.Now().Add(quoteHoldsFor),
		ExchangeRate: 20,
		PayType:      payType,
		Invoice:      invoice,
		Cart: Cart{Items: []*CartItem{{
			Product:  &Product{SKU: "r1", Title: "A record", Price: 10},
			Quantity: 1,
		}}},
	}
}

// TestTheOnChainPayPageOffersBothWallets.
//
// A square and an address for a wallet somewhere else, and the wallet in this
// app beside it -- which already knows the address and the amount. Using it
// meant copying the address out of the page, opening the wallet screen,
// pasting it in and typing the amount by hand, inside an app that knew all
// three.
func TestTheOnChainPayPageOffersBothWallets(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	order := payingOrder(PayTypeOnChain, "DsPaymentAddress")

	for _, page := range []string{orderTmplFile, orderPlacedTmplFile} {
		body := asHandlersDo(t, s, page, order)
		if !strings.Contains(body, "--payways[") {
			t.Errorf("%s does not offer the two ways to pay:\n%s", page, body)
		}
		if !strings.Contains(body, "addr=DsPaymentAddress") {
			t.Errorf("%s does not name the address:\n%s", page, body)
		}
		// The amount the block sends, in the places coins move in rather
		// than the four the page displays.
		if !strings.Contains(body, "amount=0.50000000") {
			t.Errorf("%s does not name the amount to send:\n%s", page, body)
		}
	}
}

// TestALightningOrderHasOneThingToPressOnItsPayPage.
//
// The review page's button and this one were both money-coloured with the
// same figure written across them, which for a Lightning order reads as being
// asked to pay twice. The review says "Place order" now; this is the only
// place a Lightning order is paid, and the invoice is what pays it.
func TestALightningOrderHasOneThingToPressOnItsPayPage(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	order := payingOrder(PayTypeLN, "lnbcrt1invoice")

	body := asHandlersDo(t, s, orderPlacedTmplFile, order)
	if !strings.Contains(body, "lnpay://lnbcrt1invoice") {
		t.Errorf("the pay page does not offer the invoice:\n%s", body)
	}
	// And no square: a Lightning invoice is paid by the client already
	// showing it, so a code to point a phone at is a second way that is not
	// a way.
	if strings.Contains(body, "--qr[") {
		t.Errorf("a Lightning order was given a QR code:\n%s", body)
	}
}

// paidOrder is an order whose money has arrived.
func paidOrder(payType PayType) Order {
	o := payingOrder(payType, "DsPaymentAddress")
	o.Status = StatusPaid
	return o
}

// TestTheRefundAddressIsAskedForAfterPayment.
//
// It has been in three places. Under the payment cards and on the review page
// it read as "this might go wrong" while the buyer was still deciding whether
// to trust the shop; here it is a detail for the unlikely case, given by
// somebody who has already paid.
func TestTheRefundAddressIsAskedForAfterPayment(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)

	page := asHandlersDo(t, s, orderTmplFile, paidOrder(PayTypeOnChain))
	for _, want := range []string{
		"What happens next",
		"What if it has to be sent back?",
		`name="refund_addr"`,
		"/setRefund/",
	} {
		if !strings.Contains(page, want) {
			t.Errorf("the paid order page is missing %q:\n%s", want, page)
		}
	}
}

// TestALightningOrderIsNotAskedForARefundAddress: there is nowhere for a
// Lightning payment to go back to, so asking is asking for something nobody
// can give.
func TestALightningOrderIsNotAskedForARefundAddress(t *testing.T) {
	s := shopTaking(t, PayTypeLN)

	page := asHandlersDo(t, s, orderTmplFile, paidOrder(PayTypeLN))
	if !strings.Contains(page, "What happens next") {
		t.Fatalf("the paid order page has no what-happens-next:\n%s", page)
	}
	if strings.Contains(page, "refund_addr") {
		t.Errorf("a Lightning order was asked for a refund address:\n%s", page)
	}
}

// TestSavingARefundAddress walks the route the form posts to.
func TestSavingARefundAddress(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	uid := clientintf.UserID{}

	order := paidOrder(PayTypeOnChain)
	dir := filepath.Join(s.root, ordersDir, uid.String())
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	fname := filepath.Join(dir, orderFnamePattern.FilenameFor(uint64(order.ID.Num())))
	if err := jsonfile.Write(fname, &order, s.log); err != nil {
		t.Fatal(err)
	}

	data, _ := json.Marshal(map[string]any{"refund_addr": "  DsRefund  "})
	res := answers(t, "setRefund", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleSetRefund(context.Background(), uid,
			&rpc.RMFetchResource{
				Path: []string{"setRefund", order.ID.String()},
				Data: data,
			})
	})
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("status %d: %s", res.Status, res.Data)
	}

	var saved Order
	if err := jsonfile.Read(fname, &saved); err != nil {
		t.Fatal(err)
	}
	if saved.RefundAddr != "DsRefund" {
		t.Errorf("the refund address was not saved: %q", saved.RefundAddr)
	}
	// And the buyer is put back on the order, not on a page saying "saved".
	if !strings.Contains(string(res.Data), "Order #1") {
		t.Errorf("saving did not answer with the order:\n%s", res.Data)
	}
}

// TestTheQuoteHoldsForTwentyFiveMinutes: the rate is struck when the order is
// placed, and every minute it is held is a minute the seller carries the
// difference on a currency that moves.
func TestTheQuoteHoldsForTwentyFiveMinutes(t *testing.T) {
	if got := QuoteHoldsFor(); got != "25 minutes" {
		t.Errorf("the quote holds for %q", got)
	}
}

// TestTheTransactionIsOfferedToCopy.
//
// Between "seen" and "confirmed" the shop tells the buyer to wait and the
// buyer has nothing to look at; a seller chasing a payment has the same
// problem from the other end. The transaction id is the one thing either of
// them can check without asking the other.
func TestTheTransactionIsOfferedToCopy(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)

	seen := payingOrder(PayTypeOnChain, "DsPaymentAddress")
	now := time.Now()
	seen.SeenTS = &now
	seen.PaymentTx = "abc123txid"

	paid := paidOrder(PayTypeOnChain)
	paid.PaymentTx = "abc123txid"

	for _, tc := range []struct {
		name  string
		order Order
	}{{"waiting for a confirmation", seen}, {"paid", paid}} {
		t.Run(tc.name, func(t *testing.T) {
			page := asHandlersDo(t, s, orderTmplFile, tc.order)
			if !strings.Contains(page, "--copy[") {
				t.Errorf("the transaction is not offered to copy:\n%s", page)
			}
			if !strings.Contains(page, "abc123txid") {
				t.Errorf("the transaction is not shown:\n%s", page)
			}
		})
	}
}

// TestNoTransactionIsShownWhenThereIsNotOne: a Lightning order has nothing a
// block explorer can be pointed at, and neither has an order nobody has paid.
func TestNoTransactionIsShownWhenThereIsNotOne(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	page := asHandlersDo(t, s, orderTmplFile, paidOrder(PayTypeLN))
	if strings.Contains(page, "Transaction — press to copy") {
		t.Errorf("an order with no transaction offered one:\n%s", page)
	}
}

// TestTheSellerCanCopyTheInvoiceAndTheTransaction is the same question from
// the other end of the sale.
func TestTheSellerCanCopyTheInvoiceAndTheTransaction(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	order := paidOrder(PayTypeOnChain)
	order.PaymentTx = "abc123txid"

	s.mtx.Lock()
	res, err := s.renderPage("admin_order.tmpl",
		&adminOrderContext{Order: order, UserNick: "ada"})
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	page := string(res.Data)
	for _, want := range []string{
		"Payment address — press to copy",
		"DsPaymentAddress",
		"Transaction — press to copy",
		"abc123txid",
	} {
		if !strings.Contains(page, want) {
			t.Errorf("the seller's order page is missing %q:\n%s", want, page)
		}
	}
}

// TestTheExplorerFollowsTheNetwork: an id is no use without somewhere to
// paste it, and pointing a testnet buyer at the mainnet explorer is worse
// than saying nothing.
func TestTheExplorerFollowsTheNetwork(t *testing.T) {
	for _, tc := range []struct{ net, want string }{
		{"mainnet", "dcrdata.decred.org"},
		{"testnet3", "testnet.dcrdata.org"},
		{"simnet", ""},
	} {
		if got := explorerFor(tc.net); got != tc.want {
			t.Errorf("%s: got %q, want %q", tc.net, got, tc.want)
		}
	}
}

// TestThePayPageShowsWhatWasBought: a bulleted list of titles, where the shop
// has pictures of every one of them.
func TestThePayPageShowsWhatWasBought(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	order := payingOrder(PayTypeOnChain, "DsPaymentAddress")
	order.Cart.Items[0].Product.Image = "record.jpg"

	page := asHandlersDo(t, s, orderPlacedTmplFile, order)
	if !strings.Contains(page, "--listing--") {
		t.Errorf("the pay page still lists what was bought as bullets:\n%s", page)
	}
	if !strings.Contains(page, "image: "+ProductImagePath("record.jpg")) {
		t.Errorf("the pay page does not show the product's picture:\n%s", page)
	}
}

// TestAPaidOrderOffersItsFiles.
//
// The shop sends a paid order's files and they land in Files > Purchases like
// anything else that arrives -- which left the buyer on a page that said a
// file was on its way and then said nothing else.
func TestAPaidOrderOffersItsFiles(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	order := paidOrder(PayTypeOnChain)
	order.Cart.Items[0].Product.SendFilename = "goods/guide.md"

	page := asHandlersDo(t, s, orderTmplFile, order)
	for _, want := range []string{
		"## Your files",
		"--purchase[order=00000001, sku=r1, title=A record]--",
	} {
		if !strings.Contains(page, want) {
			t.Errorf("the order page is missing %q:\n%s", want, page)
		}
	}
}

// TestAnOrderThatOwesNoFilesSaysNothingAboutThem.
func TestAnOrderThatOwesNoFilesSaysNothingAboutThem(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	page := asHandlersDo(t, s, orderTmplFile, paidOrder(PayTypeOnChain))
	if strings.Contains(page, "Your files") {
		t.Errorf("an order with no files offered some:\n%s", page)
	}
}

// TestFilesStayReachableAfterTheSellerMovesTheOrderOn.
//
// The section was inside the "payment complete" panel, which lasts only until
// the seller marks the order shipped -- so moving an order on took the
// buyer's way into a file they had bought away with it.
func TestFilesStayReachableAfterTheSellerMovesTheOrderOn(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)

	for _, status := range []OrderStatus{StatusPaid, StatusShipped, StatusCompleted} {
		order := paidOrder(PayTypeOnChain)
		order.Status = status
		order.Cart.Items[0].Product.SendFilename = "goods/guide.md"

		page := asHandlersDo(t, s, orderTmplFile, order)
		if !strings.Contains(page, "--purchase[") {
			t.Errorf("%s: the buyer cannot reach the file they bought:\n%s",
				status, page)
		}
	}

	// And an order nobody has paid for owes nothing yet.
	unpaid := payingOrder(PayTypeOnChain, "DsPaymentAddress")
	unpaid.Cart.Items[0].Product.SendFilename = "goods/guide.md"
	if page := asHandlersDo(t, s, orderTmplFile, unpaid); strings.Contains(page, "--purchase[") {
		t.Errorf("an unpaid order offered its files:\n%s", page)
	}
}

// TestAnAddressIsWrittenOnePerLine.
//
// Markdown joins consecutive lines into a paragraph, so a template with a
// name, a street and a town on three lines renders "Ada Lovelace 1 Long Road
// Kent" -- which is not an address, it is a sentence about one.
func TestAnAddressIsWrittenOnePerLine(t *testing.T) {
	got := AddressLines(&ShippingAddress{
		Name:       "Ada Lovelace",
		Address1:   "1 Long Road",
		City:       "Canterbury",
		State:      "Kent",
		PostalCode: "CT1 1AA",
	})

	want := "Ada Lovelace  \n1 Long Road  \nCanterbury  \nKent  \nCT1 1AA"
	if got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// TestAnAddressSkipsWhatIsNotThere: an empty second line is a blank line in
// the middle of an address, and an empty county is a stray comma.
func TestAnAddressSkipsWhatIsNotThere(t *testing.T) {
	got := AddressLines(&ShippingAddress{
		Name:       "Ada Lovelace",
		Address1:   "1 Long Road",
		City:       "Canterbury",
		PostalCode: "CT1 1AA",
	})
	if strings.Contains(got, "  \n  \n") {
		t.Errorf("an address with a missing line has a blank one: %q", got)
	}
	if strings.Contains(got, "Kent") {
		t.Errorf("an address invented a county: %q", got)
	}
	if AddressLines(nil) != "" {
		t.Error("no address is not an empty line")
	}
}

// TestTheCheckoutAsksForEveryLineOfAnAddress.
//
// The phone number is optional and is for whoever delivers the thing: the
// seller reaches a buyer in Bison Relay, in the order's own messages, which
// is a channel neither of them can mistype.
func TestTheCheckoutAsksForEveryLineOfAnAddress(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	res := answers(t, "checkout", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleCheckout(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"checkout"}})
	})
	page := string(res.Data)
	// Beside the box rather than as a line of prose above them all: as
	// prose it was read before anybody knew which box it was about.
	if !strings.Contains(page, `name="phone" help="A phone number`) {
		t.Errorf("the phone box has no question mark:\n%s", page)
	}
	if strings.Contains(page, "\nA phone number is only") {
		t.Errorf("the note is on the page twice:\n%s", page)
	}
	for _, want := range []string{`name="name"`, `name="address1"`,
		`name="address2"`, `name="city"`, `name="state"`,
		`name="postalCode"`, `name="phone"`} {
		if !strings.Contains(page, want) {
			t.Errorf("the checkout no longer asks for %s:\n%s", want, page)
		}
	}
}

// TestTheDeliveryPanelsRunTheWidthOfThePage.
//
// A block is laid out loosely by the column a page is built from, so a panel
// is as wide as what is in it -- right for a card in a grid, and wrong for a
// panel that is a section of a page, which comes out as wide as its longest
// line and reads as though the page were cut short.
func TestTheDeliveryPanelsRunTheWidthOfThePage(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "method": "ln",
		"name": "Ada", "address1": "1 Long Road", "city": "Canterbury",
		"state": "Kent", "postalCode": "CT1 1AA",
	})

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "--panel[full=on") {
		t.Errorf("the review's panels do not fill the page:\n%s", page)
	}
	if !strings.Contains(page, "Ada  \n1 Long Road") {
		t.Errorf("the address is not one thing per line:\n%s", page)
	}
}

// TestAPhoneNumberIsTheLastLineOfAnAddress, and only when it is given.
func TestAPhoneNumberIsTheLastLineOfAnAddress(t *testing.T) {
	with := AddressLines(&ShippingAddress{
		Name: "Ada", Address1: "1 Long Road", City: "Canterbury",
		PostalCode: "CT1 1AA", Phone: "01227 000000",
	})
	if !strings.HasSuffix(with, "  \n01227 000000") {
		t.Errorf("got %q", with)
	}

	without := AddressLines(&ShippingAddress{
		Name: "Ada", Address1: "1 Long Road", City: "Canterbury",
		PostalCode: "CT1 1AA",
	})
	if strings.HasSuffix(without, "  \n") {
		t.Errorf("an address with no phone number ends in an empty line: %q",
			without)
	}
}

// TestTheDeliveryPanelKeepsItsNoteBehindAMark.
//
// "The seller reaches you in Bison Relay" is true, worth knowing once, and
// read every time by everybody who already knows it -- which is what a help
// icon is for.
func TestTheDeliveryPanelKeepsItsNoteBehindAMark(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	shipping(s)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	setCheckout(t, s, uid, map[string]any{
		"doing": "continue", "method": "ln",
		"name": "Ada", "address1": "1 Long Road", "city": "Canterbury",
		"state": "Kent", "postalCode": "CT1 1AA",
	})

	res := answers(t, "review", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReview(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"review"}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "help=") {
		t.Errorf("the panel has no question mark:\n%s", page)
	}

	// Each line of the address on its own line: what a buyer is checking is
	// each thing they typed, against the box they typed it into.
	if !strings.Contains(page, "Canterbury  \nKent  \nCT1 1AA") {
		t.Errorf("the town, county and postcode share a line:\n%s", page)
	}
}

// TestTheTrailIsTheWayBack.
//
// Each page in the sequence used to end in a row of links -- "Back to your
// cart · Back to checkout" -- which said what the trail at the top already
// showed, in a second place, at the far end of the page from where somebody
// reads where they are.
func TestTheTrailIsTheWayBack(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	uid := clientintf.UserID{}
	fullCart(t, s, uid)

	for _, step := range []struct {
		name string
		call func() (*rpc.RMFetchResourceReply, error)
	}{
		{"checkout", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleCheckout(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"checkout"}})
		}},
		{"review", func() (*rpc.RMFetchResourceReply, error) {
			return s.handleReview(context.Background(), uid,
				&rpc.RMFetchResource{Path: []string{"review"}})
		}},
	} {
		page := string(answers(t, step.name, step.call).Data)
		if strings.Contains(page, "Back to your cart") ||
			strings.Contains(page, "Back to checkout") {
			t.Errorf("%s still ends in a row of links:\n%s", step.name, page)
		}
		if !strings.Contains(page, "[Cart](/cart)") {
			t.Errorf("%s has no way back to the cart:\n%s", step.name, page)
		}
	}

	// Pay is the one step nothing links to: an order has to be placed before
	// there is one to pay, so there is nowhere for that word to point until
	// the press that makes it.
	for _, step := range checkoutSteps {
		if step.label == "Pay" && step.path != "" {
			t.Errorf("Pay links to %q", step.path)
		}
	}
}

// TestThePayPageDoesNotOfferTheWayBack.
//
// The steps before Pay are places to answer a question, and the answers have
// been taken: the cart was emptied when the order was placed, so Cart leads
// to an empty page and Checkout would be the start of a different order.
// Behind you and gone are not the same thing.
func TestThePayPageDoesNotOfferTheWayBack(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	page := asHandlersDo(t, s, orderPlacedTmplFile,
		payingOrder(PayTypeOnChain, "DsPaymentAddress"))

	if strings.Contains(page, "](/cart)") || strings.Contains(page, "](/checkout)") {
		t.Errorf("the pay page links back into a checkout that is over:\n%s", page)
	}
	if !strings.Contains(page, "Cart | Checkout | Review | Pay") {
		t.Errorf("the pay page lost its trail:\n%s", page)
	}
	// And the row of links at the foot is gone with it.
	if strings.Contains(page, "[Your orders]") {
		t.Errorf("the pay page still ends in a row of links:\n%s", page)
	}
}

// TestThePayPageBoxesWhatRunsOut, in the theme's own warning colour, for
// both ways of paying.
func TestThePayPageBoxesWhatRunsOut(t *testing.T) {
	for _, pay := range []PayType{PayTypeOnChain, PayTypeLN} {
		s := shopTaking(t, pay)
		page := asHandlersDo(t, s, orderPlacedTmplFile,
			payingOrder(pay, "DsPaymentAddress"))

		if !strings.Contains(page, "--countdown[seconds=") {
			t.Errorf("%s: the clock is not counted:\n%s", pay, page)
		}
		// And it names the way back, for when it runs out.
		if !strings.Contains(page, "link=/reorder/00000001") {
			t.Errorf("%s: nothing to press when the price lapses:\n%s", pay, page)
		}
	}
}

// TestThePayPageKeepsItsNoteBehindAMark.
func TestThePayPageKeepsItsNoteBehindAMark(t *testing.T) {
	s := shopTaking(t, PayTypeOnChain)
	page := asHandlersDo(t, s, orderPlacedTmplFile,
		payingOrder(PayTypeOnChain, "DsPaymentAddress"))

	if !strings.Contains(page, "help=The shop watches for your payment") {
		t.Errorf("the two halves have no question mark:\n%s", page)
	}
	// And not as a paragraph under them as well.
	if strings.Contains(page, "\nThe shop watches for your payment") {
		t.Errorf("the note is on the page twice:\n%s", page)
	}
}

// TestTheLightningPayAreaIsACardOfItsOwn.
//
// It was a bare invoice line inside the heading's panel with a sentence under
// it saying that pressing it paid. A press that spends money should not need
// explaining, and what runs out belongs below the thing it is about rather
// than inside it.
func TestTheLightningPayAreaIsACardOfItsOwn(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	page := asHandlersDo(t, s, orderPlacedTmplFile,
		payingOrder(PayTypeLN, "lnbcrt1invoice"))

	if !strings.Contains(page, "**Pay with your Bison Relay wallet**") {
		t.Errorf("the Lightning half has no card of its own:\n%s", page)
	}
	if strings.Contains(page, "Pressing this pays it") {
		t.Errorf("the button is still explained in prose:\n%s", page)
	}

	// The clock sits after the pay card, not inside it.
	pay := strings.Index(page, "**Pay with your Bison Relay wallet**")
	shut := strings.Index(page[pay:], "--/panel--")
	clock := strings.Index(page, "--countdown[")
	if pay < 0 || shut < 0 || clock < 0 {
		t.Fatalf("the page is missing one of its parts:\n%s", page)
	}
	if clock < pay+shut {
		t.Errorf("what runs out is inside the pay card:\n%s", page)
	}
}

// TestTheRateIsSaidToTheNearestCentAndTheRightWayRound.
//
// It printed as a bare float -- "At 13.889331962 DCR/$" -- which is nine
// places of a figure nobody checks, labelled backwards.
func TestTheRateIsSaidToTheNearestCentAndTheRightWayRound(t *testing.T) {
	s := shopTaking(t, PayTypeLN)
	order := payingOrder(PayTypeLN, "lnbcrt1invoice")
	order.ExchangeRate = 13.889331962

	page := asHandlersDo(t, s, orderPlacedTmplFile, order)
	if !strings.Contains(page, "At 13.89 USD/DCR") {
		t.Errorf("the rate is not said plainly:\n%s", page)
	}
	if strings.Contains(page, "DCR/$") {
		t.Errorf("the rate is labelled the wrong way round:\n%s", page)
	}
}

// TestALapsedOrderCanBeOrderedAgain.
//
// A quote that runs out is not a buyer who changed their mind: they chose
// what they wanted, answered every question and were beaten by a clock.
func TestALapsedOrderCanBeOrderedAgain(t *testing.T) {
	s := storeForHandlers(t)
	s.cfg.PayType = PayTypeLN
	uid := clientintf.UserID{}

	order := Order{
		ID: 1, User: uid, Status: StatusPlaced,
		PlacedTS:  time.Now().Add(-time.Hour),
		ExpiresTS: time.Now().Add(-time.Minute),
		Cart: Cart{Items: []*CartItem{
			{Product: s.products["r1"], Quantity: 2},
		}},
	}
	dir := filepath.Join(s.root, ordersDir, uid.String())
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	fname := filepath.Join(dir, orderFnamePattern.FilenameFor(1))
	if err := jsonfile.Write(fname, &order, s.log); err != nil {
		t.Fatal(err)
	}

	res := answers(t, "reorder", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReorder(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"reorder", order.ID.String()}})
	})
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("status %d: %s", res.Status, res.Data)
	}
	if !strings.Contains(string(res.Data), "Review your order") {
		t.Errorf("ordering again did not reach the review:\n%s", res.Data)
	}

	// The same things, back in the cart.
	cart := savedCart(t, s, uid)
	if len(cart.Items) != 1 || cart.Items[0].Quantity != 2 {
		t.Fatalf("the cart holds %d lines", len(cart.Items))
	}

	// And the order it came from is called off, so there are not two live
	// orders for one cart.
	var saved Order
	if err := jsonfile.Read(fname, &saved); err != nil {
		t.Fatal(err)
	}
	if saved.Status != StatusCanceled {
		t.Errorf("the lapsed order is %q", saved.Status)
	}
}

// TestAPaidOrderCannotBeOrderedAgain: putting a sale back in a cart would be
// offering to buy it twice.
func TestAPaidOrderCannotBeOrderedAgain(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}

	order := paidOrder(PayTypeLN)
	order.User = uid
	dir := filepath.Join(s.root, ordersDir, uid.String())
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	fname := filepath.Join(dir, orderFnamePattern.FilenameFor(uint64(order.ID.Num())))
	if err := jsonfile.Write(fname, &order, s.log); err != nil {
		t.Fatal(err)
	}

	res := answers(t, "reorder", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReorder(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"reorder", order.ID.String()}})
	})
	if !strings.Contains(string(res.Data), "Payment complete") {
		t.Errorf("a paid order was put back in a cart:\n%s", res.Data)
	}
	if cart := savedCart(t, s, uid); len(cart.Items) != 0 {
		t.Errorf("%d things went back into the cart", len(cart.Items))
	}
}

// TestOrderingAgainSkipsWhatTheShopNoLongerSells.
//
// The catalogue has moved on: a product taken off the shop while this order
// sat unpaid is not one to put back.
//
// Stock is a different case and needs no test here, because the order was
// holding it: calling the order off gives it back, so the thing that lapsed
// is available again by the time it is put in the cart, which is the whole
// point of counting it.
func TestOrderingAgainSkipsWhatTheShopNoLongerSells(t *testing.T) {
	s := storeForHandlers(t)
	s.cfg.PayType = PayTypeLN
	uid := clientintf.UserID{}

	order := Order{
		ID: 1, User: uid, Status: StatusPlaced,
		ExpiresTS: time.Now().Add(-time.Minute),
		Cart: Cart{Items: []*CartItem{
			{Product: s.products["r1"], Quantity: 1},
		}},
	}
	dir := filepath.Join(s.root, ordersDir, uid.String())
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := jsonfile.Write(
		filepath.Join(dir, orderFnamePattern.FilenameFor(1)), &order, s.log); err != nil {
		t.Fatal(err)
	}

	delete(s.products, "r1")

	res := answers(t, "reorder", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleReorder(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"reorder", order.ID.String()}})
	})
	page := string(res.Data)
	if !strings.Contains(page, "empty") {
		t.Errorf("the shop did not say there was nothing to put back:\n%s", page)
	}
	if cart := savedCart(t, s, uid); len(cart.Items) != 0 {
		t.Errorf("something the shop no longer sells went back into the cart")
	}
}
