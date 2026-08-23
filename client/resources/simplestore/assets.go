package simplestore

import (
	"context"
	"os"
	"path/filepath"
	"strings"

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

// AssetsDir is where a store keeps its pictures, inside the store's own
// directory.
const AssetsDir = "assets"

// assetExts are the kinds of file a shop may show.
//
// A closed list rather than "whatever was dropped in". The directory is
// served to anyone who can reach the shop, so what may be put in it is what
// a page has a use for -- and a list of extensions is a great deal easier to
// reason about than a list of what must not go in.
var assetExts = map[string]struct{}{
	".png":  {},
	".jpg":  {},
	".jpeg": {},
	".gif":  {},
	".webp": {},
	".svg":  {},
}

// assetPath is the file one asset request names, or an error for a name that
// is not one this will serve.
//
// The whole of the guard is here. A request arrives from anyone who can
// reach the shop, so a name that walks out of the directory, hides itself, or
// names something that is not a picture is refused before anything is opened.
func (s *Store) assetPath(path []string) (string, error) {
	if len(path) != 2 {
		return "", os.ErrNotExist
	}
	name := path[1]
	if name != filepath.Base(name) || strings.HasPrefix(name, ".") {
		return "", os.ErrNotExist
	}
	if _, ok := assetExts[strings.ToLower(filepath.Ext(name))]; !ok {
		return "", os.ErrNotExist
	}
	return filepath.Join(s.root, AssetsDir, name), nil
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
