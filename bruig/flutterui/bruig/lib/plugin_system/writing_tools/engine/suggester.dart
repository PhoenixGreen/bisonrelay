import 'dart:math' as math;

// suggester.dart answers "what did they mean to type": given a word the
// dictionary does not have, the handful of dictionary words that are nearest
// to it.
//
// There is no English in this file. It is edit distance, a couple of indexes
// and a sort -- a generic string algorithm over whatever wordlist it is
// handed, which is exactly the division the whole plugin arrangement rests on.
// A provider supplies the words and their frequency ranking; the ranking
// mechanism is the app's, and stays the app's.

/// _Candidate is one possible correction and how good a guess it is: lower
/// is better.
class _Candidate {
  final String word;
  final double score;
  const _Candidate(this.word, this.score);
}

/// Suggester holds a dictionary indexed for near-miss lookup.
///
/// Rebuilt wholesale whenever the word list changes, which is rare -- once
/// when a provider is enabled and again if the language changes. A real
/// dictionary is around 120k words and indexing takes roughly 20ms.
class Suggester {
  /// _byLength indexes the dictionary by word length and _masks caches each
  /// word's letter set. Together they cut the candidates a misspelling is
  /// measured against from the whole dictionary to a few hundred.
  final Map<int, List<String>> _byLength = {};
  final Map<String, int> _masks = {};

  /// _commonRank maps a word to its position in the provider's most-common
  /// list; absent means "not common". It is what breaks the ties edit distance
  /// leaves behind -- see [suggest].
  final Map<String, int> _commonRank = {};

  /// _cache memoizes by word. Every keystroke re-checks the whole composer, so
  /// without it the same handful of misspellings is rescored on each one; with
  /// it, only a newly typed word costs anything.
  final Map<String, List<String>> _cache = {};

  /// index rebuilds from a lowercased word list and a most-common-first
  /// ranking of it.
  void index(Iterable<String> words, List<String> commonWords) {
    _byLength.clear();
    _masks.clear();
    _commonRank.clear();
    _cache.clear();

    for (var i = 0; i < commonWords.length; i++) {
      // First occurrence wins: merged lists from several providers are
      // concatenated, so an earlier provider's ranking takes precedence.
      _commonRank.putIfAbsent(commonWords[i].toLowerCase(), () => i);
    }
    for (var w in words) {
      (_byLength[w.length] ??= []).add(w);
      _masks[w] = _letterMask(w);
    }
  }

  /// suggest returns the dictionary words [word] was most likely meant to
  /// be, best first.
  ///
  /// Two things decide it, and neither is enough alone. How far the word is
  /// from what was typed -- but a short typo is one edit from a dozen words,
  /// "teh" from "the", "tea", "ten" and "tech" alike. And how common the
  /// word is -- but the commonest word within reach is not what was meant if
  /// a rarer one is a single slip away. So each candidate is scored on both:
  /// the edits it takes to reach it, weighted by how likely each kind of slip
  /// is, plus a charge that grows with how rarely the word is written.
  ///
  /// The candidate *set* is still everything within [maxDistance] plain
  /// edits, found exactly; only the order among them is a judgement.
  List<String> suggest(String word,
      {int maxSuggestions = 5, int maxDistance = 2}) {
    var cached = _cache[word];
    if (cached != null) return cached;

    var wordMask = _letterMask(word);
    var maskLimit = 2 * maxDistance;
    var scored = <_Candidate>[];

    for (var len = word.length - maxDistance;
        len <= word.length + maxDistance;
        len++) {
      for (var candidate in _byLength[len] ?? const <String>[]) {
        if (_bitCount(wordMask ^ _masks[candidate]!) > maskLimit) continue;
        var d = _editDistance(word, candidate, maxDistance);
        if (d > maxDistance) continue;
        scored.add(_Candidate(
            candidate, _slipCost(word, candidate) + _rarity(candidate)));
      }
    }

    // Two words run together: "thankyou", "infront". One slip -- a missing
    // space -- and only believed where both halves are everyday words, since
    // almost any string can be cut into two dictionary entries somewhere.
    for (var cut = 1; cut < word.length; cut++) {
      var head = word.substring(0, cut), tail = word.substring(cut);
      if (head.length == 1 && head != "a" && head != "i") continue;
      if (tail.length < 2) continue;
      var headRank = _commonRank[head], tailRank = _commonRank[tail];
      if (headRank == null || tailRank == null) continue;
      if (headRank > _everyday || tailRank > _everyday) continue;
      var rarer = headRank > tailRank ? head : tail;
      // A little dearer than a single slip: where one wrong letter also
      // makes a word, that is the likelier story -- "belive" is "believe"
      // before it is "be live".
      scored.add(_Candidate("$head $tail", 1.25 + _rarity(rarer)));
    }

    scored.sort((a, b) {
      var byScore = a.score.compareTo(b.score);
      return byScore != 0 ? byScore : a.word.compareTo(b.word);
    });
    var out = scored.take(maxSuggestions).map((c) => c.word).toList();
    _cache[word] = out;
    return out;
  }

