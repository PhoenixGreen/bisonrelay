# Code runners

Files here run code in a Run panel (see lib/plugin_system/canvas/media/code_run_host.dart).

- **yaegi.wasm.gz** is Yaegi (https://github.com/traefik/yaegi, Apache License 2.0), a Go interpreter, built as WebAssembly by tools/yaegi_wasm/build.sh with a teaching set of the standard library. The Go runtime in it is under Go's BSD-style licence.
- **wasm_exec.js** is from the Go distribution (BSD-style licence, https://go.dev/LICENSE): the glue that runs Go's WebAssembly in a browser.

Python is Pyodide (https://pyodide.org, Mozilla Public License 2.0). It is not kept here: it is downloaded the first time Python runs, checked against the hashes in code_run_host.dart, and kept in the canvas library's Runtimes folder.
