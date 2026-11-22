import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_controller_load_test.dart holds the editing session to letting go
// of one canvas when another is opened. The session lives as long as the
// app, so whatever it keeps about a canvas (a scene picked, a studio open
// on one of its sheets, rows fetched for one of its tables) is met by the
// next canvas unless load forgets it.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("opening another canvas forgets what was kept about the last", () {
    var c = CanvasController(const CanvasDocument(scenes: [
      CanvasScene(id: "a"),
      CanvasScene(id: "b"),
      CanvasScene(id: "c"),
    ]));
    addTearDown(c.dispose);

    c.pickScene(2);
    c.goToScene(1);
    c.lastFetched["chart1"] = const FetchedRows([], [], []);
    c.toggleClipSettings("shape1");
    c.dataStudio.value = "sheet1";
    c.scoreStudio.value = "score1";
    c.codeStudio.value = "code1";
    c.studio3dOpen.value = true;
    c.studio3dElement = "hero";
    c.setAnalysing("ch1", "eq", true);
    c.setPresetName("ch1", "eq", "Bright");
    c.hoveredButton = "button1";

    c.load(const CanvasDocument(scenes: [
      CanvasScene(id: "a"),
      CanvasScene(id: "b"),
      CanvasScene(id: "c"),
    ]));

    expect(c.pickedScene, isNull);
    expect(c.lastFetched, isEmpty);
    expect(c.clipSettingsOpen("shape1"), isFalse);
    expect(c.dataStudio.value, isNull);
    expect(c.scoreStudio.value, isNull);
    expect(c.codeStudio.value, isNull);
    expect(c.studio3dOpen.value, isFalse);
    expect(c.studio3dElement, isNull);
    expect(c.analysing("ch1", "eq"), isFalse);
    expect(c.presetNameOf("ch1", "eq"), isNull);
    expect(c.hoveredButton, isNull);
    expect(c.selection, isEmpty);
    expect(c.canUndo, isFalse);
    // The scenes share ids with the last canvas's: where the playhead was
    // left on one of those is not where it is on these.
    c.frame = 0;
    expect(c.frameOn(0), 0);
  });

  test("the painters' hooks go back to the editor when a second session shuts",
      () {
    // A canvas played in Files has a session of its own, made while the
    // editor's is alive, and the hooks the painters ask are one each for
    // the app. Shut, it must hand them back.
    var editor = CanvasController(const CanvasDocument(frames: 48));
    addTearDown(editor.dispose);
    var played = CanvasController(const CanvasDocument(frames: 48));

    played.play();
    expect(sheetPlaying!(), isTrue, reason: "the newest session answers");
    played.dispose();

    expect(sheetPlaying!(), isFalse, reason: "the editor's, which is paused");
    editor.play();
    expect(sheetPlaying!(), isTrue);
    editor.pause();
  });

  test("opening another canvas forgets how the last was looked at", () {
    // Channel heights and the stretch of the timeline in view are a
    // canvas's own. One never saved has no view kept to put in their place,
    // so what the last canvas left would be what it opened with.
    var c = CanvasController(const CanvasDocument(frames: 48));
    addTearDown(c.dispose);
    c.setLaneHeight("narrator", 120);
    c.timelineView = const TimelineView(10, 20);
    c.openEffects("narrator");
    expect(c.canvasView, isNotEmpty);

    c.load(const CanvasDocument(frames: 48));
    expect(c.laneHeights, isEmpty);
    expect(c.timelineView, isNull);
    expect(c.canvasView, isEmpty);
  });

  test("opening another canvas lets go of the editor's loop", () {
    // The loop is round a stretch of the last canvas's frames.
    var c = CanvasController(const CanvasDocument(frames: 200));
    addTearDown(c.dispose);
    c.looping = true;
    c.setLoop(100, 50);

    c.load(const CanvasDocument(frames: 200));
    expect(c.looping, isFalse);
    expect(c.loopRange, (0, 200), reason: "where a first press would put it");
  });

  test("coming back to the page finds the zoom as it was left", () {
    // The page puts the frame last chosen back each time it opens. The same
    // frame as now is no change, and must not send the view back to fit.
    var c = CanvasController(const CanvasDocument());
    addTearDown(c.dispose);
    c.restoreFit(CanvasFit.width);
    c.zoom = 2;
    c.restoreFit(CanvasFit.width);
    expect(c.zoom, 2);
    c.restoreFit(CanvasFit.whole);
    expect(c.zoom, 1, reason: "another frame starts from the whole of it");
  });
}
