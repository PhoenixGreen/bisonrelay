import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_animation_test.dart is about what an element looks like at frame N.
//
// It is the one calculation three different things depend on agreeing about --
// the editing stage, the exported GIF, and a published interactive canvas
// being replayed -- and none of them would notice the others disagreeing.

void main() {
  test("an empty track is the resting pose", () {
    expect(ElementTrack.empty.at(0).isRest, isTrue);
    expect(ElementTrack.empty.at(999).isRest, isTrue);
  });

  test("keys are sorted however they are given", () {
    var track = ElementTrack(const [
      Keyframe(frame: 20, dx: 20),
      Keyframe(frame: 0, dx: 0),
      Keyframe(frame: 10, dx: 10),
    ]);
    expect([for (var k in track.keys) k.frame], [0, 10, 20]);
  });

  test("a pose is interpolated between its neighbours", () {
    var track = ElementTrack(const [
      Keyframe(frame: 0, dx: 0, opacity: 0),
      Keyframe(frame: 10, dx: 100, opacity: 1),
    ]);
    expect(track.at(0).dx, 0);
    expect(track.at(5).dx, closeTo(50, 0.001));
    expect(track.at(5).opacity, closeTo(0.5, 0.001));
    expect(track.at(10).dx, 100);
  });

  test("outside the keys the nearest pose holds", () {
    // Holding rather than extrapolating. An element that fades in over frames
    // 0-10 should stay visible for the rest of the document, not carry on
    // getting brighter.
    var track = ElementTrack(const [
      Keyframe(frame: 5, dx: 10),
      Keyframe(frame: 10, dx: 20),
    ]);
    expect(track.at(0).dx, 10);
    expect(track.at(3).dx, 10);
    expect(track.at(50).dx, 20);
  });

  test("hold easing snaps rather than blends", () {
    var track = ElementTrack(const [
      Keyframe(frame: 0, dx: 0, easing: KeyframeEasing.hold),
      Keyframe(frame: 10, dx: 100),
    ]);
    expect(track.at(1).dx, 0);
    expect(track.at(9).dx, 0);
    expect(track.at(10).dx, 100);
  });

  test("easings all start and end in the same place", () {
    // Whatever the curve does in the middle, a keyframe has to be reached
    // exactly -- an easing that overshot would move an element somewhere the
    // person who placed it never put it.
    for (var easing in KeyframeEasing.values) {
      expect(easing.apply(0), 0, reason: "$easing at 0");
      if (easing == KeyframeEasing.hold) continue;
      expect(easing.apply(1), closeTo(1, 1e-9), reason: "$easing at 1");
      for (var i = 0; i <= 10; i++) {
        var t = easing.apply(i / 10);
        expect(t, inInclusiveRange(-1e-9, 1 + 1e-9),
            reason: "$easing overshoots at ${i / 10}");
      }
    }
  });

  test("withKey replaces the keyframe on the same frame", () {
    var track = ElementTrack(const [Keyframe(frame: 5, dx: 1)])
        .withKey(const Keyframe(frame: 5, dx: 99));
    expect(track.keys.length, 1);
    expect(track.keys.single.dx, 99);
  });

  test("withoutFrame removes just that one", () {
    var track = ElementTrack(const [
      Keyframe(frame: 0),
      Keyframe(frame: 5),
      Keyframe(frame: 9),
    ]).withoutFrame(5);
    expect([for (var k in track.keys) k.frame], [0, 9]);
  });

  test("two keys on one frame do not divide by zero", () {
    // Reachable from a saved file rather than from the editor, which replaces
    // rather than appends -- but a file is text from disk and may say
    // anything.
    var track = ElementTrack(const [
      Keyframe(frame: 4, dx: 1),
      Keyframe(frame: 4, dx: 2),
    ]);
    expect(track.at(4).dx, isNot(isNaN));
  });

  test("lastFrame is where the track stops changing", () {
    expect(ElementTrack.empty.lastFrame, 0);
    expect(
        ElementTrack(const [Keyframe(frame: 3), Keyframe(frame: 17)]).lastFrame,
        17);
  });

  group("moving something that is animated", () {
    // The bug this group exists for, in the reporter's own words: "create a
    // keyframe on frame 1, move the playhead to frame 20, move an element, add
    // a keyframe on frame 20 -- the movement isn't animated".
    //
    // Nothing was broken. A keyframe's dx and dy are offsets from the
    // element's *resting* position, and dragging moved the resting position --
    // so both keyframes recorded an offset of zero and the whole animation
    // slid along with the element. The drag had answered a different question
    // from the one being asked. See CanvasController.posesRatherThanMoves.

    CanvasController animated({bool auto = false}) {
      var document = const CanvasDocument(frames: 24);
      var element = ShapeElement(
        const ElementBase(id: "s1", x: 100, y: 100, width: 50, height: 50),
      );
      var controller = CanvasController(document.addElement(element));
      controller.autoKeyframe = auto;
      controller.selectOnly("s1");
      return controller;
    }

    Offset positionAt(CanvasController c, int frame) {
      var e = c.document.elementById("s1")!;
      var pose = (e.track ?? ElementTrack.empty).at(frame);
      return Offset(e.x + pose.dx, e.y + pose.dy);
    }

    test("a chart's animation preset does not turn drags into keyframes", () {
      // Reported: "keyframes are recording actions without auto keyframing
      // turned on -- I have an animation set for a chart using the chart
      // animation presets, I then re-position the chart and wherever the
      // playhead is it creates a new move keyframe".
      //
      // The presets lay two keyframes that carry nothing but how much of the
      // chart has been drawn. Those were read as "this element is animated",
      // which is true, and then as "so a drag is a pose", which is not: the
      // chart has been told how to arrive, not where to be.
      var controller = animated();
      addTearDown(controller.dispose);

      var element = controller.document.elementById("s1")!;
      controller.replaceElement(element.withBase(
        track: ElementTrack(const [
          Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
          Keyframe(frame: 20, values: {KeyframeChannel.reveal: 1}),
        ]),
      ));

      controller.frame = 12;
      controller.nudgeSelected(40, 0);

      var after = controller.document.elementById("s1")!;
      expect(after.x, 140, reason: "the element moved, as a drag should");
      expect(after.track!.keys.length, 2,
          reason: "and no keyframe was written to say so");
      for (var key in after.track!.keys) {
        expect(key.dx, 0);
        expect(key.dy, 0);
      }
      // The arrival it was given is untouched and still travels with it.
      expect(after.track!.at(0).values[KeyframeChannel.reveal], 0);
      expect(after.track!.at(20).values[KeyframeChannel.reveal], 1);
    });

    test("but a keyframe laid by hand still means poses", () {
      // The other side of the same rule. A keyframe deliberately pinned to
      // hold something where it is says nothing about any channel, and is the
      // clearest statement there is that this element's position is being
      // animated.
      var controller = animated();
      addTearDown(controller.dispose);
      controller.frame = 1;
      controller.setKeyframe("s1", const Keyframe(frame: 1));

      expect(
          controller
              .posesRatherThanMoves(controller.document.elementById("s1")!),
          isTrue);
    });

    test("the reported sequence now animates", () {
      var controller = animated();
      addTearDown(controller.dispose);

      // Frame 1: pin it where it is.
      controller.frame = 1;
      controller.setKeyframe("s1", const Keyframe(frame: 1));

      // Frame 20: move it, then pin it again.
      controller.frame = 20;
      controller.nudgeSelected(200, 60);
      controller.setKeyframe(
          "s1",
          (controller.document.elementById("s1")!.track ?? ElementTrack.empty)
              .at(20)
              .copyWith(frame: 20));

      expect(positionAt(controller, 1), const Offset(100, 100),
          reason: "frame 1 must still be where it was pinned");
      expect(positionAt(controller, 20), const Offset(300, 160));
      // And it is genuinely interpolated in between rather than snapping.
      var middle = positionAt(controller, 10);
      expect(middle.dx, greaterThan(100));
      expect(middle.dx, lessThan(300));
    });

    test("an element with no keyframes still just moves", () {
      // Posing must not become the only behaviour. Laying a document out is
      // moving things, and every move recording itself would be unusable.
      var controller = animated();
      addTearDown(controller.dispose);
      controller.frame = 8;
      controller.nudgeSelected(30, 40);

      var element = controller.document.elementById("s1")!;
      expect(element.x, 130);
      expect(element.y, 140);
      expect(element.track, isNull);
    });

    test("a still document always moves rather than posing", () {
      // frames == 1, so there is no timeline to record onto.
      var controller = CanvasController(const CanvasDocument()
          .addElement(ShapeElement(const ElementBase(id: "s1", x: 0, y: 0))));
      addTearDown(controller.dispose);
      controller.selectOnly("s1");
      controller.autoKeyframe = true;
      controller.nudgeSelected(10, 10);

      expect(controller.document.elementById("s1")!.x, 10);
      expect(controller.document.elementById("s1")!.track, isNull);
    });

    test("auto-keyframe records a move without any keyframe being asked for",
        () {
      var controller = animated(auto: true);
      addTearDown(controller.dispose);

      controller.frame = 12;
      controller.nudgeSelected(120, 0);

      expect(positionAt(controller, 12).dx, 220);
      expect(controller.document.elementById("s1")!.x, 100,
          reason: "the resting position is untouched; the pose moved");
      // The start is seeded, so one drag is a movement rather than a
      // displacement that holds for the whole document -- see
      // ElementTrack.seededFor.
      expect(positionAt(controller, 0).dx, 100);
      expect(positionAt(controller, 6).dx, closeTo(160, 0.001));
    });

    test("the seeded start is only ever added to an empty track", () {
      // A second key is the author placing poses deliberately, and inserting
      // one they did not ask for would overwrite their first frame.
      var controller = animated(auto: true);
      addTearDown(controller.dispose);

      controller.frame = 0;
      controller.setKeyframe("s1", const Keyframe(frame: 0, dx: 25));
      controller.frame = 10;
      controller.nudgeSelected(30, 0);

      expect(positionAt(controller, 0).dx, 125,
          reason: "the author's own frame 0 stands");
      expect(controller.document.elementById("s1")!.track!.keys.length, 2);
    });

    test("moving several elements on different frames builds one animation",
        () {
      // What auto-keyframe is for: park the playhead, drag one thing, move on.
      var document = const CanvasDocument(frames: 30)
          .addElement(ShapeElement(const ElementBase(id: "a", x: 0, y: 0)))
          .addElement(ShapeElement(const ElementBase(id: "b", x: 0, y: 0)));
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      controller.autoKeyframe = true;

      controller.selectOnly("a");
      controller.frame = 5;
      controller.nudgeSelected(50, 0);

      controller.selectOnly("b");
      controller.frame = 20;
      controller.nudgeSelected(0, 80);

      var a = controller.document.elementById("a")!;
      var b = controller.document.elementById("b")!;
      expect(a.track!.keyAt(5), isNotNull);
      expect(b.track!.keyAt(20), isNotNull);
      expect(a.track!.keyAt(20), isNull, reason: "each keeps its own track");
      expect(controller.document.lastAnimatedFrame, 20);
    });

    test("the resting position is still reachable through the settings", () {
      // The escape hatch: dragging poses an animated element, so relocating
      // one wholesale goes through X and Y, and the whole animation travels
      // with it because keyframes are offsets.
      var controller = animated();
      addTearDown(controller.dispose);
      controller.frame = 10;
      controller.setKeyframe("s1", const Keyframe(frame: 10, dx: 40));

      var element = controller.document.elementById("s1")!;
      controller.replaceElement(element.withBase(x: 500));

      expect(positionAt(controller, 10).dx, 540,
          reason: "the pose rides on the new resting position");
    });
  });

  group("a player's own animation", () {
    TeamElement teamOf(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    CanvasController withTeam() {
      var team = TeamElement(
        const ElementBase(id: "t1", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller =
          CanvasController(const CanvasDocument(frames: 24).addElement(team));
      controller.selectOnly("t1");
      return controller;
    }

    test("each player animates independently", () {
      // The whole point of a tactics diagram: the winger makes the run and
      // everybody else holds their line. A team-wide track can only move all
      // eleven at once, which is the one movement no move ever is.
      var controller = withTeam();
      addTearDown(controller.dispose);

      controller.frame = 0;
      controller.setPlayerKeyframe("t1", 6, const Keyframe(frame: 0));
      controller.frame = 18;
      controller.setPlayerKeyframe("t1", 6, const Keyframe(frame: 18, dx: 90));

      var team = teamOf(controller);
      expect(team.players[6].track, isNotNull);
      expect(team.players[5].track, isNull, reason: "nobody else moved");

      var rest = team.centreOf(team.players[6]);
      expect(team.centreAt(team.players[6], 0).dx, rest.dx);
      expect(team.centreAt(team.players[6], 18).dx, rest.dx + 90);
      expect(
          team.centreAt(team.players[6], 9).dx, closeTo(rest.dx + 45, 0.001));
    });

    test("a player's run survives the team being moved and resized", () {
      // Offsets on top of a fractional resting position, so both transforms
      // compose rather than one of them cancelling the other.
      var controller = withTeam();
      addTearDown(controller.dispose);
      controller.setPlayerKeyframe("t1", 6, const Keyframe(frame: 10, dx: 60));

      var team = teamOf(controller);
      var moved = team.withBase(x: 200, y: 100) as TeamElement;
      expect(moved.centreAt(moved.players[6], 10).dx,
          closeTo(team.centreAt(team.players[6], 10).dx + 200, 0.001));
    });

    test("the document's length counts a player's keyframes", () {
      // Asking the element alone reports a pitch full of runs as a still,
      // because a team's movement lives on its players.
      var controller = withTeam();
      addTearDown(controller.dispose);
      expect(controller.document.lastAnimatedFrame, 0);

      controller.setPlayerKeyframe("t1", 3, const Keyframe(frame: 21));
      expect(controller.document.lastAnimatedFrame, 21);
    });

    test("removing the last keyframe drops the track", () {
      var controller = withTeam();
      addTearDown(controller.dispose);
      controller.setPlayerKeyframe("t1", 2, const Keyframe(frame: 4, dx: 5));
      expect(teamOf(controller).players[2].track, isNotNull);

      controller.removePlayerKeyframe("t1", 2, 4);
      expect(teamOf(controller).players[2].track, isNull,
          reason: "no empty track goes into the saved file");
    });

    test("a player's keyframes survive a round trip", () {
      var controller = withTeam();
      addTearDown(controller.dispose);
      controller.setPlayerKeyframe(
          "t1", 9, const Keyframe(frame: 14, dx: 33, dy: -12));

      var back = CanvasDocument.decode(controller.document.encode())!;
      var team = back.elements.whereType<TeamElement>().single;
      expect(team.players[9].track!.keyAt(14)!.dx, 33);
      expect(team.players[9].track!.keyAt(14)!.dy, -12);
    });
  });

  group("formation spread", () {
    test("own half fits everybody inside the box", () {
      var team =
          TeamElement(const ElementBase(id: "t", width: 400, height: 300))
              .withFormation(TeamFormation.f442,
                  spread: FormationSpread.ownHalf);
      for (var p in team.players) {
        expect(p.dx, inInclusiveRange(0, 1), reason: p.number);
        expect(p.dy, inInclusiveRange(0, 1), reason: p.number);
      }
    });

    test("attacking pushes the forwards past the box", () {
      // The real metres: a 4-4-2's strikers stand about fifteen metres inside
      // the opposition half, so their fraction of a *half* is over 1.
      var team =
          TeamElement(const ElementBase(id: "t", width: 400, height: 300))
              .withFormation(TeamFormation.f442,
                  spread: FormationSpread.attacking);
      expect(team.players.last.dx, greaterThan(1));
      expect(team.players.first.dx, lessThan(0.2),
          reason: "the keeper is deep");
    });

    test("both spreads keep the same shape", () {
      // Only the denominator differs, so the order of the lines is identical.
      var box = const ElementBase(id: "t", width: 400, height: 300);
      var attacking = TeamElement(box)
          .withFormation(TeamFormation.f442, spread: FormationSpread.attacking);
      var own = TeamElement(box)
          .withFormation(TeamFormation.f442, spread: FormationSpread.ownHalf);

      for (var i = 1; i < attacking.players.length; i++) {
        expect(own.players[i].dx.compareTo(own.players[i - 1].dx),
            attacking.players[i].dx.compareTo(attacking.players[i - 1].dx),
            reason: "player $i");
        expect(own.players[i].dy, closeTo(attacking.players[i].dy, 0.0001),
            reason: "across the pitch nothing changes");
      }
    });

    test("the spread survives a change of formation", () {
      // Kept as a field for the same reason mirrored is: changing the shape
      // must not quietly change which of the two pictures is being shown.
      var team =
          TeamElement(const ElementBase(id: "t", width: 400, height: 300))
              .withFormation(TeamFormation.f442,
                  spread: FormationSpread.ownHalf)
              .withFormation(TeamFormation.f433);
      expect(team.spread, FormationSpread.ownHalf);
      for (var p in team.players) {
        expect(p.dx, inInclusiveRange(0, 1));
      }
    });
  });

  group("the reveal channel", () {
    test("moving a keyframe along the timeline keeps what it pins", () {
      // How a chart's animation is lengthened: the two keyframes are ordinary
      // ones, dragged on the timeline like anything else, so retiming one must
      // not drop the channel that made it worth having.
      var key = const Keyframe(frame: 4).withValue(KeyframeChannel.reveal, 1);
      var moved = key.copyWith(frame: 30);

      expect(moved.frame, 30);
      expect(moved.values[KeyframeChannel.reveal], 1);
    });

    test("between the two keyframes it interpolates", () {
      var track = ElementTrack.empty
          .withKey(
              const Keyframe(frame: 0).withValue(KeyframeChannel.reveal, 0))
          .withKey(
              const Keyframe(frame: 10).withValue(KeyframeChannel.reveal, 1));

      expect(track.at(0).values[KeyframeChannel.reveal], 0);
      expect(track.at(5).values[KeyframeChannel.reveal], closeTo(0.5, 0.001));
      expect(track.at(10).values[KeyframeChannel.reveal], 1);
    });
  });

  group("a chart that leaves as well as arrives", () {
    // The closing animation is the same presets played backwards, on a second
    // pair of keyframes. Its own channel rather than running the first one
    // back down to zero, because the two ends can be different animations --
    // grow in, fade out -- and one number going up and then down does not say
    // which of them is being drawn.

    CanvasController withChart() {
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 48, frameRate: 12).addElement(chart));
      controller.selectOnly("c");
      return controller;
    }

    ChartElement chartIn(CanvasController c) =>
        c.document.elementById("c") as ChartElement;

    test("choosing one lays a pair of keyframes at the end", () {
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.applyChartExit(
          chartIn(controller), ChartAnimationPreset.fadeIn);

      var track = chartIn(controller).track!;
      var closes = [
        for (var key in track.keys)
          if (key.values.containsKey(KeyframeChannel.close)) key,
      ];
      expect(closes.length, 2);
      expect(closes.first.values[KeyframeChannel.close], 0);
      expect(closes.last.values[KeyframeChannel.close], 1);
      expect(closes.last.frame, 47,
          reason: "it is the thing that happens last");
    });

    test("and it never starts before the entrance has finished", () {
      // Both at once is a chart arriving and leaving in the same breath,
      // which draws as a stutter and reads as a bug.
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.frame = 0;
      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.grow);
      var entranceEnds = 0;
      for (var key in chartIn(controller).track!.keys) {
        if (key.values[KeyframeChannel.reveal] == 1) entranceEnds = key.frame;
      }

      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.grow);
      var band = bandsIn(chartIn(controller).track!)
          .firstWhere((b) => b.channel == KeyframeChannel.close);
      expect(band.from, greaterThan(entranceEnds));
    });

    test("choosing None takes the keyframes with it", () {
      // A chart with no closing animation and a pair of close keyframes still
      // on its track would be pinned at "gone" for the end of the timeline.
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.grow);
      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.none);

      var track = chartIn(controller).track;
      expect(
          track?.keys.where((k) => k.values.containsKey(KeyframeChannel.close)),
          anyOf(isNull, isEmpty));
      expect(chartIn(controller).animation.closes, isFalse);
    });

    test("the entrance is left alone by both", () {
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.grow);
      var before = bandsIn(chartIn(controller).track!)
          .firstWhere((b) => b.channel == KeyframeChannel.reveal);

      controller.applyChartExit(
          chartIn(controller), ChartAnimationPreset.fadeIn);
      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.none);
      var after = bandsIn(chartIn(controller).track!)
          .firstWhere((b) => b.channel == KeyframeChannel.reveal);

      expect([after.from, after.to], [before.from, before.to]);
      expect(chartIn(controller).animation.preset, ChartAnimationPreset.grow);
    });

    test("a pair is one band, four separate poses are none", () {
      var track = ElementTrack(const [
        Keyframe(frame: 0, values: {KeyframeChannel.reveal: 0}),
        Keyframe(frame: 10, values: {KeyframeChannel.reveal: 1}),
        Keyframe(frame: 30, values: {KeyframeChannel.close: 0}),
        Keyframe(frame: 47, values: {KeyframeChannel.close: 1}),
      ]);
      var bands = bandsIn(track);
      expect(bands.length, 2);
      expect([bands[0].from, bands[0].to], [0, 10]);
      expect([bands[1].from, bands[1].to], [30, 47]);

      // Four poses of an element moving about are four poses. Joining them up
      // would be inventing a relationship nobody asked for.
      expect(
          bandsIn(ElementTrack(const [
            Keyframe(frame: 0, dx: 10),
            Keyframe(frame: 5, dx: 20),
            Keyframe(frame: 9, dx: 30),
          ])),
          isEmpty);
      expect(bandsIn(null), isEmpty);
    });

    test("dragging the band moves both ends and keeps its length", () {
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.grow);
      var before = bandsIn(chartIn(controller).track!).single;

      controller.shiftKeyframes("c", [before.from, before.to], -6);
      var after = bandsIn(chartIn(controller).track!).single;

      expect(after.from, before.from - 6);
      expect(after.to, before.to - 6);
      expect(after.length, before.length);
    });

    test("and it will not push either end off the timeline", () {
      // Refused rather than squashed: an animation that quietly lost its
      // length at the end of the strip is one nobody would notice until they
      // played it.
      var controller = withChart();
      addTearDown(controller.dispose);
      controller.applyChartExit(chartIn(controller), ChartAnimationPreset.grow);
      var before = bandsIn(chartIn(controller).track!).single;

      controller.shiftKeyframes("c", [before.from, before.to], 10);
      var after = bandsIn(chartIn(controller).track!).single;
      expect([after.from, after.to], [before.from, before.to]);
    });

    test("it draws with the exit preset, in reverse", () async {
      // Two presets, one chart: it must fade on the way out even though it
      // grew on the way in, and it must be going away rather than arriving.
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        showXLabels: false,
        showYLabels: false,
        showLegend: false,
        data: ChartData(categories: const [
          "x"
        ], series: [
          ChartSeries(
              name: "A", color: const Color(0xFF00AAFF), values: const [10]),
        ]),
        animation: const ChartAnimation(
          preset: ChartAnimationPreset.grow,
          exit: ChartAnimationPreset.fadeIn,
          ease: ChartEase.linear,
        ),
      );

      Future<int> inkAt({double reveal = 1, double close = 0}) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder);
        paintChart(canvas, const Rect.fromLTWH(0, 0, 400, 300), chart,
            reveal: reveal, close: close);
        var image = await recorder.endRecording().toImage(400, 300);
        var bytes = (await image.toByteData())!;
        var n = 0;
        for (var i = 0; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint32(i) == 0x00AAFFFF) n++;
        }
        return n;
      }

      var whole = await inkAt();
      expect(whole, greaterThan(100));

      // Half way out it is fading, so the bar is still its full size and no
      // longer its full colour: fewer pixels are exactly the series colour.
      var half = await inkAt(close: 0.5);
      expect(half, lessThan(whole));

      // And at the end of the closing band there is nothing left.
      expect(await inkAt(close: 1), 0);
    });

    test("which end it empties from is a separate choice", () {
      // "Grow, reversed" is the entrance run backwards, so the last bar sinks
      // first and the chart unwinds. The same shrinking front to back -- the
      // chart emptying from the left -- is a different animation and cannot
      // be had by choosing a different preset.
      const unwinds = ChartAnimation(
        exit: ChartAnimationPreset.grow,
        gap: 1,
        ease: ChartEase.linear,
      );
      const empties = ChartAnimation(
        exit: ChartAnimationPreset.grow,
        exitInOrder: true,
        gap: 1,
        ease: ChartEase.linear,
      );

      // A tenth of the way out, with ten bars.
      var reveal = 0.9;
      var first = unwinds.leaving.progressAt(reveal, 0, 10);
      var last = unwinds.leaving.progressAt(reveal, 9, 10);
      expect(last, lessThan(first),
          reason: "unwinding: the last bar is already going and the first has "
              "not started");

      first = empties.leaving.progressAt(reveal, 0, 10);
      last = empties.leaving.progressAt(reveal, 9, 10);
      expect(first, lessThan(last),
          reason: "emptying: the first bar goes first");
    });

    test("and it is only about the way out", () {
      // The entrance is unaffected: the same object is asked how far along an
      // item is on the way in, and the flip belongs to the copy the painter
      // draws the exit with.
      const animation = ChartAnimation(
        preset: ChartAnimationPreset.grow,
        exit: ChartAnimationPreset.grow,
        exitInOrder: true,
        gap: 1,
        ease: ChartEase.linear,
      );
      expect(animation.flipOrder, isFalse);
      expect(animation.progressAt(0.1, 0, 10),
          greaterThan(animation.progressAt(0.1, 9, 10)),
          reason: "arriving, the first bar is still the first to arrive");
    });

    test("the way out survives being saved and read back", () {
      var animation = const ChartAnimation(
          preset: ChartAnimationPreset.grow, exit: ChartAnimationPreset.wipe);
      var back = ChartAnimation.fromJson(animation.toJson());
      expect(back.exit, ChartAnimationPreset.wipe);
      expect(
          ChartAnimation.fromJson(const ChartAnimation(
                      exit: ChartAnimationPreset.grow, exitInOrder: true)
                  .toJson())
              .exitInOrder,
          isTrue);
      expect(back.flipOrder, isFalse,
          reason: "which end it runs from is a fact about the direction it is "
              "being played, not something saved with the chart");
      expect(back.preset, ChartAnimationPreset.grow);
      expect(back.leaving.preset, ChartAnimationPreset.wipe,
          reason: "which is what the painter draws with on the way out");
      // An old document, saved before there was a way out, has none.
      expect(ChartAnimation.fromJson(const {"preset": "grow"}).closes, isFalse);
    });
  });
}
