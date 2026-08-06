// Command wasmhostfixtureheadless is a minimal HEADLESS dynamic-wasm
// plugin used only by wasmhost's tests: it exports alloc plus two
// optional capability exports (get_spellcheck_data, fetch_link_card), but
// deliberately NOT render_screen/handle_event/poll, to prove a plugin with
// no nav item loads and behaves correctly (and that calling its
// unimplemented screen exports errors cleanly rather than panicking).
package main

import (
	"strconv"
	"unsafe"
)

//go:wasmimport env fetch_url
func hostFetchURL(url string) uint64

//go:wasmimport env fetch_url_ex
func hostFetchURLEx(url string, headersJSON string) uint64

//go:wasmimport env fetch_last_status
func hostFetchLastStatus() int32

//go:wasmimport env fetch_last_content_type
func hostFetchLastContentType() uint64

var pinned = map[int32][]byte{}

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

func writeResult(data []byte) uint64 {
	ptr := alloc(int32(len(data)))
	copy(pinned[ptr], data)
	return (uint64(uint32(ptr)) << 32) | uint64(len(data))
}

//go:wasmexport get_spellcheck_data
func getSpellcheckData() uint64 {
	return writeResult([]byte(`{"words":["hello","world"],"grammarRules":[{"pattern":"foo","message":"m","suggest":"bar"}]}`))
}

// fetch_link_card exercises fetch_url_ex plus fetch_last_status/
// fetch_last_content_type (not plain fetch_url), folding all three into the
// result title so a test calling it through the real Runtime.FetchLinkCard
// can assert on all of them without a separate test-only export.
//
//go:wasmexport fetch_link_card
func fetchLinkCard(url string) uint64 {
	packed := hostFetchURLEx(url, `{"X-Test-Header":"custom-value"}`)
	body := readMem(unpack(packed))
	status := hostFetchLastStatus()
	ct := readMem(unpack(hostFetchLastContentType()))
	title := "body=" + string(body) + " status=" + strconv.Itoa(int(status)) + " contentType=" + string(ct)
	return writeResult([]byte(`{"title":"` + title + `","description":"","author":"","thumbnailB64":""}`))
}

func main() {}
