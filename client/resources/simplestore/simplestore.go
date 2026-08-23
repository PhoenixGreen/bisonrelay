package simplestore

import (
	"bytes"
	"context"
	"encoding/hex"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"text/template"
	"time"

	"github.com/companyzero/bisonrelay/client"
	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/companyzero/bisonrelay/internal/strescape"
	"github.com/companyzero/bisonrelay/rpc"
	"github.com/decred/dcrd/chaincfg/v3"
	"github.com/decred/dcrd/dcrutil/v4"
	"github.com/decred/dcrd/txscript/v4/stdscript"
	"github.com/decred/dcrd/wire"
	"github.com/decred/dcrlnd/lnrpc"
	"github.com/decred/slog"
	"github.com/fsnotify/fsnotify"
	"github.com/pelletier/go-toml"
	"golang.org/x/sync/errgroup"
)

const (
	productsDir         = "products"
	cartsDir            = "carts"
	ordersDir           = "orders"
	pendingInvoicesDir  = "pendinginvoices"
	indexTmplFile       = "index.tmpl"
	prodTmplFile        = "product.tmpl"
	addToCartTmplFile   = "addtocart.tmpl"
	cartTmplFile        = "cart.tmpl"
	orderTmplFile       = "order.tmpl"
	ordersTmplFile      = "orders.tmpl"
	orderPlacedTmplFile = "orderplaced.tmpl"
	adminOrdersTmplFile = "admin_orders.tmpl"
	adminOrderTmplFile  = "admin_order.tmpl"
	navTmplFile         = "shopnav.tmpl"
)

type PayType string

const (
	PayTypeOnChain PayType = "onchain"
	PayTypeLN      PayType = "ln"
)

// Config holds the configuration for a simple store.
type Config struct {
	Root          string
	Log           slog.Logger
	LiveReload    bool
	OrderPlaced   func(order *Order, msg string)
	StatusChanged func(order *Order, msg string)
	PayType       PayType
	Account       string
	ShipCharge    float64
	Client        *client.Client
	LNPayClient   *client.DcrlnPaymentClient

	ExchangeRateProvider func() float64

	// ShopName and ShopTagline are what the shop calls itself, or empty for
	// a shop that would rather not say. Settings rather than lines in a
	// template: naming your own shop should not mean editing one.
	ShopName    string
	ShopTagline string

	// SiteRoot is the directory of the pages site hosted beside this store,
	// or empty when there is none. It is where the header and footer below
	// are read from, so a shop and the site it sits in share one banner
	// rather than each keeping its own copy.
	SiteRoot string

	// Header and Footer name the fragments wrapped round every page the
	// store renders. Empty means none, which is what a store hosted on its
	// own gets.
	//
	// Named rather than written out, because a shop is seven pages -- the
	// front, a product, the cart, the order list, an order, adding to the
	// cart, and the confirmation -- and a seller pasting a banner into
	// seven templates has seven places to keep in step. Naming a fragment
	// once means changing the banner changes all of them, and the pages of
	// the site along with them.
	Header string
	Footer string
}

// Store is a simple store instance. A simple store can render a front page
// (index) and individual product pages.
type Store struct {
	cfg         Config
	c           *client.Client
	log         slog.Logger
	root        string
	lnpc        *client.DcrlnPaymentClient
	runCtx      context.Context
	runCancel   func()
	chainParams *chaincfg.Params

	mtx      sync.Mutex
	products map[string]*Product
	tmpl     *template.Template

	// indexPath is where this store's front page answers, as a template
	// writes it in a link.
	//
	// Not always "/": a client hosting a pages site keeps the root for it,
	// and the store's front page moves aside to /store. Templates have to
	// be told, because a template that writes "/" is right in one
	// arrangement and sends the reader out of the shop in the other. Set
	// once by BindRoutes, before anything is served.
	indexPath string

	// shopName and shopTagline are what the shop calls itself.
	shopName    string
	shopTagline string

	// siteRoot, header and footer are the wrapper: see Config.
	siteRoot string
	header   string
	footer   string

	invoiceSettledChan  chan string
	invoiceCanceledChan chan string
	invoiceCreatedChan  chan *Order
}

