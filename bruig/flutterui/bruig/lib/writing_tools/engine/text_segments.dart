// text_segments.dart cuts a message into the pieces the checks that count
// need: words, sentences and paragraphs, each remembering where it started.
//
// One copy of these, deliberately. The counting checks and the document
// statistics both segment the same text in the same way, and for a while they
// each carried their own regexes -- the same approximation written out twice,
// with a comment in one pointing at the other. Two definitions of "sentence"
// is one more than a message has.
//
// Where the two genuinely differ, they differ in the pattern they pass rather
// than in the splitting: [wordForChecking] leaves digits out because a
// dictionary cannot rule on "3pm", and [wordForCounting] includes them
// because "3pm" is plainly a word when you are counting words.

/// sentenceEnd splits text into sentences: a full stop, question mark or
/// exclamation followed by whitespace, or a line break.
///
/// Approximate on purpose. It splits "e.g." and "Mr. Smith" in the wrong
/// place, and getting that right needs an abbreviation list that would then
/// be wrong about some other abbreviation. Everything built on it only ever
/// counts, so a wrongly split sentence costs a slightly wrong number rather
/// than a wrongly placed underline.
final RegExp sentenceEnd = RegExp(r"(?<=[.!?])\s+|\n+");

/// paragraphBreak is a blank line, which is what separates paragraphs in the
/// plain text these composers hold.
final RegExp paragraphBreak = RegExp(r"\n\s*\n");

/// wordForChecking matches a word the writing checks reason about: letters
/// and apostrophes, so "don't" is one word rather than two. The typographic
/// apostrophes are included because a field that substitutes them would
/// otherwise split every contraction in the message.
final RegExp wordForChecking = RegExp("[A-Za-z][A-Za-z'’ʼ‘]*");

/// wordForCounting matches a word for the document statistics: letters,
/// digits and apostrophes, so "don't" and "3pm" are each one word.
final RegExp wordForCounting = RegExp(r"[A-Za-z0-9][A-Za-z0-9']*");

/// TextSegment is a stretch of the original text together with where it
/// started, so an issue found inside it can be reported at the right offset.
class TextSegment {
  final String text;
  final int start;
  int get end => start + text.length;
  const TextSegment(this.text, this.start);
}

/// splitKeepingOffsets cuts [text] on [separator], keeping each piece's offset
/// and dropping the ones that are only whitespace.
List<TextSegment> splitKeepingOffsets(String text, RegExp separator) {
  var out = <TextSegment>[];
  var at = 0;
  for (var m in separator.allMatches(text)) {
    var piece = text.substring(at, m.start);
    if (piece.trim().isNotEmpty) out.add(TextSegment(piece, at));
    at = m.end;
  }
  var last = text.substring(at);
  if (last.trim().isNotEmpty) out.add(TextSegment(last, at));
  return out;
}

/// countSegments is [splitKeepingOffsets] for a caller that wants only how
/// many there were, without building the list.
int countSegments(String text, RegExp separator) {
  var n = 0;
  var at = 0;
  for (var m in separator.allMatches(text)) {
    if (text.substring(at, m.start).trim().isNotEmpty) n++;
    at = m.end;
  }
  if (text.substring(at).trim().isNotEmpty) n++;
  return n;
}
