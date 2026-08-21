package rpc

import (
	"bytes"
	"compress/zlib"
	"testing"
)

// squash returns n zero bytes, zlib-compressed. Zeroes are the cheapest thing
// to compress, which is what makes them the interesting case: a sender picks
// the ratio, and the receiver finds out only by decompressing.
func squash(t *testing.T, n uint) []byte {
	t.Helper()
	buf := bytes.NewBuffer(nil)
	zw := zlib.NewWriter(buf)
	if _, err := zw.Write(make([]byte, n)); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestABundleCannotDecompressWithoutBound(t *testing.T) {
	limit := MaxDecompressedBundleSize()

	// A message small enough to be sent, holding far more than the limit.
	bomb := squash(t, limit*8)
	if uint(len(bomb)) > MaxPayloadSizeForVersion(MaxMsgSizeV1) {
		t.Fatalf("test is not testing what it means to: the bomb is %d "+
			"bytes, which could not be sent in one message", len(bomb))
	}

	if _, err := ZLibDecode(bomb, limit); err == nil {
		t.Fatal("a message that decompresses past the limit was accepted")
	}
}

func TestABundleWithinTheBoundIsRead(t *testing.T) {
	// The bound has to leave room for what a bundle legitimately holds:
	// several messages' worth of resources.
	want := MaxPayloadSizeForVersion(MaxMsgSizeV1) * 2
	out, err := ZLibDecode(squash(t, want), MaxDecompressedBundleSize())
	if err != nil {
		t.Fatalf("a bundle of %d bytes was refused: %v", want, err)
	}
	if uint(len(out)) != want {
		t.Fatalf("got %d bytes, wanted %d", len(out), want)
	}
}

func TestTheBoundIsTiedToWhatCanBeSent(t *testing.T) {
	// The limit used to be a round number written out twice, in two
	// packages, which is how it came to be ~10x what any message could
	// carry. Deriving it keeps the two from drifting apart again.
	payload := MaxPayloadSizeForVersion(MaxMsgSizeV1)
	limit := MaxDecompressedBundleSize()

	if limit <= payload {
		t.Fatalf("limit %d leaves no room to batch: one max-size resource "+
			"is already %d", limit, payload)
	}
	if limit > payload*8 {
		t.Fatalf("limit %d is %d times what a message can carry, which is "+
			"not a bound on anything a sender has to work for",
			limit, limit/payload)
	}
}
