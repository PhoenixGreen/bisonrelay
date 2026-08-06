package wasmhost

import (
	"fmt"
	"io"
	"os"
)

// readFileCapped reads path, refusing to read more than maxBytes so a
// maliciously huge plugin.wasm can't be used to exhaust memory.
func readFileCapped(path string, maxBytes int64) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return nil, err
	}
	if fi.Size() > maxBytes {
		return nil, fmt.Errorf("file too large (%d bytes, max %d)", fi.Size(), maxBytes)
	}

	return io.ReadAll(io.LimitReader(f, maxBytes))
}
