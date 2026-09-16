import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_second_line_test.dart is where the strip under the band goes.
//
// It used to be drawn over the canvas, so opening the canvas settings or the
// grid and guides covered the top edge of the design -- the part most likely
// to be worked on while the settings that do the work are open. It pushes the
// canvas down now, the way the timeline at the bottom of the same column
// always has.
//
// Tested through canvasSecondLine and a stand-in stage rather than by mounting
// the whole screen: what is being decided is where in the column the strip
// sits, and that is exactly what this shows.

void main() {
  /// _column is the work area's shape: the band, the strip when there is one,
  /// then the canvas taking what is left.
  Future<void> show(WidgetTester tester,
      {Widget? settings, Widget? guides}) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          const SizedBox(key: ValueKey("band"), height: 40, width: 800),
          ...canvasSecondLine(settings: settings, guides: guides),
          const Expanded(
            child: SizedBox.expand(
                key: ValueKey("stage"), child: ColoredBox(color: Colors.grey)),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Widget strip(String name, double height) => SizedBox(
      key: ValueKey(name),
      height: height,
      width: 800,
      child: const Placeholder());

  testWidgets("with nothing open the canvas starts under the band",
      (tester) async {
    await show(tester);
    var band = tester.getRect(find.byKey(const ValueKey("band")));
    var stage = tester.getRect(find.byKey(const ValueKey("stage")));
    expect(stage.top, band.bottom);
  });

  testWidgets("the canvas settings push the canvas down", (tester) async {
    await show(tester, settings: strip("settings", 90));
    var settings = tester.getRect(find.byKey(const ValueKey("settings")));
    var stage = tester.getRect(find.byKey(const ValueKey("stage")));

    expect(settings.top, 40, reason: "under the band");
    expect(stage.top, settings.bottom,
        reason: "and the canvas starts below it, not behind it");
  });

  testWidgets("and so do the grid and guides", (tester) async {
    await show(tester, guides: strip("guides", 120));
    var guides = tester.getRect(find.byKey(const ValueKey("guides")));
    var stage = tester.getRect(find.byKey(const ValueKey("guides")));
    expect(guides.top, 40);
    expect(
        tester.getRect(find.byKey(const ValueKey("stage"))).top, guides.bottom);
    expect(stage.height, 120);
  });

  testWidgets("the canvas gets shorter by exactly the strip", (tester) async {
    await show(tester);
    var whole = tester.getRect(find.byKey(const ValueKey("stage"))).height;
    await show(tester, settings: strip("settings", 90));
    var shorter = tester.getRect(find.byKey(const ValueKey("stage"))).height;
    expect(whole - shorter, 90);
  });

  testWidgets("two at once is one strip, not two", (tester) async {
    // The toggles see to it that only one is open, and if one ever gets
    // through the column must not stack them.
    await show(tester,
        settings: strip("settings", 90), guides: strip("guides", 120));
    expect(find.byKey(const ValueKey("settings")), findsOneWidget);
    expect(find.byKey(const ValueKey("guides")), findsNothing);
  });
}
