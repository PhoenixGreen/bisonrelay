package simplestore

import (
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
)

type indexContext struct {
	Products map[string]*Product
	IsAdmin  bool
}

// cartContext is a cart together with what is wrong with it.
//
// Unavailable names the lines whose product the shop no longer sells --
// disabled, or deleted since it went in. A cart may hold one for as long as
// the buyer leaves it there, and placing the order is where that used to be
// discovered: the whole order was refused with a bare "bad request", naming
// a SKU the buyer has never seen, with nothing on the page to act on.
type cartContext struct {
	*Cart
	Unavailable map[string]bool
}

// HasUnavailable is whether anything in the cart cannot be bought, which is
// what decides whether the page offers to order at all.
func (c cartContext) HasUnavailable() bool { return len(c.Unavailable) > 0 }

type orderContext struct {
	Order
}

type ordersContext struct {
	Orders []*Order
}

type adminOrderSummary struct {
	ID       OrderID
	User     clientintf.UserID
	UserNick string
	Status   OrderStatus
	PlacedTS time.Time
}

type adminOrdersContext struct {
	Orders []adminOrderSummary
}

type adminOrderContext struct {
	Order    Order
	UserNick string
}
