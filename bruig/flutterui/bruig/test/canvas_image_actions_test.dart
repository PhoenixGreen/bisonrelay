import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_effects.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/image_action_file.dart';
import 'package:bruig/plugin_system/canvas/model/lightroom_preset.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/image_actions.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';
import 'support/canvas_panel_helpers.dart';

// canvas_image_actions_test.dart covers a picture's actions: steps kept from
// one picture -- copies of it included -- and done to another, added to its
// look or in place of it; and an action as a file, read back through the
// app's own parser so nothing but settings survives.

ImageElement _photo(String id, String asset, [List<ImageLayer>? layers]) =>
    ImageElement(ElementBase(id: id, x: 0, y: 0, width: 200, height: 100),
        assetId: asset, layers: layers ?? const []);

/// _glow is a picture with an Orton glow: a blurred copy of itself, screened
/// over, nudged right, and an adjustment on top.
ImageElement _glow() {
  var e = _photo("g", "sunset");
  var copy = pictureCopy(e).copyWith(
      blend: LayerBlend.screen,
      opacity: 0.6,
      effects: [
        const LayerEffect(kind: EffectKind.blur).withValue("amount", 20)
      ]);
  copy = copy.placed(copy.place.translate(100, 0));
  return e.withLayers([
    ImageLayer.base,
    copy,
    ImageLayer.adjusting(AdjustKind.vibrance),
  ]);
}

