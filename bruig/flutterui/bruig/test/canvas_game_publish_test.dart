import 'dart:convert';

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/export/canvas_export.dart';
import 'package:bruig/plugin_system/canvas/export/game_publish.dart';
import 'package:bruig/plugin_system/canvas/export/publish_targets.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/game_embed.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_game_publish_test.dart is a game published from Canvas: the bundle
// and its cover carried in an embed, drawn in a post as a cover with Play,
// and played there by the same engine (the GamePublished board, approved
// 2026-10-31).

ShapeElement _box(String id, double x, double y, double w, double h,
        {PlaySpec play = const PlaySpec()}) =>
    ShapeElement(
        ElementBase(id: id, x: x, y: y, width: w, height: h, play: play));

CounterElement _hud(String count) =>
    CounterElement(ElementBase(id: "hud-$count", width: 120, height: 50),
        source: CounterSource.game, gameCount: count, keyed: false);

CanvasDocument _game() => CanvasDocument(
        title: "Tiny Isle",
        game: true,
        masterOn: true,
        masterOver: true,
        master: CanvasScene(id: "m", elements: [_hud("coins")]),
        counts: const [
          GameCount("coins", "Coins")
        ],
        scenes: [
          CanvasScene(id: "one", name: "One", elements: [
            _box("hero", 100, 600, 40, 60,
                play: const PlaySpec(as: PlayAs.platformer)),
            // On the floor -- the canvas's bottom -- in the hero's way.
            _box("coin", 300, 680, 30, 30,
                play: const PlaySpec(
                    as: PlayAs.pickup,
                    touched: GameEffect(does: GameDoes.add, count: "coins"))),
            _hud("coins"),
          ]),
        ]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test("its options travel in the embed, and come back", () {
    var o = const GamePublishOptions(howTo: false, best: true, open: true);
    var back = GamePublishOptions.fromParams(o.params);
    expect((back.howTo, back.best, back.open), (false, true, true));
    var export = CanvasExport(Uint8List.fromList([1, 2, 3]), gameMime,
        width: 10,
        height: 10,
        cover: Uint8List.fromList([9]),
        params: o.params);
    var markup = embedMarkupFor(export);
    expect(markup, startsWith("--embed[type=$gameMime,data=AQID,cover=CQ=="));
    expect(markup, contains(",howto=0"));
    expect(markup, endsWith("]--"));
  });

  test("without its HUD, the Counters showing its counts are left out", () {
    var doc = _game();
    var kept = gameDocument(doc, const GamePublishOptions());
    expect(identical(kept, doc), isTrue);
    var bare = gameDocument(doc, const GamePublishOptions(hud: false));
    expect(bare.master!.elements, isEmpty);
    expect(bare.allScenes.single.elements.map((e) => e.id), ["hero", "coin"]);
  });

  testWidgets("published: the bundle, a cover, its name", (tester) async {
    var export = (await tester
        .runAsync(() => exportGame(_game(), const GamePublishOptions())))!;
    expect(export.mime, gameMime);
    expect(export.cover, isNotNull, reason: "its first frame");
    expect(Uri.decodeComponent(export.params["name"]!), "Tiny Isle");
    var bundle = (await tester.runAsync(() => unpackCanvas(export.data)))!;
    expect(bundle.document.game, isTrue);
    expect(bundle.document.allScenes.single.elements, hasLength(3));
    expect(extensionFor(gameMime), ".bcanvas",
        reason: "saved to a file, it opens as a canvas");
  });

  testWidgets("in a post: drawn as a cover with Play, not as nothing",
      (tester) async {
    var mk = MarkdownAreaModel("/tmp");
    mk.setPluginExtensions(canvasMarkdownExtensions());
    var data = base64Encode(utf8.encode(_game().encode()));
    var src = "A game:\n\n--embed[type=$gameMime,data=$data,"
        "name=Tiny%20Isle,howto=1,best=1,open=0,"
        "keys=${Uri.encodeComponent("Arrows move · Space jumps")}]--\n";
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<MarkdownAreaModel>.value(value: mk),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      SizedBox(width: 700, child: MarkdownArea(src, false))))),
    ));
    await tester.pump();
    var embed = tester.widget<GameEmbed>(find.byType(GameEmbed));
    expect(embed.data, data);
    expect(embed.params["name"], "Tiny%20Isle");
    expect(find.text("TINY ISLE"), findsOneWidget);
    expect(find.text("Arrows move · Space jumps"), findsOneWidget);
    expect(find.byKey(const ValueKey("gameEmbedPlay")), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("played: keys move it, P holds it, Esc leaves with the best",
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    int? given;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
      ],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          given = await Navigator.of(context).push<int>(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      GamePlayer(document: _game())));
                        },
                        child: const Text("go")),
                  ))),
    ));
    await tester.tap(find.text("go"));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey("gamePlayerCanvas")), findsOneWidget);
    expect(find.byKey(const ValueKey("gamePlayerOpen")), findsNothing,
        reason: "not let open");
    // Run right, onto the coin.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    // The game times itself by the wall clock: real time, between frames.
    for (var i = 0; i < 60; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 17)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text("Paused"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("gamePlayerResume")));
    await tester.pump();
    expect(find.text("Paused"), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(GamePlayer), findsNothing);
    expect(given, 1, reason: "the coin taken");
    expect(tester.takeException(), isNull);
  });
}
