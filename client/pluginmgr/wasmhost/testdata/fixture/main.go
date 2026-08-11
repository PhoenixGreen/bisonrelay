// Command wasmhostfixture is a minimal dynamic-wasm plugin used only by
// wasmhost's tests, compiled on the fly via `go build -buildmode=c-shared
// GOOS=wasip1 GOARCH=wasm`. It exercises every part of the host<->guest ABI
// (render_screen, handle_event, poll, and all four host imports) so the
// tests can verify the real wasmhost.Runtime against real compiled wasm,
// not a hand-rolled substitute.
package main

import (
	"strconv"
	"time"
	"unsafe"
)

//go:wasmimport env fetch_url
func hostFetchURL(url string) uint64

//go:wasmimport env kv_get
func hostKVGet(key string) uint64

//go:wasmimport env kv_set
func hostKVSet(key string, value string)

//go:wasmimport env log_msg
func hostLogMsg(msg string)

// pinned keeps allocated buffers alive: nothing else references them once
// alloc returns, so without this the Go GC could collect them before the
// host gets a chance to write to (or read from) the memory their pointer
// refers to.
var pinned = map[int32][]byte{}

// alloc is the one export every dynamic-wasm plugin must provide: it's how
// the host places a string it owns (e.g. a screen id, or a fetch_url
// response) into THIS module's own linear memory, since go:wasmexport/
// go:wasmimport marshal string parameters automatically but not results.
//
//go:wasmexport alloc
func alloc(size int32) int32 {
	if size == 0 {
		size = 1
	}
	buf := make([]byte, size)
	pinned[int32(uintptr(unsafe.Pointer(&buf[0])))] = buf
	return int32(uintptr(unsafe.Pointer(&buf[0])))
}

func readMem(ptr, length uint32) []byte {
	if length == 0 {
		return nil
	}
	return unsafe.Slice((*byte)(unsafe.Pointer(uintptr(ptr))), length)
}

func unpack(packed uint64) (ptr, length uint32) {
	return uint32(packed >> 32), uint32(packed & 0xFFFFFFFF)
}

// writeResult is the mirror image of the host's allocInGuest: since this
// side (the guest) already owns the data, it just needs to place it
// somewhere in its own memory and return the packed pointer -- no
// reentrant alloc call needed, unlike the host->guest direction.
func writeResult(data []byte) uint64 {
	ptr := alloc(int32(len(data)))
	copy(pinned[ptr], data)
	return (uint64(uint32(ptr)) << 32) | uint64(len(data))
}

//go:wasmexport render_screen
func renderScreen(screenID string) uint64 {
	return writeResult([]byte(`{"title":"` + screenID + `","widgets":[{"type":"text","text":"hello from ` + screenID + `"}]}`))
}

//go:wasmexport handle_event
func handleEvent(screenID string, event string, payloadJSON string) uint64 {
	hostKVSet("last_event", event)
	hostKVSet("last_payload", payloadJSON)
	return writeResult([]byte(`{"title":"handled ` + event + `","widgets":[]}`))
}

//go:wasmexport poll
func poll() int32 {
	// Recorded so tests can confirm the guest's wall clock is the real one
	// (wazero defaults to a FAKE clock unless the host opts into
	// WithSysWalltime -- see wasmhost.go's Load).
	hostKVSet("poll_time_unix", strconv.FormatInt(time.Now().Unix(), 10))

	packed := hostFetchURL("https://example.invalid/feed")
	body := readMem(unpack(packed))
	hostLogMsg("poll fetched body")
	hostKVSet("last_poll_body", string(body))

	prevPacked := hostKVGet("poll_count")
	prev := string(readMem(unpack(prevPacked)))
	next := "1"
	if prev == "1" {
		next = "2"
	}
	hostKVSet("poll_count", next)
	return 0
}

func main() {}
