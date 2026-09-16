import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// color_picker_layout_test.dart is the picker fitting in the room it is
// given.
//
// It has two columns -- how the colour is chosen, and the numbers and saved
// colours beside it -- and it used to work out how wide each of them was from
// a width the caller had guessed at. A guess that is eight pixels over is not
// a dialog eight pixels too wide: it is a picker laying itself out for room
// it has not got, and the difference comes out as an overflow stripe across
// the numbers.
//
// So the tests here are about widths nobody chose: the narrowest phone, the
// widths either side of the point where the columns stack, and the widest.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// openOn puts the real dialog on a screen of [screen] logical pixels wide
  /// and settles it.
  Future<void> openOn(WidgetTester tester, double screen) async {
    tester.view.physicalSize = Size(screen, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                pickPaint(context, initial: const PaintSpec(Color(0xFF3D7EFF))),
            child: const Text("open"),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  for (var screen in [
    320.0,
    360.0,
    420.0,
    600.0,
    700.0,
    728.0,
    760.0,
    900.0,
    1400.0
  ]) {
    testWidgets("nothing overflows on a screen ${screen.round()} wide",
        (tester) async {
      await openOn(tester, screen);
      expect(find.byType(AppColorPicker), findsOneWidget);
      // takeException is how a RenderFlex overflow reports itself: it paints
      // the stripe and throws. Nothing thrown is nothing overflowing.
      expect(tester.takeException(), isNull);

      // And the picker is actually inside the screen, not merely quiet about
      // being outside it.
      var box = tester.getRect(find.byType(AppColorPicker));
      expect(box.left, greaterThanOrEqualTo(-0.5));
      expect(box.right, lessThanOrEqualTo(screen + 0.5));

      // The invariant the overflow came from: the picker cannot measure the
      // room it is given -- an AlertDialog asks it how wide it wants to be --
      // so the width it is told has to be the width it actually gets. Told
      // eight pixels more than the dialog hands down, it lays itself out for
      // eight pixels it has not got, and that is the stripe.
      var told = tester.widget<AppColorPicker>(find.byType(AppColorPicker));
      expect(box.width, closeTo(told.width, 0.5),
          reason: "told the width it was actually given");
    });
  }

  testWidgets("the four ways of choosing sit on one line when there is room",
      (tester) async {
    await openOn(tester, 1400);
    var tops = [
      for (var mode in ["sliders", "wheel", "palette", "gradient"])
        tester.getRect(find.byKey(ValueKey("colorMode$mode"))).top,
    ];
    expect(tops.toSet().length, 1,
        reason: "a row of tabs that wraps moves the square down the dialog");
  });

  testWidgets("the numbers sit beside the colour when there is room",
      (tester) async {
    await openOn(tester, 1400);
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var hex = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(hex.left, greaterThan(square.right),
        reason: "two columns on a wide screen");
  });

  testWidgets("and underneath it when there is not", (tester) async {
    await openOn(tester, 420);
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var hex = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(hex.top, greaterThan(square.bottom),
        reason: "one column on a narrow screen, not a squeezed pair");
    expect(hex.left, lessThan(square.right));
  });

  testWidgets("a narrow screen gets its edges back", (tester) async {
    // A dialog's usual margin and padding is 128 pixels of nothing, which on
    // a phone is most of the screen. The picker is the content of this
    // dialog, so on a narrow one the dialog is pulled in to the edges.
    await openOn(tester, 320);
    var box = tester.getRect(find.byType(AppColorPicker));
    expect(box.width, greaterThan(250),
        reason: "the picker gets the phone's width, not half of it");
  });

  testWidgets("and stacks all the way down to a very small one",
      (tester) async {
    await openOn(tester, 260);
    expect(tester.takeException(), isNull);
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var hex = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(hex.top, greaterThan(square.bottom));
  });

  /// channelTops is where each of the four numbers sits down the panel.
  List<double> channelTops(WidgetTester tester) => [
        for (var c in ["R", "G", "B", "A"])
          tester.getRect(find.byKey(ValueKey("channel$c"))).top,
      ];

  // The right column is held at the width four numbered boxes need. Let it
  // shrink below that and what it does is fold them one to a line, which is a
  // strip of stacked numbers beside a colour square that has not budged.
  for (var screen in [620.0, 640.0, 700.0, 760.0, 900.0, 1100.0, 1400.0]) {
    testWidgets("the four numbers stay on one line at ${screen.round()}",
        (tester) async {
      await openOn(tester, screen);
      expect(tester.takeException(), isNull);
      expect(channelTops(tester).toSet().length, 1,
          reason: "R G B A on one line");
    });
  }

  testWidgets("the colour column is what gives way, not the numbers",
      (tester) async {
    // Just wide enough for two columns: the colour side should be narrower
    // than it would like, rather than full width beside a strip.
    late double narrow;
    await openOn(tester, 640);
    narrow = tester.getRect(find.byKey(const ValueKey("colorShade"))).width;
    expect(channelTops(tester).toSet().length, 1);

    await tester.pumpWidget(const SizedBox());
    await openOn(tester, 1400);
    var roomy = tester.getRect(find.byKey(const ValueKey("colorShade"))).width;
    expect(narrow, lessThan(roomy),
        reason: "the square shrinks before the numbers fold");
  });

  testWidgets("narrowing the window re-lays the picker out", (tester) async {
    // The width used to be worked out once, when the dialog opened. Drag the
    // window narrower with the picker open and it held on to room it no
    // longer had, which is the overflow stripe again -- and the two columns
    // stayed side by side however little was left.
    await openOn(tester, 1400);
    var wide = tester.getRect(find.byType(AppColorPicker)).width;
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var hex = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(hex.left, greaterThan(square.right), reason: "two columns");

    tester.view.physicalSize = const Size(420, 1200);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    var narrow = tester.getRect(find.byType(AppColorPicker)).width;
    expect(narrow, lessThan(wide));
    expect(narrow, lessThanOrEqualTo(420));

    square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    hex = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(hex.top, greaterThan(square.bottom),
        reason: "and the numbers have folded under the colour");
  });

  testWidgets("the two columns have a gutter between them", (tester) async {
    // A stack of small boxes close to a big one reads as part of it. The gap
    // is what makes them two columns.
    await openOn(tester, 1400);
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var channel = tester.getRect(find.byKey(const ValueKey("channelR")));
    expect(channel.left - square.right, greaterThanOrEqualTo(30));
  });

  testWidgets("and no heading over a panel that is obviously a colour",
      (tester) async {
    await openOn(tester, 1400);
    expect(find.text("Colour"), findsNothing);
  });
}
