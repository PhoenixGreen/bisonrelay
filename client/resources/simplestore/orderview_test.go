package simplestore

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"text/template"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// orderview_test.go covers the four pages an order appears on, and the
// questions they ask of it.
//
// The one that matters most is the first: an order's own page never showed
// how to pay it. The invoice went out once, on the page that said the order
// was placed, and a buyer who closed that page had no way back to it -- the
// order said "placed" and offered nothing to act on, while the invoice sat in
// a file only the shop reads.

func renderOrderPage(t *testing.T, name string, data any) string {
	t.Helper()
	s := &Store{indexPath: "/store", log: slog.Disabled,
		layout: DefaultIndexLayout()}

	raw, err := storeTemplate.ReadFile("template/" + name)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := template.New(name).Funcs(s.templateFuncs())
	// The order pages include the plain cart listing.
	if plain, err := storeTemplate.ReadFile("template/cart-listing-plain.tmpl"); err == nil {
		if _, err := tmpl.New("cart-listing-plain.tmpl").Parse(string(plain)); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := tmpl.Parse(string(raw)); err != nil {
		t.Fatalf("%s: %v", name, err)
	}

	var out bytes.Buffer
	if err := tmpl.ExecuteTemplate(&out, name, data); err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	return out.String()
}

func anOrder() Order {
	return Order{
		ID:           3,
		Status:       StatusPlaced,
		PlacedTS:     time.Now().Add(-10 * time.Minute),
		ExpiresTS:    time.Now().Add(42 * time.Minute),
		ExchangeRate: 25,
		PayType:      PayTypeLN,
		Invoice:      "lnabc123",
		Cart: Cart{Items: []*CartItem{
			{Product: &Product{Title: "A guitar", SKU: "gtr", Image: "g.jpg",
				Price: 20}, Quantity: 2},
		}},
	}
}

func TestAnUnpaidOrderSaysHowToPayIt(t *testing.T) {
	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: anOrder()})

	for _, want := range []string{"lnpay://lnabc123", "$40.00", "42 minutes"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the order's own page:\n%s", want, got)
		}
	}
}

func TestAPaidOrderDoesNotAskForMoneyAgain(t *testing.T) {
	order := anOrder()
	order.Status = StatusPaid
	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: order})

	if strings.Contains(got, "lnpay://") {
		t.Errorf("a paid order is still asking to be paid:\n%s", got)
	}
	if !strings.Contains(got, "the seller is preparing it") {
		t.Errorf("the status is not said in words:\n%s", got)
	}
}

func TestALapsedQuoteSaysSoRatherThanOfferingIt(t *testing.T) {
	// The rate is struck when the order is placed and held for an hour.
	// After that the invoice is stale, and a buyer paying it is paying
	// yesterday's price for today's coin.
	order := anOrder()
	order.ExpiresTS = time.Now().Add(-time.Minute)

	if !order.Expired() {
		t.Fatal("an order past its hour is not expired")
	}
	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: order})
	if strings.Contains(got, "lnpay://") {
		t.Errorf("a lapsed quote is still being offered:\n%s", got)
	}
	if !strings.Contains(got, "no longer holds") {
		t.Errorf("nothing says why there is no way to pay:\n%s", got)
	}
}

// TestABuyerCanCallOffAnUnpaidOrder covers the one thing a buyer could not
// do about an order they had thought better of.
//
// Called off rather than deleted: the record is on the seller's disk and is
// the seller's book. What was missing is the buyer being able to say so --
// an unpaid order sat there indistinguishable from one about to be paid, and
// only the seller could clear it.
func TestABuyerCanCallOffAnUnpaidOrder(t *testing.T) {
	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: anOrder()})

	if !strings.Contains(got, `value="/cancelOrder/`) {
		t.Errorf("an unpaid order cannot be called off:\n%s", got)
	}
	for _, want := range []string{
		`style="danger"`, "Nothing has been charged", "the seller is told",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the way it asks:\n%s", want, got)
		}
	}
}

func TestAPaidOrderCannotBeCalledOffByTheBuyer(t *testing.T) {
	// A paid order is a refund, which is a conversation -- and the thread on
	// the order page is where that belongs.
	order := anOrder()
	order.Status = StatusPaid

	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: order})
	if strings.Contains(got, "/cancelOrder/") {
		t.Errorf("a paid order offers to call itself off:\n%s", got)
	}
}

func TestACalledOffOrderStaysInTheList(t *testing.T) {
	// Marked rather than vanished. An order that disappears from the list is
	// a buyer wondering what became of it, which is a worse question than
	// the one a greyed row answers.
	order := anOrder()
	order.Status = StatusCanceled

	got := renderOrderPage(t, "orders.tmpl",
		&ordersContext{Orders: []*Order{&order}})
	if !strings.Contains(got, "Canceled") {
		t.Errorf("a called-off order is not in the list:\n%s", got)
	}
	if strings.Contains(got, "style: primary") {
		t.Errorf("a called-off order is still offered as something to do:\n%s",
			got)
	}
}

