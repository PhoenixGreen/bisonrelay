import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_pitch_views_test.dart is the rebuilt sports pitches -- every sport,
// seen every way -- and the reworked metal, splatter and blockchain.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

Future<List<int>> _pixels(ProceduralSpec spec, {double time = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec, time: time, frameRate: 30);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  picture.dispose();
  return out;
}

const _pitch = ProceduralSpec(
  style: ProceduralStyle.pitch,
  background: Color(0xFF2E7D32),
  foreground: Color(0xFFFFFFFF),
  accent: Color(0xFF1D3F87),
  vignette: 0,
);

void main() {
  group("pitches", () {
    testWidgets("every sport draws its own markings", (tester) async {
      var pictures = <PitchSport, List<int>>{};
      await tester.runAsync(() async {
        for (var s in PitchSport.values) {
          pictures[s] = await _pixels(_pitch.copyWith(sport: s));
        }
      });
      var sports = PitchSport.values;
      for (var i = 0; i < sports.length; i++) {
        for (var j = i + 1; j < sports.length; j++) {
          expect(pictures[sports[i]], isNot(pictures[sports[j]]),
              reason: "${sports[i].name} and ${sports[j].name}");
        }
      }
    });

    testWidgets("every view and surround draws, and each differs",
        (tester) async {
      var seen = <String, List<int>>{};
      await tester.runAsync(() async {
        for (var view = 0; view < 4; view++) {
          for (var surround = 0; surround < 3; surround++) {
            for (var area = 0; area < 2; area++) {
              var spec = _pitch.copyWith(params: {
                "view": view.toDouble(),
                "surround": surround.toDouble(),
                "area": area.toDouble(),
              });
              seen["$view/$surround/$area"] = await _pixels(spec);
            }
          }
        }
      });
      var keys = seen.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          expect(seen[keys[i]], isNot(seen[keys[j]]),
              reason: "${keys[i]} and ${keys[j]}");
        }
      }
    });

    testWidgets("half a pitch stops at the halfway line", (tester) async {
      late List<int> px;
      await tester.runAsync(
          () async => px = await _pixels(_pitch.copyWith(params: {"area": 1})));
      // The half fills the middle of the frame; at its left edge is the
      // halfway line and nothing of the other half beyond it.
      var surround = px[45 * _w + 2];
      var middle = px[45 * _w + 80];
      expect(surround, isNot(middle));
    });

    test("the football pitch players are placed on is where it always was", () {
      // Fitted to the field of play alone, flat and across, as before the
      // pitches were rebuilt -- so a formation lands where it did.
      var metrics =
          pitchRect(const Rect.fromLTWH(0, 0, 1600, 900), PitchSport.football);
      var available =
          const Rect.fromLTWH(0, 0, 1600, 900).deflate(900 * pitchInset);
      expect(metrics.area.height, closeTo(available.height, 0.5));
      expect(metrics.area.width / metrics.area.height, closeTo(105 / 68, 1e-6));
      expect(metrics.area.center.dx, closeTo(800, 0.5));
    });

    test("the new sports are saved by name", () {
      for (var s in [
        PitchSport.futsal,
        PitchSport.basketballNba,
        PitchSport.iceHockey,
        PitchSport.rugbyLeague
      ]) {
        var back = ProceduralSpec.fromJson(_pitch.copyWith(sport: s).toJson());
        expect(back.sport, s);
      }
    });
  });

  group("metal finishes", () {
    testWidgets("are different pictures, and the first is the original",
        (tester) async {
      const steel = ProceduralSpec(
          style: ProceduralStyle.metal,
          background: Color(0xFF8A9099),
          foreground: Color(0xFFE6EBF2),
          accent: Color(0xFF8B4A24),
          vignette: 0);
      var pictures = <List<int>>[];
      late List<int> unset;
      await tester.runAsync(() async {
        unset = await _pixels(steel);
        for (var f = 0; f < 8; f++) {
          pictures.add(await _pixels(steel.withParam("finish", f.toDouble())));
        }
      });
      expect(pictures[0], unset);
      for (var i = 0; i < 8; i++) {
        for (var j = i + 1; j < 8; j++) {
          expect(pictures[i], isNot(pictures[j]), reason: "$i and $j");
        }
      }
    });

    testWidgets("rust reaches the new finishes", (tester) async {
      var fine = const ProceduralSpec(style: ProceduralStyle.metal, vignette: 0)
          .withParam("finish", 1);
      late List<int> clean, rusty;
      await tester.runAsync(() async {
        clean = await _pixels(fine.copyWith(metal: const MetalSpec(rust: 0)));
        rusty = await _pixels(fine.copyWith(metal: const MetalSpec(rust: 0.8)));
      });
      expect(clean, isNot(rusty));
    });
  });

  group("splatter and blockchain", () {
    testWidgets("splash and watercolour are new pictures", (tester) async {
      const splat =
          ProceduralSpec(style: ProceduralStyle.splatter, vignette: 0);
      var pictures = <List<int>>[];
      await tester.runAsync(() async {
        for (var k = 0; k < 5; k++) {
          pictures
              .add(await _pixels(splat.withParam("splatKind", k.toDouble())));
        }
      });
      for (var i = 0; i < 5; i++) {
        for (var j = i + 1; j < 5; j++) {
          expect(pictures[i], isNot(pictures[j]), reason: "$i and $j");
        }
      }
    });

    testWidgets("the chain's layouts and the globe draw, and the globe turns",
        (tester) async {
      const chain = ProceduralSpec(
          style: ProceduralStyle.blockchain, vignette: 0, animated: true);
      late List<int> rows, depth, away, globe, later;
      await tester.runAsync(() async {
        rows = await _pixels(chain.withParam("rows", 3), time: 1);
        depth = await _pixels(chain.withParam("rows", 3).withParam("layout", 1),
            time: 1);
        away = await _pixels(chain.withParam("layout", 2), time: 1);
        globe = await _pixels(chain.withParam("mode", 5), time: 1);
        later = await _pixels(chain.withParam("mode", 5), time: 4);
      });
      expect(depth, isNot(rows));
      expect(away, isNot(rows));
      expect(globe, isNot(rows));
      expect(later, isNot(globe));
    });
  });
}
