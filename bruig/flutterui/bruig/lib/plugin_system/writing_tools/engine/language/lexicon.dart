// lexicon.dart is what the checker knows about words beyond their spelling:
// what each can be in a sentence, how often, and the forms a base word takes.
//
// It is the difference between rules about particular words and rules about
// grammar. "He go to school" is wrong because of what "he" and "go" are, not
// because of which words they happen to be, and a checker that only has the
// dictionary's yes-or-no cannot say so. The data is the provider's, like the
// dictionary; reading it is this file.

/// Tags are the parts of speech, as small numbers so a word's readings fit in
/// one int. The names are the Penn Treebank's, which the provider's rules are
/// written in.
abstract final class Tags {
  static const names = [
    "NN", "NNS", "NNP", //
    "VB", "VBP", "VBZ", "VBD", "VBN", "VBG", //
    "JJ", "JJR", "JJS", "RB", "RBR", "RBS", //
    "DT", "PDT", "CD", "EX", "IN", "TO", "CC", "MD", "UH", "RP", //
    "PRP", "PRP\$", "WP", "WDT", "WP\$", "WRB", "POS", //
    "COMMA", "STOP", "PUNCT", "SYM", "BOUND",
  ];

  static final Map<String, int> _ids = {
    for (var i = 0; i < names.length; i++) names[i]: i,
  };

  static final int nn = _ids["NN"]!;
  static final int nns = _ids["NNS"]!;
  static final int nnp = _ids["NNP"]!;
  static final int vb = _ids["VB"]!;
  static final int vbp = _ids["VBP"]!;
  static final int vbz = _ids["VBZ"]!;
  static final int vbd = _ids["VBD"]!;
  static final int vbn = _ids["VBN"]!;
  static final int vbg = _ids["VBG"]!;
  static final int jj = _ids["JJ"]!;
  static final int rb = _ids["RB"]!;
  static final int cd = _ids["CD"]!;
  static final int pos = _ids["POS"]!;
  static final int comma = _ids["COMMA"]!;
  static final int stop = _ids["STOP"]!;
  static final int punct = _ids["PUNCT"]!;
  static final int sym = _ids["SYM"]!;
  static final int bound = _ids["BOUND"]!;

  /// The tag called [name], or -1.
  static int id(String name) => _ids[name] ?? -1;

  /// Every tag whose name starts with [prefix], as a mask: "VB" is all six
  /// verb forms.
  static int maskOfPrefix(String prefix) {
    var mask = 0;
    for (var i = 0; i < names.length; i++) {
      if (names[i].startsWith(prefix)) mask |= 1 << i;
    }
    return mask;
  }
}

/// Reading is one thing a word can be.
class Reading {
  final int tag;

  /// How much of the word's use this reading is, in percent. Zero is a
  /// reading that exists and is rare.
  final int weight;

  /// The base form, which is the word itself unless this is an inflection.
  final String lemma;
  const Reading(this.tag, this.weight, this.lemma);
}

/// LexEntry is everything known about one written form.
class LexEntry {
  final List<Reading> readings;

  /// The forms this word takes when it is a base form, by tag.
  final Map<int, String> forms;

  /// Every reading, as a mask.
  final int all;

  /// The readings a rule should count as possible -- everything but the
  /// curiosities.
  final int likely;

  LexEntry(this.readings, this.forms)
      : all = readings.fold(0, (m, r) => m | (1 << r.tag)),
        likely = _likely(readings);

  static int _likely(List<Reading> readings) {
    var mask = 0;
    for (var r in readings) {
      if (r.weight >= 2) mask |= 1 << r.tag;
    }
    // A word whose readings are all rare is still something.
    return mask == 0 && readings.isNotEmpty ? 1 << readings.first.tag : mask;
  }

  /// The share of this word's use that falls under [mask], in percent.
  int weightOf(int mask) {
    var sum = 0;
    for (var r in readings) {
      if (mask & (1 << r.tag) != 0) sum += r.weight;
    }
    return sum;
  }

