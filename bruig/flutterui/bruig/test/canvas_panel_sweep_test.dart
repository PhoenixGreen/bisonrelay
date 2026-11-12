import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/ui/animation_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
    ];
  }

  Future<CanvasController> pump(WidgetTester tester, CanvasElement e,
      Widget Function(CanvasController) body,
      {required Size size, required double scale}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var c = CanvasController(
        const CanvasDocument(frames: 96, frameRate: 24).addElement(e));
    addTearDown(c.dispose);
    c.selectOnly(e.id);
    if (CanvasController.animates(e)) {
      c.applyElementAnimation(e, ElementAnimationPreset.fadeUp);
      c.applyElementExit(
          c.document.elementById(e.id)!, ElementAnimationPreset.fadeUp);
    }
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
          home: Scaffold(body: body(c))),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return c;
  }

  for (var (name, e) in elements()) {
    for (var scale in [1.0, 1.4]) {
      for (var width in [300.0, 420.0]) {
        testWidgets("$name's settings at ${width}px, ${scale}x",
            (tester) async {
          await pump(
              tester,
              e,
              (c) => SizedBox(
                  width: width, child: CanvasDesignPanel(controller: c)),
              size: Size(width, 9000),
              scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
      for (var width in [900.0, 1600.0]) {
        testWidgets("$name's Chain at ${width}px, ${scale}x", (tester) async {
          await pump(
              tester, e, (c) => AnimationPanel(controller: c, height: 420),
              size: Size(width, 600), scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
