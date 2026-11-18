import 'package:bruig/plugin_system/writing_tools/engine/checker.dart';
import 'package:bruig/plugin_system/writing_tools/engine/text_segments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// writing_not_prose_test.dart covers what the checker leaves alone: links,
// file names, embeds, HTML and code.
//
// None of it is the writer's spelling to correct, and all of it is full of
// what the checks look for. A shared file used to arrive in a post as a line
// of red: "https" misspelled, a missing space after every full stop in the
// address, "png" not a word.

const _dictionary = [
  "here", "is", "the", "file", "for", "you", "read", "docs", "at", "and", //
  "today", "see", "release", "notes", "details", "email", "me", "or", "open",
  "first", "run", "then", "check", "invoice", "a", "picture", "site", "are",
  "both", "up", "my", "cat", "it", "works", "this", "that", "of", "time",
  "i", "like", "dislike", "one", "two", "three", "four", "sentence", "long",
];

/// The two rules that fired on every address: a missing space after a full
/// stop or a comma.
final _rules = [
  GrammarRule(r"(?<=\w\w)([.!?])(?=[A-Za-z])",
      "Missing space after punctuation", r"$1 ", "Punctuation"),
  GrammarRule(r"([,;:])([A-Za-z])", "Missing space after punctuation", r"$1 $2",
      "Punctuation"),
];

WritingChecker _checker() =>
    WritingChecker()..updateData(SpellcheckData(_dictionary, const [], _rules));

List<String> _marked(String text) =>
    [for (var issue in _checker().review(text)) issue.text];

void main() {
  test("a link is not checked, wherever it is written", () {
    expect(
        _marked(
            "Read the docs at https://docs.decred.org/getting-started/ today"),
        isEmpty);
    expect(_marked("Read the docs at www.bisonrelay.org today"), isEmpty);
    expect(
        _marked(
            "The site decred.org and dcrdata.decred.org/tx/abc123 are both up"),
        isEmpty);
    expect(_marked("Email me at ken.cameron@example.com today"), isEmpty);
    expect(_marked("Check lnpay://lnbc1pvjluezpp5qqqsyq for the invoice"),
        isEmpty);
    expect(_marked("See <https://example.com/a,b.c> for details"), isEmpty);
  });

  test("a link's text is still the writer's, and still checked", () {
    expect(
        _marked(
            "See [the relase notes](https://github.com/x/y,z.w) for details"),
        ["relase"]);
    expect(
        _marked("![a picture](https://example.com/cat-photo_01.jpg)"), isEmpty);
  });

  test("the full stop that ends a sentence is not part of the address", () {
    var spans = notProseSpans("See https://decred.org/docs.");
    expect(
        "See https://decred.org/docs."
            .substring(spans.single.start, spans.single.end),
        "https://decred.org/docs");
  });

  test("a shared file and a picture are not checked", () {
    expect(
        _marked("Here is the file "
            "--embed[download=a3f9c2e1b7d04455aa01,alt=quarterly%20report.pdf]-- for you"),
        isEmpty);
    expect(
        _marked("--embed[type=image/png,alt=My%20cat,data=[content 7f3a]]--"),
        isEmpty);
    // One still being typed.
    expect(_marked("Here is the file --embed[type=image/png,alt=My"), isEmpty);
    expect(_marked("--grid[2]--\nmy cat\n--/grid--"), isEmpty);
  });

  test("file names and paths are not checked", () {
    expect(
        _marked("Open main.dart and ~/Documents/notes/todo.md first"), isEmpty);
    expect(_marked("Open /usr/local/bin/dcrd or lib/src/checker.dart first"),
        isEmpty);
    expect(_marked("Open report.final.pdf first"), isEmpty);
  });

  test("code and HTML are not checked", () {
    expect(_marked("Run `flutter pub get,now` and then check it"), isEmpty);
    expect(_marked('<img src="cat.png" width="200">'), isEmpty);
    expect(
        _marked(
            "Run this\n\n```\nflutter pub get\n\nflutter biuld,now\n```\n\nthen check it"),
        isEmpty,
        reason: "a block of code has blank lines in it and is still one block");
  });

  test("what is beside them is still checked", () {
    expect(_marked("Opne main.dart first"), ["Opne"]);
    expect(_marked("Read teh docs at https://decred.org today"), ["teh"]);
    expect(_marked("I like and/or dislike it"), isEmpty,
        reason: "one slash is a word and another word, not a path");
    expect(_marked("I like it,and you"), [",a"],
        reason: "a comma against a letter in plain prose is still a slip");
  });

  test("a finding that only contains a link is kept", () {
    var spans = notProseSpans("one two https://x.org three four");
    // Inside the address, and with an end in it: about the address.
    expect(inNotProse(spans, 10, 14), isTrue);
    expect(inNotProse(spans, 4, 12), isTrue);
    // The whole sentence, address and all: about the sentence.
    expect(inNotProse(spans, 0, 32), isFalse);
    expect(inNotProse(spans, 0, 7), isFalse);
  });
}
