import 'package:bruig/plugin_system/writing_tools/engine/language/lexicon.dart';
import 'package:bruig/plugin_system/writing_tools/engine/language/tokens.dart';

// token_rules.dart runs the provider's grammar rules: patterns over words and
// what they are, rather than over characters.
//
// A regular expression can say "he" followed by "go". It cannot say "a
// singular pronoun followed by any verb in its base form", and writing that
// out word by word is how the older rules came to cover a few dozen verbs
// and miss the rest of the language. These patterns say it directly:
//
//     he|she|it ( <VB>&!<~VBD> )
//
// A pattern is a row of elements, one per word, separated by spaces:
//
//     word            that word, in any case
//     a|an|the        any of these
//     "?"             exactly this text, for a mark that is also syntax
//     <VB>            the reading chosen for it here is VB
//     <VB*>           ... is any tag starting VB
//     <~NN>           it can be a noun, whatever it is here
//     <+NN>           it is a noun at least one time in five
//     <=NN>           it is a noun nine times in ten, and is a known word
//     [be]            any form of "be"
//     {class}         any word in the provider's list of that name
//     /regex/         its text as written matches, whole
//     #cap #lower #first #known #num #allcaps #word    what its name says
//     _  or  <_>      anything at all
//
//     #clause         a clause starts here, so a pronoun here is a subject
//
//     !x              not x          x&y    both (binds looser than |)
//     x?              optional       x{0,3} between none and three of them
//     ^  $            the sentence's start and end
//     =>x  !>x        the next word is x, or is not x or is not there --
//                     looked at and not taken
//     ( )             what to underline; the whole match if absent
//
// The messages and replacements may quote what matched: `$2` is the second
// element as written, and `$2:VBZ` is its base word in that form -- so
// "go" becomes "goes", and "went" after "didn't" becomes "go". Elements are
// numbered as written, leaving out ^ $ ( ) and the two that only look.
// Besides the tags, `:NOM` and `:ACC` turn a pronoun into its subject or
// object form, `:BE` gives the present form of "be" that goes with it, and
// `:Cap` gives the text a capital.

/// A provider's named lists of words, for `{name}`.
typedef WordClasses = Map<String, Set<String>>;

typedef _Test = bool Function(Token);

class _Element {
  final _Test? test;
  final int min;
  final int max;

  /// One of ^ $ ( ) for an element that matches no word.
  final String anchor;

  /// The words that satisfy this element, where it is nothing but words --
  /// which is what lets a rule be skipped for a sentence with none of them.
  final Set<String>? literals;

  const _Element.word(this.test, this.min, this.max, this.literals)
      : anchor = "";

  /// A look at the next word that does not take it: "=>" wants it to match
  /// and "!>" wants it not to, or not to be there.
  const _Element.ahead(this.anchor, this.test)
      : min = 0,
        max = 0,
        literals = null;
  const _Element.anchor(this.anchor)
      : test = null,
        min = 0,
        max = 0,
        literals = null;
}

/// TokenPattern is one compiled pattern.
class TokenPattern {
  final List<_Element> _elements;

  /// The words one of which the sentence must contain for this to match, or
  /// null where no element pins it down.
  final Set<String>? required;

  TokenPattern._(this._elements, this.required);