// New creates a new simple store.
func New(cfg Config) (*Store, error) {
	log := slog.Disabled
	if cfg.Log != nil {
		log = cfg.Log
	}
	runCtx, runCancel := context.WithCancel(context.Background())

	s := &Store{
		cfg:         cfg,
		c:           cfg.Client,
		log:         log,
		root:        cfg.Root,
		products:    make(map[string]*Product),
		tmpl:        template.New("*root"),
		indexPath:   "/",
		shopName:    cfg.ShopName,
		shopTagline: cfg.ShopTagline,
		siteRoot:    cfg.SiteRoot,
		header:      cfg.Header,
		footer:      cfg.Footer,
		lnpc:        cfg.LNPayClient,
		runCtx:      runCtx,
		runCancel:   runCancel,

		invoiceSettledChan:  make(chan string),
		invoiceCanceledChan: make(chan string),
		invoiceCreatedChan:  make(chan *Order),
	}

	if err := s.reloadStore(); err != nil {
		return nil, err
	}
	return s, nil
}

// ReloadStore reads the templates and the catalogue again.
//
// The store parses its templates once at start-up, so anything that changes
// them on disk has to say so -- otherwise the shop goes on serving what it
// read then, and the change looks like it did nothing.
func (s *Store) ReloadStore() error { return s.reloadStore() }

func (s *Store) reloadStore() error {
	// Reset.
	products := make(map[string]*Product, len(s.products))
	tmpl := template.New("*root").Funcs(s.templateFuncs())

	// Parse templates.
	dirs := []string{s.root, filepath.Join(s.root, "static")}
	for _, dir := range dirs {
		filenames, err := filepath.Glob(filepath.Join(dir, "*.tmpl"))
		if err != nil {
			return err
		}
		for _, filename := range filenames {
			if filepath.Ext(filename) != ".tmpl" {
				continue
			}
			rawBytes, err := os.ReadFile(filename)
			if err != nil {
				return err
			}
			data := string(rawBytes)
			data = resources.ProcessEmbeds(data,
				s.root, s.log)

			s.log.Debugf("Reloading demplate %s (name %s)", filename, filepath.Base(filename))
			t := tmpl.New(filepath.Base(filename))
			_, err = t.Parse(data)
			if err != nil {
				return fmt.Errorf("unable to parse template %s: %v",
					filename, err)
			}
		}
	}

	// Load Products.
	prodDir := filepath.Join(s.root, productsDir)
	prodFiles, err := os.ReadDir(prodDir)
	if err != nil {
		return fmt.Errorf("unable to list product files: %v", err)
	}

	for _, prodFile := range prodFiles {
		if filepath.Ext(prodFile.Name()) != ".toml" {
			continue
		}
		fname := filepath.Join(prodDir, prodFile.Name())
		var prods productsFile
		f, err := os.Open(fname)
		if err != nil {
			return fmt.Errorf("unable to load product file %s: %v",
				fname, err)
		}
		dec := toml.NewDecoder(f)
		err = dec.Decode(&prods)
		_ = f.Close()
		if err != nil {
			return fmt.Errorf("unable to decode product file %s: %v",
				fname, err)
		}
		for _, prod := range prods.Products {
			if prod.Disabled {
				continue
			}

			if _, ok := products[prod.SKU]; ok {
				return fmt.Errorf("product with duplicated SKU %s in %s",
					prod.SKU, fname)
			}

			products[prod.SKU] = prod
		}
	}

	s.mtx.Lock()
	s.products = products
	s.tmpl = tmpl
	s.mtx.Unlock()

	return nil
}

// templateFuncs are what a template may call as well as read.
//
// A function rather than a field on every context: there are seven of those
// and they have nothing in common, so a field would have to be added to each
// and remembered for the next one. A function is there for all of them,
// including the partials, which have no context of their own at all.
func (s *Store) templateFuncs() template.FuncMap {
	return template.FuncMap{
		// storeIndex is where the shop's front page is, which is not
		// always "/". Read when the template runs rather than when it is
		// parsed, because binding decides it and that happens after.
		"storeIndex": func() string { return s.indexPath },

		// productImage is what a template writes to show a product's
		// picture, or empty for one with none. Built here so the assets
		// directory is named in one place and a template cannot spell it
		// differently.
		"productImage": ProductImagePath,

		// money and dcr are the two ways a price is written, and both are
		// true. A shop quotes in USD and is paid in DCR, and there is no
		// rate in this app for anything else -- so a price shown in a
		// buyer's own currency would be a number nobody can stand behind,
		// while the amount they actually commit to is worked out from the
		// USD one regardless of what the label said.
		"money": Money,
		"dcr":   s.approxDCR,

		// shopName is what the shop calls itself, or empty for a shop that
		// would rather not say. A setting rather than a line in a template,
		// because naming your own shop should not mean editing one.
		"shopName":    func() string { return s.shopName },
		"shopTagline": func() string { return s.shopTagline },
	}
}

