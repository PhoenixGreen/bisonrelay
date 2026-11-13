import 'package:bruig/plugin_system/canvas/ui/row_header.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_row_header_test.dart is a timeline channel's header (Ken,
// 2026-11-10: "I'd like to be able to resize the timeline headers so I can
// see the full channel names ... these are reduced, probably more than they
// need to be"): a short row's name had half the room its chips left,
// "Strings" cut to "Stri..." with room to spare beside it.

Future<void> header(WidgetTester tester, double width,
    {double scale = 1, double height = 40}) async {
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
    create: (_) => ThemeNotifier(doLoad: false),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: height,
              child: RowHeader(
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
                solo: const RowToggle(ValueKey("o"), on: false),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
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
    for (var height in [12.0, 18.0, 20.5, 21.5, 26.0]) {
      await header(tester, 240, height: height);
      expect(tester.takeException(), isNull, reason: "$height tall");
    }
  });

  testWidgets("narrow or at any text size, nothing overflows", (tester) async {
    for (var scale in [0.65, 1.0, 1.5]) {
      for (var width in [132.0, 160.0, 240.0, 360.0]) {
        await header(tester, width, scale: scale);
        expect(tester.takeException(), isNull,
            reason: "at $width wide, text at $scale");
      }
    }
  });
}
