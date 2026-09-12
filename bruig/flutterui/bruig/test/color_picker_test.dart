import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/saved_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// color_picker_test.dart is the app's one colour picker: the parts of it that
// were bugs in the package it replaced, and the saved colours it adds.

Future<Color> pump(WidgetTester tester,
    {Color start = const Color(0xFF000000), bool allowAlpha = true}) async {
  var current = start;
  // No provider around it: the picker takes its colours from Material's own
  // scheme, so it works wherever there is a Theme -- which is every panel,
  // every dialog and every test that pumps one.
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => AppColorPicker(
          color: current,
          allowAlpha: allowAlpha,
          onChanged: (c) => setState(() => current = c),
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

    expect(find.byType(Wrap), findsNothing, reason: "nothing saved yet");
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
}
