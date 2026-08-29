package simplestore

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/rpc"
)

// orderlist_test.go covers the two lists of orders: a buyer's own and a
// seller's whole book.
//
// The thing worth pinning is that neither of them is a diary. An unpaid order
// at the bottom of a long page is an unpaid order nobody pays, so whatever
// wants the reader comes first whichever way the rest is sorted -- and what
// "wants the reader" means is not the same on the two pages.

func orderAt(id uint32, when time.Time, status OrderStatus) *Order {
	return &Order{
		ID: OrderID(id), Status: status, PlacedTS: when,
		ExpiresTS: when.Add(quoteHoldsFor),
		Cart: Cart{Items: []*CartItem{
			{Product: &Product{SKU: "r1", Title: "A record", Price: 10},
				Quantity: 1},
		}},
	}
}

func TestWhoAnOrderIsWaitingOn(t *testing.T) {
	now := time.Now()
	seen := now

	tests := []struct {
		name         string
		order        *Order
		buyer, sells bool
	}{{
		name:  "waiting to be paid",
		order: orderAt(1, now, StatusPlaced),
		buyer: true,
	}, {
		// The money is on its way and the network is taking its time. There
		// is nothing either of them can do, so it wants nobody.
		name: "payment seen",
		order: func() *Order {
			o := orderAt(1, now, StatusPlaced)
			o.SeenTS = &seen
			return o
		}(),
	}, {
		name:  "paid and not sent",
		order: orderAt(1, now, StatusPaid),
		sells: true,
	}, {
		name:  "on its way",
		order: orderAt(1, now, StatusShipped),
	}, {
		name:  "finished",
		order: orderAt(1, now, StatusCompleted),
	}, {
		name:  "called off",
		order: orderAt(1, now, StatusCanceled),
	}, {
		// The last word was the buyer's, so it is the seller's turn.
		name: "the buyer asked something",
		order: func() *Order {
			o := orderAt(1, now, StatusShipped)
			o.Comments = []OrderComment{{Comment: "where is it?"}}
			return o
		}(),
		sells: true,
	}}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.order.Wants(false); got != tc.buyer {
				t.Errorf("wants the buyer: got %v, want %v", got, tc.buyer)
			}
			if got := tc.order.Wants(true); got != tc.sells {
				t.Errorf("wants the seller: got %v, want %v", got, tc.sells)
			}
		})
	}
}

// TestWhatWantsYouComesFirst, whichever way the rest is sorted.
func TestWhatWantsYouComesFirst(t *testing.T) {
	now := time.Now()
	old := orderAt(1, now.Add(-3*time.Hour), StatusPlaced)  // wants the buyer
	mid := orderAt(2, now.Add(-2*time.Hour), StatusShipped) // wants nobody
	fresh := orderAt(3, now.Add(-time.Hour), StatusCompleted)

	for _, order := range []OrderSort{SortNewest, SortOldest} {
		list := []*Order{mid, fresh, old}
		orderView{Show: ShowAll, Sort: order}.arrange(list, false)
		if list[0] != old {
			t.Errorf("%s: the unpaid order is not at the top", order)
		}
	}

	// And under that, the chosen order holds.
	list := []*Order{mid, fresh, old}
	orderView{Show: ShowAll, Sort: SortNewest}.arrange(list, false)
	if list[1] != fresh || list[2] != mid {
		t.Errorf("newest first did not hold under the pinned one")
	}

	list = []*Order{mid, fresh, old}
	orderView{Show: ShowAll, Sort: SortOldest}.arrange(list, false)
	if list[1] != mid || list[2] != fresh {
		t.Errorf("oldest first did not hold under the pinned one")
	}
}

