package simplestore

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/internal/strescape"
	"github.com/companyzero/bisonrelay/rpc"
)

// adminRecentOrders is how many of the newest orders the front desk shows.
//
// Few, deliberately: the whole order book is one link away, and a page that
// lists everything is a page nobody reads the top of.
const adminRecentOrders = 5

func (s *Store) handleAdminIndex(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	orders, err := s.ListOrders()
	if err != nil {
		return nil, err
	}

	tctx := adminIndexContext{Total: len(orders)}
	for i := range orders {
		order := &orders[i]
		orders[i].UserNick = strescape.Nick(order.UserNick)

		switch order.Status {
		case StatusPlaced:
			tctx.Placed++
			tctx.Unpaid++
			tctx.Pending += order.Total()
			if order.Expired() {
				tctx.Lapsed++
			}
		case StatusPaid:
			tctx.Paid++
			tctx.ToSend++
			tctx.Taken += order.Total()
		case StatusShipped:
			tctx.Shipped++
			tctx.Taken += order.Total()
		case StatusCompleted:
			tctx.Completed++
			tctx.Taken += order.Total()
		case StatusCanceled:
			tctx.Canceled++
		}

		// Whose turn it is to say something. Asked of every order rather
		// than only the open ones: a question asked after an order was
		// completed is still a question nobody has answered.
		if order.AwaitingSeller() {
			tctx.NeedsReply++
		}
	}

	// The newest few, which ListOrders already sorts newest first.
	tctx.Recent = orders
	if len(tctx.Recent) > adminRecentOrders {
		tctx.Recent = tctx.Recent[:adminRecentOrders]
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	w := &bytes.Buffer{}
	if err := s.tmpl.ExecuteTemplate(w, adminTmplFile, &tctx); err != nil {
		return nil, fmt.Errorf("unable to execute admin template: %v", err)
	}
	return &rpc.RMFetchResourceReply{
		Data:   w.Bytes(),
		Status: rpc.ResourceStatusOk,
	}, nil
}

func (s *Store) handleAdminOrders(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	orders, err := s.ListOrders()
	if err != nil {
		return nil, err
	}

	// Whatever the path asked for, or the defaults: what is still going,
	// with whatever wants the seller at the top. See orderlist.go.
	view := parseOrderView(request.Path[2:])

	kept := orders[:0]
	for _, order := range orders {
		if view.shows(&order.Order) {
			kept = append(kept, order)
		}
	}

	// Sorted through the same code the buyer's list uses, on pointers into
	// the slice being shown.
	pointers := make([]*Order, len(kept))
	for i := range kept {
		pointers[i] = &kept[i].Order
	}
	view.arrange(pointers, true)
	sorted := make([]ManagedOrder, 0, len(kept))
	for _, p := range pointers {
		for i := range kept {
			if &kept[i].Order == p {
				sorted = append(sorted, kept[i])
				break
			}
		}
	}

	tctx := adminOrdersContext{
		Orders: sorted,
		View:   view,
		Prefix: "/admin/orders",
		Seller: true,
	}
	for i := range tctx.Orders {
		// Made safe where it arrives, so everything that renders it later is
		// safe without having to remember.
		tctx.Orders[i].UserNick = strescape.Nick(tctx.Orders[i].UserNick)
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	// Generate template.
	w := &bytes.Buffer{}
	err = s.tmpl.ExecuteTemplate(w, adminOrdersTmplFile, &tctx)
	if err != nil {
		return nil, fmt.Errorf("unable to execute product template: %v", err)
	}
	return &rpc.RMFetchResourceReply{
		Data:   w.Bytes(),
		Status: rpc.ResourceStatusOk,
	}, nil
}

func (s *Store) handleAdminViewOrder(ctx context.Context, _ clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	if len(request.Path) < 4 {
		return nil, fmt.Errorf("path has < 4 elements")
	}

	// Load order.
	var uid clientintf.UserID
	if err := uid.FromString(request.Path[2]); err != nil {
		return nil, err
	}
	var oid OrderID
	if err := oid.FromString(request.Path[3]); err != nil {
		return nil, err
	}

	orderDir := filepath.Join(s.root, ordersDir, uid.String())
	orderFname := filepath.Join(orderDir, orderFnamePattern.FilenameFor(uint64(oid)))
	var order Order
	if err := jsonfile.Read(orderFname, &order); err != nil {
		return nil, err
	}

	nick, _ := s.c.UserNick(uid)
	nick = strescape.Nick(nick)

	tctx := &adminOrderContext{
		Order:    order,
		UserNick: nick,
	}

	// Generate template.
	w := &bytes.Buffer{}
	err := s.tmpl.ExecuteTemplate(w, adminOrderTmplFile, tctx)
	if err != nil {
		return nil, fmt.Errorf("unable to execute product template: %v", err)
	}
	return &rpc.RMFetchResourceReply{
		Data:   w.Bytes(),
		Status: rpc.ResourceStatusOk,
	}, nil
}

func (s *Store) handleAdminAddOrderComment(ctx context.Context, _ clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	// Process form data.
	var comment string
	if err := json.Unmarshal(request.Data, &comment); err != nil {
		return nil, err
	}

	if len(request.Path) < 4 {
		return nil, fmt.Errorf("path has < 4 elements")
	}
	var uid clientintf.UserID
	if err := uid.FromString(request.Path[2]); err != nil {
		return nil, err
	}
	var oid OrderID
	if err := oid.FromString(request.Path[3]); err != nil {
		return nil, err
	}

	// The buyer is told by AddOrderComment, which is where every way of
	// answering one goes through -- this page, and the seller's own order
	// list in the app.
	if _, err := s.AddOrderComment(uid, oid, comment, true); err != nil {
		return nil, err
	}

	// Generate template.
	w := &bytes.Buffer{}
	w.WriteString("# Comment added\n\n")
	fmt.Fprintf(w, "[Back to Order](/admin/order/%s/%s)\n\n", uid, oid)
	return &rpc.RMFetchResourceReply{
		Data:   w.Bytes(),
		Status: rpc.ResourceStatusOk,
	}, nil
}

func (s *Store) handleAdminUpdateOrderStatus(ctx context.Context, _ clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	if len(request.Path) < 5 {
		return nil, fmt.Errorf("path has < 5 elements")
	}
	var uid clientintf.UserID
	if err := uid.FromString(request.Path[2]); err != nil {
		return nil, err
	}
	var oid OrderID
	if err := oid.FromString(request.Path[3]); err != nil {
		return nil, err
	}

	if _, err := s.SetOrderStatus(uid, oid, OrderStatus(request.Path[4])); err != nil {
		return nil, err
	}

	// Generate template.
	w := &bytes.Buffer{}
	w.WriteString("# Order Status Updated\n\n")
	fmt.Fprintf(w, "[Back to Order](/admin/order/%s/%s)\n\n", uid, oid)
	return &rpc.RMFetchResourceReply{
		Data:   w.Bytes(),
		Status: rpc.ResourceStatusOk,
	}, nil
}
