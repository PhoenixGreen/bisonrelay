package simplestore

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/internal/strescape"
	"github.com/companyzero/bisonrelay/rpc"
)

// checkout.go is the way from a full cart to a placed order.
//
// It was one button. The cart asked for an address, a way to pay and the
// order itself in a single form, and everything that could be wrong with any
// of it was found out afterwards -- an incomplete address came back as the
// words "incomplete shipping address" on a page with nothing on it, and the
// buyer's way back was the browser's own.
//
// So it is three: choose how to pay and where it goes, look at what that
// comes to, then place it. Each step is a page of its own, each says where it
// is in the sequence, and what has been answered is kept on the cart -- so
// stepping back to change one thing does not cost the others.

// checkoutStep is where the buyer is, so the trail at the top of each page
// can say so.
type checkoutStep string

const (
	stepCart     checkoutStep = "cart"
	stepCheckout checkoutStep = "checkout"
	stepReview   checkoutStep = "review"
	stepPay      checkoutStep = "pay"
)

// checkoutContext is what the checkout page is drawn from.
type checkoutContext struct {
	*Cart

	// Methods is what the shop takes, so the page offers a choice only when
	// there is one to make.
	Methods  PayMethods
	TotalDCR string

	// TotalDCRAmount is the same figure as a bare number, for the wallet
	// block to measure the reader's own balance against.
	TotalDCRAmount string

	// Ships is whether anything in the cart needs an address.
	Ships bool

	// Problem is what is wrong with what has been answered so far, said on
	// the page it was answered on rather than after the order is placed.
	Problem string

	Step checkoutStep
}

// reviewContext is the order as it will be placed.
type reviewContext struct {
	*Cart
	Methods  PayMethods
	TotalDCR string
	Ships    bool
	Step     checkoutStep
}

// checkoutForm is what one step of the checkout posts.
type checkoutForm struct {
	// Doing is which of the two things this post is: choosing a way to pay,
	// or finishing the step.
	Doing string `json:"doing"`

	Method string `json:"method"`

	// RefundAddr is a pointer so that a post which does not carry the field
	// at all can be told from one that carries it empty.
	//
	// It is asked for on the review page now, not the checkout, so the
	// checkout's own form does not send it. Read as a plain string, going
	// back a step to change the delivery address would silently wipe a
	// refund address given a page later.
	RefundAddr *string `json:"refund_addr"`

	Name       string `json:"name"`
	Address1   string `json:"address1"`
	Address2   string `json:"address2"`
	City       string `json:"city"`
	State      string `json:"state"`
	PostalCode string `json:"postalCode"`

	// Phone is optional, and for whoever delivers the thing rather than for
	// the seller: the seller reaches a buyer in Bison Relay, in the order's
	// own messages, which is a channel neither of them can mistype and which
	// is attached to the thing it is about.
	Phone string `json:"phone"`
}

// cartShips is whether anything in this cart needs an address.
func cartShips(cart *Cart) bool {
	for _, item := range cart.Items {
		if item.Product != nil && item.Product.Shipping {
			return true
		}
	}
	return false
}

// loadCart reads this buyer's cart.
func (s *Store) loadCart(uid clientintf.UserID) (*Cart, string, error) {
	fname := filepath.Join(s.root, cartsDir, uid.String())
	var cart Cart
	err := jsonfile.Read(fname, &cart)
	if err != nil && !errors.Is(err, jsonfile.ErrNotFound) {
		return nil, fname, err
	}
	return &cart, fname, nil
}

// handleCheckout is the first step: how to pay, and where it goes.
func (s *Store) handleCheckout(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	s.mtx.Lock()
	defer s.mtx.Unlock()

	cart, _, err := s.loadCart(uid)
	if err != nil {
		return nil, err
	}
	if len(cart.Items) == 0 {
		return s.emptyCartPage()
	}
	return s.checkoutPage(cart, "")
}

