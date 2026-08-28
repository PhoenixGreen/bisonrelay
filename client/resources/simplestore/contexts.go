package simplestore

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

	// Methods is what the shop will take, so the cart can offer the choice
	// when there is one to offer -- and say what it costs in DCR, which is
	// the number a buyer is actually about to part with.
	Methods  PayMethods
	TotalDCR string
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

// adminOrdersContext is the seller's order book.
//
// The whole order rather than a summary of it. A summary was five fields
// copied out by hand, and every question the page learned to ask -- what it
// came to, whose turn it is to say something, whether the amount it was
// quoted at still holds -- meant copying out another. The order answers all
// of them, and ManagedOrder is the order with the buyer's nick beside it.
type adminOrdersContext struct {
	Orders []ManagedOrder
}

// adminIndexContext is the shop's front desk: what is waiting, what has been
// taken, and the last few orders.
//
// Counted here rather than in the template, because a template counting
// orders by status is four range loops and a set of variables, and what the
// page is for is being read at a glance.
type adminIndexContext struct {
	// Waiting is what has somebody's attention on it: orders not yet paid,
	// orders paid and not sent, and orders whose last word was the buyer's.
	Unpaid     int
	ToSend     int
	NeedsReply int

	// Lapsed is unpaid orders whose quoted amount no longer holds. They are
	// not going to pay themselves, and the seller is the only one who can
	// offer to place them again.
	Lapsed int

	// Counts by status, for the shop as a whole.
	Placed    int
	Paid      int
	Shipped   int
	Completed int
	Canceled  int
	Total     int

	// Taken is what the orders that have been paid for come to, and Pending
	// what the unpaid ones would come to.
	Taken   float64
	Pending float64

	// Recent is the newest few orders, so the page is a page rather than a
	// set of numbers.
	Recent []ManagedOrder
}

type adminOrderContext struct {
	Order    Order
	UserNick string
}
