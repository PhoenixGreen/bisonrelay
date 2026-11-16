import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:bruig/plugin_system/canvas/media/code_dart_runner.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;

// code_run_host.dart runs a Run panel's code in the app (see
// CanvasController.codeRunHost):
//
//  - a web page in a hidden browser (WebKit), its stylesheets and scripts
//    put in it (webPage), what it prints caught, and a picture taken of it;
//  - Python in that browser too, with Pyodide: downloaded the first time
//    (about 13 MB), checked against the hashes below, and kept in the
//    library's Runtimes folder;
//  - Go with Yaegi, an interpreter, built as WebAssembly (assets/code, see
//    tools/yaegi_wasm/build.sh): every file of the package read into one
//    interpreter, the entry last, which runs its main.
//
// Python and Go are served to the browser from a server on this computer
// only (127.0.0.1), on a path with a secret in it, for as long as the app
// runs. Nothing is run that was not asked for with Run.

/// pyodideVersion and pyodideFiles are the Pyodide downloaded, and each of
/// its files' SHA-256: a file that does not match is not kept.
const pyodideVersion = "314.0.7";
const pyodideFiles = {
  "pyodide.js":
      "3141b814715a72e59b51b1b18b9ceae5bf19f7c852417e431bb0a34feadf825c",
  "pyodide.asm.mjs":
      "f7cdc8ece80678ceb712f8e65ebe6d3a83203a180c399865f49612a051693635",
  "pyodide.asm.wasm":
      "cc36e3cab04fdfc9a63ff13eb52eae2b911bf46c025cc7b281f394bd3de1d5e6",
  "python_stdlib.zip":
      "fa1957e5777068fc4f7437f96d860ae2fbe9c19732ba06c84e004ec16dd7dd7a",
  "pyodide-lock.json":
      "5dc2fc119108bc148c7457dc86e7675b5c87e1cafd420b9c34c1eaef7b36c010",
};

/// runLimit is how long a run may take before it is stopped: a loop that
/// never ends must not hold the browser for ever.
const runLimit = Duration(seconds: 20);

/// AppCodeRunHost is the app's: see the file header.
class AppCodeRunHost implements CodeRunHost {
  _RunServer? _server;

  Future<_RunServer> _serve() async => _server ??= await _RunServer.start();

  @override
  Future<CodeRunOutcome> run(CodeRunner runner, CodeElement code,
      CodeFile entry, Size size, void Function(CodeLog) onLog) async {
    switch (runner) {
      case CodeRunner.web:
        return _browser(webPage(code, entry), size, onLog, picture: true);
      case CodeRunner.python:
        var ready = await _pyodide(onLog);
        if (!ready) return CodeRunOutcome(logs: _logs);
        var server = await _serve();
        return _browser(pythonPage(code, entry, server.prefix), size, onLog,
            base: server.base, picture: false);
      case CodeRunner.go:
        var server = await _serve();
        await server.yaegi();
        return _browser(goPage(code, entry, server.prefix), size, onLog,
            base: server.base, picture: false);
      case CodeRunner.dart:
        return CodeRunOutcome(
            logs: await runDart(code, entry, limit: runLimit, onLog: onLog));
      case CodeRunner.flutter:
        return _flutter(code, entry, size, onLog);
      case CodeRunner.dartpad:
        return _browser(_dartpadPage(code, entry), size, onLog,
            base: "https://dartpad.dev/", picture: true, settle: 25);
      case CodeRunner.none:
        return const CodeRunOutcome();
    }
  }

  /// _logs is what the run in hand has printed: kept for its outcome.
  List<CodeLog> _logs = [];