  /// How far down the provider's ranking a word may be and still count as an
  /// everyday one, for believing that two of them were run together.
  static const _everyday = 4000;

  /// What a word's rarity adds to its score: nothing much for the commonest
  /// words, most of an edit for one the provider did not rank at all. It is
  /// what lets "the" beat "tea" for "teh" without letting it beat a rare
  /// word that is plainly the one meant.
  double _rarity(String candidate) {
    var rank = _commonRank[candidate] ?? _commonRank.length * 4 + 20000;
    return 0.22 * math.log(rank + 10) / math.ln10;
  }
}

/// How costly the slips are that turn [typed] into [meant], in edits: one
/// for an ordinary wrong, missing or extra letter, and less for the slips
/// fingers make most.
///
///   - Two letters the wrong way round is the commonest typing error there
///     is, and counts for six tenths.
///   - So does a doubled letter left single, or a single one doubled:
///     "realy", "untill".
///   - One vowel for another is how a word is misspelled by somebody who
///     knows how it sounds -- "seperate", "definately" -- and counts for
///     eight tenths.
///   - Getting the first letter wrong is rare, and costs three tenths more.
double _slipCost(String typed, String meant) {
  var a = typed, b = meant;
  var n = a.length, m = b.length;
  // The same recurrence as _editDistance, with a cost on each step.
  var prevPrev = List<double>.filled(m + 1, 0);
  var prev = List<double>.generate(m + 1, (j) => j.toDouble());
  var curr = List<double>.filled(m + 1, 0);
  for (var i = 1; i <= n; i++) {
    curr[0] = i.toDouble();
    var ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= m; j++) {
      var cb = b.codeUnitAt(j - 1);
      var substitute =
          ca == cb ? 0.0 : (_isVowel(ca) && _isVowel(cb) ? 0.8 : 1.0);
      // A letter typed that is not wanted: cheap if it doubles the one
      // before it.
      var extra = i > 1 && ca == a.codeUnitAt(i - 2) ? 0.6 : 1.0;
      // A letter wanted that was not typed: cheap if it would have doubled.
      var missing = j > 1 && cb == b.codeUnitAt(j - 2) ? 0.6 : 1.0;
      var v = prev[j - 1] + substitute;
      if (prev[j] + extra < v) v = prev[j] + extra;
      if (curr[j - 1] + missing < v) v = curr[j - 1] + missing;
      if (i > 1 &&
          j > 1 &&
          ca == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == cb &&
          prevPrev[j - 2] + 0.6 < v) {
        v = prevPrev[j - 2] + 0.6;
      }
      curr[j] = v;
    }
    var tmp = prevPrev;
    prevPrev = prev;
    prev = curr;
    curr = tmp;
  }
  var cost = prev[m];
  if (a.isNotEmpty && b.isNotEmpty && a.codeUnitAt(0) != b.codeUnitAt(0)) {
    cost += 0.3;
  }
  return cost;
}

bool _isVowel(int c) =>
    c == 0x61 || c == 0x65 || c == 0x69 || c == 0x6f || c == 0x75 || c == 0x79;

/// _letterMask is a 26-bit set of which letters appear in [w], used to reject
/// candidates before paying for the distance matrix. A single edit changes the
/// letter *set* by at most two elements (a substitution removes one and adds
/// another), so more than `2 * maxDistance` differing letters proves the words
/// are too far apart. It is a necessary condition only -- a candidate that
/// passes still has to be measured -- so the filter can never lose a
/// suggestion, only save work.
int _letterMask(String w) {
  var mask = 0;
  for (var i = 0; i < w.length; i++) {
    var c = w.codeUnitAt(i) - 97; // 'a'
    if (c >= 0 && c < 26) mask |= 1 << c;
  }
  return mask;
}

int _bitCount(int x) {
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

/// Damerau-Levenshtein (edit) distance between two strings, abandoned as soon
/// as the whole working row exceeds [max].
///
/// Damerau rather than plain Levenshtein because it counts a transposition of
/// adjacent characters as one typo rather than two, and transposition is the
/// commonest typing error there is -- "recieve", "teh", "thier". Scored as two
/// edits, the intended word sinks below every word that is merely one
/// substitution away, and never reaches the handful of corrections shown.
///
/// The bound matters: this runs over thousands of candidates per misspelled
/// word, and almost all of them are nowhere near. Returning `max + 1` for
/// those instead of finishing the matrix is most of why a full dictionary is
/// affordable at all.
int _editDistance(String a, String b, int max) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Three rows, not two: a transposition looks back two rows and two columns.
  var prevPrev = List<int>.filled(b.length + 1, 0);
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowBest = i;
    for (var j = 1; j <= b.length; j++) {
      var cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (curr[j - 1] + 1 < v) v = curr[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        var transposed = prevPrev[j - 2] + 1;
        if (transposed < v) v = transposed;
      }
      curr[j] = v;
      if (v < rowBest) rowBest = v;
    }
    // Every later row is at least this row's minimum, so once that exceeds the
    // budget the final distance cannot come back under it.
    if (rowBest > max) return max + 1;
    var tmp = prevPrev;
    prevPrev = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}
