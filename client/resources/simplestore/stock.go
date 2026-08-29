package simplestore

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/companyzero/bisonrelay/rpc"

	"github.com/decred/dcrd/dcrutil/v4"
	"github.com/decred/dcrlnd/lnrpc"
)

// stock.go is how many of a thing a shop has left, and whether it can be
// bought at all right now.
//
// Two different questions with one answer on the page. A shop can run out of
// something, and a shop can be unable to take the money for something it has
// plenty of -- a Lightning-only shop whose channels cannot receive what the
// thing costs. Both end with a buyer who cannot have it, and both used to end
// with a buyer finding that out after filling a cart: the first because
// nothing counted, the second at the moment the order was placed.
//
// So it is said on the card, before anything is added to anything.

// InStock is whether there is any of this left.
//
// A product the shop does not count is always in stock. One it does count is
// in stock while the count is above nought, and Available never goes below it
// -- see take.
func (p *Product) InStock() bool { return !p.Limited || p.Available > 0 }

// Counted is whether this product keeps a count at all, for a page deciding
// whether "3 left" is a thing it can say.
func (p *Product) Counted() bool { return p.Limited }

// Left is how many there are, for a page that counts them.
func (p *Product) Left() int {
	if !p.Limited {
		return 0
	}
	if p.Available < 0 {
		return 0
	}
	return p.Available
}

// take reduces this product's stock by [n], and says how many it could
// actually give.
//
// Clamped rather than refused, and never below nought. Two buyers can reach
// the last one at the same time -- the catalogue is read, a cart is filled,
// and an order is placed, with time passing at every step -- so this is where
// the honest answer is worked out, under the store's lock, rather than in a
// check somewhere earlier that was true when it was made.
func (p *Product) take(n uint32) uint32 {
	if !p.Limited {
		return n
	}
	if p.Available <= 0 {
		return 0
	}
	if int(n) > p.Available {
		n = uint32(p.Available)
	}
	p.Available -= int(n)
	return n
}

// give puts stock back.
//
// An order that lapses or is called off never happened, and the things in it
// were never sold. Without this, a shop selling five of something would run
// out after five people started an order and none of them finished it.
func (p *Product) give(n uint32) {
	if !p.Limited {
		return
	}
	p.Available += int(n)
}

// unavailable is why a buyer cannot have this right now, or empty when they
// can.
//
// The reason rather than a bool, because the two reasons want different words
// and only the shop knows which applies. "Sold out" on something the shop has
// a hundred of, because its channels are short, is a shop lying about its own
// stock.
type unavailable string

const (
	// soldOut is a shop that has none of this left.
	soldOut unavailable = "sold out"

	// cannotBePaid is a shop that has it and cannot take the money for it.
	//
	// Only ever a Lightning-only shop. Where on-chain is offered as well
	// there is always a way to pay, so a channel that cannot receive is not
	// a reason to stop selling anything.
	cannotBePaid unavailable = "cannot be paid for"
)

// stockCheck is what one pass over the catalogue needs to know, worked out
// once rather than per product.
//
// The Lightning question costs a call to the node, and the shop front asks it
// about every product on the page. Asked once and compared against each
// price, it is one call; asked per card it is one call per card, on a page
// that is drawn every time anybody looks at the shop.
type stockCheck struct {
	// lnOnly is whether Lightning is the only way this shop can be paid.
	lnOnly bool

	// canReceive is the most this shop can take over Lightning, in atoms, or
	// -1 when the node would not say.
	//
	// Minus one rather than nought: a node that will not answer is not a
	// node with no room, and refusing to sell anything because a balance
	// call failed would be a shop closing itself over a hiccup.
	canReceive int64
}

// stockCheck reads what it needs to judge availability.
func (s *Store) stockCheck(ctx context.Context) stockCheck {
	methods := s.payMethods()
	check := stockCheck{lnOnly: methods.LN && !methods.OnChain, canReceive: -1}
	if !check.lnOnly || s.lnpc == nil {
		return check
	}

	bal, err := s.lnpc.LNRPC().ChannelBalance(ctx, &lnrpc.ChannelBalanceRequest{})
	if err != nil {
		s.log.Warnf("Unable to read channel balance: %v", err)
		return check
	}
	check.canReceive = bal.MaxInboundAmount
	return check
}

