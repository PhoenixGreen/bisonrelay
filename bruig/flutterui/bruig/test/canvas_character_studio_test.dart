import 'dart:math' as math;
import 'dart:convert';
import 'package:bruig/plugin_system/canvas/model/elements/character_wardrobe.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_palettes.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_asset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_reference.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_physics.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/character_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart'
    show characterWeightsOf;
import 'package:bruig/plugin_system/canvas/ui/character_studio.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_character_studio_test.dart is the Character Studio (Ken's board,
// 2026-11-01): a Sketch character made a step at a time from a model sheet.

CharacterElement _girl() => CharacterElement(
    const ElementBase(
        id: "girl", name: "Juniper", x: 100, y: 60, width: 300, height: 560),
    dna: const CharacterDna(type: CharacterType.woman, headsTall: 6.5));

VectorShape _dot(Offset at) => VectorShape(paths: [
      VectorPath([
        for (var (dx, dy) in [
          (-3.0, -3.0),
          (3.0, -3.0),
          (3.0, 3.0),
          (-3.0, 3.0)
        ])
          VectorNode(at.dx + dx, at.dy + dy),
      ], closed: true),
    ]);

/// _layerShapes is how many of [d]'s shapes are on [layer].
int _layerShapes(CharacterDrawing d, String layer) => [
      for (var i = 0; i < d.shapes.length; i++)
        if (d.layerOf(i) == layer) i
    ].length;