  /// The base form of the reading tagged [tag], or null.
  String? lemmaFor(int tag) {
    for (var r in readings) {
      if (r.tag == tag) return r.lemma;
    }
    return null;
  }

  /// Whether any reading of this word has [lemma] as its base form.
  bool hasLemma(String lemma, [int mask = -1]) {
    for (var r in readings) {
      if (r.lemma == lemma && mask & (1 << r.tag) != 0) return true;
    }
    return false;
  }
}

/// Lexicon answers for a word from the provider's list.
///
/// The list is kept as the text it arrived in and searched in place. It is
/// ninety thousand lines, and turning all of it into objects to look up the
/// two hundred words of a post would cost more time and memory than every
/// lookup put together; a line is parsed when a word is first asked about and
/// kept after that.
class Lexicon {
  final String _text;
  final List<int> _lines = [];
  final Map<String, LexEntry?> _cache = {};

  Lexicon(this._text) {
    var at = 0;
    while (at < _text.length) {
      var end = _text.indexOf("\n", at);
      if (end < 0) end = _text.length;
      if (end > at && _text.codeUnitAt(at) != 0x23) _lines.add(at);
      at = end + 1;
    }
  }

  bool get isEmpty => _lines.isEmpty;

  /// Everything known about [word], which must already be lower case.
  LexEntry? lookup(String word) {
    if (_cache.containsKey(word)) return _cache[word];
    var entry = _find(word);
    _cache[word] = entry;
    return entry;
  }

  /// The form of [lemma] tagged [tag] -- "go" as a VBD is "went" -- or null
  /// where the word has no such form or is not known.
  String? inflect(String lemma, int tag) {
    var entry = lookup(lemma);
    if (entry == null) return null;
    if (tag == Tags.vb || tag == Tags.nn || tag == Tags.jj) {
      return entry.all & (1 << tag) != 0 ? lemma : null;
    }
    var form = entry.forms[tag];
    if (form != null) return form;
    // A form spelled like the base is not listed apart from it: "run" is
    // its own participle, and "put" its own past.
    if (entry.all & (1 << tag) != 0) return lemma;
    // "are" is the only verb with a present form of its own; for the rest
    // the present is the base.
    if (tag == Tags.vbp) return entry.all & (1 << Tags.vb) != 0 ? lemma : null;
    return null;
  }

  LexEntry? _find(String word) {
    var lo = 0, hi = _lines.length - 1;
    while (lo <= hi) {
      var mid = (lo + hi) >> 1;
      var order = _compare(_lines[mid], word);
      if (order == 0) return _parse(_lines[mid] + word.length + 1);
      if (order < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// Orders the word on the line at [at] against [word].
  int _compare(int at, String word) {
    for (var i = 0;; i++) {
      var c = at + i < _text.length ? _text.codeUnitAt(at + i) : 0x09;
      var lineDone = c == 0x09 || c == 0x0a;
      if (i == word.length) return lineDone ? 0 : 1;
      if (lineDone) return -1;
      var d = c - word.codeUnitAt(i);
      if (d != 0) return d;
    }
  }

  LexEntry _parse(int at) {
    var end = _text.indexOf("\n", at);
    if (end < 0) end = _text.length;
    var columns = _text.substring(at, end).split("\t");
    var word = _text.substring(_text.lastIndexOf("\n", at - 1) + 1, at - 1);
    var readings = <Reading>[];
    for (var spec in columns[0].split(" ")) {
      var parts = spec.split(":");
      if (parts.length < 2) continue;
      var tag = Tags.id(parts[0]);
      if (tag < 0) continue;
      readings.add(Reading(tag, int.tryParse(parts[1]) ?? 0,
          parts.length > 2 ? parts[2] : word));
    }
    var forms = <int, String>{};
    if (columns.length > 1) {
      for (var spec in columns[1].split(" ")) {
        var eq = spec.indexOf("=");
        if (eq <= 0) continue;
        var tag = Tags.id(spec.substring(0, eq));
        if (tag >= 0) forms[tag] = spec.substring(eq + 1);
      }
    }
    return LexEntry(readings, forms);
  }
}