  /// _browser loads [html] in a hidden browser of [size] (at least a small
  /// screen's), passes on what it prints, waits for it to say it is done
  /// (or for its page to load and settle), and takes a picture of it.
  Future<CodeRunOutcome> _browser(
      String html, Size size, void Function(CodeLog) onLog,
      {String? base, required bool picture, int settle = 0}) async {
    var logs = _logs = [];
    void log(CodeLog l) {
      logs.add(l);
      onLog(l);
    }

    // A page laid out at least as wide as a phone, its picture fitted to
    // the preview after.
    var w = math.max(360.0, size.width), h = math.max(240.0, size.height);
    if (size.width < 360) h = size.height * 360 / math.max(1, size.width);
    var done = Completer<void>();
    List<int>? shot;
    var view = HeadlessInAppWebView(
      initialSize: Size(w, h),
      initialData: InAppWebViewInitialData(
          data: html,
          baseUrl: base == null ? null : WebUri(base),
          mimeType: "text/html",
          encoding: "utf-8"),
      initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          transparentBackground: false,
          isInspectable: false),
      onWebViewCreated: (c) {
        c.addJavaScriptHandler(
            handlerName: "codeConsole",
            callback: (args) {
              var kind = args.isNotEmpty ? "${args[0]}" : "log";
              var text = args.length > 1 ? "${args[1]}" : "";
              for (var line in text.split("\n")) {
                log(CodeLog(line,
                    kind: switch (kind) {
                      "error" => CodeLogKind.error,
                      "warn" => CodeLogKind.warn,
                      "note" => CodeLogKind.note,
                      _ => CodeLogKind.log,
                    }));
              }
              return null;
            });
        c.addJavaScriptHandler(
            handlerName: "codeDone",
            callback: (_) {
              if (!done.isCompleted) done.complete();
              return null;
            });
      },
      onLoadStop: (c, url) async {
        // A page is done once it has loaded and its scripts have had a
        // moment; Python and Go say so themselves.
        if (picture) {
          // [settle] seconds more for a page that builds something itself
          // (DartPad compiling the app) before it is worth a picture.
          await Future<void>.delayed(
              Duration(milliseconds: settle > 0 ? settle * 1000 : 600));
          if (!done.isCompleted) done.complete();
        }
      },
      onReceivedError: (c, request, error) {
        if (request.isForMainFrame ?? false) {
          log(CodeLog("The page could not load: ${error.description}",
              kind: CodeLogKind.error));
          if (!done.isCompleted) done.complete();
        }
      },
    );
    try {
      await view.run();
      await done.future.timeout(runLimit, onTimeout: () {
        log(CodeLog("Stopped after ${runLimit.inSeconds} seconds.",
            kind: CodeLogKind.error));
      });
      if (picture) {
        shot = await view.webViewController?.takeScreenshot(
            screenshotConfiguration:
                ScreenshotConfiguration(compressFormat: CompressFormat.PNG));
      }
    } finally {
      await view.dispose();
    }
    return CodeRunOutcome(logs: logs, picture: shot);
  }

  /// _flutter compiles a Flutter app with flutter_eval, builds its widget
  /// and takes a picture of it, laid out at least a phone's width.
  Future<CodeRunOutcome> _flutter(CodeElement code, CodeFile entry, Size size,
      void Function(CodeLog) onLog) async {
    var logs = <CodeLog>[];
    void log(CodeLog l) {
      logs.add(l);
      onLog(l);
    }

    var built = buildFlutterApp(code, entry);
    if (built.widget == null) {
      log(CodeLog(built.error ?? "The app could not be built.",
          kind: CodeLogKind.error));
      return CodeRunOutcome(logs: logs);
    }
    var w = math.max(360.0, size.width);
    var h = size.height * w / math.max(1, size.width);
    List<int>? png;
    try {
      png = await pictureOfWidget(built.widget!, Size(w, h));
    } catch (e) {
      log(CodeLog("The app could not be drawn: $e", kind: CodeLogKind.error));
    }
    log(const CodeLog("Drawn with flutter_eval.", kind: CodeLogKind.note));
    return CodeRunOutcome(logs: logs, picture: png);
  }

  /// _pyodide makes sure Pyodide is downloaded, saying so as it is.
  Future<bool> _pyodide(void Function(CodeLog) onLog) async {
    _logs = [];
    var dir = await pyodideDir();
    var missing = <String>[];
    for (var name in pyodideFiles.keys) {
      if (!await File(path.join(dir, name)).exists()) missing.add(name);
    }
    if (missing.isEmpty) return true;
    void note(String s, [CodeLogKind kind = CodeLogKind.note]) {
      var l = CodeLog(s, kind: kind);
      _logs.add(l);
      onLog(l);
    }

    note("Fetching Python (Pyodide $pyodideVersion) the first time: "
        "about 13 MB, then kept.");
    await Directory(dir).create(recursive: true);
    var client = HttpClient();
    try {
      for (var name in missing) {
        var url = Uri.parse(
            "https://cdn.jsdelivr.net/pyodide/v$pyodideVersion/full/$name");
        var req = await client.getUrl(url);
        var res = await req.close();
        if (res.statusCode != 200) {
          note("Python could not be fetched ($name: ${res.statusCode}).",
              CodeLogKind.error);
          return false;
        }
        var bytes = <int>[];
        await for (var chunk in res) {
          bytes.addAll(chunk);
        }
        if (sha256.convert(bytes).toString() != pyodideFiles[name]) {
          note(
              "Python's $name was not what was expected, so it was not "
              "kept.",
              CodeLogKind.error);
          return false;
        }
        var part = File(path.join(dir, "$name.part"));
        await part.writeAsBytes(bytes, flush: true);
        await part.rename(path.join(dir, name));
      }
    } on SocketException catch (err) {
      note("Python could not be fetched: no internet? (${err.message})",
          CodeLogKind.error);
      return false;
    } finally {
      client.close(force: true);
    }
    note("Python is ready.");
    return true;
  }
}