func TestWhichOrdersAFilterShows(t *testing.T) {
	now := time.Now()
	placed := orderAt(1, now, StatusPlaced)
	paid := orderAt(2, now, StatusPaid)
	done := orderAt(3, now, StatusCompleted)
	off := orderAt(4, now, StatusCanceled)
	put := orderAt(5, now, StatusCanceled)
	put.Hidden = true

	all := []*Order{placed, paid, done, off, put}
	shown := func(show OrderShow) []uint32 {
		var out []uint32
		for _, o := range all {
			if (orderView{Show: show}).shows(o) {
				out = append(out, o.ID.Num())
			}
		}
		return out
	}

	same := func(got []uint32, want ...uint32) bool {
		if len(got) != len(want) {
			return false
		}
		for i := range got {
			if got[i] != want[i] {
				return false
			}
		}
		return true
	}

	// Open is the default, and hidden orders are not in it -- they are
	// cancelled, which is the only status one can have.
	if got := shown(ShowOpen); !same(got, 1, 2) {
		t.Errorf("open shows %v", got)
	}
	if got := shown(ShowWaiting); !same(got, 1) {
		t.Errorf("waiting shows %v", got)
	}
	if got := shown(ShowPaid); !same(got, 2, 3) {
		t.Errorf("paid shows %v", got)
	}
	if got := shown(ShowCancelled); !same(got, 4, 5) {
		t.Errorf("called off shows %v", got)
	}
	if got := shown(ShowAll); !same(got, 1, 2, 3, 4, 5) {
		t.Errorf("all shows %v", got)
	}
}

// TestAFilterKeepsTheOtherHalf.
//
// Each link changes one half of the view and keeps the other: pressing
// "Oldest first" must not also reset which orders are being shown.
func TestAFilterKeepsTheOtherHalf(t *testing.T) {
	view := parseOrderView([]string{"cancelled", "oldest"})
	if view.Show != ShowCancelled || view.Sort != SortOldest {
		t.Fatalf("read %+v", view)
	}

	// In either order, and with either missing.
	if got := parseOrderView([]string{"oldest", "paid"}); got != view.pair(ShowPaid, SortOldest) {
		t.Errorf("read %+v", got)
	}
	if got := parseOrderView([]string{"paid"}); got.Sort != SortNewest {
		t.Errorf("a path with no order lost the default: %+v", got)
	}
	if got := parseOrderView(nil); got.Show != ShowOpen || got.Sort != SortNewest {
		t.Errorf("an empty path is not the defaults: %+v", got)
	}
	// And a word nobody wrote changes nothing.
	if got := parseOrderView([]string{"sideways"}); got.Show != ShowOpen {
		t.Errorf("a word nobody wrote was taken as a filter: %+v", got)
	}
}

// TestTheFilterRowKeepsWhatItIsNotChanging.
func TestTheFilterRowKeepsWhatItIsNotChanging(t *testing.T) {
	c := ordersContext{
		View:   orderView{Show: ShowCancelled, Sort: SortOldest},
		Prefix: "/orders",
	}

	for _, f := range c.Filters() {
		if !strings.HasSuffix(f.Link, "/oldest") {
			t.Errorf("%q loses which end is the top: %s", f.Label, f.Link)
		}
	}
	for _, o := range c.Orderings() {
		if !strings.Contains(o.Link, "/cancelled/") {
			t.Errorf("%q loses what is being shown: %s", o.Label, o.Link)
		}
	}

	// And the current one is marked.
	marked := 0
	for _, f := range c.Filters() {
		if f.On {
			marked++
		}
	}
	if marked != 1 {
		t.Errorf("%d filters are marked as current", marked)
	}
}

