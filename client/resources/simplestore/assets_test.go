package simplestore

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
)

// assets_test.go covers a shop's pictures: what it will serve, what it will
// list, and what it refuses.
//
// The directory is served to anyone who can reach the shop, so what may be
// asked for is a closed question. One folder deep is allowed because a shop
// with covers/ and screenshots/ is somebody organising their pictures; a
// path of any depth is a shop guessing what it is allowed to open.

func withAssets(t *testing.T, names ...string) *Store {
	t.Helper()
	s := testStore(t)
	for _, name := range names {
		path := filepath.Join(append([]string{s.root, AssetsDir},
			filepath.SplitList(name)...)...)
		path = filepath.Join(s.root, AssetsDir, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("pretend"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return s
}

func TestAShopListsItsPicturesOneFolderDeep(t *testing.T) {
	s := withAssets(t, "banner.jpg", "covers/dm0004.jpg", "covers/dm0005.png")

	got, err := s.ListAssets()
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, a := range got {
		names = append(names, a.Name)
	}
	want := []string{"banner.jpg", "covers/dm0004.jpg", "covers/dm0005.png"}
	if len(names) != len(want) {
		t.Fatalf("got %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("got %v, want %v", names, want)
		}
	}
}

func TestAListingSaysWhatEachPictureIs(t *testing.T) {
	// A thumbnail has to know before it decides whether it can draw one.
	s := withAssets(t, "banner.jpg", "logo.svg")
	got, err := s.ListAssets()
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]StoreAsset{}
	for _, a := range got {
		byName[a.Name] = a
	}
	if byName["banner.jpg"].Type != "image/jpeg" {
		t.Errorf("banner.jpg is %q", byName["banner.jpg"].Type)
	}
	if byName["logo.svg"].Type != "image/svg+xml" {
		t.Errorf("logo.svg is %q", byName["logo.svg"].Type)
	}
	if byName["banner.jpg"].Size == 0 {
		t.Error("no size")
	}
}

func TestAShopWithNoPicturesListsNothing(t *testing.T) {
	// Not an error: a shop has none until the first is added.
	got, err := testStore(t).ListAssets()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 0 {
		t.Fatalf("got %v", got)
	}
}

func TestThingsThatAreNotPicturesAreNotListed(t *testing.T) {
	s := withAssets(t, "banner.jpg")
	for _, name := range []string{"notes.txt", ".hidden.jpg", "archive.zip"} {
		path := filepath.Join(s.root, AssetsDir, name)
		if err := os.WriteFile(path, []byte("x"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	got, err := s.ListAssets()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "banner.jpg" {
		t.Fatalf("got %v", got)
	}
}

func TestOnlyOneFolderDeepIsListed(t *testing.T) {
	// What is listed has to match what can be asked for, or the shop shows
	// a picture nobody can fetch.
	s := withAssets(t, "covers/deep/buried.jpg", "covers/shown.jpg")
	got, err := s.ListAssets()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "covers/shown.jpg" {
		t.Fatalf("got %v", got)
	}
}

func TestAShopServesAPictureInAFolder(t *testing.T) {
	s := withAssets(t, "covers/dm0004.jpg")
	res, err := s.handleAsset(context.Background(), clientintf.UserID{},
		&rpc.RMFetchResource{Path: []string{AssetsDir, "covers", "dm0004.jpg"}})
	if err != nil {
		t.Fatal(err)
	}
	if res.Status != rpc.ResourceStatusOk {
		t.Fatalf("status %d", res.Status)
	}
}

func TestAShopWillNotServeItsWayOut(t *testing.T) {
	s := withAssets(t, "banner.jpg")
	for _, path := range [][]string{
		{AssetsDir, "..", "products", "first-type.toml"},
		{AssetsDir, "covers", "..", "..", "secret.jpg"},
		{AssetsDir, "a", "b", "c", "deep.jpg"},
		{AssetsDir, ".hidden.jpg"},
		{AssetsDir, "notes.txt"},
		{AssetsDir},
	} {
		if _, err := s.assetPath(path); err == nil {
			t.Errorf("%v would have been served", path)
		}
	}
}

func TestDeletingAPicture(t *testing.T) {
	s := withAssets(t, "banner.jpg", "covers/dm0004.jpg")
	if err := s.DeleteAsset("covers/dm0004.jpg"); err != nil {
		t.Fatal(err)
	}
	got, _ := s.ListAssets()
	if len(got) != 1 || got[0].Name != "banner.jpg" {
		t.Fatalf("got %v", got)
	}

	// Deleting what is not there is not a failure: the shop is in the state
	// that was asked for.
	if err := s.DeleteAsset("covers/dm0004.jpg"); err != nil {
		t.Errorf("deleting twice: %v", err)
	}
}

func TestDeletingCannotReachOutOfTheShop(t *testing.T) {
	s := withAssets(t, "banner.jpg")
	for _, name := range []string{"../products/first-type.toml", "../../x.jpg"} {
		if err := s.DeleteAsset(name); err == nil {
			t.Errorf("%q was accepted", name)
		}
	}
}