  /// Compiles [source], or throws a [FormatException] saying what is wrong
  /// with it -- a pattern is written by hand and read by nobody else until
  /// it fails to match.
  factory TokenPattern.compile(String source,
      [WordClasses classes = const {}]) {
    var elements = <_Element>[];
    for (var raw in source.trim().split(RegExp(r"\s+"))) {
      if (raw.isEmpty) continue;
      if (raw == "^" || raw == r"$" || raw == "(" || raw == ")") {
        elements.add(_Element.anchor(raw));
        continue;
      }
      var ahead = raw.startsWith("=>") || raw.startsWith("!>");
      var min = 1, max = 1;
      var body = ahead ? raw.substring(2) : raw;
      var repeat = RegExp(r"\{(\d+),(\d+)\}$").firstMatch(body);
      if (repeat != null && !body.startsWith("{")) {
        min = int.parse(repeat.group(1)!);
        max = int.parse(repeat.group(2)!);
        body = body.substring(0, repeat.start);
      } else if (body.length > 1 &&
          body.endsWith("?") &&
          !body.endsWith('"?"')) {
        min = 0;
        body = body.substring(0, body.length - 1);
      }
      var literals = <String>{};
      var onlyLiterals = true;
      var tests = <_Test>[];
      for (var part in _split(body, "&")) {
        var negated = part.startsWith("!");
        if (negated) part = part.substring(1);
        var alternatives = <_Test>[];
        for (var atom in _split(part, "|")) {
          alternatives.add(_atom(atom, classes, (words) {
            if (words == null || negated) {
              onlyLiterals = false;
            } else {
              literals.addAll(words);
            }
          }, source));
        }
        if (negated) onlyLiterals = false;
        bool any(Token t) {
          for (var a in alternatives) {
            if (a(t)) return true;
          }
          return false;
        }

        tests.add(negated ? (t) => !any(t) : any);
      }
      bool all(Token t) {
        for (var test in tests) {
          if (!test(t)) return false;
        }
        return true;
      }

      if (ahead) {
        elements.add(_Element.ahead(raw.substring(0, 2), all));
        continue;
      }
      // An element narrowed by `&` still needs one of its words; one widened
      // by a tag or a wildcard needs none in particular.
      var pinned = onlyLiterals || (literals.isNotEmpty && _allLiteralOr(body));
      elements.add(
          _Element.word(all, min, max, pinned && min > 0 ? literals : null));
    }

    Set<String>? required;
    for (var e in elements) {
      var words = e.literals;
      if (words == null || words.isEmpty) continue;
      if (required == null || words.length < required.length) required = words;
    }
    return TokenPattern._(elements, required);
  }

  /// Whether the first `&`-part of [body] is words alone, so the element
  /// cannot match without one of them whatever else it asks.
  static bool _allLiteralOr(String body) {
    var first = _split(body, "&").first;
    if (first.startsWith("!")) return false;
    for (var atom in _split(first, "|")) {
      if (atom.isEmpty) return false;
      var c = atom[0];
      if (c == "<" || c == "[" || c == "/" || c == "#" || c == "_") {
        return false;
      }
    }
    return true;
  }

  /// Splits on [separator] outside the brackets an atom is written in.
  static List<String> _split(String s, String separator) {
    var out = <String>[];
    var depth = "";
    var from = 0;
    for (var i = 0; i < s.length; i++) {
      var c = s[i];
      if (depth.isEmpty) {
        if (c == "<") depth = ">";
        if (c == "[") depth = "]";
        if (c == "{") depth = "}";
        if (c == "/" || c == '"') depth = c;
        if (c == separator && depth.isEmpty) {
          out.add(s.substring(from, i));
          from = i + 1;
        }
      } else if (c == depth) {
        depth = "";
      }
    }
    out.add(s.substring(from));
    return out;
  }

  static _Test _atom(String atom, WordClasses classes,
      void Function(Set<String>? words) literal, String source) {
    Never bad(String why) => throw FormatException("$why in \"$atom\"", source);
    if (atom.isEmpty) bad("empty alternative");
    if (atom == "_" || atom == "<_>") {
      literal(null);
      return (_) => true;
    }
    var c = atom[0];
    var last = atom[atom.length - 1];
    if (c == "<") {
      if (last != ">") bad("unclosed <");
      literal(null);
      var body = atom.substring(1, atom.length - 1);
      var mode = "";
      if (body.startsWith("~") ||
          body.startsWith("=") ||
          body.startsWith("+")) {
        mode = body[0];
        body = body.substring(1);
      }
      var mask = 0;
      for (var name in body.split("|")) {
        var m = name.endsWith("*")
            ? Tags.maskOfPrefix(name.substring(0, name.length - 1))
            : (Tags.id(name) < 0 ? 0 : 1 << Tags.id(name));
        if (m == 0) bad("unknown tag $name");
        mask |= m;
      }
      return switch (mode) {
        "~" => (t) => t.canBe(mask),
        "+" => (t) =>
            t.known ? t.entry!.weightOf(mask) >= 20 : t.isTagged(mask),
        "=" => (t) =>
            t.known &&
            !t.properLooking &&
            (t.entry!.weightOf(mask) >= 90 || t.onlyBe(mask)),
        _ => (t) => t.isTagged(mask),
      };
    }
    if (c == "[") {
      if (last != "]") bad("unclosed [");
      literal(null);
      var lemma = atom.substring(1, atom.length - 1);
      return (t) => t.lower == lemma || (t.entry?.hasLemma(lemma) ?? false);
    }
    if (c == "{") {
      if (last != "}") bad("unclosed {");
      var words = classes[atom.substring(1, atom.length - 1)];
      if (words == null) bad("unknown class");
      literal(words);
      return (t) => words.contains(t.lower);
    }
    if (c == "/" && atom.length > 2) {
      if (last != "/") bad("unclosed /");
      literal(null);
      var re = RegExp("^(?:${atom.substring(1, atom.length - 1)})\$");
      return (t) => re.hasMatch(t.text);
    }
    if (c == '"' && atom.length > 2) {
      if (last != '"') bad('unclosed "');
      var text = atom.substring(1, atom.length - 1).toLowerCase();
      literal({text});
      return (t) => t.lower == text;
    }
    if (c == "#") {
      literal(null);
      return switch (atom) {
        "#cap" => (t) => t.capitalised,
        "#lower" => (t) => t.isWord && !t.capitalised,
        "#first" => (t) => t.first,
        "#known" => (t) => t.known,
        "#unknown" => (t) => t.isWord && !t.known,
        "#num" => (t) => t.kind == TokenKind.number,
        "#word" => (t) => t.isWord,
        "#allcaps" => (t) => t.allCaps,
        "#proper" => (t) => t.properLooking,
        "#clause" => (t) => t.clauseStart,
        "#opening" => (t) => t.opening,
        _ => bad("unknown test"),
      };
    }
    var word = atom.toLowerCase();
    literal({word});
    return (t) => t.lower == word;
  }

