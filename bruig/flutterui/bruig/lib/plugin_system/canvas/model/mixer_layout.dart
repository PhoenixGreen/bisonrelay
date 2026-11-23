import 'package:flutter/foundation.dart' show mapEquals;

import 'package:bruig/plugin_system/canvas/model/json_read.dart';

// mixer_layout.dart is how the mixer and the Slots panel are laid out: which
// of the mixer's bands show and how, the returns, the slots' motion parts,
// the cue columns' widths, the slots' size and the rail.
//
// It belongs to the person editing, not to the canvas: kept in the app's
// preferences (CanvasPreferences.mixerLayout), so a canvas sent to somebody
// opens with that person's mixer, not its sender's. Which strips are narrow
// is the canvas's own (CanvasController.canvasView): strips are its
// channels.

/// BandState is how one of the mixer's bands is shown.
enum BandState { shown, minimised, hidden }

/// MixerSection is one of the mixer's bands, in the rail's order: the
/// sends, last, are drawn between the devices and the mixer, as Ableton's.
enum MixerSection {
  clips("C", "Clips"),
  devices("D", "Devices"),
  mixer("M", "Mixer"),

  /// sends are the send dials, a band of their own -- shown or hidden,
  /// never minimised: there is nothing smaller to show of a dial.
  sends("S", "Sends");

  final String letter;
  final String label;
  const MixerSection(this.letter, this.label);
}

/// MixerLayout is how the mixer and the Slots panel are laid out. Every
/// limit on it is kept here: a width given out of bounds is brought inside
/// them, the sends are never minimised, and one of the main bands always
/// shows.
class MixerLayout {
  /// cueColumnLeast and cueColumnMost bound every cue column's width.
  static const double cueColumnLeast = 40;
  static const double cueColumnMost = 240;

  /// slotsFill is the largest slotsPanelSize: the slots filling the panel's
  /// height. Below it, 0 to 2 are small to large.
  static const int slotsFill = 3;

  /// mainBands are the bands one of which always shows: a mixer of send
  /// dials alone, or of nothing, is only its names.
  static const mainBands = [
    MixerSection.clips,
    MixerSection.devices,
    MixerSection.mixer,
  ];

  /// _bands is how each band shows that does not show whole.
  final Map<MixerSection, BandState> _bands;

  /// returnsShown is whether the mixer shows the returns beside the master;
  /// hidden, what is sent to them is still heard.
  final bool returnsShown;

  /// motionSlots is how the slot rows' motion parts show: whole, as a thin
  /// line, or not at all (the rail's Motion slots).
  final BandState motionSlots;

  /// cueColumnWidth is the width of the mixer's cue column, on the left,
  /// dragged by its edge; slotsCueWidth is the Slots panel's own.
  final double cueColumnWidth;
  final double slotsCueWidth;

  /// masterCueColumnWidth and slotsMasterCueWidth are the master's cue
  /// columns -- the mixer's and the Slots panel's -- on a scene with cues of
  /// its own: dragged by their own edges, apart from the scene's.
  final double masterCueColumnWidth;
  final double slotsMasterCueWidth;

  /// slotsPanelSize is how tall the Slots panel's slots are: 0 to 2, small
  /// to large, or [slotsFill], filling the panel's height.
  final int slotsPanelSize;

  /// slotsPanelNarrow makes every Slots panel column 84 wide, no pictures.
  final bool slotsPanelNarrow;

  /// railFolded folds the mixer's rail to a thin strip, for room.
  final bool railFolded;

  MixerLayout({
    Map<MixerSection, BandState> bands = const {},
    this.returnsShown = true,
    this.motionSlots = BandState.shown,
    double cueColumnWidth = 96,
    double slotsCueWidth = 120,
    double masterCueColumnWidth = 96,
    double slotsMasterCueWidth = 120,
    int slotsPanelSize = 1,
    this.slotsPanelNarrow = false,
    this.railFolded = false,
  })  : _bands = _settled(bands),
        cueColumnWidth = _cue(cueColumnWidth),
        slotsCueWidth = _cue(slotsCueWidth),
        masterCueColumnWidth = _cue(masterCueColumnWidth),
        slotsMasterCueWidth = _cue(slotsMasterCueWidth),
        slotsPanelSize = slotsPanelSize.clamp(0, slotsFill);

  /// _defaults is one as made: what a stored one means by leaving a field
  /// out.
  static final _defaults = MixerLayout();

  static double _cue(double width) =>
      width.clamp(cueColumnLeast, cueColumnMost).toDouble();

  /// _settled is [bands] as they may be: the sends never minimised, and,
  /// with every main band hidden, the mixer's shown.
  static Map<MixerSection, BandState> _settled(
      Map<MixerSection, BandState> bands) {
    var settled = {
      for (var MapEntry(key: s, value: state) in bands.entries)
        if (state != BandState.shown)
          s: s == MixerSection.sends && state == BandState.minimised
              ? BandState.hidden
              : state,
    };
    if (mainBands.every((s) => settled[s] == BandState.hidden)) {
      settled.remove(MixerSection.mixer);
    }
    return Map.unmodifiable(settled);
  }

