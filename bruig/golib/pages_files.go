package golib

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/client/resources/simplestore"
)

// localPage is one markdown file in the hosted pages directory.
type localPage struct {
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`
	IsIndex  bool      `json:"is_index"`
}

// indexPageName is the file a visitor lands on: it is what the app requests
// when someone opens another user's site.
const indexPageName = "index.md"

// partialsDir and assetsDir are the two subdirectories of a site: the
// fragments its pages share, and the pictures they show. Kept in step with
// resources.PartialsDir and resources.AssetsDir, which are what serve them.
const partialsDir = resources.PartialsDir

// oldPartialsDir is what it used to be called. A site made before the rename
// has one, and renameOldPartialsDir moves it.
const oldPartialsDir = resources.OldPartialsDir
const assetsDir = "assets"

// assetExts are the kinds of file a page may show.
//
// A closed list rather than "whatever was dropped in". The directory is
// served to anyone who asks, so what may be put in it is what a page has a
// use for -- and a list of extensions is a great deal easier to reason about
// than a list of what must not go in.
var assetExts = map[string]string{
	".png":  "image/png",
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".gif":  "image/gif",
	".webp": "image/webp",
	".svg":  "image/svg+xml",
}

// pageFileName validates a page name and returns the file it maps to inside
// root.
//
// Names are markdown-only, and flat but for one allowed subdirectory:
// "partials/". The pages directory is served to anyone who asks, so a name
// that walks out of it -- or that lands on a store's templates and order
// files -- would publish more than the author meant to. Allowing exactly one
// known prefix keeps that guarantee while giving fragments somewhere to live.
func pageFileName(root, name string) (string, error) {
	if root == "" {
		return "", fmt.Errorf("pages directory is not configured")
	}
	name = strings.TrimSpace(name)
	if name == "" {
		return "", fmt.Errorf("page name is empty")
	}

	dir := ""
	if rest, ok := strings.CutPrefix(name, partialsDir+"/"); ok {
		dir, name = partialsDir, rest
	} else if rest, ok := strings.CutPrefix(name, assetsDir+"/"); ok {
		dir, name = assetsDir, rest
	}
	if name != filepath.Base(name) || strings.HasPrefix(name, ".") {
		return "", fmt.Errorf("page name %q must be a plain file name", name)
	}

	ext := strings.ToLower(filepath.Ext(name))
	if dir == assetsDir {
		if _, ok := assetExts[ext]; !ok {
			return "", fmt.Errorf("%q is not a kind of file a page "+
				"can show", name)
		}
		// A page reaches a picture by writing ![](assets/name.jpg), and a
		// Markdown link stops at the first space. A file called "my
		// banner.jpg" would be written, listed, and served, and the only
		// thing that would not work is the one thing it is for -- so the
		// name is refused here rather than a page silently showing
		// nothing. The caller names the file, so it is the caller's job
		// to hand over one that works; see slugFileName in the UI.
		if strings.ContainsAny(name, " \t()<>\"'\\") {
			return "", fmt.Errorf("picture name %q cannot be written in "+
				"a page link", name)
		}
	} else if ext != ".md" {
		return "", fmt.Errorf("page name %q must end in .md", name)
	}
	return filepath.Join(root, dir, name), nil
}

// listLocalPages returns the markdown pages in root. A missing directory is
// not an error: hosting may be configured before anything has been written.
func listLocalPages(root string) ([]localPage, error) {
	if root == "" {
		return []localPage{}, nil
	}
	entries, err := os.ReadDir(root)
	if os.IsNotExist(err) {
		return []localPage{}, nil
	} else if err != nil {
		return nil, err
	}

	pages := make([]localPage, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".md" {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		pages = append(pages, localPage{
			Name:     e.Name(),
			Size:     info.Size(),
			Modified: info.ModTime(),
			IsIndex:  e.Name() == indexPageName,
		})
	}

	// The shared fragments, named by their path so the two kinds are told
	// apart by what they are called rather than by a second listing.
	partials, err := os.ReadDir(filepath.Join(root, partialsDir))
	if err == nil {
		for _, e := range partials {
			if e.IsDir() || filepath.Ext(e.Name()) != ".md" {
				continue
			}
			info, err := e.Info()
			if err != nil {
				continue
			}
			pages = append(pages, localPage{
				Name:     partialsDir + "/" + e.Name(),
				Size:     info.Size(),
				Modified: info.ModTime(),
			})
		}
	}

	// The index first, then the rest alphabetically: it is the page every
	// visitor sees, so it is the one to keep at hand.
	sort.Slice(pages, func(i, j int) bool {
		if pages[i].IsIndex != pages[j].IsIndex {
			return pages[i].IsIndex
		}
		return strings.ToLower(pages[i].Name) < strings.ToLower(pages[j].Name)
	})
	return pages, nil
}

func readLocalPage(root, name string) (string, error) {
	fname, err := pageFileName(root, name)
	if err != nil {
		return "", err
	}
	data, err := os.ReadFile(fname)
	if os.IsNotExist(err) {
		return "", nil
	} else if err != nil {
		return "", err
	}
	return string(data), nil
}

func writeLocalPage(root, name, content string) error {
	fname, err := pageFileName(root, name)
	if err != nil {
		return err
	}
	// The file's own directory, not the root: a shared fragment lives in
	// partials/, which does not exist until the first one is written.
	dir := filepath.Dir(fname)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}

	// Write through a temp file in the same directory: the pages dir is
	// live, and a visitor fetching mid-write would otherwise get half a
	// page. Beside the target rather than in the root, so the rename that
	// finishes it cannot cross a directory that does not exist yet.
	tmp, err := os.CreateTemp(dir, ".tmp-page-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if _, err := tmp.WriteString(content); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpName, fname)
}

func deleteLocalPage(root, name string) error {
	fname, err := pageFileName(root, name)
	if err != nil {
		return err
	}
	err = os.Remove(fname)
	if os.IsNotExist(err) {
		return nil
	}
	return err
}

// localAsset is one picture a site can show.
type localAsset struct {
	Name     string    `json:"name"`
	Size     int64     `json:"size"`
	Modified time.Time `json:"modified"`

	// Path is what a page writes to show it, which is the name with the
	// directory in front. Sent rather than rebuilt at the other end, so the
	// two cannot drift.
	Path string `json:"path"`
}

// listLocalAssets returns the pictures in the site's assets directory.
//
// A missing directory is not an error: a site has none until the first
// picture is added.
func listLocalAssets(root string) ([]localAsset, error) {
	if root == "" {
		return []localAsset{}, nil
	}
	entries, err := os.ReadDir(filepath.Join(root, assetsDir))
	if os.IsNotExist(err) {
		return []localAsset{}, nil
	} else if err != nil {
		return nil, err
	}

	out := make([]localAsset, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if _, ok := assetExts[strings.ToLower(filepath.Ext(e.Name()))]; !ok {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		out = append(out, localAsset{
			Name:     e.Name(),
			Size:     info.Size(),
			Modified: info.ModTime(),
			Path:     assetsDir + "/" + e.Name(),
		})
	}
	sort.Slice(out, func(i, j int) bool {
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})
	return out, nil
}

// readLocalAsset returns the bytes of one picture the site keeps.
//
// The site's own pictures, read from disk rather than fetched. A reader gets
// these over the wire because they are somebody else's; the person writing
// the page already has them, and a preview that had to fetch its author's own
// files would be waiting on a round trip to itself.
func readLocalAsset(root, assetPath string) ([]byte, error) {
	fname, err := pageFileName(root, assetPath)
	if err != nil {
		return nil, err
	}
	return os.ReadFile(fname)
}

// addLocalAssetBytes writes a picture into the site's assets directory under
// [name].
//
// Bytes rather than a path to copy, because what gets added is usually not
// what was picked: a picture is resized and re-encoded first, and the result
// exists only in memory. The name carries the extension the encoding chose,
// which is why it is passed rather than taken from the source.
func addLocalAssetBytes(root, name string, data []byte) (string, error) {
	fname, err := pageFileName(root, assetsDir+"/"+filepath.Base(name))
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(filepath.Dir(fname), 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(fname, data, 0o600); err != nil {
		return "", err
	}
	return assetsDir + "/" + filepath.Base(fname), nil
}

// renameOldPartialsDir moves a served site made before these were called
// fragments.
//
// The library folder was renamed first, on the reasoning that the served
// directory is never shown to anybody. It is: it sits in the same window as
// the library, one folder along, and the two disagreeing is exactly the sort
// of thing somebody finds while looking for a file and cannot explain.
//
// Careful in the same way the library's rename is, because this is a
// writer's own work and nothing else has a copy of it:
//
//   - nothing to move, nothing happens;
//   - both present, nothing happens either. That is a site in a state this
//     cannot reason about, and merging could overwrite a fragment with
//     another of the same name, so both are left where they can be seen.
//   - the move is a rename within one directory, so it either happened or
//     it did not.
//
// A failure is returned rather than swallowed: unlike the library, this
// decides what visitors are served. A site serving half its fragments from a
// directory nothing looks in would answer 404 for every page that includes
// one, and doing that quietly is worse than not starting.
func renameOldPartialsDir(root string) error {
	old := filepath.Join(root, oldPartialsDir)
	if _, err := os.Stat(old); err != nil {
		return nil
	}
	wanted := filepath.Join(root, partialsDir)
	if _, err := os.Stat(wanted); err == nil {
		return nil
	}
	return os.Rename(old, wanted)
}

// storeAssetName is a picture's file name inside a store's assets
// directory, or an error for one that would not be served.
//
// The same closed list of extensions a site uses, and the same refusal of
// anything that is not a plain file name. A store's assets are served to
// anyone who can reach the shop, so what may be written there is decided
// here rather than trusted from the other end.
func storeAssetName(name string) (string, error) {
	name = filepath.Base(strings.TrimSpace(name))
	if name == "" || name == "." || strings.HasPrefix(name, ".") {
		return "", fmt.Errorf("picture name %q is not a file name", name)
	}
	if _, ok := assetExts[strings.ToLower(filepath.Ext(name))]; !ok {
		return "", fmt.Errorf("%q is not a kind of file a shop can show", name)
	}
	if strings.ContainsAny(name, " \t()<>\"'\\") {
		return "", fmt.Errorf("picture name %q cannot be written in a page "+
			"link", name)
	}
	return name, nil
}

// addStoreAssetBytes writes a picture into the store's assets directory and
// returns the name a product records.
//
// The name alone, not a path: a product says "guitar.jpg" and the template
// builds the rest, so the directory is named in one place.
// storeAssetFolder is the one optional directory a picture may go in.
//
// One level, because that is what a shop will serve: covers/ and
// screenshots/ is somebody organising their pictures, and anything deeper
// would be written where nothing could ask for it.
func storeAssetFolder(folder string) (string, error) {
	folder = strings.Trim(strings.TrimSpace(folder), "/")
	if folder == "" {
		return "", nil
	}
	if folder != filepath.Base(folder) || strings.HasPrefix(folder, ".") {
		return "", fmt.Errorf("%q is not a folder name", folder)
	}
	if strings.ContainsAny(folder, " \t()<>\"'\\") {
		return "", fmt.Errorf("folder %q cannot be written in a page link",
			folder)
	}
	return folder, nil
}

func addStoreAssetBytes(storeRoot, folder, name string, data []byte) (string, error) {
	if storeRoot == "" {
		return "", fmt.Errorf("no store is being hosted")
	}
	safe, err := storeAssetName(name)
	if err != nil {
		return "", err
	}
	safeFolder, err := storeAssetFolder(folder)
	if err != nil {
		return "", err
	}

	dir := filepath.Join(storeRoot, simplestore.AssetsDir, safeFolder)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(dir, safe), data, 0o600); err != nil {
		return "", err
	}
	if safeFolder == "" {
		return safe, nil
	}
	return safeFolder + "/" + safe, nil
}
