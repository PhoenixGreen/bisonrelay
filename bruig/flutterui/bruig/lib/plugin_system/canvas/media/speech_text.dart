// speech_text.dart readies a script for our own voices: written forms
// said as words, and a pronunciation for every word the voices' dictionary
// does not have.
//
// Kokoro is given sounds, not letters: sherpa-onnx looks each word up in a
// pronouncing dictionary (190,000 British English words) and leaves out any
// it cannot find -- silently, so "Decred" and "2016" were simply not said.
// So, before it speaks:
//
//  - numbers, money, percentages, times, ordinals and a few symbols and
//    abbreviations are written out as words (British: "one hundred and
//    five", "twenty sixteen", "five pounds fifty");
//  - every word still missing is given a pronunciation, in the dictionary's
//    own sounds, in a small dictionary of its own that is read after the
//    main one. In order: an acronym is spelt out by its letters' names; a
//    plural or possessive of a known word is that word and its s; a word
//    with a known word inside it -- "Decred" has "cred" -- is that word
//    and the rest; and what is left is read by the NRL letter-to-sound
//    rules (Elovitz, Johnson, McHugh and Shore, "Automatic Translation of
//    English Text to Phonetics by Means of Letter-to-Sound Rules", NRL
//    Report 7948, 1976: a US Government work, in the public domain),
//    checked against whackintalk's transcription (MIT).

// ---------------------------------------------------------------------------
// Written forms as words
// ---------------------------------------------------------------------------

const _ones = [
  "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", //
  "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
  "sixteen", "seventeen", "eighteen", "nineteen",
];
const _tens = [
  "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", //
  "eighty", "ninety",
];
const _scales = [
  (1000000000000, "trillion"),
  (1000000000, "billion"),
  (1000000, "million"),
  (1000, "thousand"),
];

/// cardinal is [n] in words, as it is said in Britain: "one hundred and
/// five".
String cardinal(int n) {
  if (n < 0) return "minus ${cardinal(-n)}";
  if (n < 20) return _ones[n];
  if (n < 100) {
    return n % 10 == 0 ? _tens[n ~/ 10] : "${_tens[n ~/ 10]} ${_ones[n % 10]}";
  }
  if (n < 1000) {
    var head = "${_ones[n ~/ 100]} hundred";
    return n % 100 == 0 ? head : "$head and ${cardinal(n % 100)}";
  }
  for (var (size, name) in _scales) {
    if (n < size) continue;
    var head = "${cardinal(n ~/ size)} $name";
    var rest = n % size;
    if (rest == 0) return head;
    return rest < 100
        ? "$head and ${cardinal(rest)}"
        : "$head ${cardinal(rest)}";
  }
  return "$n";
}

/// year is [y] as a year is said: "twenty sixteen", "nineteen oh five",
/// "two thousand and nine".
String year(int y) {
  if (y >= 2000 && y < 2010) return cardinal(y);
  var hi = y ~/ 100, lo = y % 100;
  if (lo == 0) return "${cardinal(hi)} hundred";
  return "${cardinal(hi)} ${lo < 10 ? "oh ${_ones[lo]}" : cardinal(lo)}";
}

const _ordinalOf = {
  "one": "first",
  "two": "second",
  "three": "third",
  "five": "fifth",
  "eight": "eighth",
  "nine": "ninth",
  "twelve": "twelfth",
};

/// ordinal is [n] as a place: "twenty first".
String ordinal(int n) {
  var words = cardinal(n).split(" ");
  var last = words.last;
  words[words.length - 1] = _ordinalOf[last] ??
      (last.endsWith("y")
          ? "${last.substring(0, last.length - 1)}ieth"
          : "${last}th");
  return words.join(" ");
}

/// _digits is a string of digits read one at a time.
String _digits(String s) =>
    [for (var c in s.split("")) _ones[int.parse(c)]].join(" ");