// Fulfill answers one request, with the site's frame round it.
//
// The frame is put on here rather than in each handler: there are a dozen of
// them and they have one thing in common, which is that what they return is
// read as a page. See dress.go.
func (s *Store) Fulfill(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	res, err := s.fulfill(ctx, uid, request)
	if err != nil {
		return nil, err
	}
	return s.dressed(uid, request, res), nil
}

func (s *Store) fulfill(ctx context.Context, uid clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	// Admin handlers.
	if len(request.Path) > 0 && request.Path[0] == "admin" {
		if uid != s.c.PublicID() {
			return s.handleNotFound(ctx, uid, request)
		}
		switch {
		case pathEquals(request.Path, "admin"):
			return s.handleAdminIndex(ctx, uid, request)
		case pathEquals(request.Path, "admin", "orders"):
			return s.handleAdminOrders(ctx, uid, request)
		case pathHasPrefix(request.Path, "admin", "order"):
			return s.handleAdminViewOrder(ctx, uid, request)
		case pathHasPrefix(request.Path, "admin", "orderaddcomment"):
			return s.handleAdminAddOrderComment(ctx, uid, request)
		case pathHasPrefix(request.Path, "admin", "orderstatusto"):
			return s.handleAdminUpdateOrderStatus(ctx, uid, request)
		default:
			return s.handleNotFound(ctx, uid, request)
		}
	}

	switch {
	case len(request.Path) == 0 || request.Path[0] == "index.md":
		return s.handleIndex(ctx, uid, request)
	case len(request.Path) == 2 && request.Path[0] == "product":
		return s.handleProduct(ctx, uid, request)
	case pathEquals(request.Path, "addToCart"):
		return s.handleAddToCart(ctx, uid, request)
	case pathEquals(request.Path, "removeFromCart"):
		return s.handleRemoveFromCart(ctx, uid, request)
	case pathEquals(request.Path, "setCartQty"):
		return s.handleSetCartQuantity(ctx, uid, request)
	case len(request.Path) == 1 && request.Path[0] == "clearCart":
		return s.handleClearCart(ctx, uid)
	case len(request.Path) == 1 && request.Path[0] == "cart":
		return s.handleCart(ctx, uid, request)
	case len(request.Path) == 1 && request.Path[0] == "placeOrder":
		return s.handlePlaceOrder(ctx, uid, request)
	case len(request.Path) == 1 && request.Path[0] == "orders":
		return s.handleOrders(ctx, uid, request)
	case len(request.Path) == 2 && request.Path[0] == "order":
		return s.handleOrderStatus(ctx, uid, request)
	case len(request.Path) == 2 && request.Path[0] == "orderaddcomment":
		return s.handleOrderAddComment(ctx, uid, request)
	case len(request.Path) == 2 && request.Path[0] == AssetsDir:
		return s.handleAsset(ctx, uid, request)
	case len(request.Path) == 2 && request.Path[0] == "static":
		return s.handleStaticRequest(ctx, uid, request)
	default:
		return s.handleNotFound(ctx, uid, request)
	}
}

func (s *Store) reloadFSWatchers(watcher *fsnotify.Watcher) {
	// We ignore watching errors here as these are not critical to the
	// operation of the store.

	prevWatches := watcher.WatchList()
	for _, w := range prevWatches {
		err := watcher.Remove(w)
		if err != nil {
			s.log.Warnf("Unable to remove previous watcher %s: %v",
				w, err)
		}
	}

	if err := watcher.Add(filepath.Join(s.root, productsDir)); err != nil {
		s.log.Warnf("Unable to watch products dir: %v", err)
	}

	if err := watcher.Add(filepath.Join(s.root)); err != nil {
		s.log.Warnf("Unable to watch root dir: %v", err)
	}
}

