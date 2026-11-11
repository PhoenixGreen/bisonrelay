import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/own_motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_tier1_defaults_test.dart is the defaults and knobs Ken's privacy
// video found wanting (2026-11-11, the report's tier 1): a chart's titles,
// a fitted text's size, where a new exit goes, and how far a camera move
// goes.

void main() {
  test("a new chart has its titles to fill in, hidden until they are", () {
    var chart =
        newElement(ElementKind.chart, const CanvasDocument()) as ChartElement;
    expect(chart.titleBox.show, isFalse);
    expect(chart.showXTitle, isFalse);
    expect(chart.showYTitle, isFalse);
    expect(chart.title, isNotEmpty, reason: "there when turned on");
  });

  group("a new exit", () {
    test("after the arrival and a hold, not at the end of the scene", () {
      const doc = CanvasDocument(frames: 480, frameRate: 24);
      var (from, to) = newExitSpan(24, 12, doc);
      expect(from, 24 + 1 + 48, reason: "two seconds after it arrives");
      expect(to, from + 12);
    });

    test("at the end where the scene is too short for the hold", () {
      const doc = CanvasDocument(frames: 60, frameRate: 24);
      var (from, to) = newExitSpan(30, 12, doc);
      expect(to, 59);
      expect(from, 47);
    });

    test("laid by the controller after the element's arrival", () {
      var c = CanvasController(const CanvasDocument(frames: 480, frameRate: 24)
          .addElement(ShapeElement(const ElementBase(id: "s"))));
      addTearDown(c.dispose);
      c.applyElementAnimation(
          c.document.elementById("s")!, ElementAnimationPreset.fadeIn,
          length: 12);
      c.applyElementExit(
          c.document.elementById("s")!, ElementAnimationPreset.fadeIn);
      var e = c.document.elementById("s")!;
      var (arriveAt, arriveFor) = ownSpan(e, MotionKind.arrive, 24)!;
      var (leaveAt, _) = ownSpan(e, MotionKind.leave, 24)!;
      expect(leaveAt - (arriveAt + arriveFor), closeTo(49, 1),
          reason: "up for two seconds before it goes");
    });
  });

  group("a camera move's amount", () {
    test("Push in on… goes as close as asked, keeping its shape", () {
      var push = presetNamed("Push in on…")!.clip("c", target: "t");
      expect(cameraZoomOf(push), 1.7);
      var closer = withCameraZoom(push, 2.5);
      expect(cameraZoomOf(closer), 2.5);
      var scale = closer.keys[MotionProp.scale]!;
      expect((scale.first.value as MotionNumber).value, 1,
          reason: "it still starts from where it was");
      expect(cameraShakeOf(push), isNull, reason: "a push does not shake");
    });

    test("Camera shake shakes as hard as asked", () {
      var shake = presetNamed("Camera shake")!.clip("c");
      expect(cameraZoomOf(shake), isNull);
      expect(cameraShakeOf(shake), 9);
      var harder = withCameraShake(shake, 18);
      expect(cameraShakeOf(harder), 18);
    });
  });

  testWidgets("a size typed on a fitted text sets it, and stops the fitting",
      (tester) async {
    CanvasSection.openAll = true;
    addTearDown(() => CanvasSection.openAll = false);
    var text =
        newElement(ElementKind.text, const CanvasDocument()) as TextElement;
    expect(text.autoSize, isTrue, reason: "a new text is fitted");
    var c = CanvasController(const CanvasDocument().addElement(text));
    addTearDown(c.dispose);
    c.selectOnly(text.id);
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: SizedBox(
              width: 300,
              height: 2400,
              child: CanvasDesignPanel(controller: c)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var size = find.byKey(const ValueKey("typeSize"));
    expect(size, findsWidgets);
    var field = tester.widget<CanvasNumberField>(size.first);
    expect(field.label, contains("fitted"), reason: "it says it is fitted");
    field.onChanged(64);
    field.onCommit?.call();
    await tester.pumpAndSettle();
    var now = c.document.elementById(text.id) as TextElement;
    expect(now.textSpec.fontSize, 64);
    expect(now.autoSize, isFalse, reason: "the size typed is the size drawn");
  });
}
