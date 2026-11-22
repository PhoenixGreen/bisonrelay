import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_library.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/controller/view_types.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';

// canvas_preferences_test.dart holds what CanvasPreferences keeps on a
// person's machine: the key each value is stored under and the form it is
// stored in. Changing either loses what somebody had set, so a change here
// should be a decision, not an accident.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// loaded is a fresh CanvasPreferences that has read [stored].
  Future<CanvasPreferences> loaded(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(
        {for (var e in stored.entries) "flutter.${e.key}": e.value});
    var prefs = CanvasPreferences();
    addTearDown(prefs.dispose);
    await prefs.load();
    return prefs;
  }

  test("with nothing stored, every value is the one it starts with", () async {
    var prefs = await loaded({});
    expect(prefs.enabled, isFalse);
    expect(prefs.allowFetching, isFalse);
    expect(prefs.menuHidden, isFalse);
    expect(prefs.lastFolder, "");
    expect(prefs.lastName, "");
    expect(prefs.filesFolder, "");
    expect(prefs.fit, CanvasFit.whole);
    expect(prefs.canvasView("a/b"), isNull);
    expect(prefs.sidebars.current, "files");
    expect(prefs.sidebarAboveWidth, 0);
    expect(prefs.dock, const DockLayout());
    expect(prefs.dockLower, 0);
    expect(prefs.dockAbove, 0);
    expect(prefs.dockLeft, 0);
    expect(prefs.panels, isEmpty);
    expect(prefs.timeline, isFalse);
    expect(prefs.cuesShown, isTrue);
    expect(prefs.mixerBands, isEmpty);
    expect(prefs.mixerLook, "");
    expect(prefs.returnsShown, isTrue);
    expect(prefs.timelineSnap, isFalse);
    expect(prefs.timelineTrackpad, isFalse);
    expect(prefs.barBelow, isFalse);
    expect(prefs.studioLook, StudioLook.studio);
    expect(prefs.studioOverrides, isEmpty);
    expect(prefs.publish, isEmpty);
    for (var kind in AssetKind.values) {
      expect(prefs.assetView(kind),
          kind == AssetKind.audio ? AssetView.list : AssetView.icons,
          reason: kind.name);
    }
    expect(prefs.stockLibrary, StockLibrary.initial);
    expect(prefs.stockFilters, isEmpty);
    // As a new canvas has always shown them: the switch on, no edge chosen.
    expect(prefs.rulers, const CanvasRulers());
    expect(prefs.rulers.shown, isTrue);
    expect(prefs.rulers.any, isFalse);
  });

  test("each value is read from its key, in the form it was stored", () async {
    var role = StudioRole.values.first;
    var prefs = await loaded({
      "canvasEnabled": true,
      "canvasAllowFetching": true,
      "canvasMenuHidden": true,
      "canvasLastFolder": "Books",
      "canvasLastName": "Piano",
      "canvasFilesFolder": "Books",
      "canvasFit": "width",
      "canvasViews": jsonEncode({
        "Books/Piano": {"zoom": 2}
      }),
      "canvasSidebars":
          jsonEncode(const SidebarLayout(current: "design").toJson()),
      "canvasSidebarAboveWidth": "310.5",
      "canvasDock": jsonEncode(const DockLayout().toJson()),
      "canvasDockLower": "220.0",
      "canvasDockAbove": "180.0",
      "canvasDockLeft": "140.0",
      "canvasPanels": jsonEncode({"mixer": true}),
      "canvasTimeline": true,
      "canvasCuesShown": false,
      "canvasMixerBands": "shown,minimised,hidden",
      "canvasMixerLook": "wide",
      "canvasReturnsShown": false,
      // Under the keys the play bar wrote them to itself.
      "canvasTimelineSnap": true,
      "canvasTimelineTrackpad": true,
      "canvasTimelineBarBelow": true,
      "canvasStudioLook": "theme",
      "canvasStudioColours": jsonEncode({role.name: 0xFF102030}),
      "canvasPublish": jsonEncode({"format": "png"}),
      "canvasAssetViews": jsonEncode({"audio": "icons", "picture": "list"}),
      "canvasStockLibrary": "browser:characters",
      "canvasStockFilters": jsonEncode({
        "freesound": {"license": "cc0"},
        "gone": {"license": "any"},
      }),
      "canvasRulers": '{"hidden":true,"t":true,"l":true}',
    });
    expect(prefs.enabled, isTrue);
    expect(prefs.allowFetching, isTrue);
    expect(await CanvasPreferences.fetchingAllowed(), isTrue);
    expect(prefs.menuHidden, isTrue);
    expect(prefs.lastFolder, "Books");
    expect(prefs.lastName, "Piano");
    expect(prefs.filesFolder, "Books");
    expect(prefs.fit, CanvasFit.width);
    expect(prefs.canvasView("Books/Piano"), {"zoom": 2});
    expect(prefs.sidebars.current, "design");
    expect(prefs.sidebarAboveWidth, 310.5);
    expect(prefs.dock, const DockLayout());
    expect(prefs.dockLower, 220);
    expect(prefs.dockAbove, 180);
    expect(prefs.dockLeft, 140);
    expect(prefs.panels, {"mixer": true});
    expect(prefs.timeline, isTrue);
    expect(prefs.cuesShown, isFalse);
    expect(prefs.mixerBands, ["shown", "minimised", "hidden"]);
    expect(prefs.mixerLook, "wide");
    expect(prefs.returnsShown, isFalse);
    expect(prefs.timelineSnap, isTrue);
    expect(prefs.timelineTrackpad, isTrue);
    expect(prefs.barBelow, isTrue);
    expect(prefs.studioLook, StudioLook.theme);
    expect(prefs.studioOverrides, {role: const Color(0xFF102030)});
    expect(prefs.publish, {"format": "png"});
    expect(prefs.assetView(AssetKind.audio), AssetView.icons);
    expect(prefs.assetView(AssetKind.picture), AssetView.list);
    expect(prefs.assetView(AssetKind.video), AssetView.icons);
    expect(
        prefs.stockLibrary, const StockBrowserLibrary(StockBrowser.characters));
    expect(
        prefs.stockFilters,
        {
          StockSource.freesound: {"license": "cc0"},
        },
        reason: "a source this build does not know is passed by");
    expect(
        prefs.rulers, const CanvasRulers(shown: false, top: true, left: true));
  });

  test("a stock source is stored by its name, a browser apart from them",
      () async {
    for (var library in StockLibrary.all) {
      expect(StockLibrary.fromName(library.name), library,
          reason: library.name);
    }
    expect(
        const StockSourceLibrary(StockSource.nounProject).name, "nounProject");
    expect(const StockBrowserLibrary(StockBrowser.characters).name,
        "browser:characters");
    // Saved by an earlier build, before browsers were kept apart.
    expect(StockLibrary.fromName("characters"), StockLibrary.initial);
    expect(StockLibrary.fromName("browser:gone"), StockLibrary.initial);
    expect(StockLibrary.fromName(null), StockLibrary.initial);
  });

  test("a value set is stored at once and read back by the next session",
      () async {
    var role = StudioRole.values.last;
    var prefs = await loaded({});
    prefs.enabled = true;
    prefs.remember("Books", "Piano");
    prefs.fit = CanvasFit.width;
    prefs.setCanvasView("Books/Piano", {"zoom": 3});
    prefs.sidebars = const SidebarLayout(current: "assets");
    prefs.panels = {"timeline": true};
    prefs.mixerBands = ["shown", "hidden"];
    prefs.studioLook = StudioLook.theme;
    prefs.setStudioColour(role, const Color(0xFF445566));
    prefs.publish = {"format": "gif"};
    prefs.setAssetView(AssetKind.picture, AssetView.list);
    prefs.stockLibrary = const StockSourceLibrary(StockSource.jamendo);
    prefs.setStockFilter(StockSource.jamendo, "order", "popular");
    prefs.setStockFilter(StockSource.jamendo, "speed", "high");
    prefs.rulers = const CanvasRulers(top: true, right: true);
    prefs.timelineSnap = true;
    prefs.timelineTrackpad = true;
    prefs.barBelow = true;

    var stored = await SharedPreferences.getInstance();
    expect(stored.getString("canvasAssetViews"), '{"picture":"list"}');
    expect(stored.getString("canvasStockLibrary"), "jamendo");
    expect(stored.getString("canvasStockFilters"),
        '{"jamendo":{"order":"popular","speed":"high"}}');
    expect(stored.getString("canvasRulers"), '{"t":true,"r":true}');
    expect(stored.getBool("canvasTimelineSnap"), isTrue);
    expect(stored.getBool("canvasTimelineTrackpad"), isTrue);
    expect(stored.getBool("canvasTimelineBarBelow"), isTrue);

    var next = CanvasPreferences();
    addTearDown(next.dispose);
    await next.load();
    expect(next.enabled, isTrue);
    expect(next.lastFolder, "Books");
    expect(next.lastName, "Piano");
    expect(next.fit, CanvasFit.width);
    expect(next.canvasView("Books/Piano"), {"zoom": 3});
    expect(next.sidebars.current, "assets");
    expect(next.panels, {"timeline": true});
    expect(next.mixerBands, ["shown", "hidden"]);
    expect(next.studioLook, StudioLook.theme);
    expect(next.studioOverrides, {role: const Color(0xFF445566)});
    expect(next.publish, {"format": "gif"});
    expect(next.assetView(AssetKind.picture), AssetView.list);
    expect(next.assetView(AssetKind.audio), AssetView.list);
    expect(next.stockLibrary, const StockSourceLibrary(StockSource.jamendo));
    expect(next.stockFilters, {
      StockSource.jamendo: {"order": "popular", "speed": "high"},
    });
    expect(next.rulers, const CanvasRulers(top: true, right: true));
    expect(next.timelineSnap, isTrue);
    expect(next.timelineTrackpad, isTrue);
    expect(next.barBelow, isTrue);

    next.clearStudioColours();
    var last = CanvasPreferences();
    addTearDown(last.dispose);
    await last.load();
    expect(last.studioOverrides, isEmpty);
  });

  test("a dragged size is stored once the drag has paused, or on dispose",
      () async {
    SharedPreferences.setMockInitialValues({});
    var prefs = CanvasPreferences();
    prefs.dockLower = 200;
    prefs.dockLower = 240.26;
    await pumpEventQueue();
    var stored = await SharedPreferences.getInstance();
    expect(stored.containsKey("canvasDockLower"), isFalse,
        reason: "not written at every step of a drag");
    prefs.dispose();
    await pumpEventQueue();
    expect(stored.getString("canvasDockLower"), "240.3");
  });

  test("only the forty canvases looked at last keep their view", () async {
    var prefs = await loaded({});
    for (var i = 0; i < 45; i++) {
      prefs.setCanvasView("folder/$i", {"zoom": i});
    }
    expect(prefs.canvasView("folder/4"), isNull);
    expect(prefs.canvasView("folder/5"), {"zoom": 5});
    expect(prefs.canvasView("folder/44"), {"zoom": 44});
  });

  test("something unreadable under a key leaves the value as it starts",
      () async {
    var prefs = await loaded({
      "canvasSidebars": "not json",
      "canvasDock": "{",
      "canvasPanels": "[1, 2]",
      "canvasViews": "7",
      "canvasStudioColours": "\"red\"",
      "canvasDockLower": "tall",
      "canvasStudioLook": "neon",
      "canvasAssetViews": "[\"list\"]",
      "canvasStockLibrary": "neon",
      "canvasStockFilters": "{",
      "canvasRulers": "[true]",
    });
    expect(prefs.sidebars.current, "files");
    expect(prefs.dock, const DockLayout());
    expect(prefs.panels, isEmpty);
    expect(prefs.canvasView("a/b"), isNull);
    expect(prefs.studioOverrides, isEmpty);
    expect(prefs.dockLower, 0);
    expect(prefs.studioLook, StudioLook.studio);
    expect(prefs.assetView(AssetKind.picture), AssetView.icons);
    expect(prefs.assetView(AssetKind.audio), AssetView.list);
    expect(prefs.stockLibrary, StockLibrary.initial);
    expect(prefs.stockFilters, isEmpty);
    expect(prefs.rulers, const CanvasRulers());
  });

  test("the rulers are stored as what differs from none, each edge alone",
      () async {
    // One value for the switch and the four edges, so they are read and
    // written together; a field left out is as a new one has it.
    var alone = <String, CanvasRulers>{
      '{"hidden":true}': const CanvasRulers(shown: false),
      '{"t":true}': const CanvasRulers(top: true),
      '{"l":true}': const CanvasRulers(left: true),
      '{"r":true}': const CanvasRulers(right: true),
      '{"b":true}': const CanvasRulers(bottom: true),
    };
    for (var MapEntry(key: stored, value: rulers) in alone.entries) {
      expect(jsonEncode(rulers.toJson()), stored);
      var prefs = await loaded({"canvasRulers": stored});
      expect(prefs.rulers, rulers, reason: stored);
    }
    expect(const CanvasRulers().toJson(), isEmpty);
    expect(const CanvasRulers(top: true).drawn, isTrue);
    expect(const CanvasRulers(top: true, shown: false).drawn, isFalse,
        reason: "hidden without forgetting the edge");
    expect(const CanvasRulers().drawn, isFalse, reason: "shown, but no edge");
  });

  test("only what the menu, Settings or the app's frame shows notifies",
      () async {
    var prefs = await loaded({});
    var heard = 0;
    prefs.addListener(() => heard++);

    prefs.fit = CanvasFit.width;
    prefs.filesFolder = "Books";
    prefs.dockLower = 200;
    prefs.cuesShown = false;
    prefs.remember("Books", "Piano");
    prefs.setAssetView(AssetKind.video, AssetView.list);
    prefs.stockLibrary = const StockBrowserLibrary(StockBrowser.kenney);
    prefs.setStockFilter(StockSource.freesound, "license", "cc0");
    prefs.rulers = const CanvasRulers(top: true);
    expect(heard, 0);

    prefs.enabled = true;
    prefs.allowFetching = true;
    prefs.menuHidden = true;
    prefs.timeline = true;
    prefs.studioLook = StudioLook.theme;
    expect(heard, 5);

    prefs.enabled = true;
    expect(heard, 5, reason: "set to what it is already");
  });
}
