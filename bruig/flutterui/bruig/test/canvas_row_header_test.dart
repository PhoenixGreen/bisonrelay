import 'package:bruig/plugin_system/canvas/ui/timeline/row_header.dart';
import 'support/canvas_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

// canvas_row_header_test.dart is a timeline channel's header (Ken,
// 2026-11-10: "I'd like to be able to resize the timeline headers so I can
// see the full channel names ... these are reduced, probably more than they
// need to be"): a short row's name had half the room its chips left,
// "Strings" cut to "Stri..." with room to spare beside it.

/// header shows a header [width] by [height] at text [scale]. Without a
/// width it is the screen's size and the text the platform's, for a sweep of
/// sizes to change.
Future<void> header(WidgetTester tester, double? width,
    {double scale = 1, double height = 40}) async {
  Widget row(double width, double height) => RowHeader(
      colour: Colors.blue,
      width: width,
      height: height,
      name: const Text("Strings",
          key: ValueKey("name"),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false),
      badges: const [Text("M", key: ValueKey("chip"))],
      motion: const RowToggle(ValueKey("m"), on: false),
      sound: const RowToggle(ValueKey("s"), on: true),
      solo: const RowToggle(ValueKey("o"), on: false));
  Widget sized(double width, double height) => Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, height: height, child: row(width, height)));
  if (width == null) {
    await tester.pumpWidget(canvasApp(Builder(builder: (context) {
      var size = MediaQuery.sizeOf(context);
      return sized(size.width, size.height);
    })));
    return;
  }
  await tester.pumpWidget(canvasApp(
      MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: sized(width, height))),
      scaffold: false));
}

void main() {
  testWidgets("a short row's name has the room its chips leave",
      (tester) async {
    // The test's font is a wide one: at the header's widest the name fits.
    await header(tester, 360);
    var name = tester
        .renderObject<RenderParagraph>(find.byKey(const ValueKey("name")));
    expect(name.didExceedMaxLines, isFalse, reason: "Strings, whole");
    expect(find.byKey(const ValueKey("chip")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Ken's log, 2026-11-13: a row dragged down to a lane, or folded, had a
  // header 19.5 px inside -- under its 20 px line -- and overflowed.
  testWidgets("a row shorter than its line clips it, not overflowing",
      (tester) async {
    setTestScreen(tester, const Size(240, 12));
    await header(tester, null);
    await sweepSizes(tester,
        sizes: [
          for (var height in [12.0, 18.0, 20.5, 21.5, 26.0]) Size(240, height)
        ],
        scales: const [1.0],
        settle: 1);
  });

  testWidgets("narrow or at any text size, nothing overflows", (tester) async {
    setTestScreen(tester, const Size(132, 40));
    await header(tester, null);
    await sweepSizes(tester,
        sizes: [
          for (var width in [132.0, 160.0, 240.0, 360.0]) Size(width, 40)
        ],
        scales: const [0.65, 1.0, 1.5],
        settle: 1);
  });
}
