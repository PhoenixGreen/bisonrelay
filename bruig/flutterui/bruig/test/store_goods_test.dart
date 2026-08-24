import 'package:bruig/models/store_goods.dart';
import 'package:flutter_test/flutter_test.dart';

// store_goods_test.dart covers the name a library document takes when it
// becomes the file a product sends.
//
// It becomes a file on a buyer's machine, so it is named the way a file is
// named rather than the way a document is: "My Guide" arrives as
// my-guide.md, not as something with a space in it their downloads folder
// has to cope with -- the same reasoning as a site's pictures.

void main() {
  group('what a document is called once it is sold', () {
    test('is its own name, as a file name', () {
      // Through pageSlug, so a document becomes a file by the same rule
      // whether it is being published as a page or sold as a download. A
      // second rule here would mean two answers to one question.
      expect(goodNameFor("My Guide"), "my_guide.md");
    });

    test('always ends in .md, because that is what it is', () {
      expect(goodNameFor("Notes"), "notes.md");
      // Not notes.md.md: the document's name is a name, not a file.
      expect(goodNameFor("Notes.md"), isNot(endsWith(".md.md")));
    });

    test('a name with punctuation still makes one word', () {
      expect(goodNameFor("Chapter 1: Beginnings"), isNot(contains(" ")));
      expect(goodNameFor("Chapter 1: Beginnings"), endsWith(".md"));
    });

    test('two documents that differ keep differing', () {
      // Slugging collapses characters, so it is worth knowing it does not
      // collapse two real documents onto one file.
      expect(goodNameFor("Part One"), isNot(goodNameFor("Part Two")));
    });
  });
}
