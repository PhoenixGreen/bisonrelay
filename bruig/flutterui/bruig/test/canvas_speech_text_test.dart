import 'dart:io';

import 'package:bruig/plugin_system/canvas/media/speech_text.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_speech_text_test.dart is a script readied for our own voices:
// written forms said as words, and the words their dictionary lacks given
// sounds -- which before were left out, unsaid.

/// lexicon is a few words of the voices' own dictionary, in its sounds.
const lexicon = {
  "cred": "k ɹ ˈ ɛ d",
  "red": "ɹ ˈ ɛ d",
  "block": "b l ˈ ɒ k",
  "chain": "ʧ ˈ A n",
  "coin": "k ˈ Y n",
  "d": "d ˈ i ː",
  "c": "s ˈ i ː",
  "r": "ˈ ɑ ː",
  "dog": "d ˈ ɒ ɡ",
  "bus": "b ˈ ʌ s",
};

void main() {
  test("numbers are said as they are in Britain", () {
    expect(cardinal(105), "one hundred and five");
    expect(cardinal(2021), "two thousand and twenty one");
    expect(cardinal(1500000), "one million five hundred thousand");
    expect(year(2016), "twenty sixteen");
    expect(year(1905), "nineteen oh five");
    expect(year(2008), "two thousand and eight");
    expect(year(1900), "nineteen hundred");
    expect(ordinal(21), "twenty first");
    expect(ordinal(40), "fortieth");
  });

  test("written forms are words", () {
    expect(speakable("It launched in 2016."), "It launched in twenty sixteen.");
    expect(speakable("It costs £5.50, or \$2 million."),
        "It costs five pounds fifty, or two million dollars.");
    expect(speakable("Up 12.5% at 10:30 on the 3rd."),
        "Up twelve point five percent at ten thirty on the third.");
    expect(speakable("1,250 holders"),
        "one thousand two hundred and fifty holders");
    expect(speakable("Mr. Smith, e.g. him & her"),
        "Mister Smith, for example him and her");
    expect(speakable("“Quoted” (aside) 2016–2020"),
        "Quoted aside twenty sixteen to twenty twenty");
  });

  test("words are asked for as the dictionary is", () {
    expect(wordsOf(spacedChinese("欢迎来到Decred。")), ["欢迎来到", "Decred"]);
    expect(wordsOf("Decred's well-known, \"quoted\" 'words'."),
        ["Decred's", "well", "known", "\"quoted\"", "words"]);
  });

  test("a word it lacks is given sounds, from what it knows first", () {
    // A known word inside it, the rest by the rules.
    expect(pronounce("Decred", lexicon), "d i ː k ɹ ˈ ɛ d");
    // Two known words: the second's stress the lesser.
    expect(pronounce("blockchain", lexicon), "b l ˈ ɒ k ʧ ˌ A n");
    // An acronym, by its letters' names.
    expect(pronounce("DCR", lexicon), "d ˈ i ː s ˈ i ː ˈ ɑ ː");
    // A plural or a possessive.
    expect(pronounce("dogs", lexicon), "d ˈ ɒ ɡ z");
    expect(pronounce("bus's", lexicon), "b ˈ ʌ s ɪ z");
    // Nothing known: the rules, stressed, with no r before a consonant.
    expect(pronounce("farm", lexicon), "f ˈ ɑ ː m");
    // As an American says it: the r said.
    expect(pronounce("farm", lexicon, american: true), "f ˈ ɑ ɹ m");
    expect(pronounce("zorbit", const {}), startsWith("z ˈ ɔ ː b"));
    var missing = missingWords("Decred and its 2016 blockchain", {
      ...lexicon,
      "and": "a n d",
      "its": "ɪ t s",
    });
    // A number has no sounds: it is made words before this is asked.
    expect(missing.keys, ["decred", "blockchain"]);
  });

  test("every word of a real script has sounds, with the real dictionary", () {
    var dir = Platform.environment["CANVAS_KOKORO"];
    if (dir == null) {
      markTestSkipped("no Kokoro model to hand");
      return;
    }
    var real = readLexicon(File("$dir/lexicon-gb-en.txt").readAsStringSync());
    var text = speakable("Hello, this is a story about how awesome Decred is. "
        "It launched in February 2016; DCR holders vote on Politeia "
        "proposals, and the treasury paid £1.2 million.");
    var missing = missingWords(text, real);
    expect(missing.keys, containsAll(["decred", "dcr"]));
    for (var sounds in missing.values) {
      expect(sounds.trim(), isNotEmpty);
    }
    // Every sound is one the voices know.
    var tokens = File("$dir/tokens.txt")
        .readAsLinesSync()
        .map((l) => l.substring(0, l.lastIndexOf(" ")))
        .toSet();
    for (var MapEntry(:key, :value) in missing.entries) {
      for (var t in value.split(" ")) {
        expect(tokens, contains(t), reason: "$key: $value");
      }
    }
    for (var w in wordsOf(text)) {
      expect(
          real.containsKey(w.toLowerCase()) ||
              missing.containsKey(w.toLowerCase()),
          isTrue,
          reason: w);
    }
  });
}
