import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_surface_test.dart is the Surface style: seven materials,
// each a lit height field, and the settings each of them has.

const int _w = 160, _h = 90;
const Rect _page = Rect.fromLTWH(0, 0, 160, 90);

Future<List<int>> _pixels(ProceduralSpec spec) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec);
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

const _base = ProceduralSpec(
  style: ProceduralStyle.surface,
  background: Color(0xFFB08050),
  foreground: Color(0xFF503018),
  accent: Color(0xFFE0C080),
  vignette: 0,
);

void main() {
  testWidgets("each of the seven is a different picture", (tester) async {
    var pictures = <List<int>>[];
    await tester.runAsync(() async {
      for (var k = 0; k < 7; k++) {
        pictures
            .add(await _pixels(_base.withParam("surfaceKind", k.toDouble())));
      }
    });
    for (var i = 0; i < 7; i++) {
      for (var j = i + 1; j < 7; j++) {
        expect(pictures[i], isNot(pictures[j]), reason: "$i and $j");
      }
    }
  });

  group("settings reach the picture", () {
    for (var (kind, id, value) in [
      (0, "relief", 1.0),
      (3, "polish", 1.0),
      (0, "laid", 1.0),
      (1, "panels", 1.0),
      (2, "planks", 1.0),
      (5, "weave", 1.0),
    ]) {
      testWidgets("kind $kind: $id", (tester) async {
        var plain = _base.withParam("surfaceKind", kind.toDouble());
        late List<int> a, b;
        await tester.runAsync(() async {
          a = await _pixels(plain);
          b = await _pixels(plain.withParam(id, value));
        });
        expect(a, isNot(b));
      });
    }
  });

  test("does not move, and its looks cover every material", () {
    expect(ProceduralStyle.surface.canAnimate, isFalse);
    expect(ProceduralStyle.surface.family, StyleFamily.surface);
    expect({
      for (var l in looksFor(ProceduralStyle.surface))
        l.spec.choice("surfaceKind")
    }, {
      0,
      1,
      2,
      3,
      4,
      5,
      6
    });
  });

  group("the panel", () {
    Future<ProceduralSpec Function()> pump(
        WidgetTester tester, ProceduralSpec start) async {
      var current = start;
      tester.view.physicalSize = const Size(400, 2400);
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
      return () => current;
    }

    testWidgets("offers planks for wood and not for marble", (tester) async {
      var spec = await pump(tester, _base.withParam("surfaceKind", 2));
      expect(find.byKey(const ValueKey("param-planks")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-weave")), findsNothing);
      await tester.tap(find.byKey(const ValueKey("param-surfaceKind")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Marble").last);
      await tester.pumpAndSettle();
      expect(spec().choice("surfaceKind"), 3);
      expect(find.byKey(const ValueKey("param-planks")), findsNothing);
    });
  });
}
