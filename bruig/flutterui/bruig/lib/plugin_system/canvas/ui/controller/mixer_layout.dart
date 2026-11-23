part of '../canvas_controller.dart';

// How the mixer and the Slots panel are laid out: the bands from the rail,
// the returns, the slots' motion parts, the cue columns' widths, the slots'
// size, the rail folded, and which strips are narrow. Part of
// CanvasController. All but the narrow strips are one MixerLayout
// (model/mixer_layout.dart), the person's own and kept as such (KeptView),
// which holds every limit on them; the narrow strips are the canvas's own,
// kept with its view (canvasView).

extension CanvasMixerLayout on CanvasController {
  /// mixerLayout is how the mixer and the Slots panel are laid out, for
  /// keeping. See restoreMixerLayout.
  MixerLayout get mixerLayout => _mixerLayout;

  /// restoreMixerLayout puts [layout] back as it was left, without
  /// notifying, for the screen to call as it opens.
  void restoreMixerLayout(MixerLayout layout) => _mixerLayout = layout;

  /// _changeMixerLayout makes [next] the layout, telling of it if it
  /// differs: every setter below comes here.
  void _changeMixerLayout(MixerLayout next) {
    if (next == _mixerLayout) return;
    _mixerLayout = next;
    notifyListeners();
  }

  /// bandState is how mixer band [section] is shown: whole, minimised or
  /// hidden, set per band from the rail at the mixer's right edge.
  BandState bandState(MixerSection section) => _mixerLayout.band(section);

  /// setMixerSection shows [section] as [state], from the rail: the sends
  /// are never minimised (nothing is smaller than a dial), and the last of
  /// the clips, devices and mixer bands showing is never hidden.
  void setMixerSection(MixerSection section, BandState state) =>
      _changeMixerLayout(_mixerLayout.withBand(section, state));

  /// motionSlots is how the slot rows' motion parts show: whole, as a thin
  /// line, or not at all (the rail's Motion slots).
  BandState get motionSlots => _mixerLayout.motionSlots;
  set motionSlots(BandState state) =>
      _changeMixerLayout(_mixerLayout.copyWith(motionSlots: state));

  /// cueColumnWidth is the width of the mixer's cue column, on the left: 40
  /// to 240, dragged by its edge.
  double get cueColumnWidth => _mixerLayout.cueColumnWidth;
  set cueColumnWidth(double width) =>
      _changeMixerLayout(_mixerLayout.copyWith(cueColumnWidth: width));

  /// slotsCueWidth is the Slots panel's own cue column, 40 to 240 (120 first).
  double get slotsCueWidth => _mixerLayout.slotsCueWidth;
  set slotsCueWidth(double width) =>
      _changeMixerLayout(_mixerLayout.copyWith(slotsCueWidth: width));

  /// masterCueColumnWidth and slotsMasterCueWidth are the master's cue
  /// columns -- the mixer's and the Slots panel's -- on a scene with cues of
  /// its own: dragged by their own edges, apart from the scene's.
  double get masterCueColumnWidth => _mixerLayout.masterCueColumnWidth;
  set masterCueColumnWidth(double width) =>
      _changeMixerLayout(_mixerLayout.copyWith(masterCueColumnWidth: width));

  double get slotsMasterCueWidth => _mixerLayout.slotsMasterCueWidth;
  set slotsMasterCueWidth(double width) =>
      _changeMixerLayout(_mixerLayout.copyWith(slotsMasterCueWidth: width));

  /// slotsPanelSize is how tall the Slots panel's slots are: 0 to 2, small
  /// to large, or 3, filling the panel's height.
  int get slotsPanelSize => _mixerLayout.slotsPanelSize;
  set slotsPanelSize(int size) =>
      _changeMixerLayout(_mixerLayout.copyWith(slotsPanelSize: size));

  /// slotsPanelNarrow makes every Slots panel column 84 wide, no pictures.
  bool get slotsPanelNarrow => _mixerLayout.slotsPanelNarrow;
  set slotsPanelNarrow(bool narrow) =>
      _changeMixerLayout(_mixerLayout.copyWith(slotsPanelNarrow: narrow));

  /// mixerRailFolded folds the mixer's rail to a thin strip, for room.
  bool get mixerRailFolded => _mixerLayout.railFolded;
  set mixerRailFolded(bool folded) =>
      _changeMixerLayout(_mixerLayout.copyWith(railFolded: folded));

  /// returnsShown is whether the mixer shows the returns beside the master;
  /// hidden, what is sent to them is still heard.
  bool get returnsShown => _mixerLayout.returnsShown;

  set returnsShown(bool on) =>
      _changeMixerLayout(_mixerLayout.copyWith(returnsShown: on));

  /// narrowStrips are the mixer's narrow columns, by key (see setAllNarrow).
  Set<String> get narrowStrips => Set.unmodifiable(_narrowStrips);

  void toggleNarrow(String key) {
    if (!_narrowStrips.remove(key)) _narrowStrips.add(key);
    notifyListeners();
  }

  void setAllNarrow(Iterable<String> keys, bool narrow) {
    narrow ? _narrowStrips.addAll(keys) : _narrowStrips.removeAll(keys);
    notifyListeners();
  }
}
