package simplestore

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/internal/jsonfile"
	"github.com/pelletier/go-toml"
)

// The management API below is what a UI needs to run a store: read the orders,
// move them along, and edit the catalogue. It is deliberately separate from
// the page handlers, which render the same things into markdown for a remote
// visitor -- the handlers call into here so the two cannot drift.

// ManagedOrder is an order together with the seller's view of who placed it.
type ManagedOrder struct {
	Order
	UserNick string `json:"user_nick"`
}

// ListOrders returns every order placed with this store, newest first.
func (s *Store) ListOrders() ([]ManagedOrder, error) {
	s.mtx.Lock()
	defer s.mtx.Unlock()
	return s.listOrdersLocked()
}

func (s *Store) listOrdersLocked() ([]ManagedOrder, error) {
	pattern := filepath.Join(s.root, ordersDir, "*", "*.json")
	files, err := filepath.Glob(pattern)
	if err != nil {
		return nil, err
	}

	orders := make([]ManagedOrder, 0, len(files))
	for _, f := range files {
		var order Order
		if err := jsonfile.Read(f, &order); err != nil {
			// One unreadable order must not hide the rest.
			s.log.Warnf("Unable to decode order file %s: %v", f, err)
			continue
		}
		nick, _ := s.c.UserNick(order.User)
		orders = append(orders, ManagedOrder{Order: order, UserNick: nick})
	}

	sort.Slice(orders, func(i, j int) bool {
		return orders[i].PlacedTS.After(orders[j].PlacedTS)
	})
	return orders, nil
}

func (s *Store) orderFilename(uid clientintf.UserID, oid OrderID) string {
	return filepath.Join(s.root, ordersDir, uid.String(),
		orderFnamePattern.FilenameFor(uint64(oid)))
}

// loadOrderLocked reads one order. s.mtx must be held.
func (s *Store) loadOrderLocked(uid clientintf.UserID, oid OrderID) (*Order, string, error) {
	fname := s.orderFilename(uid, oid)
	var order Order
	if err := jsonfile.Read(fname, &order); err != nil {
		return nil, "", err
	}
	return &order, fname, nil
}

// ValidOrderStatus reports whether s names one of the store's statuses.
// Status arrives from the UI as a string, and an unrecognised one would be
// written to the order file and shown to the buyer as-is.
func ValidOrderStatus(status OrderStatus) bool {
	switch status {
	case StatusPlaced, StatusPaid, StatusShipped, StatusCompleted,
		StatusCanceled:
		return true
	}
	return false
}

// SetOrderStatus moves an order along and tells the buyer.
func (s *Store) SetOrderStatus(uid clientintf.UserID, oid OrderID,
	status OrderStatus) (*Order, error) {

	if !ValidOrderStatus(status) {
		return nil, fmt.Errorf("unknown order status %q", status)
	}

	s.mtx.Lock()
	defer s.mtx.Unlock()

	order, fname, err := s.loadOrderLocked(uid, oid)
	if err != nil {
		return nil, err
	}

	order.Status = status
	if err := jsonfile.Write(fname, order, s.log); err != nil {
		return nil, err
	}

	if s.cfg.StatusChanged != nil {
		msg := fmt.Sprintf("Your order %s/%s changed to status %s",
			order.User.ShortLogID(), order.ID, order.Status)
		s.cfg.StatusChanged(order, msg)
	}
	return order, nil
}

// AddOrderComment appends a comment to an order's thread.
func (s *Store) AddOrderComment(uid clientintf.UserID, oid OrderID,
	comment string, fromAdmin bool) (*Order, error) {

	s.mtx.Lock()
	defer s.mtx.Unlock()

	order, fname, err := s.loadOrderLocked(uid, oid)
	if err != nil {
		return nil, err
	}

	// Escaped whoever wrote it. A customer's comment is read by the seller
	// on their own order page, and the seller's is read by the customer on
	// theirs -- so it is untrusted in both directions, and trusting either
	// end because it is "ours" gets it wrong for the other.
	//
	// Idempotent, so escaping again what a caller already escaped costs
	// nothing and forgetting costs the guarantee.
	order.Comments = append(order.Comments, OrderComment{
		Timestamp: time.Now(),
		FromAdmin: fromAdmin,
		Comment:   EscapeUntrusted(comment),
	})
	if err := jsonfile.Write(fname, order, s.log); err != nil {
		return nil, err
	}

	// The buyer is told when the answer is the seller's. Their own comment
	// needs no message: it lands on the seller's client, which is the one
	// running this, and their order list marks it.
	if fromAdmin && s.cfg.CommentAdded != nil {
		msg := fmt.Sprintf("About your order %s/%s: %s",
			order.User.ShortLogID(), order.ID, comment)
		s.cfg.CommentAdded(order, msg)
	}
	return order, nil
}

// ManagedProduct is a product together with the file it is defined in. A
// product file may hold any number of products, so the file has to travel
// with the product for an edit to land back where it came from.
type ManagedProduct struct {
	Product
	File string `json:"file"`
}

var productFileNameRe = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

// productFilePath validates a product file name and returns its full path.
// Product files are served from the store's own directory, so a name that
// walks out of it must not be writable.
func (s *Store) productFilePath(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("product file name is empty")
	}
	if name != filepath.Base(name) || strings.HasPrefix(name, ".") {
		return "", fmt.Errorf("product file %q must be a plain file name", name)
	}
	if filepath.Ext(name) != ".toml" {
		return "", fmt.Errorf("product file %q must end in .toml", name)
	}
	return filepath.Join(s.root, productsDir, name), nil
}

