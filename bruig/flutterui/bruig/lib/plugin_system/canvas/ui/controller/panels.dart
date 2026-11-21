part of '../canvas_controller.dart';

// Part of CanvasController: how the panels under the canvas are set -- the
// timeline's tool and snapping, the mixer's size, the effects panel and its
// devices' settings -- and kept between visits. Its state is _PanelState, at
// the end of this file.

extension CanvasPanels on CanvasController {
  /// snapping is whether a dragged sound snaps to seconds and the playhead.
  bool get snapping => _panelState.snapping;

  set snapping(bool value) {
    if (_panelState.snapping == value) return;
    _panelState.snapping = value;
    notifyListeners();
  }

  /// timelineTool is what a press on a timeline sound does: grab or cut.
  TimelineTool get timelineTool => _panelState.timelineTool;

  set timelineTool(TimelineTool value) {
    if (_panelState.timelineTool == value) return;
    _panelState.timelineTool = value;
    notifyListeners();
  }

  void setLaneHeight(String channel, double height) {
    laneHeights[channel] = height;
    notifyListeners();
  }

  /// mixerOpen is whether the mixer shows; the reader's, kept (panelState).
  bool get mixerOpen => dockOpen(DockPanel.mixer);

  set mixerOpen(bool open) {
    if (open == mixerOpen) return;
    open ? _openPanel(DockPanel.mixer) : _closePanel(DockPanel.mixer);
    notifyListeners();
  }

  /// mixerSize is how much of the open mixer shows (MixerSize): all of it,
  /// one line of channels, or smaller still. Set by dragging the mixer's
  /// edge in the dock; setting it opens the mixer.
  MixerSize get mixerSize => _dockState.mixer;

  set mixerSize(MixerSize size) {
    if (mixerOpen && size == mixerSize) return;
    _dockState = _dockState.withMixer(size, _dock);
    notifyListeners();
  }

  /// mixerMinimised is the mixer folded to one line of channels, each its
  /// name over its sideways meter, as dragged all the way down; and
  /// mixerSmallest that with the names and the band rail gone too, only
  /// what each channel is doing. Both are still open.
  bool get mixerMinimised => mixerOpen && mixerSize != MixerSize.full;
  bool get mixerSmallest => mixerOpen && mixerSize == MixerSize.smallest;

  /// panelState is how the panels under the canvas were left, whatever
  /// canvas is open, for the screen to keep: which are open, the mixer's
  /// size and the Chain's view (DockState.toJson), the folded devices, the
  /// channels' size and the timeline header's width. See restorePanels.
  Map<String, dynamic> get panelState => {
        ..._dockState.toJson(),
        "folded": [...foldedDevices]..sort(),
        "laneSize": _laneSize,
        "header": _headerWidth,
      };

  /// restorePanels puts back [state] from panelState, without notifying.
  void restorePanels(Map<String, dynamic> state) {
    // Over what is open already, and as many as fit their places.
    _dockState = DockState.fromJson(state, _dock, start: _dockState);
    if (state["folded"] case List folded) {
      foldedDevices
        ..clear()
        ..addAll(folded.whereType<String>());
    }
    if (state["laneSize"] case int size when size >= 0 && size < 3) {
      _laneSize = size;
    }
    if (state["header"] case num width) {
      _headerWidth =
          width.toDouble().clamp(timelineHeaderMin, timelineHeaderMax);
    }
  }

  /// canvasView is how this canvas is looked at -- channel heights, narrow
  /// strips, zoom, effects channel -- kept with its name: restoreCanvasView.
  Map<String, dynamic> get canvasView => {
        if (laneHeights.isNotEmpty)
          "lanes": {
            for (var e in laneHeights.entries)
              e.key: double.parse(e.value.toStringAsFixed(1))
          },
        if (_narrowStrips.isNotEmpty) "narrow": [..._narrowStrips]..sort(),
        if (timelineView case var v?)
          "view": [
            double.parse(v.first.toStringAsFixed(2)),
            double.parse(v.span.toStringAsFixed(2))
          ],
        if (_effectsOf case var e?) "effectsOf": e,
      };

  /// restoreCanvasView applies [state] from canvasView; none if never seen.
  void restoreCanvasView(Map<String, dynamic> state) {
    laneHeights.clear();
    if (state["lanes"] case Map lanes) {
      for (var e in lanes.entries) {
        if (e.key is String && e.value is num) {
          laneHeights[e.key as String] = (e.value as num).toDouble();
        }
      }
    }
    _narrowStrips
      ..clear()
      ..addAll([
        if (state["narrow"] case List narrow) ...narrow.whereType<String>()
      ]);
    timelineView = switch (state["view"]) {
      [num first, num span] when span > 0 =>
        TimelineView(first.toDouble(), span.toDouble()),
      _ => null,
    };
    timelineViewSet++;
    if (state["effectsOf"] case String e) _effectsOf = e;
    notifyListeners();
  }

  /// effectsChannel is the strip the timeline's effects button opens: the
  /// channel or master picked in the mixer or timeline, else the picked
  /// sound's channel, else the master.
  String get effectsChannel {
    var channels = timelineChannels;
    if (selectedChannel case var k?) {
      if (k == mixerMasterKey ||
          k == sceneBusKey ||
          channels.any((c) => c.key == k) ||
          returnOf(k) != null) {
        return k;
      }
    }
    var picked = clipSelection;
    for (var lane in timedLanes) {
      if (picked.contains(lane.element.id)) return lane.channelKey;
    }
    return mixerMasterKey;
  }

