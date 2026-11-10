import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_pose.dart'
    show kickSeconds;
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_game_strike_test.dart is a player punching and kicking (Ken,
// 2026-11-10: "a character can punch and kick"): J punches, K kicks; what
// is in reach in front of the player and can be hit takes a hit, and is
// defeated -- gone, its effect done -- once it has taken all it takes.

int key(LogicalKeyboardKey k) => k.keyId;

ShapeElement box(String id, double x, double y, double w, double h,
        {PlaySpec play = const PlaySpec(), ElementMotion? motion}) =>
    ShapeElement(ElementBase(
        id: id,
        x: x,
        y: y,
        width: w,
        height: h,
        play: play,
        motion: motion ?? ElementMotion.none));

const foes = GameCount("foes", "Foes beaten");

/// On a canvas 1920 wide, the player stands on the floor (its foot, 1080
/// down) at 100 to
/// 140 across, facing right.
CanvasDocument field(List<CanvasElement> more) =>
    const CanvasDocument(size: CanvasSize(width: 1920))
        .copyWith(game: true, counts: const [
      foes
    ], elements: [
      box("hero", 100, 1000, 40, 80,
          play: const PlaySpec(as: PlayAs.platformer)),
      ...more,
    ]);

/// slime is something to beat at [x] on the floor, taking [hits].
ShapeElement slime(String id, double x, {int hits = 2}) =>
    box(id, x, 1050, 30, 30,
        play: PlaySpec(
            as: PlayAs.hazard,
            hits: hits,
            hitSound: "thud",
            defeated: const GameEffect(does: GameDoes.add, count: "foes")));

/// strike presses [k] once, as a tap: down for a step, up for the time the
/// strike takes, so the next is a new one.
void strike(GameRun run, CanvasDocument doc, LogicalKeyboardKey k) {
  run.input.keys.add(key(k));
  run.step(doc, 0, 1 / 60);
  run.input.keys.remove(key(k));
  for (var i = 0; i < (kickSeconds * 60).ceil() + 1; i++) {
    run.step(doc, 0, 1 / 60);
  }
}

GameRun settled(CanvasDocument doc) {
  var run = GameRun();
  for (var i = 0; i < 30; i++) {
    run.step(doc, 0, 1 / 60);
  }
  return run;
}

void main() {
  test("a kick hits what is in front; enough hits beat it", () {
    var doc = field([slime("slime", 150)]);
    var run = settled(doc);
    expect(run.bodies["hero"]!.onGround, isTrue);
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.hitsTaken["slime"], 1);
    expect(run.events.where((e) => e.hit == "slime"), hasLength(1));
    expect(run.events.where((e) => e.sound == "thud"), hasLength(1));
    expect(run.gone, isNot(contains("slime")), reason: "it takes two");
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, contains("slime"));
    expect(run.countOf(doc, "foes"), 1, reason: "its defeat is counted");
    expect(run.view(doc).elementById("slime"), isNull, reason: "gone");
  });

  test("a punch reaches less far than a kick", () {
    // 40 past the player's front: beyond a punch (36), within a kick (56).
    var doc = field([slime("slime", 180, hits: 1)]);
    var run = settled(doc);
    strike(run, doc, LogicalKeyboardKey.keyJ);
    expect(run.hitsTaken["slime"], isNull);
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, contains("slime"));
  });

  test("it strikes the way it faces", () {
    var doc = field([slime("behind", 60, hits: 1)]);
    var run = settled(doc);
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, isEmpty, reason: "facing right, it is behind");
    // A step left turns it round.
    run.input.keys.add(key(LogicalKeyboardKey.arrowLeft));
    run.step(doc, 0, 1 / 60);
    run.input.keys.remove(key(LogicalKeyboardKey.arrowLeft));
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, contains("behind"));
  });

  test("one strike while another is thrown is not a second", () {
    var doc = field([slime("slime", 150, hits: 3)]);
    var run = settled(doc);
    run.input.keys.add(key(LogicalKeyboardKey.keyK));
    run.step(doc, 0, 1 / 60);
    run.input.keys
      ..remove(key(LogicalKeyboardKey.keyK))
      ..add(key(LogicalKeyboardKey.keyJ));
    run.step(doc, 0, 1 / 60);
    expect(run.hitsTaken["slime"], 1);
  });

  test("a crate kicked open is gone, and no longer in the way", () {
    var doc = field([
      box("crate", 145, 1020, 60, 60,
          play: const PlaySpec(as: PlayAs.solid, hits: 1)),
    ]);
    var run = settled(doc);
    // Walking right, it stops at the crate.
    run.input.keys.add(key(LogicalKeyboardKey.arrowRight));
    for (var i = 0; i < 20; i++) {
      run.step(doc, 0, 1 / 60);
    }
    run.input.keys.remove(key(LogicalKeyboardKey.arrowRight));
    var stopped = run.bodies["hero"]!.at.dx;
    expect(stopped, lessThan(10), reason: "the crate is solid");
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, contains("crate"));
    run.input.keys.add(key(LogicalKeyboardKey.arrowRight));
    for (var i = 0; i < 20; i++) {
      run.step(doc, 0, 1 / 60);
    }
    expect(run.bodies["hero"]!.at.dx, greaterThan(stopped + 50),
        reason: "through where it was");
  });

  test("one copy of an element reused is hit alone", () {
    var bats = box("bats", 150, 1050, 30, 30,
        play: const PlaySpec(as: PlayAs.hazard, hits: 1),
        motion: ElementMotion(
            instances: const InstanceSet(items: [
          ElementInstance("a"),
          ElementInstance("b", dx: 600),
        ])));
    var doc = field([bats]);
    var run = settled(doc);
    strike(run, doc, LogicalKeyboardKey.keyK);
    expect(run.gone, {instanceKey("bats", "a")});
    expect(run.events.where((e) => e.hit == instanceKey("bats", "a")),
        hasLength(1));
  });

  test("a clip that starts on a hit starts on that one", () {
    var fall = MotionClip.ofKind("fall", MotionKind.leave, name: "Fall")
        .copyWith(
            length: 0.5, triggers: const [ClipTrigger(ClipTriggerKind.hit)]);
    var doc = field([
      box("slime", 150, 1050, 30, 30,
          play: const PlaySpec(as: PlayAs.hazard, hits: 1),
          motion: ElementMotion.none.withClip(fall)),
      box("other", 600, 1050, 30, 30,
          play: const PlaySpec(as: PlayAs.hazard, hits: 1),
          motion: ElementMotion.none.withClip(fall)),
    ]);
    var live = MotionPlayer();
    live.fire(doc, 0, ClipTriggerKind.hit, "slime", 0);
    expect(live.isPlaying("slime"), isTrue);
    expect(live.isPlaying("other"), isFalse);
  });

  test("what it takes to beat it is kept with it", () {
    const spec = PlaySpec(
        as: PlayAs.hazard,
        hits: 3,
        hitSound: "thud",
        defeated: GameEffect(does: GameDoes.add, count: "foes"));
    var back = PlaySpec.fromJson(spec.toJson());
    expect(back, spec);
    expect(back.hittable, isTrue);
    expect(const PlaySpec().hittable, isFalse);
    expect(PlaySpec.fromJson(const PlaySpec().toJson()).hits, 0);
  });

  test("the controls have a punch and a kick", () {
    expect(
        [for (var a in defaultControls) a.id], containsAll(["punch", "kick"]));
  });

  test("a 3D player throws its punch, then walks on", () {
    var hero = Character3dElement(
        ElementBase(
            id: "hero",
            x: 100,
            y: 780,
            width: 100,
            height: 300,
            play: const PlaySpec(as: PlayAs.platformer)),
        design: CharacterDesign(
            id: "d", name: "Vivi", body: "Vivi", updated: DateTime(2026)),
        performance: const CharacterPerformance());
    var doc = const CanvasDocument(size: CanvasSize(width: 1920))
        .copyWith(game: true, elements: [hero]);
    var run = settled(doc);
    run.input.keys.add(key(LogicalKeyboardKey.keyJ));
    run.step(doc, 0, 1 / 60);
    run.input.keys.remove(key(LogicalKeyboardKey.keyJ));
    run.step(doc, 0, 1 / 60);
    Character3dElement seen() =>
        run.view(doc).elementById("hero") as Character3dElement;
    expect(seen().performance.clips.single.kind, "Punch");
    for (var i = 0; i < 40; i++) {
      run.step(doc, 0, 1 / 60);
    }
    expect(seen().performance.clips, isEmpty, reason: "thrown, it stands");
  });
}
