import 'dart:io';

import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_panel_sweep_test.dart is every element's settings and its Chain,
// opened all the way, in a narrow sidebar and a wide one, at the text size
// the app starts with and at the larger one Ken runs (see
// bisonrelay_text_scale_overflow): nothing overruns, nothing throws.

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync("panel_sweep");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });
  tearDown(() {
    CanvasStorage.rootOverride = null;
    root.deleteSync(recursive: true);
  });
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  /// elements is one of every kind as it is first added, with an arrival
  /// where it can have one, and an instrument.
  List<(String, CanvasElement)> elements() {
    var doc = const CanvasDocument(frames: 96, frameRate: 24);
    return [
      for (var kind in ElementKind.values)
        // A 3D character's panel waits on its 3D scene, which a test
        // cannot build.
        if (kind != ElementKind.character3d)
          (kind.label, newElement(kind, doc)),
      (
        "Instrument",
        const AudioElement(ElementBase(id: "inst", width: 240, height: 80),
            instrument: InstrumentPart())
      ),
      // Each infographic chart, whose settings have controls of their own
      // (Ken, 2026-11-13): a pictogram's icons, a gauge's middle, a hint.
      for (var t in ChartType.values.where((t) => t.isInfographic))
        (
          "Chart: ${t.label}",
          (newElement(ElementKind.chart, doc) as ChartElement).copyWith(type: t)
        ),
    ];
  }

  Future<CanvasController> pump(WidgetTester tester, CanvasElement e,
      Widget Function(CanvasController) body,
      {required Size size}) async {
    SharedPreferences.setMockInitialValues({});
    setTestScreen(tester, size);
    var c = CanvasController(
        const CanvasDocument(frames: 96, frameRate: 24).addElement(e));
    addTearDown(c.dispose);
    c.selectOnly(e.id);
    if (CanvasController.animates(e)) {
      c.applyElementAnimation(e, ElementAnimationPreset.fadeUp);
      c.applyElementExit(
          c.document.elementById(e.id)!, ElementAnimationPreset.fadeUp);
    }
    await tester.pumpWidget(canvasApp(body(c)));
    return c;
  }

  for (var (name, e) in elements()) {
    testWidgets("$name's settings, narrow to wide, both text sizes",
        (tester) async {
      await pump(tester, e, (c) => CanvasDesignPanel(controller: c),
          size: const Size(300, 9000));
      await sweepSizes(tester, sizes: const [Size(300, 9000), Size(420, 9000)]);
    });
    testWidgets("$name's Chain, narrow to wide, both text sizes",
        (tester) async {
      await pump(tester, e, (c) => AnimationPanel(controller: c, height: 420),
          size: const Size(900, 600));
      await sweepSizes(tester, sizes: const [Size(900, 600), Size(1600, 600)]);
    });
  }
}
