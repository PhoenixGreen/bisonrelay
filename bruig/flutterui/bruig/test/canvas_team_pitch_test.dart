import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_presets.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/pitch.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/team_photo_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_panel_helpers.dart';

// canvas_team_pitch_test.dart is a team standing on a pitch: that it goes
// wherever the pitch goes, that a player dragged lands where the pointer is,
// and the sports, formations and looks a team now has.

CanvasDocument _withPitch(
        CanvasDocument d, ProceduralSpec Function(ProceduralSpec) f) =>
    d.copyWith(background: d.background.copyWith(spec: f(d.background.spec)));

List<TeamElement> _teams(CanvasDocument d) => [
      for (var e in d.elements)
        if (e is TeamElement) e
    ];

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);
  _photoEditorTests();
  group("a team on a pitch", () {
    test("the football preset's teams stand on its pitch", () {
      var doc = footballCanvas();
      for (var t in _teams(doc)) {
        expect(t.link, teamLinkBackground);
      }
    });

    test("stands exactly where it stood before, on a flat pitch", () {
      // Linking must not move anybody: on the pitch drawn flat and across,
      // the metres and the old box agree.
      var doc = footballCanvas();
      var home = _teams(doc).first;
      var g = teamGround(doc, home, 0)!;
      var unlinked = home.copyWith(link: "");
      var box = home.withBase(
              x: g.place.page(0, 68).dx,
              y: g.place.page(0, 68).dy,
              width: g.place.page(52.5, 0).dx - g.place.page(0, 68).dx,
              height: g.place.page(0, 0).dy - g.place.page(0, 68).dy)
          as TeamElement;
      for (var spot in home.players) {
        var linked = playerPlace(g, home, spot, 0).centre;
        var old = playerPlace(null, box.copyWith(link: ""), spot, 0).centre;
        expect((linked - old).distance, lessThan(0.01), reason: spot.name);
      }
      expect(unlinked.linked, isFalse);
    });

    test("goes with the pitch when it is turned, zoomed, moved or tilted", () {
      var doc = footballCanvas();
      var home = _teams(doc).first;
      var keeper = home.players.first;
      for (var change in <ProceduralSpec Function(ProceduralSpec)>[
        (s) => s.copyWith(rotation: 25),
        (s) => s.copyWith(scale: 0.08),
        (s) => s.copyWith(params: {"panX": 0.3}),
        (s) => s.copyWith(params: {"tiltV": 55, "perspective": 0.8}),
        (s) => s.copyWith(params: {"tiltH": 30, "perspective": 0.8}),
      ]) {
        var moved = _withPitch(doc, change);
        var g = teamGround(moved, home, 0)!;
        var at = playerPlace(g, home, keeper, 0).ground;
        // The keeper is on the pitch where the pitch itself says that spot
        // is -- the field's own mapping, not a guess.
        var field = teamFieldPoint(home, keeper, g.place);
        var placed = pitchPlacement(moved.size.rect, moved.background.spec);
        expect((at - placed.page(field.dx, field.dy)).distance, lessThan(0.01));
        // And he has moved from where he was on the flat pitch.
        var before = playerPlace(teamGround(doc, home, 0), home, keeper, 0);
        expect((at - before.ground).distance, greaterThan(1));
      }
    });

    test("a player dragged on a tilted pitch lands under the pointer", () {
      var doc = _withPitch(
          footballCanvas(),
          (s) => s.copyWith(
              rotation: 12,
              params: {"tiltV": 50, "tiltH": -20, "perspective": 0.8}));
      var home = _teams(doc).first;
      var g = teamGround(doc, home, 0)!;
      for (var (x, y) in [(10.0, 20.0), (40.0, 60.0), (80.0, 5.0)]) {
        var page = g.page(x, y);
        var back = g.field(page)!;
        expect(back.dx, closeTo(x, 1e-6));
        expect(back.dy, closeTo(y, 1e-6));
      }
    });

    test("players further from the camera are drawn smaller", () {
      var doc = _withPitch(footballCanvas(),
          (s) => s.copyWith(params: {"tiltV": 58, "perspective": 0.9}));
      var home = _teams(doc).first;
      var g = teamGround(doc, home, 0)!;
      var near = home.players.reduce((a, b) => a.dy > b.dy ? a : b);
      var far = home.players.reduce((a, b) => a.dy < b.dy ? a : b);
      expect(playerPlace(g, home, far, 0).size,
          lessThan(playerPlace(g, home, near, 0).size));
    });

    test("a new team on a pitch canvas stands on it straight away", () {
      var doc = footballCanvas();
      var team = newElement(ElementKind.player, doc) as TeamElement;
      expect(team.link, teamLinkBackground);
      var plain = const CanvasDocument();
      var loose = newElement(ElementKind.player, plain) as TeamElement;
      expect(loose.linked, isFalse);
    });
  });

  group("sports", () {
    test("every sport has formations with a player for every place", () {
      for (var sport in TeamSport.values) {
        var forms = sport.formations.where((f) => f != TeamFormation.custom);
        expect(forms, isNotEmpty, reason: sport.label);
        for (var f in forms) {
          expect(f.metres, hasLength(sport.squadSize), reason: f.label);
          if (f.roles.isNotEmpty) {
            expect(f.roles, hasLength(sport.squadSize), reason: f.label);
          }
          if (f.numbers.isNotEmpty) {
            expect(f.numbers, hasLength(sport.squadSize), reason: f.label);
          }
        }
      }
    });

    test("changing sport sets the squad up afresh", () {
      var team =
          const TeamElement(ElementBase(id: "t", width: 400, height: 300))
              .withFormation(TeamFormation.f442)
              .namedByPosition();
      var union = team.withSport(TeamSport.rugbyUnion);
      expect(union.players, hasLength(15));
      expect(union.players.first.name, isEmpty);
      expect(union.players.last.number, "15");
      var nfl = team.withSport(TeamSport.americanFootball);
      expect(nfl.players.map((p) => p.number), contains("12"));
    });

    test("linking to another sport's pitch sets the team up for it", () {
      var team =
          const TeamElement(ElementBase(id: "t", width: 400, height: 300))
              .withFormation(TeamFormation.f442);
      var hoops = team.linkedTo("background",
          pitch: PitchSport.basketballNba, reference: 20);
      expect(hoops.sport, TeamSport.basketball);
      expect(hoops.players, hasLength(5));
      expect(
          hoops.dotWidth, closeTo(TeamSport.basketball.tokenMetres * 20, 1e-9));
    });
  });

  group("the ball", () {
    TeamElement eleven() =>
        const TeamElement(ElementBase(id: "t", width: 400, height: 300))
            .withFormation(TeamFormation.f442);

    test("goes on the centre spot, last, and stays through a new formation",
        () {
      var team = eleven().withBall(true);
      expect(team.players, hasLength(12));
      expect(team.players.last.ball, isTrue);
      expect(team.ball!.dx, 1, reason: "the edge of the team's own half");
      var moved = team.withPlayer(11, team.ball!.copyWith(dx: 0.7, dy: 0.2));
      var reshaped = moved.withFormation(TeamFormation.f433).namedByPosition();
      expect(reshaped.players, hasLength(12));
      expect(reshaped.ball!.dx, 0.7, reason: "a formation is the players'");
      expect(reshaped.ball!.name, "Ball");
      expect(reshaped.withSport(TeamSport.basketball).ball, isNotNull);
      expect(team.withBall(false).ball, isNull);
    });

    test("is saved as the ball", () {
      var team = eleven().withBall(true);
      var back = TeamElement.fromJson(team.props(), team.base);
      expect(back.ball, isNotNull);
      expect(back.players.where((p) => p.ball), hasLength(1));
    });

    test("follows a path drawn over a tilted pitch exactly", () {
      var doc = _withPitch(
          footballCanvas(),
          (s) => s.copyWith(
              rotation: 8, params: {"tiltV": 50, "perspective": 0.8}));
      var home = _teams(doc).first.withBall(true);
      var path = PathElement(
        const ElementBase(id: "p", x: 600, y: 400, width: 400, height: 200),
        nodes: const [
          PathNode(x: 0, y: 1, frame: 0),
          PathNode(x: 1, y: 0, frame: 20),
        ],
        follow: PathFollow(elementId: "x", playerIndex: 11),
      );
      doc = doc.copyWith(elements: [
        for (var e in doc.elements) e.id == home.id ? home : e,
        path.copyWith(follow: PathFollow(elementId: home.id, playerIndex: 11)),
      ]);
      var controller = CanvasController(doc);
      controller
          .applyPathFollow(controller.document.elementById("p") as PathElement);
      var team = controller.document.elementById(home.id) as TeamElement;
      var g = teamGround(controller.document, team, 0)!;
      for (var f in [0, 7, 13, 20]) {
        var drawn = playerPlace(g, team, team.ball!, f).ground;
        var wanted = (controller.document.elementById("p") as PathElement)
            .positionAtFrame(f)!;
        expect((drawn - wanted).distance, lessThan(0.5), reason: "frame $f");
      }
      controller.dispose();
    });
  });

  group("saved", () {
    test("with its link, its design and each player's own touches", () {
      var team = const TeamElement(
              ElementBase(id: "t", width: 400, height: 300),
              link: "background",
              secondaryColor: Color(0xFF123456),
              kitPattern: KitPattern.hoops,
              tokenStyle: TokenStyle.portrait,
              faces: false,
              shadow: true,
              nameStyle: NameStyle.plate,
              showRuns: true)
          .withFormation(TeamFormation.f433);
      team = team.withPlayer(
          3,
          team.players[3]
              .copyWith(photo: "abc", captain: true, highlight: true));
      var back = TeamElement.fromJson(team.props(), team.base);
      expect(back.link, "background");
      expect(back.secondaryColor, const Color(0xFF123456));
      expect(back.kitPattern, KitPattern.hoops);
      expect(back.tokenStyle, TokenStyle.portrait);
      expect(back.faces, isFalse);
      expect(back.shadow, isTrue);
      expect(back.nameStyle, NameStyle.plate);
      expect(back.showRuns, isTrue);
      expect(back.players[3].photo, "abc");
      expect(back.players[3].captain, isTrue);
      expect(back.players[3].highlight, isTrue);
    });

    test("keeps its team photo, each crop and the ball's design", () {
      var team = _teams(footballCanvas())
          .first
          .copyWith(
              teamPhoto: "squad",
              ballLook: const BallLook(
                  style: BallStyle.striped,
                  color: Color(0xFF112233),
                  second: Color(0xFF445566),
                  size: 1.8,
                  shadow: false,
                  outline: false,
                  trail: true))
          .withBall(true);
      team = team.withPlayer(
          2,
          team.players[2].copyWith(
              crop: const PhotoCrop(x: 0.3, y: 0.2, radius: 0.05, turn: 12)));
      var back = TeamElement.fromJson(team.props(), team.base);
      expect(back.teamPhoto, "squad");
      expect(back.players[2].crop,
          const PhotoCrop(x: 0.3, y: 0.2, radius: 0.05, turn: 12));
      expect(back.players[3].crop, isNull);
      expect(back.ballLook, team.ballLook);
      // And a team saved before any of it reads back as it was.
      var plain = _teams(footballCanvas()).first;
      expect(plain.props().containsKey("ballLook"), isFalse);
      expect(TeamElement.fromJson(plain.props(), plain.base).ballLook,
          const BallLook());
    });

    test("every player starts on their own part of the team photo", () {
      var team = _teams(footballCanvas()).first.withBall(true);
      var crops = {
        for (var i = 0; i < team.players.length; i++)
          if (!team.players[i].ball) team.cropOf(i, 1.5),
      };
      expect(crops, hasLength(11));
      for (var c in crops) {
        expect(c.x, inInclusiveRange(0, 1));
        expect(c.y, inInclusiveRange(0, 1));
        expect(c.radius, greaterThan(0));
      }
      // The ball counts the ball's own size against the sport's.
      var big = team.copyWith(ballLook: const BallLook(size: 2));
      expect(big.radiusOf(big.ball!),
          closeTo(team.radiusOf(team.ball!) * 2, 1e-9));
    });

    testWidgets("the type's shadow reaches the names, not just the numbers",
        (tester) async {
      late List<int> plain, shadowed;
      await tester.runAsync(() async {
        var src = _Images(await _squadPhoto());
        var team = _teams(footballCanvas())
            .first
            .copyWith(link: "", showNumbers: false)
            .withBase(x: 0, y: 0, width: 200, height: 120) as TeamElement;
        plain = await _teamPixels(team, src);
        shadowed = await _teamPixels(
            team.copyWith(
                labelSpec: team.labelSpec.copyWith(
                    shadowBlur: 3,
                    shadowDistance: 3,
                    shadowColor: const Color(0xFF000000))),
            src);
      });
      // Numbers are off, so whatever changed is the names.
      expect(shadowed, isNot(plain));
    });

    testWidgets("portraits are cut from the team photo, crop by crop",
        (tester) async {
      late List<int> none, photo, moved;
      late List<List<int>> balls;
      await tester.runAsync(() async {
        var image = await _squadPhoto();
        var src = _Images(image);
        var team = (_teams(footballCanvas())
                .first
                .copyWith(link: "", tokenStyle: TokenStyle.portrait)
                .withBase(x: 0, y: 0, width: 200, height: 120) as TeamElement)
            .withBall(true);
        none = await _teamPixels(team, src);
        var withPhoto = team.copyWith(teamPhoto: "squad");
        photo = await _teamPixels(withPhoto, src);
        moved = await _teamPixels(
            withPhoto.withPlayer(
                0,
                withPhoto.players[0]
                    .copyWith(crop: const PhotoCrop(x: 0.9, y: 0.9))),
            src);
        balls = [
          for (var s in BallStyle.values)
            await _teamPixels(
                team.copyWith(ballLook: BallLook(style: s, size: 3)), src),
        ];
      });
      expect(photo, isNot(none));
      expect(moved, isNot(photo));
      for (var i = 0; i < balls.length; i++) {
        for (var j = i + 1; j < balls.length; j++) {
          expect(balls[i], isNot(balls[j]),
              reason: "${BallStyle.values[i]} and ${BallStyle.values[j]}");
        }
      }
    });
  });

  group("the panel", () {
    Future<CanvasController> panel(
        WidgetTester tester, CanvasDocument doc, String id) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var controller = CanvasController(doc);
      addTearDown(controller.dispose);
      controller.selectOnly(id);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>(
              create: (c) => ThemeNotifier(doLoad: false)),
          ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
          ChangeNotifierProvider<CanvasPreferences>(
              create: (c) => CanvasPreferences()),
        ],
        child: MaterialApp(
            home: Scaffold(body: CanvasDesignPanel(controller: controller))),
      ));
      await tester.pumpAndSettle();
      return controller;
    }

    TeamElement teamIn(CanvasController c, String id) =>
        c.document.elementById(id) as TeamElement;

    Future<void> choose(WidgetTester tester, String key, String option) async {
      var box = find.byKey(ValueKey(key));
      await tester.ensureVisible(box);
      await tester.pumpAndSettle();
      await tester.tap(box);
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets("links a team to the pitch, and unlinks it", (tester) async {
      var doc = footballCanvas();
      var loose = _teams(doc).first.copyWith(link: "");
      doc = doc.copyWith(elements: [
        for (var e in doc.elements) e.id == loose.id ? loose : e,
      ]);
      var controller = await panel(tester, doc, loose.id);
      await choose(tester, "teamPitch", "Canvas background");
      expect(teamIn(controller, loose.id).link, teamLinkBackground);
      await choose(tester, "teamPitch", "Not linked");
      expect(teamIn(controller, loose.id).linked, isFalse);
    });

    testWidgets("offers every team sport", (tester) async {
      var doc = footballCanvas();
      var id = _teams(doc).first.id;
      var controller = await panel(tester, doc, id);
      await choose(tester, "teamSport", "Rugby league");
      expect(teamIn(controller, id).sport, TeamSport.rugbyLeague);
      expect(teamIn(controller, id).players, hasLength(13));
    });

    testWidgets("sets how the players look", (tester) async {
      var doc = footballCanvas();
      var id = _teams(doc).first.id;
      var controller = await panel(tester, doc, id);
      await choose(tester, "teamToken", "Portrait");
      expect(teamIn(controller, id).tokenStyle, TokenStyle.portrait);
      expect(find.byKey(const ValueKey("teamFaces")), findsOneWidget);
      await choose(tester, "teamKit", "Stripes");
      expect(teamIn(controller, id).kitPattern, KitPattern.stripes);
      var captain = find.byKey(ValueKey("captain-2-$id"));
      // The squad list is shut until it is opened.
      if (captain.evaluate().isEmpty) {
        var players = find.text("PLAYERS");
        await tester.ensureVisible(players);
        await tester.tap(players);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(captain);
      await tester.tap(captain);
      await tester.pumpAndSettle();
      expect(teamIn(controller, id).players[2].captain, isTrue);
    });

    testWidgets("designs the ball", (tester) async {
      var doc = footballCanvas();
      var id = _teams(doc).first.id;
      var controller = await panel(tester, doc, id);
      expect(find.byKey(const ValueKey("teamBallStyle")), findsNothing);
      var toggle = find.byKey(const ValueKey("teamBall"));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await choose(tester, "teamBallStyle", "Striped");
      expect(teamIn(controller, id).ballLook.style, BallStyle.striped);
      expect(find.byKey(const ValueKey("teamBallSecond")), findsOneWidget);
      var trail = find.byKey(const ValueKey("teamBallTrail"));
      await tester.ensureVisible(trail);
      await tester.tap(trail);
      await tester.pumpAndSettle();
      expect(teamIn(controller, id).ballLook.trail, isTrue);
      var shadow = find.byKey(const ValueKey("teamBallShadow"));
      await tester.ensureVisible(shadow);
      await tester.pumpAndSettle();
      await tester.tap(shadow);
      await tester.pumpAndSettle();
      expect(teamIn(controller, id).ballLook.shadow, isFalse);
    });

    testWidgets("names by position is a switch, both ways", (tester) async {
      var doc = footballCanvas();
      var named = _teams(doc).first;
      named = named.withPlayer(1, named.players[1].copyWith(name: "Smith"));
      doc = doc.copyWith(elements: [
        for (var e in doc.elements) e.id == named.id ? named : e,
      ]);
      var id = named.id;
      var controller = await panel(tester, doc, id);
      var button = find.byKey(const ValueKey("teamNameByPosition"));
      var name = teamIn(controller, id).players[1].name;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      var on = teamIn(controller, id);
      expect(on.namesByPosition, isTrue);
      expect(on.labelOf(on.players[1]), isNot(name));
      await tester.tap(button);
      await tester.pumpAndSettle();
      var off = teamIn(controller, id);
      expect(off.namesByPosition, isFalse);
      expect(off.labelOf(off.players[1]), name);
    });

    testWidgets("adds and takes away the ball", (tester) async {
      var doc = footballCanvas();
      var id = _teams(doc).first.id;
      var controller = await panel(tester, doc, id);
      var toggle = find.byKey(const ValueKey("teamBall"));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(teamIn(controller, id).ball, isNotNull);
      expect(find.text("11 players + ball"), findsOneWidget);
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(teamIn(controller, id).ball, isNull);
    });
  });
}

