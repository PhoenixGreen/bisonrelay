import 'dart:convert';

import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_sidebar_layout_test.dart is how the sidebars are set out: panels
// moved between them, hidden and put back, sidebars added, removed and put
// back, and a saved arrangement that does not add up put right.

List<String> everywhere(SidebarLayout l) =>
    [for (var s in l.sidebars) ...s.panels, ...l.hidden];

void main() {
  test("every panel is somewhere, once, to begin with", () {
    const l = SidebarLayout();
    expect(everywhere(l)..sort(), [...sidebarPanelIds]..sort());
    expect(l.byId("files")!.panels, ["files", "presets"]);
  });

  test("a panel moves between sidebars, but not into Files or out of it", () {
    var l = const SidebarLayout().movePanel("layers", "assets");
    expect(l.sidebarOf("layers")!.id, "assets");
    expect(l.byId("design")!.panels, isNot(contains("layers")));
    expect(l.movePanel("layers", "files").sidebarOf("layers")!.id, "assets");
    expect(l.movePanel("presets", "design").sidebarOf("presets")!.id, "files");
  });

  test("hidden, a panel remembers where it was, and goes back there", () {
    var l = const SidebarLayout().hidePanel("colour");
    expect(l.hidden, ["colour"]);
    expect(l.sidebarOf("colour"), isNull);
    l = l.restorePanel("colour");
    expect(l.sidebarOf("colour")!.id, "design");
    expect(l.hidden, isEmpty);
    expect(const SidebarLayout().hidePanel("settings").hidden, isEmpty,
        reason: "the settings always stay");
    expect(const SidebarLayout().hidePanel("files").hidden, isEmpty);
    expect(const SidebarLayout().hidePanel("presets").hidden, ["presets"]);
  });

  test("a sidebar added, removed and put back with its panels", () {
    var l = const SidebarLayout().addSidebar(name: "Colour", panel: "colour");
    var mine = l.sidebars.last;
    expect(mine.panels, ["colour"]);
    expect(l.current, mine.id);
    l = l.removeSidebar(mine.id);
    expect(l.byId(mine.id), isNull);
    expect(l.hidden, ["colour"]);
    expect(l.removed.single.name, "Colour");
    l = l.restoreSidebar(mine.id);
    expect(l.byId(mine.id)!.panels, ["colour"]);
    expect(l.removed, isEmpty);
  });

  test("removing the sidebar the settings are in moves them, not hides them",
      () {
    var l = const SidebarLayout().removeSidebar("design");
    expect(l.sidebarOf("settings")!.id, "assets");
    expect(l.hidden, containsAll(["add", "layers", "colour"]));
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
        .addSidebar(name: "Mine", panel: "stock")
        .hidePanel("colour");
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
    expect(everywhere(l)..sort(), [...sidebarPanelIds]..sort(),
        reason: "every panel once, new ones where they start");
    expect(l.byId("files")!.panels, contains("files"));
    expect(l.byId("design")!.panels.where((p) => p == "add"), hasLength(1));
    expect(l.hidden, ["colour"], reason: "the settings cannot be hidden");
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
}
