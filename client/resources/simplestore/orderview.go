package simplestore

import (
	"fmt"
	"time"
)

// orderview.go is what an order's pages need to know about it that the order
// itself does not say.
//
// Methods on Order rather than fields worked out in a handler, because there
// are four pages showing an order -- the buyer's list, the buyer's own page,
// the seller's list, the seller's page -- and a fact computed in one handler
// is a fact the other three do without. A template asks the order.
//
// None of it is new information. It is the order's own fields read the way
// somebody looking at the page would read them: is this paid for, how long is
// the price good for, whose turn is it to say something.

// AwaitingPayment is whether this order is still waiting to be paid for.
//
// Placed and nothing further: the shop moves an order to paid on its own when
// the payment lands, and every state after that has been paid for.
func (order *Order) AwaitingPayment() bool {
	return order.Status == StatusPlaced
}

// Open is whether this order is still going: not finished, not called off.
func (order *Order) Open() bool {
	return order.Status != StatusCompleted && order.Status != StatusCanceled
}

// PayURI is what a buyer pays with, or empty for an order with nothing to
// pay.
//
// The same thing the confirmation page shows when an order is placed, which
// until now was the only place it was ever shown. A buyer who closed that
// page had no way back to it: the order said "placed" and offered nothing to
// act on, and the invoice was in a file only the shop reads.
func (order *Order) PayURI() string {
	// Nothing to offer once the quote has lapsed. The invoice is still
	// there and still payable, and paying it would be paying yesterday's
	// price for today's coin -- so the page says the amount no longer holds
	// rather than handing over a way to act on it.
	if !order.AwaitingPayment() || order.Invoice == "" || order.Expired() {
		return ""
	}
	if order.PayType == PayTypeLN {
		return "lnpay://" + order.Invoice
	}
	return order.Invoice
}

// Expired is whether the amount this order was quoted at no longer holds.
//
// The rate is struck when the order is placed and held for an hour. After
// that the invoice is stale, and a buyer paying it is paying yesterday's
// price for today's coin -- which is why the shop says so rather than
// quietly letting it lapse.
func (order *Order) Expired() bool {
	return order.AwaitingPayment() && !order.ExpiresTS.IsZero() &&
		time.Now().After(order.ExpiresTS)
}

// ExpiresIn is how long the quoted amount holds for, in words, or empty when
// there is nothing waiting on a clock.
func (order *Order) ExpiresIn() string {
	if !order.AwaitingPayment() || order.ExpiresTS.IsZero() || order.Expired() {
		return ""
	}
	return roughly(time.Until(order.ExpiresTS))
}

// SellerReplied is whether the last thing said about this order was said by
// the seller.
//
// Which is as close to "unread" as this can honestly get: nothing records
// what a buyer has looked at. It is still the useful half of the question --
// a buyer scanning their orders wants to know which ones have been answered.
func (order *Order) SellerReplied() bool {
	return len(order.Comments) > 0 &&
		order.Comments[len(order.Comments)-1].FromAdmin
}

// AwaitingSeller is the same question from the other end: the last word was
// the buyer's, so it is the seller's turn.
func (order *Order) AwaitingSeller() bool {
	return len(order.Comments) > 0 &&
		!order.Comments[len(order.Comments)-1].FromAdmin
}

// Lines is how many lines the order has, for a summary that would rather not
// list them.
func (order *Order) Lines() int { return len(order.Cart.Items) }

// FirstImage is the picture of the first thing in the order, as a path a page
// can show, or empty for an order of things with no pictures.
//
// One picture rather than all of them: a row in a list is a row, and the
// first thing in the order is what somebody recognises it by.
func (order *Order) FirstImage() string {
	for _, item := range order.Cart.Items {
		if item.Product != nil && item.Product.Image != "" {
			return ProductImagePath(item.Product.Image)
		}
	}
	return ""
}

// orderStatusSays is what a status means, in words.
//
// The bare word is what the shop stores and what an older template prints,
// and it answers a different question from the one a buyer is asking. "Paid"
// is a fact about the money; what they want to know is whether anything is
// expected of them, and the answer is in the sentence rather than the word.
func orderStatusSays(status OrderStatus) string {
	switch status {
	case StatusPlaced:
		return "Waiting for payment"
	case StatusPaid:
		return "Paid — the seller is preparing it"
	case StatusShipped:
		return "On its way"
	case StatusCompleted:
		return "Completed"
	case StatusCanceled:
		return "Canceled"
	default:
		return string(status)
	}
}

// roughly is a length of time as somebody would say it.
//
// To the minute under an hour and to the hour above, because that is the
// accuracy the thing being said has: "the price holds for another 42 minutes"
// is useful and "for another 42 minutes and 17 seconds" is the same sentence
// pretending to more than it knows.
func roughly(d time.Duration) string {
	if d < time.Minute {
		return "less than a minute"
	}
	if d < time.Hour {
		// Rounded rather than truncated: an hour struck forty-two minutes
		// ago has forty-one minutes and change left on it, and "41 minutes"
		// is a worse answer than the one anybody would give.
		minutes := int(d.Round(time.Minute).Minutes())
		return fmt.Sprintf("%d minute%s", minutes, plural(minutes))
	}
	hours := int(d.Round(time.Minute).Hours())
	return fmt.Sprintf("%d hour%s", hours, plural(hours))
}

func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}
