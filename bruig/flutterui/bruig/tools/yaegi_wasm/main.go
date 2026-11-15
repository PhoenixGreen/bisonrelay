//go:build js && wasm

package main

import (
	"bytes"
	"syscall/js"

	"github.com/traefik/yaegi/interp"
	"yaegiwasm/teach"
)

func main() {
	js.Global().Set("runGo", js.FuncOf(func(this js.Value, args []js.Value) any {
		var out bytes.Buffer
		i := interp.New(interp.Options{Stdout: &out, Stderr: &out})
		i.Use(teach.Symbols)
		files := args[0]
		for k := 0; k < files.Length(); k++ {
			if _, err := i.Eval(files.Index(k).String()); err != nil {
				out.WriteString(err.Error())
				break
			}
		}
		return out.String()
	}))
	select {}
}
