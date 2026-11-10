import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe, TimelineAction, TimelineActionKind;
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// A game whose things move by their slots' clips: patrols, platforms and a
// coin's pop launched as the scene starts, on a touch, on a count -- and
// solid, touched and ridden where the clips have them. Found rebuilding Sky
// Isles with every animation in slots.

ShapeElement box(String id, double x, double y, double w, double h,
    {PlaySpec play = const PlaySpec(), List<MotionClip> clips = const []}) {
  var m = ElementMotion.none;
  for (var (i, c) in clips.indexed) {
    m = m.withClip(c).inSlot(i, c.id);
  }
  return ShapeElement(ElementBase(
      id: id, x: x, y: y, width: w, height: h, play: play, motion: m));
}

/// patrol goes [by] along x and back over [seconds], round and round, from
/// the scene's start.
MotionClip patrol(String id, double by, double seconds) =>
    MotionClip.ofKind(id, MotionKind.loop, name: "Patrol").copyWith(
      length: seconds,
      loop: true,
      keys: {
        MotionProp.x: [
          const MotionKey(0, MotionNumber(0)),
          MotionKey(seconds / 2, MotionNumber(by)),
          MotionKey(seconds, const MotionNumber(0)),
        ],
      },
      triggers: const [ClipTrigger(ClipTriggerKind.sceneStarts)],
    );

const hero = PlaySpec(as: PlayAs.platformer);
const coins = GameCount("coins", "Coins");
const lives = GameCount("lives", "Lives", start: 3);
const hurts = PlaySpec(
    as: PlayAs.hazard,
    touched: GameEffect(does: GameDoes.take, count: "lives"));
const pickup = PlaySpec(
    as: PlayAs.pickup, touched: GameEffect(does: GameDoes.add, count: "coins"));