// says is why this product cannot be bought, or empty.
func (c stockCheck) says(p *Product, priceDCR dcrutil.Amount) unavailable {
	if !p.InStock() {
		return soldOut
	}
	if c.lnOnly && c.canReceive >= 0 && priceDCR > 0 &&
		int64(priceDCR) > c.canReceive {
		return cannotBePaid
	}
	return ""
}

// stockLeft is how many of a product a shop has, as a line anybody can read,
// or empty when there is nothing worth saying.
//
// Nothing for a product the shop does not count, and nothing at nought: a
// page with none left is already saying so in the panel above, and "0 left"
// beside "Currently unavailable" is the page saying it twice.
func stockLeft(p *Product) string {
	if !p.Counted() || p.Left() <= 0 {
		return ""
	}
	if p.Left() == 1 {
		return "1 left"
	}
	return fmt.Sprintf("%d left", p.Left())
}

// takeStock reduces the catalogue by what an order holds, and says what it
// could not give.
//
// Called with the store's lock held, from the one place an order comes into
// existence. Anything it could not give is the answer to "somebody bought the
// last one while this cart was open", which is a real race and not a rare
// one: a shop front is read, a cart is filled and an order is placed, with
// minutes between each.
func (s *Store) takeStock(cart *Cart) []string {
	var short []string
	for _, item := range cart.Items {
		if item.Product == nil {
			continue
		}
		prod := s.products[item.Product.SKU]
		if prod == nil || !prod.Limited {
			continue
		}
		if got := prod.take(item.Quantity); got < item.Quantity {
			// Put back what was taken: this order is not going to be placed,
			// so it must not hold any of it.
			prod.give(got)
			short = append(short, prod.Title)
		}
	}
	if len(short) == 0 {
		s.saveStock(cart)
	}
	return short
}

// giveStock puts an order's stock back.
//
// An order that lapsed or was called off never happened. Without this a shop
// selling five of something runs out after five people start an order and
// none of them finishes it -- and it never recovers, because nothing else
// counts up.
func (s *Store) giveStock(order *Order) {
	changed := false
	for _, item := range order.Cart.Items {
		if item.Product == nil {
			continue
		}
		prod := s.products[item.Product.SKU]
		if prod == nil || !prod.Limited {
			continue
		}
		prod.give(item.Quantity)
		changed = true
	}
	if changed {
		s.saveStock(&order.Cart)
	}
}

// saveStock writes the counts of the products a cart touched back to disk.
//
// The catalogue in memory is what every page is drawn from, so a count that
// only changed there is a count that resets the next time anything reloads
// the shop -- which is every time the seller saves a product, and every time
// a file in the store changes.
//
// Best effort, and deliberately after the fact. A count that fails to write
// is a shop that may oversell by one; an order refused because a file was
// locked is a sale lost for certain.
func (s *Store) saveStock(cart *Cart) {
	for _, item := range cart.Items {
		if item.Product == nil {
			continue
		}
		prod := s.products[item.Product.SKU]
		if prod == nil || !prod.Limited {
			continue
		}
		if err := s.writeStock(prod); err != nil {
			s.log.Warnf("Unable to write the stock of %q: %v", prod.SKU, err)
		}
	}
}

// writeStock puts one product's count into whichever file defines it.
//
// The file is found by its SKU rather than remembered, because a product can
// be moved between files by the seller at any time and nothing here is told.
func (s *Store) writeStock(prod *Product) error {
	dir := filepath.Join(s.root, productsDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return err
	}

	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".toml" {
			continue
		}
		path := filepath.Join(dir, e.Name())
		prods, err := s.readProductFile(path)
		if err != nil {
			continue
		}
		for _, p := range prods.Products {
			if p.SKU != prod.SKU {
				continue
			}
			if p.Available == prod.Available && p.Limited == prod.Limited {
				return nil
			}
			p.Available = prod.Available
			p.Limited = prod.Limited
			return s.writeProductFile(path, prods)
		}
	}
	return nil
}

