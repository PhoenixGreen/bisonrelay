import 'package:bruig/components/feed/page_image.dart';
import 'package:flutter_test/flutter_test.dart';

// page_image_test.dart covers which links are a picture of the site's own.
//
// A picture kept as a file is fetched from whoever is being read; a link
// with a scheme belongs to somebody else and is left to whatever handles
// those. Telling the two apart is the whole of the decision.

void main() {
  group('a picture of this site', () {
    test('is a path with no scheme', () {
      expect(isPageAssetPath("assets/banner.png"), isTrue);
      expect(isPageAssetPath("banner.png"), isTrue);
    });

    test('anything with a scheme belongs to somebody else', () {
      expect(isPageAssetPath("https://example.com/x.png"), isFalse);
      expect(isPageAssetPath("http://example.com/x.png"), isFalse);
      expect(isPageAssetPath("br://abc123/assets/x.png"), isFalse);
      expect(isPageAssetPath("data:image/png;base64,AAAA"), isFalse);
      expect(isPageAssetPath("file:///etc/passwd"), isFalse);
    });

    test('nothing at all is not a picture', () {
      expect(isPageAssetPath(""), isFalse);
    });
  });
}