/// played runs [doc]'s slots as a scene starting, and the game against
/// them, for [seconds].
(GameRun, MotionPlayer) played(CanvasDocument doc, double seconds,
    {Set<int> keys = const {}}) {
  var run = GameRun();
  var live = MotionPlayer();
  live.fire(doc, 0, ClipTriggerKind.sceneStarts, "", 0);
  run.input.keys.addAll(keys);
  for (var t = 1 / 60; t <= seconds; t += 1 / 60) {
    live.step(doc, 0, t);
    run.step(doc, 0, 1 / 60, live: live);
  }
  return (run, live);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test("a hazard patrolling from its slot hurts where its clip has it", () {
    // The player stands 200 along; the slime starts at 0 and walks 300 out.
    var doc = const CanvasDocument().copyWith(game: true, counts: const [
      lives
    ], elements: [
      box("hero", 300, 640, 40, 80, play: hero),
      box("slime", 80, 690, 40, 30,
          play: hurts, clips: [patrol("walk", 300, 4)]),
    ]);
    var (run, _) = played(doc, 0.5);
    expect(run.countOf(doc, "lives"), 3, reason: "not there yet");
    (run, _) = played(doc, 2);
    expect(run.countOf(doc, "lives"), 2,
        reason: "reached where it stands, by its live clip");
  });

  test("a platform moved by a clip carries what stands on it", () {
    var doc = const CanvasDocument().copyWith(game: true, elements: [
      box("platform", 200, 500, 200, 20,
          play: const PlaySpec(as: PlayAs.solid),
          clips: [patrol("glide", 300, 6)]),
      box("hero", 280, 400, 40, 80, play: hero),
    ]);
    var (run, live) = played(doc, 0.4);
    var body = run.bodies["hero"]!;
    expect(body.onGround, isTrue, reason: "landed on it");
    var x = body.at.dx;
    var platform =
        doc.elementById("platform")!.movedBoundsAt(0, doc, live: live).left;
    // On, a second more.
    for (var t = 0.4 + 1 / 60; t <= 1.4; t += 1 / 60) {
      live.step(doc, 0, t);
      run.step(doc, 0, 1 / 60, live: live);
    }
    var moved =
        doc.elementById("platform")!.movedBoundsAt(0, doc, live: live).left -
            platform;
    expect(moved, greaterThan(20));
    expect(body.at.dx - x, closeTo(moved, 2), reason: "carried along");
    expect(body.onGround, isTrue);
  });

  test("a clip launched over itself starts from where it started", () {
    var bump = presetNamed("Bump")!.clip("bump");
    var doc = const CanvasDocument().copyWith(elements: [
      box("icon", 0, 0, 20, 20, clips: [bump])
    ]);
    var p = MotionPlayer();
    p.launch(doc, 0, "icon", "bump", 0);
    p.step(doc, 0, 0.1);
    // Again, part way up.
    p.launch(doc, 0, "icon", "bump", 0.1);
    p.step(doc, 0, 0.12);
    var peak = 0.0;
    for (var t = 0.12; t < 1; t += 0.01) {
      p.step(doc, 0, t);
      var s = poseWithMotion(doc.elementById("icon")!, 0, doc, live: p).scale;
      if (s > peak) peak = s;
    }
    expect(peak, lessThanOrEqualTo(1.31), reason: "no bigger than one bump");
    expect(poseWithMotion(doc.elementById("icon")!, 0, doc, live: p).scale, 1,
        reason: "and back where it was");
  });

  test("a live clip seen a moment earlier, for the way it is going", () {
    // A sprite turned to its travel looks back along its pose: played live,
    // a frame back is the clip's clock moved back, not the timeline's.
    var doc = const CanvasDocument().copyWith(elements: [
      box("slime", 0, 0, 40, 30, clips: [patrol("walk", 200, 4)]),
    ]);
    var p = MotionPlayer();
    p.fire(doc, 0, ClipTriggerKind.sceneStarts, "", 0);
    var e = doc.elementById("slime")!;
    double xAt(double clock, [double back = 0]) {
      p.step(doc, 0, clock);
      return poseWithMotion(e, 0, doc, live: liveShifted(p, -back)).dx;
    }

    expect(xAt(1) - xAt(1, 0.1), greaterThan(0), reason: "going right");
    expect(xAt(3) - xAt(3, 0.1), lessThan(0), reason: "coming back");
  });

  test("a touch starts the touched element's clips, and no other's", () {
    var pop = presetNamed("Collect")!
        .clip("pop")
        .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.touched)]);
    var doc = const CanvasDocument().copyWith(elements: [
      box("a", 0, 0, 10, 10, clips: [pop]),
      box("b", 0, 0, 10, 10, clips: [pop]),
    ]);
    var p = MotionPlayer();
    p.fire(doc, 0, ClipTriggerKind.touched, "a", 0);
    p.step(doc, 0, 0.01);
    expect(p.isPlaying("a"), isTrue);
    expect(p.isPlaying("b"), isFalse);
  });

  group("through the controller", () {
    late CanvasController c;
    var t = 0;
    void step(double seconds) {
      for (var i = 0; i < (seconds * 60).round(); i++) {
        t += 16667;
        c.stepGame(1 / 60);
      }
    }

    setUp(() => t = 0);
    tearDown(() {
      c.gaming = false;
      c.dispose();
    });

    CanvasController game(CanvasDocument doc) {
      c = CanvasController(doc, audioEngine: FakeEngine({}));
      c.gameClockForTest = () => t;
      return c;
    }

    test("the scene's clips start with the game, and on its keys", () {
      var spin = presetNamed("Spin once")!.clip("spin").copyWith(
          triggers: const [ClipTrigger(ClipTriggerKind.key, target: "Space")]);
      game(const CanvasDocument().copyWith(game: true, elements: [
        box("hero", 100, 600, 40, 80, play: hero),
        box("slime", 400, 690, 40, 30, clips: [patrol("walk", 200, 4)]),
        box("sign", 600, 100, 40, 40, clips: [spin]),
      ]));
      c.gaming = true;
      step(0.5);
      expect(c.motionPlayer.isPlaying("slime"), isTrue);
      var a = c.document
          .elementById("slime")!
          .movedBoundsAt(0, c.document, live: c.liveMotion)
          .left;
      step(0.5);
      var b = c.document
          .elementById("slime")!
          .movedBoundsAt(0, c.document, live: c.liveMotion)
          .left;
      expect(b, greaterThan(a + 10), reason: "stepped by the game");
      expect(c.motionPlayer.isPlaying("sign"), isFalse);
      c.gameKey(const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.space,
          logicalKey: LogicalKeyboardKey.space,
          timeStamp: Duration.zero));
      step(1 / 60);
      expect(c.motionPlayer.isPlaying("sign"), isTrue);
      c.gaming = false;
      expect(c.motionPlayer.offTimeline, isFalse,
          reason: "stopped, back on the timeline");
    });

    test("a coin collected pops before it goes, and the HUD's count bumps", () {
      var collect = presetNamed("Collect")!
          .clip("pop", layer: 1)
          .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.touched)]);
      var float = presetNamed("Float")!
          .clip("float")
          .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.sceneStarts)]);
      var bump = presetNamed("Bump")!.clip("bump").copyWith(triggers: const [
        ClipTrigger(ClipTriggerKind.count, target: "coins")
      ]);
      game(CanvasDocument(
        game: true,
        counts: const [coins],
        masterOn: true,
        masterOver: true,
        master: CanvasScene(id: "hud", elements: [
          box("hud-coin", 10, 10, 30, 30, clips: [bump]),
        ]),
        scenes: [
          CanvasScene(id: "one", elements: [
            box("hero", 100, 640, 40, 80, play: hero),
            box("coin", 110, 680, 30, 30,
                play: pickup, clips: [float, collect]),
          ]),
        ],
      ));
      c.gaming = true;
      step(0.1);
      expect(c.game!.countOf(c.document, "coins"), 1);
      expect(c.gameView!.elementById("coin"), isNotNull,
          reason: "seen while it pops, its float notwithstanding");
      expect(c.motionPlayer.isPlaying("hud-coin"), isTrue,
          reason: "a count's trigger, on the master's HUD");
      step(1.5);
      expect(c.gameView!.elementById("coin"), isNull, reason: "then gone");
    });

    // Sky Isles v7 (2026-11-08): a game's next scene arrives through the
    // transition set after the one it leaves, as the timeline's does.
    test("the next scene arrives through its transition", () {
      game(CanvasDocument(game: true, frameRate: 24, scenes: [
        CanvasScene(
            id: "one",
            transition: const SceneTransition(
                kind: SceneTransitionKind.fade, frames: 24),
            elements: [
              box("hero", 100, 640, 40, 80, play: hero),
              box("flag", 110, 680, 30, 30,
                  play: const PlaySpec(
                      as: PlayAs.pickup,
                      touched: GameEffect(does: GameDoes.next))),
            ]),
        CanvasScene(id: "two", elements: [
          box("hero2", 100, 640, 40, 80, play: hero),
        ]),
      ]));
      c.gaming = true;
      step(0.1);
      expect(c.document.at, 1, reason: "on to the next");
      var change = c.gameChange;
      expect(change, isNotNull, reason: "giving way, not cut");
      var (left, _, over, t, _) = change!;
      expect(left.at, 0, reason: "the scene it left, as it was seen");
      expect(left.elementById("hero"), isNotNull, reason: "its own things");
      expect(over.kind, SceneTransitionKind.fade);
      expect(t, inInclusiveRange(0.0, 0.5));
      step(1.1);
      expect(c.gameChange, isNull, reason: "a second, and it has arrived");
    });

    // Sky Isles v7 (2026-11-08): a level's coins as one element, reused --
    // the one touched pops alone and goes; the rest float on.
    test("one of a coin's copies taken pops alone, the others stay", () {
      var collect = presetNamed("Collect")!
          .clip("pop", layer: 1)
          .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.touched)]);
      var float = presetNamed("Float")!
          .clip("float")
          .copyWith(triggers: const [ClipTrigger(ClipTriggerKind.sceneStarts)]);
      CanvasElement coin =
          box("coin", 110, 680, 30, 30, play: pickup, clips: [float, collect]);
      coin = coin.withBase(
          motion: coin.base.motion.copyWith(
              instances: const InstanceSet(items: [
        ElementInstance("c0"),
        ElementInstance("c1", dx: 300),
        ElementInstance("c2", dx: 600),
      ])));
      game(CanvasDocument(
        game: true,
        counts: const [coins],
        scenes: [
          CanvasScene(id: "one", elements: [
            box("hero", 100, 640, 40, 80, play: hero),
            coin,
          ]),
        ],
      ));
      c.gaming = true;
      step(0.1);
      expect(c.game!.countOf(c.document, "coins"), 1, reason: "one taken");
      expect(c.motionPlayer.isPlaying("coin#c0"), isTrue,
          reason: "its pop, its own");
      expect(c.motionPlayer.isPlaying("coin", only: {"pop"}), isFalse,
          reason: "not every copy's");
      var seen = c.gameView!.elementById("coin")!;
      expect(seen.base.motion.instances!.count, 3,
          reason: "the one taken seen while it pops");
      step(0.2);
      var e = c.document.elementById("coin")!;
      Keyframe pose(int i) => poseWithMotion(e, c.frame, c.document,
          live: c.liveMotion, instance: i);
      expect((pose(0).scale - pose(1).scale).abs(), greaterThan(0.01),
          reason: "the taken one popping, the next not");
      expect(pose(1).dy, isNot(0), reason: "the others float on");
      step(1.5);
      var left = c.gameView!.elementById("coin")!.base.motion.instances!;
      expect([for (var i in left.items) i.id], ["c1", "c2"]);
    });

    // Ken, playing Ember Vale 2: "the Sunken Ruins level doesn't play".
    // The title's stop held the timeline, and going on to another scene in
    // a game never played it again: every level stood at its first frame.
    test("a scene gone on to in a game plays its timeline", () {
      game(CanvasDocument(game: true, scenes: [
        CanvasScene(id: "one", frames: 60, actions: const [
          TimelineAction(frame: 10, kind: TimelineActionKind.stop),
        ], elements: [
          box("hero", 100, 600, 40, 80, play: hero),
        ]),
        CanvasScene(id: "two", frames: 60, elements: [
          box("hero", 100, 600, 40, 80, play: hero),
        ]),
      ]));
      c.gaming = true;
      for (var i = 0; i < 20; i++) {
        step(1 / 24);
        if (c.playing) c.tickForTest();
      }
      expect((c.frame, c.playing), (10, false), reason: "held at the stop");
      c.runButtonAction(const ButtonAction(
          kind: ButtonActionKind.goToScene, elementId: "two"));
      expect(c.document.scene.id, "two");
      expect(c.playing, isTrue, reason: "the next scene plays");
      for (var i = 0; i < 5; i++) {
        step(1 / 24);
        if (c.playing) c.tickForTest();
      }
      expect(c.frame, greaterThan(0), reason: "from its start, on");
    });

    // A wind platform on an Oscillate: in a game it goes by the game's
    // time, not the timeline's frame -- held at a stop, or past its end,
    // the level plays on, and the platform with it (Ember Vale's froze).
    test("what moves for ever goes on while the timeline holds", () {
      var wind =
          box("wind", 400, 700, 128, 32, play: const PlaySpec(as: PlayAs.solid))
              .withBase(
                  motion: ElementMotion.none.copyWith(devices: const [
        MotionDevice(MotionDeviceKind.oscillate,
            values: {"amount": 100, "rate": 0.5, "moves": 1}),
      ]));
      game(const CanvasDocument().copyWith(game: true, elements: [
        box("hero", 100, 600, 40, 80, play: hero),
        wind,
      ]));
      c.gaming = true;
      double at() => c.document
          .elementById("wind")!
          .movedBoundsAt(c.frame, c.document, live: c.liveMotion)
          .left;
      // The timeline does not move here (nothing ticks it): held.
      step(0.5);
      var a = at();
      step(0.5);
      var b = at();
      expect(c.frame, 0, reason: "the timeline held");
      expect(c.liveMotion?.running, closeTo(1, 0.05));
      expect((a - b).abs(), greaterThan(20), reason: "the platform moved on");
      expect(a, closeTo(400 + 100, 1), reason: "a quarter of its swing");
      expect(b, closeTo(400, 1), reason: "back through the middle");
      c.gaming = false;
      expect(c.liveMotion?.running, isNull);
      expect(at(), closeTo(400, 1e-6), reason: "off the game: frame 0's");
      c.gaming = true; // for tearDown
    });
  });

  // Ken: "on the title scene The Title dropped in and the title sub faded up
  // but whilst this was happening the channels for these elements didn't
  // show as playing". A clip placed on the timeline lights its slot while
  // the playhead is in it, as a launched one does.
  test("a clip placed on the timeline shows playing in its slot", () {
    var drop = presetNamed("Drop in")!.clip("drop");
    var m = ElementMotion.none
        .withClip(drop)
        .inSlot(0, "drop")
        .withPlacement(const ClipPlacement(id: "p", clip: "drop", start: 0.5));
    var c = CanvasController(
        const CanvasDocument(frameRate: 24, frames: 96).copyWith(elements: [
          ShapeElement(ElementBase(
              id: "title", x: 0, y: 0, width: 100, height: 40, motion: m)),
        ]),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(c.motionSlotState("title", 0), MotionSlotState.stopped);
    c.play();
    for (var i = 0; i < 6; i++) {
      c.tickForTest();
    }
    expect(c.motionSlotState("title", 0), MotionSlotState.stopped,
        reason: "not yet: placed at half a second");
    for (var i = 0; i < 12; i++) {
      c.tickForTest();
    }
    expect(c.motionSlotState("title", 0), MotionSlotState.playing,
        reason: "the playhead in it");
    for (var i = 0; i < 60; i++) {
      c.tickForTest();
    }
    expect(c.motionSlotState("title", 0), MotionSlotState.stopped,
        reason: "played out");
  });
}
