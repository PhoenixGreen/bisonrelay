import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/glb_info.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/model_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart' hide Animation;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

// A 3D object: a .glb from the library's 3D objects, its own animations
// read from the file -- names and lengths -- and put in its slots as clips
// "From the model", which play on the timeline as any clip does.

/// glb is a .glb holding only [json]: enough for what is read from one
/// without drawing it.
Uint8List glb(Map<String, dynamic> json) {
  var text = utf8.encode(jsonEncode(json));
  var padded = [...text, ...List.filled((4 - text.length % 4) % 4, 0x20)];
  var out = BytesBuilder()
    ..add(_u32(0x46546C67))
    ..add(_u32(2))
    ..add(_u32(20 + padded.length))
    ..add(_u32(padded.length))
    ..add(_u32(0x4E4F534A))
    ..add(padded);
  return out.toBytes();
}

List<int> _u32(int v) =>
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List();

final robot = {
  "asset": {"version": "2.0"},
  "accessors": [
    {
      "max": [1.5]
    },
    {
      "max": [0.8]
    },
    {
      "max": [3.0]
    },
  ],
  "animations": [
    {
      "name": "Walk",
      "samplers": [
        {"input": 0},
        {"input": 1}
      ]
    },
    {
      "samplers": [
        {"input": 2}
      ]
    },
  ],
};

void main() {
  test("a model's animations are read from its file", () {
    expect(glbAnimations(glb(robot)), [("Walk", 1.5), ("Animation 2", 3.0)]);
    expect(glbAnimations(glb(const {"asset": {}})), isEmpty);
    expect(
        glbAnimations(Uint8List.fromList(utf8.encode("not a model"))), isNull);
  });

  group("in the library", () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp("canvas_object3d");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
      await CanvasLibrary.list();
    });
    tearDown(() async {
      CanvasStorage.rootOverride = null;
      await root.delete(recursive: true);
    });

    test("a .glb kept is a 3D object, with what it can do", () async {
      var file = File(path.join(root.path, "Robot.glb"));
      await file.writeAsBytes(glb(robot));
      var added = await addCanvasModel(file.path, "Robot");
      expect(added.problem, isNull);
      var kept = (await CanvasLibrary.list(kind: AssetKind.model)).single;
      expect((kept.name, kept.animations.length), ("Robot", 2));
      expect(
          await CanvasMedia.existingPath(MediaKind.model, kept.id), isNotNull);

      var other = File(path.join(root.path, "notes.glb"));
      await other.writeAsString("hello");
      expect((await addCanvasModel(other.path, "Notes")).problem, isNotNull,
          reason: "not a model, whatever it is called");
    });
  });

  test("placed, its animations are clips in its slots", () {
    var asset = LibraryAsset(
        id: "abc.glb",
        kind: AssetKind.model,
        name: "Robot",
        added: DateTime(2026),
        animations: const [("Walk", 1.5), ("Wave", 3)]);
    var e = elementForAsset(asset, const CanvasDocument()) as Object3dElement;
    expect((e.assetId, e.name), ("abc.glb", "Robot"));
    var m = e.base.motion;
    expect([for (var i = 0; i < 2; i++) m.slot(i)?.name], ["Walk", "Wave"]);
    expect(m.slot(0)!.kind, MotionKind.model);
    expect(m.slot(1)!.length, 3);
    expect(e.mediaIds, {"abc.glb"}, reason: "it goes with the canvas");
    var back = elementFromJson(e.toJson()) as Object3dElement;
    expect(back.animations, e.animations);
    expect(back.base.motion.slot(0)?.inside["animation"], "Walk");
  });

  test("a model's clip on the timeline plays its animation", () {
    var e = Object3dElement(
        ElementBase(
            id: "r",
            width: 100,
            height: 100,
            motion: modelClips("r", const [("Walk", 2.0)])),
        assetId: "abc.glb",
        animations: const [("Walk", 2.0)]);
    var c = CanvasController(
        CanvasDocument(frames: 240, frameRate: 24, elements: [e]));
    addTearDown(c.dispose);
    c.placeClip("r", "r-m0", seconds: 1);
    c.weighLayer("r", 0, 0.5);
    var plays = modelPlaysAt(c.document.elementById("r")!, 36, c.document);
    expect(plays.single.$1, "Walk");
    expect(plays.single.$2, closeTo(0.5, 1e-9));
    expect(plays.single.$3, 0.5, reason: "as much as its layer counts");
    expect(modelPlaysAt(c.document.elementById("r")!, 12, c.document), isEmpty,
        reason: "before it is placed to play");
  });

  test("where 3D cannot be drawn, it is a box saying so", () async {
    var doc = CanvasDocument(elements: [
      const Object3dElement(
          ElementBase(id: "r", x: 100, y: 100, width: 300, height: 300),
          assetId: "abc.glb"),
    ]);
    var image = await renderFrame(doc, scale: 0.5);
    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
  });

  testWidgets("its clip chooses which of the model's animations it plays",
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var anims = const [("Walk", 1.5), ("Wave", 3.0)];
    var c = CanvasController(CanvasDocument(elements: [
      Object3dElement(
          ElementBase(
              id: "r", width: 100, height: 100, motion: modelClips("r", anims)),
          assetId: "abc.glb",
          animations: anims),
    ]));
    addTearDown(c.dispose);
    c.pickMotion("r", "r-m0");
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimationPanel(controller: c, height: 360)))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("animModelAnimation")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Wave").last);
    await tester.pumpAndSettle();
    var clip = c.motionOf("r").clip("r-m0")!;
    expect((clip.name, clip.length, clip.inside["animation"]),
        ("Wave", 3.0, "Wave"));
  });
}