func (s *Store) runFSWatcher(ctx context.Context, watcher *fsnotify.Watcher) {
	s.reloadFSWatchers(watcher)

	// chanReload is used to debounce file events so that we only reload
	// once when multiple events happen in sequence.
	var chanReload <-chan time.Time

	s.log.Debugf("Starting FS watcher")
	for {
		select {
		case <-ctx.Done():
			return

		case <-chanReload:
			chanReload = nil
			err := s.reloadStore()
			if err != nil {
				s.log.Errorf("Unable to reload store: %v", err)
			} else {
				s.log.Infof("Reloaded store")
			}
			s.reloadFSWatchers(watcher)

		case event, ok := <-watcher.Events:
			if !ok {
				s.log.Warnf("watcher.Events not ok")
				return
			}
			s.log.Debugf("Watcher event: %s", event)
			chanReload = time.After(time.Millisecond * 100)

		case err, ok := <-watcher.Errors:
			if !ok {
				s.log.Warnf("watcher.Errors not ok")
				return
			}
			s.log.Debugf("Watcher error: %v", err)
		}
	}
}

// runLNInvoiceWatcher watches LN invoices and tells the main invoice watcher
// routine whenever one is settled.
func (s *Store) runLNInvoiceWatcher(ctx context.Context) error {
	stream, err := s.lnpc.LNRPC().SubscribeInvoices(ctx, &lnrpc.InvoiceSubscription{})
	if err != nil {
		return err
	}

	for {
		inv, err := stream.Recv()
		if err != nil {
			return err
		}

		switch inv.State {
		case lnrpc.Invoice_SETTLED:
			select {
			case s.invoiceSettledChan <- inv.PaymentRequest:
			case <-ctx.Done():
				return ctx.Err()
			}
		case lnrpc.Invoice_CANCELED:
			select {
			case s.invoiceCanceledChan <- inv.PaymentRequest:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
}

// runOnChainInvoiceWatcher watches for on-chain transactions that may complete
// orders.
func (s *Store) runOnChainInvoiceWatcher(ctx context.Context) error {
	// TODO: have some way to look for transactions upon restart.

	stream, err := s.lnpc.LNRPC().SubscribeTransactions(ctx, &lnrpc.GetTransactionsRequest{})
	if err != nil {
		return err
	}
	for {
		tx, err := stream.Recv()
		if err != nil {
			return err
		}

		// TODO: use different number of confirmations based on the
		// the amount.
		if tx.NumConfirmations < 1 {
			continue
		}

		msgTx := wire.NewMsgTx()
		if err := msgTx.Deserialize(hex.NewDecoder(bytes.NewBuffer([]byte(tx.RawTxHex)))); err != nil {
			s.log.Warnf("Unable to deserialize raw tx %s", tx.TxHash)
			continue
		}

		for _, out := range msgTx.TxOut {
			_, addrs := stdscript.ExtractAddrs(out.Version, out.PkScript, s.chainParams)
			if len(addrs) != 1 {
				// All addressses we create here are standard
				// P2PKH, so skip any that are not that.
				continue
			}

			discriminator := onChainInvoiceDiscriminator(addrs[0].String(), dcrutil.Amount(out.Value))
			select {
			case s.invoiceSettledChan <- discriminator:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
	}
}

// removePendingInvoice removes an order from the list of orders with pending
// invoice.
func (s *Store) removePendingInvoice(order *Order) {
	dir := filepath.Join(s.root, pendingInvoicesDir)
	fname := filepath.Join(dir, fmt.Sprintf("%s-%s", order.User, order.ID))
	err := jsonfile.RemoveIfExists(fname)
	if err != nil {
		s.log.Warnf("Unable to remove pending order %s: %v",
			fname, err)
	}
}

// invoiceSettled is called when an invoice for a given order was settled (paid)
// by the user.
func (s *Store) invoiceSettled(ctx context.Context, order *Order) {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	// Remove pending invoice if exists.
	s.removePendingInvoice(order)

	// Mark order as paid. First, reload the full order from disk.
	orderDir := filepath.Join(s.root, ordersDir, order.User.String())
	orderFname := filepath.Join(orderDir, orderFnamePattern.FilenameFor(uint64(order.ID)))
	order = new(Order)
	if err := jsonfile.Read(orderFname, order); err != nil {
		s.log.Warnf("Unable to read order %s: %v", orderFname, err)
		return
	}

	// Now update status.
	order.Status = StatusPaid
	if err := jsonfile.Write(orderFname, order, s.log); err != nil {
		s.log.Warnf("Unable to write order %s: %v", orderFname, err)
		return
	}

	ru, err := s.c.UserByID(order.User)
	if err != nil {
		s.log.Warnf("Order #%d placed by unknown user %s",
			order.ID, order.User)
		return
	}

	s.log.Infof("Detected order %s/%s from user %s as paid",
		order.User.ShortLogID(), order.ID, strescape.Nick(ru.Nick()))

	// Finally, send a message to user acknowledging payment.
	var b strings.Builder
	wpm := func(f string, args ...interface{}) {
		b.WriteString(fmt.Sprintf(f, args...))
	}
	wpm("Your order %s/%s has been identified as paid",
		order.User.ShortLogID(), order.ID)

	// If the order has files attached to it, send them to the user.
	for _, item := range order.Cart.Items {
		fname := item.Product.SendFilename
		if item.Product.SendFilename == "" {
			continue
		}

		// Relative paths are set to be from the root of the simplestore.
		if !filepath.IsAbs(fname) {
			fname = filepath.Join(s.root, fname)
		}
		wpm("\nSending you the file %s included in your order",
			filepath.Base(fname))
		go func() {
			err := s.c.SendFile(order.User, 0, fname, nil)
			if err != nil {
				s.log.Errorf("Unable to send file %s to user %s due to order %s/%s: %v",
					fname, strescape.Nick(ru.Nick()),
					order.User.ShortLogID(), order.ID, err)
			} else {
				s.log.Infof("Successfully sent file %v to user %s due to order %s/%s",
					fname, strescape.Nick(ru.Nick()),
					order.User.ShortLogID(), order.ID)
			}
		}()
	}

	if s.cfg.StatusChanged != nil {
		s.cfg.StatusChanged(order, b.String())
	}
}

// invoiceExpired is called when the invoice of an order has expired.
func (s *Store) invoiceExpired(ctx context.Context, order *Order) {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	// Remove pending invoice if exists.
	s.removePendingInvoice(order)

	// Mark order as paid. First, reload the full order from disk.
	orderDir := filepath.Join(s.root, ordersDir, order.User.String())
	orderFname := filepath.Join(orderDir, orderFnamePattern.FilenameFor(uint64(order.ID)))
	order = new(Order)
	if err := jsonfile.Read(orderFname, order); err != nil {
		s.log.Warnf("Unable to read order %s: %v", orderFname, err)
		return
	}

	// Now update status.
	order.Status = StatusPaid
	if err := jsonfile.Write(orderFname, order, s.log); err != nil {
		s.log.Warnf("Unable to write order %s: %v", orderFname, err)
		return
	}

	ru, err := s.c.UserByID(order.User)
	if err != nil {
		s.log.Warnf("Order #%d placed by unknown user %s",
			order.ID, order.User)
		return
	}

	s.log.Infof("Detected order %s/%s from user %s as expired",
		order.User.ShortLogID(), order.ID, strescape.Nick(ru.Nick()))

	// Finally, send a message to user noting the expiration.
	var b strings.Builder
	wpm := func(f string, args ...interface{}) {
		b.WriteString(fmt.Sprintf(f, args...))
	}
	wpm("Your order %s/%s has been identified as expired",
		order.User.ShortLogID(), order.ID)

	if s.cfg.StatusChanged != nil {
		s.cfg.StatusChanged(order, b.String())
	}
}

// runInvoiceWatcher is the main routine that handles changes to the status
// of invoices associated with orders.
func (s *Store) runInvoiceWatcher(ctx context.Context) error {
	// List orders with pending invoices.
	s.mtx.Lock()
	dirPending := filepath.Join(s.root, pendingInvoicesDir)
	entries, err := os.ReadDir(dirPending)
	if err != nil && !os.IsNotExist(err) {
		s.mtx.Unlock()
		return err
	}

	// Create map of raw invoice to pending id.
	invoices := make(map[string]*Order, len(entries))

	// Load list of pending orders. The names in the pending invoices
	// dir is "<uid>-<order_id>".
	nameRegexp := regexp.MustCompile(`([0-9a-fA-F]{64})-([0-9]*)`)
	for _, entry := range entries {
		name := entry.Name()
		matches := nameRegexp.FindStringSubmatch(name)
		if len(matches) != 3 {
			continue
		}
		var uid clientintf.UserID
		if err := uid.FromString(matches[1]); err != nil {
			continue
		}
		var oid OrderID
		if err := oid.FromString(matches[2]); err != nil {
			continue
		}
		order := new(Order)
		fname := filepath.Join(s.root, ordersDir, uid.String(),
			orderFnamePattern.FilenameFor(uint64(oid)))
		if err := jsonfile.Read(fname, order); err != nil {
			s.log.Warnf("Unable to load order %s: %v", fname, err)
			continue
		}
		if order.Invoice == "" || order.ExpiresTS.Before(time.Now()) {
			go s.invoiceExpired(ctx, order)
			continue
		}
		if order.Status != StatusPlaced {
			s.removePendingInvoice(order)
			continue
		}
		invoices[order.invoiceDiscriminator()] = order
	}
	s.mtx.Unlock()

	// Timer that is triggered on the next time one of the invoices needs
	// to be timed out.
	nextExpiresTimer := time.NewTimer(time.Duration(math.MaxInt64))
	nextExpiresTimer.Stop()
	resetNextExpiresTimer := func() {
		var nextExpiresTime time.Time
		for _, order := range invoices {
			if nextExpiresTime.IsZero() || order.ExpiresTS.Before(nextExpiresTime) {
				nextExpiresTime = order.ExpiresTS
			}
		}
		if nextExpiresTime.IsZero() {
			return
		}
		nextExpiresTimer.Reset(time.Until(nextExpiresTime))
	}
	resetNextExpiresTimer()

	// Main loop: handle the outcome of invoices.
	for {
		select {
		case order := <-s.invoiceCreatedChan:
			invoices[order.invoiceDiscriminator()] = order

		case inv := <-s.invoiceSettledChan:
			if order := invoices[inv]; order != nil {
				delete(invoices, inv)
				go s.invoiceSettled(ctx, order)
			}

		case inv := <-s.invoiceCanceledChan:
			delete(invoices, inv)

		case <-nextExpiresTimer.C:
			now := time.Now()
			for _, order := range invoices {
				if !order.ExpiresTS.Before(now) {
					continue
				}
				delete(invoices, order.invoiceDiscriminator())
				go s.invoiceExpired(ctx, order)
			}
			resetNextExpiresTimer()

		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

// Run the simple store functions.
func (s *Store) Run(ctx context.Context) error {
	chainParams, err := s.lnpc.ChainParams(ctx)
	if err != nil {
		return err
	}
	s.chainParams = chainParams

	g, gctx := errgroup.WithContext(ctx)

	g.Go(func() error {
		<-gctx.Done()
		s.runCancel()
		return gctx.Err()
	})

	if s.cfg.LiveReload {
		g.Go(func() error {
			watcher, err := fsnotify.NewWatcher()
			if err != nil {
				return fmt.Errorf("unable to start filesystem watcher: %s", err)
			}

			s.runFSWatcher(gctx, watcher)
			return watcher.Close()
		})
	}

	g.Go(func() error { return s.runLNInvoiceWatcher(ctx) })
	g.Go(func() error { return s.runOnChainInvoiceWatcher(ctx) })
	g.Go(func() error { return s.runInvoiceWatcher(ctx) })

	return g.Wait()
}

// storeRoutePrefixes are the path prefixes the store answers on, excluding
// its index. They mirror the switch in Fulfill and exist so a router can bind
// the store beside another provider without either having to know the other's
// paths.
var storeRoutePrefixes = [][]string{
	{"product"},
	{"addToCart"},
	{"clearCart"},
	{"removeFromCart"},
	{"setCartQty"},
	{"cart"},
	{"placeOrder"},
	{"orders"},
	{"order"},
	{"orderaddcomment"},
	{"static"},
	{AssetsDir},
	{"admin"},
}

// StoreIndexPath is the path a store mounted beside a pages site answers its
// front page on. A store mounted on its own answers the index at the root, as
// it always has.
const StoreIndexPath = "store"

// BindRoutes binds the store into the passed router.
//
// With withIndex, the store also takes the root and "index.md", which is how
// a store-only client has always been served. Without it, the root is left
// for a pages provider and the store's front page moves to StoreIndexPath --
// every other store path is unchanged, so templates that link to "/cart" or
// "/admin" keep working either way.
func (s *Store) BindRoutes(r *resources.Router, withIndex bool) {
	if withIndex {
		r.BindExactPath(nil, s)
		r.BindExactPath([]string{"index.md"}, s)
	} else {
		// The front page has moved, so a template writing "/" would send
		// the reader out of the shop and onto the site's own front page.
		s.indexPath = "/" + StoreIndexPath

		// Rewrite the mount path to the index the handlers expect,
		// rather than teaching every template a prefix.
		r.BindExactPath([]string{StoreIndexPath}, resources.ProviderFunc(
			func(ctx context.Context, uid clientintf.UserID,
				req *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

				indexReq := *req
				indexReq.Path = []string{"index.md"}
				return s.Fulfill(ctx, uid, &indexReq)
			}))
	}

	for _, prefix := range storeRoutePrefixes {
		r.BindPrefixPath(prefix, s)
	}
}
