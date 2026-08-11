import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'png_fixture.dart';

// markdown_image_test.dart covers how wide a picture in a post is drawn.
//
// The setting reads "Width: N% of the column", and it has to mean that. It
// used to be applied as a maximum width, which is a different thing: an
// Image set to contain draws at its natural size whenever that fits, so a
// picture narrower than the column ignored the setting completely and 100%
// did not fill the post. Every test here uses a picture deliberately smaller
// than the column it is in, because that is the only case where a width and
// a maximum width tell apart.

/// _column is the width the picture is given to take a share of.
const _column = 800.0;

/// _picture is 200 wide -- a quarter of the column, so a setting applied as a
/// cap leaves it at 200 whatever the percentage says.
final _picture = pngOf(200, 100);

Future<double> _widthAt(WidgetTester tester, double percent,
    {MarkdownAlign align = MarkdownAlign.left}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _column,
            child: MarkdownGuideScope(
              image: ImageRule(widthPercent: percent, align: align),
              child: ImageMd("", _picture, "image/png"),
            ),
          ),
        ),
      ),
    ),
  ));
  // The picture has to be decoded before it has a size to report.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.getSize(find.byType(Image)).width;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("a picture's width is a share of the column", () {
    testWidgets("100% fills the column", (tester) async {
      // The margin the picture is drawn inside is 2 either side.
      expect(await _widthAt(tester, 100), closeTo(_column - 4, 1),
          reason: "the picture is 200 wide, and 100% has to mean the column "
              "rather than 'up to' it");
    });

    testWidgets("50% is half of it", (tester) async {
      expect(await _widthAt(tester, 50), closeTo((_column - 4) / 2, 1));
    });

    // The one the cap got right by accident, kept so the fix is not a
    // one-directional change: below the picture's natural size, a maximum
    // width and a width agree.
    testWidgets("a small share still shrinks it", (tester) async {
      expect(await _widthAt(tester, 10), closeTo((_column - 4) / 10, 1));
    });

    // The height follows from the width rather than staying put: the
    // picture is 200x100, so at any width it is half as tall as it is wide.
    testWidgets("the shape is kept", (tester) async {
      await _widthAt(tester, 100);
      var size = tester.getSize(find.byType(Image));
      expect(size.height, closeTo(size.width / 2, 1));
    });

    testWidgets("alignment still places it", (tester) async {
      await _widthAt(tester, 50, align: MarkdownAlign.right);
      var right = tester.getTopRight(find.byType(Image)).dx;
      await _widthAt(tester, 50, align: MarkdownAlign.left);
      var left = tester.getTopRight(find.byType(Image)).dx;
      expect(right, greaterThan(left));
    });
  });

  // Chat has no guide and no share to take: a picture there is bounded by
  // the chat image size setting and otherwise drawn as it always was.
  group("a picture in chat", () {
    testWidgets("is left at its natural size", (tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _column),
                child: ImageMd("", _picture, "image/png"),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(find.byType(Image)).width, 200,
          reason: "no guide means nothing changes");
    });
  });
}
