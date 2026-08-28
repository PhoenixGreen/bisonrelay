package simplestore

import (
	"bytes"
	"context"
	"encoding/hex"

	"github.com/decred/dcrd/dcrutil/v4"
	"github.com/decred/dcrd/txscript/v4/stdscript"
	"github.com/decred/dcrd/wire"
	"github.com/decred/dcrlnd/lnrpc"
)

// catchup.go is what happens to a payment made while the shop was not
// running.
//
// Both watchers are subscriptions: they are told what happens from the moment
// they start listening. A Lightning invoice settled overnight, or a
// transaction that confirmed while the seller's laptop was shut, happened to
// nobody -- the order stayed "placed", the hour on its quote ran out, and the
// buyer, who had paid, was looking at a page telling them their order was
// waiting for payment.
//
// So the shop asks, once, on the way up: for every order still waiting, has
// this already been paid? A subscription cannot answer that, and the two
// nodes can.

// catchUpPayments settles the orders that were paid while nobody was
// listening, and takes them out of [pending].
//
// Best effort throughout. A node that will not answer leaves the order where
// it is, which is where it would have been anyway -- this makes things better
// or leaves them alone, and never makes a decision it is unsure of.
func (s *Store) catchUpPayments(ctx context.Context, pending map[string]*Order) {
	if s.lnpc == nil || len(pending) == 0 {
		return
	}

	s.catchUpLN(ctx, pending)
	s.catchUpOnChain(ctx, pending)
}

// catchUpLN asks the node whether each pending Lightning invoice has been
// settled already.
func (s *Store) catchUpLN(ctx context.Context, pending map[string]*Order) {
	for disc, order := range pending {
		if order.PayType != PayTypeLN || order.Invoice == "" {
			continue
		}
		// The amount the invoice was raised for, in milli-atoms, which is
		// what IsInvoicePaid checks against.
		want := int64(order.TotalDCR()) * 1000
		if err := s.lnpc.IsInvoicePaid(ctx, want, order.Invoice); err != nil {
			continue
		}

		s.log.Infof("Order %s/%s was paid over Lightning while the shop was "+
			"not running", order.User.ShortLogID(), order.ID)
		delete(pending, disc)
		go s.invoiceSettled(ctx, order)
	}
}

// catchUpOnChain looks through the wallet's own transactions for payments to
// the addresses orders are still waiting on.
//
// The same matching the live watcher does -- an output to the address, for
// the amount the order was quoted -- run once over what the wallet already
// has rather than over what arrives next.
func (s *Store) catchUpOnChain(ctx context.Context, pending map[string]*Order) {
	waiting := false
	for _, order := range pending {
		if order.PayType == PayTypeOnChain {
			waiting = true
			break
		}
	}
	if !waiting {
		return
	}

	txs, err := s.lnpc.LNRPC().GetTransactions(ctx, &lnrpc.GetTransactionsRequest{})
	if err != nil {
		s.log.Warnf("Unable to read past transactions: %v", err)
		return
	}

	for _, tx := range txs.Transactions {
		msgTx := wire.NewMsgTx()
		err := msgTx.Deserialize(hex.NewDecoder(bytes.NewBuffer([]byte(tx.RawTxHex))))
		if err != nil {
			continue
		}

		for _, out := range msgTx.TxOut {
			_, addrs := stdscript.ExtractAddrs(out.Version, out.PkScript, s.chainParams)
			if len(addrs) != 1 {
				continue
			}
			disc := onChainInvoiceDiscriminator(addrs[0].String(),
				dcrutil.Amount(out.Value))
			order := pending[disc]
			if order == nil {
				continue
			}

			if tx.NumConfirmations >= 1 {
				s.log.Infof("Order %s/%s was paid on-chain while the shop "+
					"was not running", order.User.ShortLogID(), order.ID)
				delete(pending, disc)
				go s.invoiceSettled(ctx, order)
			} else {
				// Seen and not confirmed: the order stays pending, because
				// the live watcher still has to see it confirm.
				go s.paymentSeen(ctx, order)
			}
		}
	}
}
