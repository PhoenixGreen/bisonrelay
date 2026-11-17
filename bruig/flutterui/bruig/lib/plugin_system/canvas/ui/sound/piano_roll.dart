import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart'
    show SessionClip, clipBarChoices;
import 'package:bruig/plugin_system/canvas/ui/timeline/automation_lanes.dart'
    show envelopeLengths, settingLabel;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/chain_icons.dart';
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/ui/sound/instrument_editor.dart'
    show keyRow;
import 'package:bruig/plugin_system/canvas/ui/mixer/mixer_plugins.dart'
    show
        chainMenuDivider,
        chainMenuHeading,
        chainMenuItem,
        chainMenuStyle,
        dragPointers;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'piano_roll_gestures.dart';
part 'piano_roll_lanes.dart';
part 'piano_roll_toolbar.dart';

// piano_roll.dart is the piano roll: a MIDI clip's notes, or a MIDI
// channel's part, on a grid of keys and beats, with a lane under them for
// note velocity or a controller's curve. It opens in the effects panel in
// place of the chain (see CanvasController.openPianoRoll). Everything here
// is in beats; the controller converts a part's seconds (rollContent,
// setRollContent). A drag is one change to undo.

/// rollGrids are the grids a piano roll snaps to, in beats.
const rollGrids = <(String, double)>[
  ("1/4", 1),
  ("1/8", 0.5),
  ("1/8 T", 1 / 3),
  ("1/16", 0.25),
  ("1/16 T", 1 / 6),
  ("1/32", 0.125),
];

/// RollLane is what the lane under the notes shows: each note's velocity,
/// one controller's curve -- or, for a clip, an envelope of one of its
/// channel's settings, [setting] by its id (see ClipAutomation).
class RollLane {
  final MidiControl? control;
  final String? setting;
  const RollLane(this.control) : setting = null;
  const RollLane.setting(String this.setting) : control = null;
  String get label => control?.label ?? "Velocity";
  static const velocity = RollLane(null);
  static final all = [
    velocity,
    for (var c in MidiControl.values) RollLane(c),
  ];
  @override
  bool operator ==(Object other) =>
      other is RollLane && other.control == control && other.setting == setting;
  @override
  int get hashCode => Object.hash(control, setting);
}

/// _keysW is the keys' width, and that of the lanes' panels under them.
const double _keysW = 84;
const double _rulerH = 22;

/// _laneH is a lane's height to start with; _laneLeast its shortest, open;
/// _headH the bar the lanes fold to; _splitH the edge above them, dragged
/// to make them taller or shorter.
const double _laneH = 84;
const double _laneLeast = 48;
const double _headH = 22;
const double _splitH = 6;
const double _toolbarH = 34;

/// _statusH is the roll's foot: its notes, tool and grid.
const double _statusH = 20;

/// _gridLeast is the least of the notes kept in view: a short roll folds
/// its lanes away before it gives the notes less.
const double _gridLeast = 48;

/// _closest is the zoom at its closest, a beat's width in pixels.
const double _closest = 160;

class PianoRoll extends StatefulWidget {
  final CanvasController controller;

  /// inClipEditor is whether it is the clip editor's notes: its length and
  /// the way back to the effects are the editor's, not its own.
  final bool inClipEditor;

  const PianoRoll(
      {required this.controller, this.inClipEditor = false, super.key});

  @override
  State<PianoRoll> createState() => _PianoRollState();
}

enum _Drag { none, draw, move, resize, box, paint, erase }

/// _Tool is what a press on the grid does; knife splits a note.
enum _Tool { draw, select, paint, erase, knife, mute }

/// rollChords are what Draw draws for each note, by the semitones above
/// it: one note; a chord; or, the last, a chord from the scale's own notes.
const List<(String, List<int>)> rollChords = [
  ("One note", []),
  ("Major", [0, 4, 7]),
  ("Minor", [0, 3, 7]),
  ("Seventh", [0, 4, 7, 10]),
  ("Major seventh", [0, 4, 7, 11]),
  ("Minor seventh", [0, 3, 7, 10]),
  ("Sus four", [0, 5, 7]),
  ("Power", [0, 7, 12]),
  ("From the scale", []),
];