  /// band is how [section] is shown: whole, minimised or hidden.
  BandState band(MixerSection section) => _bands[section] ?? BandState.shown;

  /// withBand is this with [section] shown as [state], as the rail asks:
  /// the sends, asked to minimise, are hidden; the last of the main bands
  /// showing is not hidden, and this is given back unchanged.
  MixerLayout withBand(MixerSection section, BandState state) {
    if (state == BandState.hidden &&
        mainBands.contains(section) &&
        mainBands
            .where((s) => s != section)
            .every((s) => band(s) == BandState.hidden)) {
      return this;
    }
    return copyWith(bands: {..._bands, section: state});
  }

  MixerLayout copyWith({
    Map<MixerSection, BandState>? bands,
    bool? returnsShown,
    BandState? motionSlots,
    double? cueColumnWidth,
    double? slotsCueWidth,
    double? masterCueColumnWidth,
    double? slotsMasterCueWidth,
    int? slotsPanelSize,
    bool? slotsPanelNarrow,
    bool? railFolded,
  }) =>
      MixerLayout(
        bands: bands ?? _bands,
        returnsShown: returnsShown ?? this.returnsShown,
        motionSlots: motionSlots ?? this.motionSlots,
        cueColumnWidth: cueColumnWidth ?? this.cueColumnWidth,
        slotsCueWidth: slotsCueWidth ?? this.slotsCueWidth,
        masterCueColumnWidth: masterCueColumnWidth ?? this.masterCueColumnWidth,
        slotsMasterCueWidth: slotsMasterCueWidth ?? this.slotsMasterCueWidth,
        slotsPanelSize: slotsPanelSize ?? this.slotsPanelSize,
        slotsPanelNarrow: slotsPanelNarrow ?? this.slotsPanelNarrow,
        railFolded: railFolded ?? this.railFolded,
      );

  /// toJson writes only what differs from one as made; the widths to the
  /// whole pixel.
  Map<String, dynamic> toJson() {
    var d = _defaults;
    return {
      if (_bands.isNotEmpty)
        "bands": {for (var e in _bands.entries) e.key.name: e.value.name},
      if (returnsShown != d.returnsShown) "returns": returnsShown,
      if (motionSlots != d.motionSlots) "motion": motionSlots.name,
      if (cueColumnWidth.round() != d.cueColumnWidth)
        "cue": cueColumnWidth.round(),
      if (slotsCueWidth.round() != d.slotsCueWidth)
        "slotsCue": slotsCueWidth.round(),
      if (masterCueColumnWidth.round() != d.masterCueColumnWidth)
        "masterCue": masterCueColumnWidth.round(),
      if (slotsMasterCueWidth.round() != d.slotsMasterCueWidth)
        "slotsMasterCue": slotsMasterCueWidth.round(),
      if (slotsPanelSize != d.slotsPanelSize) "size": slotsPanelSize,
      if (slotsPanelNarrow != d.slotsPanelNarrow) "narrow": slotsPanelNarrow,
      if (railFolded != d.railFolded) "rail": railFolded,
    };
  }

  /// fromJson reads what [toJson] wrote, or null for what is not an object.
  /// A band or a state it does not know is passed by.
  static MixerLayout? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    BandState? state(Object? name) =>
        BandState.values.where((b) => b.name == name).firstOrNull;
    var d = _defaults;
    return MixerLayout(
      bands: {
        if (json["bands"] case Map bands)
          for (var s in MixerSection.values)
            if (state(bands[s.name]) case var b?) s: b,
      },
      returnsShown: jsonBool(json["returns"], d.returnsShown),
      motionSlots: state(json["motion"]) ?? d.motionSlots,
      cueColumnWidth: jsonDouble(json["cue"], d.cueColumnWidth),
      slotsCueWidth: jsonDouble(json["slotsCue"], d.slotsCueWidth),
      masterCueColumnWidth:
          jsonDouble(json["masterCue"], d.masterCueColumnWidth),
      slotsMasterCueWidth:
          jsonDouble(json["slotsMasterCue"], d.slotsMasterCueWidth),
      slotsPanelSize: jsonInt(json["size"], d.slotsPanelSize),
      slotsPanelNarrow: jsonBool(json["narrow"], d.slotsPanelNarrow),
      railFolded: jsonBool(json["rail"], d.railFolded),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MixerLayout &&
      mapEquals(other._bands, _bands) &&
      other.returnsShown == returnsShown &&
      other.motionSlots == motionSlots &&
      other.cueColumnWidth == cueColumnWidth &&
      other.slotsCueWidth == slotsCueWidth &&
      other.masterCueColumnWidth == masterCueColumnWidth &&
      other.slotsMasterCueWidth == slotsMasterCueWidth &&
      other.slotsPanelSize == slotsPanelSize &&
      other.slotsPanelNarrow == slotsPanelNarrow &&
      other.railFolded == railFolded;

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(
          _bands.entries.map((e) => Object.hash(e.key, e.value))),
      returnsShown,
      motionSlots,
      cueColumnWidth,
      slotsCueWidth,
      masterCueColumnWidth,
      slotsMasterCueWidth,
      slotsPanelSize,
      slotsPanelNarrow,
      railFolded);
}
