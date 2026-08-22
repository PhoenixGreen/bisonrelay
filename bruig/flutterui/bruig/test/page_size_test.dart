import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:flutter_test/flutter_test.dart';

// page_size_test.dart covers what a page is reported to cost.
//
// A post carries its pictures inside it, so its size says everything. A page
// does not -- the pictures are files of the site's own, fetched separately --
// so the page's own size says half of it, and the half it leaves out is the
// larger one. A 90 KB photograph on an 814 B page reads as free.

void main() {
  const sizes = {
    "assets/banner.jpg": 90000,
    "assets/logo.png": 2000,
    "assets/unused.png": 500000,
  };

  group('what the pictures on a page cost', () {
    test('nothing, for a page with none', () {
      expect(picturesNamedIn("# Just words", sizes), 0);
    });

    test('the picture it shows', () {
      expect(picturesNamedIn("![](assets/banner.jpg)", sizes), 90000);
    });

    test('added up over several', () {
      expect(
          picturesNamedIn(
              "![](assets/banner.jpg)\n![](assets/logo.png)", sizes),
          92000);
    });

    test('one shown twice is paid for once', () {
      // What a reader actually pays: a banner at the top and again at the
      // foot is one file, fetched one time. Counting it twice would
      // overstate the page in exactly the case the writer was being careful.
      expect(
          picturesNamedIn(
              "![](assets/banner.jpg)\ntext\n![](assets/banner.jpg)", sizes),
          90000);
    });

    test('only the ones this page shows', () {
      // The site holds a 500 KB picture no page names. It costs nobody
      // anything, and reporting it against this page would be reporting the
      // site's size, not the page's.
      expect(picturesNamedIn("![](assets/logo.png)", sizes), 2000);
    });

    test('a banner background counts', () {
      // The case that prompted this. A header field names its picture the
      // same way an ordinary image does, so it is counted the same way --
      // and it is the one most likely to be large.
      var header = "--header--\nbackground: ![](assets/banner.jpg)\n"
          "r1c1: # My Site\n--/header--";
      expect(picturesNamedIn(header, sizes), 90000);
    });

    test('a name with no file behind it counts nothing', () {
      // A broken link, not a cost. Guessing a size would report a page as
      // expensive for showing nothing at all.
      expect(picturesNamedIn("![](assets/gone.png)", sizes), 0);
    });

    test('a picture from somewhere else is not the site paying for it', () {
      expect(picturesNamedIn("![](https://example.com/x.png)", sizes), 0);
    });

    test('an embedded picture is not counted here', () {
      // An embed carries its own bytes, so it is already in the page's own
      // size. Counting it again would be charging for it twice.
      expect(picturesNamedIn("--embed[type=image/png,data=AAAA]--", sizes), 0);
    });
  });
}