void _photoEditorTests() {
  testWidgets("the team photo zooms in, focuses a face, and drags about",
      (tester) async {
    late ui.Image photo;
    await tester.runAsync(() async => photo = await _squadPhoto());
    var team = _teams(footballCanvas())
        .first
        .copyWith(teamPhoto: "squad", tokenStyle: TokenStyle.portrait);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(
          body: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) => TeamPhotoEditor(
                team: team,
                images: _Images(photo),
                begin: () {},
                write: (t) => setState(() => team = t),
                commit: () {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var editor = find.byKey(const ValueKey("teamPhotoEditor"));
    var box = tester.getRect(editor);
    double zoomShown() => double.parse(tester
        .widget<EditableText>(find.descendant(
            of: find.byKey(const ValueKey("teamPhotoZoom")),
            matching: find.byType(EditableText)))
        .controller
        .text);
    expect(zoomShown(), 1);

    // Scrolling in over the photo zooms it.
    await tester.sendEventToBinding(PointerScrollEvent(
        position: box.center, scrollDelta: const Offset(0, -300)));
    await tester.pumpAndSettle();
    expect(zoomShown(), greaterThan(1.5));

    // The buttons: whole photo again, then focus on the chosen face.
    await tester.tap(find.byKey(const ValueKey("teamPhotoFit")));
    await tester.pumpAndSettle();
    expect(zoomShown(), 1);
    await tester.tap(find.byKey(const ValueKey("teamPhotoFocus")));
    await tester.pumpAndSettle();
    expect(zoomShown(), greaterThan(2));

    // Focused, the chosen face is in the middle: dragging from the middle
    // moves its circle -- and a short way, since the photo is magnified.
    var before = team.cropOf(0, 1.5);
    await tester.dragFrom(box.center, const Offset(40, 0));
    await tester.pumpAndSettle();
    var after = team.players[0].crop!;
    expect(after.x, greaterThan(before.x));
    expect((after.x - before.x) * 300, lessThan(25));

    // Dragging the photo off the circle pans it, and leaves every crop be.
    var crops = [for (var p in team.players) p.crop];
    await tester.dragFrom(
        box.topLeft + const Offset(10, 10), const Offset(30, 30));
    await tester.pumpAndSettle();
    expect([for (var p in team.players) p.crop], crops);
  });

  testWidgets("the team photo editor moves, sizes and turns a circle",
      (tester) async {
    late ui.Image photo;
    await tester.runAsync(() async => photo = await _squadPhoto());
    var team = _teams(footballCanvas())
        .first
        .copyWith(teamPhoto: "squad", tokenStyle: TokenStyle.portrait);
    var commits = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider(
        create: (_) => ThemeNotifier(doLoad: false),
        child: Scaffold(
          body: SizedBox(
            width: 300,
            child: StatefulBuilder(
              builder: (context, setState) => TeamPhotoEditor(
                team: team,
                images: _Images(photo),
                begin: () {},
                write: (t) => setState(() => team = t),
                commit: () => commits++,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    var editor = find.byKey(const ValueKey("teamPhotoEditor"));
    // The photo is 300 by 200, shown in the middle of the editor with room
    // round it for the handles.
    var box = tester.getRect(editor);
    var scale = (300 - 2 * teamPhotoMargin) / 300;
    var origin = box.center - const Offset(150, 100) * scale;
    Offset onScreen(PhotoCrop c) =>
        origin + Offset(c.x * 300, c.y * 200) * scale;

    // Dragged from inside: moved, by as far as the drag went.
    var start = team.cropOf(0, 1.5);
    await tester.dragFrom(onScreen(start), const Offset(30, 20));
    await tester.pumpAndSettle();
    var moved = team.players[0].crop!;
    expect(onScreen(moved).dx, closeTo(onScreen(start).dx + 30, 1));
    expect(onScreen(moved).dy, closeTo(onScreen(start).dy + 20, 1));
    expect(commits, 1);

    // The handle above it turns it.
    // Moving a circle does not fix its size: it still follows the team's.
    expect(moved.radius, isNull);
    var c = onScreen(moved);
    var r = team.cropOf(0, 1.5).size * 300 * scale;
    await tester.dragFrom(c + Offset(0, -r - 16), const Offset(40, 0));
    await tester.pumpAndSettle();
    var turned = team.players[0].crop!;
    expect(turned.turn, greaterThan(10));

    // The square on its edge sizes it -- turned with the circle.
    var t = turned.turn * math.pi / 180;
    await tester.dragFrom(
        c + Offset(math.cos(t), math.sin(t)) * r, const Offset(25, 25));
    await tester.pumpAndSettle();
    expect(team.players[0].crop!.radius, greaterThan(team.cropOf(5, 1.5).size));

    // Pressing on another circle and dragging moves that player's -- and
    // makes them the chosen one.
    var at = onScreen(team.cropOf(10, 1.5));
    await tester.dragFrom(at, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(team.players[10].crop, isNotNull);

    // The default size moves every circle nobody has sized, and not the
    // one that has been.
    var own = team.players[0].crop!.radius!;
    await enterValue(tester, 
        find.byKey(const ValueKey("teamPhotoDefaultSize")), "4");
    await tester.pumpAndSettle();
    expect(team.photoCropSize, closeTo(0.04, 1e-9));
    expect(team.cropOf(3, 1.5).size, closeTo(0.04, 1e-9));
    expect(team.cropOf(0, 1.5).size, own);
    // And the button beside it puts that one back to it too.
    await tester.tap(find.byKey(const ValueKey("teamPhotoSizesReset")));
    await tester.pumpAndSettle();
    expect(team.cropOf(0, 1.5).size, closeTo(0.04, 1e-9));
    expect(team.players[0].crop, isNotNull, reason: "kept where it was");

    // Reset puts the chosen one back where it started.
    await tester.tap(find.byKey(const ValueKey("teamPhotoReset")));
    await tester.pumpAndSettle();
    expect(team.players[10].crop, isNull);
    expect(team.players[0].crop, isNotNull);
  });
}

class _Images extends CanvasImageSource {
  final ui.Image image;
  _Images(this.image);
  @override
  ui.Image? resolve(String assetId, BackgroundRemoval removal) => image;
}

/// _squadPhoto is a stand-in for a squad photo: three rows of four faces,
/// each a different colour.
Future<ui.Image> _squadPhoto() async {
  var rec = ui.PictureRecorder();
  var c = ui.Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 300, 200),
      Paint()..color = const Color(0xFF203050));
  for (var i = 0; i < 12; i++) {
    c.drawCircle(Offset((i % 4 + 0.5) * 75, (i ~/ 4 + 0.4) * 66.7), 14,
        Paint()..color = HSVColor.fromAHSV(1, i * 30.0, 0.6, 0.9).toColor());
  }
  return rec.endRecording().toImage(300, 200);
}

Future<List<int>> _teamPixels(TeamElement team, CanvasImageSource src) async {
  var rec = ui.PictureRecorder();
  paintTeam(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 200, 120), team, 0,
      images: src);
  var image = await rec.endRecording().toImage(200, 120);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  return out;
}
