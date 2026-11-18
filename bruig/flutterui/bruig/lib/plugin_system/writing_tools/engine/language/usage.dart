import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/writing_tools/engine/language/tokens.dart';

// usage.dart reads what the provider counted about how English is written:
// the company each confusable word keeps, and which common words are never
// found side by side.
//
// Both tables are kept as the bytes they arrived in. A context is looked up
// by hashing its words exactly as the provider did when it counted them and
// searching for the hash, so nothing here is ever unpacked into a map -- a
// million entries cost six megabytes and no time at start-up.

/// UsageModel answers "how often was this seen".
class UsageModel {
  final Uint32List _keys;
  final Uint8List _checks;
  final Uint8List _counts;

  /// Each confusable word, with the words it is mistaken for.
  final Map<String, Set<String>> rivals;

  final Map<String, int> _pairRank;
  final Uint8List _pairBits;
  final int _pairN;

  UsageModel._(this._keys, this._checks, this._counts, this.rivals,
      this._pairRank, this._pairBits, this._pairN);

  static final UsageModel empty = UsageModel._(Uint32List(0), Uint8List(0),
      Uint8List(0), const {}, const {}, Uint8List(0), 0);

  /// Reads the provider's tables. Anything malformed is read as absent: a
  /// checker without counts makes no guesses, which is the safe way to be
  /// wrong about a file.
  factory UsageModel.parse({
    required Uint8List ngrams,
    required List<String> confusionSets,
    required String pairWords,
    required Uint8List pairBits,
  }) {
    var keys = Uint32List(0);
    var checks = Uint8List(0);
    var counts = Uint8List(0);
    if (ngrams.length >= 4) {
      var header = ByteData.sublistView(ngrams);
      var n = header.getUint32(0, Endian.little);
      if (ngrams.length == 4 + 6 * n) {
        // Read out one at a time rather than viewed in place: a view needs
        // its bytes aligned, and a decoded buffer makes no promise about
        // where it starts.
        keys = Uint32List(n);
        for (var i = 0; i < n; i++) {
          keys[i] = header.getUint32(4 + 4 * i, Endian.little);
        }
        checks = Uint8List.sublistView(ngrams, 4 + 4 * n, 4 + 5 * n);
        counts = Uint8List.sublistView(ngrams, 4 + 5 * n);
      }
    }

    var rivals = <String, Set<String>>{};
    for (var line in confusionSets) {
      var set = line.split(" ").where((w) => w.isNotEmpty).toList();
      for (var word in set) {
        (rivals[word] ??= {}).addAll(set.where((w) => w != word));
      }
    }

    var words =
        pairWords.isEmpty ? const <String>[] : pairWords.trim().split("\n");
    var rank = <String, int>{
      for (var i = 0; i < words.length; i++) words[i]: i,
    };
    var n = words.length;
    if (pairBits.length != (n * n + 7) ~/ 8) {
      rank = {};
      n = 0;
    }
    return UsageModel._(keys, checks, counts, rivals, rank, pairBits, n);
  }

  bool get hasContexts => _keys.isNotEmpty;
  bool get hasPairs => _pairN > 0;

  /// A context, ready to be asked about: [kind] is "M" for the word either
  /// side of the gap, "A" and "B" for the two before and the two after, "l"
  /// and "r" for the one before and the one after, and "u" with no parts
  /// for anywhere at all.
  ///
  /// Hashed once and asked about several times -- the word that was typed
  /// and each of its rivals sit in the same gap, and the hashing was most of
  /// what a lookup cost.
  static int context(String kind, List<String> parts) {
    var h = _fnv(_fnvStart, kind);
    for (var p in parts) {
      h = (h ^ 0) * _fnvPrime;
      h = _fnv(h, p);
    }
    return h;
  }

  /// How often [word] was seen in the gap of [context].
  ///
  /// Zero means it was not seen there, or that being seen there settles
  /// nothing: the provider keeps a context only where one word is found far
  /// more than a rival, and then keeps every rival's count beside it. So a
  /// zero for the word that was typed, where its rival has a count, really
  /// is none. The count is rounded -- it is stored at eight steps to each
  /// doubling.
  double countIn(int context, String word) {
    var hash = _mix(context, word);
    var key = hash & 0xffffffff;
    var check = (hash >>> 40) & 0xff;
    // The first entry with this key, then along the few that share it for
    // the one whose check byte matches too.
    var lo = 0, hi = _keys.length;
    while (lo < hi) {
      var mid = (lo + hi) >> 1;
      if (_keys[mid] < key) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _keys.length && _keys[i] == key; i++) {
      if (_checks[i] == check) return _decode[_counts[i]];
    }
    return 0;
  }

