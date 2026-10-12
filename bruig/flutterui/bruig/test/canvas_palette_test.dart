import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_palette.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_palette_test.dart is a document's own colours, and changing one of
// them everywhere it is used.

const _teal = Color(0xFF2ED6A1);
const _pink = Color(0xFFFF4FA3);

/// _video is two scenes drawn in teal: a shape, a half-strength shade of it,
/// a chart's slice and a scene's background -- and a counter that counts to
/// a number exactly as large as teal is.
CanvasDocument _video() {
  var tealNumber = colorToJson(_teal).toDouble();
  return CanvasDocument(
    palette: const [PaletteSwatch("Brand", _teal)],
    scenes: [
      CanvasScene(id: "a", frames: 100, elements: [
        const ShapeElement(ElementBase(id: "box"), fill: _teal),
        ShapeElement(const ElementBase(id: "shade"),
            fill: _teal.withValues(alpha: 0.5)),
        CounterElement(
            ElementBase(
                id: "n",
                track: ElementTrack([
                  Keyframe(frame: 0, values: {KeyframeChannel.count: tealNumber}),
                ])),
            to: tealNumber),
      ]),
      const CanvasScene(
          id: "b",
          frames: 100,
          background: CanvasBackground(
              spec: ProceduralSpec(style: ProceduralStyle.dotGrid, foreground: _teal)),
          elements: [
            ChartElement(ElementBase(id: "pie"),
                type: ChartType.pie, sliceColors: [_teal]),
          ]),
    ],
  );
}

T _el<T>(CanvasController c, String id) {
  for (var s in c.document.allScenes) {
    for (var e in s.elements) {
      if (e.id == id) return e as T;
    }
  }
  throw StateError(id);
}

void main() {
  test("a colour is changed everywhere, keeping its strength", () {
    var c = CanvasController(_video());
    addTearDown(c.dispose);
    c.setSwatch(0, _pink);
    expect(_el<ShapeElement>(c, "box").fill, _pink);
    expect(_el<ShapeElement>(c, "shade").fill.a, closeTo(0.5, 0.01),
        reason: "half strength stays half strength");
    expect(_el<ShapeElement>(c, "shade").fill.withValues(alpha: 1), _pink);
    expect(_el<ChartElement>(c, "pie").sliceColors.single, _pink);
    expect(c.document.allScenes[1].background!.spec.foreground, _pink);
    expect(c.palette.single.color, _pink);
    c.undo();
    expect(_el<ShapeElement>(c, "box").fill, _teal, reason: "one change");
  });

  test("numbers that only look like a colour are left alone", () {
    var c = CanvasController(_video());
    addTearDown(c.dispose);
    c.setSwatch(0, _pink);
    var n = _el<CounterElement>(c, "n");
    expect(n.to, colorToJson(_teal).toDouble());
    expect(n.base.track!.keys.single.values[KeyframeChannel.count],
        colorToJson(_teal).toDouble());
    expect(c.document.allScenes.map((s) => s.frames), [100, 100]);
  });

  test("the palette can be taken from the canvas", () {
    var c = CanvasController(_video().copyWith(palette: const []));
    addTearDown(c.dispose);
    c.paletteFromCanvas(count: 3);
    expect([for (var p in c.palette) p.color], contains(_teal),
        reason: "among the colours most used -- white is used more, by the "
            "defaults every element writes");
  });

  test("backgrounds are drawn in the first three colours", () {
    var c = CanvasController(_video().copyWith(palette: const [
      PaletteSwatch("Ground", Color(0xFF04060C)),
      PaletteSwatch("Pattern", Color(0xFF2970FF)),
      PaletteSwatch("Highlight", _teal),
    ]));
    addTearDown(c.dispose);
    c.paletteToBackgrounds();
    var spec = c.document.allScenes[1].background!.spec;
    expect(spec.background, const Color(0xFF04060C));
    expect(spec.foreground, const Color(0xFF2970FF));
    expect(spec.accent, _teal);
  });

  test("the palette is saved", () {
    var back = CanvasDocument.decode(_video().encode())!;
    expect(back.palette.single.name, "Brand");
    expect(back.palette.single.color, _teal);
  });

  testWidgets("with nothing selected the palette is there, and changes it all",
      (tester) async {
    var c = CanvasController(_video());
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: CanvasDesignPanel(controller: c))),
    ));
    await tester.pumpAndSettle();
    var swatch = find.byKey(const ValueKey("swatch0"));
    expect(swatch, findsOneWidget);
    tester.widget<CanvasColorButton>(swatch).onChanged(_pink);
    await tester.pumpAndSettle();
    expect(_el<ShapeElement>(c, "box").fill, _pink);
  });
}