// TestCallingOffTwiceSaysWhatActuallyHappened covers the answer to pressing
// it again -- or pressing it as the payment lands.
//
// The first version of this answered every one of those with "this order has
// been paid for", which for an order the buyer had just called off is a
// sentence that would send anybody looking for their money.
func TestCallingOffTwiceSaysWhatActuallyHappened(t *testing.T) {
	root := t.TempDir()
	var uid clientintf.UserID
	uid[0] = 1
	dir := filepath.Join(root, ordersDir, uid.String())
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	fname := filepath.Join(dir, orderFnamePattern.FilenameFor(3))
	s := &Store{root: root, log: slog.Disabled, layout: DefaultIndexLayout()}

	cases := []struct {
		status OrderStatus
		says   string
	}{
		{StatusCanceled, "already been called off"},
		{StatusCompleted, "is finished"},
		{StatusPaid, "has been paid for"},
		{StatusShipped, "has been paid for"},
	}
	for _, c := range cases {
		order := anOrder()
		order.User = uid
		order.Status = c.status
		if err := jsonfile.Write(fname, &order, slog.Disabled); err != nil {
			t.Fatal(err)
		}

		res, err := s.handleCancelOrder(t.Context(), uid,
			&rpc.RMFetchResource{Path: []string{"cancelOrder", "3"}})
		if err != nil {
			t.Fatal(err)
		}
		if !strings.Contains(string(res.Data), c.says) {
			t.Errorf("%s: wanted %q, got:\n%s", c.status, c.says, res.Data)
		}
	}
}

func TestAnOrderIsNumberedTheWayItWouldBeSaid(t *testing.T) {
	// String pads to eight digits, which is what an order's file is called.
	// On a page it reads as a serial number from a machine.
	got := renderOrderPage(t, "order.tmpl", &orderContext{Order: anOrder()})
	if !strings.Contains(got, "# Order #3") {
		t.Errorf("the order is not numbered 3:\n%s", got)
	}
}

func TestTheOrderListSaysWhatIsWaiting(t *testing.T) {
	answered := anOrder()
	answered.Comments = []OrderComment{
		{Timestamp: time.Now(), FromAdmin: true, Comment: "Tomorrow"},
	}
	got := renderOrderPage(t, "orders.tmpl",
		&ordersContext{Orders: []*Order{&answered}})

	for _, want := range []string{"the seller has replied", "button: Pay"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the order list:\n%s", want, got)
		}
	}
}

// TestCancellingAnOrderAsksFirst covers the one on this page that cannot be
// undone.
//
// It was a bare link, sitting beside the two ordinary ones: a stray tap
// canceled a buyer's order, told them so, and left nothing to put it back.
func TestCancellingAnOrderAsksFirst(t *testing.T) {
	got := renderOrderPage(t, "admin_order.tmpl",
		&adminOrderContext{Order: anOrder(), UserNick: "karamble"})

	if strings.Contains(got, "](/admin/orderstatusto/") {
		t.Errorf("a status change is still a bare link:\n%s", got)
	}
	for _, want := range []string{
		`label="Cancel this order" style="danger"`,
		"there is no undo",
		`label="Mark as shipped" style="primary"`,
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the seller's order page:\n%s", want, got)
		}
	}
}

func TestTheSellersOrderPageSaysWhatItIsWorth(t *testing.T) {
	got := renderOrderPage(t, "admin_order.tmpl",
		&adminOrderContext{Order: anOrder(), UserNick: "karamble"})

	for _, want := range []string{"karamble", "$40.00", "gtr", "lnabc123"} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the seller's order page:\n%s", want, got)
		}
	}
}

func TestAFinishedOrderIsNotOfferedMoreStatuses(t *testing.T) {
	order := anOrder()
	order.Status = StatusCompleted

	got := renderOrderPage(t, "admin_order.tmpl",
		&adminOrderContext{Order: order, UserNick: "karamble"})
	if strings.Contains(got, "Cancel this order") {
		t.Errorf("a finished order can still be canceled:\n%s", got)
	}
}

func TestTheFrontDeskSaysWhatIsWaiting(t *testing.T) {
	got := renderOrderPage(t, "admin.tmpl", &adminIndexContext{
		Total: 3, ToSend: 1, NeedsReply: 2, Lapsed: 1,
		Paid: 1, Completed: 2, Taken: 120, Pending: 40, Unpaid: 1,
	})

	for _, want := range []string{
		"Waiting on you", "paid and not sent", "waiting on a reply",
		"$120.00", "$40.00",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("%q missing from the front desk:\n%s", want, got)
		}
	}
}

func TestAQuietShopSaysSoRatherThanShowingNoughts(t *testing.T) {
	got := renderOrderPage(t, "admin.tmpl", &adminIndexContext{})
	if !strings.Contains(got, "Nobody has ordered anything yet") {
		t.Errorf("a shop with no orders shows a page of noughts:\n%s", got)
	}
	if strings.Contains(got, "$0.00") {
		t.Errorf("a shop with no orders is being told what it has taken:\n%s", got)
	}
}

func TestNothingWaitingSaysThatToo(t *testing.T) {
	// A seller opening this wants an answer either way. A panel that is
	// there when there is something and gone when there is not leaves them
	// wondering whether it failed to load.
	got := renderOrderPage(t, "admin.tmpl", &adminIndexContext{
		Total: 2, Completed: 2, Taken: 60,
	})
	if !strings.Contains(got, "Nothing is waiting on you") {
		t.Errorf("a shop with nothing waiting says nothing:\n%s", got)
	}
}

func TestWhoseTurnItIsToSpeak(t *testing.T) {
	order := anOrder()
	if order.AwaitingSeller() || order.SellerReplied() {
		t.Error("an order nobody has written on is waiting on somebody")
	}

	order.Comments = []OrderComment{{Comment: "when?"}}
	if !order.AwaitingSeller() || order.SellerReplied() {
		t.Error("a buyer's question is not waiting on the seller")
	}

	order.Comments = append(order.Comments,
		OrderComment{FromAdmin: true, Comment: "tomorrow"})
	if order.AwaitingSeller() || !order.SellerReplied() {
		t.Error("the seller's answer left it still their turn")
	}
}
