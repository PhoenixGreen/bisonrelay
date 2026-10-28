import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_sprite_test.dart is the Sprite element: a sheet sliced into frames
// -- by its gaps, its grid or its own notes -- actions played from them for
// the way it faces, cues on the timeline, and the frame drawn.

class _Pictures extends CanvasImageSource {
  final Map<String, ui.Image> held;
  _Pictures(this.held);

  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => held[assetId];
}

/// _sheet is a sheet of 4 frames across and 2 down, each 16 pixels square
/// with a clear pixel of gap round it, each frame its own colour.
Future<ui.Image> _sheet() async {
  var rec = ui.PictureRecorder();
  var canvas = ui.Canvas(rec);
  for (var r = 0; r < 2; r++) {
    for (var c = 0; c < 4; c++) {
      canvas.drawRect(ui.Rect.fromLTWH(c * 18.0 + 1, r * 18.0 + 1, 16, 16),
          ui.Paint()..color = ui.Color.fromARGB(255, 40 + c * 50, r * 200, 100));
    }
  }
  return rec.endRecording().toImage(72, 36);
}

SpriteElement _sprite() => const SpriteElement(ElementBase(id: "s", x: 0, y: 0, width: 100, height: 100));

void main() {
  test("a sheet is sliced by the gaps between its frames, a row an action", () async {
    var made = await spriteFromSheet(_sprite(), "sheet", "Hero", await _sheet());
    expect((made.columns, made.rows), (4, 2));
    expect(made.frameCount, 8);
    expect(made.frameRect(5), const ui.Rect.fromLTWH(18, 18, 18, 18));
    expect(made.actions.map((a) => a.name), ["Row 1", "Row 2"]);
    expect(made.actions[1].frames[SpriteFacing.front], [4, 5, 6, 7]);
    expect(made.assetIds, {"sheet"}, reason: "its sheet kept while it is used");
  });

  test("an action plays at its speed, loops or holds, and a side mirrors the other", () {
    var e = _sprite().copyWith(sheet: "x", sheetW: 64, sheetH: 32, columns: 4, rows: 2, actions: [
      const SpriteAction("Walk", frames: {
        SpriteFacing.front: [0, 1, 2, 3],
        SpriteFacing.right: [4, 5],
      }, fps: 6),
      const SpriteAction("Jump", frames: {SpriteFacing.front: [6, 7]}, fps: 6, loop: false),
    ], action: "Walk");
    // At 12 frames a second, a frame of the action every two.
    expect([for (var f = 0; f < 10; f += 2) e.sheetFrameAt(f, 12)!.$1], [0, 1, 2, 3, 0]);
    var right = e.copyWith(facing: SpriteFacing.right);
    expect(right.sheetFrameAt(2, 12), (5, false));
    var left = e.copyWith(facing: SpriteFacing.left);
    expect(left.sheetFrameAt(2, 12), (5, true), reason: "the right side, flipped");
    expect(e.copyWith(facing: SpriteFacing.back).sheetFrameAt(0, 12), (0, false), reason: "the front's");
    // Cued to jump on frame 24, facing right: once, then held on its last.
    var cued = e.copyWith(cues: const [(frame: 24, action: "Jump", facing: SpriteFacing.right)]);
    expect(cued.sheetFrameAt(23, 12)!.$1, isNot(6));
    expect(cued.sheetFrameAt(24, 12), (6, false));
    expect(cued.sheetFrameAt(60, 12), (7, false), reason: "held, not looped");
    expect(cued.facingAt(30), SpriteFacing.right);
  });

  test("saved and read back, and made new from the Elements panel", () {
    var e = _sprite().copyWith(
        sheet: "x",
        sheetName: "Hero",
        sheetW: 64,
        sheetH: 32,
        columns: 4,
        rows: 2,
        margin: 1,
        actions: const [SpriteAction("Walk", frames: {SpriteFacing.back: [1, 2]}, fps: 10, loop: false)],
        action: "Walk",
        cues: const [(frame: 3, action: "Walk", facing: SpriteFacing.left)],
        pixelArt: false,
        facing: SpriteFacing.back);
    var back = elementFromJson(e.toJson()) as SpriteElement;
    expect(back.toJson(), e.toJson());
    var made = newElement(ElementKind.sprite, const CanvasDocument());
    expect(made, isA<SpriteElement>());
    expect((made as SpriteElement).hasSheet, isFalse);
  });

  test("an Aseprite sheet's notes: its frames and its tags", () {
    var notes = SheetNotes.read("""
{"frames": {
  "hero 0.aseprite": {"frame": {"x": 0, "y": 0, "w": 20, "h": 24}, "duration": 100},
  "hero 1.aseprite": {"frame": {"x": 20, "y": 0, "w": 20, "h": 24}, "duration": 100},
  "hero 2.aseprite": {"frame": {"x": 40, "y": 0, "w": 20, "h": 24}, "duration": 200}
 },
 "meta": {"image": "hero.png", "size": {"w": 60, "h": 24},
   "frameTags": [{"name": "Idle", "from": 0, "to": 1, "direction": "forward"},
                 {"name": "Wave", "from": 1, "to": 2, "direction": "pingpong"}]}}
""")!;
    expect(notes.frames, hasLength(3));
    expect(notes.frames[2], const ui.Rect.fromLTWH(40, 0, 20, 24));
    expect((notes.width, notes.height, notes.image), (60, 24, "hero.png"));
    expect(notes.actions.map((a) => a.name), ["Idle", "Wave"]);
    expect(notes.actions.first.fps, closeTo(10, 1e-9));
    expect(SheetNotes.read("not json"), isNull);
    expect(SheetNotes.read('{"layers": []}'), isNull);
  });

  test("drawn: the frame it is on, standing on the bottom of its box", () async {
    var sheet = await _sheet();
    var e = (await spriteFromSheet(_sprite(), "sheet", "Hero", sheet)).copyWith(action: "Row 2");
    Future<List<int>> pixels(SpriteElement s, int frame) async {
      var rec = ui.PictureRecorder();
      paintSprite(ui.Canvas(rec), const ui.Rect.fromLTWH(0, 0, 90, 90), s, frame,
          images: _Pictures({"sheet": sheet}));
      var img = await rec.endRecording().toImage(90, 90);
      return (await img.toByteData())!.buffer.asUint8List();
    }

    var first = await pixels(e, 0);
    // Row 2's first frame is red-ish 40 and green 200: its middle.
    var i = (45 * 90 + 45) * 4;
    expect(first[i + 1], greaterThan(150), reason: "row 2's frame drawn");
    // At 8 a second on a canvas of 12, a frame and a half of the canvas to
    // each of the action's: canvas frame 2 is its second.
    expect(await pixels(e, 2), isNot(first), reason: "a later frame, another colour");
    // With no sheet, a placeholder -- not nothing, not a crash.
    var empty = await pixels(_sprite(), 0);
    expect(empty.where((v) => v != 0), isNotEmpty);
  });

  group("its settings", () {
    setUpAll(() => CanvasSection.openAll = true);
    tearDownAll(() => CanvasSection.openAll = false);

    testWidgets("actions added and named, facing picked, frames by row, cues", (tester) async {
      SharedPreferences.setMockInitialValues({});
      var start = _sprite().copyWith(
          sheet: "missing", sheetW: 64, sheetH: 32, columns: 4, rows: 2,
          actions: const [SpriteAction("Row 1", frames: {SpriteFacing.front: [0, 1, 2, 3]})],
          action: "Row 1");
      var c = CanvasController(CanvasDocument(frames: 48).addElement(start));
      addTearDown(c.dispose);
      c.selectOnly("s");
      tester.view.physicalSize = const ui.Size(900, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: SizedBox(width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      SpriteElement get() => c.document.elementById("s") as SpriteElement;
      expect(find.byKey(const ValueKey("spriteSheetView")), findsOneWidget);
      // An action added from the usual ones.
      tester.widget<CanvasDropdown<String>>(find.byKey(const ValueKey("spriteActionAdd"))).onChanged("Walk");
      await tester.pumpAndSettle();
      expect(get().action, "Walk");
      // Facing right, the second row.
      await tester.ensureVisible(find.byKey(const ValueKey("spriteFacing-right")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("spriteFacing-right")));
      await tester.pumpAndSettle();
      expect(get().facing, SpriteFacing.right);
      tester.widget<CanvasDropdown<int>>(find.byKey(const ValueKey("spriteUseRow"))).onChanged(1);
      await tester.pumpAndSettle();
      expect(get().actionNamed("Walk")!.frames[SpriteFacing.right], [4, 5, 6, 7]);
      // A frame clicked on the sheet: the first of row 1, added after them.
      var view = find.byKey(const ValueKey("spriteSheetView"));
      await tester.ensureVisible(view);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(view) + const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(get().actionNamed("Walk")!.frames[SpriteFacing.right], [4, 5, 6, 7, 0]);
      // Cued here.
      await tester.ensureVisible(find.byKey(const ValueKey("spriteCueAdd")));
      await tester.tap(find.byKey(const ValueKey("spriteCueAdd")));
      await tester.pumpAndSettle();
      expect(get().cues.single.action, "Walk");
      expect(tester.takeException(), isNull);
    });
  });
}