/// _copied are the notes last copied, each from the first one's start:
/// shared by every piano roll, so a part's notes paste into a clip.
List<MidiNote> _copied = const [];

class _PianoRollState extends State<PianoRoll> {
  CanvasController get c => widget.controller;

  _Tool _tool = _Tool.draw;
  bool get _drawTool => _tool == _Tool.draw;

  /// _keep keeps notes drawn and moved in the scale; _chord is which of
  /// rollChords Draw draws; _ghost is the channel whose notes are shown
  /// faint behind these, by key, or null.
  bool _keep = false;
  int _chord = 0;
  String? _ghost;

  /// _painted are the steps a Paint drag has put a note on already.
  final Set<int> _painted = {};
  int _lastPainted = 0;
  double _grid = 0.25;
  bool _fold = false;
  bool _scale = true;

  /// _lanes are the lanes under the notes (one or two), each velocity or a
  /// controller's curve; _lanesOpen whether they show, or only headings.
  final List<RollLane> _lanes = [RollLane.velocity];
  bool _lanesOpen = false;

  /// _laneTall is each lane's height, as its edge was dragged -- as tall as
  /// there is room for, up to it; _edgeFrom and _tallFrom where the drag
  /// started, and the height then.
  double _laneTall = _laneH;
  double _edgeFrom = 0, _tallFrom = _laneH;

  /// _zoom is the zoom slider: nought the closest, one the whole of what is
  /// shown in the width there is. Null until moved: a beat 48 wide.
  double? _zoom;

  /// _zoomNow is the zoom as last drawn, and _zoomSpan how far apart its
  /// ends are (the log of the closest over the farthest): a pinch moves it
  /// in proportion. _pinchFrom is where a pinch began.
  double _zoomNow = 0, _zoomSpan = 1;
  double? _pinchFrom;

  /// _rowH is a key's height and _beatW a beat's width, zoomed by the slider.
  static const double _rowH = 12;
  double _beatW = 48;

  /// _selected are the notes picked: the controller's, so the clip
  /// editor's Notes tools change the same ones.
  Set<int> get _selected => c.rollSelected;
  final ScrollController _vertical = ScrollController();
  final ScrollController _grid1 = ScrollController();
  final ScrollController _ruler = ScrollController();
  final ScrollController _laneScroll = ScrollController();
  final ScrollController _laneScroll2 = ScrollController();
  final FocusNode _focus = FocusNode(debugLabel: "pianoRoll");
  bool _syncing = false;
  bool _scrolledToNotes = false;

  // A drag: what it is doing, where it started, and the notes as they were.
  _Drag _drag = _Drag.none;
  Offset _from = Offset.zero, _to = Offset.zero;
  List<MidiNote> _before = const [];
  int? _drawn;

  /// _laneNote and _lanePoint are the velocity bar or the curve's point
  /// being dragged in the lane -- kept here, not in the build, so a drag
  /// survives the rebuilds its own changes make.
  int? _laneNote;
  int? _lanePoint;

  @override
  void initState() {
    super.initState();
    for (var s in [_grid1, _ruler, _laneScroll, _laneScroll2]) {
      s.addListener(() => _follow(s));
    }
    c.addListener(_changed);
  }

  /// _changes tells the roll to rebuild: on every canvas change but the
  /// playhead moving on, which only its line follows (see _HeadPainter), so
  /// the notes are not laid out again at every frame of play.
  final ValueNotifier<int> _changes = ValueNotifier(0);

  void _changed() {
    if (c.notifyingPlayhead) return;
    _changes.value++;
  }

  /// _built is the roll as last built, handed back while nothing it shows
  /// has changed, since whatever holds it rebuilds every frame of play. Let
  /// go on a change of its own, of what it is given, or of what it inherits.
  Widget? _built;

  @override
  void setState(VoidCallback fn) {
    _built = null;
    super.setState(fn);
  }

