import 'package:bruig/components/feed/image_header.dart';
import 'package:flutter_test/flutter_test.dart';

import 'png_fixture.dart';

// The fixture builder is what several other tests measure against, so it has
// to be right before they mean anything.
void main() {
  test("it produces a PNG of the size asked for", () {
    var size = imageDimensions(pngOf(2000, 1000));
    expect(size?.width, 2000);
    expect(size?.height, 1000);
  });

  test("it is a real PNG, not just a header", () {
    var bytes = pngOf(64, 64);
    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(bytes.length, greaterThan(500),
        reason: "a pattern that compressed to nothing would make the "
            "compression tests meaningless");
  });
}