/// _number is a written number -- commas and all, a decimal point -- in
/// words.
String _number(String text) {
  var plain = text.replaceAll(",", "");
  var parts = plain.split(".");
  var whole = parts.first;
  String said;
  if (whole.isEmpty) {
    said = "zero";
  } else if (whole.length > 15) {
    said = _digits(whole);
  } else {
    said = cardinal(int.parse(whole));
  }
  if (parts.length > 1 && parts[1].isNotEmpty) {
    said += " point ${_digits(parts[1])}";
  }
  return said;
}

const _money = {
  "£": ("pound", "pounds", "penny", "pence"),
  "\$": ("dollar", "dollars", "cent", "cents"),
  "€": ("euro", "euros", "cent", "cents"),
};

const _abbreviations = {
  "e.g.": "for example",
  "i.e.": "that is",
  "etc.": "et cetera",
  "vs.": "versus",
  "Mr.": "Mister",
  "Mrs.": "Missus",
  "Ms.": "Miz",
  "Dr.": "Doctor",
  "St.": "Saint",
  "No.": "Number",
  "approx.": "approximately",
};

final _numberAt = r"\d[\d,]*(?:\.\d+)?";

/// speakable is [text] with its written forms in words, ready for the
/// voices' dictionary: numbers, money, percentages, times, ordinals,
/// abbreviations whose full stop would end a sentence, and symbols. Quote
/// marks and brackets go, since the dictionary does not know a word with
/// one stuck to it.
String speakable(String text) {
  var s = text
      .replaceAll(RegExp("[‘’ʼ]"), "'")
      .replaceAll(RegExp("[“”„\"]"), " ")
      .replaceAll(RegExp(r"[()\[\]{}<>*_]"), " ")
      .replaceAll("—", ", ")
      .replaceAll(" - ", ", ")
      .replaceAll("…", "...");
  _abbreviations.forEach((k, v) => s = s.replaceAll(k, v));
  // A range of numbers: "2016–2020".
  s = s.replaceAllMapped(
      RegExp("(\\d)\\s*[–-]\\s*(\\d)"), (m) => "${m[1]} to ${m[2]}");
  // Money, with a scale after it: "£5.50", "\$2 million".
  s = s.replaceAllMapped(
      RegExp(
          "([£\$€])($_numberAt)(\\s*(?:thousand|million|billion|trillion|k|m|bn)\\b)?",
          caseSensitive: false), (m) {
    var (one, many, small, smalls) = _money[m[1]]!;
    var amount = m[2]!.replaceAll(",", "");
    var scale = m[3]?.trim().toLowerCase();
    scale = switch (scale) {
      "k" => "thousand",
      "m" => "million",
      "bn" => "billion",
      _ => scale,
    };
    if (scale != null) return " ${_number(amount)} $scale $many ";
    var parts = amount.split(".");
    var whole = int.parse(parts.first.isEmpty ? "0" : parts.first);
    var said = "${cardinal(whole)} ${whole == 1 ? one : many}";
    if (parts.length > 1 && parts[1].isNotEmpty) {
      var cents = int.parse(parts[1].padRight(2, "0").substring(0, 2));
      if (cents > 0) {
        said = whole == 0
            ? "${cardinal(cents)} ${cents == 1 ? small : smalls}"
            : "$said ${cardinal(cents)}";
      }
    }
    return " $said ";
  });
  s = s.replaceAllMapped(
      RegExp("($_numberAt)\\s*%"), (m) => " ${_number(m[1]!)} percent ");
  s = s.replaceAllMapped(
      RegExp(r"\b(\d+)(st|nd|rd|th)\b"), (m) => ordinal(int.parse(m[1]!)));
  s = s.replaceAllMapped(RegExp(r"\b(\d{1,2}):(\d{2})\b"), (m) {
    var h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (min == 0) return "${cardinal(h)} o'clock";
    return "${cardinal(h)} ${min < 10 ? "oh ${_ones[min]}" : cardinal(min)}";
  });
  // A year: four digits on their own, from 1100 to 2099.
  s = s.replaceAllMapped(
      RegExp(r"(?<![\d,.])(1[1-9]\d\d|20\d\d)(?![\d,]|\.\d)"),
      (m) => year(int.parse(m[1]!)));
  s = s.replaceAllMapped(RegExp(_numberAt), (m) {
    var text = m[0]!;
    // A full stop after a number ends a sentence, not the number.
    var trailing = text.endsWith(".") ? "." : "";
    if (trailing.isNotEmpty) text = text.substring(0, text.length - 1);
    return " ${_number(text)}$trailing ";
  });
  s = s
      .replaceAll("&", " and ")
      .replaceAll("@", " at ")
      .replaceAll("+", " plus ")
      .replaceAll("=", " equals ")
      .replaceAll("~", " about ")
      .replaceAll("#", " number ")
      .replaceAll("/", " ");
  return s
      .replaceAll(RegExp(r"[ \t]+"), " ")
      .replaceAllMapped(RegExp(r" ([,.!?;:])"), (m) => m[1]!)
      .trim();
}

