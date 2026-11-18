import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:golib_plugin/definitions.dart';

// brackets.dart is the one counting check that is an error rather than an
// opinion: a bracket that is never closed is not a matter of taste, and the
// reader of the post sees it too.

/// unpairedBracketsId fires on a bracket or quote that is never closed, or a
/// closer with nothing open. `$1` is the mark.
const unpairedBracketsId = "unpaired-brackets";

final Map<String, AnalysisRunner> bracketChecks = {
  unpairedBracketsId: _unpairedBrackets,
};

/// _pairs are the marks that come in twos. The apostrophe is deliberately
/// absent: it is the same character as a single quote, and "don't" would
/// leave every message unbalanced.
const _pairs = {"(": ")", "[": "]", "{": "}"};

/// _skipped are the stretches of a message where an unmatched bracket is
/// somebody's content rather than their mistake: code. A fenced block or an
/// inline span is full of brackets that balance in a language this knows
/// nothing about, and half of one pasted in on purpose is still not a typo
/// the writer wants told about.
final _skipped = RegExp(
  r"```[\s\S]*?```" // a fenced code block
  r"|`[^`\n]*`", // an inline code span
);

/// _emoticons are the faces drawn with a bracket: ":)" is a closing bracket
/// with nothing open, and flagging it would be the single most annoying
/// thing this check does.
///
/// They are not simply skipped, though, which is what was done once. The
/// same two characters end a sum -- "(2889 / 8640 =) 0.34" -- and a page
/// reference -- "(see page 8)" -- and skipping those left the bracket in
/// front of them open for ever and marked. So a bracket in one of these is a
/// maybe: it closes what is open if something is, and is a face if nothing
/// is.
final _emoticons = RegExp(
  r"[:;=8][-~^]?[)(\]\[]" // :) :-( :] =) 8)
  r"|[)(\]\[][-~^]?[:;=8]", // (: ]:
);

/// _unpairedBrackets flags a bracket that is never closed, a closer with
/// nothing open, and an odd number of double quotes.
///
/// A stack rather than a count, so "(]" is caught and so is the *position*
/// of the offender -- a count can say a message is unbalanced but not where,
/// which in a long post is most of the work.
void _unpairedBrackets(AnalysisContext context, AnalysisCheck check) {
  var masked = _maskSkipped(context.text);
  // Where the bracket of each possible emoticon is.
  var maybe = <int>{
    for (var m in _emoticons.allMatches(masked))
      for (var i = m.start; i < m.end; i++)
        if (_pairs.containsKey(masked[i]) || _pairs.containsValue(masked[i])) i,
  };

  var open = <({String mark, int at})>[];
  var quotes = <int>[];
  // How many closers of each kind were taken from a possible emoticon. If a
  // plain closer of that kind turns up later with nothing left to close, the
  // emoticon was a face after all and this is the closer: "(well done :))".
  var borrowed = <String, int>{};
  for (var i = 0; i < masked.length; i++) {
    var c = masked[i];
    var face = maybe.contains(i);
    if (_pairs.containsKey(c)) {
      // An opening bracket in a face opens nothing: ":(" is not waiting for
      // its other half.
      if (!face) open.add((mark: c, at: i));
      continue;
    }
    if (c == '"') {
      quotes.add(i);
      continue;
    }
    if (!_pairs.containsValue(c)) continue;

    var closes = open.isNotEmpty && _pairs[open.last.mark] == c;
    if (face) {
      if (closes) {
        open.removeLast();
        borrowed[c] = (borrowed[c] ?? 0) + 1;
      }
      continue;
    }
    if (closes) {
      open.removeLast();
      continue;
    }
    if ((borrowed[c] ?? 0) > 0) {
      borrowed[c] = borrowed[c]! - 1;
      continue;
    }
    // A closer with nothing open, or one that does not match what is.
    context.report(check, i, i + 1, subject: c);
  }

  for (var unclosed in open) {
    context.report(check, unclosed.at, unclosed.at + 1, subject: unclosed.mark);
  }
  // Quotes have no direction, so the only thing that can be said is that
  // there is an odd number of them -- and the last is the one to point at,
  // since everything before it paired up.
  if (quotes.length.isOdd) {
    context.report(check, quotes.last, quotes.last + 1, subject: '"');
  }
}

/// _maskSkipped replaces code with spaces, keeping the text the same length
/// so every offset still points where it did.
String _maskSkipped(String text) {
  var masked = text.split("");
  for (var m in _skipped.allMatches(text)) {
    for (var i = m.start; i < m.end; i++) {
      masked[i] = " ";
    }
  }
  return masked.join();
}