// ListManagedProducts returns the catalogue as it is on disk, including
// products marked disabled -- which the running store skips, but which the
// seller still has to be able to see and re-enable.
func (s *Store) ListManagedProducts() ([]ManagedProduct, error) {
	dir := filepath.Join(s.root, productsDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return []ManagedProduct{}, nil
	} else if err != nil {
		return nil, err
	}

	var res []ManagedProduct
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".toml" {
			continue
		}
		prods, err := s.readProductFile(filepath.Join(dir, e.Name()))
		if err != nil {
			s.log.Warnf("Unable to read product file %s: %v", e.Name(), err)
			continue
		}
		for _, p := range prods.Products {
			res = append(res, ManagedProduct{Product: *p, File: e.Name()})
		}
	}

	sort.Slice(res, func(i, j int) bool {
		return strings.ToLower(res[i].Title) < strings.ToLower(res[j].Title)
	})
	if res == nil {
		res = []ManagedProduct{}
	}
	return res, nil
}

func (s *Store) readProductFile(path string) (*productsFile, error) {
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		return &productsFile{}, nil
	} else if err != nil {
		return nil, err
	}
	defer f.Close()

	var prods productsFile
	if err := toml.NewDecoder(f).Decode(&prods); err != nil {
		return nil, err
	}
	return &prods, nil
}

func (s *Store) writeProductFile(path string, prods *productsFile) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}

	// An emptied file is removed rather than left as an empty catalogue
	// entry the seller has no way to get rid of.
	if len(prods.Products) == 0 {
		err := os.Remove(path)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}

	data, err := toml.Marshal(prods)
	if err != nil {
		return err
	}

	// Through a temp file in the same directory: the store watches this
	// directory and reloads on write, so a partial file would briefly be
	// the catalogue.
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-products-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, path)
}

// SaveProduct writes a product, creating or replacing it by SKU.
//
// file names the product file to write into; empty means one named after the
// SKU. A product whose SKU already exists elsewhere is moved, rather than
// ending up defined twice -- which the store refuses to load at all.
func (s *Store) SaveProduct(p Product, file string) error {
	p.SKU = strings.TrimSpace(p.SKU)
	if p.SKU == "" {
		return fmt.Errorf("product needs a SKU")
	}
	// A shop links a product by writing [Title](product/SKU), and a Markdown
	// link stops at the first space. A SKU of "this is a test" is written to
	// the file, loaded into the catalogue and served perfectly -- and the
	// shop front then shows the raw text of the link instead of the
	// product, because the link ended at "this". The path would need
	// escaping too, for the same characters.
	//
	// So the SKU is what it has always looked like everywhere else: an
	// identifier. Refused here rather than repaired, because a SKU is what
	// a cart and an order already placed refer to, and quietly changing one
	// would strand them.
	if bad := strings.IndexFunc(p.SKU, func(r rune) bool {
		return r == ' ' || r == '\t' || strings.ContainsRune(`()<>"'\/`, r)
	}); bad != -1 {
		return fmt.Errorf("a SKU cannot contain %q: it is what a page links "+
			"the product by", string(p.SKU[bad]))
	}
	if strings.TrimSpace(p.Title) == "" {
		return fmt.Errorf("product needs a title")
	}
	if p.Price < 0 {
		return fmt.Errorf("product price cannot be negative")
	}

	// The file a buyer is sent, if there is one. Checked here because this
	// is the last moment anybody is watching: after this it is sent when
	// payment lands, unattended, and a wrong name is discovered by the
	// buyer receiving nothing.
	if p.SendFilename != "" {
		path, err := s.checkGood(p.SendFilename)
		if err != nil {
			return err
		}
		if _, err := os.Stat(path); err != nil {
			return fmt.Errorf("the file for this product is not in %s/: %v",
				GoodsDir, err)
		}
	}

	if file == "" {
		file = productFileNameRe.ReplaceAllString(p.SKU, "-") + ".toml"
	}
	path, err := s.productFilePath(file)
	if err != nil {
		return err
	}

	// Take the SKU out of wherever it currently lives, so that saving into
	// a different file is a move and not a duplicate.
	if err := s.removeSKU(p.SKU, path); err != nil {
		return err
	}

	prods, err := s.readProductFile(path)
	if err != nil {
		return err
	}

	replaced := false
	for i, existing := range prods.Products {
		if existing.SKU == p.SKU {
			prods.Products[i] = &p
			replaced = true
			break
		}
	}
	if !replaced {
		prods.Products = append(prods.Products, &p)
	}

	return s.writeProductFile(path, prods)
}

// DeleteProduct removes a product from the catalogue, wherever it is defined.
func (s *Store) DeleteProduct(sku string) error {
	return s.removeSKU(sku, "")
}

// removeSKU drops a SKU from every product file except keepPath.
func (s *Store) removeSKU(sku string, keepPath string) error {
	dir := filepath.Join(s.root, productsDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return err
	}

	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".toml" {
			continue
		}
		path := filepath.Join(dir, e.Name())
		if path == keepPath {
			continue
		}

		prods, err := s.readProductFile(path)
		if err != nil {
			continue
		}

		kept := prods.Products[:0]
		for _, p := range prods.Products {
			if p.SKU != sku {
				kept = append(kept, p)
			}
		}
		if len(kept) == len(prods.Products) {
			continue
		}
		prods.Products = kept
		if err := s.writeProductFile(path, prods); err != nil {
			return err
		}
	}
	return nil
}
