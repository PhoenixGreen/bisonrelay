package resources

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"os"
	"path/filepath"
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

func isBundle(reply *rpc.RMFetchResourceReply) bool {
	return reply.Meta[rpc.ResourceMetaResponseIsBundle] ==
		rpc.ResourceMetaResponseIsBundleValue
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

func TestPageWithNoPartialsIsNotBundled(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "# Plain")
	pr := NewPagesResource(root, nil)

	reply := fulfillPage(t, pr, []string{"index.md"}, nil)
	if isBundle(reply) {
		t.Fatal("a page with nothing shared has nothing to bundle")
	}
	if string(reply.Data) != "# Plain" {
		t.Fatalf("got %q", reply.Data)
	}
}

func TestPartialsAreBundledWithThePage(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[nav]--\n# Home")
	writePageFile(t, root, "partials/nav.md", "[Home](index.md)")
	pr := NewPagesResource(root, nil)

	reply := fulfillPage(t, pr, []string{"index.md"}, nil)
	if !isBundle(reply) {
		t.Fatal("a page that shares a fragment is sent as a bundle")
	}

	// The page itself has to be in it: the client looks the request path
	// up in the bundle to find what it asked for, and without it the
	// reader gets the bundle's own empty body.
	bundle := decodeBundle(t, reply)
	if _, ok := bundle.Resources["index.md"]; !ok {
		t.Fatalf("the page is missing from its own bundle: %v", keys(bundle))
	}
	if _, ok := bundle.Resources["partials/nav.md"]; !ok {
		t.Fatalf("the fragment is missing: %v", keys(bundle))
	}
	// Unexpanded: the marker survives, and the reader's client fills it.
	if got := string(bundle.Resources["index.md"].Data); got != "--include[nav]--\n# Home" {
		t.Fatalf("the page was expanded rather than left alone: %q", got)
	}
}

