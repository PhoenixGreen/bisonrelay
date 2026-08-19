package resources

import (
	"context"
	"sync"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
)

// Swappable is a Provider that forwards to an inner provider which may be
// replaced at any time.
//
// It is installed as the client's top-level resource provider so that what a
// client hosts can change while it runs: turning hosting on, pointing it at a
// different directory, or adding a store all become a matter of building a
// fresh Router and swapping it in. Without it, hosting is fixed at startup,
// because nothing holds a reference to the router once the client is running.
//
// An empty Swappable returns ErrNotHosting, not ErrProviderNotFound: hosting
// nothing at all and hosting a site that lacks one page are different answers
// to a requester, and this is the only place that can tell them apart.
type Swappable struct {
	mtx   sync.Mutex
	inner Provider
}

// NewSwappable returns a Swappable holding the passed provider, which may be
// nil.
func NewSwappable(p Provider) *Swappable {
	return &Swappable{inner: p}
}

// Set replaces the inner provider. Passing nil unbinds the route.
func (s *Swappable) Set(p Provider) {
	s.mtx.Lock()
	s.inner = p
	s.mtx.Unlock()
}

// Get returns the current inner provider, which may be nil.
func (s *Swappable) Get() Provider {
	s.mtx.Lock()
	p := s.inner
	s.mtx.Unlock()
	return p
}

// Fulfill is part of the Provider interface.
func (s *Swappable) Fulfill(ctx context.Context, uid clientintf.UserID,
	req *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	p := s.Get()
	if p == nil {
		return nil, ErrNotHosting
	}
	return p.Fulfill(ctx, uid, req)
}
