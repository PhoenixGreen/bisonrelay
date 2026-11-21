import 'dart:convert';

// dock_layout.dart is how the panels under the canvas are arranged: the
// place each opens in, how many places there are, how they are switched,
// and the layouts that set several at once. Kept in the reader's
// preferences (CanvasPreferences.dock), not the document. Which panels are
// open is the controller's (CanvasController.dockOpen): each place shows one
// panel at a time.

/// DockPanel is one of the panels under the canvas; [key] is its play-bar
/// button's. [chain] is the picked channel's or element's devices, its
/// sound or its motion (see CanvasController.chainShowsMotion).
enum DockPanel {
  timeline("Timeline", "rowsToggle", DockPlace.main),
  slots("Slots", "slotsToggle", DockPlace.left),
  mixer("Mixer", "mixerToggle", DockPlace.left),

  /// The Chain opens in main, under the mixer or the slots on the left.
  chain("Chain", "chainToggle", DockPlace.main);

  final String label;
  final String key;

  /// home is the place it opens in to begin with.
  final DockPlace home;
  const DockPanel(this.label, this.key, this.home);

  /// fromName reads a panel saved by name. The Effects and Animation names
  /// both read as the Chain, which has those two views.
  static DockPanel? fromName(Object? name) =>
      name == "effects" || name == "animation"
          ? chain
          : values.where((p) => p.name == name).firstOrNull;
}

/// DockPlace is where a panel opens: [main] along the bottom, [left] beside
/// it (with nothing there, main takes the whole width), and [above] over
/// them both.
enum DockPlace {
  main("Main"),
  left("Left, beside Main"),
  above("Above");

  final String label;
  const DockPlace(this.label);

  static DockPlace? fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// DockPlaces is how many places there are: one (every panel full width,
/// each opened in place of the last), two (main and left, side by side) or
/// three (and a panel above).
enum DockPlaces {
  one("One place: every panel full width"),
  two("Two places: Main and Left, side by side"),
  three("Three places: and a second panel above");

  final String label;
  const DockPlaces(this.label);

  static DockPlaces fromName(Object? name) =>
      values.where((p) => p.name == name).firstOrNull ?? two;
}

/// DockSwitcher is how the panels are opened: a button each on the play
/// bar, a row of tabs over each place, or the layouts alone.
enum DockSwitcher {
  buttons("Panel buttons on the play bar"),
  tabs("Tabs on each place"),
  layouts("Layouts only");

  final String label;
  const DockSwitcher(this.label);

  static DockSwitcher fromName(Object? name) =>
      values.where((s) => s.name == name).firstOrNull ?? buttons;
}

/// DockArrangement is a layout: the panel shown in each place, where each
/// opens, and [one], the panel it shows with a single place.
class DockArrangement {
  final String name;
  final Map<DockPlace, DockPanel> shown;
  final Map<DockPanel, DockPlace> homes;
  final DockPanel? one;

  /// fallback is what it shows without an above place, where it differs.
  final Map<DockPlace, DockPanel>? fallback;

  /// builtIn is one of the app's, which cannot be removed.
  final bool builtIn;

  /// chainMotion is whether it shows the Chain on its motion rather than
  /// its sound.
  final bool chainMotion;

  const DockArrangement(this.name,
      {this.shown = const {},
      this.homes = const {},
      this.one,
      this.fallback,
      this.builtIn = false,
      this.chainMotion = false});

  Map<String, dynamic> toJson() => {
        "name": name,
        "shown": {for (var e in shown.entries) e.key.name: e.value.name},
        "homes": {for (var e in homes.entries) e.key.name: e.value.name},
        if (one != null) "one": one!.name,
        if (chainMotion) "chainMotion": true,
      };

  static DockArrangement? fromJson(Object? json) {
    if (json is! Map) return null;
    var name = json["name"];
    if (name is! String || name.trim().isEmpty) return null;
    return DockArrangement(
      name.length > 60 ? name.substring(0, 60) : name,
      shown: {
        if (json["shown"] case Map shown)
          for (var e in shown.entries)
            if ((DockPlace.fromName(e.key), DockPanel.fromName(e.value))
                case (var place?, var panel?))
              place: panel,
      },
      homes: {
        if (json["homes"] case Map homes)
          for (var e in homes.entries)
            if ((DockPanel.fromName(e.key), DockPlace.fromName(e.value))
                case (var panel?, var place?))
              panel: place,
      },
      one: DockPanel.fromName(json["one"]),
      // An Animation panel saved by that name shows the Chain on its motion.
      chainMotion: json["chainMotion"] == true ||
          (json["shown"] is Map &&
              (json["shown"] as Map).containsValue("animation")) ||
          json["one"] == "animation",
    );
  }
}

/// builtInArrangements are the layouts the app comes with.
const builtInArrangements = [
  DockArrangement("Arrange",
      shown: {
        DockPlace.main: DockPanel.timeline,
        DockPlace.left: DockPanel.slots
      },
      one: DockPanel.timeline,
      builtIn: true),
  DockArrangement("Mix",
      shown: {DockPlace.main: DockPanel.chain, DockPlace.left: DockPanel.mixer},
      one: DockPanel.mixer,
      builtIn: true),
  DockArrangement("Animate",
      shown: {
        DockPlace.main: DockPanel.timeline,
        DockPlace.left: DockPanel.slots,
        DockPlace.above: DockPanel.chain,
      },
      fallback: {
        DockPlace.main: DockPanel.chain,
        DockPlace.left: DockPanel.slots,
      },
      one: DockPanel.chain,
      builtIn: true,
      chainMotion: true),
  DockArrangement("Clear", builtIn: true),
];

/// maxSavedArrangements is how many layouts of their own a reader keeps.
const int maxSavedArrangements = 24;

/// DockLayout is the whole arrangement: see the top of the file.
class DockLayout {
  final DockPlaces places;