func TestAFragmentAlreadyHeldIsNotSentAgain(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "about.md", "--include[nav]--\n# About")
	writePageFile(t, root, "partials/nav.md", "[Home](index.md)")
	pr := NewPagesResource(root, nil)

	// This is the saving the whole feature is for: the second page of a
	// site does not carry the navigation bar again.
	reply := fulfillPage(t, pr, []string{"about.md"},
		map[string]string{rpc.ResourceMetaHavePartials: "nav"})
	if isBundle(reply) {
		t.Fatal("nothing was missing, so there was nothing to bundle")
	}
	if string(reply.Data) != "--include[nav]--\n# About" {
		t.Fatalf("got %q", reply.Data)
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
	if isBundle(reply) {
		t.Fatal("there was nothing to bundle")
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

func decodeBundle(t *testing.T, reply *rpc.RMFetchResourceReply) rpc.RMResourceBundle {
	t.Helper()
	raw, err := rpc.ZLibDecode(reply.Data, 10_000_000)
	if err != nil {
		t.Fatal(err)
	}
	var b rpc.RMResourceBundle
	if err := json.Unmarshal(raw, &b); err != nil {
		t.Fatal(err)
	}
	return b
}

func keys(b rpc.RMResourceBundle) []string {
	var out []string
	for k := range b.Resources {
		out = append(out, k)
	}
	return out
}

func TestNestedFragmentsAreCollected(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[header]--")
	writePageFile(t, root, "partials/header.md",
		"# Site\n--include[navigation]--")
	writePageFile(t, root, "partials/navigation.md", "[Home](index.md)")
	pr := NewPagesResource(root, nil)

	// A header holding a navigation bar is the ordinary case, and the page
	// only names the header.
	reply := fulfillPage(t, pr, []string{"index.md"}, nil)
	b := decodeBundle(t, reply)
	for _, want := range []string{"index.md", "partials/header.md",
		"partials/navigation.md"} {
		if _, ok := b.Resources[want]; !ok {
			t.Fatalf("%q missing from %v", want, keys(b))
		}
	}
}

func TestAHeldFragmentStillYieldsWhatItReaches(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[header]--")
	writePageFile(t, root, "partials/header.md", "--include[navigation]--")
	writePageFile(t, root, "partials/navigation.md", "[Home](index.md)")
	pr := NewPagesResource(root, nil)

	// The client has the header but has never seen what the header refers
	// to. Stopping at the header would leave that hole unfilled forever.
	reply := fulfillPage(t, pr, []string{"index.md"},
		map[string]string{rpc.ResourceMetaHavePartials: "header"})
	b := decodeBundle(t, reply)

	if _, ok := b.Resources["partials/header.md"]; ok {
		t.Fatal("the header was already held and should not be sent again")
	}
	if _, ok := b.Resources["partials/navigation.md"]; !ok {
		t.Fatalf("what the header reaches is missing: %v", keys(b))
	}
}

func TestFragmentCyclesDoNotHang(t *testing.T) {
	root := t.TempDir()
	writePageFile(t, root, "index.md", "--include[a]--")
	writePageFile(t, root, "partials/a.md", "--include[b]--")
	writePageFile(t, root, "partials/b.md", "--include[a]--")
	writePageFile(t, root, "partials/self.md", "--include[self]--")
	pr := NewPagesResource(root, nil)

	reply := fulfillPage(t, pr, []string{"index.md"}, nil)
	b := decodeBundle(t, reply)
	if len(b.Resources) != 3 { // the page, a, b
		t.Fatalf("got %v", keys(b))
	}

	// And one that names itself.
	writePageFile(t, root, "index.md", "--include[self]--")
	reply = fulfillPage(t, pr, []string{"index.md"}, nil)
	if b := decodeBundle(t, reply); len(b.Resources) != 2 {
		t.Fatalf("got %v", keys(b))
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

func TestAPageCannotAskForMoreThanTheLimit(t *testing.T) {
	root := t.TempDir()
	var page string
	for i := 0; i < 500; i++ {
		page += fmt.Sprintf("--include[frag%d]--\n", i)
		writePageFile(t, root, fmt.Sprintf("partials/frag%d.md", i), "x")
	}
	writePageFile(t, root, "index.md", page)

	if n := len(PartialNames(page)); n != MaxPartialsPerPage {
		t.Fatalf("a page reached %d fragments, want %d", n,
			MaxPartialsPerPage)
	}

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	b := decodeBundle(t, reply)
	// The page itself, and no more fragments than the limit.
	if len(b.Resources) > MaxPartialsPerPage+1 {
		t.Fatalf("bundled %d resources", len(b.Resources))
	}
}

func TestABundleStaysWithinItsSize(t *testing.T) {
	root := t.TempDir()
	big := strings.Repeat("x", 300*1024)
	writePageFile(t, root, "index.md",
		"--include[one]--\n--include[two]--\n--include[three]--")
	writePageFile(t, root, "partials/one.md", big)
	writePageFile(t, root, "partials/two.md", big)
	writePageFile(t, root, "partials/three.md", "small")

	reply := fulfillPage(t, NewPagesResource(root, nil), []string{"index.md"}, nil)
	b := decodeBundle(t, reply)

	var total int
	for _, item := range b.Resources {
		total += len(item.Data)
	}
	if total > MaxBundleBytes+len("--include[one]----include[two]--") {
		t.Fatalf("bundled %d bytes, past the %d limit", total, MaxBundleBytes)
	}

	// The page is always in it, whatever had to be left out: without it the
	// reader has nothing to show, and the fragments they can ask for.
	if _, ok := b.Resources["index.md"]; !ok {
		t.Fatalf("the page is missing: %v", keys(b))
	}
	// The small one still went, rather than one large fragment costing
	// every fragment after it.
	if _, ok := b.Resources["partials/three.md"]; !ok {
		t.Fatalf("a fragment that fit was left out: %v", keys(b))
	}
}
