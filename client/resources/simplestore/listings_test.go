package simplestore

import (
	"io/fs"
	"strings"
	"testing"
)

// listings_test.go covers which pages of the shop may change a cart.
//
// A cart line is editable: it carries a quantity to set and a way to remove
// it. An order is a record of what was bought and is not -- and the danger
// is specific rather than cosmetic. The remove and quantity forms post the
// SKU to the *cart*, so a Remove button drawn on a placed order would not
// edit that order at all. It would quietly change what the buyer is about to
// buy next, from a page about something they have already paid for.

// editableListing is the include that draws a cart line with its controls.
const editableListing = "cart-listing.tmpl"

func templateBody(t *testing.T, name string) string {
	t.Helper()
	data, err := storeTemplate.ReadFile("template/" + name)
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

func TestOnlyTheCartMayChangeTheCart(t *testing.T) {
	pages, err := fs.Glob(storeTemplate, "template/*.tmpl")
	if err != nil {
		t.Fatal(err)
	}

	for _, path := range pages {
		name := strings.TrimPrefix(path, "template/")
		if name == editableListing {
			continue
		}
		body := templateBody(t, name)
		// The plain listing's name contains the editable one's, so the
		// include has to be matched exactly.
		if !strings.Contains(body, `"`+editableListing+`"`) {
			continue
		}
		if name != "cart.tmpl" {
			t.Errorf("%s draws cart lines with their controls: a Remove "+
				"button there posts to the cart, not to what the page is "+
				"about", name)
		}
	}
}

func TestTheCartIsStillEditable(t *testing.T) {
	// The other half: making the guard above pass by taking the controls
	// away from everything would leave a cart nobody can change, which is
	// the fault this all started with.
	body := templateBody(t, "cart.tmpl")
	if !strings.Contains(body, `"`+editableListing+`"`) {
		t.Fatal("the cart no longer draws its lines with their controls")
	}
	listing := templateBody(t, editableListing)
	for _, want := range []string{"/setCartQty", "/removeFromCart"} {
		if !strings.Contains(listing, want) {
			t.Errorf("a cart line has no %s", want)
		}
	}
}

func TestAnOrderShowsWhatItCameTo(t *testing.T) {
	// Every page that lists what was bought says what it cost, through the
	// same helper, so no page invents its own way of writing a price.
	for _, name := range []string{
		"order.tmpl", "orderplaced.tmpl", "orders.tmpl", "cart.tmpl",
	} {
		if !strings.Contains(templateBody(t, name), "money ") {
			t.Errorf("%s writes a price without the money helper", name)
		}
	}
}
