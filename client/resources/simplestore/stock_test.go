package simplestore

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/dcrd/dcrutil/v4"
	"github.com/decred/slog"
)

// stock_test.go covers how many of a thing a shop has, and what happens at
// nought.
//
// The counting itself is the easy half. The hard half is that a count is read
// on the shop front, checked again while a cart is filled and acted on when an
// order is placed, with minutes between each -- so every honest answer has to
// be worked out at the last of those, and everything earlier is a courtesy.

func TestAProductWithNoCountIsAlwaysInStock(t *testing.T) {
	// Which is most of what most shops sell, and the whole catalogue until
	// this existed: a missing field decodes as nought, and nought is sold
	// out.
	p := &Product{SKU: "g1", Title: "A guide"}
	if !p.InStock() {
		t.Error("a product that does not count says it has run out")
	}
	if p.Counted() {
		t.Error("a product that does not count says it does")
	}
	if got := stockLeft(p); got != "" {
		t.Errorf("it claims to have %q", got)
	}
}

func TestACountedProductRunsOut(t *testing.T) {
	p := &Product{SKU: "g1", Title: "A guide", Limited: true, Available: 2}
	if !p.InStock() {
		t.Fatal("two of something is not in stock")
	}
	if got := stockLeft(p); got != "2 left" {
		t.Errorf("got %q", got)
	}

	if got := p.take(1); got != 1 {
		t.Fatalf("took %d of 1", got)
	}
	if got := stockLeft(p); got != "1 left" {
		t.Errorf("got %q", got)
	}

	if got := p.take(1); got != 1 {
		t.Fatalf("took %d of the last 1", got)
	}
	if p.InStock() {
		t.Error("a product with none left says it is in stock")
	}
}

// TestTakingMoreThanThereIsGivesWhatThereIs, and never goes below nought: two
// buyers can reach the last one at the same time.
func TestTakingMoreThanThereIsGivesWhatThereIs(t *testing.T) {
	p := &Product{Limited: true, Available: 2}
	if got := p.take(5); got != 2 {
		t.Errorf("took %d of the 2 there were", got)
	}
	if p.Available != 0 {
		t.Errorf("stock went to %d", p.Available)
	}
	if got := p.take(1); got != 0 {
		t.Errorf("took %d from an empty shelf", got)
	}
	if p.Available != 0 {
		t.Errorf("stock went to %d", p.Available)
	}
}

// TestStockComesBack is what stops a shop selling five of something and
// running out after five people started an order and none of them finished.
func TestStockComesBack(t *testing.T) {
	p := &Product{Limited: true, Available: 1}
	p.take(1)
	p.give(1)
	if !p.InStock() || p.Available != 1 {
		t.Errorf("stock did not come back: %d", p.Available)
	}

	// And a product that does not count is not counted up either.
	free := &Product{}
	free.give(3)
	if free.Available != 0 {
		t.Errorf("an uncounted product was counted to %d", free.Available)
	}
}

// checkFor is a shop's ability to take money, as one pass over the catalogue
// sees it.
func checkFor(lnOnly bool, canReceive int64) stockCheck {
	return stockCheck{lnOnly: lnOnly, canReceive: canReceive}
}

// TestWhyAProductCannotBeBought: two reasons, and they must not be confused.
//
// "Sold out" on something the shop has a hundred of, because its channels are
// short, is a shop lying about its own stock.
func TestWhyAProductCannotBeBought(t *testing.T) {
	plenty := &Product{Title: "A guitar", Price: 20}
	gone := &Product{Title: "A guitar", Price: 20, Limited: true, Available: 0}

	// 1 DCR in atoms, against a price the shop can and cannot receive.
	const dcr = 100_000_000

	tests := []struct {
		name  string
		check stockCheck
		prod  *Product
		price int64
		want  unavailable
	}{{
		name:  "plenty of it, and the shop can be paid",
		check: checkFor(true, 5*dcr),
		prod:  plenty,
		price: dcr,
	}, {
		name:  "none left",
		check: checkFor(true, 5*dcr),
		prod:  gone,
		price: dcr,
		want:  soldOut,
	}, {
		name:  "more than the channels can receive",
		check: checkFor(true, dcr/2),
		prod:  plenty,
		price: dcr,
		want:  cannotBePaid,
	}, {
		// On-chain is always a way to pay, so a short channel is not a
		// reason to stop selling anything.
		name:  "a shop that also takes on-chain",
		check: checkFor(false, 0),
		prod:  plenty,
		price: dcr,
	}, {
		// A node that will not answer is not a node with no room, and a
		// shop that closed itself over a failed balance call would be a
		// shop closing itself over a hiccup.
		name:  "a node that would not say",
		check: checkFor(true, -1),
		prod:  plenty,
		price: dcr,
	}, {
		// Sold out beats a short channel: the shop has none of it, and why
		// it also could not be paid for is beside the point.
		name:  "both at once",
		check: checkFor(true, dcr/2),
		prod:  gone,
		price: dcr,
		want:  soldOut,
	}}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.check.says(tc.prod, dcrutil.Amount(tc.price)); got != tc.want {
				t.Errorf("got %q, want %q", got, tc.want)
			}
		})
	}
}

