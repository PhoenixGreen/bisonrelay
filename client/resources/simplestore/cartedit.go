package simplestore

import (
	"context"
	"encoding/json"
	"errors"
	"path/filepath"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/rpc"
)

// cartedit.go is changing your mind.
//
// A cart could be added to and emptied, and nothing else. Adding two of
// something by mistake left one way out: throw the whole cart away and put
// every other item back in it one at a time. That is not a presentation
// problem -- it is the point at which somebody stops buying and does
// something else instead.
//
// Both of these answer with the cart, so a buyer who changes a quantity ends
// up looking at what they now have rather than at a page saying it worked.

// editCart reads the cart, hands it to [change], and writes it back if
// anything came of it.
//
// One place, because the two ways of changing a cart differ only in what
// they do to a line, and everything around that -- reading, the lock, the
// timestamp, writing, answering with the cart -- is the same both times and
// is where the mistakes would be.
func (s *Store) editCart(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource,
	change func(cart *Cart, sku string, qty uint32) bool) (*rpc.RMFetchResourceReply, error) {

	if request.Data == nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("request data is empty"),
		}, nil
	}
	formData := struct {
		SKU string `json:"sku"`
		Qty uint32 `json:"qty"`
	}{}
	if err := json.Unmarshal(request.Data, &formData); err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusBadRequest,
			Data:   []byte("request data not valid json"),
		}, nil
	}

	fname := filepath.Join(s.root, cartsDir, uid.String())
	var cart Cart

	s.mtx.Lock()
	err := jsonfile.Read(fname, &cart)
	if err != nil && !errors.Is(err, jsonfile.ErrNotFound) {
		s.mtx.Unlock()
		return nil, err
	}

	if change(&cart, formData.SKU, formData.Qty) {
		cart.Updated = time.Now()
		if err := jsonfile.Write(fname, &cart, s.log); err != nil {
			s.mtx.Unlock()
			return nil, err
		}
	}
	s.mtx.Unlock()

	// Answered with the cart itself. A line saying "removed" would be a page
	// to read and then leave, and the buyer's next question is always what
	// is in the cart now.
	return s.handleCart(ctx, uid, request)
}

// removeFromCart takes a line out entirely.
//
// A line rather than one of something: "remove" next to a row means that
// row, and a buyer who wanted one fewer has the quantity for that.
func removeFromCart(cart *Cart, sku string, _ uint32) bool {
	for i, item := range cart.Items {
		if item.Product.SKU == sku {
			cart.Items = append(cart.Items[:i], cart.Items[i+1:]...)
			return true
		}
	}
	return false
}

// setCartQuantity sets how many of one thing are in the cart.
//
// Nought removes the line. Somebody clearing a quantity box and submitting
// means they do not want it, and leaving an item at nought in the cart would
// be a row that is there and is not.
func setCartQuantity(cart *Cart, sku string, qty uint32) bool {
	if qty == 0 {
		return removeFromCart(cart, sku, 0)
	}
	for _, item := range cart.Items {
		if item.Product.SKU == sku {
			if item.Quantity == qty {
				return false
			}
			item.Quantity = qty
			return true
		}
	}
	return false
}

func (s *Store) handleRemoveFromCart(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	return s.editCart(ctx, uid, request, removeFromCart)
}

func (s *Store) handleSetCartQuantity(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	return s.editCart(ctx, uid, request, setCartQuantity)
}

// cartWithAvailability is the cart together with the lines that can no
// longer be bought.
//
// A product can be disabled or deleted while it sits in somebody's cart, and
// nothing tells them. Placing the order was where it surfaced -- the whole
// order refused, naming a SKU the buyer has never seen -- so the cart page
// says it instead, where there is a Remove button next to the thing that is
// wrong.
func (s *Store) cartWithAvailability(cart *Cart) cartContext {
	unavailable := make(map[string]bool)
	s.mtx.Lock()
	for _, item := range cart.Items {
		if _, ok := s.products[item.Product.SKU]; !ok {
			unavailable[item.Product.SKU] = true
		}
	}
	s.mtx.Unlock()

	// What the shop takes, and what the cart comes to in DCR at today's
	// rate. The rate is struck again when the order is placed -- this is
	// what it would be if that happened now, which is what somebody deciding
	// whether to buy wants to see.
	ctx := cartContext{
		Cart:        cart,
		Unavailable: unavailable,
		Methods:     s.payMethods(),
	}
	if rate := s.approxDCR(cart.Total()); rate != "" {
		ctx.TotalDCR = rate
	}
	return ctx
}
