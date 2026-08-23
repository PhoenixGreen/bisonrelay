package simplestore

import (
	"context"
	"encoding/json"
	"io/fs"
	"os"
	"path/filepath"
	"testing"
	"text/template"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/slog"
)

// handlers_lock_test.go is about one handler calling another.
//
// The store keeps a single mutex over its products, its carts and its
// templates, and a Go mutex is not reentrant. So a handler that holds it and
// then calls another handler does not fail, or slow down, or answer wrongly:
// it stops, holding the lock, and every later request to the shop stops
// behind it. The shop does not break, it disappears.
//
// This is worth a test of its own because the mistake is invisible at the
// call site -- "answer with the cart" reads as an obviously good idea, and
// the handler it names looks like a function rather than like something that
// takes the lock you are already holding.

// storeForHandlers is a store with its shipped templates and one product,
// which is the least a cart handler needs to answer.
func storeForHandlers(t *testing.T) *Store {
	t.Helper()
	root := t.TempDir()
	for _, dir := range []string{productsDir, cartsDir} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
			t.Fatal(err)
		}
	}

	s := &Store{
		root:      root,
		log:       slog.Disabled,
		indexPath: "/",
		products:  map[string]*Product{"r1": {SKU: "r1", Title: "A record", Price: 10}},
	}

	tmpl := template.New("*root").Funcs(s.templateFuncs())
	err := fs.WalkDir(storeTemplate, "template",
		func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || filepath.Ext(path) != ".tmpl" {
				return err
			}
			raw, err := storeTemplate.ReadFile(path)
			if err != nil {
				return err
			}
			_, err = tmpl.New(filepath.Base(path)).Parse(string(raw))
			return err
		})
	if err != nil {
		t.Fatal(err)
	}
	s.tmpl = tmpl
	return s
}

// answers runs a handler and fails if it does not come back.
//
// A deadlock has no error to report and no wrong answer to compare against.
// The only thing that tells it apart from slow work is that it never
// finishes, so that is what is checked.
func answers(t *testing.T, name string,
	call func() (*rpc.RMFetchResourceReply, error)) *rpc.RMFetchResourceReply {

	t.Helper()
	type result struct {
		res *rpc.RMFetchResourceReply
		err error
	}
	done := make(chan result, 1)
	go func() {
		res, err := call()
		done <- result{res, err}
	}()

	select {
	case got := <-done:
		if got.err != nil {
			t.Fatalf("%s: %v", name, got.err)
		}
		return got.res
	case <-time.After(5 * time.Second):
		t.Fatalf("%s never came back: it is holding the store's lock, and "+
			"every later request to the shop is waiting behind it", name)
		return nil
	}
}

func addToCartRequest(sku string, qty int) *rpc.RMFetchResource {
	data, _ := json.Marshal(map[string]any{"sku": sku, "qty": qty})
	return &rpc.RMFetchResource{Path: []string{"addToCart"}, Data: data}
}

func TestAddingToACartComesBack(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}

	res := answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 2))
	})
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("got status %d", res.Status)
	}
}

func TestTheShopStillAnswersAfterAddingToACart(t *testing.T) {
	// The second half, and the one that made this look like the whole shop
	// breaking rather than one page failing: a handler that stops while
	// holding the lock takes every later request with it.
	s := storeForHandlers(t)
	uid := clientintf.UserID{}

	answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 1))
	})
	// The cart rather than the shop front: drawing the front asks the
	// client who is looking, and this store has none. What is being
	// checked is that the lock came back, and any handler that takes it
	// shows that.
	answers(t, "the cart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleCart(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"cart"}})
	})
	answers(t, "adding again", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 1))
	})
}

func TestChangingAQuantityComesBack(t *testing.T) {
	s := storeForHandlers(t)
	uid := clientintf.UserID{}

	answers(t, "addToCart", func() (*rpc.RMFetchResourceReply, error) {
		return s.handleAddToCart(context.Background(), uid,
			addToCartRequest("r1", 3))
	})
	answers(t, "setCartQty", func() (*rpc.RMFetchResourceReply, error) {
		data, _ := json.Marshal(map[string]any{"sku": "r1", "qty": 1})
		return s.handleSetCartQuantity(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"setCartQty"}, Data: data})
	})
	answers(t, "removeFromCart", func() (*rpc.RMFetchResourceReply, error) {
		data, _ := json.Marshal(map[string]any{"sku": "r1"})
		return s.handleRemoveFromCart(context.Background(), uid,
			&rpc.RMFetchResource{Path: []string{"removeFromCart"}, Data: data})
	})
}