// TestTheRibbonIsOnlyOnACardNobodyCanBuy.
func TestTheRibbonIsOnlyOnACardNobodyCanBuy(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.SoldOutLabel = "Sold out"

	s := &Store{indexPath: "/", log: slog.Disabled, layout: layout}
	plenty := &Product{Title: "A guitar", SKU: "gtr", Price: 20}
	gone := &Product{Title: "A guitar", SKU: "gtr", Price: 20,
		Limited: true, Available: 0}

	if got := s.productCard(plenty); strings.Contains(got, "badge=") {
		t.Errorf("a card anybody can buy carries a ribbon:\n%s", got)
	}
	got := s.productCard(gone)
	if !strings.Contains(got, "badge=Sold out") {
		t.Errorf("a sold-out card has no ribbon:\n%s", got)
	}
	// No colour written at all is how the ribbon asks for the theme's own
	// error colour, which is what a thing nobody can buy should be drawn in
	// -- every theme already has a colour for bad news, and one picked here
	// is that colour for every reader in whatever theme they are using.
	if strings.Contains(got, "badgeink=") {
		t.Errorf("the ribbon overrode the theme's own error colour:\n%s", got)
	}

	// And a seller who names one gets it.
	layout.SoldOutColor = "quoteBar"
	s.layout = layout
	if got := s.productCard(gone); !strings.Contains(got, "badgeink=quoteBar") {
		t.Errorf("the seller's own ribbon colour did not reach the card:\n%s", got)
	}
}

// TestACardCanSayHowManyAreLeft is the other ribbon: not "you cannot have
// this" but "you can, and there are not many".
func TestACardCanSayHowManyAreLeft(t *testing.T) {
	layout := DefaultIndexLayout()
	s := &Store{indexPath: "/", log: slog.Disabled, layout: layout}

	two := &Product{Title: "A guitar", SKU: "gtr", Price: 20,
		Limited: true, Available: 2}

	// Off by default: "2 left" is a nudge, and a shop that has not asked for
	// one should not be making it.
	if got := s.productCard(two); strings.Contains(got, "badge=") {
		t.Errorf("a shop that asked for nothing got a ribbon:\n%s", got)
	}

	layout.LowStockAt = 2
	s.layout = layout
	if got := s.productCard(two); !strings.Contains(got, "badge=2 left") {
		t.Errorf("the card does not say how many are left:\n%s", got)
	}
	if got := s.productCard(two); !strings.Contains(got, "badgeink=text") {
		t.Errorf("the count is not drawn plainly:\n%s", got)
	}

	// Above the threshold, nothing is said.
	three := &Product{Title: "A guitar", SKU: "gtr", Price: 20,
		Limited: true, Available: 3}
	if got := s.productCard(three); strings.Contains(got, "badge=") {
		t.Errorf("a card above the threshold got a ribbon:\n%s", got)
	}

	// A product the shop does not count never gets one, whatever the
	// threshold says.
	free := &Product{Title: "A guitar", SKU: "gtr", Price: 20}
	if got := s.productCard(free); strings.Contains(got, "badge=") {
		t.Errorf("an uncounted product got a count:\n%s", got)
	}
}

