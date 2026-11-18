import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:bruig/plugin_system/writing_tools/engine/writing_issue.dart';
import 'package:golib_plugin/definitions.dart';

// consistency.dart is the checks where nothing is wrong and two things
// disagree: two spellings of one word in one message, and two kinds of
// apostrophe inside its words.
//
// Both are suggestions and both refuse to take a side. Choosing between
// "colour" and "color" would be choosing between British and American English
// on the writer's behalf, so every occurrence of both is marked and the
// message names the other one, leaving the decision where it belongs.

/// spellingVariantInconsistencyId fires when both spellings of one of the
/// check's `values` pairs appear in a message. `$1` is the spelling flagged,
/// `$2` the other one.
const spellingVariantInconsistencyId = "spelling-variant-inconsistency";

/// apostropheInconsistencyId fires when straight and curly apostrophes are
/// both used inside words. `$1` is the odd one out.
const apostropheInconsistencyId = "apostrophe-inconsistency";

final Map<String, AnalysisRunner> consistencyChecks = {
  spellingVariantInconsistencyId: _spellingVariants,
  apostropheInconsistencyId: _apostropheConsistency,
};

/// _spellingVariants flags both spellings when a message uses two spellings
/// of one word.
void _spellingVariants(AnalysisContext context, AnalysisCheck check) {
  var text = context.text;
  // Asked of the document's words, gathered once, rather than by searching
  // the document for each spelling in turn. There are hundreds of pairs and
  // nearly none of them is in any given post, and two searches of the whole
  // text for each had become half of what a keystroke in a long post cost.
  var words = context.words;
  String? lower;
  bool present(String spelling) => _plainWord.hasMatch(spelling)
      ? words.contains(spelling)
      // A spelling with a hyphen or a space in it is not one of the
      // document's words, and is looked for the slow way.
      : (lower ??= text.toLowerCase()).contains(spelling);
  for (var pair in check.values) {
    var parts = pair.split("|");
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) continue;
    if (!present(parts[0]) || !present(parts[1])) continue;

    var first = _occurrences(text, parts[0]);
    var second = _occurrences(text, parts[1]);
    if (first.isEmpty || second.isEmpty) continue;
    for (var (match, other) in [
      ...first.map((m) => (m, parts[1])),
      ...second.map((m) => (m, parts[0])),
    ]) {
      var found = match.group(0)!;
      context.report(
        check,
        match.start,
        match.end,
        subject: found,
        detail: other,
        // Offered as a correction even though nothing here is wrong: taking
        // it is how you settle on one spelling, and it is the only action
        // there is to take.
        suggestions: [matchCase(found, other)],
      );
    }
  }
}

final _plainWord = RegExp(r"^[a-z]+$");

/// _occurrences finds whole-word appearances of [word], case-insensitively.
List<RegExpMatch> _occurrences(String text, String word) =>
    RegExp("\\b${RegExp.escape(word)}\\b", caseSensitive: false)
        .allMatches(text)
        .toList();

/// _wordApostrophe matches an apostrophe with a letter on both sides.
///
/// Word-internal only, and that restriction is the whole rule. A straight
/// quote around a quotation is not an apostrophe, and counting those would
/// report every message that quotes something as inconsistent.
final _wordApostrophe = RegExp("(?<=[A-Za-z])(['’])(?=[A-Za-z])");

/// _apostropheConsistency flags the minority apostrophe when a message uses
/// both the straight one and the curly one inside words.
///
/// Neither is wrong, which is why this is a suggestion. Both together is
/// what text pasted from two places looks like.
void _apostropheConsistency(AnalysisContext context, AnalysisCheck check) {
  var text = context.text;
  var straight = <int>[], curly = <int>[];
  for (var m in _wordApostrophe.allMatches(text)) {
    (m.group(1) == "'" ? straight : curly).add(m.start);
  }
  if (straight.isEmpty || curly.isEmpty) return;

  // On a tie the curly one is the odd one out: a field that substitutes
  // apostrophes produces those, so it is the one that arrived from somewhere
  // else.
  var curlyLoses = curly.length <= straight.length;
  var odd = curlyLoses ? curly : straight;
  var wanted = curlyLoses ? "'" : "’";
  for (var at in odd) {
    context.report(check, at, at + 1,
        subject: text[at], detail: wanted, suggestions: [wanted]);
  }
}
