package simplestore

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/dcrd/dcrutil/v4"
	"github.com/decred/dcrlnd/lnrpc"
)

// payment.go is how an order gets paid for: what the shop will take, whether
// it can actually take it, and what to do when it cannot.
//
// The shop took one kind of payment, whichever its config named, and found
// out whether that worked by trying it as the order was placed. When it did
// not work the order was placed anyway -- with no invoice, no address and
// nothing said -- so a buyer was handed an order they had no way to pay and
// no way to find out why.

// PayTypeBoth is a shop that will take either.
//
// A buyer choosing between them is choosing between two different promises:
// Lightning settles now, on-chain settles when the network says so. That is
// worth offering, and it is also the shop's insurance -- an order that cannot
// go one way can go the other rather than not going at all.
const PayTypeBoth PayType = "both"

// PayMethods is what a shop will take.
type PayMethods struct {
	LN      bool
	OnChain bool
}

// Any is whether the shop will take anything at all.
func (m PayMethods) Any() bool { return m.LN || m.OnChain }

// Both is whether there is a choice to offer the buyer.
func (m PayMethods) Both() bool { return m.LN && m.OnChain }

// payMethods is what this shop's config says it takes.
//
// A shop that has said nothing takes nothing, which is what it did before:
// the order went through and the buyer was told they would be contacted with
// payment details. That is still a real arrangement -- a shop settling up in
// chat -- so it stays possible, and everything below asks Any() first.
func (s *Store) payMethods() PayMethods {
	switch s.cfg.PayType {
	case PayTypeLN:
		return PayMethods{LN: true}
	case PayTypeOnChain:
		return PayMethods{OnChain: true}
	case PayTypeBoth:
		return PayMethods{LN: true, OnChain: true}
	default:
		return PayMethods{}
	}
}

// canReceiveLN is whether this shop's own node can take [amount] over
// Lightning, and what to say when it cannot.
//
// A node can only be paid what its channels have room to receive. Issuing an
// invoice for more than that is issuing one that cannot be paid: the buyer's
// wallet tries, fails, and says something about routing -- and the buyer, who
// has no way to know whose end is short, concludes their own wallet is
// broken.
//
// Approximate on purpose, and it has to be. MaxInboundAmount is what every
// channel can take between them once their reserves are set aside, so a
// payment that cannot be split still has to fit down one of them and this can
// say yes to an amount that will not arrive. It can also be out of date by
// the time the buyer pays. So it decides which way to send somebody, and
// never refuses a sale on its own.
//
// In atoms. dcrlnd sets both of these from a dcrutil.Amount, which is atoms,
// and the number this is compared against comes from Order.TotalDCR, which is
// the same -- getting that wrong by the factor between atoms and milli-atoms
// made every shop look as though it could receive a thousandth of what it
// can, so a shop offering both never once offered Lightning.
func (s *Store) canReceiveLN(ctx context.Context, amount dcrutil.Amount) (bool, string) {
	if s.lnpc == nil {
		return false, "this shop is not set up to take Lightning payments"
	}

	bal, err := s.lnpc.LNRPC().ChannelBalance(ctx, &lnrpc.ChannelBalanceRequest{})
	if err != nil {
		// Not knowing is not the same as knowing it will fail. The invoice
		// is still worth issuing -- the check is here to catch the case the
		// node answers plainly, and a node that will not answer at all is a
		// different problem, which the log is for.
		s.log.Warnf("Unable to read channel balance: %v", err)
		return true, ""
	}

	if bal.MaxInboundAmount < int64(amount) {
		return false, fmt.Sprintf("this shop cannot receive %s over "+
			"Lightning at the moment", amount)
	}
	return true, ""
}

// prepared is a way for one order to be paid.
type prepared struct {
	payType PayType

	// invoice is the Lightning invoice or the on-chain address.
	invoice string

	// says is the line the buyer's confirmation carries.
	says string
}