// TestUnavailableWinsOverTheCount.
//
// "1 left" on a thing nobody can buy is the worst sentence on the page.
func TestUnavailableWinsOverTheCount(t *testing.T) {
	layout := DefaultIndexLayout()
	layout.LowStockAt = 3
	layout.SoldOutLabel = "Sold out"

	// One left, and a Lightning-only shop whose channels cannot receive what
	// it costs.
	s := &Store{indexPath: "/", log: slog.Disabled, layout: layout,
		check: checkFor(true, 1),
		cfg:   Config{ExchangeRateProvider: func() float64 { return 20 }}}
	one := &Product{Title: "A guitar", SKU: "gtr", Price: 20,
		Limited: true, Available: 1}

	got := s.productCard(one)
	if !strings.Contains(got, "badge=Sold out") {
		t.Errorf("the card urges somebody towards a thing they cannot buy:\n%s", got)
	}
	if strings.Contains(got, "1 left") {
		t.Errorf("the card counts down something nobody can buy:\n%s", got)
	}
}

// TestNothingIsAddedToACartTheShopHasRunOutOf.
//
// The card said so and the button was still there, which is the worst of
// both: somebody who presses it has been told no and shown a way round it.
func TestNothingIsAddedToACartTheShopHasRunOutOf(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 0
	uid := clientintf.UserID{}

	res := answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 1))
	})
	page := string(res.Data)
	if !strings.Contains(page, "run out") {
		t.Errorf("the shop did not say it had run out:\n%s", page)
	}

	// And nothing went in.
	cart := savedCart(t, s, uid)
	if len(cart.Items) != 0 {
		t.Errorf("%d items went into the cart", len(cart.Items))
	}
}

// TestTheCartFlagsWhatWentOutOfStockWhileItSatThere.
func TestTheCartFlagsWhatWentOutOfStockWhileItSatThere(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}

	answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 1))
	})

	// Somebody else takes the last one.
	s.products["r1"].Limited = true
	s.products["r1"].Available = 0

	got := s.cartWithAvailability(savedCart(t, s, uid))
	if !got.Unavailable["r1"] {
		t.Error("the cart does not say the shop has run out of what is in it")
	}
}

// TestPlacingAnOrderTakesTheStock, and refuses when somebody else got there
// first.
func TestPlacingAnOrderTakesTheStock(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 2

	cart := &Cart{Items: []*CartItem{
		{Product: s.products["r1"], Quantity: 2},
	}}
	if short := s.takeStock(cart); len(short) != 0 {
		t.Fatalf("an order the shop could fill was refused: %v", short)
	}
	if s.products["r1"].Available != 0 {
		t.Errorf("stock is %d", s.products["r1"].Available)
	}

	// The same cart again: there are none left.
	short := s.takeStock(cart)
	if len(short) != 1 || short[0] != "A record" {
		t.Fatalf("got %v", short)
	}
	// And nothing was taken on the way to refusing.
	if s.products["r1"].Available != 0 {
		t.Errorf("a refused order moved the stock to %d",
			s.products["r1"].Available)
	}
}

// TestAnOrderCalledOffGivesItBack.
func TestAnOrderCalledOffGivesItBack(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 1

	order := &Order{Cart: Cart{Items: []*CartItem{
		{Product: s.products["r1"], Quantity: 1},
	}}}
	s.takeStock(&order.Cart)
	if s.products["r1"].InStock() {
		t.Fatal("the last one was not taken")
	}

	s.giveStock(order)
	if !s.products["r1"].InStock() {
		t.Error("a called-off order did not give its stock back")
	}
}

// TestStockSurvivesTheShopBeingReloaded: the catalogue in memory is what
// every page is drawn from, so a count that only changed there resets the
// next time anything reloads the shop -- which is every time the seller saves
// a product.
func TestStockSurvivesTheShopBeingReloaded(t *testing.T) {
	s := storeForHandlers(t)
	if err := s.SaveProduct(Product{
		SKU: "r1", Title: "A record", Price: 10,
		Limited: true, Available: 3,
	}, ""); err != nil {
		t.Fatal(err)
	}
	s.products["r1"] = &Product{SKU: "r1", Title: "A record", Price: 10,
		Limited: true, Available: 3}

	s.takeStock(&Cart{Items: []*CartItem{
		{Product: s.products["r1"], Quantity: 1},
	}})

	saved, err := s.ListManagedProducts()
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range saved {
		if p.SKU != "r1" {
			continue
		}
		if !p.Limited || p.Available != 2 {
			t.Errorf("the file says limited=%v available=%d",
				p.Limited, p.Available)
		}
		return
	}
	t.Fatal("the product is not in the catalogue on disk")
}