// handleSetCheckout takes what one step of the checkout answered.
//
// Two things arrive here: a way to pay, chosen by pressing one of the cards,
// and the step being finished. The first stays on this page with the choice
// marked; the second moves on, or says what is missing and stays.
func (s *Store) handleSetCheckout(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	var form checkoutForm
	if err := json.Unmarshal(request.Data, &form); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("request data not valid json"),
		}, nil
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	cart, fname, err := s.loadCart(uid)
	if err != nil {
		return nil, err
	}
	if len(cart.Items) == 0 {
		return s.emptyCartPage()
	}

	methods := s.payMethods()
	if want := PayType(form.Method); want != "" {
		if (want == PayTypeLN && methods.LN) ||
			(want == PayTypeOnChain && methods.OnChain) {
			cart.Checkout.Method = want
		}
	}
	// The refund address is only ever asked for on-chain, and is dropped
	// when the buyer moves off it: an address kept against a Lightning order
	// is a promise the shop cannot keep.
	switch {
	case cart.Checkout.Method != PayTypeOnChain:
		cart.Checkout.RefundAddr = ""
	case form.RefundAddr != nil:
		cart.Checkout.RefundAddr = refundAddr(*form.RefundAddr)
	}

	if cartShips(cart) && form.Doing != "method" {
		cart.Checkout.Ship = escapeAddress(&ShippingAddress{
			Name:       form.Name,
			Address1:   form.Address1,
			Address2:   form.Address2,
			City:       form.City,
			State:      form.State,
			PostalCode: form.PostalCode,
			Phone:      form.Phone,
		})
	}

	err = jsonfile.Write(fname, cart, s.log)
	if err != nil {
		return nil, err
	}

	// Choosing a way to pay is not finishing the step.
	if form.Doing == "method" {
		return s.checkoutPage(cart, "")
	}

	if problem := s.checkoutProblem(cart); problem != "" {
		return s.checkoutPage(cart, problem)
	}
	return s.reviewPage(cart)
}

// refundAddr is a refund address as it will be stored.
//
// Made safe where it arrives, like every other thing a customer types, so
// that the three pages which show it -- the buyer's order, the seller's
// order, the review -- are safe without having to remember.
func refundAddr(typed string) string {
	return strescape.Content(strings.TrimSpace(typed))
}

// checkoutProblem is what is still missing, or empty when nothing is.
//
// Asked before the order rather than after it. The shop used to find an
// incomplete address while placing the order and answer with the words
// "incomplete shipping address" -- no page, no way back, and no way to know
// which line was the problem.
func (s *Store) checkoutProblem(cart *Cart) string {
	if s.payMethods().Both() && cart.Checkout.Method == "" {
		return "Choose how you would like to pay."
	}
	if !cartShips(cart) {
		return ""
	}

	addr := cart.Checkout.Ship
	if addr == nil {
		return "Something in this order is posted, so it needs an address."
	}
	var missing []string
	for _, field := range []struct {
		name  string
		value string
	}{
		{"a name", addr.Name},
		{"an address", addr.Address1},
		{"a city", addr.City},
		{"a state or county", addr.State},
		{"a postal code", addr.PostalCode},
	} {
		if strings.TrimSpace(field.value) == "" {
			missing = append(missing, field.name)
		}
	}
	if len(missing) == 0 {
		return ""
	}
	return "The delivery details still need " + strings.Join(missing, ", ") + "."
}

// handleReview is the second step: what this comes to, before it is placed.
func (s *Store) handleReview(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	s.mtx.Lock()
	defer s.mtx.Unlock()

	cart, _, err := s.loadCart(uid)
	if err != nil {
		return nil, err
	}
	if len(cart.Items) == 0 {
		return s.emptyCartPage()
	}
	if problem := s.checkoutProblem(cart); problem != "" {
		return s.checkoutPage(cart, problem)
	}
	return s.reviewPage(cart)
}

// checkoutPage draws the first step. The caller holds s.mtx -- templates run
// under it everywhere else in the shop, and handlePlaceOrder holds it for the
// whole of its work and still has to be able to send somebody back here.
func (s *Store) checkoutPage(cart *Cart, problem string) (*rpc.RMFetchResourceReply, error) {
	tctx := &checkoutContext{
		Cart:           cart,
		Methods:        s.payMethods(),
		TotalDCR:       s.approxDCR(cart.Total()),
		TotalDCRAmount: s.approxDCRAmount(cart.Total()),
		Ships:          cartShips(cart),
		Problem:        problem,
		Step:           stepCheckout,
	}
	return s.renderPage(checkoutTmplFile, tctx)
}

// reviewPage draws the second step. The caller holds s.mtx.
func (s *Store) reviewPage(cart *Cart) (*rpc.RMFetchResourceReply, error) {
	tctx := &reviewContext{
		Cart:     cart,
		Methods:  s.payMethods(),
		TotalDCR: s.approxDCR(cart.Total()),
		Ships:    cartShips(cart),
		Step:     stepReview,
	}
	return s.renderPage(reviewTmplFile, tctx)
}