void main() {
  late Directory root;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<String> store(WidgetTester tester) async {
    root = (await tester
        .runAsync(() => Directory.systemTemp.createTemp("studio")))!;
    CanvasStorage.rootOverride = root.path;
    addTearDown(() async {
      CanvasStorage.rootOverride = null;
      await tester.runAsync(() => root.delete(recursive: true));
    });
    var bytes = File("test/fixtures/character_sheet.jpg").readAsBytesSync();
    return (await tester
        .runAsync(() => CanvasAssets.save(Uint8List.fromList(bytes))))!;
  }

  testWidgets("a sheet read: its views cut, measured, its palette taken",
      (tester) async {
    var asset = await store(tester);
    var c = CanvasController(CanvasDocument(elements: [_girl()]));
    addTearDown(c.dispose);
    var said = (await tester.runAsync(() => readReference(c, "girl", asset)))!;
    expect(said, startsWith("Found Front, Side, Back, and faces"));
    var e = c.document.elementById("girl") as CharacterElement;
    var ref = e.reference!;
    expect(ref.cuts.keys.toSet(), {"0,0", "270,0", "180,0", referenceFaces},
        reason: "her side faces right: the view from 270°");
    expect(ref.heads, closeTo(5.5, 0.4));
    expect(ref.skulls["0,0"], greaterThan(ref.cuts["0,0"]!.top),
        reason: "the skull under the bun");
    expect(e.palette.length, greaterThanOrEqualTo(5));
    expect(e.palette.map((s) => s.name), contains("Skin"));
    expect(e.assetIds, contains(asset), reason: "kept with the canvas");
    // One step back takes it all.
    c.undo();
    expect(
        (c.document.elementById("girl") as CharacterElement).reference, isNull);
    c.redo();

    fitToReference(c, "girl");
    expect((c.document.elementById("girl") as CharacterElement).dna.headsTall,
        closeTo(ref.heads, 0.01));
  });

  test(
      "opened in the Studio: the character alone; Done writes every copy, one step",
      () {
    var other = CharacterElement(
        const ElementBase(
            id: "boy", name: "Ade", x: 500, y: 60, width: 200, height: 400),
        dna: characterCast[4].dna);
    // A second copy of the same library character, elsewhere and turned.
    var twin =
        _girl().copyWith(characterId: "jun", pose: _girl().pose.withTurn(90));
    twin =
        twin.rebase(twin.base.copyWith(id: "twin", x: 900)) as CharacterElement;
    var first = _girl().copyWith(characterId: "jun");
    var c = CanvasController(CanvasDocument(elements: [first, other, twin]));
    addTearDown(c.dispose);
    c.openStudio("girl");
    expect(c.studioCharacter, "girl");
    expect(c.studioOpen.value, "girl");
    expect(c.document.elements.map((e) => e.id), ["girl"], reason: "alone");
    expect(c.studioWorkspace, StudioWorkspace.body,
        reason: "already in the library");
    expect(c.canUndo, isFalse, reason: "the Studio's own history");
    // Changed in the Studio.
    CharacterElement now() =>
        c.document.elementById("girl") as CharacterElement;
    c.beginInteraction();
    c.replaceElement(now().copyWith(dna: now().dna.copyWith(headsTall: 4)));
    c.endInteraction();
    c.studioView = StudioView.side;
    expect(now().pose.turn, 90);
    c.closeStudio();
    expect(c.studioCharacter, isNull);
    expect(c.studioOpen.value, isNull);
    expect(c.document.elements.map((e) => e.id), ["girl", "boy", "twin"]);
    var girl = c.document.elementById("girl") as CharacterElement;
    var copy = c.document.elementById("twin") as CharacterElement;
    expect(girl.dna.headsTall, 4);
    expect(copy.dna.headsTall, 4, reason: "every copy");
    expect((girl.x, girl.y), (100.0, 60.0),
        reason: "where it stands is the scene's");
    expect(girl.pose.turn, 0, reason: "and which way it faces");
    expect(copy.pose.turn, 90);
    expect(copy.x, 900);
    expect((c.document.elementById("boy") as CharacterElement).dna.headsTall,
        characterCast[4].dna.headsTall,
        reason: "another character untouched");
    expect(c.selection, {"girl"});
    c.undo();
    expect((c.document.elementById("girl") as CharacterElement).dna.headsTall,
        6.5);
    expect(
        (c.document.elementById("twin") as CharacterElement).dna.headsTall, 6.5,
        reason: "one step back");
  });

  test("a character new to the library is given its place there", () {
    var c = CanvasController(CanvasDocument(elements: [_girl()]));
    addTearDown(c.dispose);
    c.openStudio("girl");
    expect(c.studioWorkspace, StudioWorkspace.start,
        reason: "nothing to draw from yet");
    c.closeStudio();
    var girl = c.document.elementById("girl") as CharacterElement;
    expect(girl.characterId, isNotEmpty);
    c.undo();
    expect((c.document.elementById("girl") as CharacterElement).characterId,
        isEmpty);
  });

  test("a design moves; the scene stays", () {
    var e = _girl().copyWith(
        face: const CharacterFace({FaceControl.smile: 1}),
        speaksFor: "ada",
        pose: _girl().pose.withTurn(45));
    var design = designOf(_girl()
        .copyWith(dna: characterCast[1].dna, style: CharacterStyle.anime));
    expect(design.keys.toSet().difference(designKeys), isEmpty);
    var made = withDesign(e, design);
    expect(made.dna.headsTall, characterCast[1].dna.headsTall);
    expect(made.style, CharacterStyle.anime);
    expect(made.face[FaceControl.smile], 1,
        reason: "its expression is the scene's");
    expect(made.speaksFor, "ada");
    expect(made.pose.turn, 45);
    expect((made.x, made.y), (e.x, e.y));
  });

  testWidgets("the library keeps characters, and what they use",
      (tester) async {
    var asset = await store(tester);
    var c = CanvasController(CanvasDocument(elements: [_girl()]));
    addTearDown(c.dispose);
    await tester.runAsync(() => readReference(c, "girl", asset));
    c.openStudio("girl");
    c.closeStudio();
    // Saving is not awaited by Done: let it land.
    List<CharacterAsset> all = const [];
    for (var i = 0; i < 50 && all.isEmpty; i++) {
      all = (await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return CharacterLibrary.list();
      }))!;
    }
    expect(all, hasLength(1));
    expect(all.single.name, "Juniper");
    expect(all.single.id,
        (c.document.elementById("girl") as CharacterElement).characterId);
    expect(all.single.element(const ElementBase(id: "x")).reference?.assetId,
        asset);
    var live = (await tester.runAsync(() => CanvasStorage.liveAssetIds()))!;
    expect(live, contains(asset),
        reason: "a sheet only the library has is kept by a tidy");
    // Placed again from the library: a copy of it, with its own id.
    c.placeCharacter(all.single);
    var copies = c.document.elements.whereType<CharacterElement>().toList();
    expect(copies, hasLength(2));
    expect(copies.last.id, isNot("girl"));
    expect(copies.last.characterId, all.single.id);
    expect(copies.last.name, "Juniper");
    expect(copies.last.reference?.assetId, asset);
    c.undo();
    expect(c.document.elements, hasLength(1), reason: "one step");
    var listed = (await tester.runAsync(() => CanvasStorage.list("")))!;
    expect(listed.where((e) => e.name == canvasCharacterFolder), isEmpty,
        reason: "not a folder of canvases");
  });

  testWidgets("every workspace, full page, at every text size", (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var e = _girl().copyWith(
        characterId: "jun",
        reference: const CharacterReference("x",
            cuts: {"0,0": Rect.fromLTWH(26, 1, 63, 223)}, heads: 5.5),
        palette: const [
          Swatch("Skin", Color(0xFFF2C4A8)),
          Swatch("Hair", Color(0xFF3B2A40))
        ]);
    for (var scale in [1.0, 1.25, 1.5]) {
      var c = CanvasController(CanvasDocument(elements: [e]));
      c.openStudio("girl");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(
                body: CharacterStudioScreen(
                    controller: c,
                    stage: const ColoredBox(color: Color(0xFF222222))))),
      ));
      await tester.pumpAndSettle();
      for (var w in StudioWorkspace.values) {
        await tester.ensureVisible(find.byKey(ValueKey("studioWs-${w.name}")));
        await tester.tap(find.byKey(ValueKey("studioWs-${w.name}")));
        await tester.pumpAndSettle();
        expect(c.studioWorkspace, w);
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey("studioWsTitle")))
                .data,
            w.label);
        expect(tester.takeException(), isNull,
            reason: "${w.name} at ${scale}x");
      }
      for (var v in StudioView.values) {
        await tester.tap(find.byKey(ValueKey("studioView-${v.name}")));
        await tester.pumpAndSettle();
        expect(c.studioView, v);
      }
      expect(c.showTurnaround, isTrue, reason: "all views");
      await tester.ensureVisible(find.byKey(const ValueKey("studioWs-body")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("studioWs-body")));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey("studioFit")));
      await tester.tap(find.byKey(const ValueKey("studioFit")));
      await tester.pumpAndSettle();
      expect((c.document.elementById("girl") as CharacterElement).dna.headsTall,
          5.5);
      await tester.ensureVisible(find.byKey(const ValueKey("studioWs-rig")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("studioWs-rig")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("studioFitBones")), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey("studioWs-draw")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("studioWs-draw")));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("studioTrace")), findsOneWidget);
      // Made of 3D: no Draw.
      await tester.tap(find.byKey(const ValueKey("studioMadeOf")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Sculpted 3D").last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("studioWs-draw")), findsNothing);
      expect(c.studioWorkspace, StudioWorkspace.body);
      await tester.tap(find.byKey(const ValueKey("studioClose")));
      await tester.pumpAndSettle();
      expect(c.studioCharacter, isNull);
      expect((c.document.elementById("girl") as CharacterElement).body.kind,
          BodyKind.mannequin);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });

  testWidgets("drawing a part, the Draw step has its tools on top",
      (tester) async {
    tester.view.physicalSize = const Size(600, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var c = CanvasController(CanvasDocument(elements: [_girl()]));
    addTearDown(c.dispose);
    c.openStudio("girl");
    c.studioWorkspace = StudioWorkspace.draw;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300, child: CharacterStudioPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("studioDrawHint")), findsOneWidget);
    c.takeApartCharacterLayer("girl", "hairBase");
    c.drawOnCharacter("girl", layer: "hairBase");
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("studioDrawHint")), findsNothing);
    expect(find.byKey(const ValueKey("vectorTool-pencil")), findsOneWidget,
        reason: "the tools, once, on top");
    c.closeStudio();
    await tester.pumpAndSettle();
    expect(c.drawingOn, isNull, reason: "drawing put down on the way out");
    expect(tester.takeException(), isNull);
  });

  group("face charts", () {
    CanvasController charted() {
      var c = CanvasController(CanvasDocument(frames: 24, elements: [_girl()]));
      c.chartCharacterLayer("girl", ChartKind.mouth);
      return c;
    }

    CharacterElement girl(CanvasController c) =>
        c.document.elementById("girl") as CharacterElement;

    test("a chart made in one step, on the layer taken apart", () {
      var c = charted();
      addTearDown(c.dispose);
      expect(c.characterChart("girl", ChartKind.mouth), isNotNull);
      expect(c.layerTakenApart("girl", "mouth"), isTrue);
      expect(c.characterChart("girl", ChartKind.eyes), isNull);
      c.undo();
      expect(c.characterChart("girl", ChartKind.mouth), isNull);
      expect(c.layerTakenApart("girl", "mouth"), isFalse,
          reason: "one step back");
    });

    test("a state drawn is kept as that state; the layer's own stays", () {
      var c = charted();
      addTearDown(c.dispose);
      var key = drawnKey(girl(c), 0, 24);
      var own = _layerShapes(girl(c).drawingAt(key).$1, "mouth");
      expect(own, greaterThan(0));

      c.drawChartState("girl", ChartKind.mouth, "wide");
      expect(girl(c).faceAtFrame(0).mouth, MouthShape.wide,
          reason: "set to it");
      expect(c.drawingOn, "girl");
      expect(c.drawingLayer, "mouth");
      expect(c.editingVector!.shapes!.length, own,
          reason: "starts from the mouth as drawn");
      c.replaceElement(c.editingVector!.copyWith(shapes: [_dot(Offset.zero)]));

      var e = girl(c);
      var chart = c.characterChart("girl", ChartKind.mouth)!;
      expect(chart.drawings.keys, ["wide"]);
      expect(chart.drawings["wide"]!.shapes, hasLength(1));
      expect(_layerShapes(e.drawingAt(key).$1, "mouth"), own,
          reason: "not every other mouth");
      // Shown: the wide mouth as the face says wide, its own otherwise.
      expect(
          _layerShapes(
              e
                  .drawingShownAt(key,
                      face: const CharacterFace({}, MouthShape.wide))
                  .$1,
              "mouth"),
          1);
      expect(
          _layerShapes(
              e.drawingShownAt(key, face: CharacterFace.rest).$1, "mouth"),
          own);
      // Kept with the canvas.
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.drawingAt(key).$1.charts["mouth"]!.drawings.keys, ["wide"]);

      // Another state drawn leaves the first.
      c.drawChartState("girl", ChartKind.mouth, "closed");
      expect(girl(c).faceAtFrame(0).mouth, MouthShape.closed);
      c.replaceElement(c.editingVector!
          .copyWith(shapes: [_dot(Offset.zero), _dot(const Offset(9, 0))]));
      c.stopDrawingOnCharacter();
      chart = c.characterChart("girl", ChartKind.mouth)!;
      expect(chart.drawings["wide"]!.shapes, hasLength(1));
      expect(chart.drawings["closed"]!.shapes, hasLength(2));
    });

    test("the state a face is in: lip sync, expressions, blinks", () {
      expect(
          chartKeyOf(
              ChartKind.mouth, const CharacterFace({}, MouthShape.round)),
          "round");
      expect(
          chartKeyOf(
              ChartKind.mouth, const CharacterFace({FaceControl.smile: 0.8})),
          "smile");
      expect(
          chartKeyOf(
              ChartKind.mouth, const CharacterFace({FaceControl.smile: -0.8})),
          "frown");
      expect(
          chartKeyOf(
              ChartKind.eyes, const CharacterFace({FaceControl.eyesOpen: 0})),
          "closed");
      expect(chartKeyOf(ChartKind.eyes, CharacterFace.rest), "open");
      for (var kind in ChartKind.values) {
        for (var (state, _) in kind.keys) {
          expect(
              chartKeyOf(kind, faceForChart(CharacterFace.rest, kind, state)),
              state,
              reason: "${kind.name} set to $state reads back as it");
        }
      }
      // A blink shows the shut eyes, drawn or not.
      var d = CharacterDrawing(
          shapes: [_dot(Offset.zero)],
          parts: const [CharacterPart.head],
          order: const [1],
          layers: const ["eyes"]).copyWith(charts: {
        "eyes": LayerChart(ChartKind.eyes, {
          "closed": CharacterDrawing(
              shapes: [_dot(Offset.zero), _dot(const Offset(5, 0))],
              parts: const [CharacterPart.head, CharacterPart.head],
              order: const [1, 2],
              layers: const ["eyes", "eyes"]),
        }),
      });
      expect(_layerShapes(chartedAt(d, (k) => "closed"), "eyes"), 2);
      expect(_layerShapes(chartedAt(d, (k) => "half"), "eyes"), 1,
          reason: "not drawn: its own");
    });

    testWidgets(
        "the Face workspace: parts, states, drawing, look, expressions, a line said",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.25, 1.5]) {
        var c =
            CanvasController(CanvasDocument(frames: 24, elements: [_girl()]));
        c.openStudio("girl");
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CharacterStudioScreen(
                      controller: c,
                      stage: const ColoredBox(color: Color(0xFF222222))))),
        ));
        CharacterElement now() =>
            c.document.elementById("girl") as CharacterElement;
        Future<void> tap(String key) async {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
        }

        c.studioWorkspace = StudioWorkspace.face;
        await tester.pumpAndSettle();
        expect(c.zoom, greaterThan(1.5), reason: "the face filling the stage");
        // A part picked on the left; its states on the right.
        await tap("studioFacePart-brows");
        expect(c.studioFacePart, StudioFacePart.brows);
        expect(find.byKey(const ValueKey("studioFacePanel-brows")),
            findsOneWidget);
        await tap("studioChartState-brows-up");
        expect(chartKeyOf(ChartKind.brows, now().faceAtFrame(0)), "up");
        expect(c.drawingOn, isNull, reason: "picked to see, not to draw");
        // Drawn by hand: a chart, then the state picked drawn.
        await tap("studioMakeChart-brows");
        expect(c.characterChart("girl", ChartKind.brows), isNotNull);
        await tap("studioDrawState");
        expect(c.drawingLayer, "brows");
        await tap("studioChartDone");
        expect(c.drawingOn, isNull);
        // Every state made from the drawing at once.
        await tap("studioStartingFace");
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey("studioFacePartCount-eyes")))
                .data,
            "5 of 5");
        expect(
            tester
                .widget<Text>(
                    find.byKey(const ValueKey("studioFacePartCount-speech")))
                .data,
            "9 of 9");
        // Where it looks.
        await tap("studioLook-1--1");
        expect(now().face[FaceControl.lookX], closeTo(0.8, 1e-9));
        expect(now().face[FaceControl.lookY], closeTo(0.7, 1e-9));
        expect(now().face[FaceControl.turn], -20);
        // An expression, then one kept as its own.
        await tap("studioExpression-Happy");
        expect(now().face[FaceControl.smile], 0.8);
        await tester.enterText(
            find.descendant(
                of: find.byKey(const ValueKey("studioExpressionName")),
                matching: find.byType(TextField)),
            "Cheeky");
        await tester.pumpAndSettle();
        await tap("studioSaveExpression");
        expect(now().expressions.single.name, "Cheeky");
        expect(find.byKey(const ValueKey("studioOwnExpression-Cheeky")),
            findsOneWidget);
        // A line said.
        await tap("studioSay");
        expect(c.studioTrying, "say");
        expect(c.playing, isTrue);
        expect(now().mouthKeys, isNotEmpty);
        c.studioTry();
        await tester.pumpAndSettle();
        expect(now().mouthKeys, isEmpty);
        // Always: blink off.
        await tap("studioBlink");
        expect(now().life.blink, isFalse);
        expect(tester.takeException(), isNull, reason: "at ${scale}x");
        c.studioWorkspace = StudioWorkspace.body;
        expect(c.zoom, 1, reason: "the whole figure again");
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });
  });

  test("the Check step: an eye line drawn off on one view is caught", () {
    var c = CanvasController(CanvasDocument(frames: 24, elements: [_girl()]));
    addTearDown(c.dispose);
    CharacterElement girl() =>
        c.document.elementById("girl") as CharacterElement;
    expect(studioDrift(girl(), "eyes"), isNull,
        reason: "not drawn on any view");
    for (var turn in [0.0, 90.0]) {
      c.replaceElement(girl().copyWith(pose: girl().pose.withTurn(turn)));
      c.takeApartCharacterLayer("girl", "eyes");
    }
    var level = studioDrift(girl(), "eyes")!;
    expect(level, lessThan(0.015), reason: "the figure's own eyes agree");
    // The side's eyes drawn a head's width lower.
    c.drawOnCharacter("girl", layer: "eyes");
    var proxy = c.editingVector!;
    c.replaceElement(proxy.copyWith(shapes: [
      for (var s in proxy.shapes!)
        s.copyWith(paths: [
          for (var p in s.paths)
            VectorPath([
              for (var n in p.nodes) n.copyWith(y: n.y + girl().height * 0.05)
            ], closed: p.closed),
        ]),
    ]));
    c.stopDrawingOnCharacter();
    expect(studioDrift(girl(), "eyes")!, greaterThan(0.03));
  });

  testWidgets("the reference traced: each view its own shapes, on its parts",
      (tester) async {
    var asset = await store(tester);
    var c = CanvasController(CanvasDocument(elements: [_girl()]));
    addTearDown(c.dispose);
    CharacterElement girl() =>
        c.document.elementById("girl") as CharacterElement;
    expect(await tester.runAsync(() => traceReferenceView(c, "girl")),
        startsWith("Lay a reference"));
    await tester.runAsync(() => readReference(c, "girl", asset));
    fitToReference(c, "girl");
    var said = (await tester.runAsync(() => fitBonesToReference(c, "girl")))!;
    expect(said, startsWith("Arms turned to"));
    // Her arms hang by her sides: closer in than the stance's.
    expect(girl().pose[CharacterBone.upperArmL].abs(), lessThan(8));

    var layers = <double, Set<String?>>{};
    for (var turn in [0.0, 90.0, 180.0]) {
      c.replaceElement(girl().copyWith(pose: girl().pose.withTurn(turn)));
      var before = girl();
      said = (await tester.runAsync(() => traceReferenceView(c, "girl")))!;
      expect(said, startsWith("Traced"));
      var key = drawnKey(girl(), 0, 24);
      var (d, _) = girl().drawingAt(key);
      expect(d.shapes.length, greaterThan(80));
      expect(d.hidden, CharacterRegion.values.toSet(),
          reason: "the figure hidden there");
      for (var g in girl().dna.wardrobe) {
        expect(g.drawingAt(key).$1.replaces, isTrue, reason: "and its clothes");
      }
      layers[turn] = {for (var i = 0; i < d.shapes.length; i++) d.layerOf(i)};
      c.undo();
      expect(girl(), before, reason: "one step back");
      c.redo();
    }
    expect(
        layers[0],
        containsAll(
            ["eyes", "mouth", "hairBase", "torso", "armL", "legL", "footR"]));
    expect(layers[90], containsAll(["armL", "armR", "legL", "legR"]),
        reason: "the hidden arm and leg drawn behind");
    expect(layers[180]!.intersection({"eyes", "mouth"}), isEmpty,
        reason: "no face from behind");
  });

  group("phase 2: made from what goes together", () {
    test("an outfit is kept with the design; a scene picks it", () {
      var coat = const [Garment(GarmentKind.coat, color: Color(0xFF263552))];
      var e = _girl().copyWith(
          outfits: [CharacterOutfit("Winter", coat)], outfit: "Winter");
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.outfits.single.name, "Winter");
      expect(back.outfit, "Winter");
      expect(back.dressed.dna.wardrobe.single.kind, GarmentKind.coat);
      expect(e.copyWith(outfit: "").dressed.dna.wardrobe, e.dna.wardrobe);
      expect(designKeys, contains("outfits"));
      expect(designKeys, isNot(contains("outfit")),
          reason: "which is worn is the scene's");
      var made = withDesign(e.copyWith(outfit: "Winter"),
          designOf(e.copyWith(outfits: const [])));
      expect(made.outfit, "Winter",
          reason: "kept, though the design has no such outfit now");
      expect(made.dressed.dna.wardrobe, made.dna.wardrobe,
          reason: "so it wears the designed clothes");
    });

    test("an outfit's clothes changed in the Studio; the designed ones kept",
        () {
      var c = CanvasController(
          CanvasDocument(elements: [_girl().copyWith(characterId: "jun")]));
      addTearDown(c.dispose);
      var designed = _girl().dna.wardrobe;
      c.openStudio("girl");
      CharacterElement now() =>
          c.document.elementById("girl") as CharacterElement;
      c.studioSaveOutfit();
      expect(c.studioOutfit, "Outfit 1");
      // The outfit's clothes: a coat put on.
      c.beginInteraction();
      c.replaceElement(now().copyWith(
          dna: now().dna.copyWith(wardrobe: [
        ...now().dna.wardrobe,
        const Garment(GarmentKind.coat, color: Color(0xFF263552)),
      ])));
      c.endInteraction();
      c.studioEditOutfit("");
      expect(now().dna.wardrobe, designed,
          reason: "the designed clothes back on");
      c.studioEditOutfit("Outfit 1");
      expect(now().dna.wardrobe.last.kind, GarmentKind.coat);
      // Done while the outfit is on: the design still the designed clothes.
      c.closeStudio();
      var girl = c.document.elementById("girl") as CharacterElement;
      String clothes(List<Garment> w) =>
          jsonEncode([for (var g in w) g.toJson()]);
      expect(clothes(girl.dna.wardrobe), clothes(designed));
      expect(girl.outfits.single.wardrobe.last.kind, GarmentKind.coat);
      c.replaceElement(girl.copyWith(outfit: "Outfit 1"));
      expect(
          (c.document.elementById("girl") as CharacterElement)
              .dressed
              .dna
              .wardrobe
              .last
              .kind,
          GarmentKind.coat);
    });

    test("the cast mixed by weight; someone generated from the palettes", () {
      var a = characterCast[1].dna, b = characterCast[2].dna;
      var even = mixDna(a, [(a, 1), (b, 1)]);
      expect(even.headsTall, closeTo((a.headsTall + b.headsTall) / 2, 1e-9));
      expect(even.skin.r, closeTo((a.skin.r + b.skin.r) / 2, 1e-6));
      expect(even.hairStyle, a.hairStyle, reason: "not a measure: the onto's");
      expect(mixDna(a, [(b, 1)]).build, b.build);
      var one = generatedDna(a, 7),
          again = generatedDna(a, 7),
          other = generatedDna(a, 8);
      expect(jsonEncode(one.toJson()), jsonEncode(again.toJson()),
          reason: "a seed is a person");
      expect(jsonEncode(one.toJson()), isNot(jsonEncode(other.toJson())));
      expect(skinTones.map((s) => s.color), contains(one.skin));
      expect(eyeColours.map((s) => s.color), contains(one.eyes));
      expect(hairColours.map((s) => s.color), contains(one.hair));
      expect(one.kind.person, isTrue);
      expect(one.wardrobe, isNotEmpty);
    });

    testWidgets(
        "Generate, a part to shape, a palette, an outfit: in the Studio",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(
          CanvasDocument(elements: [_girl().copyWith(characterId: "jun")]));
      addTearDown(c.dispose);
      c.openStudio("girl");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CharacterStudioScreen(
                    controller: c,
                    stage: const ColoredBox(color: Color(0xFF222222))))),
      ));
      await tester.pumpAndSettle();
      CharacterElement now() =>
          c.document.elementById("girl") as CharacterElement;
      c.studioWorkspace = StudioWorkspace.start;
      await tester.pumpAndSettle();
      var before = jsonEncode(now().dna.toJson());
      await tester.tap(find.byKey(const ValueKey("studioGenerate")));
      await tester.pumpAndSettle();
      expect(jsonEncode(now().dna.toJson()), isNot(before));
      c.undo();
      expect(jsonEncode(now().dna.toJson()), before, reason: "one step");
      c.studioWorkspace = StudioWorkspace.body;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("studioRegion-nose")));
      await tester.pumpAndSettle();
      expect(c.studioRegion, AppearanceGroup.nose);
      expect(find.byKey(const ValueKey("studioRegionEditor-nose")),
          findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey("studioSkin-3")));
      await tester.tap(find.byKey(const ValueKey("studioSkin-3")));
      await tester.pumpAndSettle();
      expect(now().dna.skin, skinTones[3].color);
      await tester.ensureVisible(find.byKey(const ValueKey("studioMix-2")));
      await tester.tap(find.byKey(const ValueKey("studioMix-2")));
      await tester.pumpAndSettle();
      expect(now().dna.headsTall, characterCast[2].dna.headsTall,
          reason: "one picked: all of them");
      c.studioWorkspace = StudioWorkspace.clothes;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("studioSaveOutfit")));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey("studioOutfit-Outfit 1")), findsOneWidget);
      expect(find.byKey(const ValueKey("studioRemoveOutfit")), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey("studioHair-4")));
      await tester.tap(find.byKey(const ValueKey("studioHair-4")));
      await tester.pumpAndSettle();
      expect(now().dna.hair, hairColours[4].color);
      expect(tester.takeException(), isNull);
    });
  });

  group("phase 3: hair that follows", () {
    CharacterElement jumper(
            {HairPhysics physics = const HairPhysics(),
            HairStyle hair = HairStyle.long}) =>
        _girl().copyWith(
            dna: _girl().dna.copyWith(hairStyle: hair),
            pose: CharacterPose.rest.withTurn(90),
            physics: physics,
            motions: [
              const MotionClip(
                  id: "j",
                  kind: MotionKind.jump,
                  layer: MotionLayer.body,
                  start: 0,
                  length: 48,
                  blend: 0),
            ]);
    const box = Rect.fromLTWH(0, 0, 300, 560);

    test("kept with the design, the default left out", () {
      var e = jumper(physics: const HairPhysics(stiffness: 0.8, bounce: 0.2));
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.physics, e.physics);
      expect(designOf(e), contains("physics"));
      expect(jumper().toJson().containsKey("physics"), isFalse);
      expect(HairPhysics.fromJson({"on": false}).on, isFalse);
    });

    test(
        "thrown by a jump and settling; the same frame the same however reached",
        () {
      var e = jumper();
      var swings = [for (var f = 0; f < 40; f++) hairSwayAt(e, f, 24, box)];
      var most = swings.map((s) => s.across.abs()).reduce(math.max);
      expect(most, greaterThan(0.05), reason: "the take-off throws it");
      expect(most, lessThanOrEqualTo(0.5));
      expect(swings.map((s) => s.stretch.abs()).reduce(math.max),
          greaterThan(0.01),
          reason: "rising and dropping, it hangs longer and shorter");
      expect(swings.last.across.abs(), lessThan(0.03),
          reason: "landed, it settles");
      var again = hairSwayAt(e, 7, 24, box);
      expect(again.across, swings[7].across);
      expect(again.stretch, swings[7].stretch);
    });

    test("heavier swings further; off or bald, none", () {
      // How far it swings, all told.
      double swung(HairPhysics p) => [
            for (var f = 0; f < 30; f++)
              hairSwayAt(jumper(physics: p), f, 24, box).across.abs()
          ].reduce((a, b) => a + b);
      expect(swung(const HairPhysics(weight: 1)),
          greaterThan(swung(const HairPhysics(weight: 0))));
      expect(swung(const HairPhysics(stiffness: 1)),
          lessThan(swung(const HairPhysics(stiffness: 0))));
      expect(swung(const HairPhysics(bounce: 1)),
          greaterThan(swung(const HairPhysics(bounce: 0))));
      expect(
          hairSwayAt(jumper(physics: const HairPhysics(on: false)), 6, 24, box)
              .isNone,
          isTrue);
      expect(
          hairSwayAt(jumper(hair: HairStyle.bald), 6, 24, box).isNone, isTrue);
      var still = hairSwayAt(_girl(), 30, 24, box);
      expect(still.across.abs(), inInclusiveRange(1e-6, 0.02),
          reason: "a breath of air");
      expect(still.stretch, 0);
    });

    test("drawn hair on the hair layers sways; the rest stays", () {
      var sway = const HairSway(0.2, 0.1);
      expect(sway.at(const Offset(10, 5), 20), const Offset(10, 5),
          reason: "above the brow");
      var p = sway.at(const Offset(10, 120), 20);
      expect(p.dx, closeTo(30, 1e-9));
      expect(p.dy, closeTo(130, 1e-9));
      expect(hairLayers,
          containsAll([BodyLayer.hairBack.name, BodyLayer.hairFront.name]));
    });

    testWidgets("the Rig workspace sets it, at every text size",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.5]) {
        var c = CanvasController(
            CanvasDocument(elements: [_girl().copyWith(characterId: "jun")]));
        c.openStudio("girl");
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CharacterStudioScreen(
                      controller: c,
                      stage: const ColoredBox(color: Color(0xFF222222))))),
        ));
        CharacterElement now() =>
            c.document.elementById("girl") as CharacterElement;
        c.studioWorkspace = StudioWorkspace.rig;
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey("studioHairWeight")));
        await tester.pumpAndSettle();
        var weight = tester.widget<CanvasSlider>(
            find.byKey(const ValueKey("studioHairWeight")));
        weight.onChanged(0.2);
        weight.onCommit?.call();
        await tester.pumpAndSettle();
        expect(now().physics.weight, 0.2);
        await tester
            .ensureVisible(find.byKey(const ValueKey("studioHairPhysics")));
        await tester.tap(find.byKey(const ValueKey("studioHairPhysics")));
        await tester.pumpAndSettle();
        expect(now().physics.on, isFalse);
        expect(find.byKey(const ValueKey("studioHairWeight")), findsNothing);
        c.undo();
        await tester.pumpAndSettle();
        expect(now().physics.on, isTrue, reason: "one step back");
        expect(tester.takeException(), isNull, reason: "at ${scale}x");
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });

    testWidgets("tried in a stance and moving: not the design, not a step",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(
          CanvasDocument(elements: [_girl().copyWith(characterId: "jun")]));
      addTearDown(c.dispose);
      c.openStudio("girl");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: CharacterStudioScreen(
                    controller: c,
                    stage: const ColoredBox(color: Color(0xFF222222))))),
      ));
      CharacterElement now() =>
          c.document.elementById("girl") as CharacterElement;
      c.studioWorkspace = StudioWorkspace.rig;
      await tester.pumpAndSettle();
      var design = jsonEncode(now().pose.toJson());
      var steps = c.canUndo;
      var wave = posePresets.firstWhere((p) => p.name == "Wave");
      await tester
          .ensureVisible(find.byKey(const ValueKey("studioTryPose-Wave")));
      await tester.tap(find.byKey(const ValueKey("studioTryPose-Wave")));
      await tester.pumpAndSettle();
      expect(c.studioTrying, "Wave");
      var (held, _) = now().performanceAt(0, 24);
      expect(held[CharacterBone.upperArmR], wave.pose[CharacterBone.upperArmR]);
      expect(held.turn, now().pose.turn, reason: "turned as the view shows it");
      expect(jsonEncode(now().pose.toJson()), design,
          reason: "its own pose kept");
      expect(c.canUndo, steps, reason: "not a step to undo");
      await tester.tap(find.byKey(const ValueKey("studioTryMotion-walk")));
      await tester.pump();
      expect(c.studioTrying, "walk");
      expect(c.playing, isTrue);
      expect(c.looping, isTrue);
      expect(now().track, isNull, reason: "the stance gone");
      expect(now().motions.single.kind, MotionKind.walk);
      await tester.tap(find.byKey(const ValueKey("studioTryOff")));
      await tester.pump();
      expect(c.playing, isFalse);
      expect(c.looping, isFalse, reason: "the loop as it was");
      expect(now().motions, isEmpty);
      expect(find.byKey(const ValueKey("studioTryOff")), findsNothing);
      // Done while trying: the canvas's copy as designed.
      c.studioTry(pose: "Wave");
      c.closeStudio();
      var placed = c.document.elementById("girl") as CharacterElement;
      expect(placed.track, isNull);
      expect(placed.motions, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    test("a starting face: every state drawn from the figure; those drawn kept",
        () {
      var c = CanvasController(CanvasDocument(frames: 24, elements: [_girl()]));
      addTearDown(c.dispose);
      c.openStudio("girl");
      CharacterElement now() =>
          c.document.elementById("girl") as CharacterElement;
      var face = jsonEncode(now().face.toJson());
      c.chartCharacterLayer("girl", ChartKind.eyes);
      var mine = CharacterDrawing(
          shapes: [_dot(const Offset(1, 1))],
          parts: const [CharacterPart.head],
          order: const [1],
          layers: const ["eyes"]);
      var eyes = c.characterChart("girl", ChartKind.eyes)!;
      var (d, _) = now().drawingAt(drawnKey(now(), 0, 24));
      c.replaceElement(now().withDrawingAt(
          drawnKey(now(), 0, 24),
          d.copyWith(
              charts: {...d.charts, "eyes": eyes.withDrawing("wide", mine)})));
      c.studioStartingFace();
      for (var kind in ChartKind.values) {
        var chart = c.characterChart("girl", kind)!;
        expect(chart.drawings.keys.toSet(), {for (var (k, _) in kind.keys) k},
            reason: kind.name);
      }
      var made = c.characterChart("girl", ChartKind.eyes)!;
      expect(jsonEncode(made.drawings["wide"]!.toJson()),
          jsonEncode(mine.toJson()),
          reason: "drawn already: kept");
      expect(jsonEncode(made.drawings["open"]!.toJson()),
          isNot(jsonEncode(made.drawings["closed"]!.toJson())),
          reason: "each state as the face makes it");
      expect(jsonEncode(now().face.toJson()), face,
          reason: "the face as it was");
      c.undo();
      expect(c.characterChart("girl", ChartKind.mouth), isNull,
          reason: "one step");
    });

    test("expressions kept with the design; a line said is only tried", () {
      var c = CanvasController(CanvasDocument(
          frames: 24, elements: [_girl().copyWith(characterId: "jun")]));
      addTearDown(c.dispose);
      c.openStudio("girl");
      CharacterElement now() =>
          c.document.elementById("girl") as CharacterElement;
      c.replaceElement(now().copyWith(
          face: const CharacterFace({
        FaceControl.smile: 0.5,
        FaceControl.lookY: 0.3,
        FaceControl.turn: 30
      })));
      c.studioSaveExpression("  Smug ");
      var x = now().expressions.single;
      expect(x.name, "Smug");
      expect(x.face[FaceControl.smile], 0.5);
      expect(x.face[FaceControl.lookY], 0.3,
          reason: "where it looks is part of it");
      expect(x.face[FaceControl.turn], 0, reason: "not which way the head is");
      expect(designOf(now()), contains("expressions"));
      var back = elementFromJson(now().toJson()) as CharacterElement;
      expect(back.expressions.single.face[FaceControl.smile], 0.5);
      c.studioSaveExpression("Smug");
      expect(now().expressions, hasLength(1), reason: "the same name replaced");
      c.studioSay("Hello there, Bob.");
      expect(now().mouthKeys.map((m) => m.shape), contains(MouthShape.closed),
          reason: "the b in Bob");
      c.pause();
      c.closeStudio();
      var placed = c.document.elementById("girl") as CharacterElement;
      expect(placed.mouthKeys, isEmpty);
      expect(placed.expressions.single.name, "Smug");
      c.studioRemoveExpression("Smug");
    });

    testWidgets("a scene picks from the character's own expressions",
        (tester) async {
      CanvasSection.openAll = true;
      addTearDown(() => CanvasSection.openAll = false);
      tester.view.physicalSize = const Size(900, 14000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var smug = const SavedExpression("Smug",
          CharacterFace({FaceControl.smile: 0.45, FaceControl.squint: 0.4}));
      var c = CanvasController(CanvasDocument(frames: 24, elements: [
        _girl().copyWith(expressions: [smug])
      ]));
      addTearDown(c.dispose);
      c.selectOnly("girl");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.byKey(const ValueKey("characterOwnFeeling-Smug")));
      await tester.tap(find.byKey(const ValueKey("characterOwnFeeling-Smug")));
      await tester.pumpAndSettle();
      var e = c.document.elementById("girl") as CharacterElement;
      expect(e.face[FaceControl.smile], 0.45);
      expect(find.textContaining("Smug"), findsWidgets,
          reason: "named in the summary too");
      expect(tester.takeException(), isNull);
    });
  });

  group("phase 5: motion and test", () {
    test(
        "a walk tuned to the character: its stride, bounce, arms, push-off, lean",
        () {
      CharacterPose at(MotionFeel f, double t) =>
          motionAt(MotionKind.walk, t, feel: f).pose;
      var t = MotionKind.walk.seconds / 4;
      var made = at(MotionFeel.asMade, t);
      var long = at(const MotionFeel(stride: 1), t);
      expect(long.swing(CharacterBone.thighL).abs(),
          greaterThan(made.swing(CharacterBone.thighL).abs()));
      expect(
          at(const MotionFeel(armSwing: 0), t).swing(CharacterBone.upperArmL),
          0);
      expect(at(const MotionFeel(lean: 1), t).swing(CharacterBone.spine),
          greaterThan(made.swing(CharacterBone.spine)));
      var high = [
        for (var i = 0; i < 20; i++)
          motionAt(MotionKind.walk, i / 20, feel: const MotionFeel(bounce: 1))
              .pose
              .lift
      ];
      var flat = [
        for (var i = 0; i < 20; i++)
          motionAt(MotionKind.walk, i / 20, feel: const MotionFeel(bounce: 0))
              .pose
              .lift
      ];
      expect(high.reduce(math.max), greaterThan(0.03));
      expect(flat.reduce(math.max), 0);
      expect(const MotionFeel(stride: 1).travels(MotionKind.walk),
          closeTo(MotionKind.walk.travels * 1.6, 1e-9));
      expect(const MotionFeel(stride: 1).travels(MotionKind.jump),
          MotionKind.jump.travels);
      // Kept with the design; as made, left out.
      var e = _girl().copyWith(
          feel: const MotionFeel(bounce: 0.8),
          gameMotions: const GameMotions()
              .withMotion(GameMove.falling, MotionKind.clap));
      var back = elementFromJson(e.toJson()) as CharacterElement;
      expect(back.feel, e.feel);
      expect(back.gameMotions[GameMove.falling], MotionKind.clap);
      expect(back.gameMotions[GameMove.walking], MotionKind.walk);
      expect(designOf(e).keys, containsAll(["feel", "gameMotions"]));
      expect(_girl().toJson().containsKey("feel"), isFalse);
      expect(
          const GameMotions()
              .withMotion(GameMove.walking, MotionKind.walk)
              .isDefault,
          isTrue);
      // A placed copy walks as tuned.
      var walking = e.copyWith(motions: [
        const MotionClip(
            id: "w",
            kind: MotionKind.walk,
            layer: MotionLayer.body,
            start: 0,
            length: 48,
            blend: 0),
      ]);
      var (tuned, _) = walking.performanceAt(6, 24);
      var (plain, _) =
          walking.copyWith(feel: MotionFeel.asMade).performanceAt(6, 24);
      expect(tuned.lift, isNot(plain.lift));
    });

    testWidgets(
        "the Motion workspace: the library tried, the walk tuned, the game's motions",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.25, 1.5]) {
        var c = CanvasController(CanvasDocument(
            frames: 24, elements: [_girl().copyWith(characterId: "jun")]));
        c.openStudio("girl");
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CharacterStudioScreen(
                      controller: c,
                      stage: const ColoredBox(color: Color(0xFF222222))))),
        ));
        CharacterElement now() =>
            c.document.elementById("girl") as CharacterElement;
        Future<void> tap(String key) async {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pump();
        }

        c.studioWorkspace = StudioWorkspace.motion;
        await tester.pumpAndSettle();
        await tap("studioMotion-dance");
        expect(c.studioTrying, "dance");
        expect(c.playing, isTrue);
        await tap("studioStance-Point");
        expect(c.studioTrying, "Point");
        expect(c.playing, isFalse);
        var stride = tester.widget<CanvasSlider>(
            find.byKey(const ValueKey("studioFeel-stride")));
        stride.onChanged(0.9);
        stride.onCommit?.call();
        await tester.pump();
        expect(now().feel.stride, 0.9);
        expect(
            tester
                .widget<Text>(find.descendant(
                    of: find.byKey(const ValueKey("studioMotion-walk")),
                    matching: find.textContaining("tuned")))
                .data,
            contains("tuned"));
        await tap("studioWatchWalk");
        expect(c.studioTrying, "walk");
        expect(now().pose.turn, 90, reason: "side on, to see the stride");
        tester
            .widget<CanvasDropdown<MotionKind>>(
                find.byKey(const ValueKey("studioGameMove-falling")))
            .onChanged(MotionKind.clap);
        await tester.pump();
        expect(now().gameMotions[GameMove.falling], MotionKind.clap);
        await tap("studioFeelReset");
        expect(now().feel.isDefault, isTrue);
        await tap("studioTryOff");
        expect(c.studioTrying, isNull);
        expect(tester.takeException(), isNull, reason: "at ${scale}x");
        // Done: the tuning and the game's motions kept, nothing tried.
        c.closeStudio();
        var placed = c.document.elementById("girl") as CharacterElement;
        expect(placed.gameMotions[GameMove.falling], MotionKind.clap);
        expect(placed.motions, isEmpty);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });

    testWidgets(
        "the Test workspace: played, turned round, driven with the keys",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.5]) {
        var c = CanvasController(CanvasDocument(
            frames: 24, elements: [_girl().copyWith(characterId: "jun")]));
        c.openStudio("girl");
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CharacterStudioScreen(
                      controller: c,
                      stage: const ColoredBox(color: Color(0xFF222222))))),
        ));
        CharacterElement now() =>
            c.document.elementById("girl") as CharacterElement;
        Future<void> tap(String key) async {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.pump();
        }

        c.studioWorkspace = StudioWorkspace.test;
        await tester.pumpAndSettle();
        await tap("studioPlay-turntable");
        expect(c.studioTrying, "turntable");
        expect(now().poseAtFrame(c.document.frames ~/ 2).turn, closeTo(180, 1),
            reason: "half way round");
        await tap("studioPlay-run");
        expect(now().motions.single.kind, MotionKind.run);
        expect(now().track, isNull, reason: "the turntable gone");
        await tap("studioDrive");
        expect(c.studioDriving, isTrue);
        await tester.pump();
        expect(find.byKey(const ValueKey("studioDriveHint")), findsOneWidget);
        expect(now().motions.single.kind, MotionKind.idle,
            reason: "standing, as its game has it");
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(now().motions.single.kind, MotionKind.walk);
        expect(now().pose.turn, 90, reason: "facing left");
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(now().motions.single.kind, MotionKind.run);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(now().motions.single.kind, MotionKind.jump);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump(Duration(
            milliseconds: (MotionKind.jump.seconds * 1000).round() + 50));
        expect(now().motions.single.kind, MotionKind.walk,
            reason: "landed, still walking left");
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(now().motions.single.kind, MotionKind.idle);
        expect(now().pose.turn, 90, reason: "still facing the way it went");
        // Off the Test workspace, the keys let go of it.
        c.studioWorkspace = StudioWorkspace.body;
        await tester.pumpAndSettle();
        expect(c.studioDriving, isFalse);
        expect(now().motions, isEmpty);
        expect(now().pose.turn, 0, reason: "back as the view shows it");
        expect(tester.takeException(), isNull, reason: "at ${scale}x");
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });
  });

  group("phase 6: sculpted in 3D", () {
    testWidgets("every workspace on a sculpted body, at every text size",
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (var scale in [1.0, 1.25, 1.5]) {
        var e = _girl().copyWith(
            characterId: "jun",
            body: const CharacterBody(kind: BodyKind.mannequin));
        var c = CanvasController(CanvasDocument(frames: 24, elements: [e]));
        c.openStudio("girl");
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: CharacterStudioScreen(
                      controller: c,
                      stage: const ColoredBox(color: Color(0xFF222222))))),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey("studioWs-draw")), findsNothing,
            reason: "no drawing in 3D");
        for (var w in StudioWorkspace.values) {
          if (w.drawnOnly) continue;
          c.studioWorkspace = w;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: "${w.name} at ${scale}x");
        }
        // Rig: the skin's weights, not the hair's physics.
        c.studioWorkspace = StudioWorkspace.rig;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey("studioHairPhysics")), findsNothing);
        var weights = find.byKey(const ValueKey("studioWeights"));
        await tester.ensureVisible(weights);
        var drop = tester.widget<CanvasDropdown<HumanBone?>>(weights);
        expect(
            drop.options.firstWhere((o) => o.$1 == HumanBone.leftUpperArm).$2,
            "Right upper arm",
            reason:
                "the model's left is the page's right, which the character calls its right");
        drop.onChanged(HumanBone.leftUpperArm);
        await tester.pump();
        expect(c.studioWeights, HumanBone.leftUpperArm);
        expect(
            characterWeightsOf
                ?.call(c.document.elementById("girl") as CharacterElement),
            HumanBone.leftUpperArm);
        c.studioWorkspace = StudioWorkspace.face;
        expect(characterWeightsOf, isNull, reason: "Rig's only");
        c.studioWorkspace = StudioWorkspace.rig;
        c.studioWeights = HumanBone.spine;
        c.closeStudio();
        expect(characterWeightsOf, isNull, reason: "none in a scene");
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    });

    testWidgets(
        "a placed character's sidebar is its scene's: its design is the Studio's",
        (tester) async {
      CanvasSection.openAll = true;
      addTearDown(() => CanvasSection.openAll = false);
      tester.view.physicalSize = const Size(900, 8000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var c = CanvasController(CanvasDocument(frames: 24, elements: [_girl()]));
      addTearDown(c.dispose);
      c.selectOnly("girl");
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 420, child: CanvasDesignPanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("openCharacterStudio")), findsOneWidget);
      for (var design in [
        "character",
        "style",
        "layers",
        "appearance",
        "wardrobe"
      ]) {
        expect(find.byKey(ValueKey("elementSection-$design")), findsNothing,
            reason: design);
      }
      for (var scene in ["pose", "motion", "face", "lipSync"]) {
        expect(find.byKey(ValueKey("elementSection-$scene")), findsOneWidget,
            reason: scene);
      }
      // In the Studio, the design's sections are there to be shown.
      c.openStudio("girl");
      c.studioWorkspace = StudioWorkspace.rig;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("elementSection-character")),
          findsOneWidget);
      // Done: the handles the Studio had out are put away.
      c.editFace = true;
      c.editRig = true;
      c.closeStudio();
      expect(c.editFace, isFalse);
      expect(c.editRig, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