  @override
  void didUpdateWidget(PianoRoll old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.inClipEditor != widget.inClipEditor) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _built = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
  }

  void _follow(ScrollController lead) {
    if (_syncing || !lead.hasClients) return;
    _syncing = true;
    for (var s in [_grid1, _ruler, _laneScroll, _laneScroll2]) {
      if (s == lead || !s.hasClients) continue;
      var p = s.position;
      var to = lead.offset.clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((p.pixels - to).abs() > 0.5) s.jumpTo(to);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _changes.dispose();
    _vertical.dispose();
    _grid1.dispose();
    _ruler.dispose();
    _laneScroll.dispose();
    _laneScroll2.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---- What it shows

  /// _scaleOf is the scale lit on the rows: the channel's Scale's, or C major.
  (int, List<int>) _scaleOf() {
    var part = c.instrumentOf(c.pianoRoll!.channel)?.instrument;
    var effect = part?.effects
        .where((e) => e.on && e.kind == MidiEffectKind.scale)
        .firstOrNull;
    if (effect == null) return (0, scaleSteps[0]);
    return (
      effect.choice("root"),
      scaleSteps[effect.choice("scale").clamp(0, scaleSteps.length - 1)]
    );
  }

  /// _keys are the rows, top to bottom: every key, or -- folded -- the
  /// scale's keys and any other in use, from an octave under the lowest
  /// note to an octave over the highest (C3 to C6 with none).
  List<int> _keys(List<MidiNote> notes) {
    if (!_fold) return [for (var k = 127; k >= 0; k--) k];
    var (root, steps) = _scaleOf();
    var used = {for (var n in notes) n.key};
    var lo = used.isEmpty ? 48 : math.max(0, used.reduce(math.min) - 12);
    var hi = used.isEmpty ? 84 : math.min(127, used.reduce(math.max) + 12);
    return [
      for (var k = hi; k >= lo; k--)
        if (used.contains(k) || steps.contains((k - root) % 12)) k
    ];
  }

  /// _inKey is [key] kept in the scale when Keep in key is on: the nearest
  /// key of it, the lower between two.
  int _inKey(int key) {
    if (!_keep) return key;
    var (root, steps) = _scaleOf();
    for (var d = 0; d < 12; d++) {
      if (steps.contains((key - d - root) % 12)) return key - d;
      if (steps.contains((key + d - root) % 12)) return key + d;
    }
    return key;
  }

  /// _stamp is what Draw puts down for [key]: it alone, or the chord on it.
  List<int> _stamp(int key) {
    key = _inKey(key);
    if (_chord <= 0 || _chord >= rollChords.length) return [key];
    if (_chord == rollChords.length - 1) {
      // A triad of the scale's own notes: every other one, up from it.
      var (root, steps) = _scaleOf();
      var up = [
        for (var k = key; k <= math.min(127, key + 24); k++)
          if (steps.contains((k - root) % 12)) k
      ];
      return [
        for (var i in [0, 2, 4])
          if (i < up.length) up[i]
      ];
    }
    return [
      for (var d in rollChords[_chord].$2)
        if (key + d <= 127) key + d
    ];
  }

  /// _ghostNotes are the notes of the channel chosen to show faint, in
  /// beats: its clip in the same slot row, or its part.
  List<MidiNote> _ghostNotes() {
    var key = _ghost;
    if (key == null) return const [];
    var row = c.pianoRoll?.row;
    if (row != null) return c.session.at(key, row)?.notes ?? const [];
    var spb = c.document.audio.secondsPerBeat;
    return [
      for (var n
          in c.instrumentOf(key)?.instrument?.notes ?? const <MidiNote>[])
        n.copyWith(start: n.start / spb, length: n.length / spb),
    ];
  }

  double _snap(double beat) => (beat / _grid).floor() * _grid;
  double _round(double beat) => (beat / _grid).round() * _grid;

  // ---- Writing

  void _write(List<MidiNote> notes, {bool transient = false}) {
    if (transient) c.beginInteraction();
    c.setRollContent(notes: notes, transient: transient);
    if (!transient) c.endInteraction();
  }

  void _writeControls(Map<MidiControl, List<ControlPoint>> controls,
      {bool transient = false}) {
    if (transient) c.beginInteraction();
    c.setRollContent(controls: controls, transient: transient);
    if (!transient) c.endInteraction();
  }

  void _delete() {
    var content = c.rollContent;
    if (content == null || _selected.isEmpty) return;
    var notes = [
      for (var (i, n) in content.notes.indexed)
        if (!_selected.contains(i)) n,
    ];
    _selected.clear();
    _write(notes);
  }

  /// _copy keeps the notes picked, to paste -- and, cut, takes them out.
  void _copy({bool cut = false}) {
    var content = c.rollContent;
    if (content == null || _selected.isEmpty) return;
    var picked = [
      for (var (i, n) in content.notes.indexed)
        if (_selected.contains(i)) n,
    ];
    var from = picked.map((n) => n.start).reduce(math.min);
    _copied = [for (var n in picked) n.copyWith(start: n.start - from)];
    if (cut) _delete();
    setState(() {});
  }

  /// _paste puts the notes copied at the playhead, picked; and, stopped,
  /// moves the playhead on past them, so the next paste follows on.
  void _paste() {
    var content = c.rollContent;
    if (content == null || _copied.isEmpty) return;
    var at = c.rollPlayhead ?? c.rollCursor;
    var added = [
      for (var n in _copied)
        if (!content.clip || n.start + at < content.beats)
          n.copyWith(start: n.start + at),
    ];
    if (added.isEmpty) return;
    _write([...content.notes, ...added]);
    _selected
      ..clear()
      ..addAll([
        for (var i = 0; i < added.length; i++) content.notes.length + i,
      ]);
    if (!c.playing) {
      var span = _copied.map((n) => n.end).reduce(math.max);
      c.rollCursor = at + math.max(_grid, (span / _grid).ceil() * _grid);
    }
    setState(() {});
  }

  void _selectAll() {
    var content = c.rollContent;
    if (content == null) return;
    setState(() => _selected
      ..clear()
      ..addAll([for (var i = 0; i < content.notes.length; i++) i]));
  }

  /// _quantise moves the picked notes (or all) and their lengths onto the grid.
  void _quantise() {
    var content = c.rollContent;
    if (content == null) return;
    var all = _selected.isEmpty;
    _write([
      for (var (i, n) in content.notes.indexed)
        if (all || _selected.contains(i))
          n.copyWith(
              start: _round(n.start), length: math.max(_grid, _round(n.length)))
        else
          n,
    ]);
  }

  void _nudge(double beats, int keys) {
    var content = c.rollContent;
    if (content == null || _selected.isEmpty) return;
    _write([
      for (var (i, n) in content.notes.indexed)
        _selected.contains(i)
            ? n.copyWith(
                start: math.max(0, n.start + beats),
                key: (n.key + keys).clamp(0, 127))
            : n,
    ]);
  }

  /// _stepOctave is the C Step input's computer keys start from.
  int _stepOctave = 60;

  // ---- piano_roll_gestures.dart -------------------------------------------

  // ---- The grid's gestures

  // ---- Building

  @override
  Widget build(BuildContext context) => _built ??= ListenableBuilder(
        listenable: _changes,
        builder: (context, _) {
          pianoRollBuilds++;
          var content = c.rollContent;
          var look = MixerLook.of(context);
          if (content == null) return const SizedBox();
          _selected.removeWhere((i) => i >= content.notes.length);
          var keys = _keys(content.notes);
          var (root, steps) = _scaleOf();
          if (!_scrolledToNotes) {
            _scrolledToNotes = true;
            // Opened on the notes, or on middle C with none.
            var middle = content.notes.isEmpty
                ? 60
                : content.notes.map((n) => n.key).reduce((a, b) => a + b) ~/
                    content.notes.length;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_vertical.hasClients) return;
              var row = keys.indexOf(middle);
              var to = row * _rowH - _vertical.position.viewportDimension / 2;
              _vertical.jumpTo(to.clamp(0, _vertical.position.maxScrollExtent));
            });
          }
          return LayoutBuilder(builder: (context, box) {
            // The zoom: from the closest to the whole of it (32 bars or one).
            var gridW = math.max(40.0, box.maxWidth - _keysW);
            // The farthest is the whole of it, at no more than 48 a beat:
            // a short clip shown at its ordinary size, not stretched.
            var far = math.min(48.0, gridW / math.max(1.0, content.beats));
            var t = _zoom ??
                (far >= 48
                    ? 1.0
                    : math.log(_closest / 48) / math.log(_closest / far));
            _beatW = math.exp(math.log(_closest) +
                (math.log(far) - math.log(_closest)) * t.clamp(0.0, 1.0));
            _zoomNow = t.clamp(0.0, 1.0);
            _zoomSpan = math.max(0.01, math.log(_closest / far));
            var width = content.beats * _beatW;
            // The lanes: as tall as dragged, up to the room there is over
            // the notes' least; short of their least, folded to a bar --
            // and short of that, not there.
            var height = box.maxHeight.isFinite ? box.maxHeight : 480.0;
            // The foot, where there is room for it beside the notes.
            var status = height >= 220;
            var room = height - _toolbarH - _rulerH - (status ? _statusH : 0);
            var showLanes = room - _headH >= 24;
            var tallest = (room - _splitH - _gridLeast) / _lanes.length;
            var open = showLanes && _lanesOpen && tallest >= _laneLeast;
            var laneH = open ? math.min(_laneTall, tallest) : 0.0;
            return Focus(
              focusNode: _focus,
              onKeyEvent: _onKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _toolbar(look, content, t),
                    SizedBox(
                      height: _rulerH,
                      child: Row(children: [
                        SizedBox(
                          width: _keysW,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, top: 4),
                            child: Text("keys",
                                style: TextStyle(
                                    fontSize: 9.5, color: look.studio.muted)),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _ruler,
                            scrollDirection: Axis.horizontal,
                            // Pressed or dragged, the playhead
                            // goes there, on the grid.
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                key: const ValueKey("rollRuler"),
                                supportedDevices: dragPointers,
                                behavior: HitTestBehavior.opaque,
                                dragStartBehavior: DragStartBehavior.down,
                                onTapUp: (d) =>
                                    _putHead(d.localPosition.dx, content),
                                onHorizontalDragStart: (d) =>
                                    _putHead(d.localPosition.dx, content),
                                onHorizontalDragUpdate: (d) =>
                                    _putHead(d.localPosition.dx, content),
                                child: CustomPaint(
                                  size: Size(width, _rulerH),
                                  painter: _RulerPainter(content.beats, _beatW,
                                      c.document.audio.beatsPerBar, look.studio,
                                      clip: content.clip),
                                  foregroundPainter: _HeadPainter(
                                      c, _beatW, look.studio,
                                      marker: true),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: _keysW,
                                height: keys.length * _rowH,
                                child: CustomPaint(
                                  painter: _KeysPainter(
                                      keys, _rowH, look.studio,
                                      named: _fold),
                                ),
                              ),
                              Expanded(
                                // Pinched on a trackpad: closer, or farther.
                                child: Listener(
                                  onPointerPanZoomStart: (_) =>
                                      _pinchFrom = _zoomNow,
                                  onPointerPanZoomUpdate: (e) {
                                    var from = _pinchFrom;
                                    if (from == null ||
                                        (e.scale - 1).abs() < 0.01) {
                                      return;
                                    }
                                    setState(() => _zoom =
                                        (from - math.log(e.scale) / _zoomSpan)
                                            .clamp(0.0, 1.0));
                                  },
                                  onPointerPanZoomEnd: (_) => _pinchFrom = null,
                                  child: SingleChildScrollView(
                                    controller: _grid1,
                                    scrollDirection: Axis.horizontal,
                                    child: GestureDetector(
                                      key: const ValueKey("rollGrid"),
                                      // Not swiped: two fingers scrolling on
                                      // a trackpad would draw notes.
                                      supportedDevices: dragPointers,
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (d) => _tapGrid(
                                          d.localPosition, content, keys),
                                      // A right-click takes a note out: a
                                      // double-click's wait would hold back
                                      // every note drawn.
                                      onSecondaryTapUp: (d) {
                                        var hit = _hit(d.localPosition,
                                            content.notes, keys);
                                        if (hit == null) return;
                                        _selected
                                          ..clear()
                                          ..add(hit.$1);
                                        _delete();
                                      },
                                      // From the press, not from where the drag
                                      // was told apart from a click.
                                      dragStartBehavior: DragStartBehavior.down,
                                      onPanStart: (d) => _startDrag(
                                          d.localPosition, content, keys),
                                      onPanUpdate: (d) =>
                                          _updateDrag(d.localPosition, keys),
                                      onPanEnd: (_) => _endDrag(),
                                      child: CustomPaint(
                                        size: Size(width, keys.length * _rowH),
                                        painter: _GridPainter(
                                          notes: content.notes,
                                          keys: keys,
                                          rowH: _rowH,
                                          beatW: _beatW,
                                          beats: content.beats,
                                          beatsPerBar:
                                              c.document.audio.beatsPerBar,
                                          grid: _grid,
                                          selected: {..._selected},
                                          ghosts: _ghostNotes(),
                                          root: root,
                                          steps: _scale ? steps : null,
                                          box: _drag == _Drag.box
                                              ? Rect.fromPoints(_from, _to)
                                              : null,
                                          studio: look.studio,
                                        ),
                                        foregroundPainter: _HeadPainter(
                                            c, _beatW, look.studio),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
                      ),
                    ),
                    // The lanes, each chosen in its panel at the left; the edge
                    // above them drags their height.
                    if (showLanes && open) ...[
                      _laneEdge(look, laneH, tallest),
                      for (var (i, lane) in _lanes.indexed)
                        SizedBox(
                          height: laneH,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _lanePanel(look, i),
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller:
                                        i == 0 ? _laneScroll : _laneScroll2,
                                    scrollDirection: Axis.horizontal,
                                    child: _laneArea(
                                        content, look, width, lane, laneH),
                                  ),
                                ),
                              ]),
                        ),
                    ] else if (showLanes)
                      _foldedLanes(look, canOpen: tallest >= _laneLeast),
                    if (status) _status(look, content),
                  ]),
            );
          });
        },
      );

  // ---- piano_roll_toolbar.dart --------------------------------------------

  static String _trim(double b) =>
      b == b.roundToDouble() ? "${b.round()}" : b.toStringAsFixed(2);
}