  /// Whether a sentence whose words are [words] could match at all.
  bool couldMatch(Set<String> words) {
    var needed = required;
    if (needed == null) return true;
    // Whichever is the shorter list is the one walked: a class can run to
    // hundreds of words and a sentence to twenty.
    if (needed.length <= words.length) {
      for (var w in needed) {
        if (words.contains(w)) return true;
      }
    } else {
      for (var w in words) {
        if (needed.contains(w)) return true;
      }
    }
    return false;
  }

  /// The test a match's first word has to pass, where the pattern opens
  /// with a word it cannot do without -- so that the hundred places a
  /// pattern does not start cost a test each rather than a match attempt.
  late final _Test? _opening = () {
    for (var e in _elements) {
      if (e.anchor == "^" || e.anchor == "(") continue;
      return e.anchor.isEmpty && e.min > 0 ? e.test : null;
    }
    return null;
  }();

  /// Every place this matches in [tokens].
  List<TokenMatch> allMatches(List<Token> tokens) {
    var out = <TokenMatch>[];
    var opening = _opening;
    for (var at = 0; at <= tokens.length; at++) {
      if (opening != null && (at == tokens.length || !opening(tokens[at]))) {
        continue;
      }
      var match = _matchAt(tokens, at);
      if (match != null) out.add(match);
    }
    return out;
  }

  TokenMatch? _matchAt(List<Token> tokens, int at) {
    var starts = List<int>.filled(_elements.length, -1);
    var ends = List<int>.filled(_elements.length, -1);
    var open = -1, close = -1;

    bool atStart(int i) {
      for (var j = 0; j < i; j++) {
        if (tokens[j].kind != TokenKind.punctuation) return false;
      }
      return true;
    }

    bool atEnd(int i) {
      for (var j = i; j < tokens.length; j++) {
        if (tokens[j].kind != TokenKind.punctuation) return false;
      }
      return true;
    }

    bool step(int e, int i) {
      if (e == _elements.length) return true;
      var element = _elements[e];
      switch (element.anchor) {
        case "^":
          return atStart(i) && step(e + 1, i);
        case r"$":
          return atEnd(i) && step(e + 1, i);
        case "(":
          var saved = open;
          open = i;
          if (step(e + 1, i)) return true;
          open = saved;
          return false;
        case ")":
          var saved = close;
          close = i;
          if (step(e + 1, i)) return true;
          close = saved;
          return false;
        case "=>":
          return i < tokens.length &&
              element.test!(tokens[i]) &&
              step(e + 1, i);
        case "!>":
          return (i >= tokens.length || !element.test!(tokens[i])) &&
              step(e + 1, i);
      }
      // As many as it will take, then fewer.
      var n = 0;
      while (n < element.max &&
          i + n < tokens.length &&
          element.test!(tokens[i + n])) {
        n++;
      }
      for (; n >= element.min; n--) {
        starts[e] = i;
        ends[e] = i + n;
        if (step(e + 1, i + n)) return true;
      }
      starts[e] = -1;
      ends[e] = -1;
      return false;
    }

    // A match has to begin with a word of its own: an optional first element
    // that matched nothing would otherwise report the same match again from
    // every earlier position.
    if (!step(0, at)) return null;
    var first = -1, last = -1;
    var groups = <(int, int)>[];
    for (var e = 0; e < _elements.length; e++) {
      if (_elements[e].anchor.isNotEmpty) continue;
      groups.add((starts[e], ends[e]));
      if (ends[e] > starts[e]) {
        if (first < 0) first = starts[e];
        last = ends[e];
      }
    }
    if (first < 0 || first != at) return null;
    var from = open < 0 ? first : open;
    var to = close < 0 ? last : close;
    if (to <= from) return null;
    return TokenMatch(tokens, groups, from, to);
  }
}