  /// [countIn] for a context asked about once.
  double count(String kind, List<String> parts, String word) =>
      countIn(context(kind, parts), word);

  static final List<double> _decode = [
    for (var v = 0; v < 256; v++) math.pow(2, v / 8).toDouble(),
  ];

  /// Whether [first] directly followed by [second] is a pairing that edited
  /// English all but never has, though both words are common.
  bool neverTogether(String first, String second) {
    var a = _pairRank[first], b = _pairRank[second];
    if (a == null || b == null) return false;
    var at = a * _pairN + b;
    return _pairBits[at >> 3] & (1 << (at & 7)) != 0;
  }

  /// The provider's tools/mkusage `fileKey`, which this has to match bit for
  /// bit: the context's hash with its low ten bits dropped, mixed with the
  /// same hash of the word in the gap and stirred. The low four bytes are
  /// the key and the sixth is the check that goes with it.
  int _mix(int context, String word) {
    var wordHash = _wordHashes[word] ??= _fnv(_fnvStart, word);
    var h = (context >>> 10) * 0x9E3779B97F4A7C15 ^ wordHash;
    h ^= h >>> 29;
    h *= 0xBF58476D1CE4E5B9;
    h ^= h >>> 32;
    return h;
  }

  /// The confusable words' own hashes. There are a few hundred of them and
  /// each is asked about thousands of times.
  final Map<String, int> _wordHashes = {};

  static const _fnvStart = 0xcbf29ce484222325;
  static const _fnvPrime = 0x100000001b3;

  /// FNV-1a over [s] as UTF-8, continuing from [h].
  static int _fnv(int h, String s) {
    for (var i = 0; i < s.length; i++) {
      var c = s.codeUnitAt(i);
      if (c > 0x7f) {
        // Not plain ASCII: start over the slow way, byte for byte as the
        // provider hashed it.
        for (var b in utf8.encode(s.substring(i))) {
          h = (h ^ b) * _fnvPrime;
        }
        return h;
      }
      h = (h ^ c) * _fnvPrime;
    }
    return h;
  }
}

/// Unit is one piece of a sentence as the counts see it, with the tokens it
/// was made from.
class Unit {
  final String text;
  final int firstToken;
  final int lastToken;
  const Unit(this.text, this.firstToken, this.lastToken);
}

const _transparent = {
  '"', "'", "‘", "’", "“", "”", "(", ")", "[", "]", //
};

/// The sentence as the provider counted sentences: each word whole,
/// contractions included, every number one thing, and the marks reduced to
/// what they do. Quotes and brackets are left out, since a word's company is
/// the same inside them as outside.
///
/// tools/mkusage `units` in the plugin is the other copy of this, and the
/// two must agree: a context filed under one spelling and asked for under
/// another is simply never found.
List<Unit> unitsOf(Sentence sentence) {
  var tokens = sentence.tokens;
  var out = <Unit>[];
  for (var i = 0; i < tokens.length; i++) {
    var t = tokens[i];
    switch (t.kind) {
      case TokenKind.word:
        if (!t.spaceBefore &&
            out.isNotEmpty &&
            t.lower.startsWith("'") &&
            i > 0 &&
            tokens[i - 1].isWord) {
          var before = out.removeLast();
          out.add(Unit(before.text + t.lower, before.firstToken, i));
        } else {
          out.add(Unit(t.lower, i, i));
        }
      case TokenKind.number:
        out.add(Unit("#", i, i));
      case TokenKind.other:
        out.add(Unit("*", i, i));
      case TokenKind.punctuation:
        var c = t.text[0];
        if (c == "," || c == ";" || c == ":" || c == "—" || c == "–") {
          out.add(Unit(",", i, i));
        } else if (c == "." || c == "!" || c == "?" || c == "…") {
          // The stop that ends the sentence is the sentence's end.
          var closing = true;
          for (var j = i + 1; j < tokens.length; j++) {
            if (!_transparent.contains(tokens[j].text[0])) closing = false;
          }
          if (!closing) out.add(Unit(".", i, i));
        } else if (!_transparent.contains(c)) {
          out.add(Unit("*", i, i));
        }
    }
  }
  return out;
}