// emptyCartPage is what a checkout with nothing in it says.
//
// Reachable by going back to a step after emptying the cart in another
// window, and by pressing a stale button. Neither is an error worth a status
// code: what somebody in that position needs is the way back to the shop.
func (s *Store) emptyCartPage() (*rpc.RMFetchResourceReply, error) {
	return &rpc.RMFetchResourceReply{
		Data: []byte(fmt.Sprintf("# Nothing to check out\n\nYour cart is "+
			"empty.\n\n[Back to the shop](%s)\n", s.indexPath)),
		Status: rpc.ResourceStatusOk,
	}, nil
}

// renderPage runs one of the shop's templates. The caller holds the lock.
func (s *Store) renderPage(name string, data any) (*rpc.RMFetchResourceReply, error) {
	// A shop made before these pages existed does not have them: templates
	// are copied into the store once and are the seller's from then on, so a
	// new one only arrives when they restore pages. Said plainly, with the
	// way back, rather than as a rendering error on a blank screen.
	if s.tmpl.Lookup(name) == nil {
		return &rpc.RMFetchResourceReply{
			Data: []byte(fmt.Sprintf("# This shop has no %s page yet\n\n"+
				"The seller can add it from Pages, under Restore pages.\n\n"+
				"[Back to your cart](/cart)\n", strings.TrimSuffix(name, ".tmpl"))),
			Status: rpc.ResourceStatusOk,
		}, nil
	}

	w := &bytes.Buffer{}
	if err := s.tmpl.ExecuteTemplate(w, name, data); err != nil {
		return nil, fmt.Errorf("unable to execute %s: %v", name, err)
	}
	return &rpc.RMFetchResourceReply{Data: w.Bytes(), Status: rpc.ResourceStatusOk}, nil
}

// Ready is whether a way to pay is settled: either the buyer has chosen one,
// or the shop only offers one and never asked.
func (c *checkoutContext) Ready() bool {
	return !c.Methods.Both() || c.Checkout.Method != ""
}

// Chose is whether [method] is the one this order will be paid with.
//
// A shop offering one way is answered by that way whether or not the buyer
// pressed anything, which is what keeps the single-card page from asking a
// question with only one answer.
func (c *checkoutContext) Chose(method string) bool {
	if c.Checkout.Method != "" {
		return string(c.Checkout.Method) == method
	}
	if c.Methods.Both() {
		return false
	}
	return (method == string(PayTypeLN) && c.Methods.LN) ||
		(method == string(PayTypeOnChain) && c.Methods.OnChain)
}

// PayingOnChain is whether this order is heading for an on-chain payment, and
// so whether there is anywhere for a refund to go back to.
func (c *checkoutContext) PayingOnChain() bool {
	return c.Chose(string(PayTypeOnChain))
}

// WalletShow is which halves of the wallet block to draw: only the kinds of
// payment this shop actually takes.
//
// An on-chain balance beside a Lightning-only shop is a figure that answers
// a question nobody asked, and worse, one a buyer can read as "you have
// enough" when their only route is a channel that is short.
func (c *checkoutContext) WalletShow() string {
	var show []string
	if c.Methods.LN {
		show = append(show, "ln")
	}
	if c.Methods.OnChain {
		show = append(show, "onchain")
	}
	return strings.Join(show, " ")
}

// MethodSays is the chosen way to pay, in words, for the review page.
func (c *reviewContext) MethodSays() string { return payMethodSays(c.Checkout.Method, c.Methods) }

// PayingOnChain is whether the review page should mention the refund address.
func (c *reviewContext) PayingOnChain() bool {
	if c.Checkout.Method != "" {
		return c.Checkout.Method == PayTypeOnChain
	}
	return c.Methods.OnChain && !c.Methods.LN
}

// payMethodSays is a way to pay as somebody would say it.
func payMethodSays(method PayType, methods PayMethods) string {
	switch {
	case method == PayTypeLN, method == "" && methods.LN && !methods.OnChain:
		return "Lightning"
	case method == PayTypeOnChain, method == "" && methods.OnChain && !methods.LN:
		return "On-chain"
	default:
		return ""
	}
}

// checkoutSteps are the words of the trail, in order.
//
// Four rather than the three a buyer presses through, because the last one is
// the one they care about: an order has to exist before there is anything to
// pay -- the invoice and the address come from it -- so placing it and paying
// for it cannot be the same press. A trail that stopped at "Review" would end
// one step before the step everybody is here for.
var checkoutSteps = []struct {
	label string

	// path is where the step is, for the ones a buyer can go back to.
	//
	// Written as a Markdown link, and only the steps behind the current one
	// are live -- the block decides that, not this. Pay has none: an order
	// has to be placed before there is one to pay, so there is nowhere for
	// that word to point until the press that makes it.
	path string
}{
	{"Cart", "/cart"},
	{"Checkout", "/checkout"},
	{"Review", "/review"},
	{"Pay", ""},
}

