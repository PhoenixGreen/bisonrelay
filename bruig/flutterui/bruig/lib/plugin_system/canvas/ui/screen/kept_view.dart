import 'dart:async';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// kept_view.dart is what the Canvas page remembers, from one run of the app
// to the next, of what the controller holds: put back as the page opens, and
// written down as it changes.
//
// Two things are remembered. How the page was left, whatever canvas is open
// (the frame, the rulers, the cues, the mixer, the play bar's snapping,
// scrubbing and place, where the panels open and which are open): the list
// in KeptView._kept. And how one canvas was looked at (its channel heights,
// narrow strips, timeline zoom and effects channel), kept under that
// canvas's folder and name.
//
// To remember something more the controller holds, add a line to _kept: how
// the controller takes it back, and how it is written down. Nothing else
// needs to change. What a widget holds itself (the sidebars, whether the
// timeline shows, the panels' sizes) it writes down as it changes it: see
// CanvasScreen and CanvasDock.

/// _Kept is one thing remembered: [put] hands the controller what the
/// preferences hold, without notifying; [keep] writes down what the
/// controller has now. A preference set to what it already holds is not
/// written again (CanvasPreferences), so keep costs nothing when nothing
/// has changed.
typedef _Kept = ({void Function() put, void Function() keep});

/// KeptView puts back how the Canvas page was left as it opens, and writes
/// it down as it changes and as the page is left.
class KeptView {
  final CanvasController _controller;
  final CanvasPreferences _prefs;

  KeptView(this._controller, this._prefs);

  /// _kept is how the page was left, whatever canvas is open. In the order
  /// it is put back: where the panels open comes before which are open,
  /// since each place shows one.
  late final List<_Kept> _kept = [
    (
      put: () => _controller.restoreFit(_prefs.fit),
      keep: () => _prefs.fit = _controller.fit,
    ),
    (
      put: () => _controller.restoreRulers(_prefs.rulers),
      keep: () => _prefs.rulers = _controller.rulers,
    ),
    (
      put: () => _controller.restoreShown(cues: _prefs.cuesShown),
      keep: () => _prefs.cuesShown = _controller.cuesShown,
    ),
    (
      put: () => _controller.restoreMixer(_prefs.mixerBands,
          returns: _prefs.returnsShown),
      keep: () {
        _prefs.mixerBands = _controller.mixerBandNames;
        _prefs.returnsShown = _controller.returnsShown;
      },
    ),
    (
      put: () => _controller.restoreMixerLook(_prefs.mixerLook),
      keep: () => _prefs.mixerLook = _controller.mixerLook,
    ),
    (
      put: () => _controller.restoreSnapping(_prefs.timelineSnap),
      keep: () => _prefs.timelineSnap = _controller.snapping,
    ),
    (
      put: () => _controller.restoreTrackpadScrolls(_prefs.timelineTrackpad),
      keep: () => _prefs.timelineTrackpad = _controller.trackpadScrolls,
    ),
    (
      put: () => _controller.restoreBarBelow(_prefs.barBelow),
      keep: () => _prefs.barBelow = _controller.barBelow,
    ),
    (
      put: () => _controller.restoreDock(_prefs.dock),
      keep: () => _prefs.dock = _controller.dock,
    ),
    (
      put: () => _controller.restorePanels(_prefs.panels),
      keep: () => _prefs.panels = _controller.panelState,
    ),
  ];

  /// _delay is how long after a change it is written down: a panel's edge
  /// being dragged, or a timeline scrolled, changes at every step.
  static const _delay = Duration(milliseconds: 800);
  Timer? _timer;

  /// _viewOf is the canvas whose view is kept, as "folder/name", or null
  /// for one never saved; _view is that view as last seen, which is what is
  /// written down. Not as it is now: by the time the page hears that
  /// another canvas has opened, the controller has let the last one's go.
  String? _viewOf;
  Map<String, dynamic>? _view;

  /// _loads is the controller's count of canvases opened when _viewOf was
  /// taken, so another one opening can be told from this one being saved
  /// under a name; -1 before the first look.
  int _loads = -1;

  String? get _canvasKey => _controller.name == null
      ? null
      : "${_controller.folder ?? ""}/${_controller.name}";

  /// open puts back how the page was left and starts keeping it. For the
  /// page's initState: nothing here notifies.
  ///
  /// Only the first time the page opens in a run of the app. The controller
  /// outlives the page, so after that it holds how things were left, and
  /// the preferences only follow it.
  void open() {
    if (!_controller.opened) {
      for (var kept in _kept) {
        kept.put();
      }
    }
    // chrome, not the controller: it passes over the playhead stepping on
    // and a drag's steps, and tells when either ends.
    _controller.chrome.addListener(_changed);
    _changed();
  }

  /// close writes down how the page is being left, and stops keeping.
  void close() {
    _closed = true;
    _controller.chrome.removeListener(_changed);
    if (_controller.loads == _loads) _view = _controller.canvasView;
    _write();
  }

  bool _closed = false;

  void _changed() {
    if (_controller.loads != _loads) {
      _another();
      return;
    }
    // Saved under a name, or under another: its view goes with it.
    _viewOf = _canvasKey;
    // Not while it plays: the timeline's view follows the playhead, and is
    // kept as it stops.
    if (_controller.playing) return;
    _view = _controller.canvasView;
    _timer ??= Timer(_delay, _write);
  }

  /// _another keeps the view of the canvas that was open, and puts back the
  /// view of the one that has opened in its place.
  void _another() {
    var first = _loads < 0;
    if (!first) _write();
    _loads = _controller.loads;
    _viewOf = _canvasKey;
    _view = null;
    // The page opening on the canvas the controller already holds: its view
    // is as it was left.
    if (first) return;
    // One never saved has no view kept. The controller let the last
    // canvas's go as this one opened, so it starts as any does.
    var key = _viewOf;
    if (key == null) return;
    var view = _prefs.canvasView(key);
    var loads = _loads;
    // After this change has been told: putting the view back tells again.
    scheduleMicrotask(() {
      if (_closed || _controller.loads != loads) return;
      // As left, or as any canvas starts for one never looked at.
      _controller.restoreCanvasView(view ?? const {});
    });
  }

  void _write() {
    _timer?.cancel();
    _timer = null;
    for (var kept in _kept) {
      kept.keep();
    }
    if ((_viewOf, _view) case (var key?, var view?)) {
      _prefs.setCanvasView(key, view);
    }
  }
}
