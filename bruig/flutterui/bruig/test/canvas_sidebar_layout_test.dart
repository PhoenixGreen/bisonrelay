import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';

// canvas_sidebar_layout_test.dart is how the sidebars are set out: panels
// moved between them, hidden and put back, sidebars added, removed and put
// back, and a saved arrangement that does not add up put right.

/// everywhere is every panel [l] has, in a sidebar or hidden, by name.
List<String> everywhere(SidebarLayout l) => [
      for (var s in l.sidebars)
        for (var p in s.panels) p.name,
      for (var p in l.hidden) p.name,
    ];

/// _all is every panel there is, by name.
List<String> _all() => [for (var p in SidebarPanel.values) p.name]..sort();

void main() {
  test("every panel is somewhere, once, to begin with", () {
    const l = SidebarLayout();
    expect(everywhere(l)..sort(), _all());
    expect(l.byId("files")!.panels, [SidebarPanel.files, SidebarPanel.presets]);
  });

  test("a panel moves between sidebars, but not into Files or out of it", () {
    var l = const SidebarLayout().movePanel(SidebarPanel.layers, "assets");
    expect(l.sidebarOf(SidebarPanel.layers)!.id, "assets");
    expect(l.byId("design")!.panels, isNot(contains(SidebarPanel.layers)));
    expect(
        l
            .movePanel(SidebarPanel.layers, "files")
            .sidebarOf(SidebarPanel.layers)!
            .id,
        "assets");
    expect(
        l
            .movePanel(SidebarPanel.presets, "design")
            .sidebarOf(SidebarPanel.presets)!
            .id,
        "files");
  });

  test("a sidebar's panels follow the order its stack has them in", () {
    const l = SidebarLayout();
    var moved = l.withPanelOrder("design", [
      SidebarPanel.layers,
      SidebarPanel.add,
      // Not the Design sidebar's: passed by.
      SidebarPanel.stock,
    ]);
    expect(moved.byId("design")!.panels, [
      SidebarPanel.layers,
      SidebarPanel.add,
      // Those the order does not name stay, after, as they were.
      SidebarPanel.scenes,
      SidebarPanel.vocalCues,
      SidebarPanel.colour,
      SidebarPanel.settings,
    ]);
    expect(moved.byId("assets")!.panels, l.byId("assets")!.panels);
    expect(identical(l.withPanelOrder("design", l.byId("design")!.panels), l),
        isTrue,
        reason: "nothing moved: the same layout");
    expect(identical(l.withPanelOrder("nonsense", const []), l), isTrue);
  });

  test("hidden, a panel remembers where it was, and goes back there", () {
    var l = const SidebarLayout().hidePanel(SidebarPanel.colour);
    expect(l.hidden, [SidebarPanel.colour]);
    expect(l.sidebarOf(SidebarPanel.colour), isNull);
    l = l.restorePanel(SidebarPanel.colour);
    expect(l.sidebarOf(SidebarPanel.colour)!.id, "design");
    expect(l.hidden, isEmpty);
    expect(
        const SidebarLayout().hidePanel(SidebarPanel.settings).hidden, isEmpty,
        reason: "the settings always stay");
    expect(const SidebarLayout().hidePanel(SidebarPanel.files).hidden, isEmpty);
    expect(const SidebarLayout().hidePanel(SidebarPanel.presets).hidden,
        [SidebarPanel.presets]);
  });

  test("a sidebar added, removed and put back with its panels", () {
    var l = const SidebarLayout()
        .addSidebar(name: "Colour", panel: SidebarPanel.colour);
    var mine = l.sidebars.last;
    expect(mine.panels, [SidebarPanel.colour]);
    expect(l.current, mine.id);
    l = l.removeSidebar(mine.id);
    expect(l.byId(mine.id), isNull);
    expect(l.hidden, [SidebarPanel.colour]);
    expect(l.removed.single.name, "Colour");
    l = l.restoreSidebar(mine.id);
    expect(l.byId(mine.id)!.panels, [SidebarPanel.colour]);
    expect(l.removed, isEmpty);
  });

  test("removing the sidebar the settings are in moves them, not hides them",
      () {
    var l = const SidebarLayout().removeSidebar("design");
    expect(l.sidebarOf(SidebarPanel.settings)!.id, "assets");
    expect(
        l.hidden,
        containsAll(
            [SidebarPanel.add, SidebarPanel.layers, SidebarPanel.colour]));
    expect(l.removeSidebar("files").byId("files"), isNotNull,
        reason: "Files stays");
  });

  test("a sidebar moves along the row", () {
    var l = const SidebarLayout().moveSidebar("design", 2);
    expect([for (var s in l.sidebars) s.id],
        ["files", "assets", "design", "game"]);
    l = l.moveSidebar("game", 0);
    expect(l.sidebars.first.id, "game");
    expect(l.moveSidebar("nonsense", 1).toJson(), l.toJson());
  });

  test("kept and read back as it was", () {
    var l = const SidebarLayout()
        .withMode(SidebarMode.above)
        .addSidebar(name: "Mine", panel: SidebarPanel.stock)
        .hidePanel(SidebarPanel.colour);
    var back = SidebarLayout.fromJson(jsonDecode(jsonEncode(l.toJson())));
    expect(back.toJson(), l.toJson());
    expect(back.mode, SidebarMode.above);
  });

  test("an arrangement that does not add up is put right", () {
    var l = SidebarLayout.fromJson({
      "sidebars": [
        {
          "id": "design",
          "name": "Design",
          "icon": "design",
          "panels": ["add", "add", "files", "nonsense", "settings"]
        },
        {
          "id": "mine",
          "name": "",
          "icon": "?",
          "panels": ["layers"]
        },
      ],
      "hidden": ["settings", "colour"],
    });
    expect(everywhere(l)..sort(), _all(),
        reason: "every panel once, new ones where they start");
    expect(l.byId("files")!.panels, contains(SidebarPanel.files));
    expect(l.byId("design")!.panels.where((p) => p == SidebarPanel.add),
        hasLength(1));
    expect(l.hidden, [SidebarPanel.colour],
        reason: "the settings cannot be hidden");
    expect(l.byId("mine")!.name, "Sidebar");
    expect(l.byId("game"), isNotNull);
    expect(SidebarLayout.fromJson("junk").toJson(),
        const SidebarLayout().toJson());
  });

  test("hidden, it is shown again the way it was", () {
    var l = const SidebarLayout()
        .withMode(SidebarMode.above)
        .withMode(SidebarMode.hidden);
    expect(l.mode, SidebarMode.hidden);
    expect(l.shownAgain.mode, SidebarMode.above);
  });

  test("what may go where, and what may be hidden, is the panel's to say", () {
    var files = const SidebarLayout().byId(SidebarSet.filesId)!;
    var game = const SidebarLayout().byId(SidebarSet.gameId)!;
    var design = const SidebarLayout().byId("design")!;
    for (var panel in SidebarPanel.values) {
      var into = [
        for (var s in [files, game, design])
          if (SidebarLayout.canGoIn(panel, s)) s.id
      ];
      expect(into, [panel.only ?? "design"], reason: panel.name);
      expect(const SidebarLayout().hidePanel(panel).hidden,
          panel.canHide ? [panel] : isEmpty,
          reason: panel.name);
    }
    expect([
      for (var p in SidebarPanel.values)
        if (!p.canHide) p
    ], [
      SidebarPanel.files,
      SidebarPanel.settings,
      SidebarPanel.game
    ]);
  });

  test("every kind of asset in the library has a panel, under its name", () {
    // The panels are in the model, which cannot see the library's kinds: a
    // kind added there is given a panel here by hand, and this says so.
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    for (var kind in AssetKind.values) {
      var panel = SidebarPanel.fromName(kind.name);
      expect(panel, isNotNull, reason: "no panel for ${kind.name}");
      expect(panel!.title, kind.label);
      expect(canvasSidebarPanel(panel, controller, const SizedBox()).icon,
          assetKindIcon(kind));
    }
  });

  test("a panel is headed for the canvas; its title does not change", () {
    var controller = CanvasController(const CanvasDocument());
    addTearDown(controller.dispose);
    String heading(SidebarPanel panel) =>
        canvasSidebarPanel(panel, controller, const SizedBox()).label;
    expect(heading(SidebarPanel.settings), isNot("Settings"),
        reason: "named for what is selected");
    expect(SidebarPanel.settings.title, "Settings");
    for (var panel in SidebarPanel.values) {
      expect(canvasSidebarPanel(panel, controller, const SizedBox()).id,
          panel.name,
          reason: "the stack keeps what it remembers under the panel's name");
    }
  });
}
