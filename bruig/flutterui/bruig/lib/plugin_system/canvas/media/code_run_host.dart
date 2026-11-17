import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
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

// code_run_host.dart runs a Run panel's code (see
// CanvasController.codeRunHost): web pages in hidden WebKit, Python there
// with Pyodide (downloaded once, hash-checked), Go with Yaegi as WebAssembly
// (tools/yaegi_wasm/build.sh). Python and Go are served from 127.0.0.1 on a
// secret path. Nothing runs unless asked with Run.

/// pyodideVersion and pyodideFiles are the Pyodide downloaded and each
/// file's SHA-256: a file that does not match is not kept.
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

/// sealedSettings are every Code page browser's settings: own storage,
/// forgotten (no cookie follows a reader), no windows, every navigation
/// asked about (see [stayOnPage], [sealed]).
InAppWebViewSettings sealedSettings({bool transparentBackground = true}) =>
    InAppWebViewSettings(
        javaScriptEnabled: true,
        isInspectable: false,
        incognito: true,
        javaScriptCanOpenWindowsAutomatically: false,
        useShouldOverrideUrlLoading: true,
        transparentBackground: transparentBackground);

/// stayOnPage keeps a Code page where it was put: navigating elsewhere
/// tells that address who is reading. Only a run server at [origin] may
/// load whole; frames are [sealed]'s business.
Future<NavigationActionPolicy> stayOnPage(NavigationAction action,
    {String origin = ""}) async {
  var url = action.request.url;
  if (!action.isForMainFrame || url == null) {
    return NavigationActionPolicy.ALLOW;
  }
  if (const {"about", "data", "blob"}.contains(url.scheme)) {
    return NavigationActionPolicy.ALLOW;
  }
  if (origin.isNotEmpty && url.origin == origin) {
    return NavigationActionPolicy.ALLOW;
  }
  return NavigationActionPolicy.CANCEL;
}

/// _localOrigin is [base]'s origin where it is this machine (the run
/// server), else nothing.
String _localOrigin(String base) {
  var u = Uri.parse(base);
  return u.host == "127.0.0.1" || u.host == "localhost" ? u.origin : "";
}

/// runLimit is how long a run may take: a loop that never ends must not
/// hold the browser for ever.
const runLimit = Duration(seconds: 20);

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
        // Never past a proxy somebody set up to hide from the network.
        if (await networkIsProxied()) {
          return const CodeRunOutcome(logs: [
            CodeLog(
                "DartPad isn't used while a proxy is set: it would be "
                "reached without it.",
                kind: CodeLogKind.note)
          ]);
        }
        return _browser(_dartpadPage(code, entry), size, onLog,
            base: "https://dartpad.dev/", picture: true, settle: 25);
      case CodeRunner.none:
        return const CodeRunOutcome();
    }
  }

  /// _logs is what the run in hand has printed.
  List<CodeLog> _logs = [];

  /// _browser loads [html] hidden at [size] (at least a small screen),
  /// passes on its prints, waits for it to settle, and takes a picture.
  Future<CodeRunOutcome> _browser(
      String html, Size size, void Function(CodeLog) onLog,
      {String? base, required bool picture, int settle = 0}) async {
    var logs = _logs = [];
    void log(CodeLog l) {
      logs.add(l);
      onLog(l);
    }

    // At least a phone's width; the picture is fitted to the preview.
    var w = math.max(360.0, size.width), h = math.max(240.0, size.height);
    if (size.width < 360) h = size.height * 360 / math.max(1, size.width);
    var done = Completer<void>();
    List<int>? shot;
    // DartPad is run on its own site on purpose; anything else is sealed
    // off the network (see [sealed]) but for this machine's run server.
    var origin = base == null ? "" : Uri.parse(base).origin;
    var open = base != null && origin != _localOrigin(base);
    var view = HeadlessInAppWebView(
      initialSize: Size(w, h),
      initialData: InAppWebViewInitialData(
          data: open ? html : sealed(html, origin: origin),
          baseUrl: base == null ? null : WebUri(base),
          mimeType: "text/html",
          encoding: "utf-8"),
      initialSettings: open
          ? InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: false,
              isInspectable: false,
              incognito: true)
          : sealedSettings(transparentBackground: false),
      shouldOverrideUrlLoading:
          open ? null : (c, action) => stayOnPage(action, origin: origin),
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
        // A page is done once loaded and its scripts have had a moment;
        // Python and Go say so themselves.
        if (picture) {
          // [settle] seconds more for a page that builds itself (DartPad
          // compiling) before it is worth a picture.
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

  /// _flutter compiles a Flutter app with flutter_eval and takes a picture
  /// of its widget, at least a phone's width.
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

  /// _pyodide makes sure Pyodide is downloaded, reporting progress.
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

    // As every canvas download (canvas_network.dart): never past a proxy,
    // https only, size capped.
    if (await networkIsProxied()) {
      note(
          "Python isn't fetched while a proxy is set: it would be reached "
          "without it.",
          CodeLogKind.error);
      return false;
    }
    note("Fetching Python (Pyodide $pyodideVersion) the first time: "
        "about 13 MB, then kept.");
    await Directory(dir).create(recursive: true);
    var client = canvasHttpClient();
    try {
      for (var name in missing) {
        var url = Uri.parse(
            "https://cdn.jsdelivr.net/pyodide/v$pyodideVersion/full/$name");
        var res = await canvasGet(client, url);
        if (res == null || res.statusCode != 200) {
          note(
              "Python could not be fetched "
              "($name: ${res?.statusCode ?? "refused"}).",
              CodeLogKind.error);
          return false;
        }
        var bytes = await readCapped(res, 64 * 1024 * 1024);
        if (bytes == null) {
          note("Python's $name was too big, so it was not kept.",
              CodeLogKind.error);
          return false;
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

/// _json is [v] as JSON for a page's script, with "</" escaped so a file
/// mentioning </script> cannot end the script early.
String _json(Object v) => jsonEncode(v).replaceAll("</", r"<\/");

/// _files is [code]'s files as JSON, name to text.
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

/// pythonPage runs [entry] with Pyodide from [prefix]: every file written
/// to a folder first, so imports work, then run as "__main__".
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

/// goPage runs [code]'s Go files with Yaegi, served from [prefix]: the
/// package's other files first, [entry] last.
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

/// _dartpadPage is DartPad, embedded, sent [entry]'s code once ready, to
/// compile and run on Google's servers. Its console shows in the picture.
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

  /// yaegi unpacks the Go interpreter from the app's assets, once.
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