// ---- The painters

const _noteNames = [
  "C",
  "C♯",
  "D",
  "E♭",
  "E",
  "F",
  "F♯",
  "G",
  "A♭",
  "A",
  "B♭",
  "B"
];

class _KeysPainter extends CustomPainter {
  final List<int> keys;
  final double rowH;
  final StudioColors studio;
  final bool named;
  _KeysPainter(this.keys, this.rowH, this.studio, {required this.named});

  @override
  void paint(Canvas canvas, Size size) {
    for (var (i, k) in keys.indexed) {
      var black = isBlackKey(k);
      var r = Rect.fromLTWH(0, i * rowH, size.width, rowH);
      canvas.drawRect(
          r,
          Paint()
            ..color =
                black ? const Color(0xFF24262B) : const Color(0xFFD9DCE2));
      canvas.drawLine(r.bottomLeft, r.bottomRight,
          Paint()..color = const Color(0xFF8A8F99));
      if (k % 12 == 0 || named) {
        var tp = TextPainter(
          text: TextSpan(
              text: "${_noteNames[k % 12]}${k ~/ 12 - 1}",
              style: TextStyle(
                  fontSize: 8,
                  color: black
                      ? const Color(0xFFC9CCD2)
                      : const Color(0xFF26282D))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas,
            Offset(size.width - tp.width - 4, r.center.dy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) =>
      old.keys.length != keys.length ||
      old.named != named ||
      old.studio != studio;
}

class _RulerPainter extends CustomPainter {
  final double beats, beatW;
  final int beatsPerBar;
  final StudioColors studio;
  final bool clip;

  _RulerPainter(this.beats, this.beatW, this.beatsPerBar, this.studio,
      {required this.clip});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.panel);
    // A clip's loop, as a brace along the top.
    if (clip) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 2, beats * beatW, 4), const Radius.circular(2)),
          Paint()..color = studio.on.withValues(alpha: 0.85));
    }
    var step = beatW < 20 ? beatsPerBar : 1;
    for (var b = 0; b < beats; b += step) {
      var bar = b % beatsPerBar == 0;
      var tp = TextPainter(
        text: TextSpan(
            text:
                "${b ~/ beatsPerBar + 1}${bar ? "" : ".${b % beatsPerBar + 1}"}",
            style: TextStyle(
                fontSize: 9, color: bar ? studio.text : studio.muted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(b * beatW + 3, 8));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.beats != beats || old.beatW != beatW || old.clip != clip;
}

class _GridPainter extends CustomPainter {
  final List<MidiNote> notes;
  final List<int> keys;
  final double rowH, beatW, beats, grid;
  final int beatsPerBar;
  final Set<int> selected;

  /// ghosts are another channel's notes, drawn faint behind these.
  final List<MidiNote> ghosts;
  final int root;
  final List<int>? steps;

  final Rect? box;
  final StudioColors studio;

  _GridPainter({
    required this.notes,
    required this.keys,
    required this.rowH,
    required this.beatW,
    required this.beats,
    required this.beatsPerBar,
    required this.grid,
    required this.selected,
    this.ghosts = const [],
    required this.root,
    required this.steps,
    required this.box,
    required this.studio,
  });

  /// _note is a note's colour, the MIDI orange.
  static const _note = Color(0xFFD08F3E);

  @override
  void paint(Canvas canvas, Size size) {
    var inScale = steps == null ? null : {for (var s in steps!) s};
    // Rows: in the scale lit, the rest darker, C picked out.
    for (var (i, k) in keys.indexed) {
      var pc = (k - root) % 12;
      var lit = inScale == null ? !isBlackKey(k) : inScale.contains(pc);
      canvas.drawRect(
          Rect.fromLTWH(0, i * rowH, size.width, rowH),
          Paint()
            ..color = k % 12 == 0
                ? const Color(0xFF23252B)
                : lit
                    ? const Color(0xFF1D1F24)
                    : const Color(0xFF141518));
      canvas.drawLine(
          Offset(0, (i + 1) * rowH),
          Offset(size.width, (i + 1) * rowH),
          Paint()..color = const Color(0xFF22242A));
    }
    var cols = (beats / grid).round();
    for (var i = 0; i <= cols; i++) {
      var b = i * grid;
      var x = b * beatW;
      var bar = (b / beatsPerBar - (b / beatsPerBar).round()).abs() < 1e-6;
      var beat = (b - b.round()).abs() < 1e-6;
      if (!bar && !beat && grid * beatW < 6) continue;
      canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = bar
                ? const Color(0xFF5A5E66)
                : beat
                    ? const Color(0xFF3A3D44)
                    : const Color(0xFF26282D));
    }
    canvas.drawRect(Rect.fromLTRB(beats * beatW, 0, size.width, size.height),
        Paint()..color = const Color(0x66000000));
    for (var n in ghosts) {
      var row = keys.indexOf(n.key);
      if (row < 0) continue;
      var r = RRect.fromRectAndRadius(
          Rect.fromLTWH(n.start * beatW, row * rowH + 1,
              math.max(4, n.length * beatW - 1), rowH - 2),
          const Radius.circular(2));
      canvas.drawRRect(r, Paint()..color = const Color(0x14FFFFFF));
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = const Color(0x40FFFFFF));
    }
    // The notes, coloured by how hard they are played: a muted one hollow,
    // one left to chance the fainter the less likely.
    for (var (i, n) in notes.indexed) {
      var row = keys.indexOf(n.key);
      if (row < 0) continue;
      var r = Rect.fromLTWH(n.start * beatW, row * rowH + 1,
          math.max(4, n.length * beatW - 1), rowH - 2);
      var v = n.velocity / 127;
      var picked = selected.contains(i);
      // The MIDI orange, as solid as the note is likely to play, and a line
      // along its foot as long as it is hard.
      if (!n.muted) {
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)),
            Paint()..color = _note.withValues(alpha: 0.35 + 0.65 * n.chance));
        if (r.width > 8) {
          canvas.drawRect(
              Rect.fromLTWH(r.left + 2, r.bottom - 3, (r.width - 4) * v, 1.5),
              Paint()..color = Colors.white.withValues(alpha: 0.55));
        }
      }
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(2)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = picked ? 1.5 : 1
            ..color =
                picked ? Colors.white : Color.lerp(_note, Colors.black, 0.35)!);
      if (r.width >= 26 && rowH >= 11) {
        var name = TextPainter(
            text: TextSpan(
                text: "${_noteNames[n.key % 12]}${n.key ~/ 12 - 1}",
                style: TextStyle(
                    fontSize: math.min(9.5, rowH - 3),
                    fontWeight: FontWeight.w600,
                    color: n.muted ? _note : const Color(0xFF1E1A10))),
            textDirection: TextDirection.ltr)
          ..layout(maxWidth: r.width - 4);
        name.paint(canvas,
            Offset(r.left + 3, r.top + (rowH - 2 - name.height) / 2 - 1));
      }
    }
    if (box case var b?) {
      canvas.drawRect(b, Paint()..color = studio.on.withValues(alpha: 0.12));
      canvas.drawRect(
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = studio.on);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => true;
}