/// spacedChinese is Chinese [text] with a space between its Chinese and
/// any letters or numbers beside it: the dictionary is asked for a word at
/// a time, and "到Decred" would be asked for as one.
String spacedChinese(String text) => text
    .replaceAllMapped(
        RegExp("([\u3400-\u9fff])([A-Za-z0-9])"), (m) => "${m[1]} ${m[2]}")
    .replaceAllMapped(
        RegExp("([A-Za-z0-9])([\u3400-\u9fff])"), (m) => "${m[1]} ${m[2]}");

// ---------------------------------------------------------------------------
// Pronouncing what the dictionary does not have
// ---------------------------------------------------------------------------

/// wordsOf are the words in [text] as the voices' dictionary is asked for
/// them: split at spaces, sentence punctuation -- Chinese too -- and
/// hyphens, with any quote mark at their ends taken off.
List<String> wordsOf(String text) => [
      for (var w in text.split(
          RegExp("[\\s,.!?;:\\-\u3001\u3002\uff01\uff0c\uff1a\uff1b\uff1f]+")))
        if (w.replaceAll(RegExp(r"^'+|'+$"), "") case var word
            when word.isNotEmpty)
          word,
    ];

/// readLexicon is a pronouncing dictionary's text: a word a line, then its
/// sounds, each separated by spaces.
Map<String, String> readLexicon(String text) {
  var out = <String, String>{};
  for (var line in text.split("\n")) {
    var at = line.indexOf(" ");
    if (at <= 0) continue;
    out.putIfAbsent(line.substring(0, at), () => line.substring(at + 1).trim());
  }
  return out;
}

/// missingWords are the pronunciations for the words in [text] that
/// [lexicon] does not have -- a word and its sounds, as a line of a
/// dictionary would be. [american]: as an American says them.
Map<String, String> missingWords(String text, Map<String, String> lexicon,
    {bool american = false}) {
  var out = <String, String>{};
  for (var word in wordsOf(text)) {
    var key = word.toLowerCase();
    if (lexicon.containsKey(key) || out.containsKey(key)) continue;
    var sounds = pronounce(word, lexicon, american: american);
    if (sounds != null && sounds.isNotEmpty) out[key] = sounds;
  }
  return out;
}

const _vowelLetters = "aeiouy";