/// pyodideDir is where Pyodide is kept: the library's Runtimes folder.
Future<String> pyodideDir() async => path.join(await CanvasStorage.libraryDir(),
    canvasRuntimesFolder, "pyodide-$pyodideVersion");

/// _json is [v] as JSON to put in a page's script: "</" kept from ending
/// the script early, as a file that mentions </script> would.
String _json(Object v) => jsonEncode(v).replaceAll("</", r"<\/");

/// _files is [code]'s files as JSON: name to text.
String _files(CodeElement code) =>
    _json({for (var f in code.files) f.name: f.text});

const _say = '''
function say(k, m) {
  try { window.flutter_inappwebview.callHandler("codeConsole", k, String(m)); } catch (e) {}
}
function done() {
  try { window.flutter_inappwebview.callHandler("codeDone"); } catch (e) {}
}
''';

/// pythonPage is a page that runs [entry] of [code] with Pyodide, served
/// from [prefix]: every file written into a folder of its own first, so
/// imports between them work, and run as "__main__".
String pythonPage(CodeElement code, CodeFile entry, String prefix) => '''
<!doctype html><html><head><meta charset="utf-8"></head><body>
<script>$_say</script>
<script src="${prefix}pyodide/pyodide.js"></script>
<script>
(async () => {
  try {
    const py = await loadPyodide({
      indexURL: "${prefix}pyodide/",
      stdout: (l) => say("log", l),
      stderr: (l) => say("error", l),
    });
    const files = ${_files(code)};
    py.FS.mkdirTree("/home/pyodide/project");
    for (const [n, t] of Object.entries(files)) {
      py.FS.writeFile("/home/pyodide/project/" + n, t);
    }
    py.globals.set("ENTRY", ${_json(entry.name)});
    py.runPython(`
import sys, os, runpy
os.chdir("/home/pyodide/project")
sys.path.insert(0, "/home/pyodide/project")
runpy.run_path(ENTRY, run_name="__main__")
`);
  } catch (e) {
    // The traceback's end: where, and what.
    const lines = String(e && e.message || e).trim().split("\\n");
    const from = lines.findIndex((l) => l.includes('File "' + ${_json(entry.name)}) || l.includes('File "/home/pyodide/project/'));
    say("error", (from >= 0 ? lines.slice(from) : lines.slice(-3)).join("\\n"));
  }
  done();
})();
</script></body></html>''';

/// goPage is a page that runs [code]'s Go files with Yaegi, served from
/// [prefix]: the other files of the package first, [entry] last.
String goPage(CodeElement code, CodeFile entry, String prefix) {
  var files = [
    for (var f in code.files)
      if (f.language == CodeLanguage.go && f.id != entry.id) f.text,
    entry.text,
  ];
  return '''
<!doctype html><html><head><meta charset="utf-8"></head><body>
<script>$_say</script>
<script src="${prefix}go/wasm_exec.js"></script>
<script>
(async () => {
  try {
    const go = new Go();
    const res = await WebAssembly.instantiateStreaming(fetch("${prefix}go/yaegi.wasm"), go.importObject);
    go.run(res.instance);
    const out = globalThis.runGo(${_json(files)});
    for (const line of String(out).replace(/\\n\$/, "").split("\\n")) {
      if (line.length || out.length) say(/^\\d+:\\d+: /.test(line) ? "error" : "log", line);
    }
  } catch (e) {
    say("error", String(e && e.message || e));
  }
  done();
})();
</script></body></html>''';
}