/// _HeadPainter is the playhead over the grid (a line, brighter while it
/// plays) or over the ruler (a marker), repainted as it moves
/// (CanvasController.playheadMoved) with nothing under it rebuilt.
/// pianoRollBuilds counts builds, for a test that play does not rebuild.
@visibleForTesting
int pianoRollBuilds = 0;

class _HeadPainter extends CustomPainter {
  final CanvasController c;
  final double beatW;
  final StudioColors studio;
  final bool marker;
  _HeadPainter(this.c, this.beatW, this.studio, {this.marker = false})
      : super(repaint: c.playheadMoved);

  @override
  void paint(Canvas canvas, Size size) {
    var playing = c.rollPlayhead;
    var x = (playing ?? c.rollCursor) * beatW;
    if (marker) {
      canvas.drawPath(
          Path()
            ..moveTo(x - 5, size.height - 9)
            ..lineTo(x + 5, size.height - 9)
            ..lineTo(x, size.height)
            ..close(),
          Paint()..color = studio.text);
      return;
    }
    canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..strokeWidth = playing != null ? 2 : 1
          ..color = studio.text.withValues(alpha: playing != null ? 0.8 : 0.5));
  }

  @override
  bool shouldRepaint(_HeadPainter old) =>
      old.c != c ||
      old.beatW != beatW ||
      old.studio != studio ||
      old.marker != marker;
}

