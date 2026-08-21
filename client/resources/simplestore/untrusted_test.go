package simplestore

import (
	"strings"
	"testing"
)

// untrusted_test.go covers what a customer can write into an order.
//
// A store's pages are text/template, which does not escape, and what comes
// out of them is Markdown that the other party reads in their own client. So
// the markup in a name, an address or a comment is the thing to disarm: not
// because it can run -- the renderer draws, it does not run -- but because a
// form or a download shown on a seller's own order page reads as the store's,
// because it is.

func TestEscapeUntrustedDisarmsPageMarkup(t *testing.T) {
	for _, attack := range []string{
		"--form--\ntype=\"text\" name=\"card\"\n--/form--",
		"--embed[type=image/png,data=AAAA]--",
		"--embed[download=" + strings.Repeat("a", 64) + "]--",
		"--include[header]--",
		"--header--\n--row[90,left]--\nx\n--/row--\n--/header--",
		"--nav[pills]--\n[Pay here](br://abc/pay)\n--/nav--",
		"--grid--\nx\n--/grid--",
		"--columns[2]--\nx\n--/columns--",
		"--cards--\n--card--\ntitle: Pay\n--/card--\n--/cards--",
		"--section id=x --\ny\n--/section--",
		"--endofpost--",
	} {
		got := EscapeUntrusted(attack)
		if strings.Contains(got, "--") {
			t.Errorf("a marker survived:\nin  %q\nout %q", attack, got)
		}
	}
}

func TestEscapeUntrustedLeavesOrdinaryWritingAlone(t *testing.T) {
	for _, ok := range []string{
		"Please leave it with the neighbour",
		"Flat 3-B, 12 King's Road",
		"order #4 - the blue one",
		"my e-mail is me@example.com",
		"",
	} {
		if got := EscapeUntrusted(ok); got != ok {
			t.Errorf("changed ordinary text:\nin  %q\nout %q", ok, got)
		}
	}
}

func TestEscapeUntrustedIsIdempotent(t *testing.T) {
	// Applied where the text arrives and again where it is stored, so
	// doing it twice has to mean what doing it once meant.
	in := "--form-- and -- dashes"
	once := EscapeUntrusted(in)
	if twice := EscapeUntrusted(once); twice != once {
		t.Fatalf("once %q, twice %q", once, twice)
	}
}

func TestAnAddressIsEscapedInEveryField(t *testing.T) {
	bad := "--embed[download=x]--"
	got := escapeAddress(&ShippingAddress{
		Name: bad, Address1: bad, Address2: bad, City: bad,
		State: bad, PostalCode: bad, Phone: bad, CountryCode: bad,
	})
	for name, v := range map[string]string{
		"Name": got.Name, "Address1": got.Address1,
		"Address2": got.Address2, "City": got.City, "State": got.State,
		"PostalCode": got.PostalCode, "Phone": got.Phone,
		"CountryCode": got.CountryCode,
	} {
		if strings.Contains(v, "--") {
			t.Errorf("%s was left as %q", name, v)
		}
	}

	if escapeAddress(nil) != nil {
		t.Fatal("an order with no address should stay that way")
	}
}
