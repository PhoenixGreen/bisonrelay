import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_cube.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_adjustment.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/presets/film_tables.dart';
import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/adjustment_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';

// canvas_image_filters_test.dart covers the adjustments that came with
// actions: the colour tables (the app's film tables, .cube files and
// HaldCLUT pictures), the colour mixer, and the kinds that read a pixel's
// neighbours -- each drawn through the real shader.

void main() {
  group("colour tables", () {
    test("the app's film tables read as their sources have them", () async {
      var bytes = File(filmTablesAsset).readAsBytesSync();
      var tables = readFilmTables(bytes);
      expect(tables.keys, containsAll([for (var t in filmTables) t.id]));
      expect(tables.length, filmTables.length);
      // Redscale, read from its HaldCLUT at these colours (see SOURCES.md):
      // mid-grey goes warm, pure blue goes violet.
      var red = tables["redscale"]!;
      void near((double, double, double) got, List<double> want) {
        expect(got.$1, closeTo(want[0], 0.03));
        expect(got.$2, closeTo(want[1], 0.03));
        expect(got.$3, closeTo(want[2], 0.03));
      }

      near(red.at(32 / 63, 32 / 63, 32 / 63), [0.435, 0.408, 0.333]);
      near(red.at(0, 0, 1), [0.341, 0.235, 0.561]);
      near(red.at(1, 0, 0), [0.769, 0.118, 0.298]);
      // Black and white is grey whatever goes in.
      var (r, g, b) = tables["bw-press"]!.at(0.9, 0.1, 0.2);
      expect((r - g).abs() + (g - b).abs(), lessThan(0.03));
    });

    test("a .cube file is read, its domain and size respected", () {
      // Two points a side, swapping red and blue.
      var swap = StringBuffer("TITLE \"Swap\"\nLUT_3D_SIZE 2\n");
      for (var b = 0; b < 2; b++) {
        for (var g = 0; g < 2; g++) {
          for (var r = 0; r < 2; r++) {
            swap.writeln("$b $g $r");
          }
        }
      }
      var (file, problem) = parseCubeFile(swap.toString());
      expect(problem, isNull);
      expect(file!.title, "Swap");
      var (r, g, b) = file.cube.at(1, 0.5, 0);
      expect(r, closeTo(0, 0.01));
      expect(g, closeTo(0.5, 0.01));
      expect(b, closeTo(1, 0.01));

      // A big one is kept at the most points a side.
      var big = StringBuffer("LUT_3D_SIZE 33\n");
      for (var i = 0; i < 33 * 33 * 33; i++) {
        var r = i % 33 / 32, g = i ~/ 33 % 33 / 32, b = i ~/ 1089 / 32;
        big.writeln("$r $g $b");
      }
      var (bigFile, _) = parseCubeFile(big.toString());
      expect(bigFile!.cube.n, maxCubeSize);
      var (r2, g2, b2) = bigFile.cube.at(0.3, 0.6, 0.9);
      expect(r2, closeTo(0.3, 0.01));
      expect(g2, closeTo(0.6, 0.01));
      expect(b2, closeTo(0.9, 0.01));

      // A 1D table is made into a 3D one: here, each channel inverted.
      var (one, _) = parseCubeFile("LUT_1D_SIZE 2\n1 1 1\n0 0 0\n");
      var (r3, _, _) = one!.cube.at(0.25, 0, 0);
      expect(r3, closeTo(0.75, 0.02));

      for (var bad in ["", "LUT_3D_SIZE 2\n0 0 0\n", "hello"]) {
        expect(parseCubeFile(bad).$1, isNull, reason: bad);
      }
    });

    test("a HaldCLUT picture is read: pixel k is red k%n, green k/n%n", () {
      // Level 2: 8 by 8 pixels, a 4-point table that changes nothing.
      var rgba = Uint8List(8 * 8 * 4);
      for (var k = 0; k < 64; k++) {
        rgba[k * 4] = (k % 4 * 255 / 3).round();
        rgba[k * 4 + 1] = (k ~/ 4 % 4 * 255 / 3).round();
        rgba[k * 4 + 2] = (k ~/ 16 * 255 / 3).round();
        rgba[k * 4 + 3] = 255;
      }
      var (cube, problem) = haldCube(rgba, 8, 8);
      expect(problem, isNull);
      expect(cube!.n, 4);
      var (r, g, b) = cube.at(0.2, 0.5, 0.8);
      expect(r, closeTo(0.2, 0.01));
      expect(g, closeTo(0.5, 0.01));
      expect(b, closeTo(0.8, 0.01));
      expect(haldCube(rgba, 8, 7).$1, isNull);
    });

    test("a table read in is kept in the adjustment, whole or not at all", () {
      var cube = ColourCube.identity(5);
      var a = ImageAdjustment(
          kind: AdjustKind.colourTable, cube: cube, tableName: "Mine");
      var back = ImageAdjustment.fromJson(a.toJson());
      expect(back.cube!.n, 5);
      expect(back.cube!.rgb, cube.rgb);
      expect(back.tableName, "Mine");
      var json = a.toJson();
      (json["cube"] as Map)["n"] = 6;
      expect(ImageAdjustment.fromJson(json).cube, isNull,
          reason: "the bytes are for a 5-point table");
      var film = ImageAdjustment.fromJson(
          const ImageAdjustment(kind: AdjustKind.colourTable, table: "sepia")
              .toJson());
      expect(film.table, "sepia");
    });
  });

  test("the colour mixer takes each band's setting at its hue", () {
    var a = const ImageAdjustment(
        kind: AdjustKind.colourMixer,
        values: {"blueSat": -1, "orangeHue": 1, "greenLum": 0.5});
    expect(mixerAt(a, 240 / 360).$2, closeTo(0, 1e-9));
    expect(mixerAt(a, 30 / 360).$1, closeTo(30, 1e-9));
    expect(mixerAt(a, 120 / 360).$3, closeTo(0.5, 1e-9));
    // Between orange and yellow, part of orange's turn.
    var between = mixerAt(a, 45 / 360).$1;
    expect(between, greaterThan(0));
    expect(between, lessThan(30));
  });

  testWidgets("every kind draws through the shader, and changes the picture",
      (tester) async {
    await tester.runAsync(AdjustShader.load);
    expect(AdjustShader.ready.value, isTrue);
    // A small picture with a little of everything: a ramp and a block.
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder);
    const room = Rect.fromLTWH(0, 0, 64, 64);
    canvas.drawRect(
        room,
        Paint()
          ..shader = ui.Gradient.linear(const Offset(0, 0),
              const Offset(64, 64), const [Colors.orange, Colors.indigo]));
    canvas.drawRect(
        const Rect.fromLTWH(20, 20, 20, 20), Paint()..color = Colors.white);
    var below = recorder.endRecording();
    var plain = await _pixels(tester, (c) => c.drawPicture(below));

    var settings = {
      AdjustKind.colourTable: const ImageAdjustment(
          kind: AdjustKind.colourTable, table: "bw-press"),
      AdjustKind.colourMixer: const ImageAdjustment(
          kind: AdjustKind.colourMixer, values: {"orangeSat": -1}),
      AdjustKind.colourBalance: const ImageAdjustment(
          kind: AdjustKind.colourBalance, values: {"midsRed": 1}),
      AdjustKind.channelMixer: const ImageAdjustment(
          kind: AdjustKind.channelMixer, values: {"rr": 0, "rb": 1}),
    };
    for (var kind in AdjustKind.values) {
      var a = settings[kind] ?? ImageAdjustment(kind: kind);
      var got = await _pixels(tester, (c) => paintAdjusted(c, room, a, below));
      var changed = 0;
      for (var i = 0; i < got.length; i += 4) {
        if ((got[i] - plain[i]).abs() > 3 ||
            (got[i + 1] - plain[i + 1]).abs() > 3 ||
            (got[i + 2] - plain[i + 2]).abs() > 3) {
          changed++;
        }
      }
      // Curves and levels start as nothing; the rest do something.
      if (kind == AdjustKind.curves || kind == AdjustKind.levels) continue;
      expect(changed, greaterThan(0), reason: kind.name);
    }
  });

  group("in the panel", () {
    Future<CanvasController> pumpPanel(
        WidgetTester tester, ImageAdjustment adjust) async {
      SharedPreferences.setMockInitialValues({});
      var e = ImageElement(
          const ElementBase(id: "i", x: 0, y: 0, width: 100, height: 100),
          assetId: "red",
          layers: [
            ImageLayer.base,
            ImageLayer.adjusting(adjust.kind).copyWith(adjust: adjust),
          ]);
      var c = CanvasController(const CanvasDocument().addElement(e));
      addTearDown(c.dispose);
      c.selectOnly("i");
      c.editImage("i", layer: e.stack.last.id);
      setTestScreen(tester, const Size(900, 4000));
      await tester.pumpWidget(canvasApp(
          SizedBox(width: 420, child: CanvasDesignPanel(controller: c))));
      await tester.pumpAndSettle();
      return c;
    }

    ImageAdjustment adjustOf(CanvasController c) =>
        (c.document.elementById("i")! as ImageElement).stack.last.adjust;

    testWidgets("the colour mixer shows one colour at a time", (tester) async {
      var c = await pumpPanel(
          tester, const ImageAdjustment(kind: AdjustKind.colourMixer));
      expect(find.byKey(const ValueKey("adjust-redHue")), findsOneWidget);
      expect(find.byKey(const ValueKey("adjust-blueSat")), findsNothing);
      var blue = find.byKey(const ValueKey("adjustGroup-blue"));
      await tester.ensureVisible(blue);
      await tester.tap(blue);
      await tester.pumpAndSettle();
      var sat = tester
          .widget<CanvasStepper>(find.byKey(const ValueKey("adjust-blueSat")));
      expect(sat.label, "Saturation");
      sat.onChanged(-100);
      sat.onCommit?.call();
      await tester.pumpAndSettle();
      expect(adjustOf(c).value("blueSat"), closeTo(-1, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets("a film table is picked from the list", (tester) async {
      var c = await pumpPanel(
          tester, const ImageAdjustment(kind: AdjustKind.colourTable));
      expect(find.byType(ColourTableSettings), findsOneWidget);
      var pick = tester.widget<CanvasDropdown<String>>(
          find.byKey(const ValueKey("adjustTablePick")));
      pick.onChanged("slide-vivid");
      await tester.pumpAndSettle();
      expect(adjustOf(c).table, "slide-vivid");
      expect(find.textContaining("CC BY-SA"), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<Uint8List> _pixels(
    WidgetTester tester, void Function(ui.Canvas) draw) async {
  var recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  var image = recorder.endRecording().toImageSync(64, 64);
  var data = await tester
      .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  return data!.buffer.asUint8List();
}
