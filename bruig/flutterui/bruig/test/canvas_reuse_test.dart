import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_reuse_test.dart is one design used in many places: a named text
// style, linked copies of an element, and several elements arriving in turn.

TextElement _text(String id, {double x = 0}) =>
    TextElement(ElementBase(id: id, x: x, width: 300, height: 60),
        text: id, textSpec: const TextSpec(fontSize: 30));

ShapeElement _shape(String id, double x, int arrives) =>
    ShapeElement(ElementBase(
        id: id,
        x: x,
        track: ElementTrack([
          Keyframe(frame: arrives, values: const {KeyframeChannel.reveal: 0}),
          Keyframe(
              frame: arrives + 10, values: const {KeyframeChannel.reveal: 1}),
        ])));

CanvasDocument _scenes() => CanvasDocument(scenes: [
      CanvasScene(id: "a", frames: 100, elements: [_text("head1")]),
      CanvasScene(id: "b", frames: 100, elements: [_text("head2")]),
    ]);

TextElement _find(CanvasController c, String id) {
  for (var s in c.document.allScenes) {
    for (var e in s.elements) {
      if (e.id == id) return e as TextElement;
    }
  }
  throw StateError(id);
}

Future<void> _panel(WidgetTester tester, CanvasController c) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ChangeNotifierProvider<CanvasPreferences>(
          create: (c) => CanvasPreferences()),
    ],
    child: MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group("text styles", () {
    test("changing a style restyles every text in it, in every scene", () {
      var c = CanvasController(_scenes());
      addTearDown(c.dispose);
      var name = c.saveTextStyle(_find(c, "head1"));
      expect(name, "Style 1");
      c.useTextStyle("head2", name);
      c.updateTextStyle(name, const TextSpec(fontSize: 64, weight: 900));
      expect(_find(c, "head1").textSpec.fontSize, 64);
      expect(_find(c, "head2").textSpec.weight, 900);
      c.undo();
      expect(_find(c, "head2").textSpec.fontSize, 30, reason: "one change");
    });

    test("renaming and removing keep the texts", () {
      var c = CanvasController(_scenes());
      addTearDown(c.dispose);
      var name = c.saveTextStyle(_find(c, "head1"), name: "Heading");
      c.renameTextStyle(name, "Title");
      expect(_find(c, "head1").style, "Title");
      c.removeTextStyle("Title");
      expect(_find(c, "head1").style, "");
      expect(_find(c, "head1").textSpec.fontSize, 30);
    });

    test("styles are saved", () {
      var d = _scenes().copyWith(
          textStyles: const [NamedTextStyle("Label", TextSpec(fontSize: 12))]);
      var back = CanvasDocument.decode(d.encode())!;
      expect(back.textStyles.single.name, "Label");
      expect(back.textStyles.single.spec.fontSize, 12);
    });
  });

  group("linked copies", () {
    test("pushing gives the copies the design, keeping their place and time",
        () {
      var c = CanvasController(
          const CanvasDocument().addElement(_shape("s", 100, 5)));
      addTearDown(c.dispose);
      c.linkedCopy("s");
      var copy = c.selection.single;
      var moved = c.document.elementById(copy)!.withBase(x: 700);
      c.apply(c.document.withElement(moved));
      var source = c.document.elementById("s") as ShapeElement;
      c.apply(c.document.withElement(
          source.copyWith(fill: const Color(0xFFFF3B5C), strokeWidth: 4)));
      expect(c.pushToLinked("s"), 1);
      var after = c.document.elementById(copy) as ShapeElement;
      expect(after.fill, const Color(0xFFFF3B5C));
      expect(after.strokeWidth, 4);
      expect(after.x, 700, reason: "its own place");
      expect(after.id, copy);
    });

    test("an unlinked copy is left alone", () {
      var c = CanvasController(
          const CanvasDocument().addElement(_shape("s", 100, 5)));
      addTearDown(c.dispose);
      c.linkedCopy("s");
      var copy = c.selection.single;
      c.unlink(copy);
      expect(c.pushToLinked("s"), 0);
    });
  });

  test("arrivals are staggered left to right, the first kept", () {
    var c = CanvasController(const CanvasDocument()
        .addElement(_shape("right", 600, 40))
        .addElement(_shape("left", 100, 10))
        .addElement(_shape("middle", 300, 0)));
    addTearDown(c.dispose);
    c.staggerArrivals(["right", "left", "middle"], 8);
    int at(String id) =>
        c.document.elementById(id)!.base.track!.keys.first.frame;
    expect(at("left"), 10);
    expect(at("middle"), 18);
    expect(at("right"), 26);
  });

  group("the panel", () {
    testWidgets("a text's Style row saves and updates a style", (tester) async {
      var c = CanvasController(const CanvasDocument().addElement(_text("t")));
      addTearDown(c.dispose);
      c.selectOnly("t");
      await _panel(tester, c);
      await tester.ensureVisible(find.byKey(const ValueKey("textStyleSave")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("textStyleSave")));
      await tester.pumpAndSettle();
      expect(c.textStyles, hasLength(1));
      expect((c.document.elements.single as TextElement).style, "Style 1");
      expect(find.byKey(const ValueKey("textStyleUpdate")), findsOneWidget);
    });

    testWidgets("there is no linked-copy row: designs are kept as presets",
        (tester) async {
      var c = CanvasController(
          const CanvasDocument().addElement(_shape("s", 100, 5)));
      addTearDown(c.dispose);
      c.selectOnly("s");
      await _panel(tester, c);
      expect(find.byKey(const ValueKey("elementLinks")), findsNothing);
      expect(find.byKey(const ValueKey("linkedCopy")), findsNothing);
    });

    testWidgets("several selected can be staggered", (tester) async {
      var c = CanvasController(const CanvasDocument()
          .addElement(_shape("a", 100, 0))
          .addElement(_shape("b", 300, 0)));
      addTearDown(c.dispose);
      c.selectOnly("a");
      c.toggleSelected("b");
      await _panel(tester, c);
      tester
          .widget<CanvasNumberField>(find.byKey(const ValueKey("staggerGap")))
          .onChanged(12);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("staggerApply")));
      await tester.pumpAndSettle();
      expect(c.document.elementById("b")!.base.track!.keys.first.frame, 12);
    });
  });
}
