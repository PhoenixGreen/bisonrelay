// sidebar_layout.dart is how the Canvas sidebar is set out: hidden, beside
// everything or over the panels under the canvas; which sidebars there are
// and which panels each holds. Kept in CanvasPreferences.sidebars. Every
// panel appears once: in a sidebar, or hidden, remembering where it came
// from. Files holds only files and presets; Game only the game's settings,
// shown for a game. The files and the selection's settings are never hidden.

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

/// SidebarMode is the sidebar hidden, beside everything at full height, or
/// over the panels under the canvas, which then have the whole width.
enum SidebarMode {
  hidden("Hidden"),
  full("Full height"),
  above("Above the bottom panels");

  final String label;
  const SidebarMode(this.label);

  static SidebarMode fromName(Object? name) =>
      values.where((m) => m.name == name).firstOrNull ?? full;
}

/// SidebarPanel is a panel a sidebar can hold. Its name is how it is kept
/// (in CanvasPreferences.sidebars, and in the panel stacks' own keys).
///
/// To add one: a value here, in one of [defaultSidebars]; then its heading
/// and its body in ui/sidebar/sidebar_panels.dart, where the compiler asks
/// for both.
enum SidebarPanel {
  files("Files", only: SidebarSet.filesId, canHide: false),
  presets("Presets", only: SidebarSet.filesId),
  add("Add"),

  /// scenes is headed for what the canvas has: scenes, pages, or the
  /// sections of a piece of sound.
  scenes("Scenes"),
  vocalCues("Vocal cues"),
  layers("Layers"),
  colour("Colour"),

  /// settings is the selection's settings, headed for what is selected.
  settings("Settings", canHide: false),

  // One for each kind of asset in the library (AssetKind, in storage/).
  picture("Pictures"),
  video("Videos"),
  audio("Audio"),
  vector("Vectors"),
  model("3D objects"),
  characters("Characters"),
  cast("Cast"),
  stock("Stock"),
  game("Game", only: SidebarSet.gameId, canHide: false);

  /// title is its name where it is not headed for the canvas or the
  /// selection: in a menu, on a chip, as a new sidebar's name.
  final String title;

  /// only is the id of the one sidebar it may be in; null for a panel that
  /// may be in any but Files and Game.
  final String? only;

  /// canHide is whether it can be taken out of every sidebar.
  final bool canHide;

  const SidebarPanel(this.title, {this.only, this.canHide = true});

  /// fromName reads a panel kept by name; null for one not known.
  static SidebarPanel? fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// sidebarIconNames are the icons a sidebar can wear (see sidebarIcon).
const sidebarIconNames = [
  "design", "media", "game", "folder", "brush", "star", "bookmark", //
  "bolt", "heart", "chart", "layers", "palette", "movie", "music",
];

/// SidebarSet is one sidebar: its name, its icon and its panels in order.
class SidebarSet {
  /// filesId and gameId are the two sidebars that are always there.
  static const filesId = "files", gameId = "game";

  final String id;
  final String name;
  final String icon;
  final List<SidebarPanel> panels;

  /// fixed is the Files or Game sidebar: its panels its own, never removed.
  final bool fixed;

  /// gameOnly is the Game sidebar, shown only for a game.
  final bool gameOnly;

  const SidebarSet(this.id, this.name, this.icon, this.panels,
      {this.fixed = false, this.gameOnly = false});

  SidebarSet copyWith(
          {String? name, String? icon, List<SidebarPanel>? panels}) =>
      SidebarSet(
          id, name ?? this.name, icon ?? this.icon, panels ?? this.panels,
          fixed: fixed, gameOnly: gameOnly);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "icon": icon,
        "panels": [for (var p in panels) p.name],
      };
}

/// RemovedSidebar is a sidebar taken away, kept so it can be put back where
/// it stood, with its panels.
class RemovedSidebar {
  final String id;
  final String name;
  final String icon;
  final int at;
  const RemovedSidebar(this.id, this.name, this.icon, this.at);

  Map<String, dynamic> toJson() =>
      {"id": id, "name": name, "icon": icon, "at": at};
}

