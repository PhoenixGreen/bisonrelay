import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_design.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_performance.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_shape.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/cast_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_cast_test.dart is the Cast (Ken, 2026-11-10): a game's hero kept
// once, with linked copies in its scenes. Each copy's own: its place and
// size, which way it faces, whether it is shown, what it does there, and
// whether it is the player there. Shared: its design, its game settings,
// its motions, its name.

CharacterDesign design({double eyes = 0.3}) => CharacterDesign(
    id: "d1",
    name: "Vivi",
    body: "Vivi",
    shape: const CharacterShape().withValue("eyes.size", eyes),
    updated: DateTime(2026));

Character3dElement vivi(
        {double x = 100,
        double w = 90,
        PlaySpec play = const PlaySpec(),
        CharacterPerformance p = const CharacterPerformance(),
        double eyes = 0.3,
        String id = "vivi"}) =>
    Character3dElement(
        ElementBase(
            id: id,
            name: "Vivi",
            x: x,
            y: 700,
            width: w,
            height: w * 2.2,
            play: play),
        design: design(eyes: eyes),
        performance: p);

const hero = PlaySpec(as: PlayAs.platformer, speed: 340, jump: 260);
const wave = CharacterPerformance(
    clips: [MotionClip3d(kind: "Wave", start: 1, length: 3)]);

/// game is a title with a big waving Vivi, and two levels with her played.
CanvasDocument game() {
  var doc = CanvasDocument().addElement(vivi(x: 400, w: 380, p: wave));
  doc = doc.addScene().goToScene(1).addElement(vivi(play: hero));
  doc = doc.addScene().goToScene(2).addElement(vivi(x: 60, play: hero));
  return doc.goToScene(1);
}

Character3dElement inScene(CanvasDocument doc, int i) =>
    doc.allScenes[i].elements.single as Character3dElement;