void main() {
  group("steps", () {
    test("a copy of the picture is kept as a copy, never as that picture", () {
      var e = _glow();
      expect(isPictureCopy(e, e.stack[1]), isTrue);
      var data = lookData(e);
      expect(jsonEncode(data), isNot(contains("sunset")));
      expect(lookSteps(data), 2);

      var other = _photo("o", "harbour");
      var done = withLookApplied(other, data, replace: false);
      var copy = done.stack[1];
      expect(copy.kind, LayerKind.picture);
      expect(copy.look!.assetId, "harbour", reason: "its own picture copied");
      expect(copy.blend, LayerBlend.screen);
      expect(copy.opacity, closeTo(0.6, 1e-9));
      expect(copy.effects.single.value("amount"), 20);
      expect(copy.place.left, closeTo(100, 1e-6), reason: "nudged as it was");
      expect(copy.look!.id, isEmpty, reason: "never the element's own id");
      expect(done.stack.last.adjust.kind, AdjustKind.vibrance);
    });

    test("added, an action goes on top; replacing, it takes the look's place",
        () {
      var target = _photo("t", "photo", [
        ImageLayer.base.copyWith(effects: [
          const LayerEffect(kind: EffectKind.dropShadow),
        ]),
        ImageLayer.adjusting(AdjustKind.invert),
      ]);
      var data = lookData(_glow());

      var added = withLookApplied(target, data, replace: false);
      expect([
        for (var l in added.stack) l.kind
      ], [
        LayerKind.base,
        LayerKind.adjustment,
        LayerKind.picture,
        LayerKind.adjustment,
      ]);
      expect(added.stack[1].adjust.kind, AdjustKind.invert, reason: "kept");
      expect(added.stack.first.effects.single.kind, EffectKind.dropShadow);

      var replaced = withLookApplied(added, data);
      expect(replaced.stack.length, 3, reason: "the copy and invert gone");
      expect(replaced.stack.first.effects, isEmpty,
          reason: "the base as the action has it");
    });

    test("only the chosen steps are kept", () {
      var e = _glow();
      var data = lookData(e, only: {e.stack[2].id});
      expect(lookSteps(data), 1);
      var done = withLookApplied(_photo("o", "x"), data);
      expect(done.stack.last.adjust.kind, AdjustKind.vibrance);
      expect(done.stack.where((l) => l.kind == LayerKind.picture), isEmpty);
    });

    test("a picture without a picture takes no copies", () {
      var done = withLookApplied(
          const ImageElement(ElementBase(id: "blank")), lookData(_glow()));
      expect(done.stack.where((l) => l.kind == LayerKind.picture), isEmpty);
    });
  });

  group("as a file", () {
    test("written and read back, it is the same action", () {
      var data = lookData(_glow());
      var (action, problem) =
          readImageAction(packImageAction("Orton glow", data));
      expect(problem, isNull);
      expect(action!.name, "Orton glow");
      expect(action.steps, 2);
      var a = withLookApplied(_photo("o", "x"), data);
      var b = withLookApplied(_photo("o", "x"), action.data);
      expect(b.stack.length, a.stack.length);
      expect(b.stack[1].blend, a.stack[1].blend);
    });

    test("what is not an action is turned away", () {
      for (var bytes in [
        Uint8List.fromList([1, 2, 3]),
        utf8.encode(jsonEncode({"format": "something else", "data": {}})),
        utf8.encode(jsonEncode({
          "format": "bruig-image-action",
          "name": "Empty",
          "data": {"layers": []}
        })),
        Uint8List(maxImageActionBytes + 1),
      ]) {
        var (action, problem) = readImageAction(bytes);
        expect(action, isNull);
        expect(problem, isNotNull);
      }
    });

    test("only settings survive, each within its range", () {
      var raw = {
        "format": "bruig-image-action",
        "name": "x" * 200,
        "data": {
          "base": {"op": 9, "script": "no"},
          "layers": [
            // A picture that is not a copy: never let in.
            {
              "k": "picture",
              "look": {"asset": "somebody-elses.png"},
            },
            {"k": "paint", "strokes": []},
            {
              "k": "adjustment",
              "op": 7,
              "adjust": {"k": "invert"}
            },
            for (var i = 0; i < 100; i++)
              {
                "k": "texture",
                "texture": {"k": "grain"}
              },
          ],
        },
      };
      var (action, _) = readImageAction(utf8.encode(jsonEncode(raw)));
      expect(action!.name.length, 80);
      var text = jsonEncode(action.data);
      expect(text, isNot(contains("somebody-elses")));
      expect(text, isNot(contains("script")));
      var layers = action.data["layers"] as List;
      expect(layers.length, 46,
          reason: "48 read; the picture and the paint not let in");
      expect(layers.first["k"], "adjustment");
      expect(layers.first.containsKey("op"), isFalse, reason: "clamped to 1");
      expect(action.data["base"]["op"], isNull);
    });
  });

  group("Lightroom presets", () {
    const preset = """<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description rdf:about=""
    xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
   crs:PresetType="Normal"
   crs:Exposure2012="+0.50"
   crs:Contrast2012="+20"
   crs:Highlights2012="-60"
   crs:Shadows2012="+40"
   crs:Blacks2012="+15"
   crs:Clarity2012="+25"
   crs:Vibrance="+30"
   crs:IncrementalTemperature="+12"
   crs:HueAdjustmentOrange="-10"
   crs:SaturationAdjustmentBlue="-50"
   crs:SplitToningShadowHue="200"
   crs:SplitToningShadowSaturation="25"
   crs:GrainAmount="30"
   crs:PostCropVignetteAmount="-25"
   crs:LensProfileEnable="1">
   <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">Moody Teal</rdf:li></rdf:Alt></crs:Name>
   <crs:Dehaze>+10</crs:Dehaze>
   <crs:ToneCurvePV2012Red>
    <rdf:Seq><rdf:li>0, 20</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq>
   </crs:ToneCurvePV2012Red>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>""";

    test("each setting goes onto the adjustment that does the same", () {
      var (read, problem) = readLightroomPreset(preset, "file name");
      expect(problem, isNull);
      expect(read!.name, "Moody Teal");
      var done = withLookApplied(_photo("o", "x"), read.data);
      AdjustKind? kindOf(ImageLayer l) =>
          l.kind == LayerKind.adjustment ? l.adjust.kind : null;
      var kinds = [for (var l in done.stack) kindOf(l)];
      expect(
          kinds,
          containsAll([
            AdjustKind.temperature,
            AdjustKind.exposure,
            AdjustKind.brightness,
            AdjustKind.shadowsHighlights,
            AdjustKind.curves,
            AdjustKind.clarity,
            AdjustKind.vibrance,
            AdjustKind.colourMixer,
            AdjustKind.colourBalance,
          ]));
      ImageAdjustment of(AdjustKind k) =>
          done.stack.firstWhere((l) => kindOf(l) == k).adjust;
      expect(of(AdjustKind.exposure).value("stops"), 0.5);
      expect(of(AdjustKind.shadowsHighlights).value("shadows"), 0.4);
      expect(of(AdjustKind.shadowsHighlights).value("highlights"), 0.6);
      expect(of(AdjustKind.clarity).value("dehaze"), closeTo(0.1, 1e-9),
          reason: "read from a child element, not only attributes");
      expect(of(AdjustKind.colourMixer).value("blueSat"), -0.5);
      expect(of(AdjustKind.colourMixer).value("orangeHue"), -0.1);
      // A teal push in the shadows: blue and green up, red down.
      var balance = of(AdjustKind.colourBalance);
      expect(balance.value("shadowsRed"), lessThan(0));
      expect(balance.value("shadowsBlue"), greaterThan(0));
      // The red channel's own curve, lifting its blacks.
      var redCurve = done.stack
          .where((l) => kindOf(l) == AdjustKind.curves)
          .map((l) => l.adjust)
          .firstWhere((a) => a.curves.containsKey(CurveChannel.red));
      expect(
          redCurve.curve(CurveChannel.red).first.dy, closeTo(20 / 255, 1e-6));
      expect(
          done.stack
              .where((l) => l.kind == LayerKind.texture)
              .map((l) => l.texture.kind),
          [TextureKind.grain, TextureKind.vignette]);
      expect(read.left, ["lens profile enable"]);
    });

    test("what is not a preset, or has nothing to do, is turned away", () {
      expect(readLightroomPreset("<html></html>", "x").$1, isNull);
      expect(readLightroomPreset('<x crs:LensProfileEnable="1"/>', "x").$1,
          isNull);
    });
  });

  group("in the panel", () {
    late Directory root;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync("image_actions");
      CanvasStorage.rootOverride = root.path;
      SavedPresetStore.looks.forget();
    });

    tearDown(() {
      CanvasStorage.rootOverride = null;
      SavedPresetStore.looks.forget();
      root.deleteSync(recursive: true);
    });

    Future<CanvasController> pumpPanel(
        WidgetTester tester, ImageElement e) async {
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly(e.id);
      setTestScreen(tester, const Size(900, 4000));
      await tester.pumpWidget(canvasApp(
          SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await tester.pumpAndSettle();
      return c;
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      var found = find.byKey(ValueKey(key));
      await tester.ensureVisible(found);
      await tester.tap(found);
      await tester.pumpAndSettle();
    }

    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets("saved with the steps chosen, then done to another picture",
        (tester) async {
      var e = _glow();
      var c = await pumpPanel(tester, e);
      await idle(tester);
      await openSection(tester, "image.actions");
      await tapKey(tester, "imageActionSave");
      // The copy left out: only the vibrance is kept.
      await tapKey(tester, "imageActionStep-${e.stack[1].id}");
      await tester.enterText(
          find.byKey(const ValueKey("imageActionName")), "Lively");
      await tapKey(tester, "imageActionSaveConfirm");
      await pumpUntil(tester, () => SavedPresetStore.looks.presets.isNotEmpty);
      await tester.pumpAndSettle();
      var kept = SavedPresetStore.looks.presets.single;
      expect(kept.name, "Lively");
      expect(lookSteps(kept.data), 1);
      // Kept, it can be sent, saved as a file or deleted.
      expect(find.byKey(const ValueKey("imageActionSend")), findsOneWidget);
      expect(find.byKey(const ValueKey("imageActionDelete")), findsOneWidget);

      c.addElement(_photo("t", "harbour"));
      await tester.pumpAndSettle();
      await openSection(tester, "image.actions");
      await tapKey(tester, "imageAction-${kept.id}");
      var t = c.document.elementById("t")! as ImageElement;
      expect(t.stack.last.adjust.kind, AdjustKind.vibrance);
      // One step to undo the whole action.
      c.undo();
      t = c.document.elementById("t")! as ImageElement;
      expect(t.stack, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets("a .cube file comes in as an action of one step",
        (tester) async {
      var file = File("${root.path}/Teal.cube");
      var text = StringBuffer("LUT_3D_SIZE 2\n");
      for (var i = 0; i < 8; i++) {
        text.writeln("${i % 2 * 0.5} ${i ~/ 2 % 2} ${i ~/ 4}");
      }
      file.writeAsStringSync(text.toString());
      await pumpPanel(tester, _photo("p", "photo"));
      await idle(tester);
      var context = tester.element(find.byType(CanvasDesignPanel));
      unawaited(importImageActionFile(context, file.path));
      await idle(tester);
      expect(find.textContaining("1 step: Teal"), findsOneWidget);
      await tapKey(tester, "imageActionImportConfirm");
      await pumpUntil(tester, () => SavedPresetStore.looks.presets.isNotEmpty);
      var kept = SavedPresetStore.looks.presets.single;
      expect(kept.name, "Teal");
      var done = withLookApplied(_photo("o", "x"), kept.data);
      var table = done.stack.last.adjust;
      expect(table.kind, AdjustKind.colourTable);
      expect(table.cube!.n, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets("an action file is shown, then kept", (tester) async {
      var file = File("${root.path}/glow$imageActionExtension");
      file.writeAsBytesSync(packImageAction("Glow", lookData(_glow())));
      await pumpPanel(tester, _photo("p", "photo"));
      await idle(tester);
      var context = tester.element(find.byType(CanvasDesignPanel));
      unawaited(importImageActionFile(context, file.path));
      await idle(tester);
      expect(find.textContaining("Copy of the picture"), findsOneWidget);
      await tapKey(tester, "imageActionImportConfirm");
      await pumpUntil(tester, () => SavedPresetStore.looks.presets.isNotEmpty);
      expect(SavedPresetStore.looks.presets.single.name, "Glow");
      expect(tester.takeException(), isNull);
    });
  });

  test("a fill keeps its colour through a file", () {
    var e = _photo("f", "x", [
      ImageLayer.solid(const PaintSpec(ui.Color(0xFF123456))),
      ImageLayer.base,
    ]);
    var (action, _) = readImageAction(packImageAction("Fill", lookData(e)));
    var done = withLookApplied(_photo("o", "y"), action!.data);
    expect(done.stack.first.fill.color, const ui.Color(0xFF123456));
  });
}
