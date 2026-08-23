package resources

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/companyzero/bisonrelay/client/clientintf"
	"github.com/companyzero/bisonrelay/rpc"
)

// pages_test.go covers the shared fragments a page can include.
//
// The claim being tested is the one the feature exists for: a fragment
// several pages share crosses the wire once. That is why the reply is a
// bundle -- the client stores what a bundle carries and answers later
// requests for it without another message -- and why the asking side gets to
// say what it already has.

func writePageFile(t *testing.T, root, name, content string) {
	t.Helper()
	fname := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(fname), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(fname, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func fulfillPage(t *testing.T, pr *PagesResource, path []string,
	meta map[string]string) *rpc.RMFetchResourceReply {
	t.Helper()
	res, err := pr.Fulfill(context.Background(), clientintf.UserID{},
		&rpc.RMFetchResource{Path: path, Meta: meta})
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func TestPartialNames(t *testing.T) {
	got := PartialNames("--include[nav]--\nhi\n--include[nav]--\n--include[foot]--")
	if len(got) != 2 || got[0] != "nav" || got[1] != "foot" {
		t.Fatalf("wanted [nav foot] without repeats, got %v", got)
	}

	// Go templates are a different mechanism entirely -- expanded before
	// anything is sent -- and must not be picked up as fragments.
	if n := PartialNames("{{.Products}} and {{template \"nav\"}}"); len(n) != 0 {
		t.Fatalf("templates are not partials, got %v", n)
	}
}

func TestAMissingFragmentDoesNotFailThePage(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[gone]--\n# Home")
	pr := NewPagesResource(root, nil)

	reply := fulfillPage(t, pr, []string{"index.md"}, nil)
	if reply.Status != rpc.ResourceStatusOk {
		t.Fatalf("the page still serves, got status %v", reply.Status)
	}
	// Shown as nothing where it would have gone, since the marker itself
	// is not writing.
	if got := string(reply.Data); got != "\n# Home" {
		t.Fatalf("got %q", got)
	}
}

func TestAPathCannotWalkOutOfTheDirectory(t *testing.T) {
	root := t.TempDir()
	outside := filepath.Join(filepath.Dir(root), "secret.md")
	if err := os.WriteFile(outside, []byte("private"), 0o600); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(outside)

	pr := NewPagesResource(root, nil)
	reply := fulfillPage(t, pr, []string{"..", "secret.md"}, nil)
	if reply.Status != rpc.ResourceStatusNotFound {
		t.Fatalf("expected not found, got %v with %q", reply.Status, reply.Data)
	}
}

// The tests below are the adversarial ones: what a page can be made to do to
// whoever opens it.

func TestAnIncludeCannotNameAFileOutsideThePartials(t *testing.T) {
	// The pattern is the first of three guards, and the strictest: a name
	// with a dot or a slash in it is not an include at all, so it is drawn
	// as the text it is rather than being resolved to anything.
	for _, name := range []string{
		"password.txt",
		"../../secret",
		"../secret",
		"a/b",
		"..",
		".",
		"nav.md",
		"~/.ssh/id_rsa",
		"/etc/passwd",
	} {
		if got := PartialNames("--include[" + name + "]--"); len(got) != 0 {
			t.Errorf("%q was read as a fragment: %v", name, got)
		}
	}

	// And what does match is forced under partials/ with an extension of
	// this side's choosing, so the name can only ever reach one directory.
	if got := PartialPath("navigation"); len(got) != 2 ||
		got[0] != PartialsDir || got[1] != "navigation.md" {
		t.Fatalf("got %v", got)
	}
}

func TestAPictureIsServedAndNotBundled(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "![A banner](assets/banner.png)")
	writePageFile(t, root, "assets/banner.png", "not really a png")
	pr := NewPagesResource(root, nil)

	// Asked for on its own, the way the reader will ask.
	reply := fulfillPage(t, pr, []string{"assets", "banner.png"}, nil)
	if reply.Status != rpc.ResourceStatusOk {
		t.Fatalf("status %v", reply.Status)
	}
	if string(reply.Data) != "not really a png" {
		t.Fatalf("got %q", reply.Data)
	}
	// And the page that shows it does not carry it: a picture behind every
	// page of a site crosses the wire once, not once per page.
	page := fulfillPage(t, pr, []string{"index.md"}, nil)
	if string(page.Data) != "![A banner](assets/banner.png)" {
		t.Fatalf("the page was changed: %q", page.Data)
	}
}

// The tests below are about what a reader receives: one page, with its
// fragments already in it.

func TestFragmentsArriveInThePage(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[nav]--\n# Home")
	writePageFile(t, root, PartialsDir+"/nav.md", "[Home](index.md)")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	want := "[Home](index.md)\n# Home"
	if string(reply.Data) != want {
		t.Fatalf("got %q, want %q", reply.Data, want)
	}
}

func TestAFragmentInsideAFragmentArrivesToo(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[header]--")
	writePageFile(t, root, PartialsDir+"/header.md", "# Site\n--include[nav]--")
	writePageFile(t, root, PartialsDir+"/nav.md", "[Home](index.md)")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	want := "# Site\n[Home](index.md)"
	if string(reply.Data) != want {
		t.Fatalf("got %q, want %q", reply.Data, want)
	}
}

func TestAFragmentUsedTwiceIsFilledInTwice(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[r]--\nmiddle\n--include[r]--")
	writePageFile(t, root, PartialsDir+"/r.md", "---")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	if n := strings.Count(string(reply.Data), "---"); n != 2 {
		t.Fatalf("filled in %d times: %q", n, reply.Data)
	}
}

func TestAFragmentThatReachesItselfIsLeftAsWritten(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[loop]--")
	writePageFile(t, root, PartialsDir+"/loop.md", "before --include[loop]-- after")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	got := string(reply.Data)
	// Left visible, so the writer can see they have made a loop rather than
	// wondering where it went.
	if !strings.Contains(got, "before") || !strings.Contains(got, "after") ||
		!strings.Contains(got, "--include[loop]--") {
		t.Fatalf("got %q", got)
	}
}

func TestTwoFragmentsThatReachEachOtherDoNotHang(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[a]--")
	writePageFile(t, root, PartialsDir+"/a.md", "A --include[b]--")
	writePageFile(t, root, PartialsDir+"/b.md", "B --include[a]--")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	got := string(reply.Data)
	if !strings.Contains(got, "A") || !strings.Contains(got, "B") {
		t.Fatalf("got %q", got)
	}
}

func TestAPageCannotPullInMoreThanTheLimit(t *testing.T) {
	root := t.TempDir()
	var page string
	for i := 0; i < 200; i++ {
		page += fmt.Sprintf("--include[frag%d]--", i)
		writePageFile(t, root, fmt.Sprintf("%s/frag%d.md", PartialsDir, i), "x")
	}
	writePageFile(t, root, "index.md", page)

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	// Past the limit the markers are shown as nothing rather than read, so
	// what arrives holds no more than the limit allows.
	if n := strings.Count(string(reply.Data), "x"); n > MaxPartialsPerPage {
		t.Fatalf("filled in %d fragments, limit is %d", n, MaxPartialsPerPage)
	}
}

func TestAPageTooLargeOnceFilledInIsSentAsWritten(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[big]--")
	writePageFile(t, root, PartialsDir+"/big.md", strings.Repeat("x", MaxExpandedBytes+1))

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	// Visibly wrong in a way that says which page and which fragment, rather
	// than an oversized reply the sending side refuses and a reader waiting
	// for a page that never comes.
	if string(reply.Data) != "--include[big]--" {
		t.Fatalf("got %d bytes", len(reply.Data))
	}
}
