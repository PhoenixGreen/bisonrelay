package resources

import (
	"context"
	"errors"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
)

func okProvider(body string) Provider {
	return ProviderFunc(func(context.Context, clientintf.UserID,
		*rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusOk,
			Data:   []byte(body),
		}, nil
	})
}

func fulfill(t *testing.T, p Provider, path ...string) (*rpc.RMFetchResourceReply, error) {
	t.Helper()
	return p.Fulfill(context.Background(), clientintf.UserID{},
		&rpc.RMFetchResource{Path: path})
}

// TestSwappableEmptyIsNotHosting asserts the distinction the Pages UI depends
// on: serving nothing at all is a different answer from serving a site that
// lacks the requested page.
func TestSwappableEmptyIsNotHosting(t *testing.T) {
	sw := NewSwappable(nil)

	if _, err := fulfill(t, sw, "index.md"); !errors.Is(err, ErrNotHosting) {
		t.Fatalf("empty swappable: got %v, want ErrNotHosting", err)
	}

	// A router with routes, none of which match, is hosting -- it just
	// does not have that page.
	r := NewRouter()
	r.BindExactPath([]string{"index.md"}, okProvider("hello"))
	sw.Set(r)

	if _, err := fulfill(t, sw, "missing.md"); !errors.Is(err, ErrProviderNotFound) {
		t.Fatalf("unmatched path: got %v, want ErrProviderNotFound", err)
	}

	reply, err := fulfill(t, sw, "index.md")
	if err != nil {
		t.Fatal(err)
	}
	if string(reply.Data) != "hello" {
		t.Fatalf("got %q, want %q", reply.Data, "hello")
	}

	// Swapping back to nothing goes back to not-hosting, which is what
	// turning hosting off at runtime does.
	sw.Set(nil)
	if _, err := fulfill(t, sw, "index.md"); !errors.Is(err, ErrNotHosting) {
		t.Fatalf("after clearing: got %v, want ErrNotHosting", err)
	}
}

// TestRouterFirstMatchWins pins the ordering the store depends on when it is
// bound beside a pages site: the store's own paths are bound first, and the
// catch-all filesystem route must not shadow them.
func TestRouterFirstMatchWins(t *testing.T) {
	r := NewRouter()
	r.BindPrefixPath([]string{"cart"}, okProvider("store"))
	r.BindPrefixPath(nil, okProvider("pages"))

	for _, tc := range []struct {
		path []string
		want string
	}{
		{[]string{"cart"}, "store"},
		{[]string{"cart", "anything"}, "store"},
		{[]string{"index.md"}, "pages"},
		{nil, "pages"},
	} {
		reply, err := fulfill(t, r, tc.path...)
		if err != nil {
			t.Fatalf("path %v: %v", tc.path, err)
		}
		if got := string(reply.Data); got != tc.want {
			t.Errorf("path %v: got %q, want %q", tc.path, got, tc.want)
		}
	}
}
