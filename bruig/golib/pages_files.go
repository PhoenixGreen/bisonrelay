package golib

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
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

// partialsDir is the one subdirectory of a site, holding the fragments its
// pages share. Kept in step with resources.PartialsDir, which is what serves
// them.
const partialsDir = "partials"

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
	}
	if name != filepath.Base(name) || strings.HasPrefix(name, ".") {
		return "", fmt.Errorf("page name %q must be a plain file name", name)
	}
	if filepath.Ext(name) != ".md" {
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