// preparePayment works out how this order can be paid and gets what is needed
// to pay it, or says why it cannot.
//
// The order of preference is the buyer's choice, then whatever else the shop
// takes. A shop offering both is a shop that can still sell when one of them
// is having a bad day -- which was already true of an invoice that failed to
// generate, and is now true of one that would have failed to pay.
func (s *Store) preparePayment(ctx context.Context, order *Order,
	want PayType) (*prepared, error) {

	methods := s.payMethods()
	if !methods.Any() {
		return nil, nil
	}

	total := order.TotalDCR()
	if total <= 0 {
		return nil, fmt.Errorf("order has no amount to pay")
	}

	// What to try, in order. The buyer's choice first when the shop offers
	// it, then the other as a fallback.
	var attempts []PayType
	if want == PayTypeLN && methods.LN {
		attempts = []PayType{PayTypeLN, PayTypeOnChain}
	} else if want == PayTypeOnChain && methods.OnChain {
		attempts = []PayType{PayTypeOnChain, PayTypeLN}
	} else if methods.LN {
		attempts = []PayType{PayTypeLN, PayTypeOnChain}
	} else {
		attempts = []PayType{PayTypeOnChain, PayTypeLN}
	}

	var why []string
	for _, try := range attempts {
		switch {
		case try == PayTypeLN && methods.LN:
			if ok, reason := s.canReceiveLN(ctx, total); !ok {
				why = append(why, reason)
				continue
			}
			invoice, err := s.lnpc.GetInvoice(ctx, int64(total)*1000, nil)
			if err != nil {
				s.log.Errorf("Unable to generate LN invoice for order %s: %v",
					order.ID, err)
				why = append(why, "this shop could not raise a Lightning invoice")
				continue
			}
			return &prepared{
				payType: PayTypeLN,
				invoice: invoice,
				says:    "LN Invoice for payment: lnpay://" + invoice,
			}, nil

		case try == PayTypeOnChain && methods.OnChain:
			addr, err := s.c.OnchainRecvAddrForUser(order.User, s.cfg.Account)
			if err != nil {
				s.log.Errorf("Unable to generate on-chain addr for order %s: %v",
					order.ID, err)
				why = append(why, "this shop could not raise an on-chain address")
				continue
			}
			return &prepared{
				payType: PayTypeOnChain,
				invoice: addr,
				says:    "On-chain Payment Address: " + addr,
			}, nil
		}
	}

	return nil, &cannotTakePayment{why: why}
}

// wantPayType is the way the buyer asked to pay, or empty for a buyer who
// was not asked.
//
// Read off the form the cart submits, which only offers the choice when the
// shop takes both. Anything else is ignored rather than refused: a shop that
// takes one kind of payment takes that kind whatever arrives.
func wantPayType(request *rpc.RMFetchResource) PayType {
	var form struct {
		Method string `json:"method"`
	}
	if err := json.Unmarshal(request.Data, &form); err != nil {
		return ""
	}
	switch PayType(form.Method) {
	case PayTypeLN:
		return PayTypeLN
	case PayTypeOnChain:
		return PayTypeOnChain
	default:
		return ""
	}
}

// cannotPayPage is what a buyer is shown when the shop cannot take their
// money.
//
// A page rather than a bare status, because this is the one moment where the
// buyer has done everything right and the shop has not: what they need is
// what went wrong, that their cart is untouched, and that the seller has been
// told.
func (s *Store) cannotPayPage(cannot *cannotTakePayment) (*rpc.RMFetchResourceReply, error) {
	var b strings.Builder
	b.WriteString("# The shop cannot take payment right now\n\n")
	b.WriteString("Your order has not been placed and nothing has left your ")
	b.WriteString("wallet. What is in your cart is still there.\n\n")
	for _, why := range cannot.Says() {
		fmt.Fprintf(&b, "- %s\n", why)
	}
	b.WriteString("\nThe seller has been told. Try again in a little while, ")
	b.WriteString("or ask them about it.\n")

	return &rpc.RMFetchResourceReply{
		Data:   []byte(b.String()),
		Status: rpc.ResourceStatusOk,
	}, nil
}

// cannotTakePayment is a shop that cannot be paid for this order right now.
//
// An error rather than an empty result, because it must not be possible to
// carry on and place the order by accident. That is exactly what used to
// happen: every failure here was a log line, the code fell through, and the
// buyer was handed an order with nothing to pay it with.
type cannotTakePayment struct {
	why []string
}

func (e *cannotTakePayment) Error() string {
	if len(e.why) == 0 {
		return "this shop cannot take payment at the moment"
	}
	return e.why[0]
}

// Says is the whole of it, for a page that has room to say more than a
// sentence.
func (e *cannotTakePayment) Says() []string { return e.why }
