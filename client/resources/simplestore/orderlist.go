package simplestore

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/rpc"
)

// orderlist.go is a list of orders somebody is looking through.
//
// One list, two readers. A buyer's own orders and a seller's whole order book
// are the same rows asking the same questions -- which of these needs
// something from me, what happened to the rest, and where is the one I am
// thinking of -- so they are sorted and filtered by the same code.
//
// The default is not "newest first". It is "whatever needs you first, then
// newest", because a list of orders is not a diary: an unpaid order at the
// bottom of a long page is an unpaid order nobody pays.

// OrderShow is which orders a list is showing.
type OrderShow string

const (
	// ShowOpen is everything still going: not finished and not called off.
	// The default, because a list nobody has filtered should be the things
	// that are still true.
	ShowOpen OrderShow = "open"

	// ShowAll is every order, hidden ones included.
	ShowAll OrderShow = "all"

	ShowWaiting   OrderShow = "waiting"
	ShowPaid      OrderShow = "paid"
	ShowCancelled OrderShow = "cancelled"
)

// OrderSort is which end of the list is the top.
type OrderSort string

const (
	SortNewest OrderSort = "newest"
	SortOldest OrderSort = "oldest"
)

// orderView is what a list was asked for.
type orderView struct {
	Show OrderShow
	Sort OrderSort
}

// parseOrderView reads the two words out of a path, in either order and with
// either missing.
//
// Either missing because the links are built one at a time: pressing
// "Oldest first" keeps whatever was being shown, and pressing "Cancelled"
// keeps which end was the top. A path that has to carry both in a fixed
// order is a path every link has to know the whole of.
func parseOrderView(rest []string) orderView {
	view := orderView{Show: ShowOpen, Sort: SortNewest}
	for _, word := range rest {
		switch OrderShow(strings.ToLower(word)) {
		case ShowOpen:
			view.Show = ShowOpen
			continue
		case ShowAll:
			view.Show = ShowAll
			continue
		case ShowWaiting:
			view.Show = ShowWaiting
			continue
		case ShowPaid:
			view.Show = ShowPaid
			continue
		case ShowCancelled:
			view.Show = ShowCancelled
			continue
		}
		switch OrderSort(strings.ToLower(word)) {
		case SortOldest:
			view.Sort = SortOldest
		case SortNewest:
			view.Sort = SortNewest
		}
	}
	return view
}

// path is this view written back out, for the links that change one half of
// it and keep the other.
func (v orderView) path(prefix string, show OrderShow, order OrderSort) string {
	return fmt.Sprintf("%s/%s/%s", prefix, show, order)
}

// pair is a view with both halves said, for a test to compare against.
func (v orderView) pair(show OrderShow, order OrderSort) orderView {
	return orderView{Show: show, Sort: order}
}

// shows is whether an order belongs in this view.
func (v orderView) shows(order *Order) bool {
	switch v.Show {
	case ShowAll:
		return true
	case ShowWaiting:
		return order.AwaitingPayment()
	case ShowPaid:
		return order.Status == StatusPaid || order.Status == StatusShipped ||
			order.Status == StatusCompleted
	case ShowCancelled:
		return order.Status == StatusCanceled
	default:
		// Open, and nothing the reader has put away. Hidden orders are still
		// there under Cancelled, which is the only status one can have.
		return order.Open() && !order.Hidden
	}
}

// arrange puts a list in the order it should be read.
//
// Whatever needs the reader comes first whichever way the rest is sorted,
// because that is not a sorting question: it is the reason somebody opened
// the page. Under that, the chosen order.
func (v orderView) arrange(orders []*Order, seller bool) {
	sort.SliceStable(orders, func(i, j int) bool {
		a, b := orders[i], orders[j]
		if wa, wb := a.Wants(seller), b.Wants(seller); wa != wb {
			return wa
		}
		if v.Sort == SortOldest {
			return a.PlacedTS.Before(b.PlacedTS)
		}
		return a.PlacedTS.After(b.PlacedTS)
	})
}

// Wants is whether this order is waiting on the person reading it.
//
// Two different questions with one name. A buyer is wanted by an order that
// has not been paid for; a seller is wanted by one that has been paid for and
// not yet sent, and by one whose last word was the buyer's. An order that
// wants nobody is a record.
func (order *Order) Wants(seller bool) bool {
	if !order.Open() {
		return false
	}
	if seller {
		return order.Status == StatusPaid || order.AwaitingSeller()
	}
	return order.AwaitingPayment() && !order.PaymentSeen()
}

// readOrders is every order in a directory.
func (s *Store) readOrders(dir string) ([]*Order, error) {
	files, err := os.ReadDir(dir)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}

	var orders []*Order
	for _, file := range files {
		if file.IsDir() {
			continue
		}
		order := &Order{}
		fname := filepath.Join(dir, file.Name())
		if err := jsonfile.Read(fname, order); err != nil {
			s.log.Warnf("Unable to read order %s: %v", fname, err)
			continue
		}
		orders = append(orders, order)
	}
	return orders, nil
}

// handleHideOrder puts a called-off order away.
//
// Away rather than gone, and the difference matters here more than it usually
// does. There is one copy of an order and it lives in the seller's store --
// the buyer is reading the seller's records, not their own -- so a buyer's
// delete button would delete somebody else's books. And an order's number is
// the last one on disk plus one, so removing the newest would hand the next
// order a number that has already been used, in messages and in the metadata
// on every file this shop has sent.
//
// So it is hidden: out of the list, still on the shelf, and still there under
// Cancelled for whoever wants to look.
func (s *Store) handleHideOrder(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	var oid OrderID
	if err := oid.FromString(request.Path[1]); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("invalid order id"),
		}, nil
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	order, fname, err := s.loadOrderLocked(uid, oid)
	if err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("order not found"),
		}, nil
	}

	// Only one that is over. An order still going is one the reader has
	// something to do about, and putting it away would be hiding the thing
	// the list exists to surface.
	if order.Open() {
		return s.renderPage(orderTmplFile, &orderContext{Order: *order})
	}

	order.Hidden = true
	if err := jsonfile.Write(fname, order, s.log); err != nil {
		return nil, err
	}
	return s.ordersPage(uid, orderView{Show: ShowOpen, Sort: SortNewest})
}

// ordersPage draws a buyer's own list. The caller holds the lock.
func (s *Store) ordersPage(uid clientintf.UserID, view orderView) (*rpc.RMFetchResourceReply, error) {
	orders, err := s.readOrders(filepath.Join(s.root, ordersDir, uid.String()))
	if err != nil {
		return nil, err
	}

	kept := orders[:0]
	for _, order := range orders {
		if view.shows(order) {
			kept = append(kept, order)
		}
	}
	view.arrange(kept, false)

	return s.renderPage(ordersTmplFile, &ordersContext{
		Orders: kept,
		View:   view,
		Prefix: "/orders",
	})
}
