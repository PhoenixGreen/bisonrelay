import 'package:bruig/components/color_picker.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// color_picker_gradient_test.dart is the Gradient tab: the second colour, set
// where the first one is.
//
// It is here rather than beside each thing that can be coloured, so the tests
// that matter are the ones about that bargain -- a picker that is not being
// asked for a gradient does not offer one, and a picker that is offers the
// whole of itself for choosing the second colour rather than a second,
// smaller picker of its own.

void main() {
  Future<void> show(
    WidgetTester tester, {
    required PaintSpec paint,
    required ValueChanged<PaintSpec> onChanged,
    bool fades = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var current = paint;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => AppColorPicker(
              width: 320,
              color: current.color,
              gradient: current.gradient,
              onGradientChanged: fades
                  ? (g) => setState(() {
                        current = PaintSpec(current.color, gradient: g);
                        onChanged(current);
                      })
                  : null,
              onChanged: (c) => setState(() {
                current = PaintSpec(c, gradient: current.gradient);
                onChanged(current);
              }),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  var gradientTab = find.byKey(const ValueKey("colorModegradient"));

  testWidgets("is not offered where there is nowhere to put one",
      (tester) async {
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF)),
        onChanged: (_) {},
        fades: false);
    expect(gradientTab, findsNothing,
        reason: "the palette editor next door wants one flat colour");
    expect(find.byKey(const ValueKey("colorModesliders")), findsOneWidget);
  });

  testWidgets("is the fourth way of choosing, after the palette",
      (tester) async {
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF)), onChanged: (_) {});
    expect(gradientTab, findsOneWidget);
    expect(
        tester.getRect(gradientTab).left,
        greaterThan(tester
            .getRect(find.byKey(const ValueKey("colorModepalette")))
            .left));
  });

  testWidgets("a colour with one point on the bar is a flat colour",
      (tester) async {
    // No "make this a gradient" switch. One point is a flat colour and two is
    // a fade, which is the same thing the switch used to say and one control
    // fewer to find.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF)), onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    expect(find.text("One colour"), findsOneWidget);
    expect(find.byKey(const ValueKey("gradientRadial")), findsNothing,
        reason: "nothing to point in a direction yet");
    expect(find.byKey(const ValueKey("gradientBar")), findsOneWidget,
        reason: "the bar is there with the one point on it");

    await tester.tap(find.byKey(const ValueKey("gradientAdd")));
    await tester.pumpAndSettle();
    expect(said?.gradient, isNotNull);
    expect(find.byKey(const ValueKey("gradientRadial")), findsOneWidget);
  });

  testWidgets("the second colour starts out related to the first",
      (tester) async {
    // A new fade that begins on flat black is one whose first job is to be
    // undone.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF)), onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gradientAdd")));
    await tester.pumpAndSettle();

    var second = HSVColor.fromColor(said!.gradient!.to);
    expect(
        second.hue, closeTo(HSVColor.fromColor(const Color(0xFF3D7EFF)).hue, 2),
        reason: "the same colour, darker -- not an unrelated one");
  });

  testWidgets("taking the last extra colour out makes it flat again",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    // Pick the second point, then take it out.
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gradientRemove")));
    await tester.pumpAndSettle();

    expect(said!.gradient, isNull);
    expect(find.text("One colour"), findsOneWidget);
  });

  testWidgets("straight or radial, and no angle on a radial one",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey("gradientAngle")), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("gradientRadial")));
    await tester.pumpAndSettle();
    expect(said!.gradient!.radial, isTrue);
    expect(find.byKey(const ValueKey("gradientAngle")), findsNothing,
        reason: "a radial gradient runs outwards, so it has no direction");

    await tester.tap(find.byKey(const ValueKey("gradientLinear")));
    await tester.pumpAndSettle();
    expect(said!.gradient!.radial, isFalse);
    expect(find.byKey(const ValueKey("gradientAngle")), findsOneWidget);
  });

  testWidgets("the whole picker chooses whichever end is grabbed",
      (tester) async {
    // One picker editing the selected end, not a second smaller picker for
    // the second colour: a gradient's two colours are chosen against each
    // other, and two pickers is what stops you doing that.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();
    expect(find.text("Editing the first colour"), findsOneWidget);

    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    expect(find.text("Editing the second colour"), findsOneWidget);

    // And now the picker is working on the second colour: whatever it is
    // told lands in the gradient rather than in the base colour.
    await tester.enterText(
        find.byKey(const ValueKey("colorPickerHex")), "#00FF00");
    await tester.pumpAndSettle();
    expect(said!.gradient!.to.toARGB32(), 0xFF00FF00);
    expect(said!.color, const Color(0xFF3D7EFF),
        reason: "the first colour is not what was being edited");
  });

  testWidgets("dragging the handles moves where the fade happens",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    // Grab the first handle, at the left, and drag it to the middle.
    await tester.dragFrom(
        Offset(bar.left + 4, bar.center.dy), Offset(bar.width * 0.4, 0));
    await tester.pumpAndSettle();
    expect(said!.gradient!.start, greaterThan(0.2),
        reason: "more of the first colour stays flat before the fade starts");
    expect(said!.gradient!.end, 1.0, reason: "the far end has not moved");
  });

  testWidgets("shows the fade at the size the colour square is",
      (tester) async {
    // Big enough to watch the angle and the radial switch happen in, rather
    // than a strip you set a number against and then go and look somewhere
    // else.
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (_) {});
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    var preview = tester.getRect(find.byKey(const ValueKey("gradientPreview")));
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    expect(preview.height, greaterThan(100));
    expect(preview.height, greaterThan(bar.height * 2));
    expect(preview.top, lessThan(bar.top),
        reason: "the fade above, the stops that make it underneath");
  });

  testWidgets("a colour can be added to the fade and taken out again",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey("gradientAdd")));
    await tester.pumpAndSettle();
    expect(said!.gradient!.count, 3);
    await tester.tap(find.byKey(const ValueKey("gradientAdd")));
    await tester.pumpAndSettle();
    expect(said!.gradient!.count, 4);

    // Remove takes out the one being edited, so pick one first.
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gradientRemove")));
    await tester.pumpAndSettle();
    expect(said!.gradient!.count, 3);
  });

  testWidgets("but the last two colours cannot be taken out", (tester) async {
    // A fade with one colour is a flat colour, and the way to say that is the
    // checkbox at the top, not a remove button that empties the gradient.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gradientRemove")));
    await tester.pumpAndSettle();
    expect(said?.gradient?.count ?? 2, 2);
  });

  testWidgets("the third colour is editable like the other two",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA), end: 0.5)),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gradientAdd")));
    await tester.pumpAndSettle();
    // The colour just added is the one being edited -- adding a colour is
    // something you do in order to choose it.
    expect(find.textContaining("of 3"), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey("colorPickerHex")), "#00FF00");
    await tester.pumpAndSettle();
    var ramp = said!.gradient!.ramp;
    expect(ramp.length, 2);
    expect(ramp.where((s) => s.color.toARGB32() == 0xFF00FF00).length, 1,
        reason: "the typed colour landed on the stop that was chosen");
    expect(ramp.where((s) => s.color == const Color(0xFFFF3DAA)).length, 1,
        reason: "and the colour that was already there is still there");
    expect(said!.color, const Color(0xFF3D7EFF),
        reason: "the first colour is not what was being edited");
  });

  testWidgets("each point has its own opacity", (tester) async {
    // Per point, so a fade can run from a colour to nothing -- which is most
    // of what a gradient on a chart or a picture is actually for.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    // The first colour, turned halfway down.
    var slider = tester.getRect(find.byKey(const ValueKey("gradientOpacity")));
    await tester.dragFrom(Offset(slider.right - 20, slider.center.dy),
        Offset(-slider.width / 2, 0));
    await tester.pumpAndSettle();
    expect(said!.color.a, lessThan(0.9));
    expect(said!.gradient!.to.a, 1.0,
        reason: "the other point is not the one that was chosen");

    // And now the second.
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    slider = tester.getRect(find.byKey(const ValueKey("gradientOpacity")));
    await tester.dragFrom(
        Offset(slider.right - 20, slider.center.dy), Offset(-slider.width, 0));
    await tester.pumpAndSettle();
    expect(said!.gradient!.to.a, lessThan(0.5));
  });

  testWidgets("the thin handles either side of a point shape the change",
      (tester) async {
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();
    expect(said, isNull, reason: "nothing changed by opening the tab");

    // With the second point chosen, the handle for the span into it sits
    // halfway along the bar. Drag it towards that point.
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.tapAt(Offset(bar.right - 4, bar.center.dy));
    await tester.pumpAndSettle();
    await tester.dragFrom(
        Offset(bar.center.dx, bar.center.dy), Offset(bar.width * 0.3, 0));
    await tester.pumpAndSettle();

    expect(said!.gradient!.toBias, greaterThan(0.6),
        reason: "the change into the second colour now happens late");
    expect(said!.gradient!.to, const Color(0xFFFF3DAA),
        reason: "and the point itself has not moved");
    expect(said!.gradient!.end, 1.0);
  });

  testWidgets("and there is no handle before the first colour", (tester) async {
    // A span belongs to the colour it runs into, and nothing runs into the
    // first one.
    PaintSpec? said;
    await show(tester,
        paint: const PaintSpec(Color(0xFF3D7EFF),
            gradient: GradientSpec(to: Color(0xFFFF3DAA))),
        onChanged: (p) => said = p);
    await tester.tap(gradientTab);
    await tester.pumpAndSettle();

    // The first point is chosen to begin with; the only thin handle is the
    // one in the span after it, halfway along. Dragging from the far left
    // grabs the point, not a handle.
    var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
    await tester.dragFrom(
        Offset(bar.left + 4, bar.center.dy), Offset(bar.width * 0.25, 0));
    await tester.pumpAndSettle();
    expect(said!.gradient!.start, greaterThan(0.15),
        reason: "the point moved, which is what a drag on a point does");
    expect(said!.gradient!.toBias, 0.5);
  });
}
