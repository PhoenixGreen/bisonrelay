import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// An element moved by a clip is clicked where it is drawn, not where it
// rests: the boundsAt lesson again, for clips.

void main() {
  testWidgets("moved by a clip, it is clicked where it is drawn",
      (tester) async {
    var key = GlobalKey<CanvasStageState>();
    var c = CanvasController(const CanvasDocument(frames: 48, frameRate: 24)
        .addElement(ShapeElement(
            const ElementBase(id: "s", x: 100, y: 100, width: 100, height: 100),
            fill: const Color(0xFFFF0000),
            strokeWidth: 0)));
    addTearDown(c.dispose);
    // 300 across in its first second, and held there.
    var clip = c.newClip("s");
    c.editMotionClip(
        "s",
        clip,
        (m) => m.copyWith(length: 1, after: ClipHold.last, keys: {
              MotionProp.x: const [
                MotionKey(0, MotionNumber(0)),
                MotionKey(1, MotionNumber(300)),
              ],
            }));
    c.placeClip("s", clip, seconds: 0);
    c.frame = 36;
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 900,
                  height: 700,
                  child: CanvasStage(key: key, controller: c)))),
    ));
    await tester.pumpAndSettle();
    var stage = key.currentState!;
    // Where it rests: nothing there now.
    await tester.tapAt(stage.toStagePoint(const Offset(150, 150)));
    await tester.pumpAndSettle();
    expect(c.selection, isEmpty);
    // Where the clip has taken it.
    await tester.tapAt(stage.toStagePoint(const Offset(450, 150)));
    await tester.pumpAndSettle();
    expect(c.selection, {"s"});
  });
}
