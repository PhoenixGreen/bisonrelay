import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transitions_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_keep_timing_test.dart is a run of scenes cut to a voice-over, whose
// start times must not move when a transition or a length is changed.

const _fade = SceneTransition(kind: SceneTransitionKind.fade);

CanvasDocument _four({bool keep = true}) => CanvasDocument(
      keepTiming: keep,
      scenes: [
        for (var i = 0; i < 4; i++)
          CanvasScene(id: "s$i", frames: 100, transition: _fade),
      ],
    );

List<int> _starts(CanvasDocument d) =>
    [for (var i = 0; i < d.allScenes.length; i++) d.startOfScene(i)];

void main() {
  group("the document", () {
    test("a longer transition is taken from the scene before it", () {
      var d = _four();
      var longer = d.withScene(
          1, d.allScenes[1].copyWith(transition: _fade.copyWith(frames: 30, overlap: 30)));
      expect(_starts(longer), isNot(_starts(d)),
          reason: "left alone, everything after it moves");
      var kept = longer.keepingStarts(d);
      expect(_starts(kept), _starts(d));
      expect(kept.allScenes[1].frames, 118, reason: "18 more frames shared");
      expect(kept.sequenceFrames, d.sequenceFrames);
    });

    test("a longer scene is taken from the one after it", () {
      var d = _four();
      var longer = d.withScene(1, d.allScenes[1].copyWith(frames: 130));
      var kept = longer.keepingStarts(d, fixed: {"s1"});
      expect(kept.allScenes[1].frames, 130, reason: "the change asked for");
      expect(kept.allScenes[2].frames, 70, reason: "taken from its neighbour");
      expect(kept.startOfScene(3), d.startOfScene(3));
    });

    test("the setting is saved", () {
      expect(CanvasDocument.decode(_four().encode())!.keepTiming, isTrue);
      expect(_four(keep: false).toJson().containsKey("keepTiming"), isFalse);
    });
  });

  group("the controller", () {
    test("a transition changed keeps every start, with the setting on", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      var before = _starts(c.document);
      c.setSceneTransition(0, _fade.copyWith(frames: 24, overlap: 24));
      c.setDefaultTransition(_fade.copyWith(frames: 6, overlap: 6));
      expect(_starts(c.document), before);
    });

    test("and moves them with it off, as it always did", () {
      var c = CanvasController(_four(keep: false));
      addTearDown(c.dispose);
      var before = _starts(c.document);
      c.setSceneTransition(0, _fade.copyWith(frames: 24, overlap: 24));
      expect(_starts(c.document), isNot(before));
    });

    test("the Length field takes from the next scene", () {
      var c = CanvasController(_four());
      addTearDown(c.dispose);
      var before = _starts(c.document);
      c.goToScene(1);
      c.setSceneLength(140);
      expect(c.document.allScenes[1].frames, 140);
      expect(c.document.startOfScene(3), before[3]);
    });
  });

  testWidgets("the panel's switch turns it on", (tester) async {
    var c = CanvasController(_four(keep: false));
    addTearDown(c.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 280, child: CanvasTransitionsPanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    var toggle = find.byKey(const ValueKey("keepTiming"));
    expect(toggle, findsOneWidget);
    tester.widget<CanvasToggle>(toggle).onChanged(true);
    await tester.pumpAndSettle();
    expect(c.document.keepTiming, isTrue);
  });
}