/// _dartpadPage is DartPad, embedded, sent [entry]'s code once it says it
/// is ready, and left to compile and run it on Google's servers. What it
/// prints stays in DartPad's own console, shown in the picture.
String _dartpadPage(CodeElement code, CodeFile entry) => '''
<!doctype html><html><head><meta charset="utf-8">
<style>html,body,iframe{margin:0;width:100%;height:100%;border:0}</style></head><body>
<script>$_say</script>
<iframe id="pad" src="https://dartpad.dev/?embed=true&run=true&theme=light"></iframe>
<script>
const code = ${_json(entry.text)};
let sent = false;
function send() {
  if (sent) return; sent = true;
  document.getElementById("pad").contentWindow.postMessage({type: "sourceCode", sourceCode: code}, "*");
}
addEventListener("message", (e) => { if (e.data && e.data.type === "ready") send(); });
// A DartPad that never says it is ready is sent the code anyway.
setTimeout(send, 8000);
say("note", "Sent to DartPad: it needs the internet.");
</script></body></html>''';

/// _RunServer serves Pyodide and Yaegi to the hidden browser, from this
/// computer only, under a path with a secret in it.
class _RunServer {
  final HttpServer _http;
  final String _secret;
  String? _yaegiPath;
  _RunServer(this._http, this._secret);

  String get base => "http://127.0.0.1:${_http.port}/";
  String get prefix => "/$_secret/";

  static Future<_RunServer> start() async {
    var http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var rng = math.Random.secure();
    var secret = List.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, "0"))
        .join();
    var s = _RunServer(http, secret);
    http.listen(s._answer);
    return s;
  }

  /// yaegi unpacks the Go interpreter, once, from the app's assets.
  Future<void> yaegi() async {
    if (_yaegiPath != null && await File(_yaegiPath!).exists()) return;
    var dir = path.join(await CanvasStorage.libraryDir(), canvasRuntimesFolder);
    await Directory(dir).create(recursive: true);
    var packed = await rootBundle.load("assets/code/yaegi.wasm.gz");
    var bytes = gzip.decode(packed.buffer.asUint8List());
    var file = path.join(
        dir, "yaegi-${sha256.convert(bytes).toString().substring(0, 12)}.wasm");
    if (!await File(file).exists()) {
      await File("$file.part").writeAsBytes(bytes, flush: true);
      await File("$file.part").rename(file);
    }
    _yaegiPath = file;
  }

  Future<void> _answer(HttpRequest req) async {
    var res = req.response;
    try {
      var p = req.uri.path;
      if (!p.startsWith(prefix)) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      var rest = p.substring(prefix.length);
      List<int>? body;
      String type = "application/octet-stream";
      if (rest.startsWith("pyodide/")) {
        var name = rest.substring("pyodide/".length);
        if (pyodideFiles.containsKey(name)) {
          body = await File(path.join(await pyodideDir(), name)).readAsBytes();
          type = _typeOf(name);
        }
      } else if (rest == "go/yaegi.wasm" && _yaegiPath != null) {
        body = await File(_yaegiPath!).readAsBytes();
        type = "application/wasm";
      } else if (rest == "go/wasm_exec.js") {
        var js = await rootBundle.loadString("assets/code/wasm_exec.js");
        body = utf8.encode(js);
        type = "text/javascript";
      }
      if (body == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      res.headers.set(HttpHeaders.contentTypeHeader, type);
      res.headers.set("Access-Control-Allow-Origin", "*");
      res.add(body);
    } catch (_) {
      res.statusCode = HttpStatus.internalServerError;
    } finally {
      await res.close();
    }
  }

  static String _typeOf(String name) => switch (path.extension(name)) {
        ".js" || ".mjs" => "text/javascript",
        ".wasm" => "application/wasm",
        ".json" => "application/json",
        ".zip" => "application/zip",
        _ => "application/octet-stream",
      };
}

/// useAppCodeRunHost lets Run panels run code in this app.
void useAppCodeRunHost() => CanvasController.codeRunHost ??= AppCodeRunHost();