// soldOutPage is what somebody is shown for pressing a button on a thing the
// shop has run out of.
func (s *Store) soldOutPage(prod *Product) (*rpc.RMFetchResourceReply, error) {
	return &rpc.RMFetchResourceReply{
		Data: []byte(fmt.Sprintf("# %s is not available\n\nThe shop has run "+
			"out of this. Nothing has been added to your cart.\n\n"+
			"[Back to the shop](%s)\n", prod.Title, s.indexPath)),
		Status: rpc.ResourceStatusOk,
	}, nil
}

// soldOutWhileOrderingPage is the race, said plainly.
//
// Somebody else took the last one between this cart being filled and this
// order being placed. Nothing has been ordered and nothing has been charged,
// and the rest of the cart is untouched -- which is the whole of what the
// person reading it needs.
func (s *Store) soldOutWhileOrderingPage(short []string) (*rpc.RMFetchResourceReply, error) {
	var b strings.Builder
	b.WriteString("# The shop has run out\n\n")
	b.WriteString("Your order has not been placed and nothing has left your ")
	b.WriteString("wallet. What is in your cart is still there.\n\n")
	for _, title := range short {
		fmt.Fprintf(&b, "- There is not enough %s left\n", title)
	}
	b.WriteString("\nTake it out of your cart, or lower how many you asked ")
	b.WriteString("for, and the rest can still be ordered.\n\n")
	fmt.Fprintf(&b, "[Back to your cart](/cart)\n")

	return &rpc.RMFetchResourceReply{
		Data:   []byte(b.String()),
		Status: rpc.ResourceStatusOk,
	}, nil
}

// refreshStockCheck asks the node what it can receive and keeps the answer
// for the pages about to be drawn.
//
// Kept rather than asked per card, and taken before the store's lock rather
// than under it. A shop front draws every product on one page: asked per card
// this is one call to the node per product, every time anybody looks at the
// shop, and asked under the lock it is a network round trip with the whole
// shop waiting behind it.
//
// Slightly stale on purpose, then. What it decides is whether to draw a
// ribbon, and a shop whose channels changed a second ago is a shop that draws
// the right ribbon a second later.
func (s *Store) refreshStockCheck(ctx context.Context) {
	check := s.stockCheck(ctx)
	s.checkMtx.Lock()
	s.check = check
	s.checkMtx.Unlock()
}

// unavailableFor is why a buyer cannot have this product, or empty.
func (s *Store) unavailableFor(p *Product) unavailable {
	s.checkMtx.Lock()
	check := s.check
	s.checkMtx.Unlock()
	return check.says(p, s.priceDCR(p))
}

// priceDCR is what a product costs in DCR at the rate held now, or nought
// when no rate is known.
func (s *Store) priceDCR(p *Product) dcrutil.Amount {
	if s.cfg.ExchangeRateProvider == nil || p == nil {
		return 0
	}
	rate := s.cfg.ExchangeRateProvider()
	if rate <= 0 {
		return 0
	}
	amount, err := dcrutil.NewAmount(p.Price / rate)
	if err != nil {
		return 0
	}
	return amount
}

// Unavailable is whether a buyer cannot have this product right now, for a
// template deciding whether to draw the ribbon.
func (s *Store) Unavailable(p *Product) bool { return s.unavailableFor(p) != "" }

// UnavailableSays is why, in words, for the product's own page -- which has
// room to say which of the two it is.
//
// The card cannot: it carries one label for both reasons, because from the
// buyer's side they are the same fact. Here they are not. "Sold out" on
// something the shop has a hundred of, because its channels are short, is a
// shop lying about its own stock; and "we cannot take your money" on
// something that is genuinely gone is a shop blaming its wallet.
func (s *Store) UnavailableSays(p *Product) string {
	switch s.unavailableFor(p) {
	case soldOut:
		return "The shop has run out of this."
	case cannotBePaid:
		return "The shop cannot take payment for this at the moment. It is " +
			"nothing to do with your wallet, and it usually clears on its own."
	default:
		return ""
	}
}

// LowStock is whether this product is down to the few the seller asked to be
// told about.
//
// Only ever said about something a buyer can still have: a count on a thing
// nobody can buy is the shop urging somebody towards a closed door.
func (s *Store) LowStock(p *Product) bool {
	layout := s.IndexLayout()
	if layout.LowStockAt <= 0 || !p.Counted() || s.Unavailable(p) {
		return false
	}
	return p.Left() > 0 && p.Left() <= layout.LowStockAt
}
