package resources

import (
	"context"
	"encoding/json"
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
