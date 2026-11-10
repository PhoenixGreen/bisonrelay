// sidebar_layout.dart is how the Canvas sidebar is set out: whether it is
// shown, and how (beside everything, or above the panels under the canvas),
// which sidebars there are, and which panels each holds. The reader's, kept
// in the preferences (see CanvasPreferences.sidebars).
//
// Every panel there is appears once: in a sidebar, or among the hidden ones,
// which remember where they came from so they can go back. Files keeps the
// files and the presets and nothing else; the Game sidebar keeps the game's
// settings and shows only for a game. The files and the selection's settings
// can move but never be hidden.

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

/// sidebarPanelIds are the panels there are, in the order a new sidebar set
/// out as it starts has them. Kept as names: see SidebarPanel in the UI.
const sidebarPanelIds = [
  "files", "presets", //
  "add", "scenes", "vocalCues", "layers", "colour", "settings", //
  "picture", "video", "audio", "vector", "model", "characters", "cast", //
  "stock", "game",
];

/// requiredPanels can move but not be hidden.
const requiredPanels = {"files", "settings"};

/// filesPanels live in the Files sidebar only, and gamePanels in the Game
/// one.
const filesPanels = {"files", "presets"};
const gamePanels = {"game"};

/// sidebarIconNames are the icons a sidebar can wear: see sidebarIcon in
/// the UI.
const sidebarIconNames = [
  "design", "media", "game", "folder", "brush", "star", "bookmark", //
  "bolt", "heart", "chart", "layers", "palette", "movie", "music",
];

/// SidebarSet is one sidebar: its name, its icon and its panels in order.
class SidebarSet {
  final String id;
  final String name;
  final String icon;
  final List<String> panels;

  /// fixed is the Files or the Game sidebar: kept as it is, its panels its
  /// own, never removed.
  final bool fixed;

  /// gameOnly is the Game sidebar, shown only for a game.
  final bool gameOnly;

  const SidebarSet(this.id, this.name, this.icon, this.panels,
      {this.fixed = false, this.gameOnly = false});

  SidebarSet copyWith({String? name, String? icon, List<String>? panels}) =>
      SidebarSet(
          id, name ?? this.name, icon ?? this.icon, panels ?? this.panels,
          fixed: fixed, gameOnly: gameOnly);

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "icon": icon,
        "panels": panels,
        if (fixed) "fixed": true,
        if (gameOnly) "game": true,
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

/// defaultSidebars are the sidebars as they start.
const defaultSidebars = [
  SidebarSet("files", "Files", "folder", ["files", "presets"], fixed: true),
  SidebarSet("design", "Design", "design",
      ["add", "scenes", "vocalCues", "layers", "colour", "settings"]),
  SidebarSet("assets", "Assets", "media", [
    "picture",
    "video",
    "audio",
    "vector",
    "model",
    "characters",
    "cast",
    "stock"
  ]),
  SidebarSet("game", "Game", "game", ["game"], fixed: true, gameOnly: true),
];

/// maxSidebars is how many a reader can have.
const int maxSidebars = 12;

/// SidebarLayout is the whole arrangement: see the top of the file.
class SidebarLayout {
  final SidebarMode mode;

  /// opened is the way it was last shown, to show it again from hidden.
  final SidebarMode opened;

  /// current is the sidebar on show.
  final String current;

  final List<SidebarSet> sidebars;
  final List<String> hidden;

  /// hiddenFrom is the sidebar each hidden panel came from.
  final Map<String, String> hiddenFrom;
  final List<RemovedSidebar> removed;

  const SidebarLayout({
    this.mode = SidebarMode.full,
    this.opened = SidebarMode.full,
    this.current = "files",
    this.sidebars = defaultSidebars,
    this.hidden = const [],
    this.hiddenFrom = const {},
    this.removed = const [],
  });

