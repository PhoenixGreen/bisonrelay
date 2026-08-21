package simplestore

import "regexp"

// untrusted.go neutralises the markup in text a customer supplies.
//
// A store's pages are Go templates, and the templates are text/template
// rather than html/template -- there is no escaping, and there is nowhere
// obvious to put any, since what comes out is Markdown rather than HTML.
// So a name, an address or a comment written by whoever placed an order is
// rendered into a page the seller then reads in their own client.
//
// Bison Relay's page markup is not decorative. --embed[...]-- puts a picture
// or a file download on the page, --form-- puts something to fill in and
// submit, --include[...]-- pulls in a fragment, and a br:// link goes to
// somebody's site. A customer able to write those into an order is able to
// put a form, or a download, in front of the seller on the seller's own
// order page -- which reads as the store's own, because it is.
//
// Nothing here can execute: the renderer draws, it does not run. What it
// prevents is the seller being shown something that appears to come from
// their own store and does not.

// _markerRun is two or more hyphens together.
//
// Every one of Bison Relay's page markers opens with two -- --embed,
// --form--, --include, --grid, --row and the rest -- so breaking the pair
// disarms all of them, including any added later. Matching the markers by
// name would have to be kept in step with them for ever, and would be wrong
// the first time somebody forgot.
var _markerRun = regexp.MustCompile(`-{2,}`)

// EscapeUntrusted makes text supplied by a customer safe to render.
//
// Runs of hyphens collapse to one. A customer writing an em-dash as "--"
// loses a hyphen, which is a small price beside a customer writing a form.
// Deliberately not a removal of anything else: the point is to stop text
// being read as structure, not to censor what somebody may say.
func EscapeUntrusted(s string) string {
	return _markerRun.ReplaceAllString(s, "-")
}

// escapeAddress returns the address with every field a customer typed made
// safe. Applied where the address arrives rather than where it is shown, so
// that anything rendering it later is safe without having to remember.
func escapeAddress(a *ShippingAddress) *ShippingAddress {
	if a == nil {
		return nil
	}
	out := *a
	out.Name = EscapeUntrusted(out.Name)
	out.Address1 = EscapeUntrusted(out.Address1)
	out.Address2 = EscapeUntrusted(out.Address2)
	out.City = EscapeUntrusted(out.City)
	out.State = EscapeUntrusted(out.State)
	out.PostalCode = EscapeUntrusted(out.PostalCode)
	out.Phone = EscapeUntrusted(out.Phone)
	out.CountryCode = EscapeUntrusted(out.CountryCode)
	return &out
}