/// Whether [word] is said with a vowel first, and so takes "an".
///
/// By sound, which spelling only mostly follows: "an hour" and "a user".
bool takesAn(String word) {
  var w = word.toLowerCase();
  if (w.isEmpty) return false;
  if (RegExp(r"^(hour|honest|honou?r|heir)").hasMatch(w)) return true;
  if (RegExp(r"^(uni(?!n|m)|us[aeiu]|ut[ei]|eu|ew|one|once|ur[ai]n|ub[ie]|ufo)")
      .hasMatch(w)) {
    return false;
  }
  return "aeiou".contains(w[0]);
}

const _nominative = {
  "me": "I", "him": "he", "her": "she", "us": "we", "them": "they", //
};
const _accusative = {
  "i": "me", "he": "him", "she": "her", "we": "us", "they": "them", //
};
const _be = {
  "i": "am", "you": "are", "we": "are", "they": "are", "these": "are", //
  "those": "are",
};

/// TokenMatch is one place a pattern matched.
class TokenMatch {
  final List<Token> tokens;

  /// Each element's tokens, as [start, end) into [tokens]; the two are equal
  /// for an optional element that matched nothing.
  final List<(int, int)> groups;

  /// The tokens to underline, as [start, end).
  final int from;
  final int to;

  TokenMatch(this.tokens, this.groups, this.from, this.to);

  int get start => tokens[from].start;
  int get end => tokens[to - 1].end;

  /// Fills in [template] against [source], the text the tokens were read
  /// from. Returns null where it asks for a form the lexicon cannot supply
  /// -- an answer with a hole in it is worse than no answer.
  String? expand(String template, String source, Lexicon lexicon) {
    var failed = false;
    var out =
        template.replaceAllMapped(RegExp(r"\$(\d+)(?::([A-Za-z$]+))?"), (m) {
      var n = int.parse(m.group(1)!);
      if (n < 1 || n > groups.length) return m.group(0)!;
      var (a, b) = groups[n - 1];
      if (b <= a) return "";
      var form = m.group(2);
      var written = source.substring(tokens[a].start, tokens[b - 1].end);
      if (form == null) return written;
      var token = tokens[a];
      switch (form) {
        case "Cap":
          return written[0].toUpperCase() + written.substring(1);
        case "NOM":
          return _nominative[token.lower] ?? written;
        case "ACC":
          return _accusative[token.lower] ?? written;
        case "BE":
          return _be[token.lower] ?? "is";
      }
      var tag = Tags.id(form);
      String? made;
      if (tag >= 0) {
        // Its base word, by whichever reading has one that takes this form.
        var bases = <String>{
          token.lemma,
          for (var r in token.entry?.readings ?? const <Reading>[]) r.lemma,
        };
        for (var base in bases) {
          made = lexicon.inflect(base, tag);
          if (made != null) break;
        }
      }
      if (made == null) {
        failed = true;
        return "";
      }
      return made;
    });
    if (failed) return null;
    out = out.replaceAll(RegExp(r" {2,}"), " ").trim();
    // "a(n)" is whichever of the two the next word takes.
    return out.replaceAllMapped(
        RegExp(r"\ba\(n\)(\s+)(\S+)"),
        (m) =>
            "${takesAn(m.group(2)!) ? "an" : "a"}${m.group(1)}${m.group(2)}");
  }
}
