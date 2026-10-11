import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_light.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/pitch_views.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

Future<void> _pumpSettings(WidgetTester tester, ProceduralSpec Function() get,
    void Function(ProceduralSpec) set) async {
  tester.view.physicalSize = const Size(400, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(MaterialApp(
    home: ChangeNotifierProvider(
      create: (_) => ThemeNotifier(doLoad: false),
      child: Scaffold(
        body: SingleChildScrollView(
          child: CanvasControlScope(
            maxWidth: 300,
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) => ProceduralSettings(
                  spec: get(),
                  onChanged: (s) => setState(() => set(s)),
                  onBegin: () {},
                  onCommit: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

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

  group("the camera", () {
    double distance(List<int> a, List<int> b) {
      var sum = 0;
      for (var i = 0; i < a.length; i++) {
        for (var sh in [24, 16, 8]) {
          sum += (((a[i] >> sh) & 0xFF) - ((b[i] >> sh) & 0xFF)).abs();
        }
      }
      return sum / (a.length * 3);
    }

    testWidgets("turning the pitch a little does not change its size",
        (tester) async {
      late List<int> still, turned, zoomed;
      await tester.runAsync(() async {
        still = await _pixels(_pitch);
        turned = await _pixels(_pitch.copyWith(rotation: 0.5));
        zoomed = await _pixels(_pitch.copyWith(scale: 0.06));
      });
      // Half a degree moves a few pixels at the edges; a jump in size moves
      // all of them -- as a zoom of a fifth does.
      expect(distance(still, turned), lessThan(distance(still, zoomed) / 3));
    });

    testWidgets("size zooms, and the position settings move it",
        (tester) async {
      late List<int> base, zoom, moved, side;
      await tester.runAsync(() async {
        base = await _pixels(_pitch);
        zoom = await _pixels(_pitch.copyWith(scale: 0.1));
        moved = await _pixels(_pitch.copyWith(params: {"panX": 0.4}));
        side = await _pixels(
            _pitch.copyWith(params: {"tiltH": 30, "perspective": 0.8}));
      });
      expect(zoom, isNot(base));
      expect(moved, isNot(base));
      expect(side, isNot(base));
    });

    testWidgets("choosing a view puts the camera settings in place",
        (tester) async {
      var current = _pitch;
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 300,
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => ProceduralSettings(
                      spec: current,
                      onChanged: (s) => setState(() => current = s),
                      onBegin: () {},
                      onCommit: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("param-view")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Broadcast").last);
      await tester.pumpAndSettle();
      expect(current.p("tiltV"), 58);
      expect(current.p("perspective"), 0.85);
      // And the zoom is with the camera, not among the amounts.
      expect(find.byKey(const ValueKey("pitchZoom")), findsOneWidget);
      expect(find.text("Size"), findsNothing);
    });

    testWidgets("the orbit pad moves the camera in one gesture",
        (tester) async {
      var current = _pitch;
      await _pumpSettings(tester, () => current, (s) => current = s);
      var pad = find.byKey(const ValueKey("pitchOrbitPad"));
      expect(pad, findsOneWidget);
      // The numbers are behind Fine tune, not in the way.
      expect(find.byKey(const ValueKey("param-tiltV")), findsNothing);

      // Drag right and up: turned, and tilted back.
      await tester.drag(pad, const Offset(50, -40));
      await tester.pumpAndSettle();
      expect(current.p("turn"), greaterThan(20));
      expect(current.p("tiltV"), greaterThan(10));

      // Shift-drag: to the side, and the lens.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.drag(pad, const Offset(40, -40));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(current.p("tiltH"), greaterThan(5));
      expect(current.p("perspective"), greaterThan(0.1));

      // Scroll zooms.
      var before = current.scale;
      await tester.sendEventToBinding(PointerScrollEvent(
          position: tester.getCenter(pad), scrollDelta: const Offset(0, -200)));
      await tester.pumpAndSettle();
      expect(current.scale, greaterThan(before));

      // Double-click is flat again, at the same zoom.
      var zoomed = current.scale;
      await tester.tap(pad);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(pad);
      await tester.pumpAndSettle();
      expect(current.p("tiltV"), 0);
      expect(current.p("turn"), 0);
      expect(current.p("tiltH"), 0);
      expect(current.p("perspective"), 0);
      expect(current.scale, zoomed);
    });

    testWidgets("the stadium and track settings show with their surround",
        (tester) async {
      var current = _pitch;
      await _pumpSettings(tester, () => current, (s) => current = s);
      expect(find.byKey(const ValueKey("param-tiers")), findsNothing);
      expect(find.byKey(const ValueKey("param-lanes")), findsNothing);
      current = current.withParam("surround", 1);
      await _pumpSettings(tester, () => current, (s) => current = s);
      expect(find.byKey(const ValueKey("param-tiers")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-roof")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-lanes")), findsNothing);
      current = current.withParam("surround", 2);
      await _pumpSettings(tester, () => current, (s) => current = s);
      expect(find.byKey(const ValueKey("param-lanes")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-tiers")), findsNothing);
    });

    testWidgets("stadium and track options each change the picture",
        (tester) async {
      var stadium = _pitch.withParam("surround", 1).withParam("tiltV", 50);
      var track = _pitch.withParam("surround", 2);
      late List<int> s0, t0;
      var changed = <String, List<int>>{};
      await tester.runAsync(() async {
        s0 = await _pixels(stadium);
        t0 = await _pixels(track);
        for (var (id, v) in [
          ("tiers", 3.0),
          ("roof", 2.0),
          ("boards", 1.0),
          ("standSize", 1.6)
        ]) {
          changed[id] = await _pixels(stadium.withParam(id, v));
        }
        for (var (id, v) in [
          ("lanes", 4.0),
          ("trackColour", 1.0),
          ("fieldEvents", 0.0)
        ]) {
          changed[id] = await _pixels(track.withParam(id, v));
        }
      });
      for (var id in ["tiers", "roof", "boards", "standSize"]) {
        expect(changed[id], isNot(s0), reason: id);
      }
      for (var id in ["lanes", "trackColour", "fieldEvents"]) {
        expect(changed[id], isNot(t0), reason: id);
      }
    });

    testWidgets("a track's corners are track, not grass", (tester) async {
      // Seen flat, the apron's corner -- 4 m beyond the corner flag -- is
      // outside the kerb, so it is the track's colour and not the pitch's.
      late List<int> px;
      await tester.runAsync(() async {
        px = await _pixels(_pitch.withParam("surround", 2));
      });
      // The track's red, somewhere round the bend near the top right of
      // where the field's corner is.
      int red(int argb) => (argb >> 24) & 0xFF;
      int green(int argb) => (argb >> 16) & 0xFF;
      var reddish = 0;
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          var c = px[y * _w + x];
          if (red(c) > green(c) + 40) reddish++;
        }
      }
      expect(reddish, greaterThan(_w * _h ~/ 20));
    });

    testWidgets("each view offers five shots, and the first is where it starts",
        (tester) async {
      var current = _pitch;
      await _pumpSettings(tester, () => current, (s) => current = s);
      await tester.tap(find.byKey(const ValueKey("param-view")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Broadcast").last);
      await tester.pumpAndSettle();
      expect(pitchShotOf(2, current.params, current.scale), 0);

      var shot = find.byKey(const ValueKey("pitchShot"));
      await tester.ensureVisible(shot);
      await tester.tap(shot);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Left box").last);
      await tester.pumpAndSettle();
      var left = pitchShots[2]![3].$2;
      expect(current.p("panX"), left["panX"]);
      expect(current.scale / 0.05, closeTo(left["zoom"]!, 1e-9));

      // Moved off it with the pad, it is Custom.
      await tester.drag(
          find.byKey(const ValueKey("pitchOrbitPad")), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(pitchShotOf(2, current.params, current.scale), -1);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("pitchShot")),
              matching: find.text("Custom")),
          findsOneWidget);

      // Every shot of every view is a different camera.
      for (var shots in pitchShots.values) {
        expect(shots, hasLength(5));
        var seen = <String>{};
        for (var (_, v) in shots) {
          expect(seen.add(v.toString()), isTrue);
        }
      }
    });

    testWidgets("a camera is saved as a view, and put back", (tester) async {
      var root = Directory.systemTemp.createTempSync("pitch-views");
      CanvasStorage.rootOverride = root.path;
      SavedPresetStore.pitchViews.forget();
      addTearDown(() {
        CanvasStorage.rootOverride = null;
        SavedPresetStore.pitchViews.forget();
        root.deleteSync(recursive: true);
      });
      Future<void> idle() async {
        for (var i = 0; i < 24; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 4)));
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      var current = withPitchCamera(_pitch, pitchShots[3]![3].$2);
      await _pumpSettings(tester, () => current, (s) => current = s);
      await idle();
      var name = find.byKey(const ValueKey("pitchViewName"));
      await tester.ensureVisible(name);
      await tester.enterText(
          find.descendant(of: name, matching: find.byType(EditableText)),
          "My corner");
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("pitchSaveView")));
      await idle();
      expect(SavedPresetStore.pitchViews.presets.map((p) => p.name),
          ["My corner"]);

      // Somewhere else, then back by the saved view.
      var saved = pitchCameraOf(current);
      current = withPitchCamera(current, pitchShots[0]![0].$2);
      await _pumpSettings(tester, () => current, (s) => current = s);
      await idle();
      var pick = find.byKey(const ValueKey("pitchSavedView"));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await tester.tap(find.text("My corner").last);
      await tester.pumpAndSettle();
      expect(pitchCameraOf(current), saved);

      // And deleted.
      await tester.tap(find.byKey(const ValueKey("pitchDeleteView")));
      await idle();
      expect(SavedPresetStore.pitchViews.presets, isEmpty);
    });

    testWidgets("the stadium never lies over the pitch", (tester) async {
      // However near the stand and however soft, every pixel of the pitch
      // is the pitch's: the same with the near stand at full strength as
      // with none at all.
      for (var camera in [
        for (var view in pitchShots.keys)
          for (var (_, shot) in pitchShots[view]!) shot,
      ]) {
        var stand = withPitchCamera(_pitch.withParam("surround", 1), camera);
        late List<int> none, full;
        await tester.runAsync(() async {
          none = await _pixels(stand.withParam("nearStands", 0));
          full = await _pixels(
              stand.withParam("nearStands", 1).withParam("depthOfField", 1));
        });
        var place = pitchPlacement(_page, stand);
        var checked = 0;
        for (var x = 2.0; x <= 103; x += 4) {
          for (var y = 2.0; y <= 66; y += 4) {
            var at = place.page(x, y);
            var px = at.dx.floor(), py = at.dy.floor();
            if (px < 0 || py < 0 || px >= _w || py >= _h) continue;
            checked++;
            expect(full[py * _w + px], none[py * _w + px],
                reason: "\$camera at \$x, \$y m");
          }
        }
        expect(checked, greaterThan(50));
      }
    });

    testWidgets("the near stand is drawn, soft, rather than cut away",
        (tester) async {
      var stand = _pitch
          .withParam("surround", 1)
          .withParam("tiltV", 50)
          .withParam("perspective", 0.85);
      late List<int> shown, hidden, sharp, soft;
      await tester.runAsync(() async {
        shown = await _pixels(stand);
        hidden = await _pixels(stand.withParam("nearStands", 0));
        sharp = await _pixels(stand.withParam("depthOfField", 0));
        soft = await _pixels(stand.withParam("depthOfField", 1));
      });
      expect(shown, isNot(hidden));
      expect(sharp, isNot(soft));
      // The near stand is at the bottom of the frame: that is where the
      // two differ.
      var bottom = 0, top = 0;
      for (var y = 0; y < _h; y++) {
        for (var x = 0; x < _w; x++) {
          if (shown[y * _w + x] != hidden[y * _w + x]) {
            y > _h * 0.6 ? bottom++ : (y < _h * 0.3 ? top++ : null);
          }
        }
      }
      expect(bottom, greaterThan(top));
    });

    test("a pitch saved with the old tilt and turn keeps its camera", () {
      var old = ProceduralSpec.fromJson({
        ..._pitch.toJson(),
        "params": {"view": 2, "tilt": 0.5, "spin": 10},
      });
      expect(old.params["tiltV"], closeTo(90 - (14 + 0.5 * 46), 1e-9));
      expect(old.params["turn"], 10);
      expect(old.params.containsKey("tilt"), isFalse);
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
