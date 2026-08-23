package golib

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/companyzero/bisonrelay/client"
	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/client/resources/simplestore"
	"github.com/decred/slog"
)

// Hosting modes. A client either serves nothing, a directory of markdown
// pages, a simple store, or a pages site with the store's paths bound
// alongside it (see simplestore.Store.BindRoutes).
const (
	hostModeOff           = "off"
	hostModePages         = "pages"
	hostModeStore         = "store"
	hostModePagesAndStore = "both"

	// The two upstream modes are set by config file only: they hand
	// hosting to something outside the app, so there is nothing for the UI
	// to edit.
	hostModeHTTP      = "http"
	hostModeClientRPC = "clientrpc"
)

// siteRootFor is the pages directory a store should read its header and
// footer from, or empty when no site is being hosted beside it.
//
// A store hosted alone has nothing to wear: there is no site, so naming a
// fragment would only put markers round every page that expand to nothing.
func siteRootFor(cfg pagesHostConfig) string {
	if cfg.Mode != hostModePages && cfg.Mode != hostModePagesAndStore {
		return ""
	}
	return cfg.PagesPath
}

// pagesHostConfig is what the UI can change about hosting. It round-trips to
// Dart, and is also what the legacy `[resources] upstream = ...` config line
// is parsed into at startup.
type pagesHostConfig struct {
	Mode            string  `json:"mode"`
	PagesPath       string  `json:"pages_path"`
	StorePath       string  `json:"store_path"`
	StorePayType    string  `json:"store_pay_type"`
	StoreAccount    string  `json:"store_account"`
	StoreShipCharge float64 `json:"store_ship_charge"`

	// StoreHeader and StoreFooter name the fragments the store wears, or
	// are empty for a shop that keeps its own look.
	StoreHeader string `json:"store_header"`
	StoreFooter string `json:"store_footer"`

	// StoreName and StoreTagline are what the shop calls itself, or are
	// empty for a shop that would rather not say. Settings rather than
	// lines in a template: naming your own shop should not mean editing
	// one, and a shop that had to would be called "My Shop" for ever.
	StoreName    string `json:"store_name"`
	StoreTagline string `json:"store_tagline"`

	// HTTPUpstream is the base URL served in hostModeHTTP.
	HTTPUpstream string `json:"http_upstream"`
}

// editable reports whether this mode is one the UI offers. The upstream modes
// are deliberately not: the app is not the thing serving in those.
func (cfg pagesHostConfig) editable() bool {
	switch cfg.Mode {
	case hostModeHTTP, hostModeClientRPC:
		return false
	}
	return true
}

// pagesHost owns what this client serves to others, and can rebuild it while
// the client runs.
//
// The client is handed a single Swappable at startup; every change replaces
// the Router inside it. That is the whole reason this type exists: the
// client reads cfg.ResourcesProvider once and never again, so hosting was
// previously fixed for the life of the process and only settable by editing
// the config file by hand.
type pagesHost struct {
	slot *resources.Swappable
	log  slog.Logger

	// appDataDir is where the app keeps everything else, and where a site
	// and a store are offered by default. It comes from the running app
	// rather than dcrutil.AppDataDir: bruig and brclient keep their data
	// in different places, and offering the wrong one would quietly serve
	// an empty directory.
	appDataDir string

	mtx       sync.Mutex
	cfg       pagesHostConfig
	store     *simplestore.Store
	storeStop func()
	c         *client.Client
	lnpc      *client.DcrlnPaymentClient
	ratesFn   func() float64
	orderNtfn func(order *simplestore.Order, msg string)
	runCtx    context.Context

	// rpcRouter is the router the clientrpc resources service binds into,
	// when hosting is delegated to an external client over the RPC
	// interface.
	rpcRouter *resources.Router
}

func newPagesHost(log slog.Logger, appDataDir string) *pagesHost {
	return &pagesHost{
		slot:       resources.NewSwappable(nil),
		log:        log,
		appDataDir: appDataDir,
		cfg:        pagesHostConfig{Mode: hostModeOff},
	}
}

// provider is what gets handed to client.Config.ResourcesProvider.
func (ph *pagesHost) provider() resources.Provider { return ph.slot }

// attach supplies the pieces a store needs, which only exist once the client
// itself does.
func (ph *pagesHost) attach(ctx context.Context, c *client.Client,
	lnpc *client.DcrlnPaymentClient, ratesFn func() float64,
	orderNtfn func(order *simplestore.Order, msg string)) {

	ph.mtx.Lock()
	ph.runCtx = ctx
	ph.c = c
	ph.lnpc = lnpc
	ph.ratesFn = ratesFn
	ph.orderNtfn = orderNtfn
	ph.mtx.Unlock()
}