  /// homes is where each panel that has been moved opens; one not here
  /// opens in its own [DockPanel.home]. Read through [homeOf].
  final Map<DockPanel, DockPlace> homes;
  final DockSwitcher switcher;

  /// showLayouts is whether the layouts are on the play bar as well as in
  /// its layout menu; with the layouts the switcher, they always are.
  final bool showLayouts;

  /// saved are the reader's own layouts, after the built-in ones.
  final List<DockArrangement> saved;

  const DockLayout({
    this.places = DockPlaces.two,
    this.homes = const {},
    this.switcher = DockSwitcher.buttons,
    this.showLayouts = true,
    this.saved = const [],
  });

  /// placeOf is where [panel] opens as things are: everything in main with
  /// one place, and main for a panel kept above while there is no above.
  DockPlace placeOf(DockPanel panel) {
    if (places == DockPlaces.one) return DockPlace.main;
    var home = homeOf(panel);
    if (home == DockPlace.above && places != DockPlaces.three) {
      return DockPlace.main;
    }
    return home;
  }

  /// homeOf is where [panel] opens when there are places for it.
  DockPlace homeOf(DockPanel panel) => homes[panel] ?? panel.home;

  List<DockPlace> get placesShown => switch (places) {
        DockPlaces.one => const [DockPlace.main],
        DockPlaces.two => const [DockPlace.main, DockPlace.left],
        DockPlaces.three => DockPlace.values,
      };

  bool get layoutsOnBar => switcher == DockSwitcher.layouts || showLayouts;

  /// arrangements are the layouts to choose from: the app's, then the
  /// reader's own.
  List<DockArrangement> get arrangements => [...builtInArrangements, ...saved];

  DockLayout copyWith({
    DockPlaces? places,
    Map<DockPanel, DockPlace>? homes,
    DockSwitcher? switcher,
    bool? showLayouts,
    List<DockArrangement>? saved,
  }) =>
      DockLayout(
        places: places ?? this.places,
        homes: homes ?? this.homes,
        switcher: switcher ?? this.switcher,
        showLayouts: showLayouts ?? this.showLayouts,
        saved: saved ?? this.saved,
      );

  /// withHome is [panel] opening in [place].
  DockLayout withHome(DockPanel panel, DockPlace place) =>
      copyWith(homes: {...homes, panel: place});

  Map<String, dynamic> toJson() => {
        "places": places.name,
        "homes": {for (var e in homes.entries) e.key.name: e.value.name},
        "switcher": switcher.name,
        "showLayouts": showLayouts,
        if (saved.isNotEmpty) "saved": [for (var a in saved) a.toJson()],
      };

