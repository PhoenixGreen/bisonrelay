import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_document_test.dart is about the file format.
//
// A saved canvas is the only artefact of this feature that outlives the
// session, and a field dropped on the way out is silent -- the document loads,
// looks nearly right, and whatever was lost is only noticed later by whoever
// made it. So every element kind goes out and comes back, and the properties
// that would be easiest to forget are the ones checked.

void main() {
  test("every element kind survives a round trip", () {
    // Built through the factory, so a kind added there without a fromJson is
    // caught here rather than in the editor.
    var document = const CanvasDocument();
    for (var kind in ElementKind.values) {
      document = document.addElement(newElement(kind, document));
    }

    var back = CanvasDocument.decode(document.encode());
    expect(back, isNotNull);
    expect(back!.elements.length, ElementKind.values.length);
    expect([for (var e in back.elements) e.kind], ElementKind.values);
    for (var i = 0; i < back.elements.length; i++) {
      expect(back.elements[i].id, document.elements[i].id);
    }
  });

  test("a picture keeps how it is framed inside its box", () {
    // Framing is written only when it is not the default, so this also checks
    // that the default reads back as the default rather than as nothing.
    var framed = ImageElement(
      const ElementBase(id: "i", width: 100, height: 200),
      assetId: "abcdefghijklmnop",
      framing: const ImageFraming(x: 0.2, y: 0.8, zoom: 2.5),
    );
    var plain = ImageElement(
      const ElementBase(id: "j", width: 100, height: 200),
      assetId: "abcdefghijklmnop",
    );

    var back = CanvasDocument.decode(
        CanvasDocument(elements: [framed, plain]).encode())!;
    var one = back.elements.first as ImageElement;
    expect(one.framing.x, 0.2);
    expect(one.framing.y, 0.8);
    expect(one.framing.zoom, 2.5);
    expect((back.elements[1] as ImageElement).framing.isDefault, isTrue);
  });

  test("a text element keeps its type and its box", () {
    var element = TextElement(
      ElementBase(
          id: "t1", name: "Headline", x: 4, y: 8, width: 200, height: 60),
      text: "Hello",
      textSpec: const TextSpec(
        fontFamily: "Georgia",
        fontSize: 37,
        weight: 800,
        italic: true,
        letterSpacing: 2.5,
        lineHeight: 1.45,
        textCase: TextCase.upper,
        color: Color(0xFF112233),
        outlineWidth: 3,
        outlineColor: Color(0xFFAABBCC),
      ),
      box: const BoxSpec(
          fill: Color(0x80FF0000), borderWidth: 4, borderRadius: 12),
      autoSize: true,
    );

    var back =
        CanvasDocument.decode(CanvasDocument(elements: [element]).encode())!
            .elements
            .first;
    expect(back, isA<TextElement>());
    var text = back as TextElement;

    expect(text.text, "Hello");
    expect(text.autoSize, isTrue);
    expect(text.textSpec.fontFamily, "Georgia");
    expect(text.textSpec.fontSize, 37);
    expect(text.textSpec.weight, 800);
    expect(text.textSpec.italic, isTrue);
    expect(text.textSpec.letterSpacing, 2.5);
    expect(text.textSpec.lineHeight, 1.45);
    expect(text.textSpec.textCase, TextCase.upper);
    expect(text.textSpec.outlineWidth, 3);
    expect(text.box.borderRadius, 12);
    expect(text.name, "Headline");
  });

  test("colours survive exactly", () {
    // Colour is stored as one packed integer rather than as four floating
    // point channels, because a float channel round-tripped through JSON is a
    // colour that comes back very slightly different. This is what says so.
    const colour = Color(0xC3456789);
    var element = ShapeElement(const ElementBase(id: "s1"), fill: colour);
    var back =
        CanvasDocument.decode(CanvasDocument(elements: [element]).encode())!
            .elements
            .first;
    expect((back as ShapeElement).fill.toARGB32(), colour.toARGB32());
  });

  test("a team round-trips its squad, formation and lettering", () {
    var element = TeamElement(
      const ElementBase(id: "t1", x: 100, y: 50, width: 400, height: 300),
      mirrored: true,
      namePosition: LabelPosition.left,
      labelRotation: -90,
      nameGap: 11,
      lockDotAspect: false,
      dotWidth: 30,
      dotHeight: 18,
      showNames: false,
    ).withFormation(TeamFormation.f433, mirror: true);

    var back =
        CanvasDocument.decode(CanvasDocument(elements: [element]).encode())!
            .elements
            .first as TeamElement;

    expect(back.formation, TeamFormation.f433);
    expect(back.mirrored, isTrue);
    expect(back.players.length, 11);
    // "1" for the keeper, and written rather than counted -- a squad number is
    // a label, so "07" has to survive as typed.
    expect(back.players.first.number, "1");
    expect(back.namePosition, LabelPosition.left);
    expect(back.labelRotation, -90);
    expect(back.nameGap, 11);
    expect(back.lockDotAspect, isFalse);
    expect(back.dotWidth, 30);
    expect(back.dotHeight, 18);
    expect(back.showNames, isFalse);
  });

  test("a formation keeps the squad's numbers and names", () {
    // The whole reason changing formation is not "delete the team and make a
    // new one": a manager comparing 4-3-3 with 4-4-2 is moving the same eleven
    // people, and losing their names would make the comparison useless.
    var team = TeamElement(const ElementBase(id: "t1", width: 400, height: 300))
        .withFormation(TeamFormation.f442);
    var named = team.copyWith(players: [
      for (var p in team.players) p.copyWith(name: "Player ${p.number}"),
    ]);

    var moved = named.withFormation(TeamFormation.f4231);
    expect(moved.players.length, 11);
    expect(moved.players[7].name, named.players[7].name);
    expect(moved.players[7].number, named.players[7].number);
    expect(moved.players[7].dy, isNot(named.players[7].dy));
  });

  test("mirroring a team turns it round, not just along the pitch", () {
    // Flipping only the length leaves the right back on the left touchline --
    // a shape that is a 4-4-2 in outline and wrong in every detail.
    var box = const ElementBase(id: "t", width: 400, height: 300);
    var home = TeamElement(box).withFormation(TeamFormation.f442);
    var away = TeamElement(box).withFormation(TeamFormation.f442, mirror: true);

    for (var i = 0; i < home.players.length; i++) {
      expect(away.players[i].dx, closeTo(1 - home.players[i].dx, 0.0001));
      expect(away.players[i].dy, closeTo(1 - home.players[i].dy, 0.0001));
    }
  });

  test("a player's position follows the team's box", () {
    // Positions are fractions of the box, which is what makes the team a real
    // transform: moving it moves everybody, with nobody having been dragged.
    var team = TeamElement(
      const ElementBase(id: "t", x: 0, y: 0, width: 200, height: 100),
    ).withFormation(TeamFormation.f442);
    var keeper = team.players.first;
    var before = team.centreOf(keeper);

    var moved = team.withBase(x: 500, y: 300) as TeamElement;
    expect(moved.centreOf(keeper).dx, closeTo(before.dx + 500, 0.0001));
    expect(moved.centreOf(keeper).dy, closeTo(before.dy + 300, 0.0001));

    var scaled = team.withBase(width: 400) as TeamElement;
    expect(scaled.centreOf(keeper).dx, closeTo(before.dx * 2, 0.0001));
  });

  test("bring forward and send to back reorder one player", () {
    var team = TeamElement(const ElementBase(id: "t", width: 400, height: 300))
        .withFormation(TeamFormation.f442);
    var striker = team.players.last;

    var back = team.movePlayer(team.players.length - 1, 0);
    expect(back.players.first.number, striker.number);
    expect(back.players.length, 11);

    // Off either end is a no-op rather than an error: the buttons are disabled
    // there, and a model that threw would make that a correctness question.
    expect(back.movePlayer(0, -3).players.first.number, striker.number);
    expect(team.movePlayer(99, 0).players.length, 11);
  });

  test("chart data and its series colours survive", () {
    var element = ChartElement(
      const ElementBase(id: "c1"),
      type: ChartType.stackedBar,
      title: "Title",
      xAxisLabel: "X",
      yAxisLabel: "Y",
      showValues: true,
      data: const ChartData(categories: [
        "a",
        "b"
      ], series: [
        ChartSeries(name: "One", color: Color(0xFF010203), values: [1, 2]),
        ChartSeries(name: "Two", color: Color(0xFF040506), values: [3, 4]),
      ]),
    );
    var back =
        CanvasDocument.decode(CanvasDocument(elements: [element]).encode())!
            .elements
            .first as ChartElement;

    expect(back.type, ChartType.stackedBar);
    expect(back.data.categories, ["a", "b"]);
    expect(back.data.series.length, 2);
    expect(back.data.series[1].name, "Two");
    expect(back.data.series[1].values, [3.0, 4.0]);
    expect(back.data.series[0].color.toARGB32(), 0xFF010203);
    expect(back.showValues, isTrue);
    expect(back.xAxisLabel, "X");
  });

  test("keyframes and timeline markers survive", () {
    var document = CanvasDocument(
      frames: 40,
      frameRate: 24,
      actions: const [
        TimelineAction(
            frame: 20, kind: TimelineActionKind.loop, target: 5, repeats: 3),
      ],
      elements: [
        ShapeElement(ElementBase(
          id: "s1",
          track: ElementTrack(const [
            Keyframe(frame: 0, opacity: 0),
            Keyframe(frame: 10, dx: 30, dy: -5, scale: 1.5, rotate: 45),
          ]),
        )),
      ],
    );

    var back = CanvasDocument.decode(document.encode())!;
    expect(back.frames, 40);
    expect(back.frameRate, 24);
    expect(back.actions.single.kind, TimelineActionKind.loop);
    expect(back.actions.single.target, 5);
    expect(back.actions.single.repeats, 3);

    var track = back.elements.single.track!;
    expect(track.keys.length, 2);
    expect(track.keys.first.opacity, 0);
    expect(track.keys.last.dx, 30);
    expect(track.keys.last.rotate, 45);
  });

  test("an unknown element kind becomes a placeholder rather than vanishing",
      () {
    // A document written by a newer build has an element here somewhere.
    // Leaving something visible where it was is recoverable; silently deleting
    // it is not.
    var json = '{"version":1,"elements":[{"kind":"hologram","id":"x","x":1,'
        '"y":2,"w":3,"h":4}]}';
    var back = CanvasDocument.decode(json);
    expect(back, isNotNull);
    expect(back!.elements.length, 1);
    expect(back.elements.first.id, "x");
    expect(back.elements.first.x, 1);
  });

  test("a damaged file returns null rather than throwing", () {
    // The caller's response is to say so and leave the file alone. An
    // exception here would take down the page the canvas was opened from, and
    // an empty document would invite overwriting the reader's only copy.
    expect(CanvasDocument.decode("not json at all"), isNull);
    expect(CanvasDocument.decode("[1,2,3]"), isNull);
    expect(CanvasDocument.decode(""), isNull);
  });

  test("a missing field falls back rather than throwing", () {
    var back = CanvasDocument.decode('{"elements":[{"kind":"text"}]}');
    expect(back, isNotNull);
    expect(back!.elements.single, isA<TextElement>());
    expect(back.frames, 1);
  });

  test("the canvas height follows the ratio and the width", () {
    expect(const CanvasSize(ratio: CanvasRatio.wide, width: 1600).height, 900);
    expect(const CanvasSize(ratio: CanvasRatio.square, width: 800).height, 800);
    expect(const CanvasSize(ratio: CanvasRatio.tall, width: 900).height, 1600);
    // Rounded rather than truncated: truncating leaves half a pixel of
    // background along the bottom edge of every export.
    expect(const CanvasSize(ratio: CanvasRatio.wide, width: 1281).height, 721);
  });

  test("every preset builds, encodes and reloads", () {
    for (var preset in builtinPresets) {
      var document = preset.build();
      var back = CanvasDocument.decode(document.encode());
      expect(back, isNotNull, reason: "${preset.id} failed to reload");
      expect(back!.elements.length, document.elements.length,
          reason: "${preset.id} lost elements");
    }
  });

  test("the football preset puts a team on each half", () {
    var document = footballCanvas();
    var teams = document.elements.whereType<TeamElement>().toList();
    expect(teams.length, 2,
        reason: "one element per side, not twenty-two per pitch");

    for (var team in teams) {
      expect(team.players.length, 11);
      expect(team.formation, TeamFormation.f442);
    }

    // The two face each other rather than both attacking the same way, which
    // is only true if the away side is mirrored.
    var home = teams.firstWhere((t) => !t.mirrored);
    var away = teams.firstWhere((t) => t.mirrored);
    expect(
        home.centreOf(home.players.first).dx, lessThan(document.size.width / 2),
        reason: "the home keeper is in the left-hand goal");
    expect(away.centreOf(away.players.first).dx,
        greaterThan(document.size.width / 2),
        reason: "and the away keeper in the right-hand one");

    // The keeper is the first player, and is the one in a different shirt.
    expect(home.keeperColor, isNot(home.playerColor));
  });

  test("two canvases from one preset do not share elements", () {
    var a = footballCanvas();
    var b = footballCanvas();
    var aIds = {for (var e in a.elements) e.id};
    var bIds = {for (var e in b.elements) e.id};
    expect(aIds.intersection(bIds), isEmpty);
  });
}