  /// effectsOpen is whether the effects panel shows effectsOf's chain.
  bool get effectsOpen => _dockState.showsSound;

  set effectsOpen(bool open) {
    if (open == effectsOpen) return;
    open ? _showChain(ChainView.sound) : _closePanel(DockPanel.chain);
    notifyListeners();
  }

  /// effectsFocus is the device last asked for ("eq", "comp" ...), and
  /// effectsFocusCount how often, so asking again scrolls to it again.
  String? get effectsFocus => _effectsFocus;

  int get effectsFocusCount => _effectsFocusCount;

  /// openEffects shows [key]'s chain in the effects panel, unfolded on and
  /// scrolled to [device] where one is given.
  void openEffects(String key, {String? device}) {
    if (device != null) {
      foldedDevices.remove(device);
      _effectsFocus = device;
      _effectsFocusCount++;
      // Speech is the Speech view's; anything else -- its Vocaliser too --
      // is in the chain.
      _speechShown = device == "speech";
      _pitchShown = false;
      _instrumentShown = false;
    }
    _effectsOf = key;
    _showChain(ChainView.sound);
    notifyListeners();
  }

  /// editorWide is whether the editor in the effects strip -- a clip's, or
  /// a part's piano roll -- is widened: every setting, and the most room.
  bool get editorWide => _editorWide;

  /// settingsShut is whether editor [kind]'s settings are folded away.
  bool settingsShut(String kind) => _panelState.settingsShut[kind] ?? false;

  void toggleSettingsShut(String kind) {
    _panelState.settingsShut[kind] = !settingsShut(kind);
    notifyListeners();
  }

  /// analysing is whether device [id] of strip [owner] has its display on:
  /// the real sound drawn, rather than a picture of its settings.
  bool analysing(String owner, String id) =>
      _panelState.analysing.contains("$owner|$id");

  void setAnalysing(String owner, String id, bool on) {
    if (on ? _panelState.analysing.add("$owner|$id") : _panelState.analysing.remove("$owner|$id")) {
      if (!on) stopScope(owner, id);
      notifyListeners();
    }
  }

  /// showingB is whether device [id] of strip [owner] is on its B set.
  bool showingB(String owner, String id) => _abB.contains("$owner|$id");

  /// toggleAB swaps device [id]'s settings with its other set (A|B), as one
  /// undo step. Pressed first, B starts as a copy of A, to compare by ear.
  void toggleAB(String owner, String id) {
    var devices = devicesOf(owner);
    var i = deviceIndexOf(devices, id);
    if (i < 0) return;
    var d = devices[i];
    var key = "$owner|$id";
    var now = {for (var p in d.kind.params) p.id: d.value(p.id)};
    var other = _panelState.abOther[key] ?? now;
    var next = d;
    for (var MapEntry(key: k, value: v) in other.entries) {
      next = next.withValue(k, v);
    }
    _panelState.abOther[key] = now;
    if (!_abB.remove(key)) _abB.add(key);
    beginInteraction();
    setDevicesOf(owner, [...devices]..[i] = next);
    endInteraction();
  }

  /// showingBOf is showingB for the card kept as [key]: see toggleABOf.
  bool showingBOf(String key) => _abB.contains(key);

  /// toggleABOf is toggleAB for a card whose settings are a whole thing --
  /// a strip's EQ or compressor, the master's limiter, a Ducker: [now] is
  /// what it is set to, and [apply] puts the other set on it (transient; the
  /// one undo step is this). Pressed first, B starts as a copy of A.
  void toggleABOf(String key, Object now, void Function(Object other) apply) {
    var other = _panelState.abSets[key] ?? now;
    _panelState.abSets[key] = now;
    if (!_abB.remove(key)) _abB.add(key);
    beginInteraction();
    apply(other);
    endInteraction();
  }

  /// presetNameOf is the preset last put on device [id] of strip [owner],
  /// or null for its defaults: what its bar says.
  String? presetNameOf(String owner, String id) => _panelState.presetNames["$owner|$id"];

  void setPresetName(String owner, String id, String? name) {
    name == null
        ? _panelState.presetNames.remove("$owner|$id")
        : _panelState.presetNames["$owner|$id"] = name;
    notifyListeners();
  }
}

/// _PanelState is what CanvasPanels keeps between calls, here beside the code that
/// uses it. The controller holds one, as _panelState; most fields are read and
/// set through CanvasPanels's getters and setters above, which say what each is.
class _PanelState {
  bool snapping = false;

  TimelineTool timelineTool = TimelineTool.select;

  /// settingsShut is, by editor ("roll" a piano roll, "clip" a slot's
  /// clip), whether its settings are folded to a strip. The roll starts
  /// folded, so the notes come first.
  final Map<String, bool> settingsShut = {"roll": true};

  /// analysing are the devices, as "strip|device", whose displays show the
  /// real sound: off until switched on, as keeping and drawing it costs.
  final Set<String> analysing = {};

  /// abOther are each compared device's other settings, by "strip|device",
  /// and _abB those heard with their B: see toggleAB.
  final Map<String, Map<String, double>> abOther = {};

  /// abSets are the other A/B sets of cards whose settings are not knobs
  /// (an EQ's bands, a compressor's, a limiter's): see toggleABOf.
  final Map<String, Object> abSets = {};

  /// presetNames are the presets last put on devices, by "strip|device".
  final Map<String, String> presetNames = {};

  /// forgetDocument lets go of what is kept by strip and device: they are
  /// the canvas's, and another is being opened.
  void forgetDocument() {
    analysing.clear();
    abOther.clear();
    abSets.clear();
    presetNames.clear();
  }
}