// storeSteps writes the trail block for one page.
//
// The steps carry their own links, which is what replaced the row of "Back to
// your cart · Back to checkout" at the foot of every page in the sequence.
// That row said the same thing the trail already showed, in a second place,
// at the far end of the page from where somebody reads where they are.
func storeSteps(title, on string) string {
	// Nothing links back once the order exists.
	//
	// The steps before Pay are places to answer a question, and the answers
	// have been taken: the cart was emptied when the order was placed, so
	// Cart leads to an empty page and Checkout would be the start of a
	// different order. Behind you and gone are not the same thing.
	placed := on == string(stepPay)

	words := make([]string, 0, len(checkoutSteps))
	for _, step := range checkoutSteps {
		if step.path == "" || placed {
			words = append(words, step.label)
			continue
		}
		words = append(words, fmt.Sprintf("[%s](%s)", step.label, step.path))
	}
	return fmt.Sprintf("--steps[on=%s]--\n%s\n%s\n--/steps--\n",
		on, title, strings.Join(words, " | "))
}

// Delivery is how the things in this order reach the buyer.
//
// Three answers, and the page says a different thing for each. "Nothing in
// this order is posted, so there is nowhere for it to go" was true and
// useless: it told a buyer what was not happening. What they want to know is
// where the thing they just bought turns up.
type Delivery string

const (
	// DeliveryPost is anything that goes in the post.
	DeliveryPost Delivery = "post"

	// DeliveryFile is a good the shop sends as a file, over Bison Relay
	// itself, once the order is paid for. See goods.go.
	DeliveryFile Delivery = "file"

	// DeliverySeller is everything else: the seller arranges it with the
	// buyer in the order's own messages.
	DeliverySeller Delivery = "seller"
)

// cartDelivery is how a cart's contents reach whoever bought them.
//
// Post wins over a file when a cart holds both: an address is the answer that
// needs checking, and the file arrives regardless.
func cartDelivery(cart *Cart) Delivery {
	file := false
	for _, item := range cart.Items {
		if item.Product == nil {
			continue
		}
		if item.Product.Shipping {
			return DeliveryPost
		}
		if item.Product.SendFilename != "" {
			file = true
		}
	}
	if file {
		return DeliveryFile
	}
	return DeliverySeller
}

// Delivery is how this order reaches the buyer, for the review page's panel.
func (c *reviewContext) Delivery() Delivery { return cartDelivery(c.Cart) }

// Files is the goods in this order the shop sends as files, by name.
//
// Counted rather than shown, on the page at least: the order is listed in
// full a few lines above, and a product named again in a panel about delivery
// reads as a mistake rather than as a second fact. What the panel needs from
// this is how many, so it can say "this arrives" or "these arrive".
func (c *reviewContext) Files() []string {
	var out []string
	for _, item := range c.Items {
		if item.Product != nil && item.Product.SendFilename != "" {
			out = append(out, item.Product.Title)
		}
	}
	return out
}

// QuoteHoldsFor is how long the quoted amount stands for, in words.
func (c *reviewContext) QuoteHoldsFor() string { return QuoteHoldsFor() }

// handleSetRefund saves where a refund should go for an order that already
// exists.
//
// Asked after the money has arrived rather than before it left. Under the
// payment cards it read as "this might go wrong" at the moment a buyer was
// deciding whether to trust the shop at all; on the page that says the
// payment came through, next to what happens next, it is what it actually is
// -- a detail for the unlikely case, given by somebody who is no longer
// deciding anything.
func (s *Store) handleSetRefund(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	var form struct {
		RefundAddr string `json:"refund_addr"`
	}
	if err := json.Unmarshal(request.Data, &form); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("request data not valid json"),
		}, nil
	}

	var oid OrderID
	if err := oid.FromString(request.Path[1]); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("invalid order id"),
		}, nil
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	fname := filepath.Join(s.root, ordersDir, uid.String(),
		orderFnamePattern.FilenameFor(uint64(oid.Num())))
	var order Order
	if err := jsonfile.Read(fname, &order); err != nil {
		if errors.Is(err, jsonfile.ErrNotFound) {
			return &rpc.RMFetchResourceReply{
				Status: rpc.ResourceStatusBadRequest,
				Data:   []byte("order not found"),
			}, nil
		}
		return nil, err
	}

	// On-chain only, and never on an order that is finished with. A refund
	// address on a Lightning order is a promise nobody can keep, and one
	// added to a closed order is a change to a record.
	if !order.OnChain() || !order.Open() {
		return s.renderPage(orderTmplFile, &orderContext{Order: order})
	}

	order.RefundAddr = refundAddr(form.RefundAddr)
	if err := jsonfile.Write(fname, &order, s.log); err != nil {
		return nil, err
	}
	return s.renderPage(orderTmplFile, &orderContext{Order: order})
}

