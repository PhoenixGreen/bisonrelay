import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_builder.dart';
import 'package:bruig/plugin_system/canvas/render/sprite_pixels.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/sprite_builder_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_sprite_builder_test.dart is a figure built from Kenney's modular
// character pack: its pieces found by their names -- named either way
// round, as the pack has them -- put together, and its animations drawn
// into a Sprite's sheet. A small pack stands in for his.

Future<Uint8List> _png(int w, int h, ui.Color c) async {
  var rec = ui.PictureRecorder();
  ui.Canvas(rec).drawColor(c, ui.BlendMode.src);
  var img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

Future<Archive> _pack() async {
  var a = Archive();
  Future<void> add(String name, int w, int h, int colour) async {
    var b = await _png(w, h, ui.Color(colour));
    a.addFile(ArchiveFile(name, b.length, b));
  }

  const skin = 0xFFF6CCA0;
  for (var (p, w, h) in [("arm", 170, 136), ("hand", 61, 71), ("head", 173, 168), ("leg", 93, 164), ("neck", 96, 37)]) {
    await add("PNG/Skin/Tint 1/tint1_$p.png", w, h, skin);
  }
  await add("PNG/Hair/Black/blackMan1.png", 158, 119, 0xFF222222);
  await add("PNG/Shirts/Blue/blueShirt1.png", 153, 174, 0xFF3366CC);
  await add("PNG/Shirts/Blue/blueArm_short.png", 118, 96, 0xFF3366CC);
  await add("PNG/Shirts/Yellow/shirtYellow1.png", 153, 174, 0xFFFFCC00);
  await add("PNG/Shirts/Yellow/armYellow_long.png", 171, 142, 0xFFFFCC00);
  await add("PNG/Pants/Blue 1/pantsBlue11.png", 153, 47, 0xFF224488);
  await add("PNG/Pants/Blue 1/pantsBlue1_long.png", 111, 166, 0xFF224488);
  await add("PNG/Pants/Yellow/pantsYellow1.png", 153, 47, 0xFFCCAA00);
  await add("PNG/Pants/Yellow/legYellow_long.png", 111, 166, 0xFFCCAA00);
  await add("PNG/Shoes/Brown 1/brown1Shoe1.png", 94, 42, 0xFF663300);
  await add("PNG/Face/Eyes/eyeBlack_large.png", 21, 21, 0xFF000000);
  await add("PNG/Face/Eyebrows/blackBrow1.png", 40, 17, 0xFF000000);
  await add("PNG/Face/Nose/Tint 1/tint1Nose1.png", 31, 21, 0xFFE0A070);
  await add("PNG/Face/Mouth/mouth_happy.png", 34, 13, 0xFF880000);
  await add("PNG/Face/Mouth/mouth_oh.png", 20, 20, 0xFF880000);
  return a;
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync("sprite_builder");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });
  tearDown(() {
    CanvasStorage.rootOverride = null;
    root.deleteSync(recursive: true);
  });

  test("the pieces found by their names, either way round", () async {
    var parts = ModularParts(await _pack());
    expect(parts.isModular, isTrue);
    expect(parts.skins, [1]);
    expect(parts.shirts.keys, containsAll(["Blue", "Yellow"]), reason: "blueShirt1 and shirtYellow1");
    expect(parts.sleeves["Yellow"]!.keys, ["long"], reason: "armYellow_long");
    expect(parts.legs.keys, containsAll(["Blue 1", "Yellow"]), reason: "pantsBlue1_long and legYellow_long");
    expect(parts.pants["Blue 1"]!.keys, [1]);
    expect(parts.shoes["Brown 1"]!.keys, [1]);
    expect(parts.mouths.keys, containsAll(["happy", "oh"]));
    var look = parts.standard();
    expect((look.shirtColour, look.pantsColour, look.shoeColour), ("Blue", "Blue 1", "Brown 1"));
    expect(ModularLook.fromJson(look.toJson())!.toJson(), look.toJson());
  });

  test("its animations drawn a row each, a figure in every cell", () async {
    var parts = ModularParts(await _pack());
    var chosen = [modularAnimations[0], modularAnimations[1]];
    var (sheet, cols, rows) = await modularSheet(parts, parts.standard(), chosen, 76);
    expect((cols, rows), (8, 2));
    expect(sheet.height, 152);
    var px = (await SpritePixels.of(sheet))!;
    var cw = sheet.width ~/ cols;
    for (var (row, a) in chosen.indexed) {
      for (var k = 0; k < a.frames.length; k++) {
        var any = false;
        for (var y = row * 76; y < (row + 1) * 76 && !any; y += 2) {
          for (var x = k * cw; x < (k + 1) * cw && !any; x += 2) {
            if (px.at(x, y).a > 0) any = true;
          }
        }
        expect(any, isTrue, reason: "${a.name} frame $k");
      }
    }
  });

  testWidgets("built in the Sprite's settings: chosen, and the sprite made", (tester) async {
    SharedPreferences.setMockInitialValues({});
    var parts = await tester.runAsync(() async => ModularParts(await _pack()));
    SpriteBuilderGroupState.parts = parts;
    addTearDown(() => SpriteBuilderGroupState.parts = null);
    var c = CanvasController(CanvasDocument(frames: 24)
        .addElement(const SpriteElement(ElementBase(id: "s", x: 10, y: 10, width: 100, height: 100))));
    addTearDown(c.dispose);
    tester.view.physicalSize = const ui.Size(420, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: SpriteBuilderGroup(
                      controller: c, sprite: c.document.elementById("s") as SpriteElement)))),
    ));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("spriteBuilderOpen")));
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("spriteBuilderPreview")), findsOneWidget);
    expect(find.byKey(const ValueKey("spriteBuilder-shirtColour")), findsOneWidget);
    // Only two animations, to keep it quick.
    for (var a in modularAnimations.skip(2)) {
      await tester.tap(find.byKey(ValueKey("spriteBuilderAnimation-${a.name}")));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey("spriteBuilderBuild")));
    // The sheet is drawn, encoded and stored over real time: waited on a
    // turn at a time, the widget pumped between.
    for (var i = 0; i < 200 && !(c.document.elementById("s") as SpriteElement).hasSheet; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    var e = c.document.elementById("s") as SpriteElement;
    expect(e.hasSheet, isTrue);
    expect(e.actions.map((a) => a.name), ["Idle", "Walk"]);
    expect(e.actionNamed("Walk")!.frames[SpriteFacing.front], [8, 9, 10, 11, 12, 13, 14, 15]);
    expect(e.built?["look"], isNotNull, reason: "built again from what it was built from");
    expect(tester.takeException(), isNull);
  });
}