/// pronounce is [word]'s sounds, in [lexicon]'s own: see the note at the
/// top for the order things are tried in. Null where nothing can be said.
String? pronounce(String word, Map<String, String> lexicon,
    {bool american = false}) {
  var w = word.toLowerCase();
  if (lexicon[w] case var known?) return known;
  var letters = w.replaceAll(RegExp(r"[^a-z']"), "");
  if (letters.isEmpty) return null;
  // An acronym: in capitals and short, or with no vowel to say.
  var bare = letters.replaceAll("'", "");
  var capitals = word.replaceAll(RegExp(r"[^A-Za-z]"), "");
  var acronym = (capitals.length >= 2 &&
          capitals.length <= 5 &&
          capitals == capitals.toUpperCase()) ||
      (bare.length <= 5 && !bare.split("").any(_vowelLetters.contains));
  if (acronym) {
    var names = [for (var c in bare.split("")) lexicon[c]];
    if (names.every((n) => n != null)) return names.join(" ");
  }
  // A plural or a possessive of a word it knows.
  for (var (end, keep) in [
    ("'s", 0),
    ("s'", 0),
    ("'", 0),
    ("es", 0),
    ("s", 0)
  ]) {
    if (!letters.endsWith(end) || letters.length <= end.length + 1) continue;
    var base = letters.substring(0, letters.length - end.length + keep);
    if (lexicon[base] case var sounds?) return "$sounds ${_plural(sounds)}";
  }
  // A word it knows inside it, at its start or its end, and the rest read
  // by the rules -- the longest known piece; or two known words.
  String? best;
  var bestLength = 0;
  for (var cut = 1; cut < bare.length; cut++) {
    var head = bare.substring(0, cut), tail = bare.substring(cut);
    var headKnown = head.length >= 3 ? lexicon[head] : null;
    var tailKnown = tail.length >= 3 ? lexicon[tail] : null;
    if (headKnown != null && tailKnown != null) {
      // A compound: the second word's stress made the lesser.
      return "$headKnown ${tailKnown.replaceAll("ˈ", "ˌ")}";
    }
    if (tailKnown != null && tail.length > bestLength) {
      best =
          "${_ruleSounds(head, stressed: false, endsWord: false, american: american)} "
          "$tailKnown";
      bestLength = tail.length;
    }
    if (headKnown != null && head.length > bestLength) {
      best =
          "$headKnown ${_ruleSounds(tail, stressed: false, american: american)}";
      bestLength = head.length;
    }
  }
  if (best != null && bestLength * 2 >= bare.length) return best.trim();
  return _ruleSounds(bare, stressed: true, american: american);
}

/// _plural is the s on the end of a word ending in [sounds]: "iz" after a
/// hiss, "s" after a voiceless sound, "z" otherwise.
String _plural(String sounds) {
  var last = sounds.split(" ").last;
  if (const {"s", "z", "ʃ", "ʒ", "ʧ", "ʤ"}.contains(last)) return "ɪ z";
  if (const {"p", "t", "k", "f", "θ"}.contains(last)) return "s";
  return "z";
}

// ---- the NRL rules

/// _Rule is one rule: [match] said as [out] where the letters before it fit
/// [left] and those after it [right].
typedef _Rule = ({String left, String match, String right, List<String> out});