  static DockLayout fromJson(Object? json) {
    if (json is! Map) return const DockLayout();
    return DockLayout(
      places: DockPlaces.fromName(json["places"]),
      homes: {
        if (json["homes"] case Map homes)
          for (var e in homes.entries)
            if ((DockPanel.fromName(e.key), DockPlace.fromName(e.value))
                case (var panel?, var place?))
              panel: place,
      },
      switcher: DockSwitcher.fromName(json["switcher"]),
      showLayouts: json["showLayouts"] != false,
      saved: [
        if (json["saved"] case List saved)
          for (var a in saved.take(maxSavedArrangements))
            if (DockArrangement.fromJson(a) case var arrangement?) arrangement,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DockLayout && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// MixerSize is how much of the mixer shows while it is open: all of it,
/// folded to one line of channels (dragged all the way down), or smaller
/// still, strips without names or the band rail.
enum MixerSize { full, minimised, smallest }

/// ChainView is which of its two views the Chain shows: a channel's sound
/// (its devices) or an element's motion.
enum ChainView { sound, motion }

/// DockState is which panels under the canvas are open, how big the mixer
/// is, and which view the Chain is on. Where each opens is the [DockLayout];
/// this is what is open now.
///
/// One rule holds it together: each place shows one panel at a time. So a
/// panel is opened with [opened], which shuts whatever shared its place, and
/// never by adding to [open] by hand.
class DockState {
  final Set<DockPanel> open;

  /// mixer is the mixer's size; [MixerSize.full] whenever it is shut.
  final MixerSize mixer;

  /// chain is the view the Chain shows, or shut, the one it will reopen on.
  final ChainView chain;

  const DockState({
    this.open = const {DockPanel.timeline},
    this.mixer = MixerSize.full,
    this.chain = ChainView.sound,
  });

  bool isOpen(DockPanel panel) => open.contains(panel);

  /// showsMotion and showsSound are the Chain open on that view.
  bool get showsMotion => isOpen(DockPanel.chain) && chain == ChainView.motion;
  bool get showsSound => isOpen(DockPanel.chain) && chain == ChainView.sound;

  /// opened is [panel] open, and whatever shared its place in [layout] shut.
  DockState opened(DockPanel panel, DockLayout layout) {
    var place = layout.placeOf(panel);
    var next = this;
    for (var other in open) {
      if (other != panel && layout.placeOf(other) == place) {
        next = next.closed(other);
      }
    }
    return next._with(open: {...next.open, panel});
  }

  /// closed is [panel] shut. A mixer shut is full size when next opened.
  DockState closed(DockPanel panel) => _with(
      open: {...open}..remove(panel),
      mixer: panel == DockPanel.mixer ? MixerSize.full : mixer);

  /// showing is exactly [panels] open, none shutting another: for a layout
  /// that names one panel for each place. Follow with [settled] where the
  /// places may since have changed.
  DockState showing(Set<DockPanel> panels) => _with(
      open: panels,
      mixer: panels.contains(DockPanel.mixer) && isOpen(DockPanel.mixer)
          ? mixer
          : MixerSize.full);

  /// settled is one open panel in each place: where two share one in
  /// [layout], the first in the panels' order stays.
  DockState settled(DockLayout layout) {
    var taken = <DockPlace>{};
    var next = this;
    for (var panel in DockPanel.values) {
      if (!isOpen(panel)) continue;
      if (!taken.add(layout.placeOf(panel))) next = next.closed(panel);
    }
    return next;
  }

  /// shownIn is the panel showing in [place], or null.
  DockPanel? shownIn(DockPlace place, DockLayout layout) {
    for (var panel in DockPanel.values) {
      if (isOpen(panel) && layout.placeOf(panel) == place) return panel;
    }
    return null;
  }

  /// withMixer is the mixer at [size], open; [layout] says what it shuts.
  DockState withMixer(MixerSize size, DockLayout layout) =>
      (isOpen(DockPanel.mixer) ? this : opened(DockPanel.mixer, layout))
          ._with(mixer: size);

  /// onView is the Chain on [view], open or shut as it is.
  DockState onView(ChainView view) => _with(chain: view);

  DockState _with({Set<DockPanel>? open, MixerSize? mixer, ChainView? chain}) =>
      DockState(
          open: Set.unmodifiable(open ?? this.open),
          mixer: mixer ?? this.mixer,
          chain: chain ?? this.chain);

  /// toJson is how it is kept between visits. The keys are older than this
  /// class: "rows" is the Timeline, "effects" and "animation" the Chain on
  /// its sound and on its motion.
  Map<String, dynamic> toJson() => {
        "mixer": !isOpen(DockPanel.mixer)
            ? "hidden"
            : switch (mixer) {
                MixerSize.full => "shown",
                MixerSize.minimised => "minimised",
                MixerSize.smallest => "smallest",
              },
        "rows": isOpen(DockPanel.timeline),
        "slots": isOpen(DockPanel.slots),
        "effects": showsSound,
        "animation": showsMotion,
        "chain": chain.name,
      };

  /// fromJson reads what [toJson] wrote over [start] (what is open before
  /// anything was kept), then leaves one panel to a place in [layout].
  static DockState fromJson(Map<String, dynamic> json, DockLayout layout,
      {DockState start = const DockState()}) {
    var open = {...start.open};
    void set(DockPanel panel, Object? shown) {
      if (shown == true) open.add(panel);
      if (shown == false) open.remove(panel);
    }

    var size = switch (json["mixer"]) {
      "shown" => MixerSize.full,
      "minimised" => MixerSize.minimised,
      "smallest" => MixerSize.smallest,
      _ => null,
    };
    if (size != null) open.add(DockPanel.mixer);
    if (json["mixer"] == "hidden") open.remove(DockPanel.mixer);
    set(DockPanel.timeline, json["rows"]);
    set(DockPanel.slots, json["slots"]);
    // One written before the view was kept says it by which was open.
    var view =
        ChainView.values.where((v) => v.name == json["chain"]).firstOrNull ??
            (json["animation"] == true && json["effects"] != true
                ? ChainView.motion
                : start.chain);
    if (json["effects"] == true || json["animation"] == true) {
      open.add(DockPanel.chain);
    } else if (json["effects"] == false && json["animation"] == false) {
      open.remove(DockPanel.chain);
    }
    return DockState(
            open: Set.unmodifiable(open),
            mixer: open.contains(DockPanel.mixer)
                ? (size ?? start.mixer)
                : MixerSize.full,
            chain: view)
        .settled(layout);
  }

  @override
  bool operator ==(Object other) =>
      other is DockState &&
      other.mixer == mixer &&
      other.chain == chain &&
      other.open.length == open.length &&
      other.open.containsAll(open);

  @override
  int get hashCode => Object.hash(mixer, chain, Object.hashAllUnordered(open));
}