// jsonRound is a product through the wire and back, so the seller's editor
// and the shop cannot disagree about what a count means.
func TestACountSurvivesTheWire(t *testing.T) {
	in := Product{SKU: "r1", Title: "A record", Limited: true, Available: 4}
	raw, err := json.Marshal(in)
	if err != nil {
		t.Fatal(err)
	}
	var out Product
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatal(err)
	}
	if !out.Limited || out.Available != 4 {
		t.Errorf("came back limited=%v available=%d", out.Limited, out.Available)
	}
	if !strings.Contains(string(raw), `"limited":true`) {
		t.Errorf("the wire does not carry the flag: %s", raw)
	}
}

// TestTheProductPageSaysItOnce.
//
// It had a panel with the words written in it and the same words pinned to
// its corner as a ribbon, drawn on top of each other. The ribbon is for a
// card on the shop front, where there is no room to explain; the page has
// room, so it says what it is and why.
func TestTheProductPageSaysItOnce(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 0

	s.mtx.Lock()
	res, err := s.renderPage(prodTmplFile, s.products["r1"])
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	page := string(res.Data)

	if strings.Contains(page, "badge=") {
		t.Errorf("the product page draws the ribbon over its own words:\n%s", page)
	}
	if strings.Count(page, "Currently unavailable") != 1 {
		t.Errorf("the page says it %d times:\n%s",
			strings.Count(page, "Currently unavailable"), page)
	}
	if !strings.Contains(page, "The shop has run out of this.") {
		t.Errorf("the page does not say why:\n%s", page)
	}
	// And no way to add it to a cart.
	if strings.Contains(page, "/addToCart") {
		t.Errorf("a sold-out product can still be added to a cart:\n%s", page)
	}
}

// TestTheProductPageCountsDownBesideTheTitle.
//
// It was a row of its own under the price, which put a fact about whether you
// can have this thing three paragraphs away from the thing.
func TestTheProductPageCountsDownBesideTheTitle(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 2

	s.mtx.Lock()
	res, err := s.renderPage(prodTmplFile, s.products["r1"])
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	page := string(res.Data)
	if !strings.Contains(page, "--steps[chip=2 left") {
		t.Errorf("the count is not beside the title:\n%s", page)
	}
	if !strings.Contains(page, "chipink=quoteBar") {
		t.Errorf("the count is not boxed like the panel below it:\n%s", page)
	}
	if !strings.Contains(page, "/addToCart") {
		t.Errorf("a product that is still for sale cannot be bought:\n%s", page)
	}
	// The title is inside the block, not a heading of its own as well.
	if strings.Contains(page, "# A record") {
		t.Errorf("the title is drawn twice:\n%s", page)
	}
}

// TestAProductWithNoneLeftSaysSoOnce.
//
// "0 left" beside "Currently unavailable" is the page saying it twice.
func TestAProductWithNoneLeftSaysSoOnce(t *testing.T) {
	s := storeForHandlers(t)
	s.products["r1"].Limited = true
	s.products["r1"].Available = 0

	s.mtx.Lock()
	res, err := s.renderPage(prodTmplFile, s.products["r1"])
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	page := string(res.Data)
	if strings.Contains(page, "chip=") {
		t.Errorf("a product with none left still counts them:\n%s", page)
	}
	if !strings.Contains(page, "# A record") {
		t.Errorf("the page lost its title:\n%s", page)
	}
	if got := stockLeft(s.products["r1"]); got != "" {
		t.Errorf("stockLeft says %q about nothing left", got)
	}
}

// TestAnUncountedProductNeverCountsAnything.
func TestAnUncountedProductNeverCountsAnything(t *testing.T) {
	s := storeForHandlers(t)

	s.mtx.Lock()
	res, err := s.renderPage(prodTmplFile, s.products["r1"])
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if page := string(res.Data); strings.Contains(page, "chip=") {
		t.Errorf("a product the shop does not count carries a count:\n%s", page)
	}
}