const _ruleText = <String>[
  // A
  " [ARE] =AA R", " [AR]O=AX R", "[AR]#=EH R", " ^[AS]#=EY S", "[A]WA=AX",
  "[AW]=AO", " :[ANY]=EH N IY", "[A]^+#=EY", "#:[ALLY]=AX L IY",
  " [AL]#=AX L", "[AGAIN]=AX G EH N", "#:[AG]E=IH JH", "[A]^%=EY",
  "[A]^+:#=AE", " :[A]^+ =EY", " [ARR]=AX R", "[ARR]=AE R", " ^[AR] =AA R",
  "[AR]=AA R", "[AIR]=EH R", "[AI]=EY", "[AY]=EY", "[AU]=AO", "#:[AL] =AX L",
  "#:[ALS] =AX L Z", "[ALK]=AO K", "[AL]^=AO L", " :[ABLE]=EY B AX L",
  "[ABLE]=AX B AX L", "[ANG]+=EY N JH", "[A]=AE",
  // B
  " [BE]^#=B IH", "[BEING]=B IY IH NG", " [BOTH] =B OW TH", " [BUS]#=B IH Z",
  "[BUIL]=B IH L", "[B]=B",
  // C
  " [CH]^=K", "^E[CH]=K", "[CH]=CH", " S[CI]#=S AY", "[CI]A=SH", "[CI]O=SH",
  "[CI]EN=SH", "[C]+=S", "[CK]=K", "[COM]%=K AH M", "[C]=K",
  // D
  "#:[DED] =D IH D", ".E[D] =D", "#:^E[D] =T", " [DE]^#=D IH", " [DO] =D UW",
  " [DOES]=D AH Z", " [DOING]=D UW IH NG", " [DOW]=D AW", "[DU]A=JH UW",
  "[D]=D",
  // E
  "#:[E] =", "'^:[E] =", " :[E] =IY", "#[ED] =D", "#:[E]D =", "[EV]ER=EH V",
  "[E]^%=IY", "[ERI]#=IY R IY", "[ERI]=EH R IH", "#:[ER]#=ER", "[ER]#=EH R",
  "[ER]=ER", " [EVEN]=IY V EH N", "#:[E]W=", "@[EW]=UW", "[EW]=Y UW",
  "[E]O=IY", "#:&[ES] =IH Z", "#:[E]S =", "#:[ELY] =L IY",
  "#:[EMENT]=M EH N T", "[EFUL]=F UH L", "[EE]=IY", "[EARN]=ER N",
  " [EAR]^=ER", "[EAD]=EH D", "#:[EA] =IY AX", "[EA]SU=EH", "[EA]=IY",
  "[EIGH]=EY", "[EI]=IY", " [EYE]=AY", "[EY]=IY", "[EU]=Y UW", "[E]=EH",
  // F
  "[FUL]=F UH L", "[F]=F",
  // G
  "[GIV]=G IH V", " [G]I^=G", "[GE]T=G EH", "SU[GGES]=G JH EH S", "[GG]=G",
  " B#[G]=G", "[G]+=JH", "[GREAT]=G R EY T", "#[GH]=", "[G]=G",
  // H
  " [HAV]=HH AE V", " [HERE]=HH IY R", " [HOUR]=AW ER", "[HOW]=HH AW",
  "[H]#=HH", "[H]=",
  // I
  " [IN]=IH N", " [I] =AY", "[IN]D=AY N", "[IER]=IY ER", "#:R[IED] =IY D",
  "[IED] =AY D", "[IEN]=IY EH N", "[IE]T=AY EH", " :[I]%=AY", "[I]%=IY",
  "[IE]=IY", "[I]^+:#=IH", "[IR]#=AY R", "[IZ]%=AY Z", "[IS]%=AY Z",
  "[I]D%=AY", "+^[I]^+=IH", "[I]T%=AY", "#:^[I]^+=IH", "[I]^+=AY",
  "[IR]=ER", "[IGH]=AY", "[ILD]=AY L D", "[IGN] =AY N", "[IGN]^=AY N",
  "[IGN]%=AY N", "[IQUE]=IY K", "[I]=IH",
  // J, K, L, M
  "[J]=JH", " [K]N=", "[K]=K", "[LO]C#=L OW", "L[L]=", "#:^[L]%=AX L",
  "[LEAD]=L IY D", "[L]=L", "[MOV]=M UW V", "[M]=M",
  // N
  "E[NG]+=N JH", "[NG]R=NG G", "[NG]#=NG G", "[NGL]%=NG G AX L", "[NG]=NG",
  "[NK]=NG K", " [NOW] =N AW", "[N]=N",
  // O
  "[OF] =AX V", "[OROUGH]=ER OW", "#:[OR] =ER", "#:[ORS] =ER Z", "[OR]=AO R",
  " [ONE]=W AH N", "[OW]=OW", " [OVER]=OW V ER", "[OV]=AH V", "[O]^%=OW",
  "[O]^EN=OW", "[O]^I#=OW", "[OL]D=OW L", "[OUGHT]=AO T", "[OUGH]=AH F",
  " [OU]=AW", "H[OU]S#=AW", "[OUS]=AX S", "[OUR]=AO R", "[OULD]=UH D",
  "^[OU]^L=AH", "[OUP]=UW P", "[OU]=AW", "[OY]=OY", "[OING]=OW IH NG",
  "[OI]=OY", "[OOR]=AO R", "[OOK]=UH K", "[OOD]=UH D", "[OO]=UW", "[O]E=OW",
  "[O] =OW", "[OA]=OW", " [ONLY]=OW N L IY", " [ONCE]=W AH N S",
  "[ON'T]=OW N T", "C[O]N=AA", "[O]NG=AO", " :^[O]N=AH", "I[ON]=AX N",
  "#:[ON] =AX N", "#^[ON]=AX N", "[O]ST =OW", "[OF]^=AO F",
  "[OTHER]=AH DH ER", "[OSS] =AO S", "#^:[OM]=AH M", "[O]=AA",
  // P, Q, R
  "[PH]=F", "[PEOP]=P IY P", "[POW]=P AW", "[PUT] =P UH T", "[P]=P",
  "[QUAR]=K W AO R", "[QU]=K W", "[Q]=K", " [RE]^#=R IY", "[R]=R",
  // S
  "[SH]=SH", "#[SION]=ZH AX N", "[SOME]=S AH M", "#[SUR]#=ZH ER",
  "[SUR]#=SH ER", "#[SU]#=ZH UW", "#[SSU]#=SH UW", "#[SED] =Z D",
  "#[S]#=Z", "[SAID]=S EH D", "^[SION]=SH AX N", "[S]S=", ".[S] =Z",
  "#:.E[S] =Z", "#:^##[S] =Z", "#:^#[S] =S", "U[S] =S", " :#[S] =Z",
  " [SCH]=S K", "[S]C+=", "#[SM]=Z M", "#[SN]'=Z AX N", "[S]=S",
  // T
  " [THE] =DH AX", "[TO] =T UW", "[THAT] =DH AE T", " [THIS] =DH IH S",
  " [THEY]=DH EY", " [THERE]=DH EH R", "[THER]=DH ER", "[THEIR]=DH EH R",
  " [THAN] =DH AE N", " [THEM] =DH EH M", "[THESE] =DH IY Z",
  " [THEN]=DH EH N", "[THROUGH]=TH R UW", "[THOSE]=DH OW Z",
  "[THOUGH] =DH OW", " [THUS]=DH AH S", "[TH]=TH", "#:[TED] =T IH D",
  "S[TI]#N=CH", "[TI]O=SH", "[TI]A=SH", "[TIEN]=SH AX N", "[TUR]#=CH ER",
  "[TU]A=CH UW", " [TWO]=T UW", "[T]=T",
  // U
  " [UN]I=Y UW N", " [UN]=AH N", " [UPON]=AX P AO N", "@[UR]#=UH R",
  "[UR]#=Y UH R", "[UR]=ER", "[U]^ =AH", "[U]^^=AH", "[UY]=AY", " G[U]#=",
  "G[U]%=W", "G[U]#=W", "#N[U]=Y UW", "@[U]=UW", "[U]=Y UW",
  // V, W, X, Y, Z
  "[VIEW]=V Y UW", "[V]=V", " [WERE]=W ER", "[WA]S=W AA", "[WA]T=W AA",
  "[WHERE]=W EH R", "[WHAT]=W AA T", "[WHOL]=HH OW L", "[WHO]=HH UW",
  "[WH]=W", "[WAR]=W AO R", "[WOR]^=W ER", "[WR]=R", "[W]=W", " [X]=Z",
  "[X]=K S", "[YOUNG]=Y AH NG", " [YOU]=Y UW", " [YES]=Y EH S", " [Y]=Y",
  "#^:[Y] =IY", "#^:[Y]I=IY", " :[Y] =AY", " :[Y]#=AY", " :[Y]^+:#=IH",
  " :[Y]^#=AY", "[Y]=IH", "[Z]=Z",
];