// Goods are the lines of this order that are delivered as a file.
//
// For the block on the order page that offers each of them: the shop knows
// what it owes and cannot know whether it arrived -- where a file landed is a
// fact about the buyer's machine. So the page names what was bought and the
// buyer's own client answers. See markdown_purchase.dart.
func (order *Order) Goods() []*CartItem {
	var out []*CartItem
	for _, item := range order.Cart.Items {
		if item.Product != nil && item.Product.SendFilename != "" {
			out = append(out, item)
		}
	}
	return out
}

// handleReorder puts a lapsed order's things back in the cart.
//
// A quote that runs out is not a buyer who changed their mind: they chose
// what they wanted, answered every question and were beaten by a clock. The
// shop calls the order off and puts its stock back, and until now that left
// them with an empty cart and a shop front to start again from.
//
// So this is the one press that undoes the clock: the same items, at whatever
// today's rate makes them, straight back to the review.
func (s *Store) handleReorder(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	var oid OrderID
	if err := oid.FromString(request.Path[1]); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("invalid order id"),
		}, nil
	}

	s.mtx.Lock()
	order, orderFname, err := s.loadOrderLocked(uid, oid)
	if err != nil {
		s.mtx.Unlock()
		if errors.Is(err, jsonfile.ErrNotFound) {
			return &rpc.RMFetchResourceReply{
				Status: rpc.ResourceStatusBadRequest,
				Data:   []byte("order not found"),
			}, nil
		}
		return nil, err
	}

	// Only an order nobody paid for. One that has been paid is a sale, and
	// putting a sale back in a cart would be offering to buy it twice.
	if !order.AwaitingPayment() {
		reply, err := s.renderPage(orderTmplFile, &orderContext{Order: *order})
		s.mtx.Unlock()
		return reply, err
	}

	// Called off on the way past, if the shop's own timer has not got to it
	// yet. Two live orders for one cart is the thing this must not leave
	// behind -- and the buyer pressing this has already decided which one
	// they want.
	if order.Status == StatusPlaced {
		order.Status = StatusCanceled
		if err := jsonfile.Write(orderFname, order, s.log); err != nil {
			s.mtx.Unlock()
			return nil, err
		}
		s.giveStock(order)
	}

	// Back into the cart, taking what the shop still has: the catalogue has
	// moved on, and a product that sold out while this order sat unpaid is
	// not one to put back.
	cart, cartFname, err := s.loadCart(uid)
	if err != nil {
		s.mtx.Unlock()
		return nil, err
	}

	var gone []string
	for _, item := range order.Cart.Items {
		if item.Product == nil {
			continue
		}
		prod := s.products[item.Product.SKU]
		if prod == nil || !prod.InStock() {
			gone = append(gone, item.Product.Title)
			continue
		}
		added := false
		for _, have := range cart.Items {
			if have.Product != nil && have.Product.SKU == prod.SKU {
				have.Quantity += item.Quantity
				added = true
				break
			}
		}
		if !added {
			cart.Items = append(cart.Items,
				&CartItem{Product: prod, Quantity: item.Quantity})
		}
	}
	cart.Updated = time.Now()

	if err := jsonfile.Write(cartFname, cart, s.log); err != nil {
		s.mtx.Unlock()
		return nil, err
	}
	s.mtx.Unlock()

	if len(cart.Items) == 0 {
		return s.emptyCartPage()
	}
	if len(gone) > 0 {
		return s.checkoutPageLocked(cart,
			"The shop has run out of "+strings.Join(gone, ", ")+
				" since you ordered. The rest is back in your cart.")
	}
	return s.reviewPageLocked(cart)
}

// checkoutPageLocked and reviewPageLocked take the lock themselves, for the
// handlers that have already let go of it.
func (s *Store) checkoutPageLocked(cart *Cart, problem string) (*rpc.RMFetchResourceReply, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()
	return s.checkoutPage(cart, problem)
}

func (s *Store) reviewPageLocked(cart *Cart) (*rpc.RMFetchResourceReply, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()
	return s.reviewPage(cart)
}
