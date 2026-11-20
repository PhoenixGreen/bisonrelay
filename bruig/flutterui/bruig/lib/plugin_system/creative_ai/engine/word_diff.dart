// word_diff.dart is the difference between two versions of some text, word
// by word, for showing a suggested rewrite as what it takes out and puts in
// rather than as a second paragraph to compare by eye.
//
// Words keep the spaces after them, so joining the pieces of either side
// gives that side back exactly. Pure Dart.

/// DiffKind is whether a piece is in both versions, only the old or only
/// the new.
enum DiffKind { same, removed, added }

class DiffPiece {
  final DiffKind kind;
  final String text;
  const DiffPiece(this.kind, this.text);

  @override
  bool operator ==(Object other) =>
      other is DiffPiece && other.kind == kind && other.text == text;
  @override
  int get hashCode => Object.hash(kind, text);
  @override
  String toString() => "${kind.name}(${text.replaceAll("\n", r"\n")})";
}

/// _tokens splits [text] into words, each with the white space after it; a
/// run of punctuation is a word of its own so a changed comma is shown as
/// that rather than as a changed word.
List<String> _tokens(String text) => [
      for (var m in RegExp(r"[\p{L}\p{N}'’]+\s*|[^\p{L}\p{N}\s]+\s*|\s+",
              unicode: true)
          .allMatches(text))
        m.group(0)!
    ];

/// wordDiff is [before] turned into [after], in pieces. Neighbouring pieces
/// of a kind are joined.
List<DiffPiece> wordDiff(String before, String after) {
  var a = _tokens(before), b = _tokens(after);
  // Common start and end are cut first: a rewrite usually keeps both, and
  // the table in between is all that costs anything.
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  var midA = a.sublist(start, endA), midB = b.sublist(start, endB);

  var pieces = <DiffPiece>[
    for (var t in a.sublist(0, start)) DiffPiece(DiffKind.same, t),
  ];
  // Longest common subsequence over the middle; past a size it would cost
  // too much, the middle is shown as all out and all in.
  if (midA.length * midB.length > 4000000) {
    pieces.addAll([for (var t in midA) DiffPiece(DiffKind.removed, t)]);
    pieces.addAll([for (var t in midB) DiffPiece(DiffKind.added, t)]);
  } else {
    var n = midA.length, m = midB.length;
    var table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        table[i][j] = midA[i] == midB[j]
            ? table[i + 1][j + 1] + 1
            : (table[i + 1][j] >= table[i][j + 1]
                ? table[i + 1][j]
                : table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (midA[i] == midB[j]) {
        pieces.add(DiffPiece(DiffKind.same, midA[i]));
        i++;
        j++;
      } else if (table[i + 1][j] >= table[i][j + 1]) {
        pieces.add(DiffPiece(DiffKind.removed, midA[i++]));
      } else {
        pieces.add(DiffPiece(DiffKind.added, midB[j++]));
      }
    }
    while (i < n) {
      pieces.add(DiffPiece(DiffKind.removed, midA[i++]));
    }
    while (j < m) {
      pieces.add(DiffPiece(DiffKind.added, midB[j++]));
    }
  }
  pieces.addAll([for (var t in a.sublist(endA)) DiffPiece(DiffKind.same, t)]);

  // Join neighbours of a kind.
  var joined = <DiffPiece>[];
  for (var p in pieces) {
    if (joined.isNotEmpty && joined.last.kind == p.kind) {
      joined[joined.length - 1] = DiffPiece(p.kind, joined.last.text + p.text);
    } else {
      joined.add(p);
    }
  }
  return joined;
}
