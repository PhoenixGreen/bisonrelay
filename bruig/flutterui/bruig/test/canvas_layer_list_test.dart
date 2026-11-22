import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';

import 'support/canvas_app.dart';

// canvas_layer_list_test.dart is the Layers panel where what it lists and
// what the document holds differ: a sound on the timeline is an element
// with no row here, and the background is a row that is not an element.

/// _between is two shapes with a sound on the timeline between them in the
/// document's order: the list shows B over A and nothing else.
CanvasDocument _between() => CanvasDocument(elements: [
      const ShapeElement(ElementBase(id: "a", name: "A")),
      AudioElement(const ElementBase(id: "s", name: "Sound", visible: false),
          clip: const MediaClip(
              playlist: [MediaSource(assetId: "t", length: 2)], timed: true)),
      const ShapeElement(ElementBase(id: "b", name: "B")),
    ]);

void main() {
  Future<void> show(WidgetTester tester, CanvasController c) async {
    setTestScreen(tester, const Size(600, 800));
    await tester.pumpWidget(canvasApp(
        SizedBox(width: 320, child: CanvasLayersPanel(controller: c))));
    await tester.pump();
  }

  /// listed is the ids of the layers with a row, bottom first.
  List<String> listed(CanvasController c) => [
        for (var e in c.document.elements)
          if (!isTimelineSound(e)) e.id
      ];

  testWidgets("Shift-click picks the rows between, not a sound with no row",
      (tester) async {
    // Deleting the selection then took the sound with it, unseen.
    var c = CanvasController(_between());
    addTearDown(c.dispose);
    await show(tester, c);
    expect(find.text("Sound"), findsNothing);

    await tester.tap(find.text("A"));
    // Past the window in which a second press is a double-click.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text("B"));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.selection, {"a", "b"});
  });

  testWidgets("Move forward and Move back pass over a sound with no row",
      (tester) async {
    // One press swapped the row with the sound, and nothing was seen to move.
    var c = CanvasController(_between());
    addTearDown(c.dispose);
    await show(tester, c);
    expect(listed(c), ["a", "b"]);

    // A, the lower row: forward, over B.
    await tester.tap(find.byTooltip("Move forward").last);
    await tester.pump();
    expect(listed(c), ["b", "a"]);
    // And A, now the upper row, back again.
    await tester.tap(find.byTooltip("Move back").first);
    await tester.pump();
    expect(listed(c), ["a", "b"]);
  });

  testWidgets("the top row cannot move forward, nor the bottom one back",
      (tester) async {
    // Though, in the document's order, a sound is over the top row.
    var c = CanvasController(CanvasDocument(elements: [
      ..._between().elements,
      AudioElement(const ElementBase(id: "s2", visible: false),
          clip: const MediaClip(
              playlist: [MediaSource(assetId: "t", length: 2)], timed: true)),
    ]));
    addTearDown(c.dispose);
    await show(tester, c);
    bool enabled(Finder button) =>
        tester
            .widget<InkWell>(
                find.descendant(of: button, matching: find.byType(InkWell)))
            .onTap !=
        null;
    expect(enabled(find.byTooltip("Move forward").first), isFalse);
    expect(enabled(find.byTooltip("Move forward").last), isTrue);
    expect(enabled(find.byTooltip("Move back").first), isTrue);
    expect(enabled(find.byTooltip("Move back").last), isFalse);
  });

  testWidgets("the background's row names a 3D stage and a parallax backdrop",
      (tester) async {
    // It named the pattern's style whatever the backdrop was.
    for (var (kind, name) in [
      (BackdropKind.flat, "Background — Plain"),
      (BackdropKind.stage, "Background — 3D stage"),
      (BackdropKind.parallax, "Background — Parallax"),
    ]) {
      var c = CanvasController(const CanvasDocument()
          .copyWith(background: CanvasBackground(backdrop: kind)));
      await show(tester, c);
      expect(find.text(name), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });
}