// config returns the hosting configuration currently in effect.
func (ph *pagesHost) config() pagesHostConfig {
	ph.mtx.Lock()
	defer ph.mtx.Unlock()
	return ph.cfg
}

// parseUpstream turns the config file's hosting lines into a hosting config.
//
// The legacy `upstream = pages:/path` / `upstream = simplestore:/path` forms
// keep behaving exactly as they did. A separate storePath alongside a pages
// upstream is the one thing they could not express: a site with a shop in it.
func parseUpstream(upstream, storePath, payType, account string,
	shipCharge float64, header, footer, name, tagline string) pagesHostConfig {
	cfg := pagesHostConfig{
		Mode:            hostModeOff,
		StorePayType:    payType,
		StoreAccount:    account,
		StoreShipCharge: shipCharge,
		StoreHeader:     header,
		StoreFooter:     footer,
		StoreName:       name,
		StoreTagline:    tagline,
	}
	switch {
	case strings.HasPrefix(upstream, "pages:"):
		cfg.Mode = hostModePages
		cfg.PagesPath = upstream[len("pages:"):]
	case strings.HasPrefix(upstream, "simplestore:"):
		cfg.Mode = hostModeStore
		cfg.StorePath = upstream[len("simplestore:"):]
	case strings.HasPrefix(upstream, "http://"),
		strings.HasPrefix(upstream, "https://"):
		cfg.Mode = hostModeHTTP
		cfg.HTTPUpstream = upstream
	case upstream == "clientrpc":
		cfg.Mode = hostModeClientRPC
	}

	if storePath != "" && cfg.editable() {
		cfg.StorePath = storePath
		if cfg.Mode == hostModePages {
			cfg.Mode = hostModePagesAndStore
		} else if cfg.Mode == hostModeOff {
			cfg.Mode = hostModeStore
		}
	}
	return cfg
}

// apply rebuilds what this client serves. It is safe to call at any time,
// including before the client exists (in which case a store cannot be
// started and is reported as an error).
func (ph *pagesHost) apply(cfg pagesHostConfig) error {
	ph.mtx.Lock()
	defer ph.mtx.Unlock()

	// The upstream modes bind a single provider and have nothing else to
	// build.
	switch cfg.Mode {
	case hostModeHTTP:
		router := resources.NewRouter()
		router.BindPrefixPath(nil, resources.NewHttpProvider(cfg.HTTPUpstream))
		ph.stopStoreLocked()
		ph.slot.Set(router)
		ph.cfg = cfg
		return nil

	case hostModeClientRPC:
		// Left empty here: the clientrpc resources service binds its
		// own routes into it as remote clients subscribe.
		router := resources.NewRouter()
		ph.stopStoreLocked()
		ph.rpcRouter = router
		ph.slot.Set(router)
		ph.cfg = cfg
		return nil
	}

	wantPages := cfg.Mode == hostModePages || cfg.Mode == hostModePagesAndStore
	wantStore := cfg.Mode == hostModeStore || cfg.Mode == hostModePagesAndStore

	if wantPages && cfg.PagesPath == "" {
		return fmt.Errorf("pages hosting needs a directory")
	}
	if wantStore && cfg.StorePath == "" {
		return fmt.Errorf("store hosting needs a directory")
	}

	// Stop whatever store is running before standing up its replacement,
	// so two of them are never watching the same directory.
	ph.stopStoreLocked()

	if !wantPages && !wantStore {
		ph.slot.Set(nil)
		ph.cfg = pagesHostConfig{Mode: hostModeOff}
		ph.log.Infof("Resource hosting disabled")
		return nil
	}

	router := resources.NewRouter()

	if wantStore {
		store, err := ph.startStoreLocked(cfg)
		if err != nil {
			return err
		}
		// Without a pages site the store keeps the root, which is
		// where a store-only client has always served its front page.
		store.BindRoutes(router, !wantPages)
	}

	if wantPages {
		if err := os.MkdirAll(cfg.PagesPath, 0o700); err != nil {
			ph.stopStoreLocked()
			return fmt.Errorf("unable to create pages dir: %v", err)
		}
		if err := renameOldPartialsDir(cfg.PagesPath); err != nil {
			ph.stopStoreLocked()
			return fmt.Errorf("unable to rename the partials dir: %v", err)
		}
		// PagesResource rather than a plain filesystem one: it serves
		// the same files, and bundles the shared fragments a page
		// refers to so they cross the wire once rather than once per
		// page. See resources.PagesResource.
		router.BindPrefixPath(nil, resources.NewPagesResource(
			cfg.PagesPath, ph.log))
	}

	ph.slot.Set(router)
	ph.cfg = cfg
	ph.log.Infof("Resource hosting mode %q (pages %q, store %q)",
		cfg.Mode, cfg.PagesPath, cfg.StorePath)
	return nil
}