/// defaultSidebars are the sidebars as they start, each with its panels:
/// every [SidebarPanel] is in one of them.
const defaultSidebars = [
  SidebarSet(SidebarSet.filesId, "Files", "folder",
      [SidebarPanel.files, SidebarPanel.presets],
      fixed: true),
  SidebarSet("design", "Design", "design", [
    SidebarPanel.add,
    SidebarPanel.scenes,
    SidebarPanel.vocalCues,
    SidebarPanel.layers,
    SidebarPanel.colour,
    SidebarPanel.settings,
  ]),
  SidebarSet("assets", "Assets", "media", [
    SidebarPanel.picture,
    SidebarPanel.video,
    SidebarPanel.audio,
    SidebarPanel.vector,
    SidebarPanel.model,
    SidebarPanel.characters,
    SidebarPanel.cast,
    SidebarPanel.stock,
  ]),
  SidebarSet(SidebarSet.gameId, "Game", "game", [SidebarPanel.game],
      fixed: true, gameOnly: true),
];

/// maxSidebars is the most sidebars there can be, the app's four included.
const int maxSidebars = 12;

/// SidebarLayout is how the sidebar is set out: see the top of the file.
/// Every change returns a new one; fromJson puts right whatever was kept
/// that does not add up.
class SidebarLayout {
  final SidebarMode mode;

  /// opened is the way it was last shown, to show it again from hidden.
  final SidebarMode opened;

  final String current;

  final List<SidebarSet> sidebars;
  final List<SidebarPanel> hidden;

  /// hiddenFrom is the sidebar each hidden panel came from.
  final Map<SidebarPanel, String> hiddenFrom;
  final List<RemovedSidebar> removed;