  SidebarLayout copyWith({
    SidebarMode? mode,
    SidebarMode? opened,
    String? current,
    List<SidebarSet>? sidebars,
    List<String>? hidden,
    Map<String, String>? hiddenFrom,
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
  SidebarSet? sidebarOf(String panel) =>
      sidebars.where((s) => s.panels.contains(panel)).firstOrNull;

  /// canGoIn is whether [panel] may be in [sidebar]: Files' panels in Files
  /// only, the game's in Game only, and everything else anywhere else.
  static bool canGoIn(String panel, SidebarSet sidebar) {
    if (filesPanels.contains(panel)) return sidebar.id == "files";
    if (gamePanels.contains(panel)) return sidebar.id == "game";
    return !sidebar.fixed;
  }

  /// withMode is the sidebar shown [mode]; shown, it is remembered as the
  /// way to show it again.
  SidebarLayout withMode(SidebarMode mode) =>
      copyWith(mode: mode, opened: mode == SidebarMode.hidden ? opened : mode);

  /// shownAgain is the sidebar back as it was last shown.
  SidebarLayout get shownAgain => copyWith(mode: opened);

  /// movePanel is [panel] moved to the end of [to], from wherever it was.
  SidebarLayout movePanel(String panel, String to) {
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

  /// hidePanel is [panel] taken out of its sidebar, remembered as from there.
  SidebarLayout hidePanel(String panel) {
    if (requiredPanels.contains(panel)) return this;
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
  SidebarLayout restorePanel(String panel, {String? into}) {
    if (!hidden.contains(panel)) return this;
    var to = byId(into ?? hiddenFrom[panel] ?? "");
    to = to != null && canGoIn(panel, to)
        ? to
        : sidebars.where((s) => canGoIn(panel, s)).firstOrNull;
    return to == null ? this : movePanel(panel, to.id);
  }

  /// addSidebar is a new, empty sidebar called [name] -- holding [panel]
  /// where one is given -- after the others.
  SidebarLayout addSidebar({String? name, String? panel}) {
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
        if (requiredPanels.contains(p)) p
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
          if (!requiredPanels.contains(p)) p
      ],
      hiddenFrom: {
        ...hiddenFrom,
        for (var p in gone.panels)
          if (!requiredPanels.contains(p)) p: id
      },
      removed: [
        ...removed.where((r) => r.id != id),
        RemovedSidebar(id, gone.name, gone.icon, at),
      ],
      current: current == id ? (refuge?.id ?? "files") : current,
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

  /// moveSidebar is sidebar [id] moved to place [to] along the row, the
  /// others closing up round it.
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
  SidebarLayout get asStarted =>
      SidebarLayout(mode: mode, opened: opened, current: "files");

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        "opened": opened.name,
        "current": current,
        "sidebars": [for (var s in sidebars) s.toJson()],
        if (hidden.isNotEmpty) "hidden": hidden,
        if (hiddenFrom.isNotEmpty) "hiddenFrom": hiddenFrom,
        if (removed.isNotEmpty) "removed": [for (var r in removed) r.toJson()],
      };

  /// fromJson reads what was kept, and puts right whatever does not add up:
  /// a panel twice, one no longer made, a new one never seen (it goes where
  /// a new sidebar set has it), Files' or Game's panels anywhere else, or
  /// those two sidebars missing.
  static SidebarLayout fromJson(Object? json) {
    if (json is! Map) return const SidebarLayout();
    var seen = <String>{};
    var known = sidebarPanelIds.toSet();
    List<String> panelsOf(Object? list) => [
          if (list is List)
            for (var p in list)
              if (p is String && known.contains(p) && seen.add(p)) p
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
        ].whereType<String>().toList();
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
          fixed.id == "files" ? 0 : sidebars.length,
          fixed.copyWith(panels: [
            for (var p in fixed.panels)
              if (seen.add(p)) p
          ]));
    }
    var hidden = [
      for (var p in panelsOf(json["hidden"]))
        if (!requiredPanels.contains(p)) p else _misplaced(p, seen),
    ].whereType<String>().toList();
    var hiddenFrom = <String, String>{
      if (json["hiddenFrom"] case Map from)
        for (var e in from.entries)
          if (e.key is String && e.value is String && hidden.contains(e.key))
            e.key as String: e.value as String,
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
      current: json["current"] is String ? json["current"] as String : "files",
      sidebars: sidebars,
      hidden: hidden,
      hiddenFrom: hiddenFrom,
      removed: removed,
    );
    // Whatever is not anywhere -- a panel new since this was written, or one
    // put right above -- goes where it starts.
    for (var p in sidebarPanelIds) {
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
      layout = layout.copyWith(current: "files");
    }
    return layout;
  }

  /// _misplaced is a panel found where it may not be: let go, to be put
  /// back where it starts by fromJson.
  static String? _misplaced(String panel, Set<String> seen) {
    seen.remove(panel);
    return null;
  }
}
