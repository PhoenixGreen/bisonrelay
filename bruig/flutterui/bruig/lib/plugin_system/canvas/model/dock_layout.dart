import 'dart:convert';

// dock_layout.dart is how the panels under the canvas are arranged: which of
// the places each one opens in, how many places there are, how they are
// switched, and the layouts that set several at once. The reader's, kept in
// the preferences (see CanvasPreferences.dock), not the document's.
//
// Which panels are open is the controller's (see CanvasController.dockOpen):
// each place shows one panel at a time, so opening one closes whatever else
// was showing in its place.

/// DockPanel is one of the panels under the canvas. [key] is its button's,
/// on the play bar.
///
/// [chain] is the picked channel's or element's devices: its sound (the
/// effects) or its motion (the animation), switched in the panel -- see
/// CanvasController.chainShowsMotion.
enum DockPanel {
  timeline("Timeline", "rowsToggle"),
  slots("Slots", "slotsToggle"),
  mixer("Mixer", "mixerToggle"),
  chain("Chain", "chainToggle");

  final String label;
  final String key;
  const DockPanel(this.label, this.key);

  /// fromName reads a panel saved by name. The Effects and Animation panels
  /// of before are the Chain's two views now, so either name is the Chain.
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
      // One saved when the Animation panel was a panel of its own shows
      // the Chain on its motion.
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
  final Map<DockPanel, DockPlace> homes;
  final DockSwitcher switcher;

  /// showLayouts is whether the layouts are on the play bar as well as in
  /// its layout menu; with the layouts the switcher, they always are.
  final bool showLayouts;

  /// saved are the reader's own layouts, after the built-in ones.
  final List<DockArrangement> saved;

  const DockLayout({
    this.places = DockPlaces.two,
    this.homes = defaultHomes,
    this.switcher = DockSwitcher.buttons,
    this.showLayouts = true,
    this.saved = const [],
  });

  /// defaultHomes are where the panels open to begin with. The Chain opens
  /// in main, under the mixer or the slots on the left.
  static const defaultHomes = {
    DockPanel.timeline: DockPlace.main,
    DockPanel.slots: DockPlace.left,
    DockPanel.mixer: DockPlace.left,
    DockPanel.chain: DockPlace.main,
  };

  /// placeOf is where [panel] opens as things are: everything in main with
  /// one place, and main for a panel kept above while there is no above.
  DockPlace placeOf(DockPanel panel) {
    if (places == DockPlaces.one) return DockPlace.main;
    var home = homes[panel] ?? defaultHomes[panel]!;
    if (home == DockPlace.above && places != DockPlaces.three) {
      return DockPlace.main;
    }
    return home;
  }

  /// homeOf is where [panel] opens when there are places for it.
  DockPlace homeOf(DockPanel panel) => homes[panel] ?? defaultHomes[panel]!;

  /// placesShown are the places there are.
  List<DockPlace> get placesShown => switch (places) {
        DockPlaces.one => const [DockPlace.main],
        DockPlaces.two => const [DockPlace.main, DockPlace.left],
        DockPlaces.three => DockPlace.values,
      };

  /// layoutsOnBar is whether the play bar carries the layouts.
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

  /// withHome is [panel] opening in [place] from now on.
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
        ...defaultHomes,
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
