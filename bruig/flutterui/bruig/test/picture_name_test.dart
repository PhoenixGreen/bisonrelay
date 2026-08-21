import 'package:bruig/components/pages/add_picture_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

// picture_name_test.dart covers what a picture added to a site gets called.
//
// A page reaches one by writing ![](assets/name.jpg), and a Markdown link
// stops at the first space. Files arrive named the way people and cameras
// name them -- "Decred - Open Source in the AI Era.jpg" -- and that one
// would be written, listed and served perfectly while the page showed
// nothing, because the link ended at "Decred".

void main() {
  group('making a name a page can link to', () {
    test('spaces become one dash', () {
      expect(slugFileName("Decred - Open Source in the AI Era"),
          "decred-open-source-in-the-ai-era");
    });

    test('a run of punctuation does not become a run of dashes', () {
      expect(slugFileName("a  --  b"), "a-b");
    });

    test('brackets, quotes and the rest go', () {
      // Every one of these ends or confuses a Markdown link.
      expect(slugFileName("banner (1)"), "banner-1");
      expect(slugFileName("it's mine"), "it-s-mine");
      expect(slugFileName('say "hi"'), "say-hi");
      expect(slugFileName("<banner>"), "banner");
    });

    test('it does not start or end with a dash or a dot', () {
      // A leading dot would be a hidden file, which the name check refuses.
      expect(slugFileName(" banner "), "banner");
      expect(slugFileName(".banner."), "banner");
      expect(slugFileName("---banner---"), "banner");
    });

    test('lowercased', () {
      // Two files differing only in capitals are the same file on a Mac and
      // different ones on Linux. A site whose pictures appear only for its
      // author is a hard thing to work out from the outside.
      expect(slugFileName("Banner"), "banner");
    });

    test('an ordinary name is left alone', () {
      expect(slugFileName("banner-2"), "banner-2");
      expect(slugFileName("banner_2"), "banner_2");
      expect(slugFileName("logo.dark"), "logo.dark");
    });

    test('a name with nothing usable in it still gets one', () {
      // Real: a name that is all punctuation, or all in a script with no
      // ASCII in it. Neither is a reason to refuse the picture.
      expect(slugFileName("!!!"), "picture");
      expect(slugFileName(""), "picture");
      expect(slugFileName("日本語"), "picture");
    });

    test('what comes out is always something a page can link to', () {
      // The property the whole thing exists for, checked over the awkward
      // cases at once rather than trusted one example at a time.
      for (var name in [
        "Decred - Open Source in the AI Era",
        "banner (1)",
        "it's mine",
        '  spaced  out  ',
        "!!!",
        "..",
        "a\tb",
      ]) {
        var got = slugFileName(name);
        expect(got, isNotEmpty, reason: name);
        expect(RegExp(r"^[a-z0-9._-]+$").hasMatch(got), isTrue, reason: name);
        expect(got.startsWith("."), isFalse, reason: name);
      }
    });
  });
}
