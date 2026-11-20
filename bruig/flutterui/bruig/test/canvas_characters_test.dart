import 'dart:io';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/drawn_characters.dart';
import 'package:bruig/plugin_system/canvas/presets/drawn_styles.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kaykit_packs.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/character_browser.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/kaykit_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/canvas_app.dart';

// canvas_characters_test.dart covers the characters added to the Stock
// panel: people drawn here from CC0 styles' parts, and KayKit's 3D
// characters, offered to download with the room they take said first.

void main() {
  var styles = readDrawnStyles(File(drawnStylesAsset).readAsBytesSync());

  test("the four styles come with the app, each credited", () {
    expect(styles.keys,
        containsAll(["open-peeps", "notionists", "lorelei", "pixel-art"]));
    for (var s in styles.values) {
      expect(s.licence, "CC0 1.0", reason: s.id);
      expect(s.creator, isNotEmpty);
      expect(s.groups, isNotEmpty, reason: s.id);
      for (var g in s.groups) {
        expect(s.choices(g), isNotEmpty, reason: "${s.id} $g");
      }
    }
  });

  test("a character is a whole SVG, the same from the same seed", () {
    for (var s in styles.values) {
      var a = randomCharacter(s, math.Random(3));
      var b = randomCharacter(s, math.Random(3));
      expect(drawnSvg(s, a), drawnSvg(s, b), reason: s.id);
      var svg = drawnSvg(s, a);
      expect(svg, startsWith("<svg xmlns"));
      expect(svg, isNot(contains("{{")), reason: "every place filled");
      expect(svg, isNot(contains("<script")));
    }
    // A part left out leaves no trace; a colour that is none says so.
    var peeps = styles["open-peeps"]!;
    var bare = randomCharacter(peeps, math.Random(1))
        .withPart("accessories", null)
        .withColour("clothing", "transparent");
    expect(drawnSvg(peeps, bare), contains('fill="none"'));
    expect(drawnSvg(peeps, bare.withPart("accessories", "eyepatch")).length,
        greaterThan(drawnSvg(peeps, bare).length));
  });

  test("the room left is read from df on macOS and Linux alike", () {
    const mac = "Filesystem   1024-blocks      Used Available Capacity iused "
        "ifree %iused  Mounted on\n/dev/disk3s5  239362496 200000000 "
        "28311552    88%  1 2  1%   /System/Volumes/Data\n";
    expect(freeBytesFromDf(mac), 28311552 * 1024);
    const linux =
        "Filesystem     1K-blocks     Used Available Use% Mounted on\n"
        "/dev/sda1      102400000 51200000  51200000  50% /\n";
    expect(freeBytesFromDf(linux), 51200000 * 1024);
    expect(freeBytesFromDf("nonsense"), isNull);
  });

  test("KayKit's packs are pinned, so the sizes said are the sizes fetched",
      () {
    for (var p in kayKitPacks) {
      expect(p.commit, matches(RegExp(r"^[0-9a-f]{40}$")));
      for (var c in p.characters) {
        expect(p.url(c), contains("/${p.commit}/"));
        expect(p.url(c), endsWith(".glb"));
      }
      expect(p.bytes, greaterThan(10 << 20));
    }
    expect(megabytes(18975976), "18.1 MB");
  });

  group("in the Stock panel", () {
    late Directory root;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      root = Directory.systemTemp.createTempSync("characters");
      CanvasStorage.rootOverride = root.path;
      CanvasLibrary.resetForTest();
    });
    tearDown(() {
      CanvasStorage.rootOverride = null;
      root.deleteSync(recursive: true);
    });

    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
    }

    Future<void> tap(WidgetTester tester, String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await idle(tester);
    }

    testWidgets("a character is chosen, made over, and put on the canvas",
        (tester) async {
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      setTestScreen(tester, const Size(500, 2400));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 360,
          child:
              SingleChildScrollView(child: CharacterBrowser(controller: c)))));
      await idle(tester);
      expect(find.byKey(const ValueKey("characterTiles")), findsOneWidget);
      await tap(tester, "character-0");
      expect(find.byKey(const ValueKey("characterMaking")), findsOneWidget);

      var part = tester.widget<CanvasDropdown<String>>(
          find.byKey(const ValueKey("characterPart-accessories")));
      part.onChanged("sunglasses");
      await idle(tester);

      await tap(tester, "characterAdd");
      for (var i = 0; i < 20 && c.document.elements.isEmpty; i++) {
        await idle(tester);
      }
      expect(c.document.elements.single.kind, ElementKind.vector);
      var kept = (await tester
              .runAsync(() => CanvasLibrary.list(kind: AssetKind.vector)))!
          .single;
      expect(kept.author, "Pablo Stanley");
      expect(kept.license, "CC0 1.0");
      expect(tester.takeException(), isNull);
    });

    testWidgets("KayKit says its size, and fetches nothing unless allowed",
        (tester) async {
      // df runs outside the test's clock: the room is said here instead.
      KayKitBrowser.freeSpace = (_) async => 5 << 30;
      addTearDown(() => KayKitBrowser.freeSpace = freeBytesAt);
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      setTestScreen(tester, const Size(500, 2400));
      await tester.pumpWidget(canvasApp(SizedBox(
          width: 360,
          child: SingleChildScrollView(child: KayKitBrowser(controller: c)))));
      await idle(tester);
      expect(find.textContaining("Download (17.2 MB)"), findsOneWidget);
      var room = find.textContaining("Room on this computer: 5.0 GB");
      for (var i = 0; i < 20 && room.evaluate().isEmpty; i++) {
        await idle(tester);
      }
      expect(room, findsOneWidget);
      await tap(tester, "kayKitDownload-adventurers");
      expect(find.textContaining("Fetching is switched off"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
