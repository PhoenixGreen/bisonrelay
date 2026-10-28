import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_painter.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_pixels.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/sprite_painting.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_export.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
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
    var e = _sprite().copyWith(sheet: "x", sheetW: 64, sheetH: 32, columns: 4, rows: 2, directions: true, actions: [
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
      // A figure: directions on, facing right, the second row.
      expect(find.byKey(const ValueKey("spriteFacing-right")), findsNothing,
          reason: "a sprite is not a figure until it has directions");
      await tester.ensureVisible(find.byKey(const ValueKey("spriteDirections")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("spriteDirections")));
      await tester.pumpAndSettle();
      expect(get().directions, isTrue);
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
      // The frames as thumbnails, picked and moved with buttons.
      await tester.ensureVisible(find.byKey(const ValueKey("spriteFrame-4")));
      await tester.tap(find.byKey(const ValueKey("spriteFrame-4")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("spriteFrameEarlier")));
      await tester.pumpAndSettle();
      expect(get().actionNamed("Walk")!.frames[SpriteFacing.right], [4, 5, 6, 0, 7]);
      await tester.tap(find.byKey(const ValueKey("spriteFrameRemove")));
      await tester.pumpAndSettle();
      expect(get().actionNamed("Walk")!.frames[SpriteFacing.right], [4, 5, 6, 7]);
      expect(find.byKey(const ValueKey("spritePreview")), findsOneWidget);
      // Cued here.
      await tester.ensureVisible(find.byKey(const ValueKey("spriteCueAdd")));
      await tester.tap(find.byKey(const ValueKey("spriteCueAdd")));
      await tester.pumpAndSettle();
      expect(get().cues.single.action, "Walk");
      expect(tester.takeException(), isNull);
    });
  });

  group("painted", () {
    late Directory library;
    setUpAll(() {
      library = Directory.systemTemp.createTempSync("sprite_paint_test");
      CanvasStorage.rootOverride = library.path;
    });
    tearDownAll(() {
      CanvasStorage.rootOverride = null;
      library.deleteSync(recursive: true);
    });

    test("pixels: dabs, lines with no gaps, a fill kept to its frame, frames copied", () async {
      var p = SpritePixels.blank(8, 4);
      const red = ui.Color(0xFFFF0000), blue = ui.Color(0xFF0000FF);
      p.line(0, 0, 3, 3, red);
      expect([for (var k = 0; k < 4; k++) p.at(k, k)], List.filled(4, red));
      // A fill of the clear left frame, kept to it.
      p.fill(0, 3, blue, within: const ui.Rect.fromLTWH(0, 0, 4, 4));
      expect(p.at(0, 3), blue);
      expect(p.at(5, 0).a, 0, reason: "not past its frame");
      p.copyFrame(const ui.Rect.fromLTWH(0, 0, 4, 4), const ui.Rect.fromLTWH(4, 0, 4, 4));
      expect(p.at(6, 2), red);
      var g = p.grown(12, 4);
      expect((g.width, g.at(6, 2), g.at(10, 0).a), (12, red, 0));
      var back = await SpritePixels.of(await g.image());
      expect(back!.at(6, 2), red);
    });

    test("painted on: each stroke kept as the sheet, one undo; frames added and copied", () async {
      var c = CanvasController(const CanvasDocument().addElement(
          const SpriteElement(ElementBase(id: "s", x: 0, y: 0, width: 160, height: 160))));
      addTearDown(c.dispose);
      var made = await blankSprite(c, c.document.elementById("s") as SpriteElement, 16, 16, 2);
      c.replaceElement(made!.rebase(made.base.copyWith(width: 160, height: 160)));
      expect(made.frameCount, 2);
      c.paintSprite("s");
      var session = c.spritePaint!;
      session.set(colour: const ui.Color(0xFF00AA00), size: 2);
      var before = (c.document.elementById("s") as SpriteElement).sheet;
      // Across the middle of the first frame, shown 160 across: 10 a pixel.
      await session.strokeStart(const ui.Offset(15, 80));
      await session.strokeTo(const ui.Offset(145, 80));
      await session.strokeEnd();
      var e = c.document.elementById("s") as SpriteElement;
      expect(e.sheet, isNot(before), reason: "kept as a new sheet");
      var px = await SpritePixels.of(session.view(e).live!);
      expect(px!.at(8, 8).toARGB32(), 0xFF00AA00);
      expect(px.at(20, 8).a, 0, reason: "the second frame left alone");
      c.undo();
      expect((c.document.elementById("s") as SpriteElement).sheet, before, reason: "one undo");
      // A frame copied: the sheet a frame wider, the frame in the animation.
      await session.strokeStart(const ui.Offset(80, 80));
      await session.strokeEnd();
      await session.addFrame(copy: true);
      e = c.document.elementById("s") as SpriteElement;
      expect((e.columns, e.sheetW, e.frameCount), (3, 48, 3));
      expect(e.actionNamed("Play")!.frames[SpriteFacing.front], [0, 1, 2]);
      expect(session.frame, 2);
      var grown = await SpritePixels.of(session.view(e).live!);
      expect(grown!.at(32 + 8, 8).toARGB32(), 0xFF00AA00, reason: "the frame copied");
      // Shown as painted: the frame still, not playing.
      var view = session.view(e);
      expect(view.frame, 2);
      expect(view.onion, 1, reason: "the frame before it, faintly");
      c.paintSprite(null);
      expect(spritePaintingOf, isNull);
    });

    test("saved out: a row an animation, its notes read back; an animation as a GIF", () async {
      var sheet = await _sheet();
      var e = (await spriteFromSheet(_sprite(), "sheet", "Hero", sheet)).copyWith(
          directions: true,
          actions: const [
            SpriteAction("Walk", frames: {SpriteFacing.front: [0, 1, 2], SpriteFacing.right: [4, 5]}, fps: 5),
            SpriteAction("Idle", frames: {SpriteFacing.front: [3]}),
          ],
          action: "Walk");
      var rows = exportRows(e);
      expect(rows.map((r) => r.name), ["Walk front", "Walk back", "Walk left", "Walk right", "Idle front",
        "Idle back", "Idle left", "Idle right"]);
      expect(rows[2].frames, [(4, true), (5, true)], reason: "the left, the right flipped");
      var (png, notes) = (await exportSheet(e, sheet, image: "hero.png"))!;
      var read = SheetNotes.read(notes)!;
      expect(read.image, "hero.png");
      expect(read.frames.length, rows.fold<int>(0, (n, r) => n + r.frames.length));
      expect(read.actions.first.name, "Walk front");
      expect(read.actions.first.fps, closeTo(5, 0.01));
      var decoded = await (await ui.instantiateImageCodec(png)).getNextFrame();
      expect((decoded.image.width, decoded.image.height), (read.width, read.height));
      var gif = (await exportGif(e, sheet, "Walk"))!;
      expect(String.fromCharCodes(gif.take(6)), "GIF89a");
      var codec = await ui.instantiateImageCodec(gif);
      expect(codec.frameCount, 3);
      expect((await codec.getNextFrame()).duration, const Duration(milliseconds: 200));
    });

    test("made from a character: its frames from the playhead, turned each way", () async {
      var who = CharacterElement(const ElementBase(id: "c", x: 0, y: 0, width: 100, height: 200),
          dna: CharacterType.boy.dna, pose: posePresets[1].pose);
      var made = (await spriteFromCharacter(_sprite(), who, from: 0, count: 3, directions: true, cell: 64))!;
      expect((made.columns, made.rows, made.frameCount), (3, 4, 12));
      expect(made.directions, isTrue);
      expect(made.actions.single.frames[SpriteFacing.back], [6, 7, 8]);
      // Something drawn in each row.
      var p = await SpritePixels.of((await (await ui.instantiateImageCodec(
              await File((await CanvasAssets.pathOf(made.sheet))!).readAsBytes()))
          .getNextFrame())
          .image);
      for (var r = 0; r < 4; r++) {
        var cell = made.frameRect(r * 3);
        var any = false;
        for (var y = cell.top.toInt(); y < cell.bottom && !any; y += 2) {
          for (var x = cell.left.toInt(); x < cell.right && !any; x += 2) {
            if (p!.at(x, y).a > 0) any = true;
          }
        }
        expect(any, isTrue, reason: "row $r drawn");
      }
    });
  });
}
