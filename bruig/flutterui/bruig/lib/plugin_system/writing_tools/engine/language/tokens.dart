import 'dart:math' as math;

import 'package:bruig/plugin_system/writing_tools/engine/language/lexicon.dart';
import 'package:bruig/plugin_system/writing_tools/engine/text_segments.dart';

// tokens.dart cuts a paragraph into sentences and a sentence into words, and
// says what each word is.
//
// Everything the grammar checks reason about starts here. A regular
// expression sees characters; these see "a pronoun, then a verb in its base
// form, then a full stop", which is the level a rule of grammar is stated at.

enum TokenKind {
  word,
  number,
  punctuation,

  /// Something that is not prose and is not to be read as it: a link, an
  /// address, a handle, a run of code.
  other,
}

/// Token is one word, number or mark of a sentence.
class Token {
  /// Where it is in the text that was tokenized.
  final int start;
  final int end;

  /// As written.
  final String text;

  /// Lower-cased, with a typographic apostrophe made plain -- what the
  /// lexicon and the rules are keyed by.
  final String lower;

  final TokenKind kind;

  /// Whether whitespace came before it. "dog 's" and "dog's" differ in this
  /// alone.
  final bool spaceBefore;

  /// What the lexicon has for it, or null for a word it does not know.
  final LexEntry? entry;

  /// The readings a rule may count as possible, as a mask of [Tags].
  int likely = 0;

  /// The reading chosen for this sentence.
  int tag = 0;

  /// The first word of its sentence, where a capital says nothing.
  bool first = false;

  /// The first thing in its sentence -- so not the first word after a
  /// bullet or a number, which is a list item's and need not be capitalised,
  /// nor after an opening quote, where it is as often a fragment being
  /// quoted.
  bool opening = false;

  /// Whether a clause starts here: it is the sentence's first word, or
  /// follows a comma or one of the words that join clauses. A pronoun here
  /// is a subject -- which "you" and "it" otherwise need not be.
  bool clauseStart = false;

  Token(this.start, this.end, this.text, this.lower, this.kind,
      this.spaceBefore, this.entry);

  bool get isWord => kind == TokenKind.word;

  /// Whether the lexicon knows the word. An unknown word still gets a guess
  /// at what it is, and a rule that needs to be sure asks this first.
  bool get known => entry != null;

  bool get capitalised {
    var c = text.codeUnitAt(0);
    return c >= 0x41 && c <= 0x5a;
  }

  bool get allCaps => text.length > 1 && text == text.toUpperCase() && isWord;

  /// Whether a capital here means something: it is not the sentence's first
  /// word, so the writer chose it.
  bool get properLooking => capitalised && !first;

  bool canBe(int mask) => likely & mask != 0;
  bool onlyBe(int mask) => likely != 0 && likely & ~mask == 0;
  bool isTagged(int mask) => (1 << tag) & mask != 0;

  /// The base form under the chosen reading, or the word itself.
  String get lemma => entry?.lemmaFor(tag) ?? lower;

  @override
  String toString() => "$text/${Tags.names[tag]}";
}

/// Sentence is a run of tokens that ends where the writer stopped.
class Sentence {
  final List<Token> tokens;
  Sentence(this.tokens);
  int get start => tokens.first.start;
  int get end => tokens.last.end;
}

const _apostrophes = "'’ʼ‘";

bool _isLetter(int c) =>
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0xc0 && c <= 0x24f && c != 0xd7 && c != 0xf7) ||
    // A soft hyphen is where a word may be broken, and is not a break.
    c == 0xad;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0xa0;
bool _isApostrophe(int c) =>
    c == 0x27 || c == 0x2019 || c == 0x2bc || c == 0x2018;

/// The ends that are a second word rather than part of the first: "they're"
/// is "they" and "are".
const _clitics = {"'s", "'re", "'ve", "'ll", "'d", "'m"};

/// Abbreviations whose full stop is theirs and does not end a sentence.
const _abbreviations = {
  "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "eg", "ie", //
  "inc", "ltd", "co", "corp", "no", "fig", "approx", "dept", "est", "gen",
  "gov", "sen", "rep", "col", "capt", "lt", "sgt", "rev", "hon", "mt", "ave",
  "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov",
  "dec", "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat",
  "sun", "cf", "al", "ca", "vol", "pp", "ed", "eds", "nos",
};

/// The words a clause can start after.
const _joiners = {
  "and", "but", "or", "nor", "so", "yet", "because", "when", "whenever", //
  "while", "if", "unless", "although", "though", "since", "until", "whereas",
  "once", "after", "before", "then", "that",
};

/// The marks a clause does not start after: the ones that close something.
const _closers = {")", "]", "”", "’", "'", '"', "."};

