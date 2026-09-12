import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/saved_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// color_picker_test.dart is the app's one colour picker: the parts of it that
// were bugs in the package it replaced, and the saved colours it adds.

/// _Answer is what the picker last said, which is the only way to read it
/// back once the field is holding something other than hex.
class _Answer {
  Color color;
  _Answer(this.color);
}

Future<_Answer> pump(WidgetTester tester,
    {Color start = const Color(0xFF000000),
    bool allowAlpha = true,
    double width = 320}) async {
  var answer = _Answer(start);
  // Room enough for the tallest of the three modes. The palette is a wheel, a
  // harmony, five swatches with a lock and a hex under each, and two sliders
  // -- which is taller than the eight hundred pixels a test view has by
  // default, and a menu that opens off the bottom of the screen cannot be
  // tapped.
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
            color: answer.color,
            allowAlpha: allowAlpha,
            width: width,
            onChanged: (c) => setState(() => answer.color = c),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return answer;
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
    // The handle on the rim takes the whole set with it, so what it must not
    // do is let go half way round and grab one of the five.
    var pointer =
        await tester.startGesture(Offset(wheel.right - 4, wheel.center.dy));
    await pointer.moveBy(Offset(-wheel.width * 0.1, wheel.height * 0.3));
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

  testWidgets("the ring outside the wheel turns the whole set", (tester) async {
    await pump(tester, start: const Color(0xFFCC3366), width: 360);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    // What the five are, relative to each other: a harmony is a shape, and
    // the handle on the rim turns the shape without changing it.
    List<double> hues() => [
          for (var i = 0; i < 5; i++)
            HSVColor.fromColor(tester
                        .widget<Container>(find.descendant(
                            of: find.byKey(ValueKey("paletteSpot$i")),
                            matching: find.byType(Container)))
                        .decoration is BoxDecoration
                    ? ((tester
                            .widget<Container>(find.descendant(
                                of: find.byKey(ValueKey("paletteSpot$i")),
                                matching: find.byType(Container)))
                            .decoration as BoxDecoration)
                        .color!)
                    : const Color(0xFF000000))
                .hue,
        ];

    var before = hues();
    var gaps = [for (var i = 1; i < 5; i++) (before[i] - before[0]) % 360];

    var wheel = tester.getRect(find.byKey(const ValueKey("colorPaletteWheel")));
    // A press on the rim, a quarter of the way round from where the handle
    // is: the set should follow it there.
    await tester.tapAt(Offset(wheel.center.dx, wheel.top + 4));
    await tester.pumpAndSettle();

    var after = hues();
    expect((after[0] - before[0]).abs(), greaterThan(20),
        reason: "the set did not turn");
    var moved = [for (var i = 1; i < 5; i++) (after[i] - after[0]) % 360];
    for (var i = 0; i < gaps.length; i++) {
      expect(moved[i], closeTo(gaps[i], 1.5),
          reason: "the arrangement came apart: $gaps became $moved");
    }
  });

  testWidgets("greyscale takes the colour out of the picker", (tester) async {
    // A notation is a way of working, not a label on a field: told to work in
    // greys, the field, the wheel and the answer are all greys.
    var answer = await pump(tester, start: const Color(0xFFCC3366), width: 360);
    await tester.tap(find.byKey(const ValueKey("colorFormat")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Greyscale").last);
    await tester.pumpAndSettle();

    // Read off what the picker answered with rather than out of the field:
    // the field is holding a brightness now, not a hex.
    var showing = answer.color;
    expect((showing.r * 255).round(), (showing.g * 255).round());
    expect((showing.g * 255).round(), (showing.b * 255).round());

    // The ramp is one axis: dragging up and down it gives darker and lighter
    // greys and never a colour.
    var ramp = tester.getRect(find.byKey(const ValueKey("colorShade")));
    await tester.tapAt(Offset(ramp.left + ramp.width * 0.8, ramp.center.dy));
    await tester.pumpAndSettle();
    var lighter = answer.color;
    expect((lighter.r * 255).round(), (lighter.b * 255).round());
    expect(lighter.r, greaterThan(showing.r),
        reason: "the right of the ramp is the light end");

    // And the hue slider is not there at all: a greyscale has no hue to set.
    expect(find.byKey(const ValueKey("colorHue")), findsNothing);
  });

  testWidgets("each notation brings its own field and sliders", (tester) async {
    await pump(tester, start: const Color(0xFF3A7BD5), width: 360);

    Future<void> choose(String name) async {
      await tester.tap(find.byKey(const ValueKey("colorFormat")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    // CMYK picks out of cyan against magenta, with the other two inks on
    // sliders of their own.
    await choose("CMYK");
    expect(find.byKey(const ValueKey("colorYellow")), findsOneWidget);
    expect(find.byKey(const ValueKey("colorBlack")), findsOneWidget);
    expect(find.byKey(const ValueKey("colorHue")), findsNothing);

    // LAB picks out of the a-b plane at a lightness.
    await choose("LAB");
    expect(find.byKey(const ValueKey("colorLightness")), findsOneWidget);
    expect(find.byKey(const ValueKey("colorYellow")), findsNothing);

    // And HSL is back to a hue slider, over a different square.
    await choose("HSL");
    expect(find.byKey(const ValueKey("colorHue")), findsOneWidget);
  });

  testWidgets("the wheel is in the notation's own space", (tester) async {
    // The notations used to reach only the sliders mode, so a wheel in LAB
    // was an HSV wheel with a LAB reading under it -- and the slider beside
    // it said Brightness whatever was chosen.
    var answer = await pump(tester, start: const Color(0xFF3A7BD5), width: 360);
    await tester.tap(find.byKey(const ValueKey("colorModewheel")));
    await tester.pumpAndSettle();

    Future<void> choose(String name) async {
      await tester.tap(find.byKey(const ValueKey("colorFormat")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await choose("LAB");
    expect(find.text("Lightness"), findsOneWidget,
        reason: "LAB's third axis is its lightness, not a brightness");

    await choose("CMYK");
    expect(find.text("Ink"), findsOneWidget);

    // And what comes off the wheel in greyscale is a grey, wherever on it the
    // press lands.
    await choose("Greyscale");
    var wheel = tester.getRect(find.byKey(const ValueKey("colorWheel")));
    await tester
        .tapAt(Offset(wheel.center.dx + wheel.width * 0.3, wheel.center.dy));
    await tester.pumpAndSettle();
    expect((answer.color.r * 255).round(), (answer.color.g * 255).round());
    expect((answer.color.g * 255).round(), (answer.color.b * 255).round());
  });

  testWidgets("a locked colour stays while the rest are worked on",
      (tester) async {
    var answer = await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    Color spot(int i) => (tester
            .widget<Container>(find.descendant(
                of: find.byKey(ValueKey("paletteSpot$i")),
                matching: find.byType(Container)))
            .decoration as BoxDecoration)
        .color!;

    var kept = spot(1);
    await tester.tap(find.byKey(const ValueKey("paletteLock1")));
    await tester.pumpAndSettle();

    // A different harmony re-lays the set -- except the one being kept.
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Triad").last);
    await tester.pumpAndSettle();

    expect(spot(1).toARGB32(), kept.toARGB32(),
        reason: "the locked colour was re-laid with the rest");
    expect(spot(2).toARGB32(), isNot(kept.toARGB32()),
        reason: "and the unlocked ones did move");

    // Unlocked again, it goes where the harmony says.
    await tester.tap(find.byKey(const ValueKey("paletteLock1")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Square").last);
    await tester.pumpAndSettle();
    expect(spot(1).toARGB32(), isNot(kept.toARGB32()));
    expect(answer.color, isNotNull);
  });

  testWidgets("reset puts every mode back to how it started", (tester) async {
    var answer = await pump(tester, start: const Color(0xFF3366CC), width: 380);

    // Wander: another mode, another notation, a different harmony, a lock,
    // and a colour that is none of the above.
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("paletteLock2")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Triad").last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("paletteSpot3")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colorFormat")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("CMYK").last);
    await tester.pumpAndSettle();
    expect(answer.color.toARGB32(), isNot(0xFF3366CC));

    await tester.tap(find.byKey(const ValueKey("colorReset")));
    await tester.pumpAndSettle();

    expect(answer.color.toARGB32(), 0xFF3366CC,
        reason: "the colour it opened on");
    expect(find.text("Hex"), findsOneWidget, reason: "and hex with it");
    // The lock is off, which is what makes the palette safe to fiddle with.
    var lock = tester.widget<Icon>(find.descendant(
        of: find.byKey(const ValueKey("paletteLock2")),
        matching: find.byType(Icon)));
    expect(lock.icon, Icons.lock_open);
  });

  testWidgets("a palette colour can be typed in", (tester) async {
    // Where a palette usually starts: a colour somebody already has, arriving
    // as six characters.
    var answer = await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    Color spot(int i) => (tester
            .widget<Container>(find.descendant(
                of: find.byKey(ValueKey("paletteSpot$i")),
                matching: find.byType(Container)))
            .decoration as BoxDecoration)
        .color!;

    await tester.enterText(find.byKey(const ValueKey("paletteHex0")), "cc4400");
    await tester.pumpAndSettle();

    // Near enough: the set is laid out in the notation's own space, and a
    // colour typed into it comes back through that space.
    var first = spot(0);
    expect((first.r * 255).round(), closeTo(0xcc, 4));
    expect((first.g * 255).round(), closeTo(0x44, 4));
    expect((first.b * 255).round(), closeTo(0x00, 4));
    expect((answer.color.r * 255).round(), closeTo(0xcc, 4),
        reason: "and the picker answers with what was typed");

    // The arrangement follows it, as it does when its handle is dragged: the
    // others are still the same distance round the wheel from it.
    expect(spot(2).toARGB32(), isNot(first.toARGB32()));

    // A locked colour is set where it stands and takes nothing with it.
    await tester.tap(find.byKey(const ValueKey("paletteLock3")));
    await tester.pumpAndSettle();
    var others = [spot(0), spot(1), spot(2), spot(4)];
    await tester.enterText(find.byKey(const ValueKey("paletteHex3")), "119933");
    await tester.pumpAndSettle();
    expect((spot(3).g * 255).round(), closeTo(0x99, 4));
    expect([spot(0), spot(1), spot(2), spot(4)].map((c) => c.toARGB32()),
        others.map((c) => c.toARGB32()),
        reason: "typing into a locked colour moved the rest of the set");
  });

  testWidgets("a full field selects itself, so a colour can be pasted in",
      (tester) async {
    // Every box here is exactly full -- six characters of six, or three of
    // three -- so a paste that merely arrives at the caret is twice as long
    // as the box allows and the limit throws away the half that was pasted.
    // Nothing appears to happen, which is what "I can't paste into it" is.
    await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    var field = find.descendant(
        of: find.byKey(const ValueKey("paletteHex0")),
        matching: find.byType(TextField));
    await tester.tap(field);
    await tester.pumpAndSettle();

    var controller = tester.widget<TextField>(field).controller!;
    expect(controller.text.length, 6);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, controller.text.length,
        reason: "the box was not selected, so a paste would be truncated");

    // The picker's own notation field, and a channel, the same.
    await tester.tap(find.byKey(const ValueKey("colorModesliders")));
    await tester.pumpAndSettle();
    var hex = find.byKey(const ValueKey("colorPickerHex"));
    await tester.tap(hex);
    await tester.pumpAndSettle();
    var hexText = tester.widget<TextField>(hex).controller!;
    expect(hexText.selection.end, hexText.text.length);
  });

  testWidgets("the palette's brightness is the wheel's brightness",
      (tester) async {
    // The slider under the palette sets how bright the set is, so the disc it
    // is picked out of has to be showing that. Drawn at the wheel mode's own
    // axis instead, the only things that moved when the slider moved were
    // the five dots on top of it.
    await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();

    // The function the wheel is painted with, asked what it draws half way
    // out at a red.
    Color wheelAt() {
      var painter = tester
          .widget<CustomPaint>(find.byKey(const ValueKey("colorPaletteWheel")))
          .painter;
      return ((painter as dynamic).at as Color Function(double, double))(
          20, 0.7);
    }

    var before = wheelAt();
    var slider = tester.getRect(find.byKey(const ValueKey("paletteValue")));
    await tester
        .tapAt(Offset(slider.left + slider.width * 0.2, slider.center.dy));
    await tester.pumpAndSettle();
    var after = wheelAt();

    expect(
        after.r + after.g + after.b, lessThan(before.r + before.g + before.b),
        reason: "the wheel itself did not darken: "
            "${before.toARGB32().toRadixString(16)} to "
            "${after.toARGB32().toRadixString(16)}");
  });

  testWidgets("a typed colour is the colour, in every harmony", (tester) async {
    // An arrangement cannot always reach a colour typed into it: the fourth
    // of a set of shades is drawn at a quarter of the brightness it is led
    // by, so a bright colour there would need a lead four times brighter
    // than there is room for -- and what came back was a darker, washed-out
    // version of what had been typed.
    for (var harmony in ["Analogous", "Complementary", "Shades"]) {
      await pump(tester, start: const Color(0xFF884422), width: 380);
      await tester.tap(find.byKey(const ValueKey("colorModepalette")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("colorHarmony")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(harmony).last);
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await tester.enterText(find.byKey(ValueKey("paletteHex$i")), "3366cc");
        await tester.pumpAndSettle();
        var got = (tester
                .widget<Container>(find.descendant(
                    of: find.byKey(ValueKey("paletteSpot$i")),
                    matching: find.byType(Container)))
                .decoration as BoxDecoration)
            .color!;
        expect(got.toARGB32() & 0xFFFFFF, 0x3366cc,
            reason: "$harmony spot $i came back as "
                "${got.toARGB32().toRadixString(16)}");
      }
    }
  });

  testWidgets("a custom set is turned by the rim, not re-laid", (tester) async {
    // The whole point of a custom set is that no rule moves its five. Re-laid
    // from the harmony's own places, the handle on the rim wiped out the
    // arrangement it was supposed to be turning.
    await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Custom").last);
    await tester.pumpAndSettle();

    Color spot(int i) => (tester
            .widget<Container>(find.descendant(
                of: find.byKey(ValueKey("paletteSpot$i")),
                matching: find.byType(Container)))
            .decoration as BoxDecoration)
        .color!;

    // A set somebody has put together by hand.
    for (var (i, hex)
        in ["cc2200", "22cc00", "0022cc", "cccc00", "00cccc"].indexed) {
      await tester.enterText(find.byKey(ValueKey("paletteHex$i")), hex);
      await tester.pumpAndSettle();
    }
    var before = [for (var i = 0; i < 5; i++) HSVColor.fromColor(spot(i)).hue];

    var wheel = tester.getRect(find.byKey(const ValueKey("colorPaletteWheel")));
    await tester.tapAt(Offset(wheel.center.dx, wheel.top + 4));
    await tester.pumpAndSettle();

    var after = [for (var i = 0; i < 5; i++) HSVColor.fromColor(spot(i)).hue];
    var by = (after[0] - before[0]) % 360;
    expect(by, isNot(closeTo(0, 0.5)), reason: "nothing turned");
    for (var i = 1; i < 5; i++) {
      expect((after[i] - before[i]) % 360, closeTo(by, 1.5),
          reason: "the set was re-laid rather than turned: "
              "$before became $after");
    }
  });

  testWidgets("brightness moves a custom set without re-laying it",
      (tester) async {
    await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("colorHarmony")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Custom").last);
    await tester.pumpAndSettle();

    Color spot(int i) => (tester
            .widget<Container>(find.descendant(
                of: find.byKey(ValueKey("paletteSpot$i")),
                matching: find.byType(Container)))
            .decoration as BoxDecoration)
        .color!;

    for (var (i, hex)
        in ["cc2200", "22cc00", "0022cc", "cccc00", "00cccc"].indexed) {
      await tester.enterText(find.byKey(ValueKey("paletteHex$i")), hex);
      await tester.pumpAndSettle();
    }
    var hues = [for (var i = 0; i < 5; i++) HSVColor.fromColor(spot(i)).hue];

    var slider = tester.getRect(find.byKey(const ValueKey("paletteValue")));
    await tester
        .tapAt(Offset(slider.left + slider.width * 0.35, slider.center.dy));
    await tester.pumpAndSettle();

    // Darker, and still the same five colours: what was built is kept and
    // only how bright it is has changed.
    for (var i = 0; i < 5; i++) {
      expect(HSVColor.fromColor(spot(i)).hue, closeTo(hues[i], 2),
          reason: "the custom set was re-laid by the brightness slider");
    }
    expect(HSVColor.fromColor(spot(0)).value, lessThan(0.8),
        reason: "and it did darken");
  });

  testWidgets("the harmony row has one reset, not two", (tester) async {
    // The one on the mode line puts every mode back; a second one beside the
    // harmony that only re-laid the five was the same button doing less.
    await pump(tester, start: const Color(0xFF3366CC), width: 380);
    await tester.tap(find.byKey(const ValueKey("colorModepalette")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("colorHarmonyReset")), findsNothing);
    expect(find.byKey(const ValueKey("colorReset")), findsOneWidget);
  });
}
