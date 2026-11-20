import 'package:bruig/plugin_system/creative_ai/claude/claude_code.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/tools/guide.dart';
import 'package:flutter/material.dart';

// writing_suggestions.dart is the changes Claude offers to the document open
// on the Writing page, waiting to be accepted or rejected, and the quick
// rewrites (Improve, Shorten...) that make them.
//
// A suggestion remembers the text it replaces, not only where it was. The
// person goes on writing while one waits, so by the time it is accepted its
// place may have moved; it is found again by its text, nearest where it
// was, and refused if that text is gone rather than pasted over something
// else.

class WritingSuggestion {
  final int id;
  int start;
  int end;
  final String original;
  final String replacement;
  final String note;

  /// source is what made it: "Improve", "Claude Code", "Writing sidebar".
  final String source;

  /// document is the open document it belongs to (folder/name).
  final String document;

  /// before and after are a little of the text either side, which is how it
  /// is found again once the writer has typed above it -- and the only way an
  /// insertion, which has no text of its own, can be.
  final String before;
  final String after;

  WritingSuggestion({
    required this.id,
    required this.start,
    required this.end,
    required this.original,
    required this.replacement,
    required this.note,
    required this.source,
    required this.document,
    this.before = "",
    this.after = "",
  });

  bool get isInsertion => start == end;
}

/// OfferResult is what became of an offered change.
class OfferResult {
  final int? id;
  final bool applied;
  final String? error;
  const OfferResult({this.id, this.applied = false, this.error});
}

class WritingSuggestions extends ChangeNotifier {
  final CreativeAi ai;
  WritingSuggestions(this.ai);

  final List<WritingSuggestion> _items = [];
  int _next = 1;
  bool _disposed = false;

  TextEditingController? get _editor => ai.composer().editor;

  /// documentKey is the document open now.
  String get documentKey {
    var lib = ai.library();
    return "${lib.openFolder}/${lib.openName ?? ""}";
  }

