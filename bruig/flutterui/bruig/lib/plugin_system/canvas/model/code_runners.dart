import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';

// code_runners.dart is what runs a Code panel's project, worked out from
// its files: a web page in a browser, Python in the browser (Pyodide), Go in
// the browser (Yaegi), Dart in the app (dart_eval), a Flutter app drawn in
// the app (flutter_eval) or, when asked, on DartPad. And the pieces of a run
// that are plain text work: the page with its stylesheets and scripts put in
// it.

enum CodeRunner {
  web("Browser"),
  python("Python · Pyodide"),
  go("Go · Yaegi"),
  dart("Dart · dart_eval"),
  flutter("Flutter · flutter_eval"),
  dartpad("Flutter · DartPad"),
  none("Nothing to run");

  final String label;
  const CodeRunner(this.label);

  /// online is whether it needs the internet each time it runs.
  bool get online => this == dartpad;

  /// previews is whether it makes something to look at, not just output.
  bool get previews => this == web || this == flutter || this == dartpad;
}

/// runnable is whether a file of [language] can be run from.
bool runnable(CodeLanguage language) => switch (language) {
      CodeLanguage.html ||
      CodeLanguage.js ||
      CodeLanguage.python ||
      CodeLanguage.go ||
      CodeLanguage.dart =>
        true,
      _ => false,
    };

/// entryFile is the file [run] starts [code] from: its own pick, else the
/// first page, else the first file with a main, else the first it can run.
CodeFile? entryFile(CodeRunElement run, CodeElement? code) {
  if (code == null) return null;
  if (code.file(run.entry) case var f? when runnable(f.language)) return f;
  CodeFile? first(bool Function(CodeFile) ok) =>
      code.files.where(ok).firstOrNull;
  return first((f) => f.language == CodeLanguage.html) ??
      first((f) =>
          (f.language == CodeLanguage.python && f.text.contains("__main__")) ||
          f.name == "main.py" ||
          f.name == "main.go" ||
          f.name == "main.dart") ??
      first((f) => runnable(f.language));
}

/// isFlutter is whether Dart [text] is a Flutter app.
bool isFlutter(String text) => text.contains("package:flutter/");

/// runnerOf is what runs [run]'s project.
CodeRunner runnerOf(CodeRunElement run, CodeElement? code) {
  var f = entryFile(run, code);
  if (f == null) return CodeRunner.none;
  return switch (f.language) {
    CodeLanguage.html || CodeLanguage.js || CodeLanguage.css => CodeRunner.web,
    CodeLanguage.python => CodeRunner.python,
    CodeLanguage.go => CodeRunner.go,
    // A Flutter project's Dart is an app even before it says so.
    CodeLanguage.dart => isFlutter(f.text) || code!.project == CodeKind.flutter
        ? (run.dartpad ? CodeRunner.dartpad : CodeRunner.flutter)
        : CodeRunner.dart,
    CodeLanguage.text => CodeRunner.none,
  };
}

/// consoleCapture is the script put first in a page so what it prints, and
/// its errors, come back to the app: each as a message to the
/// "codeConsole" handler.
const consoleCapture = r'''<script>(function(){
function send(k,a){try{var m=Array.prototype.map.call(a,function(x){if(typeof x==="string")return x;try{return JSON.stringify(x)}catch(e){return String(x)}}).join(" ");
window.flutter_inappwebview&&window.flutter_inappwebview.callHandler("codeConsole",k,m)}catch(e){}}
["log","info","warn","error"].forEach(function(k){var o=console[k];console[k]=function(){send(k,arguments);o.apply(console,arguments)}});
addEventListener("error",function(e){send("error",[e.message+(e.lineno?" (line "+e.lineno+")":"")])});
addEventListener("unhandledrejection",function(e){send("error",[String(e.reason)])});
})();</script>''';

/// webPage is [code]'s page [entry] as one document: each stylesheet it
/// links and each script it loads that is a file of the project put into
/// it, and [head] (the console's capture) first. A script file run by
/// itself is wrapped in an empty page.
String webPage(CodeElement code, CodeFile entry,
    {String head = consoleCapture}) {
  if (entry.language == CodeLanguage.js) {
    return "<!doctype html><html><head>$head</head><body>"
        "<script>\n${_safe(entry.text)}\n</script></body></html>";
  }
  var html = entry.text;
  html = html.replaceAllMapped(
      RegExp(r'''<link\b[^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>''',
          caseSensitive: false), (m) {
    var f = code.fileNamed(m[1]!);
    if (f == null || f.language != CodeLanguage.css) return m[0]!;
    return "<style>\n${f.text}\n</style>";
  });
  html = html.replaceAllMapped(
      RegExp(
          r'''<script\b([^>]*)\bsrc\s*=\s*["']([^"']+)["']([^>]*)>\s*</script>''',
          caseSensitive: false), (m) {
    var f = code.fileNamed(m[2]!);
    if (f == null || f.language != CodeLanguage.js) return m[0]!;
    var attrs = "${m[1]}${m[3]}".trim();
    return "<script${attrs.isEmpty ? "" : " $attrs"}>\n${_safe(f.text)}\n</script>";
  });
  var headTag = RegExp(r"<head\b[^>]*>", caseSensitive: false);
  if (headTag.hasMatch(html)) {
    return html.replaceFirstMapped(headTag, (m) => "${m[0]}$head");
  }
  return "$head$html";
}

/// _safe keeps a script's own text from closing the tag it is put in.
String _safe(String js) =>
    js.replaceAll(RegExp(r"</script", caseSensitive: false), r"<\/script");
