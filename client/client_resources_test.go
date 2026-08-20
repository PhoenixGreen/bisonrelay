package client

import (
	"testing"

	"github.com/companyzero/bisonrelay/client/resources"
	"github.com/companyzero/bisonrelay/rpc"
)

// client_resources_test.go covers reading one's own site.
//
// A reply that comes over the wire is unpacked as it is stored. A local one
// is not stored at all -- there is no request to match it to -- so it reaches
// the caller exactly as the provider built it. When that is a bundle, what
// arrives is the compressed bundle rather than the page, which the reader
// then tries to decode as text: "Unexpected extension byte (at offset 1)".

func bundleOf(t *testing.T, items map[string]string) *rpc.RMFetchResourceReply {
	t.Helper()
	bundle := rpc.RMResourceBundle{
		Resources: map[string]rpc.RMFetchResourceReply{},
	}
	for path, body := range items {
		bundle.Resources[path] = rpc.RMFetchResourceReply{
			Data:   []byte(body),
			Status: rpc.ResourceStatusOk,
		}
	}
	br := &resources.BundledResource{Bundle: bundle}
	res, err := br.Fulfill(nil, UserID{}, &rpc.RMFetchResource{})
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func TestUnbundleLocalTakesOutThePageAsked(t *testing.T) {
	res := bundleOf(t, map[string]string{
		"index.md":           "--include[nav]--\n# Home",
		"partials/nav.md":    "[Home](index.md)",
	})

	got, err := unbundleLocal(res, "index.md")
	if err != nil {
		t.Fatal(err)
	}
	if string(got.Data) != "--include[nav]--\n# Home" {
		t.Fatalf("got %q", got.Data)
	}
	// And it is no longer flagged as a bundle, or the reader would try to
	// unpack it a second time.
	if got.Meta[rpc.ResourceMetaResponseIsBundle] ==
		rpc.ResourceMetaResponseIsBundleValue {
		t.Fatal("the extracted page is still marked as a bundle")
	}
}

func TestUnbundleLocalCanTakeOutAFragmentToo(t *testing.T) {
	res := bundleOf(t, map[string]string{
		"index.md":        "# Home",
		"partials/nav.md": "[Home](index.md)",
	})

	got, err := unbundleLocal(res, "partials/nav.md")
	if err != nil {
		t.Fatal(err)
	}
	if string(got.Data) != "[Home](index.md)" {
		t.Fatalf("got %q", got.Data)
	}
}

func TestUnbundleLocalLeavesAPlainReplyAlone(t *testing.T) {
	plain := &rpc.RMFetchResourceReply{
		Data:   []byte("# Home"),
		Status: rpc.ResourceStatusOk,
	}
	got, err := unbundleLocal(plain, "index.md")
	if err != nil {
		t.Fatal(err)
	}
	if got != plain {
		t.Fatal("a reply that is not a bundle should be passed through")
	}
}

func TestUnbundleLocalMissingPathIsNotFound(t *testing.T) {
	res := bundleOf(t, map[string]string{"index.md": "# Home"})
	got, err := unbundleLocal(res, "gone.md")
	if err != nil {
		t.Fatal(err)
	}
	if got.Status != rpc.ResourceStatusNotFound {
		t.Fatalf("expected not found, got %v", got.Status)
	}
}