final Map<String, List<_Rule>> _rules = () {
  var out = <String, List<_Rule>>{};
  var form = RegExp(r"^(.*?)\[(.*?)\](.*?)=(.*)$");
  for (var line in _ruleText) {
    var m = form.firstMatch(line)!;
    var said = m[4]!.trim();
    var rule = (
      left: m[1]!,
      match: m[2]!,
      right: m[3]!,
      out: said.isEmpty ? const <String>[] : said.split(" "),
    );
    out.putIfAbsent(rule.match[0], () => []).add(rule);
  }
  return out;
}();

const _vowels = "AEIOUY";
const _consonants = "BCDFGHJKLMNPQRSTVWXZ";
const _voiced = "BDVGJLMNRWZ";
const _front = "EIY";
const _sibilants = ["S", "C", "G", "Z", "X", "J", "CH", "SH"];
const _palatal = ["T", "S", "R", "D", "L", "Z", "N", "J", "TH", "CH", "SH"];
const _suffixes = ["ER", "E", "ES", "ED", "ING", "ELY"];

/// _fits is whether the letters of [text] from [at], going the way of
/// [step], fit [pattern] -- read the same way. See the rules' signs: #
/// vowels, : any consonants, ^ a consonant, . a voiced one, + a front
/// vowel, & a hiss, @ a consonant before a long u, % a suffix.
bool _fits(String text, int at, String pattern, int step) {
  var t = at;
  bool inside(int i) => i >= 0 && i < text.length;
  bool pair(List<String> set) {
    var two = step > 0
        ? (t + 2 <= text.length ? text.substring(t, t + 2) : "")
        : (t >= 1 ? text.substring(t - 1, t + 1) : "");
    if (set.contains(two)) {
      t += 2 * step;
      return true;
    }
    if (inside(t) && set.contains(text[t])) {
      t += step;
      return true;
    }
    return false;
  }

  var signs = step > 0 ? pattern.split("") : pattern.split("").reversed;
  for (var c in signs) {
    switch (c) {
      case "#":
        if (!inside(t) || !_vowels.contains(text[t])) return false;
        while (inside(t) && _vowels.contains(text[t])) {
          t += step;
        }
      case ":":
        while (inside(t) && _consonants.contains(text[t])) {
          t += step;
        }
      case "^":
        if (!inside(t) || !_consonants.contains(text[t])) return false;
        t += step;
      case ".":
        if (!inside(t) || !_voiced.contains(text[t])) return false;
        t += step;
      case "+":
        if (!inside(t) || !_front.contains(text[t])) return false;
        t += step;
      case "&":
        if (!pair(_sibilants)) return false;
      case "@":
        if (!pair(_palatal)) return false;
      case "%":
        var rest = text.substring(t);
        var suffix = _suffixes.where(rest.startsWith).firstOrNull;
        if (suffix == null) return false;
        t += suffix.length;
      default:
        if (!inside(t) || text[t] != c) return false;
        t += step;
    }
  }
  return true;
}

