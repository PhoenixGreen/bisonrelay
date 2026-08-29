package simplestore

import (
	"fmt"
	"strings"
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

// PaymentSeen is whether the shop has seen the payment for this order and is
// waiting for the network to confirm it.
//
// On-chain only: a Lightning payment either settles or does not, and there is
// no gap to be in.
func (order *Order) PaymentSeen() bool {
	return order.Status == StatusPlaced && order.SeenTS != nil
}

// Paid is whether the money for this order has arrived and the seller has not
// yet moved it on.
//
// The one moment worth a page of its own: everything before it is the buyer
// being asked for something, and this is the shop saying it is done. After
// the seller ships it the order is about delivery instead, so the panel goes.
func (order *Order) Paid() bool { return order.Status == StatusPaid }

// Fulfilled is whether this order has been paid for, whatever has happened to
// it since.
//
// Paid, sent or finished -- as against waiting for payment or called off. The
// question it answers is whether the shop owes the buyer the things in it,
// which stays true after the seller marks an order shipped. Reading that off
// Paid alone took the buyer's way into a file they had bought away from them
// the moment the seller moved the order on.
func (order *Order) Fulfilled() bool {
	switch order.Status {
	case StatusPaid, StatusShipped, StatusCompleted:
		return true
	}
	return false
}

// OnChain is whether this order is being paid on-chain.
func (order *Order) OnChain() bool { return order.PayType == PayTypeOnChain }

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
	// Nothing to offer once the money is on its way: an address shown beside
	// "we have seen your payment" is an invitation to pay twice.
	if order.PaymentSeen() {
		return ""
	}

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

// PayQR is what a phone should be pointed at to pay this order, or empty when
// there is nothing to point it at.
//
// A Decred URI rather than the bare address, because the amount matters here:
// an order is paid by sending exactly what it was quoted, and an address on
// its own leaves that to be typed in by hand. Decrediton and Cake Wallet both
// read this form, and the address is written out beneath it for a wallet on
// the same machine, which would rather be copied to.
//
// Lightning has its own button and needs no square: the invoice is paid by
// the client that is already showing it.
func (order *Order) PayQR() string {
	if order.PayURI() == "" || !order.OnChain() {
		return ""
	}
	return fmt.Sprintf("decred:%s?amount=%.8f", order.Invoice,
		order.TotalDCR().ToCoin())
}

// quoteHoldsFor is how long the DCR amount an order was quoted at stands for.
//
// The rate is struck when the order is placed, and this is how long the shop
// will honour it. It is a promise about a price in a currency that moves, so
// it is short on purpose: every minute of it is a minute the seller carries
// the difference, and it only has to be long enough to open a wallet and
// send. An hour was a long time to stand behind a number, and a lapsed quote
// costs the buyer nothing but the press that asks for a new one.
const quoteHoldsFor = 25 * time.Minute

// QuoteHoldsFor is the same, in words, for a page that has to say it before
// there is an order to say it about.
func QuoteHoldsFor() string { return roughly(quoteHoldsFor) }

// Expired is whether the amount this order was quoted at no longer holds.
//
// A payment already seen is never expired, whatever the clock says: the buyer
// paid the amount they were quoted, inside the hour they were given, and the
// network is taking its own time about it.
//
// The rate is struck when the order is placed and held for [quoteHoldsFor].
// After that the invoice is stale, and a buyer paying it is paying yesterday's
// price for today's coin -- which is why the shop says so rather than
// quietly letting it lapse.
func (order *Order) Expired() bool {
	return order.AwaitingPayment() && !order.PaymentSeen() &&
		!order.ExpiresTS.IsZero() && time.Now().After(order.ExpiresTS)
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
// orderSays is what is happening with one order, in words.
//
// The order rather than the status, because the middle of an on-chain payment
// is not a status: the order is still "placed" while its money is in the
// mempool, and "waiting for payment" is the one thing that is no longer true
// of it.
func orderSays(order Order) string {
	if order.PaymentSeen() {
		return "Payment seen — waiting for a confirmation"
	}
	if order.Expired() {
		return "Waiting for payment — the quoted amount has lapsed"
	}
	return orderStatusSays(order.Status)
}

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
		// Which rounds an hour to "60 minutes", and nobody says that.
		if minutes >= 60 {
			return "1 hour"
		}
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

// PayAmount is what this order comes to in DCR, as a bare number, or empty
// when there is nothing to pay.
//
// For the two blocks that have to act on the figure rather than show it:
// --paynow-- sends exactly this, and --wallet-- measures a balance against
// it. Eight places, which is what an atom is worth -- a figure rounded to
// what the page happened to display is one that underpays.
func (order *Order) PayAmount() string {
	if order.PayURI() == "" {
		return ""
	}
	return fmt.Sprintf("%.8f", order.TotalDCR().ToCoin())
}

// Explorer is where a transaction for this shop's network can be looked up.
//
// The host only, because what the page offers is something to copy rather
// than something to press: a link that opens a browser from inside a shop
// page is the shop deciding where its buyer goes next, and a transaction id
// pasted into an explorer is the same answer without that.
func explorerFor(net string) string {
	switch net {
	case "testnet3", "testnet":
		return "testnet.dcrdata.org"
	case "simnet", "regnet":
		// No public explorer for a network only this machine can see. The
		// page says the id and stops there.
		return ""
	default:
		return "dcrdata.decred.org"
	}
}

// AddressLines is a shipping address written the way an address is written:
// one thing per line.
//
// Markdown joins consecutive lines into a paragraph, so a template that puts
// a name, a street and a town on three lines gets "Ada Lovelace 1 Long Road
// Kent" -- which is not an address, it is a sentence about one. Two trailing
// spaces are Markdown's own hard break, and this is where they go: invisible
// whitespace at the end of a template line is exactly the kind of thing that
// gets tidied away by an editor nobody blames.
func AddressLines(a *ShippingAddress) string {
	if a == nil {
		return ""
	}
	var lines []string
	add := func(s string) {
		if s = strings.TrimSpace(s); s != "" {
			lines = append(lines, s)
		}
	}
	add(a.Name)
	add(a.Address1)
	add(a.Address2)

	// The town, the county and the postcode each on their own line.
	//
	// They were one line joined by commas, which is how an envelope is
	// written and not how a form is read back: what a buyer is checking is
	// each thing they typed, against the box they typed it into.
	add(a.City)
	add(a.State)
	add(a.PostalCode)
	add(a.CountryCode)

	// Last, and only when it is there. A phone number is for whoever
	// delivers the thing; the seller reaches the buyer in Bison Relay, in
	// the order's own messages.
	add(a.Phone)

	return strings.Join(lines, "  \n")
}

// ExpiresInSeconds is how long the quoted amount holds for, in seconds, or
// nought when nothing is waiting on a clock.
//
// Seconds remaining rather than the moment it runs out, because the page is
// drawn by the shop and read by somebody else: an absolute time would be
// compared against the reader's own clock, and two machines a few minutes
// apart would disagree about an order neither of them is wrong about.
func (order *Order) ExpiresInSeconds() int {
	if !order.AwaitingPayment() || order.PaymentSeen() ||
		order.ExpiresTS.IsZero() {
		return 0
	}
	left := int(time.Until(order.ExpiresTS).Seconds())
	if left < 0 {
		return 0
	}
	return left
}
