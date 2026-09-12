import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/saved_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// color_picker_test.dart is the app's one colour picker: the parts of it that
// were bugs in the package it replaced, and the saved colours it adds.

Future<Color> pump(WidgetTester tester,
    {Color start = const Color(0xFF000000),
    bool allowAlpha = true,
    double width = 320}) async {
  var current = start;
  // No provider around it: the picker takes its colours from Material's own
  // scheme, so it works wherever there is a Theme -- which is every panel,
  // every dialog and every test that pumps one.
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      // Scrolling, the way every real use of it is: a picker in a dialog or
      // a settings column has a scroll view over it, and the wheel is taller
      // than a small window.
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => AppColorPicker(
            color: current,
            allowAlpha: allowAlpha,
            width: width,
            onChanged: (c) => setState(() => current = c),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return current;
}

/// _shown is the colour the picker is showing, read back off its hex field.
Color _shown(WidgetTester tester) {
  var field =
      tester.widget<TextField>(find.byKey(const ValueKey("colorPickerHex")));
  return Color(int.parse(field.controller!.text, radix: 16));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SavedColors.instance.forget();
  });

  testWidgets("a black remembers the hue it was", (tester) async {
    // The bug this picker was written for. A colour with no brightness has no
    // hue to read back, so a picker that keeps only the colour forgets which
    // way the hue slider was pointing the moment the colour goes black --
    // the slider snaps home, the square turns red, and nothing moves until a
    // colour is picked out of the square again.
    await pump(tester, start: const Color(0xFF20A0FF));

    // Down to black by hand, which is how a colour with no hue in it
    // arrives: the picker reads the typed value back in.
    await tester.enterText(
        find.byKey(const ValueKey("colorPickerHex")), "ff000000");
    await tester.pumpAndSettle();
    expect(_shown(tester).toARGB32(), 0xFF000000);

    // Now up out of the black again, in the square alone. The hue slider has
    // not been touched, so what comes back should be the blue it was.
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    await tester.dragFrom(
        square.center, Offset(square.width * 0.3, -square.height * 0.3));
    await tester.pumpAndSettle();

    var showing = _shown(tester);
    expect(showing.b, greaterThan(showing.r),
        reason:
            "the blue came back as ${showing.toARGB32().toRadixString(16)}");
  });

  testWidgets("a channel caption is dragged to change its number",
      (tester) async {
    await pump(tester, start: const Color(0xFF804040));

    var before = _shown(tester);
    await tester.drag(
        find.byKey(const ValueKey("channelG")), const Offset(60, 0));
    await tester.pumpAndSettle();

    var after = _shown(tester);
    expect(after.g, greaterThan(before.g),
        reason: "dragging G right raises the green");
    expect((after.r * 255).round(), (before.r * 255).round(),
        reason: "and leaves the red alone");
  });

  testWidgets("a colour is kept, offered, and forgotten again", (tester) async {
    await pump(tester, start: const Color(0xFF3366CC));

    expect(find.byKey(const ValueKey("savedSwatches")), findsNothing,
        reason: "nothing saved yet");
    await tester.tap(find.byKey(const ValueKey("saveColor")));
    await tester.pumpAndSettle();

    expect(SavedColors.instance.colors, hasLength(1));
    expect(SavedColors.instance.colors.first.toARGB32(), 0xFF3366CC);

    // Saved once only: the button goes dead while the picker is showing a
    // colour that is already kept.
    var add =
        tester.widget<IconButton>(find.byKey(const ValueKey("saveColor")));
    expect(add.onPressed, isNull);

    // And it can be taken away again, which is what the remove button is for
    // once a saved colour is the one showing.
    await tester.tap(find.byKey(const ValueKey("forgetColor")));
    await tester.pumpAndSettle();
    expect(SavedColors.instance.colors, isEmpty);
  });

  testWidgets("remove is offered only for a colour that is saved",
      (tester) async {
    await pump(tester, start: const Color(0xFF3366CC));
    var forget =
        tester.widget<IconButton>(find.byKey(const ValueKey("forgetColor")));
    expect(forget.onPressed, isNull,
        reason: "nothing to forget about a colour off the wheel");
  });

  test("the saved list is two rows and no more", () async {
    SharedPreferences.setMockInitialValues({});
    SavedColors.instance.forget();
    var saved = SavedColors.instance;
    await saved.load();
    for (var i = 0; i < savedColorsLimit + 5; i++) {
      await saved.add(Color(0xFF000000 + i));
    }
    expect(saved.colors, hasLength(savedColorsLimit));
    expect(saved.isFull, isTrue);
    expect(savedColorsLimit, savedColorsPerRow * 2);
  });

  test("and it comes back after a restart", () async {
    SharedPreferences.setMockInitialValues({});
    SavedColors.instance.forget();
    await SavedColors.instance.load();
    await SavedColors.instance.add(const Color(0x80FF0000));

    // A second run of the app: the same store, told to forget what it is
    // holding in memory, reads its list back off the disk.
    SavedColors.instance.forget();
    await SavedColors.instance.load();
    expect(SavedColors.instance.colors.single.toARGB32(), 0x80FF0000,
        reason: "including how see-through it was");
  });

  testWidgets("the wheel is another way of saying the same colour",
      (tester) async {
    // Three ways of choosing, one colour: whatever is set in one is what the
    // next one opens on.
    await pump(tester, start: const Color(0xFFCC3366));
    await tester.tap(find.byKey(const ValueKey("colorModewheel")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("colorWheel")), findsOneWidget);
    expect(_shown(tester).toARGB32(), 0xFFCC3366,
        reason: "the wheel opened on the colour the square had");

    // A press on the wheel, out towards the rim on the right, is a red.
    var wheel = tester.getRect(find.byKey(const ValueKey("colorWheel")));
    await tester
        .tapAt(Offset(wheel.center.dx + wheel.width * 0.4, wheel.center.dy));
    await tester.pumpAndSettle();
    var showing = _shown(tester);
    expect(showing.r, greaterThan(showing.b),
        reason: "the right of the wheel is where the reds are: "
            "${showing.toARGB32().toRadixString(16)}");

    // And back to the sliders, which open on what the wheel left.
    var fromWheel = _shown(tester).toARGB32();
    await tester.tap(find.byKey(const ValueKey("colorModesliders")));
    await tester.pumpAndSettle();
    expect(_shown(tester).toARGB32(), fromWheel);
  });

  testWidgets("the palette lays five colours out and answers with one",
      (tester) async {
    await pump(tester, start: const Color(0xFF3366CC));
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    // The first of the five is the colour it was opened on: the palette is a
    // way of asking what goes with this one.
    expect(_shown(tester).toARGB32(), 0xFF3366CC);

    // Choosing another of the five is what the picker then answers with.
    await tester.tap(find.byKey(const ValueKey("paletteSpot2")));
    await tester.pumpAndSettle();
    expect(_shown(tester).toARGB32(), isNot(0xFF3366CC));

    // A complementary set puts its second colour across the wheel from its
    // first -- which is the whole of what a harmony is.
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Complementary").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("paletteSpot0")));
    await tester.pumpAndSettle();
    var first = HSVColor.fromColor(_shown(tester));
    await tester.tap(find.byKey(const ValueKey("paletteSpot2")));
    await tester.pumpAndSettle();
    var across = HSVColor.fromColor(_shown(tester));
    var turn = (across.hue - first.hue).abs();
    expect(turn, closeTo(180, 2),
        reason: "the two are $turn apart round the wheel");
  });

  testWidgets("a palette handle keeps hold of the drag it started",
      (tester) async {
    // Which handle is being held is decided when the press lands and kept for
    // the rest of the drag. Worked out on every move instead, a handle
    // dragged past its neighbour hands the drag over half way and the set
    // jumps.
    await pump(tester, start: const Color(0xFFCC3366));
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    var wheel = tester.getRect(find.byKey(const ValueKey("colorPaletteWheel")));
    // From the middle outwards: the handle in the middle takes the whole set
    // with it, so what it must not do is let go and grab one of the five.
    var pointer = await tester.startGesture(wheel.center);
    await pointer.moveBy(Offset(wheel.width * 0.3, 0));
    await tester.pumpAndSettle();
    await pointer.moveBy(Offset(0, wheel.height * 0.2));
    await tester.pumpAndSettle();
    await pointer.up();
    await tester.pumpAndSettle();

    // The five are still the arrangement they were: dragged by the middle,
    // the shape turns rather than coming apart.
    var swatches = [
      for (var i = 0; i < 5; i++)
        tester.widget<Container>(find.descendant(
            of: find.byKey(ValueKey("paletteSpot$i")),
            matching: find.byType(Container))),
    ];
    expect(swatches, hasLength(5));
    expect(_shown(tester).toARGB32(), isNot(0xFFCC3366),
        reason: "the set moved with the drag");
  });

  test("a colour is written and read back in every notation", () {
    // The sums are the only part of the picker that can be wrong in a way
    // nobody sees, so they are checked without a widget.
    const colour = Color(0xFF3A7BD5);
    for (var format in ColorFormat.values) {
      var written = ColorText.write(colour, format);
      var read = ColorText.read(written, format, colour);
      expect(read, isNotNull,
          reason: "$format wrote '$written' and could "
              "not read it back");
      if (format == ColorFormat.grey) continue;
      // Within a few points per channel. These notations round to whole
      // numbers on the way out, and one step of L or of a in LAB is worth
      // more than one step of red.
      var slack = format == ColorFormat.lab ? 6 : 3;
      expect((read!.r * 255 - colour.r * 255).abs(), lessThan(slack),
          reason: "$format red");
      expect((read.g * 255 - colour.g * 255).abs(), lessThan(slack),
          reason: "$format green");
      expect((read.b * 255 - colour.b * 255).abs(), lessThan(slack),
          reason: "$format blue");
    }

    // And greyscale is the one that does not round-trip a colour, because it
    // cannot hold one: it says how bright, and reads back a grey.
    var grey = ColorText.read("128", ColorFormat.grey, colour)!;
    expect(grey.r, grey.g);
    expect(grey.g, grey.b);
  });

  testWidgets("a wide picker puts the numbers beside the colour",
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, start: const Color(0xFF3366CC), width: 620);
    var square = tester.getRect(find.byKey(const ValueKey("colorShade")));
    var field = tester.getRect(find.byKey(const ValueKey("colorPickerHex")));
    expect(field.left, greaterThan(square.right),
        reason: "the numbers are under the colour rather than beside it");

    // And the field is whole: the hex it holds was being cut off.
    expect(field.width, greaterThan(120));
  });
}
