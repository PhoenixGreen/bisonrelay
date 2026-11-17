import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';

// chart_words.dart is a chart's live words: anything in braces in its
// title, description or a note is worked out from the numbers it draws,
// and changes with them: "{leader by Points} top on {most Points}" reads
// "Man City top on 9". The words: {leader by X}, {last by X} (who has the
// most and least of series X), {most X}, {least X}, {average of X}, {total
// of X}, {X of NAME}, {date} (the date shown) and {count} (how many shown).

/// liveWords is [text] with every {word} worked out from [data]; a word it
/// cannot work out is left as {?word}, so the mistake shows.
String liveWords(ChartData data, String text) {
  if (!text.contains("{")) return text;
  return text.replaceAllMapped(RegExp(r"\{([^}]*)\}"), (m) {
    var word = m[1]!.trim();
    return wordFor(data, word) ?? "{?$word}";
  });
}

/// unknownWords is the {words} in [text] that [data] cannot work out.
List<String> unknownWords(ChartData data, String text) => [
      for (var m in RegExp(r"\{([^}]*)\}").allMatches(text))
        if (wordFor(data, m[1]!.trim()) == null) m[1]!.trim()
    ];

/// wordFor is what one word says of [data], or null.
String? wordFor(ChartData data, String word) {
  var low = word.toLowerCase();
  // The marks it shows: not a gap between groups.
  var shown = [
    for (var (i, c) in data.categories.indexed)
      if (c != "…") i
  ];
  int? series(String name) {
    var n = name.trim().toLowerCase();
    for (var (i, s) in data.series.indexed) {
      if (s.name.trim().toLowerCase() == n) return i;
    }
    return null;
  }

  // Whole numbers stay whole, even part-way between two dates while the
  // chart plays (ChartData.whole is kept from where it set off).
  String number(int s, double v) {
    var whole = s < data.whole.length
        ? data.whole[s]
        : data.series[s].values.every((x) => x.isNaN || x == x.roundToDouble());
    return whole
        ? "${v.round()}"
        : v.toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "");
  }

  if (low == "date") return data.at.isEmpty ? null : data.at;
  if (low == "count") return "${shown.length}";

  RegExpMatch? m;
  if ((m = RegExp(r"^(average|total) of (.+)$").firstMatch(low)) != null) {
    var s = series(m![2]!);
    if (s == null) return null;
    var v = [
      for (var i in shown)
        if (!data.valueAt(s, i).isNaN) data.valueAt(s, i)
    ];
    if (v.isEmpty) return null;
    var sum = v.fold(0.0, (a, b) => a + b);
    return m[1] == "total"
        ? number(s, sum)
        : (sum / v.length).toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "");
  }
  if ((m = RegExp(r"^(most|least) (.+)$").firstMatch(low)) != null) {
    var s = series(m![2]!);
    if (s == null) return null;
    var v = [
      for (var i in shown)
        if (!data.valueAt(s, i).isNaN) data.valueAt(s, i)
    ];
    if (v.isEmpty) return null;
    return number(
        s,
        m[1] == "most"
            ? v.reduce((a, b) => a > b ? a : b)
            : v.reduce((a, b) => a < b ? a : b));
  }
  if ((m = RegExp(r"^(leader|last) by (.+)$").firstMatch(low)) != null) {
    var s = series(m![2]!);
    if (s == null) return null;
    int? best;
    for (var i in shown) {
      var v = data.valueAt(s, i);
      if (v.isNaN) continue;
      // Ties go to the first, as the sheet has them.
      if (best == null ||
          (m[1] == "leader"
              ? v > data.valueAt(s, best)
              : v <= data.valueAt(s, best))) {
        best = i;
      }
    }
    return best == null ? null : data.categories[best];
  }
  if ((m = RegExp(r"^(.+?) of (.+)$").firstMatch(word)) != null) {
    var s = series(m![1]!);
    if (s == null) return null;
    var who = m[2]!.trim().toLowerCase();
    for (var i in shown) {
      if (data.categories[i].trim().toLowerCase() == who) {
        var v = data.valueAt(s, i);
        return v.isNaN ? null : number(s, v);
      }
    }
    return null;
  }
  return null;
}

/// wordChoices are words to offer for a chart showing [data]: as (what the
/// button says, what it puts in).
List<(String, String)> wordChoices(ChartData data) {
  if (data.series.isEmpty) return const [];
  var x = data.series.first.name;
  var who = data.categories.firstWhere((c) => c != "…", orElse: () => "");
  return [
    if (data.at.isNotEmpty) ("Date", "{date}"),
    ("Leader", "{leader by $x}"),
    ("Most $x", "{most $x}"),
    ("Average", "{average of $x}"),
    ("Total", "{total of $x}"),
    ("Last", "{last by $x}"),
    if (who.isNotEmpty) ("$x of $who", "{$x of $who}"),
    ("How many", "{count}"),
  ];
}