class _VelocityPainter extends CustomPainter {
  final List<MidiNote> notes;
  final double beatW;
  final Set<int> selected;
  final StudioColors studio;
  _VelocityPainter(this.notes, this.beatW, this.selected, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF141518));
    for (var (i, n) in notes.indexed) {
      var h = (size.height - 8) * n.velocity / 127;
      var x = n.start * beatW;
      canvas.drawRect(
          Rect.fromLTWH(x, size.height - 4 - h, 4, h),
          Paint()
            ..color =
                selected.contains(i) ? Colors.white : const Color(0xFFD08F3E));
      canvas.drawCircle(Offset(x + 2, size.height - 4 - h), 2.5,
          Paint()..color = studio.text);
    }
  }

  @override
  bool shouldRepaint(_VelocityPainter old) => true;
}

class _CurvePainter extends CustomPainter {
  final List<ControlPoint> points;
  final double rest, beatW;
  final StudioColors studio;

  /// length is a curve's own length, in beats, drawn round and round --
  /// fainter after the first -- or null for one drawn once.
  final double? length;
  _CurvePainter(this.points, this.rest, this.beatW, this.studio, {this.length});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF141518));
    double y(double v) => 4 + (1 - v) * (size.height - 8);
    canvas.drawLine(Offset(0, y(rest)), Offset(size.width, y(rest)),
        Paint()..color = studio.edge);
    if (points.isEmpty) return;
    var span = length == null ? null : length! * beatW;
    Path once(double from, double to) {
      var path = Path()..moveTo(from, y(points.first.$2));
      for (var (t, v) in points) {
        path.lineTo(from + t * beatW, y(v));
      }
      return path..lineTo(to, y(points.last.$2));
    }

    if (span != null && span > 1) {
      var faint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = studio.on.withValues(alpha: 0.35);
      for (var x = span; x < size.width; x += span) {
        canvas.drawPath(once(x, x + span), faint);
      }
      canvas.drawLine(Offset(span, 0), Offset(span, size.height),
          Paint()..color = studio.on.withValues(alpha: 0.5));
    }
    var path = once(0, span ?? size.width);
    var fill = Path.from(path)
      ..lineTo(span ?? size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = studio.on.withValues(alpha: 0.12));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = studio.on);
    for (var (t, v) in points) {
      canvas.drawCircle(
          Offset(t * beatW, y(v)), 3.5, Paint()..color = studio.text);
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) => true;
}