void main() {
  test("added to the Cast, every scene's copy is linked, each its own", () {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    var id = c.addToCast("vivi")!;
    expect(c.cast.single.id, id);
    for (var i = 0; i < 3; i++) {
      expect(inScene(c.document, i).base.cast, id, reason: "scene $i linked");
    }
    var title = inScene(c.document, 0);
    expect((title.x, title.width), (400.0, 380.0),
        reason: "the title's Vivi stays big, where she was");
    expect(title.performance.clips.single.kind, "Wave",
        reason: "and does what she did there");
    expect(title.base.play.as, PlayAs.none, reason: "not played on the title");
    expect(title.base.play.speed, 340,
        reason: "but her game settings are the player's, ready");
    expect(c.castCopiesOf(id), 3);
    c.undo();
    expect(c.cast, isEmpty, reason: "one step to undo");
    expect(inScene(c.document, 0).base.cast, isEmpty);
  });

  test("what is shared, changed on one copy, changes every copy", () {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    c.addToCast("vivi");
    var here = c.document.elementById("vivi") as Character3dElement;
    // Faster, in the woods: in every scene.
    c.replaceElement(here
        .rebase(here.base.copyWith(play: here.base.play.copyWith(speed: 420))));
    expect(inScene(c.document, 2).base.play.speed, 420);
    expect(inScene(c.document, 0).base.play.speed, 420);
    expect(inScene(c.document, 0).base.play.as, PlayAs.none,
        reason: "still not played on the title");
    expect(c.cast.single.base.play.speed, 420, reason: "the member too");
    // Her look, from the Studio: everywhere.
    here = c.document.elementById("vivi") as Character3dElement;
    c.replaceElement(here.copyWith(design: design(eyes: 0.8)));
    expect(inScene(c.document, 0).design.shape.get("eyes.size"), 0.8);
    // A motion clip: shared.
    here = c.document.elementById("vivi") as Character3dElement;
    var shake = presetNamed("Shake")!.clip("hurt");
    c.replaceElement(here.withBase(motion: here.base.motion.withClip(shake)));
    expect(inScene(c.document, 2).base.motion.clips.map((m) => m.id),
        contains("hurt"));
  });

  test("what is its own stays in its scene", () {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    c.addToCast("vivi");
    var here = c.document.elementById("vivi") as Character3dElement;
    c.replaceElement(
        here.withBase(x: 900, width: 120, height: 264, rotation: 10));
    c.replaceElement((c.document.elementById("vivi") as Character3dElement)
        .performing(wave)
        .copyWith(turn: 0.5));
    var other = inScene(c.document, 2);
    expect((other.x, other.width, other.base.rotation), (60.0, 90.0, 0.0));
    expect(other.performance.clips, isEmpty);
    expect(other.turn, 0);
    var title = inScene(c.document, 0);
    expect(title.width, 380);
  });

  test("kept with the document, linked as it was", () {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    var id = c.addToCast("vivi")!;
    var back = CanvasDocument.decode(jsonEncode(c.document.toJson()))!;
    expect(back.cast.single.id, id);
    expect(inScene(back, 0).base.cast, id);
    expect(inScene(back, 0).width, 380);
  });

  test("placed from the Cast, unlinked, taken out of the Cast", () {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    var id = c.addToCast("vivi")!;
    c.goToScene(2);
    c.placeFromCast(id);
    var placed = c.document.elements.last;
    expect(placed.base.cast, id);
    expect(placed.id, isNot("vivi"), reason: "a copy of its own");
    expect(c.selection, {placed.id});
    expect(c.castCopiesOf(id), 4);
    // Unlinked, a copy is its own: what it shares no longer follows.
    c.unlinkFromCast(placed.id);
    c.goToScene(1);
    var here = c.document.elementById("vivi") as Character3dElement;
    c.replaceElement(here
        .rebase(here.base.copyWith(play: here.base.play.copyWith(jump: 300))));
    c.goToScene(2);
    expect(c.document.elementById(placed.id)!.base.play.jump, 260);
    expect(c.document.elementById("vivi")!.base.play.jump, 300);
    // Out of the Cast: every copy kept, as it is.
    c.removeFromCast(id);
    expect(c.cast, isEmpty);
    expect(inScene(c.document, 0).base.cast, isEmpty);
    expect(inScene(c.document, 0).width, 380);
  });

  test("a copy is its member's shared part with its own", () {
    var member = vivi(play: hero, eyes: 0.8);
    var copy = vivi(x: 400, w: 380, p: wave);
    var linked = castLinked(member, copy) as Character3dElement;
    expect(linked.design.shape.get("eyes.size"), 0.8);
    expect((linked.x, linked.width), (400.0, 380.0));
    expect(linked.performance.clips.single.kind, "Wave");
    expect(linked.base.play.as, PlayAs.none);
    expect(linked.base.play.speed, 340);
    expect(sameShared(member, linked), isTrue);
    expect(sameShared(member, copy), isFalse);
  });

  // The panel itself: what a click does, not only what the model can.
  testWidgets("the Cast panel adds, places and unlinks", (tester) async {
    var c = CanvasController(game());
    addTearDown(c.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (_) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
          home: Scaffold(
              body: SizedBox(width: 320, child: CastPanel(controller: c)))),
    ));
    expect(find.byKey(const ValueKey("castEmpty")), findsOneWidget);
    c.selectOnly("vivi");
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey("castAdd")));
    await tester.pump();
    var id = c.cast.single.id;
    expect(find.text("3 copies"), findsOneWidget);
    expect(find.byKey(const ValueKey("castLinkedNote")), findsOneWidget);
    await tester.tap(find.byKey(ValueKey("castMember-$id")));
    await tester.pump();
    expect(find.text("4 copies"), findsOneWidget, reason: "one placed");
    expect(c.document.elements.last.base.cast, id);
    await tester.tap(find.byKey(const ValueKey("castUnlink")));
    await tester.pump();
    expect(c.document.elements.last.base.cast, isEmpty);
    expect(find.text("3 copies"), findsOneWidget);
    await tester.tap(find.byKey(ValueKey("castRemove-$id")));
    await tester.pump();
    expect(c.cast, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
