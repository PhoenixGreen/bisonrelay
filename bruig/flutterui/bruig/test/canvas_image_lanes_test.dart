import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart'
    show VectorCue;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/image_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_image_lanes_test.dart is a picture's layers on the timeline: a lane
// each, picked by a click and retimed by a drag.

final _top = ImageLayer.picture("blue", const Rect.fromLTWH(0, 0, 500, 500));

ImageElement _picture() => ImageElement(
      ElementBase(
          id: "i",
          x: 0,
          y: 0,
          width: 100,
          height: 100,
          track: ElementTrack(const [
            Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
            Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
          ])),
      assetId: "red",
      animation: const ElementAnimation(preset: ElementAnimationPreset.fadeIn),
      layers: [ImageLayer.base, _top],
    );

void main() {
  group("timing by frames", () {
    test("a start is said as the cue that puts it there", () {
      var e = _picture();
      expect(withLayerStartAt(e, 1, 0, 10).stack[1].cue, VectorCue.together);
      expect(withLayerStartAt(e, 1, 10, 10).stack[1].cue, VectorCue.after);
      var gap = withLayerStartAt(e, 1, 14, 10).stack[1];
      expect(gap.cue, VectorCue.gap);
      expect(gap.cueGap, 4);
    });

    test("the arrival is fitted round the layers again", () {
      var e = withLayerSpanFitted(
          withLayerStartAt(_picture(), 1, 10, 10));
      expect(imageArrivalSpan(e), (0, 20),
          reason: "ten for the base, then ten for the layer");
    });
  });

  testWidgets("a lane each: picked by a click, retimed by a drag",
      (tester) async {
    var c = CanvasController(
        const CanvasDocument().copyWith(frames: 100).addElement(_picture()));
    addTearDown(c.dispose);
    c.selectOnly("i");
    expect(imageLanesFor(c), isNotNull,
        reason: "offered before anything is staggered");
    expect(imageLanesShown(c, imageLanesFor(c)!), isEmpty);
    c.vectorLanes = VectorLanes.all;
    expect(imageLanesShown(c, imageLanesFor(c)!), [0, 1]);
    expect(imageLanesLabel(VectorLanes.picked), "Layer picked");

    tester.view.physicalSize = const Size(1200, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const view = TimelineView(0, 100);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListenableBuilder(
                listenable: c,
                builder: (context, _) =>
                    ImageLayerLanes(controller: c, view: view)))));
    ImageElement now() => c.document.elementById("i")! as ImageElement;
    var lanes = find.byKey(const ValueKey("imageLayerLanes"));
    var origin = tester.getTopLeft(lanes) + Offset(c.headerWidth, 0);
    var width = 1200 - c.headerWidth;
    Offset at(int frame, int lane) =>
        origin +
        Offset(view.centreOf(frame, width),
            lane * imageLaneHeight + imageLaneHeight / 2);

    // A click on the second lane picks the layer over the base.
    await tester.tapAt(at(5, 1));
    await tester.pump();
    expect(c.imageEditing, "i");
    expect(c.imageLayer, _top.id);

    // Its end dragged from frame 10 to 4: it takes four frames.
    await tester.dragFrom(at(10, 1), at(4, 1) - at(10, 1));
    await tester.pumpAndSettle();
    expect(now().layerById(_top.id)!.cueLength, 4);

    // Its bar dragged on to where the base ends: after it.
    await tester.dragFrom(at(2, 1), at(12, 1) - at(2, 1));
    await tester.pumpAndSettle();
    expect(now().layerById(_top.id)!.cue, VectorCue.after);
    expect(imageArrivalSpan(now()), (0, 14),
        reason: "the arrival fitted round both: ten, then four");
    c.undo();
    expect(now().layerById(_top.id)!.cue, VectorCue.together,
        reason: "a drag is one undo step");
    expect(tester.takeException(), isNull);
  });
}
