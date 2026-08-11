// suggester.dart answers "what did they mean to type": given a word the
// dictionary does not have, the handful of dictionary words that are nearest
// to it.
//
// There is no English in this file. It is edit distance, a couple of indexes
// and a sort -- a generic string algorithm over whatever wordlist it is
// handed, which is exactly the division the whole plugin arrangement rests on.
// A provider supplies the words and their frequency ranking; the ranking
// mechanism is the app's, and stays the app's.

/// _Candidate is one possible correction, with the two numbers it is ordered
/// by: how far it is from what was typed, and how common a word it is.
class _Candidate {
  final String word;
  final int distance;
  final int commonRank;
  const _Candidate(this.word, this.distance, this.commonRank);
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

  /// suggest ranks the dictionary words within [maxDistance] edits of [word]:
  /// nearest first, and among equally near ones, commonest first.
  ///
  /// The second half matters as much as the first. A short typo is one edit
  /// from a dozen words -- "teh" reaches "the", "tech", "meh", "th" and "te"
  /// alike -- and with distance alone deciding, which of them surfaces is
  /// arbitrary, so the intended word is as likely to be missing as not.
  /// Ordering ties by how common a word is puts the one somebody plausibly
  /// meant at the top. Words the provider ranked at all come before words it
  /// didn't.
  ///
  /// Only the candidate *set* is narrowed, never the scoring: every word the
  /// index offers is still measured exactly, so this returns what comparing
  /// against the entire dictionary would, just without doing it.
  List<String> suggest(String word,
      {int maxSuggestions = 5, int maxDistance = 2}) {
    var cached = _cache[word];
    if (cached != null) return cached;

    var wordMask = _letterMask(word);
    var maskLimit = 2 * maxDistance;
    // Rank beyond any real one, for words the provider left unranked.
    var unranked = _commonRank.length + 1;
    var scored = <_Candidate>[];

    for (var len = word.length - maxDistance;
        len <= word.length + maxDistance;
        len++) {
      for (var candidate in _byLength[len] ?? const <String>[]) {
        if (_bitCount(wordMask ^ _masks[candidate]!) > maskLimit) continue;
        var d = _editDistance(word, candidate, maxDistance);
        if (d <= maxDistance) {
          scored
              .add(_Candidate(candidate, d, _commonRank[candidate] ?? unranked));
        }
      }
    }

    scored.sort((a, b) {
      var byDistance = a.distance.compareTo(b.distance);
      if (byDistance != 0) return byDistance;
      return a.commonRank.compareTo(b.commonRank);
    });
    var out = scored.take(maxSuggestions).map((c) => c.word).toList();
    _cache[word] = out;
    return out;
  }
}

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
