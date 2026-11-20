import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';

// writing_style_facts.dart reads a writer's voice out of a document: how long
// their sentences and paragraphs run, how easy it reads, British or American
// spelling, how often they use contractions, how they use headings and
// lists, and a few of their own paragraphs as samples.
//
// Measured, not judged, as a canvas style's facts are: the guide says what
// they mean. Plain text in, so any Markdown document reads the same way.

/// _british and _american are spellings that give a writer away.
const _pairs = [
  ("colour", "color"),
  ("favour", "favor"),
  ("honour", "honor"),
  ("labour", "labor"),
  ("behaviour", "behavior"),
  ("centre", "center"),
  ("metre", "meter"),
  ("theatre", "theater"),
  ("organise", "organize"),
  ("realise", "realize"),
  ("recognise", "recognize"),
  ("analyse", "analyze"),
  ("defence", "defense"),
  ("licence", "license"),
  ("travelled", "traveled"),
  ("cancelled", "canceled"),
  ("programme", "program"),
  ("grey", "gray"),
  ("whilst", "while"),
  ("apologise", "apologize"),
  ("prioritise", "prioritize"),
];

/// writingStyleFactsOf is [text]'s voice, measured.
Map<String, Object?> writingStyleFactsOf(String text) {
  var stats = WritingStats.of(text);
  var lower = text.toLowerCase();
  int count(String word) => RegExp("\\b$word\\w*\\b").allMatches(lower).length;

  var british = 0, american = 0;
  for (var (gb, us) in _pairs) {
    british += count(gb);
    american += count(us);
  }
  var spelling = british == american
      ? "unclear"
      : british > american
          ? "British spelling"
          : "American spelling";

  var contractions =
      RegExp(r"\b\w+['’](s|t|re|ve|ll|d|m)\b", caseSensitive: false)
          .allMatches(text)
          .length;
  var perThousand = stats.words == 0 ? 0.0 : contractions * 1000 / stats.words;

  var lines = text.split("\n");
  var headings = lines.where((l) => RegExp(r"^#{1,6} ").hasMatch(l)).length;
  var bullets =
      lines.where((l) => RegExp(r"^\s*([-*+]|\d+\.) ").hasMatch(l)).length;
  var questions = RegExp(r"\?").allMatches(text).length;
  var exclamations = RegExp(r"!(?!\[)").allMatches(text).length;
  var firstPerson = RegExp(r"\b(i|me|my|we|our|us)\b").allMatches(lower).length;
  var secondPerson = RegExp(r"\b(you|your)\b").allMatches(lower).length;

  return {
    "words": stats.words,
    if (stats.sentences > 0)
      "sentenceWords": (stats.words / stats.sentences * 10).round() / 10,
    if (stats.paragraphs > 0)
      "paragraphWords": (stats.words / stats.paragraphs).round(),
    if (stats.readingEase case var ease?) "readingEaseScore": ease.round(),
    if (stats.readingEaseLabel case var label?) "readingEase": label,
    "spelling": spelling,
    "contractions": perThousand >= 15
        ? "often"
        : perThousand >= 4
            ? "sometimes"
            : "rarely",
    "headings": headings,
    "listItems": bullets,
    "questionsPerThousandWords":
        stats.words == 0 ? 0 : (questions * 1000 / stats.words).round(),
    "exclamationsPerThousandWords":
        stats.words == 0 ? 0 : (exclamations * 1000 / stats.words).round(),
    "voice": firstPerson > secondPerson * 2
        ? "first person"
        : secondPerson > firstPerson * 2
            ? "speaks to the reader"
            : "mixed",
    "samples": _samples(text),
  };
}

/// _samples are up to three of the writer's own prose paragraphs, the
/// longest first, each cut to 700 characters.
List<String> _samples(String text) {
  var paragraphs = [
    for (var p in text.split(RegExp(r"\n\s*\n")))
      if (!RegExp(r"^\s*(#|[-*+] |\d+\. |>|!\[|```|\|)").hasMatch(p) &&
          p.trim().split(RegExp(r"\s+")).length >= 20)
        p.trim()
  ]..sort((a, b) => b.length.compareTo(a.length));
  return [
    for (var p in paragraphs.take(3))
      p.length <= 700 ? p : "${p.substring(0, 697)}…"
  ];
}

/// factualWritingGuide is a guide written from [facts] alone, for a style
/// saved without Claude.
String factualWritingGuide(String name, Map<String, Object?> facts) {
  var b = StringBuffer("# $name\n\nA writing voice, measured from a document "
      "of ${facts["words"]} words.\n\n");
  if (facts["sentenceWords"] != null) {
    b.writeln("- Sentences average ${facts["sentenceWords"]} words; "
        "paragraphs about ${facts["paragraphWords"] ?? "?"}.");
  }
  if (facts["readingEase"] != null) {
    b.writeln("- Reads as ${facts["readingEase"]} "
        "(Flesch ${facts["readingEaseScore"]}).");
  }
  if (facts["spelling"] != "unclear") b.writeln("- ${facts["spelling"]}.");
  b.writeln("- Contractions: ${facts["contractions"]}. Voice: "
      "${facts["voice"]}.");
  if ((facts["headings"] as int? ?? 0) > 0 ||
      (facts["listItems"] as int? ?? 0) > 0) {
    b.writeln("- Uses ${facts["headings"]} headings and "
        "${facts["listItems"]} list items.");
  }
  if (facts["samples"] case List samples when samples.isNotEmpty) {
    b.writeln("\n## In the writer's own words\n");
    for (var s in samples) {
      b.writeln("> ${"$s".replaceAll("\n", "\n> ")}\n");
    }
  }
  return b.toString();
}