/// rulePhones is [word] by the NRL rules: ARPAbet, without stress.
List<String> rulePhones(String word) {
  var text = " ${word.toUpperCase().replaceAll(RegExp(r"[^A-Z']"), "")} ";
  var out = <String>[];
  var i = 1;
  while (i < text.length - 1) {
    var applied = false;
    for (var rule in _rules[text[i]] ?? const <_Rule>[]) {
      if (!text.startsWith(rule.match, i)) continue;
      if (!_fits(text, i - 1, rule.left, -1)) continue;
      if (!_fits(text, i + rule.match.length, rule.right, 1)) continue;
      out.addAll(rule.out);
      i += rule.match.length;
      applied = true;
      break;
    }
    if (!applied) i++;
  }
  return out;
}

const _arpaVowels = {
  "AA", "AE", "AH", "AO", "AW", "AX", "AY", "EH", "ER", "EY", "IH", "IY", //
  "OW", "OY", "UH", "UW",
};

const _consonantSounds = {
  "B": "b", "CH": "ʧ", "D": "d", "DH": "ð", "F": "f", "G": "ɡ", "HH": "h", //
  "JH": "ʤ", "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ", "P": "p",
  "R": "ɹ", "S": "s", "SH": "ʃ", "T": "t", "TH": "θ", "V": "v", "W": "w",
  "Y": "j", "Z": "z", "ZH": "ʒ",
};

/// _ruleSounds is [word] by the rules, in the voices' British sounds: no r
/// unless a vowel follows it, the vowel before it longer instead. With
/// [stressed], the first full vowel is stressed -- after an unstressed
/// prefix -- as a word of its own; without, none is, as part of a word.
/// [endsWord] is whether it is the end of the word, where a last "ee" is
/// said short. [american]: every r said, in the American dictionary's own
/// vowels.
String _ruleSounds(String word,
    {required bool stressed, bool endsWord = true, bool american = false}) {
  var phones = rulePhones(word);
  var vowelsAt = [
    for (var (i, p) in phones.indexed)
      if (_arpaVowels.contains(p)) i
  ];
  var primary = -1;
  if (stressed && vowelsAt.isNotEmpty) {
    var prefix = RegExp(
        r"^(a|be|de|re|in|un|con|com|ex|pre|pro|per|sur|to)(?=[a-z]{3})");
    primary = vowelsAt.length > 1 && prefix.hasMatch(word)
        ? vowelsAt[1]
        : vowelsAt[0];
  }
  var out = <String>[];
  for (var i = 0; i < phones.length; i++) {
    var p = phones[i];
    if (!_arpaVowels.contains(p)) {
      out.add(_consonantSounds[p] ?? "");
      continue;
    }
    var stress = i == primary;
    if (american) {
      var sound = switch (p) {
        "AA" => "ɑ",
        "AE" => "æ",
        "AH" => "ʌ",
        "AO" => "ɔ",
        "AW" => "W",
        "AX" => "ə",
        "AY" => "I",
        "EH" => "ɛ",
        "ER" => stress ? "ɜ ɹ" : "ə ɹ",
        "EY" => "A",
        "IH" => "ɪ",
        "IY" => "i",
        "OW" => "O",
        "OY" => "Y",
        "UH" => "ʊ",
        _ => "u", // UW
      };
      out.add(stress ? "ˈ $sound" : sound);
      continue;
    }
    // An r after a vowel, with no vowel after it, is not said in British.
    var next = i + 1 < phones.length ? phones[i + 1] : null;
    var after = i + 2 < phones.length ? phones[i + 2] : null;
    var silentR =
        next == "R" && (after == null || !_arpaVowels.contains(after));
    var last = endsWord && i == phones.length - 1;
    var sound = switch (p) {
      "AA" => silentR ? "ɑ ː" : "ɒ",
      "AE" => silentR ? "ɑ ː" : "a",
      "AH" => "ʌ",
      "AO" => "ɔ ː",
      "AW" => "W",
      "AX" => "ə",
      "AY" => silentR ? "I ə" : "I",
      "EH" => silentR ? "ɛ ː" : "ɛ",
      "ER" => stress ? "ɜ ː" : "ə",
      "EY" => silentR ? "ɛ ː" : "A",
      "IH" => silentR ? "ɪ ə" : "ɪ",
      "IY" => silentR ? "ɪ ə" : (stress || !last ? "i ː" : "i"),
      "OW" => silentR ? "ɔ ː" : "Q",
      "OY" => "Y",
      "UH" => silentR ? "ʊ ə" : "ʊ",
      _ => silentR ? "ʊ ə" : "u ː", // UW
    };
    out.add(stress ? "ˈ $sound" : sound);
    if (silentR) i++;
  }
  return out.where((s) => s.isNotEmpty).join(" ");
}