  const SidebarLayout({
    this.mode = SidebarMode.full,
    this.opened = SidebarMode.full,
    this.current = SidebarSet.filesId,
    this.sidebars = defaultSidebars,
    this.hidden = const [],
    this.hiddenFrom = const {},
    this.removed = const [],
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = SidebarLayout();

  SidebarLayout copyWith({
    SidebarMode? mode,
    SidebarMode? opened,
    String? current,
    List<SidebarSet>? sidebars,
    List<SidebarPanel>? hidden,
    Map<SidebarPanel, String>? hiddenFrom,
    List<RemovedSidebar>? removed,
  }) =>
      SidebarLayout(
        mode: mode ?? this.mode,
        opened: opened ?? this.opened,
        current: current ?? this.current,
        sidebars: sidebars ?? this.sidebars,
        hidden: hidden ?? this.hidden,
        hiddenFrom: hiddenFrom ?? this.hiddenFrom,
        removed: removed ?? this.removed,
      );

  /// shown are the sidebars there are for this canvas: Game only for a game.
  List<SidebarSet> shown({required bool game}) => [
        for (var s in sidebars)
          if (!s.gameOnly || game) s
      ];

  SidebarSet? byId(String id) => sidebars.where((s) => s.id == id).firstOrNull;

  /// sidebarOf is the sidebar holding [panel], or null for a hidden one.
  SidebarSet? sidebarOf(SidebarPanel panel) =>
      sidebars.where((s) => s.panels.contains(panel)).firstOrNull;

  /// canGoIn is whether [panel] may be in [sidebar]: Files' panels in Files
  /// only, the game's in Game only, and everything else anywhere else.
  static bool canGoIn(SidebarPanel panel, SidebarSet sidebar) =>
      panel.only == null ? !sidebar.fixed : sidebar.id == panel.only;

  /// withMode is the sidebar shown [mode]; a shown mode is kept for later.
  SidebarLayout withMode(SidebarMode mode) =>
      copyWith(mode: mode, opened: mode == SidebarMode.hidden ? opened : mode);

  /// shownAgain is the sidebar back as it was last shown.
  SidebarLayout get shownAgain => copyWith(mode: opened);

  /// movePanel is [panel] moved to the end of [to], from wherever it was.
  SidebarLayout movePanel(SidebarPanel panel, String to) {
    var target = byId(to);
    if (target == null || !canGoIn(panel, target)) return this;
    if (target.panels.contains(panel)) return this;
    return copyWith(
      sidebars: [
        for (var s in sidebars)
          if (s.id == to)
            s.copyWith(panels: [...s.panels, panel])
          else
            s.copyWith(panels: [...s.panels.where((p) => p != panel)]),
      ],
      hidden: [...hidden.where((p) => p != panel)],
      hiddenFrom: {...hiddenFrom}..remove(panel),
    );
  }

  /// withPanelOrder is sidebar [id]'s panels put in [order], which is how
  /// its stack on screen has them (the reader drags a panel's heading up
  /// or down there). A panel of the sidebar's that [order] does not name
  /// stays, after those it does; one it names that is not the sidebar's is
  /// passed by. The same layout where nothing moves.
  SidebarLayout withPanelOrder(String id, List<SidebarPanel> order) {
    var sidebar = byId(id);
    if (sidebar == null) return this;
    var next = [
      for (var p in order)
        if (sidebar.panels.contains(p)) p,
      for (var p in sidebar.panels)
        if (!order.contains(p)) p,
    ];
    var same = true;
    for (var (i, p) in next.indexed) {
      same = same && sidebar.panels[i] == p;
    }
    if (same) return this;
    return copyWith(sidebars: [
      for (var s in sidebars) s.id == id ? s.copyWith(panels: next) : s,
    ]);
  }

  /// hidePanel is [panel] taken out of its sidebar, remembered as from there.
  SidebarLayout hidePanel(SidebarPanel panel) {
    if (!panel.canHide) return this;
    var from = sidebarOf(panel);
    if (from == null) return this;
    return copyWith(
      sidebars: [
        for (var s in sidebars)
          s.id == from.id
              ? s.copyWith(panels: [...s.panels.where((p) => p != panel)])
              : s,
      ],
      hidden: [...hidden, panel],
      hiddenFrom: {...hiddenFrom, panel: from.id},
    );
  }

  /// restorePanel is a hidden [panel] put back: where it came from, while
  /// that sidebar is there, and otherwise the first that will take it.
  SidebarLayout restorePanel(SidebarPanel panel, {String? into}) {
    if (!hidden.contains(panel)) return this;
    var to = byId(into ?? hiddenFrom[panel] ?? "");
    to = to != null && canGoIn(panel, to)
        ? to
        : sidebars.where((s) => canGoIn(panel, s)).firstOrNull;
    return to == null ? this : movePanel(panel, to.id);
  }

  /// addSidebar adds an empty sidebar called [name], holding [panel] if given.
  SidebarLayout addSidebar({String? name, SidebarPanel? panel}) {
    if (sidebars.length >= maxSidebars) return this;
    var n = 1;
    bool taken(String id) =>
        sidebars.any((s) => s.id == id) || removed.any((r) => r.id == id);
    while (taken("custom$n")) {
      n++;
    }
    var id = "custom$n";
    var icon = sidebarIconNames[(n + 3) % sidebarIconNames.length];
    var next = copyWith(sidebars: [
      ...sidebars,
      SidebarSet(id, name ?? "Sidebar $n", icon, const []),
    ], current: id);
    return panel == null ? next : next.movePanel(panel, id);
  }

  /// removeSidebar is [id] taken away: its panels hidden, remembered as its,
  /// and the sidebar itself kept to be put back. A panel that cannot be
  /// hidden goes to the first other sidebar that will take it.
  SidebarLayout removeSidebar(String id) {
    var gone = byId(id);
    if (gone == null || gone.fixed) return this;
    var keep = [
      for (var p in gone.panels)
        if (!p.canHide) p
    ];
    var refuge = sidebars
        .where((s) => s.id != id && !s.fixed && !s.gameOnly)
        .firstOrNull;
    if (keep.isNotEmpty && refuge == null) return this;
    var at = sidebars.indexOf(gone);
    return copyWith(
      sidebars: [
        for (var s in sidebars)
          if (s.id == refuge?.id)
            s.copyWith(panels: [...s.panels, ...keep])
          else if (s.id != id)
            s,
      ],
      hidden: [
        ...hidden,
        for (var p in gone.panels)
          if (p.canHide) p
      ],
      hiddenFrom: {
        ...hiddenFrom,
        for (var p in gone.panels)
          if (p.canHide) p: id
      },
      removed: [
        ...removed.where((r) => r.id != id),
        RemovedSidebar(id, gone.name, gone.icon, at),
      ],
      current: current == id ? (refuge?.id ?? SidebarSet.filesId) : current,
    );
  }

  /// restoreSidebar is a removed sidebar put back where it stood, with the
  /// panels it had that are still hidden.
  SidebarLayout restoreSidebar(String id) {
    var r = removed.where((x) => x.id == id).firstOrNull;
    if (r == null || sidebars.length >= maxSidebars) return this;
    var panels = [
      for (var p in hidden)
        if (hiddenFrom[p] == id) p
    ];
    var list = [...sidebars];
    list.insert(
        r.at.clamp(0, list.length), SidebarSet(id, r.name, r.icon, panels));
    return copyWith(
      sidebars: list,
      hidden: [...hidden.where((p) => !panels.contains(p))],
      hiddenFrom: {...hiddenFrom}..removeWhere((p, _) => panels.contains(p)),
      removed: [...removed.where((x) => x.id != id)],
      current: id,
    );
  }

  /// moveSidebar moves sidebar [id] to place [to], the others closing up.
  SidebarLayout moveSidebar(String id, int to) {
    var from = sidebars.indexWhere((s) => s.id == id);
    if (from < 0) return this;
    var list = [...sidebars];
    var moving = list.removeAt(from);
    list.insert(to.clamp(0, list.length), moving);
    return copyWith(sidebars: list);
  }

  /// renamed and withIcon change one sidebar's name or icon; not Files' or
  /// Game's.
  SidebarLayout renamed(String id, String name) {
    var s = byId(id);
    var clean = name.trim();
    if (s == null || s.fixed || clean.isEmpty) return this;
    return copyWith(sidebars: [
      for (var x in sidebars)
        x.id == id
            ? x.copyWith(
                name: clean.length > 30 ? clean.substring(0, 30) : clean)
            : x,
    ]);
  }

  SidebarLayout withIcon(String id, String icon) {
    var s = byId(id);
    if (s == null || s.fixed || !sidebarIconNames.contains(icon)) return this;
    return copyWith(sidebars: [
      for (var x in sidebars) x.id == id ? x.copyWith(icon: icon) : x,
    ]);
  }

  /// asStarted is the sidebars as they start, kept shown as they are.
  SidebarLayout get asStarted => SidebarLayout(mode: mode, opened: opened);

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        "opened": opened.name,
        "current": current,
        "sidebars": [for (var s in sidebars) s.toJson()],
        if (hidden.isNotEmpty) "hidden": [for (var p in hidden) p.name],
        if (hiddenFrom.isNotEmpty)
          "hiddenFrom": {for (var e in hiddenFrom.entries) e.key.name: e.value},
        if (removed.isNotEmpty) "removed": [for (var r in removed) r.toJson()],
      };

  /// fromJson reads what was kept, and puts right whatever does not add up:
  /// a panel twice, an unknown one, a new one never seen (it goes where a new
  /// sidebar set has it), Files' or Game's panels elsewhere, or those two
  /// sidebars missing.
  static SidebarLayout fromJson(Object? json) {
    if (json is! Map) return const SidebarLayout();
    // Each panel once: the first place it is met is where it is.
    var seen = <SidebarPanel>{};
    List<SidebarPanel> panelsOf(Object? list) => [
          if (list is List)
            for (var name in list)
              if (SidebarPanel.fromName(name) case var p? when seen.add(p)) p
        ];
    var sidebars = <SidebarSet>[];
    if (json["sidebars"] case List list) {
      for (var raw in list.take(maxSidebars)) {
        if (raw is! Map) continue;
        var id = raw["id"];
        if (id is! String || id.isEmpty) continue;
        if (sidebars.any((s) => s.id == id)) continue;
        var builtIn = defaultSidebars.where((s) => s.id == id).firstOrNull;
        var name = raw["name"] is String && (raw["name"] as String).isNotEmpty
            ? raw["name"] as String
            : builtIn?.name ?? "Sidebar";
        var icon = sidebarIconNames.contains(raw["icon"])
            ? raw["icon"] as String
            : builtIn?.icon ?? "star";
        var probe = SidebarSet(id, name, icon, const [],
            fixed: builtIn?.fixed ?? false,
            gameOnly: builtIn?.gameOnly ?? false);
        var panels = [
          for (var p in panelsOf(raw["panels"]))
            if (SidebarLayout.canGoIn(p, probe)) p else _misplaced(p, seen),
        ].nonNulls.toList();
        sidebars.add(builtIn != null
            ? SidebarSet(id, builtIn.fixed ? builtIn.name : name,
                builtIn.fixed ? builtIn.icon : icon, panels,
                fixed: builtIn.fixed, gameOnly: builtIn.gameOnly)
            : SidebarSet(id, name.length > 30 ? name.substring(0, 30) : name,
                icon, panels));
      }
    }
    // Files and Game are always there.
    for (var fixed in defaultSidebars.where((s) => s.fixed)) {
      if (sidebars.any((s) => s.id == fixed.id)) continue;
      sidebars.insert(
          fixed.id == SidebarSet.filesId ? 0 : sidebars.length,
          fixed.copyWith(panels: [
            for (var p in fixed.panels)
              if (seen.add(p)) p
          ]));
    }
    var hidden = [
      for (var p in panelsOf(json["hidden"]))
        if (p.canHide) p else _misplaced(p, seen),
    ].nonNulls.toList();
    var hiddenFrom = <SidebarPanel, String>{
      if (json["hiddenFrom"] case Map from)
        for (var e in from.entries)
          if ((SidebarPanel.fromName(e.key), e.value) case (var p?, String id)
              when hidden.contains(p))
            p: id,
    };
    var removed = <RemovedSidebar>[
      if (json["removed"] case List list)
        for (var r in list.take(maxSidebars))
          if (r is Map &&
              r["id"] is String &&
              !sidebars.any((s) => s.id == r["id"]))
            RemovedSidebar(
                r["id"] as String,
                r["name"] is String ? r["name"] as String : "Sidebar",
                sidebarIconNames.contains(r["icon"])
                    ? r["icon"] as String
                    : "star",
                r["at"] is int ? r["at"] as int : 0),
    ];
    var layout = SidebarLayout(
      mode: SidebarMode.fromName(json["mode"]),
      opened: SidebarMode.fromName(json["opened"]) == SidebarMode.hidden
          ? SidebarMode.full
          : SidebarMode.fromName(json["opened"]),
      current: jsonString(json["current"], _defaults.current),
      sidebars: sidebars,
      hidden: hidden,
      hiddenFrom: hiddenFrom,
      removed: removed,
    );
    // Whatever is not anywhere -- a panel new since this was written, or one
    // put right above -- goes where it starts.
    for (var p in SidebarPanel.values) {
      if (layout.sidebarOf(p) != null || layout.hidden.contains(p)) continue;
      var home = defaultSidebars.firstWhere((s) => s.panels.contains(p));
      var to = layout.byId(home.id) ??
          layout.sidebars.where((s) => canGoIn(p, s)).firstOrNull;
      if (to == null) continue;
      layout = layout.copyWith(sidebars: [
        for (var s in layout.sidebars)
          s.id == to.id ? s.copyWith(panels: [...s.panels, p]) : s,
      ]);
    }
    if (layout.byId(layout.current) == null) {
      layout = layout.copyWith(current: SidebarSet.filesId);
    }
    return layout;
  }

  /// _misplaced is a panel found where it may not be: let go, to be put
  /// back where it starts by fromJson.
  static SidebarPanel? _misplaced(SidebarPanel panel, Set<SidebarPanel> seen) {
    seen.remove(panel);
    return null;
  }
}
