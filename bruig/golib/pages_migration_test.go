package golib

import (
	"os"
	"path/filepath"
	"testing"
)

// pages_migration_test.go covers moving a served site made when these were
// called partials.
//
// Unlike the library's rename, this decides what visitors are served: a site
// serving its fragments from a directory nothing looks in answers 404 for
// every page that includes one.

func writeIn(t *testing.T, root, dir, name, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, dir), 0o700); err != nil {
		t.Fatal(err)
	}
	err := os.WriteFile(filepath.Join(root, dir, name), []byte(body), 0o600)
	if err != nil {
		t.Fatal(err)
	}
}

func TestASiteMadeBeforeTheRenameIsMoved(t *testing.T) {
	root := t.TempDir()
	writeIn(t, root, oldPartialsDir, "header.md", "# a banner")

	if err := renameOldPartialsDir(root); err != nil {
		t.Fatal(err)
	}

	got, err := os.ReadFile(filepath.Join(root, partialsDir, "header.md"))
	if err != nil {
		t.Fatalf("the fragment did not come across: %v", err)
	}
	if string(got) != "# a banner" {
		t.Fatalf("got %q", got)
	}
	if _, err := os.Stat(filepath.Join(root, oldPartialsDir)); err == nil {
		t.Error("the old directory is still there")
	}
}

func TestASiteWithNothingToMoveIsLeftAlone(t *testing.T) {
	root := t.TempDir()
	if err := renameOldPartialsDir(root); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, partialsDir)); err == nil {
		t.Error("a directory was made that nothing asked for")
	}
}

func TestASiteWithBothIsLeftAlone(t *testing.T) {
	// A site in a state this cannot reason about. Merging could overwrite a
	// fragment with another of the same name, so both are left where the
	// writer can see them.
	root := t.TempDir()
	writeIn(t, root, oldPartialsDir, "header.md", "the old one")
	writeIn(t, root, partialsDir, "header.md", "the new one")

	if err := renameOldPartialsDir(root); err != nil {
		t.Fatal(err)
	}

	for dir, want := range map[string]string{
		oldPartialsDir: "the old one",
		partialsDir:    "the new one",
	} {
		got, err := os.ReadFile(filepath.Join(root, dir, "header.md"))
		if err != nil || string(got) != want {
			t.Errorf("%s/header.md is %q, %v", dir, got, err)
		}
	}
}

func TestMovingTwiceIsNotAProblem(t *testing.T) {
	// Hosting is reconfigured while the app runs, so this can be reached
	// more than once.
	root := t.TempDir()
	writeIn(t, root, oldPartialsDir, "footer.md", "the end")

	for range 2 {
		if err := renameOldPartialsDir(root); err != nil {
			t.Fatal(err)
		}
	}

	got, err := os.ReadFile(filepath.Join(root, partialsDir, "footer.md"))
	if err != nil || string(got) != "the end" {
		t.Fatalf("got %q, %v", got, err)
	}
}

func TestAFragmentPathStillNamesTheServedDirectory(t *testing.T) {
	// What a page's --include[] resolves against has to be the directory the
	// fragments are actually in, or every include answers 404.
	root := t.TempDir()
	fname, err := pageFileName(root, partialsDir+"/header.md")
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(fname) != filepath.Join(root, "fragments") {
		t.Fatalf("got %q", fname)
	}
}