// startStoreLocked builds and runs a store. ph.mtx must be held.
func (ph *pagesHost) startStoreLocked(cfg pagesHostConfig) (*simplestore.Store, error) {
	if ph.c == nil {
		return nil, fmt.Errorf("client is not running yet")
	}

	// Generate the template store if the path does not exist.
	if _, err := os.Stat(cfg.StorePath); os.IsNotExist(err) {
		if err := simplestore.WriteTemplate(cfg.StorePath); err != nil {
			return nil, fmt.Errorf("unable to write simplestore template: %v", err)
		}
	}

	scfg := simplestore.Config{
		Root:                 cfg.StorePath,
		Log:                  ph.log,
		LiveReload:           true,
		Client:               ph.c,
		PayType:              simplestore.PayType(cfg.StorePayType),
		Account:              cfg.StoreAccount,
		ShipCharge:           cfg.StoreShipCharge,
		LNPayClient:          ph.lnpc,
		ExchangeRateProvider: ph.ratesFn,
		OrderPlaced:          ph.orderNtfn,
		StatusChanged:        ph.orderNtfn,

		// The site the shop sits in, and the two fragments it wears. Only
		// when a site is actually being hosted: a store on its own has no
		// fragments to read and would put empty markers round every page.
		SiteRoot:    siteRootFor(cfg),
		ShopName:    cfg.StoreName,
		ShopTagline: cfg.StoreTagline,
		Header:      cfg.StoreHeader,
		Footer:      cfg.StoreFooter,
	}
	store, err := simplestore.New(scfg)
	if err != nil {
		return nil, fmt.Errorf("unable to initialize simple store: %v", err)
	}

	ctx, cancel := context.WithCancel(ph.runCtx)
	ph.store = store
	ph.storeStop = cancel
	go func() {
		if err := store.Run(ctx); err != nil && ctx.Err() == nil {
			ph.log.Errorf("Simple store exited: %v", err)
		}
	}()
	return store, nil
}

// runningStore returns the store this client is serving, or an error naming
// what to do about it. Every store command goes through here, so "the store
// is off" is one message rather than a nil dereference per command.
func (ph *pagesHost) runningStore() (*simplestore.Store, error) {
	ph.mtx.Lock()
	defer ph.mtx.Unlock()
	if ph.store == nil {
		return nil, fmt.Errorf("no store is being hosted")
	}
	return ph.store, nil
}

// clientRPCRouter returns the router the clientrpc resources service should
// bind into, or nil when hosting is not delegated over RPC.
func (ph *pagesHost) clientRPCRouter() *resources.Router {
	ph.mtx.Lock()
	defer ph.mtx.Unlock()
	return ph.rpcRouter
}

// stopStoreLocked stops a running store, if any. ph.mtx must be held.
func (ph *pagesHost) stopStoreLocked() {
	if ph.storeStop != nil {
		ph.storeStop()
		ph.storeStop = nil
	}
	ph.store = nil
}

// defaultPagesPath is where the UI offers to keep a site when hosting is
// switched on and the user has no directory of their own in mind.
func (ph *pagesHost) defaultPagesPath() string {
	return filepath.Join(ph.appDataDir, "pages")
}

// defaultStorePath is the same for a store.
func (ph *pagesHost) defaultStorePath() string {
	return filepath.Join(ph.appDataDir, "store")
}

// pagesHostStatus assembles what the Pages UI needs in one round trip.
func (cc *clientCtx) pagesHostStatus() (pagesHostStatus, error) {
	cfg := cc.pagesHost.config()
	pages, err := listLocalPages(cfg.PagesPath)
	if err != nil {
		return pagesHostStatus{}, err
	}
	return pagesHostStatus{
		Config:           cfg,
		Editable:         cfg.editable(),
		DefaultPath:      cc.pagesHost.defaultPagesPath(),
		DefaultStorePath: cc.pagesHost.defaultStorePath(),
		Pages:            pages,
	}, nil
}
