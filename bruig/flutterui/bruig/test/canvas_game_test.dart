import 'dart:ui' as ui;

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/game_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:provider/provider.dart';

// canvas_game_test.dart is a canvas played as a game: elements walking,
// falling, jumping and landing on what is solid; the view following; a
// sprite walking as it moves; and the keys and controllers that drive it.

ShapeElement box(String id, double x, double y, double w, double h,
        {PlayAs as = PlayAs.none, PlaySpec? play}) =>
    ShapeElement(ElementBase(
        id: id,
        x: x,
        y: y,
        width: w,
        height: h,
        play: play ?? PlaySpec(as: as)));

/// A canvas 1280 wide and 720 high, as a new one is.
const page = CanvasDocument();

int key(LogicalKeyboardKey k) => k.keyId;

void main() {
  // The panel's sections, open: these test what the controls do, not where
  // they are folded away.
  setUp(() => CanvasSection.openAll = true);
  tearDown(() => CanvasSection.openAll = false);

  group("kept", () {
    test("an element's play, and the document's controls", () {
      var e = box("p", 0, 0, 10, 10,
          play: const PlaySpec(
              as: PlayAs.platformer, speed: 200, jump: 90, follow: false));
      var back = ElementBase.fromJson(e.base.toJson(), "Shape");
      expect(back.play, e.base.play);
      var doc = page.copyWith(controls: [
        const ControlAction("jump", "Jump", keys: [32], pad: [PadInput.b]),
      ]);
      var again = CanvasDocument.fromJson(doc.toJson());
      expect(again.controlsNow.single.pad, [PadInput.b]);
      expect(CanvasDocument.fromJson(page.copyWith(game: true).toJson()).game,
          isTrue,
          reason: "made a game, it stays one");
      expect(CanvasDocument.fromJson(page.toJson()).game, isFalse);
      expect(page.controlsNow.map((a) => a.id),
          ["left", "right", "up", "down", "jump", "act"]);
      expect(CanvasDocument.fromJson(page.toJson()).controls, isNull,
          reason: "the usual controls are not written down");
    });
  });

  group("a platformer", () {
    CanvasDocument world(List<CanvasElement> more) => page.copyWith(elements: [
          box("hero", 100, 100, 40, 60, as: PlayAs.platformer),
          ...more,
        ]);

    void run(GameRun g, CanvasDocument doc, double seconds,
        {Set<int> keys = const {}}) {
      g.input.keys
        ..clear()
        ..addAll(keys);
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.step(doc, 0, 1 / 60);
      }
    }

    test("falls to the canvas's bottom edge, and stands there", () {
      var g = GameRun();
      var doc = world([]);
      run(g, doc, 2);
      var b = g.bodies["hero"]!;
      expect(160 + b.at.dy, closeTo(720, 0.01), reason: "its feet on the edge");
      expect(b.onGround, isTrue);
    });

    test("walks at its speed, and faces the way it goes", () {
      var g = GameRun();
      var doc = world([]);
      run(g, doc, 1);
      var x = g.bodies["hero"]!.at.dx;
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.arrowLeft)});
      expect(g.bodies["hero"]!.at.dx - x, closeTo(-160, 6));
      expect(g.bodies["hero"]!.facing, -1);
    });

    test("jumps as high as it is set to, once, from the ground", () {
      var g = GameRun();
      var doc = world([]);
      run(g, doc, 1);
      var ground = g.bodies["hero"]!.at.dy;
      var top = ground;
      g.input.keys.add(key(LogicalKeyboardKey.space));
      for (var i = 0; i < 90; i++) {
        g.step(doc, 0, 1 / 60);
        top = top < g.bodies["hero"]!.at.dy ? top : g.bodies["hero"]!.at.dy;
      }
      expect(ground - top, closeTo(180, 12));
      expect(g.bodies["hero"]!.onGround, isTrue,
          reason: "held, it does not jump again in the air");
    });

    test("lands on a platform, and a wall stops it", () {
      var g = GameRun();
      // A platform under it, and a wall to its right.
      var doc = world([
        box("ledge", 60, 400, 200, 20, as: PlayAs.solid),
        // To the floor: one that stops short is walked under.
        box("wall", 300, 200, 20, 520, as: PlayAs.solid),
      ]);
      run(g, doc, 1);
      expect(160 + g.bodies["hero"]!.at.dy, closeTo(400, 0.01));
      run(g, doc, 1, keys: {key(LogicalKeyboardKey.keyD)});
      expect(140 + g.bodies["hero"]!.at.dx, lessThanOrEqualTo(300.01),
          reason: "against the wall, not through it");
    });
    // A map's solid layer is the ground; a layer not marked solid is
    // scenery, walked through.
    group("on a tile map", () {
      // Cells 32 across at the canvas's corner: a floor along row 15 (y
      // 480), a wall at column 8 (x 256) from row 10 down, and the same
      // wall again on a layer that is only scenery, at column 5.
      TileMapElement map({bool solid = true}) => TileMapElement(
            const ElementBase(id: "map", width: 1280, height: 720),
            layers: [
              TileLayer(name: "Scenery", cells: {
                for (var r = 10; r < 15; r++) cellKey(5, r): 1,
              }),
              TileLayer(name: "Ground", solid: solid, cells: {
                for (var c = 0; c < 20; c++) cellKey(c, 15): 1,
                for (var r = 10; r < 15; r++) cellKey(8, r): 1,
              }),
            ],
          );

      test("stands on the solid tiles, and they stop it walking", () {
        var g = GameRun();
        var doc = world([map()]);
        run(g, doc, 1);
        expect(160 + g.bodies["hero"]!.at.dy, closeTo(480, 0.01),
            reason: "on the floor of tiles, not the canvas's edge");
        expect(g.bodies["hero"]!.onGround, isTrue);
        run(g, doc, 2, keys: {key(LogicalKeyboardKey.arrowRight)});
        expect(140 + g.bodies["hero"]!.at.dx, closeTo(256, 0.01),
            reason: "through the scenery at column five, against the wall");
      });

      test("a layer not marked solid is walked through", () {
        var g = GameRun();
        run(g, world([map(solid: false)]), 1);
        expect(160 + g.bodies["hero"]!.at.dy, closeTo(720, 0.01));
      });

      test("a run of tiles along a row is one box", () {
        var boxes = tileGround(map(), 0);
        expect(boxes.where((b) => b.top == 480).single,
            const Rect.fromLTWH(0, 480, 640, 32));
        expect(boxes.length, 1 + 5, reason: "the floor, and each wall cell");
      });

      test("kept with the map", () {
        var layer = map().layers.last;
        expect(TileLayer.fromJson(layer.toJson()).solid, isTrue);
        expect(TileLayer.fromJson(map(solid: false).layers.last.toJson()).solid,
            isFalse);
      });
    });
  });

  // A character played walks as it goes: its own motions for the timeline,
  // the game's while it plays.
  // Ken's Game rules board: pickups, hazards and the counts they change.
  group("game rules", () {
    const coins = GameCount("coins", "Coins");
    const lives = GameCount("lives", "Lives",
        start: 3, reach: 0, then: GameEffect(does: GameDoes.restart));
    ShapeElement coin(String id, double x) => box(id, x, 680, 20, 20,
        play: const PlaySpec(
            as: PlayAs.pickup,
            touched: GameEffect(does: GameDoes.add, count: "coins")));
    ShapeElement spikes(double x) => box("spikes", x, 680, 60, 40,
        play: const PlaySpec(
            as: PlayAs.hazard,
            touched: GameEffect(does: GameDoes.take, count: "lives")));
    CanvasDocument world(List<CanvasElement> more,
            {List<GameCount> counts = const [coins, lives]}) =>
        page.copyWith(game: true, counts: counts, elements: [
          box("hero", 100, 600, 40, 60, as: PlayAs.platformer),
          ...more,
        ]);
    void run(GameRun g, CanvasDocument doc, double seconds,
        {Set<int> keys = const {}}) {
      g.input.keys
        ..clear()
        ..addAll(keys);
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.step(doc, 0, 1 / 60);
      }
    }

    var right = {key(LogicalKeyboardKey.arrowRight)};

    test("kept: what touching does, and the game's counts", () {
      var doc = world([coin("c", 300), spikes(500)]);
      var back = CanvasDocument.fromJson(doc.toJson());
      expect(back.counts, [coins, lives]);
      expect(back.elementById("c")!.base.play, doc.elementById("c")!.base.play);
      expect(back.elementById("spikes")!.base.play.touched.does, GameDoes.take);
    });

    test("a coin is taken once, counted, and gone", () {
      var g = GameRun();
      var doc = world([coin("a", 300), coin("b", 400)]);
      run(g, doc, 0.2);
      expect(g.countOf(doc, "coins"), 0);
      run(g, doc, 1.2, keys: right);
      expect(g.countOf(doc, "coins"), 2);
      expect(g.gone, {"a", "b"});
      expect(g.view(doc).elementById("a"), isNull, reason: "taken, not drawn");
      // Walked back over where they were: nothing more.
      run(g, doc, 1.2, keys: {key(LogicalKeyboardKey.arrowLeft)});
      expect(g.countOf(doc, "coins"), 2);
    });

    test("one that stays is counted once a touch, not once a step", () {
      var g = GameRun();
      var stays = coin("s", 110).rebase(coin("s", 110)
          .base
          .copyWith(play: coin("s", 110).base.play.copyWith(stays: true)));
      var doc = world([stays]);
      run(g, doc, 1);
      expect(g.countOf(doc, "coins"), 1, reason: "stood on it a second");
      expect(g.view(doc).elementById("s"), isNotNull);
    });

    test(
        "spikes take a life and send the player back; none left, it starts again",
        () {
      var g = GameRun();
      var doc = world([coin("c", 300), spikes(500)]);
      run(g, doc, 0.2);
      run(g, doc, 1.5, keys: right);
      expect(g.countOf(doc, "coins"), 1);
      expect(g.countOf(doc, "lives"), 2);
      expect(g.bodies["hero"]!.at.dx, lessThan(200),
          reason: "back where it started, more or less");
      // On to the end of the lives: 3, 2, 1, and back to 3 -- the game
      // started again, every count and coin as it began.
      var seen = [g.countOf(doc, "lives")];
      var restarted = false;
      g.input.keys.addAll(right);
      for (var step = 0; step < 6 * 60 && !restarted; step++) {
        g.step(doc, 0, 1 / 60);
        var now = g.countOf(doc, "lives");
        if (now != seen.last) {
          seen.add(now);
          if (now == 3) {
            restarted = true;
            expect(g.countOf(doc, "coins"), 0);
            expect(g.gone, isEmpty);
            expect(g.bodies["hero"], isNull, reason: "back where it was put");
          }
        }
      }
      expect(seen, [2, 1, 3]);
    });

    test("a scene, or the end, asked of the canvas", () {
      var g = GameRun();
      var flag = box("flag", 300, 600, 20, 120,
          play: const PlaySpec(
              as: PlayAs.pickup,
              touched: GameEffect(does: GameDoes.scene, scene: "level2")));
      var doc = world([flag]);
      run(g, doc, 1.2, keys: right);
      expect(g.events.single.scene, "level2");
      g.events.clear();
      var end = box("end", 300, 600, 20, 120,
          play: const PlaySpec(
              as: PlayAs.hazard,
              sendsBack: false,
              touched: GameEffect(does: GameDoes.stop)));
      var g2 = GameRun();
      run(g2, world([end]), 1.2, keys: right);
      expect(g2.events.single.stop, isTrue);
    });

    test("the controller ends the game, and a Counter shows a count", () {
      var counter = CounterElement(const ElementBase(id: "n"),
          keyed: false, source: CounterSource.game, gameCount: "coins");
      var c = CanvasController(
          world([coin("a", 300), counter]).copyWith(frames: 240));
      addTearDown(c.dispose);
      expect(c.counterValue(counter), 0, reason: "its start, not playing");
      expect(
          CounterElement.fromJson(counter.props(), const ElementBase(id: "n"))
              .gameCount,
          "coins");
      c.gaming = true;
      c.game!.input.keys.addAll(right);
      for (var i = 0; i < 80; i++) {
        c.stepGame(1 / 60);
      }
      expect(c.counterValue(counter), 1);
      c.game!.events.add(const GameEvent(stop: true));
      c.stepGame(1 / 60);
      expect(c.gaming, isFalse);
    });
  });

  // Ken's board: things pressed by an action, and a stop that waits for one.
  group("pressed by an action", () {
    // A lever beside the path; a gate across it; the hero walking right.
    CanvasDocument world({double reach = 48}) =>
        page.copyWith(game: true, frames: 240, elements: [
          box("hero", 100, 600, 40, 60, as: PlayAs.platformer),
          box("lever", 340, 660, 20, 60,
              play: PlaySpec(
                  pressedBy: "act",
                  reach: reach,
                  press: const ButtonAction(
                      kind: ButtonActionKind.toggleElement,
                      elementId: "gate"))),
          box("gate", 400, 520, 30, 200, as: PlayAs.solid),
        ]);
    var right = {key(LogicalKeyboardKey.arrowRight)};
    var act = key(LogicalKeyboardKey.keyE);

    test("kept", () {
      var spec = world().elementById("lever")!.base.play;
      var back = ElementBase.fromJson(
          world().elementById("lever")!.base.toJson(), "Shape");
      expect(back.play, spec);
      expect(back.play.press.elementId, "gate");
    });

    test("only in reach; pressed, the gate opens for the game alone", () {
      var c = CanvasController(world());
      addTearDown(c.dispose);
      c.gaming = true;
      var g = c.game!;
      void run(double seconds, Set<int> keys) {
        g.input.keys
          ..clear()
          ..addAll(keys);
        for (var t = 0.0; t < seconds; t += 1 / 60) {
          c.stepGame(1 / 60);
        }
      }

      run(0.5, {});
      // Pressed from where it stands: too far from the lever.
      run(0.05, {act});
      run(0.05, {});
      expect(g.toggled, isEmpty);
      // Walked up to the gate: stopped by it, beside the lever.
      run(1.5, right);
      expect(140 + g.bodies["hero"]!.at.dx, closeTo(400, 0.5));
      run(0.05, {act});
      run(0.05, {});
      expect(g.toggled, {"gate"});
      expect(c.gameView!.elementById("gate")!.visible, isFalse);
      run(1, right);
      expect(140 + g.bodies["hero"]!.at.dx, greaterThan(430),
          reason: "through where the gate was");
      c.gaming = false;
      expect(c.document.elementById("gate")!.visible, isTrue,
          reason: "stopped, the gate is where it was put");
      expect(c.canUndo, isFalse, reason: "nothing written to the document");
    });

    test("a Button pressed by an action does its own", () {
      var c =
          CanvasController(page.copyWith(game: true, frames: 240, elements: [
        ButtonElement(
            ElementBase(id: "b", play: const PlaySpec(pressedBy: "jump")),
            action: const ButtonAction(
                kind: ButtonActionKind.goToFrame, frame: 120)),
      ]));
      addTearDown(c.dispose);
      c.gaming = true;
      c.game!.input.keys.add(key(LogicalKeyboardKey.space));
      c.stepGame(1 / 60);
      expect(c.frame, 120);
      c.gaming = false;
    });

    test("a stop that waits for Jump goes on when it is pressed", () {
      var c = CanvasController(page.copyWith(frames: 100, actions: [
        const TimelineAction(
            frame: 10, kind: TimelineActionKind.stop, waitsFor: "jump"),
      ]));
      addTearDown(c.dispose);
      expect(
          TimelineAction.fromJson(c.document.actions.single.toJson()).waitsFor,
          "jump");
      c.frame = 8;
      c.play();
      c.tickForTest();
      c.tickForTest();
      expect((c.frame, c.playing, c.waitingFor), (10, false, "jump"));
      // Another key: still waiting.
      expect(
          c.waitKey(const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyQ,
              logicalKey: LogicalKeyboardKey.keyQ,
              timeStamp: Duration.zero)),
          isFalse);
      expect(c.playing, isFalse);
      expect(
          c.waitKey(const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.space,
              logicalKey: LogicalKeyboardKey.space,
              timeStamp: Duration.zero)),
          isTrue);
      expect((c.playing, c.waitingFor), (true, null));
      c.pause();
    });
  });

  // Ken's board: up to four players, one keyboard shared and a controller
  // each, the camera keeping them all in view.
  group("players", () {
    CanvasDocument world() => page.copyWith(elements: [
          box("one", 100, 600, 40, 60, as: PlayAs.platformer),
          box("two", 600, 600, 40, 60,
              play: const PlaySpec(as: PlayAs.platformer, player: 2)),
        ]);
    void run(GameRun g, CanvasDocument doc, double seconds,
        {Set<int> keys = const {}}) {
      g.input.keys
        ..clear()
        ..addAll(keys);
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.step(doc, 0, 1 / 60);
      }
    }

    NormalizedGamepadEvent stick(String pad, double v) =>
        NormalizedGamepadEvent(
            gamepadId: pad,
            timestamp: 0,
            axis: GamepadAxis.leftStickX,
            value: v,
            rawEvent: GamepadEvent(
                gamepadId: pad,
                timestamp: 0,
                type: KeyType.analog,
                key: "x",
                value: v));

    test("kept: who plays it, and the other players' controls", () {
      var doc = world().copyWith(playerControls: {
        2: [
          const ControlAction("jump", "Jump", keys: [32])
        ],
      });
      var back = CanvasDocument.fromJson(doc.toJson());
      expect(back.elementById("two")!.base.play.player, 2);
      expect(back.controlsFor(2).single.keys, [32]);
      expect(back.controlsFor(3).first.keys, isEmpty,
          reason: "a controller's alone");
      expect(back.players, {1, 2});
    });

    test("one keyboard: the arrows the first's, WASD the second's", () {
      var g = GameRun();
      var doc = world();
      run(g, doc, 1);
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.keyD)});
      expect(g.bodies["one"]!.at.dx, 0,
          reason: "D is the second player's now, not the first's");
      expect(g.bodies["two"]!.at.dx, closeTo(160, 6));
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.arrowLeft)});
      expect(g.bodies["one"]!.at.dx, closeTo(-160, 6),
          reason: "the arrows the first's; the second stays put");
      expect(g.bodies["two"]!.at.dx, closeTo(160, 6));
      // F jumps the second.
      g.input.keys
        ..clear()
        ..add(key(LogicalKeyboardKey.keyF));
      g.step(doc, 0, 1 / 60);
      expect(g.bodies["two"]!.velocity.dy, lessThan(0));
      expect(g.bodies["one"]!.velocity.dy, greaterThanOrEqualTo(0));
    });

    test("a controller each, in the order they are first used", () {
      var g = GameRun();
      var doc = world();
      run(g, doc, 1);
      g.input.gamepad(stick("pad-a", -0.9));
      g.input.gamepad(stick("pad-b", 0.9));
      run(g, doc, 0.5);
      expect(g.bodies["one"]!.at.dx, lessThan(-50));
      expect(g.bodies["two"]!.at.dx, greaterThan(50));
    });

    test("the camera keeps them both in view: between them", () {
      var g = GameRun();
      var doc = world();
      run(g, doc, 0.1);
      // Their middles, 120 and 620: halfway, 370, less half the page.
      expect(g.camera.dx, 0, reason: "never left of the canvas");
      var far = page.copyWith(elements: [
        box("one", 1400, 600, 40, 60, as: PlayAs.platformer),
        box("two", 2000, 600, 40, 60,
            play: const PlaySpec(as: PlayAs.platformer, player: 2)),
      ]);
      var g2 = GameRun();
      run(g2, far, 0.1);
      expect(g2.camera.dx, closeTo((1420 + 2020) / 2 - 640, 0.5));
    });
  });

  // Ken: levels, start screens and menus -- a game going from scene to
  // scene.
  group("scenes", () {
    ShapeElement hero() => box("hero", 100, 600, 40, 60, as: PlayAs.platformer);
    ShapeElement flag(String id, GameEffect does) => box(id, 300, 600, 20, 120,
        play: PlaySpec(as: PlayAs.pickup, touched: does));
    CanvasDocument levels({String start = "title"}) => CanvasDocument(
            game: true,
            gameStart: start,
            frames: 240,
            counts: const [
              GameCount("lives", "Lives",
                  start: 1, reach: 0, then: GameEffect(does: GameDoes.restart)),
            ],
            scenes: [
              CanvasScene(id: "title", name: "Title", elements: [
                ButtonElement(
                    const ElementBase(
                        id: "start", play: PlaySpec(pressedBy: "jump")),
                    action: const ButtonAction(
                        kind: ButtonActionKind.goToScene, elementId: "one")),
              ]),
              CanvasScene(id: "one", name: "Level 1", elements: [
                hero(),
                flag("flag1", const GameEffect(does: GameDoes.next)),
              ]),
              CanvasScene(id: "two", name: "Level 2", elements: [
                hero(),
                box("spikes", 300, 680, 60, 40,
                    play: const PlaySpec(
                        as: PlayAs.hazard,
                        touched:
                            GameEffect(does: GameDoes.take, count: "lives"))),
              ]),
              CanvasScene(id: "three", name: "Level 3", elements: [
                hero(),
                flag("flag3", const GameEffect(does: GameDoes.next)),
              ]),
            ]);

    /// run plays [c] for [seconds], or until its scene changes.
    void run(CanvasController c, double seconds, {Set<int> keys = const {}}) {
      c.game!.input.keys
        ..clear()
        ..addAll(keys);
      var at = c.document.at;
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        if (!c.gaming || c.document.at != at) return;
        c.stepGame(1 / 60);
      }
    }

    var right = {key(LogicalKeyboardKey.arrowRight)};

    test("kept: where it starts, and a scene by its id", () {
      var back = CanvasDocument.fromJson(levels().toJson());
      expect(back.gameStart, "title");
      expect(
          GameEffect.fromJson(
              const GameEffect(does: GameDoes.scene, scene: "two").toJson()),
          const GameEffect(does: GameDoes.scene, scene: "two"));
    });

    test("from the title screen, level to level, and the end after the last",
        () {
      var c = CanvasController(levels());
      addTearDown(c.dispose);
      c.goToScene(3);
      c.gaming = true;
      expect(c.document.at, 0, reason: "on the title screen");
      run(c, 0.1);
      run(c, 0.05, keys: {key(LogicalKeyboardKey.space)});
      expect(c.document.at, 1, reason: "Jump pressed its Start button");
      run(c, 1.5, keys: right);
      expect(c.document.at, 2, reason: "the flag: on to the next scene");
      expect(c.game!.bodies["hero"]?.at.dx ?? 0, lessThan(50),
          reason: "the next level's player where it was put");
    });

    test("started again, back to the title screen", () {
      var c = CanvasController(levels());
      addTearDown(c.dispose);
      c.goToScene(2);
      c.gaming = true;
      c.goToScene(2);
      c.game!.newScene();
      run(c, 1.5, keys: right);
      expect(c.document.at, 0,
          reason: "the last life gone: the game again, from its start");
      expect(c.game!.countOf(c.document, "lives"), 1);
    });

    // Ken: the master canvas as a game's HUD -- over the levels, left off
    // the title screen.
    test("the master over every scene, and left off one", () {
      var doc = CanvasDocument(
          masterOn: true,
          masterOver: true,
          master: CanvasScene(id: "m", elements: [box("score", 0, 0, 10, 10)]),
          scenes: [
            const CanvasScene(id: "title", masterOff: true),
            CanvasScene(id: "one", elements: [box("hero", 0, 0, 10, 10)]),
          ]);
      var back = CanvasDocument.fromJson(doc.toJson());
      expect(back.masterOver, isTrue);
      expect(back.allScenes.first.masterOff, isTrue);
      expect(doc.goToScene(0).masterScene, isNull, reason: "the title screen");
      expect(doc.goToScene(1).masterScene!.id, "m");
      expect(
          stackedWithMaster(
                  [box("score", 0, 0, 1, 1)], [box("hero", 0, 0, 1, 1)],
                  over: true)
              .map((e) => e.id),
          ["hero", "score"],
          reason: "over: drawn after the level");
    });

    testWidgets("drawn over the level, a HUD; under, as before",
        (tester) async {
      ShapeElement fill(String id, Color c) =>
          ShapeElement(ElementBase(id: id, width: 1280, height: 720), fill: c);
      Future<int> middle(bool over) async {
        var doc = CanvasDocument(
            masterOn: true,
            masterOver: over,
            master: CanvasScene(
                id: "m", elements: [fill("hud", const Color(0xFFFF0000))]),
            scenes: [
              CanvasScene(
                  id: "one",
                  elements: [fill("level", const Color(0xFF0000FF))]),
              const CanvasScene(id: "two"),
            ]);
        late int colour;
        await tester.runAsync(() async {
          var recorder = ui.PictureRecorder();
          paintCanvasDocument(ui.Canvas(recorder), doc);
          var picture = recorder.endRecording();
          var image = await picture.toImage(1280, 720);
          var bytes = (await image.toByteData())!;
          colour = bytes.getUint32((360 * 1280 + 640) * 4);
          image.dispose();
          picture.dispose();
        });
        return colour;
      }

      expect(await middle(true), 0xFF0000FF, reason: "the HUD on top: red");
      expect(await middle(false), 0x0000FFFF, reason: "the level on top: blue");
    });

    testWidgets("the Game panel's start, HUD and per-scene master",
        (tester) async {
      var c = CanvasController(CanvasDocument(
          game: true,
          masterOn: true,
          master: CanvasScene(id: "m", elements: [box("score", 0, 0, 10, 10)]),
          scenes: [
            const CanvasScene(id: "title", name: "Title"),
            CanvasScene(id: "one", name: "Level 1"),
          ]));
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: SizedBox(
                    width: 300,
                    height: 2000,
                    child: CanvasGamePanel(controller: c)))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("gameStart")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Title").last);
      await tester.pumpAndSettle();
      expect(c.document.gameStart, "title");
      await tester.tap(find.byKey(const ValueKey("gameMasterOver")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Over every scene: a HUD").last);
      await tester.pumpAndSettle();
      expect(c.document.masterOver, isTrue);
      expect(find.byKey(const ValueKey("gameSceneHud-0")), findsOneWidget);
      expect(find.byKey(const ValueKey("gameSceneStart")), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey("gameScene-0")));
      await tester.pumpAndSettle();
      expect(c.document.allScenes.first.masterOff, isTrue,
          reason: "the title screen without the HUD");
      expect(tester.takeException(), isNull);
    });

    test("after the last scene the game is over; stopped, back where it was",
        () {
      var c = CanvasController(levels());
      addTearDown(c.dispose);
      c.goToScene(1);
      c.gaming = true;
      c.goToScene(3);
      c.game!.newScene();
      run(c, 1.5, keys: right);
      expect(c.gaming, isFalse, reason: "no scene after the last");
      expect(c.document.at, 1, reason: "back on the scene being worked on");
    });
  });

  // Found playing Sky Isles, the prototype platformer (2026-10-31).
  group("in a level", () {
    test("a moving platform carries what stands on it", () {
      var g = GameRun();
      // A platform under the hero, moving 100 across over 60 frames.
      var platform = ShapeElement(ElementBase(
          id: "lift",
          x: 60,
          y: 400,
          width: 200,
          height: 20,
          play: const PlaySpec(as: PlayAs.solid),
          track: ElementTrack(const [
            Keyframe(frame: 0),
            Keyframe(frame: 60, dx: 100),
          ])));
      var doc = page.copyWith(frames: 120, elements: [
        box("hero", 100, 300, 40, 60, as: PlayAs.platformer),
        platform,
      ]);
      for (var i = 0; i < 30; i++) {
        g.step(doc, 0, 1 / 60);
      }
      var b = g.bodies["hero"]!;
      expect(b.onGround, isTrue, reason: "landed on it");
      var x = b.at.dx;
      for (var f = 1; f <= 60; f++) {
        g.step(doc, f, 1 / 60);
      }
      expect(b.at.dx - x, closeTo(100, 1), reason: "carried as far as it went");
      expect(b.onGround, isTrue, reason: "and still on it");
      // Looped back to its start, the timeline is no move: not carried.
      g.step(doc, 0, 1 / 60);
      expect(b.at.dx - x, closeTo(100, 1));
    });

    test(
        "a scene's own parallax backdrop moves with the view, and the "
        "master's", () {
      var g = GameRun();
      ParallaxElement scenery() =>
          ParallaxElement(const ElementBase(id: backgroundParallaxId),
              layers: const [ParallaxLayer(kind: SceneryKind.hills)]);
      var back = CanvasBackground(
          backdrop: BackdropKind.parallax, parallax: scenery());
      var doc = CanvasDocument(game: true, scenes: [
        CanvasScene(id: "one", background: back, elements: [
          box("hero", 1000, 600, 40, 60, as: PlayAs.platformer),
        ]),
        const CanvasScene(id: "two"),
      ]);
      g.step(doc, 0, 1 / 60);
      expect(g.camera.dx, greaterThan(0));
      expect(g.view(doc).scene.background!.parallax!.camera.x, g.camera.dx,
          reason: "the scene's own: it went nowhere, the view moving");
      var shared = doc.withMaster(CanvasScene(id: "m", background: back));
      shared = shared.copyWith(masterOn: true);
      expect(
          g.view(shared).master!.background!.parallax!.camera.x, g.camera.dx);
    });

    test("show and hide: a bridge put out, a HUD's banner shown", () {
      var g = GameRun();
      ShapeElement hidden(String id, double x, double y) {
        var e = box(id, x, y, 200, 40);
        return e.rebase(e.base.copyWith(visible: false)) as ShapeElement;
      }

      var doc = page.copyWith(
          game: true,
          masterOn: true,
          master: CanvasScene(id: "hud", elements: [hidden("win", 400, 200)]),
          elements: [
            box("hero", 100, 600, 40, 60, as: PlayAs.platformer),
            box("gem", 100, 600, 40, 60,
                play: const PlaySpec(
                    as: PlayAs.pickup,
                    touched: GameEffect(does: GameDoes.show, element: "win"))),
            box("lever", 100, 600, 40, 60,
                play: const PlaySpec(
                    as: PlayAs.pickup,
                    stays: true,
                    touched: GameEffect(does: GameDoes.hide, element: "wall"))),
            box("wall", 300, 500, 40, 220, as: PlayAs.solid),
          ]);
      expect(
          GameEffect.fromJson(
              const GameEffect(does: GameDoes.show, element: "win").toJson()),
          const GameEffect(does: GameDoes.show, element: "win"));
      g.step(doc, 0, 1 / 60);
      var view = g.view(doc);
      expect(view.master!.elements.firstWhere((e) => e.id == "win").visible,
          isTrue,
          reason: "the HUD's banner, shown");
      expect(g.shown(doc.elementById("wall")!), isFalse,
          reason: "hidden: no longer in the way");
      // Shown already, showing it again leaves it shown.
      g.step(doc, 0, 1 / 60);
      expect(
          g.view(doc).master!.elements.firstWhere((e) => e.id == "win").visible,
          isTrue);
    });

    test("a sprite is touched where it is drawn, not the square round it", () {
      var g = GameRun();
      // A coin drawn in the middle half of its 100 box.
      var coin = SpriteElement(
          const ElementBase(
              id: "coin",
              x: 200,
              y: 620,
              width: 100,
              height: 100,
              play: PlaySpec(
                  as: PlayAs.pickup,
                  touched: GameEffect(does: GameDoes.add, count: "coins"))),
          sheet: "x",
          drawn: const Rect.fromLTRB(0.25, 0.25, 0.75, 0.75));
      var doc = page.copyWith(game: true, counts: const [
        GameCount("coins", "Coins")
      ], elements: [
        box("hero", 140, 660, 40, 60, as: PlayAs.platformer),
        coin
      ]);
      g.step(doc, 0, 1 / 60);
      g.bodies["hero"]!.at = const Offset(40, 0);
      g.step(doc, 0, 1 / 60);
      expect(g.countOf(doc, "coins"), 0,
          reason: "in its square, not yet at the coin");
      g.bodies["hero"]!.at = const Offset(100, 0);
      g.step(doc, 0, 1 / 60);
      expect(g.countOf(doc, "coins"), 1, reason: "at the coin");
    });

    test("a Counter of the game's count is live, however it was made", () {
      // A new counter is keyed: chosen to show a count, it read its start.
      var hud = const CounterElement(ElementBase(id: "coins"),
          source: CounterSource.game, gameCount: "coins");
      expect(hud.keyed, isTrue);
      expect(hud.live, isTrue);
      var c = CanvasController(page.copyWith(
          game: true,
          counts: const [GameCount("coins", "Coins", start: 2)],
          elements: [hud]));
      addTearDown(c.dispose);
      expect(c.counterValue(hud), 2);
    });

    test("the game, and each scene of it, from its first frame", () {
      var c = CanvasController(CanvasDocument(game: true, frames: 120, scenes: [
        CanvasScene(id: "one", frames: 120, elements: [
          box("hero", 100, 600, 40, 60, as: PlayAs.platformer),
          box("flag", 100, 600, 40, 60,
              play: const PlaySpec(
                  as: PlayAs.pickup, touched: GameEffect(does: GameDoes.next))),
        ]),
        CanvasScene(id: "two", frames: 120, elements: [
          box("hero", 100, 600, 40, 60, as: PlayAs.platformer),
        ]),
      ]));
      addTearDown(c.dispose);
      // Left part way through each while it was made.
      c.goToScene(1);
      c.frame = 80;
      c.goToScene(0);
      c.frame = 60;
      c.gaming = true;
      expect(c.frame, 0, reason: "a title, a wait for Space: from the start");
      c.stepGame(1 / 60);
      expect(c.document.at, 1, reason: "the flag");
      expect(c.frame, 0, reason: "the next level from its start too");
      c.gaming = false;
    });
  });

  group("a character", () {
    CharacterElement hero(PlayAs as, {double speed = 160}) =>
        CharacterElement(ElementBase(
            id: "hero",
            x: 100,
            y: 100,
            width: 100,
            height: 300,
            play: PlaySpec(as: as, speed: speed)));
    CharacterElement seen(GameRun g, CanvasDocument doc, int frame) =>
        g.view(doc, frame: frame).elementById("hero") as CharacterElement;
    void run(GameRun g, CanvasDocument doc, double seconds,
        {Set<int> keys = const {}}) {
      g.input.keys
        ..clear()
        ..addAll(keys);
      for (var t = 0.0; t < seconds; t += 1 / 60) {
        g.step(doc, 0, 1 / 60);
      }
    }

    test("stands swaying, walks side on the way it goes, and jumps", () {
      var g = GameRun();
      var doc = page.copyWith(elements: [hero(PlayAs.platformer)]);
      run(g, doc, 1.5);
      var still = seen(g, doc, 10);
      expect(still.motions.single.kind, MotionKind.idle);
      expect(still.pose.turn, 0, reason: "as it was drawn, until it moves");
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.arrowRight)});
      var walking = seen(g, doc, 10);
      expect(walking.motions.single.kind, MotionKind.walk);
      expect(walking.pose.turn, -90, reason: "side on, to the right");
      // At its pace: 160 a second is a walk of 0.6 heights a second.
      expect(walking.motions.single.speed, closeTo(160 / (0.6 * 300), 0.01));
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.arrowLeft)});
      expect(seen(g, doc, 10).pose.turn, 90);
      run(g, doc, 0.1, keys: {key(LogicalKeyboardKey.space)});
      expect(seen(g, doc, 10).motions.single.kind, MotionKind.jump);
      run(g, doc, 2);
      var landed = seen(g, doc, 10);
      expect(landed.motions.single.kind, MotionKind.idle);
      expect(landed.pose.turn, 90, reason: "still facing the way it went");
    });

    test("fast, it runs", () {
      var g = GameRun();
      var doc = page.copyWith(elements: [hero(PlayAs.platformer, speed: 500)]);
      run(g, doc, 1);
      run(g, doc, 0.3, keys: {key(LogicalKeyboardKey.arrowRight)});
      expect(seen(g, doc, 0).motions.single.kind, MotionKind.run);
    });

    test("seen from above, its back to the reader going up", () {
      var g = GameRun();
      var doc = page.copyWith(elements: [hero(PlayAs.topDown)]);
      run(g, doc, 0.3, keys: {key(LogicalKeyboardKey.arrowUp)});
      expect(seen(g, doc, 0).pose.turn, 180);
      expect(seen(g, doc, 0).motions.single.kind, MotionKind.walk);
      run(g, doc, 0.3, keys: {key(LogicalKeyboardKey.arrowDown)});
      expect(seen(g, doc, 0).pose.turn, 0);
    });

    test("its stride runs on the game's clock, whatever the frame", () {
      var g = GameRun();
      var doc = page.copyWith(elements: [hero(PlayAs.platformer)]);
      run(g, doc, 1);
      run(g, doc, 0.5, keys: {key(LogicalKeyboardKey.arrowRight)});
      // The scene looping back to frame 0 does not restart the stride.
      for (var frame in [0, 37, 200]) {
        var clip = seen(g, doc, frame).motions.single;
        expect((frame - clip.start) / doc.frameRate, closeTo(0.5, 0.06),
            reason: "half a second in, at frame $frame");
      }
    });
  });

  test("top-down walks every way, as fast diagonally", () {
    var g = GameRun();
    var doc = page.copyWith(elements: [
      box("hero", 600, 300, 40, 40,
          play: const PlaySpec(as: PlayAs.topDown, speed: 100)),
    ]);
    g.input.keys.addAll([
      key(LogicalKeyboardKey.arrowRight),
      key(LogicalKeyboardKey.arrowDown)
    ]);
    for (var i = 0; i < 60; i++) {
      g.step(doc, 0, 1 / 60);
    }
    expect(g.bodies["hero"]!.at.distance, closeTo(100, 1));
  });

  test("the view follows the player; the backdrop stays behind", () {
    var g = GameRun();
    var doc = page.copyWith(elements: [
      box("hero", 1000, 600, 40, 60, as: PlayAs.platformer),
      box("tree", 1200, 500, 50, 100),
    ]);
    g.step(doc, 0, 1 / 60);
    expect(g.camera.dx, closeTo(1020 - 640, 1));
    var view = g.view(doc);
    expect(view.elementById("tree")!.x, closeTo(1200 - g.camera.dx, 0.01));
    expect(view.elementById("hero")!.x,
        closeTo(1000 + g.bodies["hero"]!.at.dx - g.camera.dx, 0.01));
    expect(doc.elementById("tree")!.x, 1200, reason: "the document untouched");
  });

  test("a sprite walks, stands and jumps as it moves", () {
    var g = GameRun();
    const actions = [
      SpriteAction("Idle", frames: {}),
      SpriteAction("Walk", frames: {}),
      SpriteAction("Jump", frames: {}),
    ];
    var doc = page.copyWith(elements: [
      const SpriteElement(
          ElementBase(
              id: "s",
              x: 100,
              // Standing on the canvas's bottom edge.
              y: 660,
              width: 40,
              height: 60,
              play: PlaySpec(as: PlayAs.platformer)),
          actions: actions,
          action: "Idle",
          directions: true),
    ]);
    String now() => (g.view(doc).elementById("s") as SpriteElement).action;
    g.step(doc, 0, 1 / 60);
    g.step(doc, 0, 1 / 60);
    expect(now(), "Idle");
    g.input.keys.add(key(LogicalKeyboardKey.arrowRight));
    g.step(doc, 0, 1 / 60);
    expect(now(), "Walk");
    expect((g.view(doc).elementById("s") as SpriteElement).facing,
        SpriteFacing.right);
    g.input.keys.add(key(LogicalKeyboardKey.space));
    g.step(doc, 0, 1 / 60);
    g.step(doc, 0, 1 / 60);
    expect(now(), "Jump");
  });

  test("a controller's stick past its dead zone, and its buttons", () {
    var input = GameInput();
    NormalizedGamepadEvent axis(GamepadAxis a, double v) =>
        NormalizedGamepadEvent(
            gamepadId: "1",
            timestamp: 0,
            axis: a,
            value: v,
            rawEvent: GamepadEvent(
                gamepadId: "1",
                timestamp: 0,
                type: KeyType.analog,
                key: "x",
                value: v));
    input.gamepad(axis(GamepadAxis.leftStickX, -0.2));
    expect(input.pad, isEmpty, reason: "inside the dead zone");
    input.gamepad(axis(GamepadAxis.leftStickX, -0.8));
    expect(input.pad, {PadInput.leftStickLeft});
    input.gamepad(axis(GamepadAxis.leftStickX, 0));
    expect(input.pad, isEmpty);
    var jump = page.controlsNow.firstWhere((a) => a.id == "jump");
    input.gamepad(NormalizedGamepadEvent(
        gamepadId: "1",
        timestamp: 0,
        button: GamepadButton.a,
        value: 1,
        rawEvent: GamepadEvent(
            gamepadId: "1",
            timestamp: 0,
            type: KeyType.button,
            key: "a",
            value: 1)));
    expect(input.pressed(jump), isTrue);
    input.endStep(page.controlsNow);
    expect(input.pressed(jump), isFalse, reason: "held is not pressed again");
  });

  group("the controller", () {
    CanvasController make() =>
        CanvasController(page.copyWith(frames: 240, elements: [
          box("hero", 100, 100, 40, 60, as: PlayAs.platformer),
        ]));

    test("keys bound to an action are taken while playing; Esc stops", () {
      var c = make();
      addTearDown(c.dispose);
      c.gaming = true;
      expect(c.playing, isTrue);
      var space = const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.space,
          logicalKey: LogicalKeyboardKey.space,
          timeStamp: Duration.zero);
      expect(c.gameKey(space), isTrue, reason: "Space jumps, not pauses");
      expect(
          c.gameKey(const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyQ,
              logicalKey: LogicalKeyboardKey.keyQ,
              timeStamp: Duration.zero)),
          isFalse);
      c.stepGame(1 / 60);
      expect(c.gameView, isNotNull);
      expect(
          c.gameKey(const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.escape,
              logicalKey: LogicalKeyboardKey.escape,
              timeStamp: Duration.zero)),
          isTrue);
      expect((c.gaming, c.gameView, c.playing), (false, null, false));
      expect(c.document.elementById("hero")!.y, 100,
          reason: "stopped, everything is where it was put");
    });
  });

  // Ken: the game's settings in a Game panel of their own -- each
  // element's, and with nothing picked the game's -- every element still
  // until it is given something to do.
  testWidgets("the Game panel: an element's play, the game's controls",
      (tester) async {
    var c = CanvasController(page.copyWith(game: true, elements: [
      box("hero", 100, 100, 40, 60),
      const TileMapElement(ElementBase(id: "map", width: 640, height: 320),
          layers: [TileLayer(name: "Ground"), TileLayer(name: "Sky")]),
    ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300,
                  height: 1400,
                  child: CanvasGamePanel(controller: c)))),
    ));
    await tester.pumpAndSettle();
    // Nothing picked: the game's own settings.
    expect(find.text("A game · 1 scene · 1 player"), findsOneWidget);
    expect(find.byKey(const ValueKey("control-1-jump")), findsOneWidget);
    // Each player's controls, one at a time.
    await tester.tap(find.byKey(const ValueKey("controlsPlayer-2")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("control-2-jump")), findsOneWidget);
    expect(find.text("F"), findsWidgets, reason: "the second player's jump");
    expect(find.byKey(const ValueKey("playAs-platformer")), findsNothing);

    // An element picked: still, until it is given something to do.
    c.selectOnly("hero");
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("control-1-jump")), findsNothing);
    expect(c.document.elementById("hero")!.base.play.as, PlayAs.none);
    expect(
        find.text("Character · Not played").evaluate().isNotEmpty ||
            find.textContaining("Not played").evaluate().isNotEmpty,
        isTrue);
    await tester.tap(find.byKey(const ValueKey("playAs-platformer")));
    await tester.pumpAndSettle();
    expect(c.document.elementById("hero")!.base.play.as, PlayAs.platformer);
    expect(find.byKey(const ValueKey("playJump")), findsOneWidget);
    expect(c.canUndo, isTrue);
    await tester.tap(find.byKey(const ValueKey("playPlayer")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Player 2").last);
    await tester.pumpAndSettle();
    expect(c.document.elementById("hero")!.base.play.player, 2);

    // A tile map: which of its layers are the ground.
    c.selectOnly("map");
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("gameSolid-0")));
    await tester.pumpAndSettle();
    expect([
      for (var l in (c.document.elementById("map") as TileMapElement).layers)
        l.solid
    ], [
      true,
      false
    ]);

    // Played from here, and stopped.
    await tester.tap(find.byKey(const ValueKey("playGame")));
    await tester.pump();
    expect(c.gaming, isTrue);
    await tester.tap(find.byKey(const ValueKey("playGame")));
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.gaming, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets("made a pickup in the Game panel; counts added and given a rule",
      (tester) async {
    var c = CanvasController(page.copyWith(game: true, elements: [
      box("coin", 100, 100, 20, 20),
    ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300,
                  height: 2000,
                  child: CanvasGamePanel(controller: c)))),
    ));
    c.selectOnly("coin");
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("playAs-pickup")));
    await tester.pumpAndSettle();
    var spec = c.document.elementById("coin")!.base.play;
    expect(spec.as, PlayAs.pickup);
    expect(c.document.counts.single.name, "Coins", reason: "made for it");
    expect(spec.touched,
        GameEffect(does: GameDoes.add, count: c.document.counts.single.id));
    expect(find.byKey(const ValueKey("playTouched-count")), findsOneWidget);
    expect(find.byKey(const ValueKey("playStays")), findsOneWidget);
    // One undo takes back the count and the pickup together.
    c.undo();
    expect(c.document.counts, isEmpty);
    expect(c.document.elementById("coin")!.base.play.as, PlayAs.none);
    c.redo();

    // The game's own: its counts.
    c.clearSelection();
    await tester.pumpAndSettle();
    // A card each, opened to change it.
    expect(find.text("Coins"), findsWidgets);
    expect(find.byKey(const ValueKey("count-name-0")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("count-open-0")));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("count-name-0")), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey("countAdd")));
    await tester.tap(find.byKey(const ValueKey("countAdd")));
    await tester.pumpAndSettle();
    expect(c.document.counts.length, 2);
    await tester.ensureVisible(find.byKey(const ValueKey("count-reaches-1")));
    await tester.tap(find.byKey(const ValueKey("count-reaches-1")));
    await tester.pumpAndSettle();
    expect(c.document.counts[1].reach, 10);
    expect(c.document.counts[1].then.does, GameDoes.restart);
    expect(find.byKey(const ValueKey("count-then-1-does")), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey("count-remove-1")));
    await tester.tap(find.byKey(const ValueKey("count-remove-1")));
    await tester.pumpAndSettle();
    expect(c.document.counts.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a Counter set to show a game count", (tester) async {
    var c = CanvasController(page.copyWith(game: true, counts: const [
      GameCount("coins", "Coins", start: 5)
    ], elements: [
      CounterElement(const ElementBase(id: "n", width: 200, height: 80),
          keyed: false),
    ]));
    addTearDown(c.dispose);
    c.selectOnly("n");
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => CanvasControlScope(
              maxWidth: 280,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: elementSettings(context, c, c.selected!)),
            ),
          ),
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    var shows = find.byKey(const ValueKey("counterSource"));
    if (shows.evaluate().isEmpty) {
      // Its section shut: opened.
      var section = find.byKey(const ValueKey("elementSection-count"));
      await tester.ensureVisible(section);
      await tester.tap(
          find.descendant(of: section, matching: find.text("Count")).first);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(shows);
    await tester.tap(shows);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CounterSource.game.label).last);
    await tester.pumpAndSettle();
    var n = c.document.elementById("n") as CounterElement;
    expect((n.source, n.gameCount), (CounterSource.game, "coins"));
    expect(c.counterValue(n), 5, reason: "its start, before the game");
    expect(find.byKey(const ValueKey("counterGameCount")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("pressed by an action, in the Game panel", (tester) async {
    var c = CanvasController(page.copyWith(game: true, elements: [
      box("lever", 100, 100, 20, 60),
      box("gate", 300, 100, 20, 200),
      ButtonElement(const ElementBase(id: "b")),
    ]));
    addTearDown(c.dispose);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 300,
                  height: 1600,
                  child: CanvasGamePanel(controller: c)))),
    ));
    c.selectOnly("lever");
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("playReach")), findsNothing);
    await tester.tap(find.byKey(const ValueKey("playPressedBy")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Action").last);
    await tester.pumpAndSettle();
    expect(c.document.elementById("lever")!.base.play.pressedBy, "act");
    await tester.tap(find.byKey(const ValueKey("playReach")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("A player beside it").last);
    await tester.pumpAndSettle();
    expect(c.document.elementById("lever")!.base.play.reach, 48);
    expect(find.byKey(const ValueKey("playPress-does")), findsOneWidget,
        reason: "what a press does, as a button's");
    // A Button does its own.
    c.selectOnly("b");
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey("playPressedBy")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Jump").last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("playPress-does")), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Ken runs a larger text size: the panel at each, in each state.
  testWidgets("the Game panel fits at every text size", (tester) async {
    var doc = CanvasDocument(
        game: true,
        gameStart: "title",
        masterOn: true,
        masterOver: true,
        master: CanvasScene(id: "m", elements: [box("score", 0, 0, 10, 10)]),
        counts: const [
          GameCount("coins", "Coins"),
          GameCount("lives", "Lives",
              start: 3, reach: 0, then: GameEffect(does: GameDoes.restart)),
        ],
        scenes: [
          const CanvasScene(id: "title", name: "Title", masterOff: true),
          CanvasScene(id: "one", name: "Level 1", elements: [
            box("hero", 100, 100, 40, 60, as: PlayAs.platformer),
            box("coin", 200, 100, 20, 20,
                play: const PlaySpec(
                    as: PlayAs.pickup,
                    touched: GameEffect(does: GameDoes.next))),
            box("spikes", 300, 100, 60, 20,
                play: const PlaySpec(
                    as: PlayAs.hazard,
                    pressedBy: "act",
                    reach: 48,
                    touched: GameEffect(does: GameDoes.take, count: "lives"))),
          ]),
          const CanvasScene(id: "two", name: "Level 2"),
        ]);
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var scale in [1.0, 1.25, 1.5]) {
      for (var pick in [null, "hero", "coin", "spikes"]) {
        var c = CanvasController(doc);
        c.goToScene(1);
        if (pick != null) c.selectOnly(pick);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeNotifier>(
                create: (c) => ThemeNotifier(doLoad: false)),
            ChangeNotifierProvider<SnackBarModel>(
                create: (c) => SnackBarModel()),
            ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences()),
          ],
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  body: SizedBox(
                      width: 300,
                      height: 2400,
                      child: CanvasGamePanel(controller: c)))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: "${pick ?? "nothing"} picked at ${scale}x");
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      }
    }
  });

  testWidgets("an element's settings no longer have a Play section",
      (tester) async {
    var c = CanvasController(
        page.copyWith(elements: [box("hero", 100, 100, 40, 60)]));
    addTearDown(c.dispose);
    c.selectOnly("hero");
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: CanvasControlScope(
            maxWidth: 280,
            child: Builder(
                builder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: elementSettings(context, c, c.selected!))),
          ),
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("elementSection-play")), findsNothing,
        reason: "it is in the Game panel now");
    expect(tester.takeException(), isNull);
  });
}