// TestACalledOffOrderCanBePutAway.
//
// Away rather than gone: there is one copy of an order and it lives in the
// seller's store, and an order's number is the last one on disk plus one --
// so removing the newest would hand the next order a number already used.
func TestACalledOffOrderCanBePutAway(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}
	dir := filepath.Join(s.root, ordersDir, uid.String())

	order := orderAt(1, time.Now(), StatusCanceled)
	order.User = uid
	writeOrder(t, s, dir, order)

	res := answers(t, "hideOrder", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleHideOrder(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"hideOrder", order.ID.String()}})
	})
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("status %d: %s", res.Status, res.Data)
	}

	var saved Order
	if err := jsonfile.Read(
		filepath.Join(dir, orderFnamePattern.FilenameFor(1)), &saved); err != nil {
		t.Fatal(err)
	}
	if !saved.Hidden {
		t.Error("the order was not put away")
	}
	// Still on the shelf: hiding is not deleting.
	if saved.Status != StatusCanceled || saved.ID.Num() != 1 {
		t.Errorf("hiding changed the order: %+v", saved)
	}
}

// TestAnOrderStillGoingCannotBePutAway: it is the thing the list exists to
// surface.
func TestAnOrderStillGoingCannotBePutAway(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}
	dir := filepath.Join(s.root, ordersDir, uid.String())

	order := orderAt(1, time.Now(), StatusPlaced)
	order.User = uid
	writeOrder(t, s, dir, order)

	answers(t, "hideOrder", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleHideOrder(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"hideOrder", order.ID.String()}})
	})

	var saved Order
	if err := jsonfile.Read(
		filepath.Join(dir, orderFnamePattern.FilenameFor(1)), &saved); err != nil {
		t.Fatal(err)
	}
	if saved.Hidden {
		t.Error("an order still going was put away")
	}
}

// TestTheBarCountsWhatIsWaitingOnYou.
//
// An order waiting to be paid is the one thing in this shop with a clock on
// it: a buyer who has to open Orders to find out whether one is running out
// finds out afterwards.
func TestTheBarCountsWhatIsWaitingOnYou(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}
	dir := filepath.Join(s.root, ordersDir, uid.String())

	if got := s.ordersWanting(uid); got != 0 {
		t.Errorf("an empty shop wants %d", got)
	}

	writeOrder(t, s, dir, func() *Order {
		o := orderAt(1, time.Now(), StatusPlaced)
		o.User = uid
		return o
	}())
	writeOrder(t, s, dir, func() *Order {
		o := orderAt(2, time.Now(), StatusCompleted)
		o.User = uid
		return o
	}())

	if got := s.ordersWanting(uid); got != 1 {
		t.Errorf("got %d, want 1", got)
	}
}

func writeOrder(t *testing.T, s *Store, dir string, order *Order) {
	t.Helper()
	if err := jsonfile.Write(
		filepath.Join(dir, orderFnamePattern.FilenameFor(uint64(order.ID.Num()))),
		order, s.log); err != nil {
		t.Fatal(err)
	}
}

// TestTheDashboardPointsAtTheOrdersItIsTalkingAbout.
//
// It said "open the order book" and led to the whole book, unfiltered: a
// seller told fifteen orders are waiting was handed every order they have
// ever taken and left to find them.
func TestTheDashboardPointsAtTheOrdersItIsTalkingAbout(t *testing.T) {
	s := shopTaking(t, PayTypeLN)

	s.mtx.Lock()
	res, err := s.renderPage("admin.tmpl", &adminIndexContext{
		Total: 20, ToSend: 15, NeedsReply: 2, Lapsed: 3,
		Recent: []ManagedOrder{{
			Order:    *orderAt(1, time.Now(), StatusPaid),
			UserNick: "ada",
		}},
	})
	s.mtx.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	page := string(res.Data)

	for _, want := range []string{
		"[15 paid and not sent yet](/admin/orders/paid/newest)",
		"](/admin/orders/open/newest)",
		"](/admin/orders/waiting/oldest)",
		"[Open the order book](/admin/orders)",
	} {
		if !strings.Contains(page, want) {
			t.Errorf("the dashboard is missing %q:\n%s", want, page)
		}
	}

	// And its rows are the ones the order book draws, not a plainer copy.
	if !strings.Contains(page, "badge=Needs you") {
		t.Errorf("a paid order is not marked as wanting the seller:\n%s", page)
	}
}
