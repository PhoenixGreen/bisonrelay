package simplestore

import (
	"embed"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

//go:embed template
var storeTemplate embed.FS

// WriteTemplate writes the store template in the given path.
func WriteTemplate(rootDestPath string) error {
	if err := os.MkdirAll(rootDestPath, 0o700); err != nil {
		return fmt.Errorf("unable to create root dir for store: %w", err)
	}

	if entries, err := os.ReadDir(rootDestPath); err != nil {
		return fmt.Errorf("failed to read %v: %w", rootDestPath, err)
	} else if len(entries) != 0 {
		return os.ErrExist
	}

	walkDirFunc := func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if d.Type().IsRegular() {
			data, err := storeTemplate.ReadFile(path)
			if err != nil {
				return fmt.Errorf("unable to read template file %s: %v",
					path, err)
			}

			// path[8:] skips the 'template/' prefix.
			destFilename := filepath.Join(rootDestPath, path[9:])
			if err := os.WriteFile(destFilename, data, 0o644); err != nil {
				return fmt.Errorf("unable to write template file %s: %v",
					destFilename, err)
			}

			return nil
		}

		if d.IsDir() && path != "template" {
			// path[8:] skips the 'template/' prefix.
			destFilename := filepath.Join(rootDestPath, path[9:])
			return os.Mkdir(destFilename, 0o700)
		}

		return nil
	}

	return fs.WalkDir(storeTemplate, "template", walkDirFunc)
}

// shopRecordDirs are the directories a shop keeps its own records in: what
// it sells, and who is buying it.
//
// Written only when a shop is first made, and never again. The example
// products in the shipped set exist so somebody has a file to look at on
// day one; after that the catalogue is the seller's, and anything that
// treats it as ours can undo work nobody has another copy of.
var shopRecordDirs = []string{productsDir, cartsDir, ordersDir}

// isShopRecord is whether a path inside the store belongs to the shop rather
// than to the app.
func isShopRecord(rel string) bool {
	for _, dir := range shopRecordDirs {
		if rel == dir || strings.HasPrefix(rel, dir+"/") {
			return true
		}
	}
	return false
}

// RestoreTemplates writes the shipped templates over whatever is in the
// store, and adds anything it does not have.
//
// A store's templates are copied in once, when the store is made, and are
// the seller's own from then on. So a template shipped or changed later never
// reaches a store that already exists -- which is how a shop can be running
// a front page written for a version of the app from a year ago, with no
// sign that anything newer exists.
//
// Overwriting is the seller's decision and never the app's: these are files
// somebody may have spent an afternoon on, and there is no undo. So this is
// offered as something to choose rather than done on start-up, and it says
// what it will do before it does it.
//
// What is left alone is what is not a template: products/ and carts/ are the
// shop's own records, and nothing here writes to them.
//
// That last part was a claim rather than a fact for one commit. The shipped
// set includes example products -- they are how a brand-new shop gets a file
// to look at -- so copying the directory over wholesale rewrote a seller's
// catalogue with them. A product they had moved to a file of its own came
// back in the file it left, which is a duplicate SKU, and a duplicate SKU
// makes the whole catalogue refuse to load: every product gone from the shop
// front at once, from pressing a button that said it would restore pages.
func RestoreTemplates(rootDestPath string) error {
	if err := os.MkdirAll(rootDestPath, 0o700); err != nil {
		return fmt.Errorf("unable to create root dir for store: %w", err)
	}

	return fs.WalkDir(storeTemplate, "template",
		func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			// path[9:] skips the 'template/' prefix.
			if isShopRecord(path[min(9, len(path)):]) {
				return nil
			}
			if d.IsDir() {
				if path == "template" {
					return nil
				}
				return os.MkdirAll(filepath.Join(rootDestPath, path[9:]), 0o700)
			}
			if !d.Type().IsRegular() {
				return nil
			}
			data, err := storeTemplate.ReadFile(path)
			if err != nil {
				return fmt.Errorf("unable to read template file %s: %v",
					path, err)
			}
			dest := filepath.Join(rootDestPath, path[9:])
			if err := os.MkdirAll(filepath.Dir(dest), 0o700); err != nil {
				return err
			}
			if err := os.WriteFile(dest, data, 0o644); err != nil {
				return fmt.Errorf("unable to write template file %s: %v",
					dest, err)
			}
			return nil
		})
}
