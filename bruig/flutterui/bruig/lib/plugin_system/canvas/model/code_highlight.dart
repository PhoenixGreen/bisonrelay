import 'dart:collection';

import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/re_highlight.dart';

// code_highlight.dart colours code by what each piece of it is: a keyword,
// a string, a function's name. The grammars are highlight.js's, in Dart
// (re_highlight), so a lesson's colours are the ones a learner sees on the
// web. What comes out is runs of the text, each with its role; the painter
// and the stage's editor both build their text from the same runs, so the
// two never disagree.

/// CodeRole is what a run of code is, for its colour.
enum CodeRole {
  plain,
  keyword,
  string,
  number,
  comment,
  function,
  type,
  tag,
  attribute,
}

/// CodeRun is [text]'s characters [start] to [end] in [role]; [link] is a
/// file's id where the run is that file's name, used from another file.
class CodeRun {
  final int start;
  final int end;
  final CodeRole role;
  final String link;
  const CodeRun(this.start, this.end, this.role, [this.link = ""]);
}

CodeRole _roleOf(String? scope) {
  if (scope == null) return CodeRole.plain;
  var s = scope.split(".").first;
  return switch (s) {
    "keyword" || "literal" || "selector-tag" || "doctag" => CodeRole.keyword,
    "string" || "regexp" => CodeRole.string,
    "number" => CodeRole.number,
    "comment" || "meta" || "quote" => CodeRole.comment,
    "title" ||
    "section" ||
    "selector-id" ||
    "selector-class" =>
      scope == "title.class" || scope == "title.class.inherited"
          ? CodeRole.type
          : CodeRole.function,
    "type" || "built_in" || "symbol" => CodeRole.type,
    "tag" || "name" => CodeRole.tag,
    "attr" ||
    "attribute" ||
    "property" ||
    "selector-pseudo" =>
      CodeRole.attribute,
    "variable" when scope == "variable.language" => CodeRole.type,
    _ => CodeRole.plain,
  };
}

/// _Runs gathers a highlight's text into runs: each piece of text in the
/// innermost role that has a colour.
class _Runs implements HighlightRenderer {
  final List<CodeRun> runs = [];
  final List<CodeRole?> _stack = [];
  int _at = 0;

  @override
  void addText(String text) {
    CodeRole role = CodeRole.plain;
    for (var r in _stack.reversed) {
      if (r != null && r != CodeRole.plain) {
        role = r;
        break;
      }
    }
    if (text.isEmpty) return;
    if (runs.isNotEmpty && runs.last.role == role && runs.last.end == _at) {
      var last = runs.removeLast();
      runs.add(CodeRun(last.start, _at + text.length, role));
    } else {
      runs.add(CodeRun(_at, _at + text.length, role));
    }
    _at += text.length;
  }

  @override
  void openNode(DataNode node) => _stack.add(_roleOf(node.scope));

  @override
  void closeNode(DataNode node) {
    if (_stack.isNotEmpty) _stack.removeLast();
  }
}

final Highlight _highlight = Highlight()
  ..registerLanguages({
    "xml": langXml,
    "css": langCss,
    "javascript": langJavascript,
    "python": langPython,
    "go": langGo,
    "dart": langDart,
  });

/// _cache keeps the last highlights by language and text: a pane is drawn
/// every frame, and its file changes only as it is edited.
final LinkedHashMap<String, List<CodeRun>> _cache = LinkedHashMap();

/// highlightRuns is [text] in [language], as runs covering all of it.
List<CodeRun> highlightRuns(CodeLanguage language, String text) {
  if (language.grammar.isEmpty || text.isEmpty) {
    return [if (text.isNotEmpty) CodeRun(0, text.length, CodeRole.plain)];
  }
  var key = "${language.grammar}\u0000$text";
  var hit = _cache.remove(key);
  if (hit != null) {
    _cache[key] = hit;
    return hit;
  }
  List<CodeRun> runs;
  try {
    var r = _Runs();
    _highlight.highlight(code: text, language: language.grammar).render(r);
    runs = r.runs;
    // Whatever the grammar left out, plain: the runs must cover the text.
    if (runs.isEmpty || runs.last.end < text.length) {
      runs = [
        ...runs,
        CodeRun(runs.isEmpty ? 0 : runs.last.end, text.length, CodeRole.plain)
      ];
    }
  } catch (_) {
    runs = [CodeRun(0, text.length, CodeRole.plain)];
  }
  _cache[key] = runs;
  while (_cache.length > 48) {
    _cache.remove(_cache.keys.first);
  }
  return runs;
}

/// linkNames is what names each of [e]'s files other than [self] goes by in
/// code: its name, and for a Python module its name without ".py" (as
/// "import words" uses words.py).
Map<String, String> linkNames(CodeElement e, String self) => {
      for (var f in e.files)
        if (f.id != self) ...{
          f.name: f.id,
          if (f.language == CodeLanguage.python && f.name.endsWith(".py"))
            f.name.substring(0, f.name.length - 3): f.id,
        }
    };

/// withLinks splits [runs] of [text] where another file's name is used,
/// marking those pieces with the file's id (whole words only).
List<CodeRun> withLinks(
    List<CodeRun> runs, String text, Map<String, String> names) {
  if (names.isEmpty) return runs;
  var keys = names.keys.where((k) => k.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  var pattern =
      RegExp(r"(?<![\w.])(" + keys.map(RegExp.escape).join("|") + r")(?![\w])");
  var found = pattern.allMatches(text).toList();
  if (found.isEmpty) return runs;
  var out = <CodeRun>[];
  var m = 0;
  for (var r in runs) {
    var at = r.start;
    while (m < found.length && found[m].end <= at) {
      m++;
    }
    var k = m;
    while (k < found.length && found[k].start < r.end) {
      var f = found[k];
      var s = f.start < at ? at : f.start;
      var e = f.end > r.end ? r.end : f.end;
      // A bare module name ("words") only in code: in a string or a
      // comment it is a word. A file's whole name counts anywhere
      // ("style.css" in an href).
      var bare = !f[1]!.contains(".");
      if (bare && (r.role == CodeRole.string || r.role == CodeRole.comment)) {
        k++;
        continue;
      }
      if (s > at) out.add(CodeRun(at, s, r.role));
      out.add(CodeRun(s, e, r.role, names[f[1]!] ?? ""));
      at = e;
      if (f.end > r.end) break;
      k++;
    }
    if (at < r.end) out.add(CodeRun(at, r.end, r.role));
  }
  return out;
}