/// Tokenizer turns text into tagged sentences, using one [Lexicon].
class Tokenizer {
  final Lexicon lexicon;

  /// How much likelier one reading is after another, as the provider counted
  /// it: [_lift] of a pair is the log of how many times more often the second
  /// tag follows the first than it turns up anywhere.
  final List<double> _lift;
  static final int _n = Tags.names.length;

  Tokenizer(this.lexicon, [String transitions = ""])
      : _lift = List.filled(_n * _n, 0.0) {
    for (var line in transitions.split("\n")) {
      var parts = line.split(" ");
      if (parts.length != 3) continue;
      var a = Tags.id(parts[0]), b = Tags.id(parts[1]);
      var v = double.tryParse(parts[2]);
      if (a < 0 || b < 0 || v == null) continue;
      _lift[a * _n + b] = v;
    }
  }

  /// The sentences of [text], each word tagged.
  List<Sentence> sentences(String text) {
    var tokens = _tokens(text);
    var out = <Sentence>[];
    var current = <Token>[];
    void close() {
      if (current.isEmpty) return;
      _tag(current);
      out.add(Sentence(current));
      current = <Token>[];
    }

    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i];
      // A line break ends a sentence whether or not anything else did: a
      // heading, a list item and a signature are each their own thing.
      if (current.isNotEmpty &&
          text.substring(current.last.end, t.start).contains("\n")) {
        close();
      }
      current.add(t);
      if (_endsSentence(tokens, i)) {
        // The marks that close what the sentence opened go with it.
        while (i + 1 < tokens.length &&
            !tokens[i + 1].spaceBefore &&
            const {'"', "'", ")", "]", "”", "’"}.contains(tokens[i + 1].text)) {
          current.add(tokens[++i]);
        }
        close();
      }
    }
    close();
    return out;
  }

  bool _endsSentence(List<Token> tokens, int i) {
    var t = tokens[i];
    if (t.kind != TokenKind.punctuation) return false;
    var c = t.text.codeUnitAt(0);
    if (c != 0x2e && c != 0x21 && c != 0x3f && c != 0x2026) return false;
    if (i + 1 >= tokens.length) return true;
    var next = tokens[i + 1];
    // Closing marks first, then whatever follows them.
    var j = i + 1;
    while (j < tokens.length &&
        !tokens[j].spaceBefore &&
        const {'"', "'", ")", "]", "”", "’"}.contains(tokens[j].text)) {
      j++;
    }
    if (j >= tokens.length) return true;
    next = tokens[j];
    if (!next.spaceBefore) return false;
    // "Really?" she asked. The quotation ended; the sentence did not.
    if (j > i + 1 && next.isWord && !next.capitalised) return false;
    if (c != 0x2e && c != 0x2026) return true;
    // An ellipsis trails off as often as it stops...
    if (t.text.length > 1 || c == 0x2026) return next.capitalised;

    // A full stop. It ends the sentence unless it belongs to the word before
    // it, and then only if what follows could not be a new sentence.
    if (i == 0 || t.spaceBefore) return true;
    var before = tokens[i - 1];
    var abbreviation = _abbreviations.contains(before.lower) ||
        (before.isWord && before.text.length == 1 && before.capitalised);
    if (abbreviation) return false;
    if (before.lower.contains(".")) {
      // "U.S." and "a.m." end sentences too. Taken as an end only where the
      // next word is an ordinary one given a capital for the occasion.
      if (!next.capitalised) return false;
      var entry = lexicon.lookup(next.lower);
      return entry != null && entry.likely & (1 << Tags.nnp) == 0;
    }
    // "the file is main.dart and" has no sentence end in it.
    return next.capitalised || !next.isWord;
  }

  List<Token> _tokens(String text) {
    var out = <Token>[];
    // What is not prose is one token each, so that a rule sees "a link"
    // where the link is and not the pieces of its address.
    var skip = notProse.allMatches(text).toList();
    var skipAt = 0;
    var i = 0;
    var space = true;
    while (i < text.length) {
      var c = text.codeUnitAt(i);
      if (_isSpace(c)) {
        space = true;
        i++;
        continue;
      }
      while (skipAt < skip.length && skip[skipAt].end <= i) {
        skipAt++;
      }
      if (skipAt < skip.length && skip[skipAt].start == i) {
        var m = skip[skipAt];
        out.add(Token(i, m.end, m.group(0)!, m.group(0)!.toLowerCase(),
            TokenKind.other, space, null));
        i = m.end;
        space = false;
        continue;
      }
      if (_isLetter(c)) {
        i = _word(text, i, space, out);
      } else if (_isDigit(c)) {
        var end = i + 1;
        while (end < text.length) {
          var d = text.codeUnitAt(end);
          if (_isDigit(d) || _isLetter(d)) {
            end++;
          } else if ((d == 0x2e || d == 0x2c || d == 0x3a || d == 0x2f) &&
              end + 1 < text.length &&
              _isDigit(text.codeUnitAt(end + 1))) {
            end++;
          } else {
            break;
          }
        }
        var s = text.substring(i, end);
        out.add(
            Token(i, end, s, s.toLowerCase(), TokenKind.number, space, null));
        i = end;
      } else {
        // A mark, and any straight repeats of it: "..." and "!!" are one.
        var end = i + 1;
        while (end < text.length && text.codeUnitAt(end) == c) {
          end++;
        }
        var s = text.substring(i, end);
        out.add(Token(i, end, s, s, TokenKind.punctuation, space, null));
        i = end;
      }
      space = false;
    }
    return out;
  }

  /// Reads the word at [i] into [out] -- as two tokens where it is two words
  /// written as one -- and returns where it ended.
  int _word(String text, int i, bool space, List<Token> out) {
    var end = i + 1;
    while (end < text.length) {
      var d = text.codeUnitAt(end);
      if (_isLetter(d)) {
        end++;
        continue;
      }
      // An apostrophe, hyphen or full stop is part of the word only with a
      // letter after it: "don't", "well-known", "e.g".
      var joins = _isApostrophe(d) || d == 0x2d || d == 0x2e;
      if (joins &&
          end + 1 < text.length &&
          _isLetter(text.codeUnitAt(end + 1))) {
        // A full stop joins only single letters -- "U.S", never "end.The".
        if (d == 0x2e) {
          var single = end - i == 1 ||
              (end - i >= 2 && text.codeUnitAt(end - 2) == 0x2e);
          var nextSingle =
              end + 2 >= text.length || !_isLetter(text.codeUnitAt(end + 2));
          if (!single || !nextSingle) break;
        }
        end += 2;
        continue;
      }
      break;
    }
    var raw = text.substring(i, end);
    var lower = raw.toLowerCase().replaceAll("\u00ad", "");
    for (var k = 0; k < _apostrophes.length; k++) {
      if (k > 0) lower = lower.replaceAll(_apostrophes[k], "'");
    }

    var entry = lexicon.lookup(lower);
    if (entry == null) {
      var cut = lower.lastIndexOf("'");
      if (cut > 0 && _clitics.contains(lower.substring(cut))) {
        var head = lower.substring(0, cut);
        out.add(Token(i, i + cut, raw.substring(0, cut), head, TokenKind.word,
            space, lexicon.lookup(head)));
        var tail = lower.substring(cut);
        out.add(Token(i + cut, end, raw.substring(cut), tail, TokenKind.word,
            false, lexicon.lookup(tail)));
        return end;
      }
      if (lower.endsWith("n't") && lower.length > 3) {
        // A negative the lexicon does not list is still its verb.
        entry = lexicon.lookup(lower.substring(0, lower.length - 3));
      }
    }
    out.add(Token(i, end, raw, lower, TokenKind.word, space, entry));
    return end;
  }

  static final int _nounish = Tags.maskOfPrefix("NN");
  static final int _open = Tags.maskOfPrefix("NN") |
      Tags.maskOfPrefix("VB") |
      Tags.maskOfPrefix("JJ") |
      Tags.maskOfPrefix("RB");

  /// What a word the lexicon does not have is likeliest to be, from how it
  /// is written.
  List<Reading> _guess(Token t) {
    var w = t.lower;
    if (w.contains("-")) {
      // A compound takes after its last part, and is as often an adjective
      // made for the occasion.
      var last = lexicon.lookup(w.substring(w.lastIndexOf("-") + 1));
      return [
        Reading(Tags.jj, 50, w),
        Reading(Tags.nn, 40, w),
        if (last != null)
          for (var r in last.readings)
            if (r.tag != Tags.jj &&
                r.tag != Tags.nn &&
                (1 << r.tag) & _open != 0)
              Reading(r.tag, 5, w),
      ];
    }
    if (t.capitalised) return [Reading(Tags.nnp, 100, w)];
    if (w.endsWith("ly")) {
      return [Reading(Tags.rb, 80, w), Reading(Tags.jj, 20, w)];
    }
    if (w.endsWith("ing")) {
      return [
        Reading(Tags.vbg, 60, w),
        Reading(Tags.nn, 30, w),
        Reading(Tags.jj, 10, w)
      ];
    }
    if (w.endsWith("ed")) {
      return [
        Reading(Tags.vbn, 45, w),
        Reading(Tags.vbd, 40, w),
        Reading(Tags.jj, 15, w)
      ];
    }
    if (w.endsWith("s") && !w.endsWith("ss")) {
      return [Reading(Tags.nns, 70, w), Reading(Tags.vbz, 30, w)];
    }
    return [
      Reading(Tags.nn, 70, w),
      Reading(Tags.jj, 15, w),
      Reading(Tags.vb, 15, w)
    ];
  }

  /// The readings to choose among for [t].
  List<Reading> _readings(Token t) {
    switch (t.kind) {
      case TokenKind.number:
        return [Reading(Tags.cd, 100, t.lower)];
      case TokenKind.other:
        return [Reading(Tags.nnp, 100, t.lower)];
      case TokenKind.punctuation:
        var c = t.text.codeUnitAt(0);
        var tag =
            c == 0x2c || c == 0x3b || c == 0x3a || c == 0x2014 || c == 0x2013
                ? Tags.comma
                : c == 0x2e || c == 0x21 || c == 0x3f || c == 0x2026
                    ? Tags.stop
                    : _isApostrophe(c) ||
                            c == 0x22 ||
                            c == 0x201c ||
                            c == 0x201d ||
                            c == 0x28 ||
                            c == 0x29 ||
                            c == 0x5b ||
                            c == 0x5d
                        ? Tags.punct
                        : Tags.sym;
        return [Reading(tag, 100, t.text)];
      case TokenKind.word:
        var entry = t.entry;
        if (entry == null) return _guess(t);
        // A capital the writer chose makes any word a possible name: "Apple",
        // "Bill", "March".
        if (t.properLooking && entry.all & _nounish != 0 ||
            t.properLooking && !t.allCaps) {
          return [
            for (var r in entry.readings)
              if (r.tag != Tags.nnp) Reading(r.tag, r.weight ~/ 2, r.lemma),
            Reading(Tags.nnp, 50 + entry.weightOf(1 << Tags.nnp) ~/ 2, t.lower),
          ];
        }
        return entry.readings;
    }
  }

  /// Chooses each token's reading: the path through the sentence that best
  /// fits both what each word usually is and what usually follows what.
  void _tag(List<Token> tokens) {
    if (tokens.isEmpty) return;
    var nothingBefore = true;
    for (var t in tokens) {
      if (t.isWord) {
        t.first = true;
        t.clauseStart = true;
        t.opening = nothingBefore;
        break;
      }
      nothingBefore = false;
      if (t.kind != TokenKind.punctuation) break;
    }
    for (var i = 1; i < tokens.length; i++) {
      var before = tokens[i - 1];
      if (before.kind == TokenKind.punctuation
          ? !_closers.contains(before.text[0])
          : _joiners.contains(before.lower)) {
        tokens[i].clauseStart = true;
      }
    }
    var n = tokens.length;
    var options = <List<Reading>>[];
    for (var t in tokens) {
      var readings = _readings(t);
      options.add(readings);
      var mask = 0;
      for (var r in readings) {
        if (r.weight >= 2) mask |= 1 << r.tag;
      }
      t.likely = mask == 0 ? 1 << readings.first.tag : mask;
    }

    var score = <List<double>>[];
    var back = <List<int>>[];
    for (var i = 0; i < n; i++) {
      var here = options[i];
      var s = List<double>.filled(here.length, 0);
      var b = List<int>.filled(here.length, 0);
      for (var k = 0; k < here.length; k++) {
        // A reading counted at nothing is still possible, and is kept in the
        // running at a cost rather than ruled out.
        var emit = math.log(here[k].weight < 1 ? 0.3 : here[k].weight);
        if (i == 0) {
          s[k] = emit + _lift[Tags.bound * _n + here[k].tag];
          continue;
        }
        var prev = options[i - 1];
        var best = double.negativeInfinity;
        var from = 0;
        for (var j = 0; j < prev.length; j++) {
          var v = score[i - 1][j] + _lift[prev[j].tag * _n + here[k].tag];
          if (v > best) {
            best = v;
            from = j;
          }
        }
        s[k] = best + emit;
        b[k] = from;
      }
      score.add(s);
      back.add(b);
    }
    var last = options[n - 1];
    var bestEnd = 0;
    var bestScore = double.negativeInfinity;
    for (var k = 0; k < last.length; k++) {
      var v = score[n - 1][k] + _lift[last[k].tag * _n + Tags.bound];
      if (v > bestScore) {
        bestScore = v;
        bestEnd = k;
      }
    }
    var k = bestEnd;
    for (var i = n - 1; i >= 0; i--) {
      tokens[i].tag = options[i][k].tag;
      k = back[i][k];
    }
  }
}
