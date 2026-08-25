package simplestore

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
)

// assets.go serves the pictures a shop shows.
//
// Files asked for on their own, the way a site's pictures are, and for the
// same reason: a shop front showing a dozen products with their pictures
// written into the page would be a dozen pictures in one message, and a
// message carries 1 MiB. The front page of a shop with anything in it would
// not fit.
//
// The reader needs nothing for this. A picture named by path in a page is
// fetched from whoever served that page, so ![](assets/thing.jpg) in a store
// page is resolved against the store exactly as it is against a site.

// AssetsDir is where a store keeps its pictures: the directory inside the
// store, and the path it answers on.
//
// Not "assets", which is the site's. Once a site and a shop are hosted
// together their paths are one space, the store claims its names before the
// site takes what is left, and a shop calling its pictures assets/ took
// every banner and logo on the site's own pages with it. The site had that
// word first, so the shop uses another.
//
// One name for the directory and the path, because two would drift: the
// template writes the path, golib writes the directory, and a shop whose
// pictures are written to one place and served from another shows nothing
// with nothing to see wrong.
const AssetsDir = "shopassets"

// assetExts are the kinds of file a shop may show.
//
// A closed list rather than "whatever was dropped in". The directory is
// served to anyone who can reach the shop, so what may be put in it is what
// a page has a use for -- and a list of extensions is a great deal easier to
// reason about than a list of what must not go in.
// The type is kept beside the extension so a listing can say what a file is
// without opening it -- which is what a thumbnail needs to know before it
// decides whether it can draw one.
var assetExts = map[string]string{
	".png":  "image/png",
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".gif":  "image/gif",
	".webp": "image/webp",
	".svg":  "image/svg+xml",
}

// assetPath is the file one asset request names, or an error for a name that
// is not one this will serve.
//
// The whole of the guard is here. A request arrives from anyone who can
// reach the shop, so a name that walks out of the directory, hides itself, or
// names something that is not a picture is refused before anything is opened.
func (s *Store) assetPath(path []string) (string, error) {
	// One directory deep at most: a shop with covers/ and screenshots/ is
	// somebody organising their pictures, and a shop that can be asked for
	// a path of any depth is one guessing what it is allowed to open.
	if len(path) < 2 || len(path) > 3 {
		return "", os.ErrNotExist
	}
	for _, part := range path[1:] {
		if part != filepath.Base(part) || strings.HasPrefix(part, ".") ||
			part == "" {
			return "", os.ErrNotExist
		}
	}
	name := path[len(path)-1]
	if _, ok := assetExts[strings.ToLower(filepath.Ext(name))]; !ok {
		return "", os.ErrNotExist
	}
	return filepath.Join(append([]string{s.root}, path...)...), nil
}

// StoreAsset is one picture a shop keeps.
type StoreAsset struct {
	// Name is what a page writes to show it, without the directory the shop
	// serves them from: "banner.jpg", or "covers/guitar.jpg".
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	Type     string    `json:"type"`
	Modified time.Time `json:"modified"`
}

// ListAssets returns the pictures a shop has, one directory deep.
//
// A missing directory is not an error: a shop has no pictures until the
// first one is added.
func (s *Store) ListAssets() ([]StoreAsset, error) {
	root := filepath.Join(s.root, AssetsDir)
	out := []StoreAsset{}

	var walk func(dir, prefix string) error
	walk = func(dir, prefix string) error {
		entries, err := os.ReadDir(dir)
		if os.IsNotExist(err) {
			return nil
		} else if err != nil {
			return err
		}
		for _, e := range entries {
			name := e.Name()
			if strings.HasPrefix(name, ".") {
				continue
			}
			if e.IsDir() {
				// Only the one level, matching what can be asked for.
				if prefix == "" {
					if err := walk(filepath.Join(dir, name), name+"/"); err != nil {
						return err
					}
				}
				continue
			}
			mime, ok := assetExts[strings.ToLower(filepath.Ext(name))]
			if !ok {
				continue
			}
			info, err := e.Info()
			if err != nil {
				continue
			}
			out = append(out, StoreAsset{
				Name:     prefix + name,
				Size:     info.Size(),
				Type:     mime,
				Modified: info.ModTime(),
			})
		}
		return nil
	}

	if err := walk(root, ""); err != nil {
		return nil, err
	}
	sort.Slice(out, func(i, j int) bool {
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}

// DeleteAsset removes one of a shop's pictures.
func (s *Store) DeleteAsset(name string) error {
	s.mtx.Lock()
	defer s.mtx.Unlock()

	path, err := s.assetPath(append([]string{AssetsDir},
		strings.Split(name, "/")...))
	if err != nil {
		return fmt.Errorf("%q is not one of this shop's pictures", name)
	}
	err = os.Remove(path)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

func (s *Store) handleAsset(_ context.Context, _ clientintf.UserID,
	request *rpc.RMFetchResource) (*rpc.RMFetchResourceReply, error) {

	fname, err := s.assetPath(request.Path)
	if err != nil {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusNotFound,
		}, nil
	}
	data, err := os.ReadFile(fname)
	if os.IsNotExist(err) {
		return &rpc.RMFetchResourceReply{
			Status: rpc.ResourceStatusNotFound,
		}, nil
	} else if err != nil {
		return nil, err
	}
	return &rpc.RMFetchResourceReply{
		Data:   data,
		Status: rpc.ResourceStatusOk,
	}, nil
}

// placeholderImage is the picture a product with none of its own is shown
// with.
//
// Load-bearing rather than decorative. A card is a picture and the writing
// that goes with it, and a card with no picture is a hole in the row -- so
// every product contributes one, and this is what a product that has not
// been given one contributes. It ships with a new store; see WriteTemplate.
const placeholderImage = "placeholder.png"

// ProductImagePath is what a template writes to show a product's picture, or
// empty for a product with none.
//
// Built here rather than in a template, so the directory is named in one
// place and a template cannot spell it differently.
func ProductImagePath(image string) string {
	if strings.TrimSpace(image) == "" {
		return ""
	}
	return AssetsDir + "/" + image
}
