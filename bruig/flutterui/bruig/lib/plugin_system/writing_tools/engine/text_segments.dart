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

/// notProse matches the stretches of a message that are not writing: links,
/// addresses, file names and paths, embeds and the other `--name[...]--`
/// blocks, HTML tags, and code.
///
/// None of it is the writer's spelling or grammar to correct. A link is
/// spelled the way its site spells it, an embed is a line of settings, and a
/// file is called what it is called -- and all of them are full of exactly
/// what the checks look for: words no dictionary has, full stops with no
/// space after them, commas against letters. Marking "https" as a
/// misspelling teaches nobody anything.
///
/// A link's *text* is still prose, and still checked: in
/// `[the relase notes](https://...)` the address is skipped and the
/// misspelling in front of it is not.
final RegExp notProse = RegExp(
  // Code: a fenced block, closed or still being typed, and an inline span.
  // (Not "$" for the end: with multiLine that is the end of the line, and a
  // block would stop at its own first line.)
  r"```[\s\S]*?(?:```|(?![\s\S]))"
  r"|`[^`\n]*`"
  // --embed[...]-- and its kin, with the one level of brackets an embed's
  // own "data=[content id]" puts inside it; then one still being typed, to
  // the end of its line; then the bare ones, --form-- and --/grid--.
  r"|--/?[A-Za-z]+\[(?:[^\[\]\n]|\[[^\]\n]*\])*\]--"
  r"|--/?[A-Za-z]+\[[^\n]*"
  r"|--/?[A-Za-z]+--"
  // An HTML tag, or an address in angle brackets.
  r"|<[A-Za-z/!][^<>\n]*>"
  // Where a markdown link or picture points: the bracketed part after "]".
  r"|(?<=\])\([^()\n]*(?:\([^()\n]*\)[^()\n]*)?\)"
  // And a reference-style definition, "[id]: address".
  r"|(?<=^\[[^\]\n]{1,60}\]:)[ \t]*\S+"
  // Addresses: anything with a scheme, www., an email, a bare domain.
  r"|\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\x22]*[^\s<>\x22.,;:!?)\]'’”]"
  r"|\bmailto:[^\s<>]+"
  r"|\bwww\.[^\s<>\x22]*[^\s<>\x22.,;:!?)\]'’”]"
  r"|[\w.+-]+@[\w-]+(?:\.[\w-]+)+"
  r"|\b(?:[A-Za-z0-9-]+\.)+(?:com|org|net|edu|gov|io|dev|app|info|xyz|co|uk|us|de|fr|ca|au|me|tv|ai|gg|sh|ly|cc|onion)\b"
  r"(?:[/:?#][^\s<>\x22]*[^\s<>\x22.,;:!?)\]'’”])?"
  // Paths: from the root, the home directory or here; a Windows drive; and
  // anything with two or more slashes in it. "and/or" has one.
  r"|(?<![\w/])(?:~|\.{1,2})?/(?:[\w.@%+-]+/)*[\w.@%+-]+"
  r"|\b[A-Za-z]:\\[^\s]+"
  r"|\b[\w.@%+-]+(?:/[\w.@%+-]+){2,}"
  // A file by name.
  r"|\b[\w-]+(?:\.[\w-]+)*\.(?:dart|go|md|txt|pdf|png|jpe?g|gif|svg|webp|"
  r"json|ya?ml|toml|html?|css|js|ts|py|rs|sh|zip|gz|tar|mp3|mp4|mov|wav|csv|"
  r"xlsx?|docx?|pptx?|exe|dmg|apk|wasm|log|conf|cfg|ini|lock|sql|xml|cpp|"
  r"java|kt|swift|rb|php|epub|bin|iso)\b"
  // A handle or a tag.
  r"|(?<![\w/&])[@#][A-Za-z_][\w-]*",
  multiLine: true,
);

/// Span is a stretch of text by its two ends.
typedef Span = ({int start, int end});

/// The stretches of [text] that are not prose, in order.
List<Span> notProseSpans(String text) => [
      for (var m in notProse.allMatches(text))
        if (m.end > m.start) (start: m.start, end: m.end),
    ];

/// Whether a finding over [start] to [end] is about something in [spans]
/// rather than about the writing: it lies inside one, or one of its ends
/// does.
///
/// A finding that merely *contains* a span is left alone. A sentence that is
/// too long is too long whether or not there is a link in the middle of it.
bool inNotProse(List<Span> spans, int start, int end) {
  if (spans.isEmpty || end <= start) return false;
  bool inside(int at) {
    // The last span starting at or before [at], if it reaches past it.
    var lo = 0, hi = spans.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (spans[mid].start <= at) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo > 0 && at < spans[lo - 1].end;
  }

  return inside(start) || inside(end - 1);
}
