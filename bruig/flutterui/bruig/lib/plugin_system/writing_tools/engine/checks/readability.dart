import 'package:bruig/plugin_system/writing_tools/engine/analysis.dart';
import 'package:bruig/plugin_system/writing_tools/engine/text_segments.dart';
import 'package:golib_plugin/definitions.dart';

// readability.dart is about how hard a sentence is to follow rather than
// whether it is correct.
//
// One check so far. It has a file of its own because the family is a real one
// -- paragraph length and nesting depth belong beside it -- and because the
// alternative was leaving it in a general "miscellaneous" file, which is the
// file every later check would also land in.

/// longSentenceId fires on a sentence of the check's threshold or more words.
/// `$2` is the length.
const longSentenceId = "long-sentence";

final Map<String, AnalysisRunner> readabilityChecks = {
  longSentenceId: _longSentences,
};

/// _longSentences flags a sentence past the threshold, underlining the whole
/// of it.
void _longSentences(AnalysisContext context, AnalysisCheck check) {
  var threshold = check.threshold > 0 ? check.threshold : 30;
  for (var sentence in context.sentences) {
    var words = wordForChecking.allMatches(sentence.text).length;
    if (words < threshold) continue;
    context.report(check, sentence.start, sentence.end, detail: "$words");
  }
}
