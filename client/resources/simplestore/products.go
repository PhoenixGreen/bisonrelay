package simplestore

import (
	"fmt"
	"strconv"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/decred/dcrd/dcrutil/v4"
)

type Product struct {
	Title       string   `json:"title"`
	SKU         string   `json:"sku"`
	Description string   `json:"description"`
	Tags        []string `json:"tags"`
	Price       float64  `json:"price"`
	Disabled    bool     `json:"disabled,omitempty"`
	Shipping    bool     `json:"shipping"`

	// Image names a picture in the store's assets directory -- "banner.jpg",
	// not a path -- or is empty for a product with none.
	//
	// A file rather than something written into the page. A shop front
	// showing a dozen products with their pictures inlined would be a dozen
	// pictures in one message, and a message may carry 1 MiB: the front page
	// of a shop with anything in it would simply not fit. Asked for on its
	// own, a picture crosses the wire once and the page draws while they are
	// still on their way. See assets.go.
	Image        string `json:"image"`
	SendFilename string `json:"send_filename"`
}

type productsFile struct {
	Products []*Product
}

type CartItem struct {
	Product  *Product `json:"product"`
	Quantity uint32   `json:"quantity"`
}

type Cart struct {
	Items   []*CartItem `json:"items"`
	Updated time.Time   `json:"updated"`
}

// HasCharges returns true if at least one item has a positive charge amount.
func (cart *Cart) HasCharges() bool {
	for _, item := range cart.Items {
		if item.Quantity > 0 && item.Product.Price > 0 {
			return true
		}
	}

	return false
}

// Total returns the total amount, with 2 decimal places accuracy.
// Total is what one line of a cart comes to: the price times how many.
//
// On the item rather than worked out in a template, because a template
// cannot multiply without saying so awkwardly, and a cart that shows a unit
// price and a quantity but no line total leaves the buyer doing the sum.
func (item *CartItem) Total() float64 {
	return item.Product.Price * float64(item.Quantity)
}

func (cart *Cart) TotalCents() int64 {
	var totalUSDCents int64
	for _, item := range cart.Items {
		totalItemUSDCents := int64(item.Quantity) * int64(item.Product.Price*100)
		totalUSDCents += totalItemUSDCents
	}
	return totalUSDCents
}

// Total returns the total cart amount in USD.
func (cart *Cart) Total() float64 {
	return float64(cart.TotalCents()) / 100
}

type OrderID uint32

func (id OrderID) String() string {
	return fmt.Sprintf("%08d", id)
}

// Num is the order's number as somebody would say it.
//
// String pads to eight digits, which is what an order's file is called and
// how it sorts in a directory. On a page it reads as a serial number from a
// machine -- "Order #00000003" -- where what the buyer has is their third
// order.
func (id OrderID) Num() uint32 { return uint32(id) }

func (id *OrderID) FromString(s string) error {
	i, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return err
	}
	*id = OrderID(i)
	return nil
}

type OrderStatus string

const (
	StatusPlaced    OrderStatus = "placed"
	StatusPaid      OrderStatus = "paid"
	StatusShipped   OrderStatus = "shipped"
	StatusCompleted OrderStatus = "completed"
	StatusCanceled  OrderStatus = "canceled"
)

type ShippingAddress struct {
	Name        string `json:"name"`
	Address1    string `json:"address1"`
	Address2    string `json:"address2"`
	City        string `json:"city"`
	State       string `json:"state"`
	PostalCode  string `json:"postalCode"`
	Phone       string `json:"phone"`
	CountryCode string `json:"countrycode"`
}

type OrderComment struct {
	Timestamp time.Time `json:"ts"`
	FromAdmin bool      `json:"fromAdmin"`
	Comment   string    `json:"comment"`
}

type Order struct {
	ID           OrderID           `json:"id"`
	User         clientintf.UserID `json:"user"`
	Cart         Cart              `json:"cart"`
	Status       OrderStatus       `json:"status"`
	PlacedTS     time.Time         `json:"placed_ts"`
	ResolvedTS   *time.Time        `json:"resolved_ts"`
	ShipCharge   float64           `json:"ship_charge"`
	ExchangeRate float64           `json:"exchange_rate"`
	PayType      PayType           `json:"pay_type"`
	Invoice      string            `json:"invoice"`
	ShipAddr     *ShippingAddress  `json:"shipping"`
	Comments     []OrderComment    `json:"comments"`
	ExpiresTS    time.Time         `json:"expires_ts"`

	// SeenTS is when the shop first saw the payment for this order, before
	// the network had confirmed it.
	//
	// Only on-chain has this middle state: a Lightning payment either
	// settles or does not. Recorded because it is the answer to the question
	// a buyer asks in that gap -- has it arrived? -- and because it is the
	// reason not to let the order lapse while a transaction for it is
	// already in the mempool.
	SeenTS *time.Time `json:"seen_ts"`
}

// Total returns the total amount, with 2 decimal places accuracy.
func (order *Order) TotalCents() int64 {
	totalUSDCents := order.Cart.TotalCents()
	if order.ShipCharge > 0 {
		totalUSDCents += int64(order.ShipCharge * 100)
	}
	return totalUSDCents
}

// Total returns the total amount as a float USD.
func (order *Order) Total() float64 {
	return float64(order.TotalCents()) / 100
}

// TotalDCR returns the total order amount in DCR, given the configured exchange
// rate.
func (order *Order) TotalDCR() dcrutil.Amount {
	if order.ExchangeRate == 0 {
		return 0
	}
	totalDCR := order.Total() / order.ExchangeRate
	amount, _ := dcrutil.NewAmount(totalDCR)
	return amount
}

// onChainInvoiceDiscriminator returns the unique(ish) order discriminator for
// onchain payments.
func onChainInvoiceDiscriminator(addr string, amount dcrutil.Amount) string {
	return fmt.Sprintf("%s_%d", addr, amount)
}

// invoiceDiscriminator returns a unique(ish) invoice discriminator for this
// order. For LN payments, this is the invoice itself. For on-chain payments,
// this is the payment address + expected payment amount.
func (order *Order) invoiceDiscriminator() string {
	switch order.PayType {
	case PayTypeLN:
		return order.Invoice
	case PayTypeOnChain:
		return onChainInvoiceDiscriminator(order.Invoice, order.TotalDCR())
	default:
		return ""
	}
}