  /// items are those waiting on the document open now.
  List<WritingSuggestion> get items {
    var doc = documentKey;
    return [
      for (var s in _items)
        if (s.document == doc) s
    ];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// offer puts forward replacing [start]..[end] with [replacement]: waiting
  /// to be accepted, or put straight in if the person has chosen that.
  OfferResult offer({
    required int start,
    required int end,
    required String replacement,
    String note = "",
    required String source,
  }) {
    var editor = _editor;
    if (editor == null) {
      return const OfferResult(
          error: "No document is open: open one on the Writing page first.");
    }
    var text = editor.text;
    if (start < 0 || end < start || end > text.length) {
      return OfferResult(
          error: "$start..$end is outside the document (${text.length} "
              "characters long).");
    }
    var original = text.substring(start, end);
    if (original == replacement) {
      return const OfferResult(error: "That would change nothing.");
    }
    if (ai.prefs.applyEdits) {
      _apply(editor, start, end, replacement);
      return const OfferResult(applied: true);
    }
    var s = WritingSuggestion(
      id: _next++,
      start: start,
      end: end,
      original: original,
      replacement: replacement,
      note: note,
      source: source,
      document: documentKey,
      before: text.substring((start - _context).clamp(0, start).toInt(), start),
      after:
          text.substring(end, (end + _context).clamp(end, text.length).toInt()),
    );
    _items.add(s);
    _notify();
    return OfferResult(id: s.id);
  }

  /// accept puts suggestion [id] into the document. Returns why not, or
  /// null.
  String? accept(int id) {
    var s = _items.where((x) => x.id == id).firstOrNull;
    if (s == null) return null;
    var editor = _editor;
    if (editor == null) return "No document is open.";
    if (s.document != documentKey) return "That was for another document.";
    var at = _locate(editor.text, s);
    if (at < 0) {
      return "The text this was for has changed, so it was not put in.";
    }
    _items.remove(s);
    _apply(editor, at, at + s.original.length, s.replacement);
    return null;
  }

  /// _context is how much text either side a suggestion remembers.
  static const int _context = 40;

  /// _locate is where [s]'s original text starts now; -1 if it is gone.
  ///
  /// First with the words either side (where it was, or the nearest place
  /// they all appear together), then -- for a replacement whose neighbours
  /// were rewritten -- by its own text alone, nearest where it was. An
  /// insertion is found only with its neighbours: on its own it is nothing.
  static int _locate(String text, WritingSuggestion s) {
    var whole = s.before + s.original + s.after;
    var at = _nearest(text, whole, s.start - s.before.length);
    if (at >= 0) return at + s.before.length;
    if (s.original.isEmpty) {
      // Either side alone, for an insertion at the very start or end, or
      // beside something since changed.
      if (s.before.isNotEmpty) {
        at = _nearest(text, s.before, s.start - s.before.length);
        if (at >= 0) return at + s.before.length;
      }
      if (s.after.isNotEmpty) return _nearest(text, s.after, s.start);
      return s.start <= text.length ? s.start : -1;
    }
    return _nearest(text, s.original, s.start);
  }

  /// _nearest is where [find] appears in [text] closest to [near], or -1.
  static int _nearest(String text, String find, int near) {
    if (find.isEmpty) return -1;
    var best = -1;
    for (var i = text.indexOf(find); i >= 0; i = text.indexOf(find, i + 1)) {
      if (best < 0 || (i - near).abs() < (best - near).abs()) best = i;
    }
    return best;
  }

  void reject(int id) {
    _items.removeWhere((x) => x.id == id);
    _notify();
  }

  /// acceptAll puts in every suggestion on this document, last first so the
  /// earlier ones' places hold. Returns how many could not be.
  int acceptAll() {
    var mine = items..sort((a, b) => b.start.compareTo(a.start));
    var failed = 0;
    for (var s in mine) {
      if (accept(s.id) != null) failed++;
    }
    return failed;
  }

  void rejectAll() {
    var doc = documentKey;
    _items.removeWhere((x) => x.document == doc);
    _notify();
  }

  /// _apply makes the change, and moves the places of suggestions after it.
  void _apply(TextEditingController editor, int start, int end, String with_) {
    editor.value =
        editor.value.replaced(TextRange(start: start, end: end), with_);
    var shift = with_.length - (end - start);
    for (var s in _items) {
      if (s.start >= end) {
        s.start += shift;
        s.end += shift;
      }
    }
    _notify();
  }

  // ------------------------------------------------------------------------
  // Quick rewrites
  // ------------------------------------------------------------------------

  String? _busy;
  String? _error;

  /// busy is the rewrite under way ("Improve"), or null.
  String? get busy => _busy;

  /// error is why the last rewrite did not work, until the next one.
  String? get error => _error;

  /// target is what a rewrite works on: the selection, or with nothing
  /// selected, the paragraph the cursor is in.
  (int, int)? target() {
    var editor = _editor;
    if (editor == null) return null;
    var text = editor.text;
    var sel = editor.selection;
    if (!sel.isValid) return null;
    if (!sel.isCollapsed) return (sel.start, sel.end);
    if (text.trim().isEmpty) return null;
    var at = sel.baseOffset.clamp(0, text.length).toInt();
    var start = text.lastIndexOf("\n\n", at > 0 ? at - 1 : 0);
    start = start < 0 ? 0 : start + 2;
    var end = text.indexOf("\n\n", at);
    end = end < 0 ? text.length : end;
    if (end <= start) return null;
    return (start, end);
  }

  /// rewrite does [action] (or the person's own [instruction]) to the
  /// target, and offers the result.
  Future<void> rewrite({RewriteAction? action, String? instruction}) async {
    if (_busy != null) return;
    var label = action?.label ?? "Rewrite";
    var ask = action?.instruction ?? (instruction ?? "").trim();
    if (ask.isEmpty) return;
    _error = null;
    var editor = _editor;
    var range = target();
    if (editor == null || range == null) {
      _error = "Select some text, or put the cursor in a paragraph, first.";
      _notify();
      return;
    }
    var (start, end) = range;
    var text = editor.text;
    var passage = text.substring(start, end);
    _busy = label;
    _notify();
    try {
      var exe = await ai.claude();
      if (exe == null) {
        _error = CreativeAi.claudeMissing;
        return;
      }
      var answer = await ClaudeCode.ask(
        exe: exe,
        prompt: rewritePrompt(ask, passage,
            before:
                text.substring((start - 1200).clamp(0, start).toInt(), start),
            after: text.substring(
                end, (end + 600).clamp(end, text.length).toInt())),
        system: rewriteSystemPrompt,
        model: ai.prefs.editModel.alias,
      );
      if (!answer.ok) {
        _error = answer.error;
        return;
      }
      var result = keepEdges(passage, cleanRewrite(answer.text));
      if (result.trim().isEmpty) {
        _error = "Claude sent back nothing to put in.";
        return;
      }
      // The document may have changed while Claude worked: offered against
      // the text it was asked about, found again on accept.
      var now = _editor?.text ?? "";
      var at = now.length >= end && now.substring(start, end) == passage
          ? start
          : now.indexOf(passage);
      if (at < 0) {
        _error = "The text changed while Claude was working; try again.";
        return;
      }
      var r = offer(
          start: at,
          end: at + passage.length,
          replacement: result,
          source: label);
      if (r.error != null) _error = r.error;
    } finally {
      _busy = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// cleanRewrite is a rewrite with what a model sometimes wraps it in taken
/// off: the `<passage>` tags it was given, or a fence.
String cleanRewrite(String text) {
  var t = text;
  var tag = RegExp(r"^\s*<passage>\n?([\s\S]*?)\n?</passage>\s*$");
  var m = tag.firstMatch(t);
  if (m != null) t = m.group(1)!;
  var fence = RegExp(r"^\s*```[a-z]*\n([\s\S]*?)\n```\s*$");
  m = fence.firstMatch(t);
  if (m != null) t = m.group(1)!;
  return t;
}

/// keepEdges gives [rewritten] the white space [original] starts and ends
/// with, so a paragraph's breaks survive its rewrite.
String keepEdges(String original, String rewritten) {
  var lead = RegExp(r"^\s*").firstMatch(original)!.group(0)!;
  var trail = RegExp(r"\s*$").firstMatch(original)!.group(0)!;
  return "$lead${rewritten.trim()}$trail";
}
