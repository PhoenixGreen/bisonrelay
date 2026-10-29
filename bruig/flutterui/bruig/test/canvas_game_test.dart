import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
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
  });

  test("top-down walks every way, as fast diagonally", () {
    var g = GameRun();
    var doc = page.copyWith(elements: [
      box("hero", 600, 300, 40, 40,
          play: const PlaySpec(as: PlayAs.topDown, speed: 100)),
    ]);
    g.input.keys.addAll(
        [key(LogicalKeyboardKey.arrowRight), key(LogicalKeyboardKey.arrowDown)]);
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
    CanvasController make() => CanvasController(page.copyWith(frames: 240, elements: [
          box("hero", 100, 100, 40, 60, as: PlayAs.platformer),
        ]));

    test("keys bound to an action are taken while playing; Esc stops", () {
      var c = make();
      addTearDown(c.dispose);
      expect(c.playable, isTrue);
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

  testWidgets("an element's Play section", (tester) async {
    var c = CanvasController(page.copyWith(elements: [box("hero", 100, 100, 40, 60)]));
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
              body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => SingleChildScrollView(
          child: SizedBox(
            width: 320,
            child: CanvasControlScope(
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
    var section = find.byKey(const ValueKey("elementSection-play"));
    expect(section, findsOneWidget);
    if (find.byKey(const ValueKey("playAs")).evaluate().isEmpty) {
      await tester.ensureVisible(section);
      await tester.tap(find.descendant(of: section, matching: find.text("Play")).first);
      await tester.pumpAndSettle();
    }
    tester
        .widget<CanvasDropdown<PlayAs>>(find.byKey(const ValueKey("playAs")))
        .onChanged(PlayAs.platformer);
    await tester.pumpAndSettle();
    expect(c.document.elementById("hero")!.base.play.as, PlayAs.platformer);
    expect(find.byKey(const ValueKey("playJump")), findsOneWidget);
    expect(c.playable, isTrue);
    expect(tester.takeException(), isNull);
  });
}
