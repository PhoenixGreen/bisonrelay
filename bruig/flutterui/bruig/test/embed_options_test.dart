import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/feed/image_header.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'png_fixture.dart';

// embed_options_test.dart covers shrinking a picture before it goes into a
// post: a maximum width, then compression of what is left.
//
// The order is most of the point. Scaling a 2000-wide photograph to 1000
// throws away three quarters of the pixels, so compressing afterwards works
// on a quarter as much data, and the quality figure describes the picture
// that will actually be seen rather than one about to be discarded.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final wide = pngOf(2000, 1000);
  final small = pngOf(400, 300);

  test("the fixtures are the sizes these tests assume", () {
    expect(imageDimensions(wide)?.width, 2000);
    expect(imageDimensions(wide)?.height, 1000);
    expect(imageDimensions(small)?.width, 400);
  });

  group("maximum width", () {
    test("a wide picture is scaled, keeping its shape", () async {
      var out = await prepareEmbed(
          wide, "image/png", const EmbedOptions(maxWidth: 1000));
      expect(out.width, 1000);
      expect(out.height, 500, reason: "2000x1000 asked for 1000 is 1000x500");
    });

    // Scaling one up makes a larger file that looks worse than the original.
    test("a picture already narrower is left alone", () async {
      var out = await prepareEmbed(
          small, "image/png", const EmbedOptions(maxWidth: 1000));
      expect(out.width, 400);
      expect(out.data, same(small));
    });

    test("no maximum leaves the size alone", () async {
      var out = await prepareEmbed(wide, "image/png", EmbedOptions.none);
      expect(out.width, 2000);
      expect(out.data, same(wide));
    });
  });

  group("compression", () {
    test("it makes the file smaller", () async {
      var out = await prepareEmbed(
          wide, "image/png", const EmbedOptions(quality: 40));
      expect(out.data.length, lessThan(wide.length));
      expect(out.mime, "image/jpeg");
    });

    test("quality of 100 leaves the encoding alone", () async {
      var out = await prepareEmbed(
          wide, "image/png", const EmbedOptions(quality: 100));
      expect(out.mime, "image/png");
      expect(out.data, same(wide));
    });
  });

  // Both together, in the arrangement that was asked for: the size comes
  // down first and the quality setting then applies to that.
  test("width first, then quality", () async {
    var both = await prepareEmbed(
        wide, "image/png", const EmbedOptions(maxWidth: 1000, quality: 40));

    // The scaling happened -- the result is 1000 wide, not 2000 -- and the
    // compression happened after it, on those dimensions.
    expect(both.width, 1000);
    expect(both.height, 500);
    expect(both.mime, "image/jpeg");

    // No comparison against the scaled-but-uncompressed bytes here, which is
    // where the first version of this test went wrong: that compares a PNG
    // against a JPEG, and which is smaller depends entirely on the picture.
    // This fixture is high-frequency noise, which zlib packs well and JPEG
    // packs badly, so the "compressed" one is legitimately the larger of the
    // two. The test below compares like with like instead.
  });

  // The saving the whole feature is for, and a comparison of two JPEGs, so
  // the only difference between them is the scaling.
  test("both together beat compression alone", () async {
    var compressedOnly =
        await prepareEmbed(wide, "image/png", const EmbedOptions(quality: 40));
    var both = await prepareEmbed(
        wide, "image/png", const EmbedOptions(maxWidth: 1000, quality: 40));
    expect(both.data.length, lessThan(compressedOnly.data.length));
  });

  test("something that is not an image is untouched", () async {
    var out = await prepareEmbed(
        small, "text/plain", const EmbedOptions(maxWidth: 10, quality: 1));
    expect(out.data, same(small));
    expect(out.mime, "text/plain");
  });

  test("options that change nothing say so", () {
    expect(EmbedOptions.none.changesAnything, isFalse);
    expect(const EmbedOptions(maxWidth: 800).changesAnything, isTrue);
    expect(const EmbedOptions(quality: 99).changesAnything, isTrue);
  });

  group("transparency", () {
    final logo = pngWithAlphaOf(400, 300);
    final opaque = pngWithAlphaOf(400, 300, transparent: false);

    test("a see-through picture is found to be one", () async {
      expect(await hasTransparency(logo), isTrue);
    });

    test("one with an alpha channel it does not use is not", () async {
      // Which is most PNGs, and exactly what the quality setting is for.
      expect(await hasTransparency(opaque), isFalse);
    });

    test("a logo keeps its format however low the quality", () async {
      // Compression encodes to JPEG, which has no alpha channel: the
      // transparency would come back filled in, usually black, and the
      // writer would not be told.
      var out = await prepareEmbed(
          logo, "image/png", const EmbedOptions(quality: 30));
      expect(out.mime, "image/png");
      expect(out.data, same(logo));
    });

    test("an opaque picture is still compressed", () async {
      var out = await prepareEmbed(
          opaque, "image/png", const EmbedOptions(quality: 30));
      expect(out.mime, "image/jpeg");
      expect(out.data.length, lessThan(opaque.length));
    });

    test("something undecodable is treated as see-through", () async {
      // The safe way to be wrong: a file that could have been smaller,
      // rather than one that comes back with black behind it.
      expect(await hasTransparency(Uint8List.fromList([1, 2, 3])), isTrue);
    });
  });

  group("choosing a format", () {
    final logo = pngWithAlphaOf(400, 300);
    final opaque = pngWithAlphaOf(400, 300, transparent: false);

    test("automatic is what it always did", () async {
      // The default, so every caller that does not care is unaffected.
      var out = await prepareEmbed(
          wide, "image/png", const EmbedOptions(quality: 40));
      expect(out.mime, "image/jpeg");
    });

    test("PNG comes back as PNG, however low the quality", () async {
      // Lossless: quality changes how hard it packs, never how it looks.
      var out = await prepareEmbed(wide, "image/png",
          const EmbedOptions(quality: 20, format: EmbedFormat.png));
      expect(out.mime, "image/png");
    });

    test("PNG keeps a see-through picture see-through", () async {
      // The reason to ask for PNG at all.
      var out = await prepareEmbed(logo, "image/png",
          const EmbedOptions(quality: 40, format: EmbedFormat.png));
      expect(out.mime, "image/png");
      expect(await hasTransparency(out.data), isTrue);
    });

    test("asking for JPEG still will not flatten transparency", () async {
      // Being overruled by an explicit choice would make this worse, not
      // better: choosing JPEG is choosing a size, not asking for a logo to
      // come back with black behind it -- and nothing would say it had.
      var out = await prepareEmbed(logo, "image/png",
          const EmbedOptions(quality: 40, format: EmbedFormat.jpeg));
      expect(out.mime, "image/png");
    });

    test("asking for JPEG re-encodes even at full quality", () async {
      // Naming a format is asking for that format. Quality 100 only means
      // "leave it alone" when no format was named.
      var out = await prepareEmbed(opaque, "image/png",
          const EmbedOptions(quality: 100, format: EmbedFormat.jpeg));
      expect(out.mime, "image/jpeg");
      expect(out.data, isNot(same(opaque)));
    });

    test("naming nothing at full quality still leaves it alone", () async {
      var out = await prepareEmbed(
          wide, "image/png", const EmbedOptions(quality: 100));
      expect(out.data, same(wide));
    });

    test("the bytes really are the format claimed", () async {
      // The mime is what names the file, and a name that disagrees with the
      // contents is a page pointing at something no decoder will open. The
      // magic numbers rather than the string, because the string is what
      // would be wrong.
      var asJpeg = await prepareEmbed(opaque, "image/png",
          const EmbedOptions(quality: 60, format: EmbedFormat.jpeg));
      expect(asJpeg.mime, "image/jpeg");
      expect(asJpeg.data.take(3), [0xFF, 0xD8, 0xFF]);

      var asPng = await prepareEmbed(opaque, "image/png",
          const EmbedOptions(quality: 60, format: EmbedFormat.png));
      expect(asPng.mime, "image/png");
      expect(asPng.data.take(4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  group("vectors", () {
    test("are passed through untouched", () async {
      // No pixels to scale and no quality to trade away -- and decoding one
      // would turn a few kilobytes of markup into a bitmap.
      var svg = Uint8List.fromList(
          '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits);
      var out = await prepareEmbed(
          svg, "image/svg+xml", const EmbedOptions(maxWidth: 100, quality: 30));
      expect(out.mime, "image/svg+xml");
      expect(out.data, same(svg));
    });
  });
}
