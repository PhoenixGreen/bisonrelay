import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/automation.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart'
    show SessionClip, clipBarChoices;
import 'package:bruig/plugin_system/canvas/ui/automation_lanes.dart'
    show envelopeLengths, settingLabel;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/chain_icons.dart';
import 'package:bruig/plugin_system/canvas/model/note_tools.dart';
import 'package:bruig/plugin_system/canvas/ui/instrument_editor.dart'
    show keyRow;
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
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

// piano_roll.dart is the piano roll: a MIDI clip's notes, or a MIDI
// channel's part, on a grid of keys and beats, with a lane under them for
// each note's velocity or a controller's curve. It opens in the effects
// panel in place of the chain (see CanvasController.openPianoRoll), as
// Ableton's clip view does.
//
// A press on the grid draws a note (or picks one), a drag draws a longer one
// or moves or stretches those picked, a right-click takes one out. The ruler
// holds the playhead: where Play starts and a paste lands. Everything here
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

/// _keysW is the keys' width, and the lanes' panels' under them: room for
/// what a lane shows, chosen there.
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

/// _Tool is what a press on the grid does: draw a note (or a chord),
/// select and move, paint a run of notes, erase, split a note, mute one.
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

  /// _lanes are the lanes under the notes -- one, or two -- each the
  /// notes' velocity or a controller's curve; _lanesOpen whether they show,
  /// or only their headings.
  final List<RollLane> _lanes = [RollLane.velocity];
  // Folded to begin with, as Ken asked: opened when they are wanted.
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

  /// _rowH and _beatW are the grid's measures: a key's height, a beat's
  /// width -- the width zoomed with the slider.
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

  /// _changes tells the roll to be built again: on every change the canvas
  /// tells of but the playhead moving on, which only its line follows (see
  /// _HeadPainter). Ken's systems review, 2026-11-08: every note was laid
  /// out again at every frame of play.
  final ValueNotifier<int> _changes = ValueNotifier(0);

  void _changed() {
    if (c.notifyingPlayhead) return;
    _changes.value++;
  }

  /// _built is the roll as last built, handed back while nothing it shows
  /// has changed -- whatever holds it is built again at every frame of
  /// play. Let go of on a change of its own, of what it is given, or of
  /// what it inherits.
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

  /// _scaleOf is the scale lit on the rows: the channel's Scale effect's,
  /// where it has one, or C major.
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

  /// _quantise moves the picked notes -- or every one, with none picked --
  /// onto the grid, and their lengths to whole steps of it.
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

  /// _stepKey plays Step input from the computer's keys, as the instrument
  /// editor's keys play: A to ' a note each from the octave's C (held
  /// together, a chord), Z and X an octave down and up, Tab a rest. Null
  /// for a key it leaves to the roll.
  KeyEventResult? _stepKey(KeyEvent e) {
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return null;
    }
    var t = c.pianoRoll;
    var element = t == null ? null : c.instrumentOf(t.channel);
    if (element == null) return null;
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab) {
      c.stepRest();
      return KeyEventResult.handled;
    }
    var ch = e.character?.toLowerCase() ?? e.logicalKey.keyLabel.toLowerCase();
    if (ch == "z" || ch == "x") {
      if (e is KeyDownEvent) {
        setState(() => _stepOctave =
            (_stepOctave + (ch == "z" ? -12 : 12)).clamp(12, 108));
      }
      return KeyEventResult.handled;
    }
    var i = ch.length == 1 ? keyRow.indexOf(ch) : -1;
    if (i < 0) return null;
    if (e is KeyDownEvent) c.noteOn(element, _stepOctave + i);
    if (e is KeyUpEvent) c.noteOff(element, _stepOctave + i);
    return KeyEventResult.handled;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (c.rollStep) {
      if (_stepKey(e) case var handled?) return handled;
    }
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var shift = HardwareKeyboard.instance.isShiftPressed;
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed) {
      switch (e.logicalKey) {
        case LogicalKeyboardKey.keyC:
          _copy();
        case LogicalKeyboardKey.keyX:
          _copy(cut: true);
        case LogicalKeyboardKey.keyV:
          _paste();
        case LogicalKeyboardKey.keyA:
          _selectAll();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    switch (e.logicalKey) {
      // The tools by their keys, as the toolbar shows them.
      case LogicalKeyboardKey.keyV:
        setState(() => _tool = _Tool.select);
      case LogicalKeyboardKey.keyD:
        setState(() => _tool = _Tool.draw);
      case LogicalKeyboardKey.keyB:
        setState(() => _tool = _Tool.paint);
      case LogicalKeyboardKey.keyE:
        setState(() => _tool = _Tool.erase);
      case LogicalKeyboardKey.keyC:
        setState(() => _tool = _Tool.knife);
      case LogicalKeyboardKey.keyM:
        setState(() => _tool = _Tool.mute);
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        _delete();
      case LogicalKeyboardKey.arrowUp:
        _nudge(0, shift ? 12 : 1);
      case LogicalKeyboardKey.arrowDown:
        _nudge(0, shift ? -12 : -1);
      case LogicalKeyboardKey.arrowLeft:
        _nudge(-_grid, 0);
      case LogicalKeyboardKey.arrowRight:
        _nudge(_grid, 0);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ---- The grid's gestures

  /// _hit is the note under [p] and whether it is at its right end, where
  /// a drag stretches it.
  (int, bool)? _hit(Offset p, List<MidiNote> notes, List<int> keys) {
    for (var i = notes.length - 1; i >= 0; i--) {
      var n = notes[i];
      var row = keys.indexOf(n.key);
      if (row < 0) continue;
      var r = Rect.fromLTWH(
          n.start * _beatW, row * _rowH, math.max(4, n.length * _beatW), _rowH);
      if (r.contains(p)) return (i, p.dx > r.right - 6);
    }
    return null;
  }

  int? _keyAt(double y, List<int> keys) {
    var row = (y / _rowH).floor();
    return row < 0 || row >= keys.length ? null : keys[row];
  }

  void _tapGrid(Offset p, RollContent content, List<int> keys) {
    _focus.requestFocus();
    var hit = _hit(p, content.notes, keys);
    setState(() {
      if (hit != null) {
        if (!HardwareKeyboard.instance.isShiftPressed) _selected.clear();
        _selected.add(hit.$1);
        return;
      }
      _selected.clear();
    });
    switch (_tool) {
      case _Tool.erase:
        if (hit != null) {
          _write([...content.notes]..removeAt(hit.$1));
          _selected.clear();
        }
        return;
      case _Tool.knife:
        // Cut in two where it was pressed, on the grid.
        if (hit == null) return;
        var n = content.notes[hit.$1];
        var at = _round(p.dx / _beatW);
        if (at <= n.start + 1e-6 || at >= n.end - 1e-6) return;
        _write([
          for (var (i, m) in content.notes.indexed)
            if (i == hit.$1) ...[
              m.copyWith(length: at - m.start),
              m.copyWith(start: at, length: m.end - at),
            ] else
              m,
        ]);
        _selected.clear();
        return;
      case _Tool.mute:
        // It -- or, picked among others, all those picked -- muted, or
        // played again.
        if (hit == null) return;
        var which = _selected.length > 1 && _selected.contains(hit.$1)
            ? {..._selected}
            : {hit.$1};
        var muting = !content.notes[hit.$1].muted;
        _write([
          for (var (i, m) in content.notes.indexed)
            which.contains(i) ? m.copyWith(muted: muting) : m,
        ]);
        return;
      case _Tool.draw:
        if (hit != null) return;
        var key = _keyAt(p.dy, keys);
        if (key == null) return;
        var start = _snap(p.dx / _beatW);
        if (start >= content.beats) return;
        var put = [for (var k in _stamp(key)) MidiNote(k, start, _grid, 100)];
        _write([...content.notes, ...put]);
        setState(() => _selected
          ..clear()
          ..addAll(
              [for (var i = 0; i < put.length; i++) content.notes.length + i]));
      case _Tool.select || _Tool.paint:
        return;
    }
  }

  void _startDrag(Offset p, RollContent content, List<int> keys) {
    _focus.requestFocus();
    _from = p;
    _to = p;
    _before = content.notes;
    var hit = _hit(p, content.notes, keys);
    if (_tool == _Tool.erase) {
      _drag = _Drag.erase;
      _eraseAt(p, keys);
      setState(() {});
      return;
    }
    if (_tool == _Tool.paint) {
      var key = _keyAt(p.dy, keys);
      if (key == null) return;
      _drag = _Drag.paint;
      _painted.clear();
      _paintAt(p, _inKey(key));
      setState(() {});
      return;
    }
    if (_tool == _Tool.knife || _tool == _Tool.mute) {
      _drag = _Drag.none;
      return;
    }
    if (hit != null) {
      if (!_selected.contains(hit.$1)) {
        _selected
          ..clear()
          ..add(hit.$1);
      }
      _drag = hit.$2 ? _Drag.resize : _Drag.move;
    } else if (_drawTool) {
      var key = _keyAt(p.dy, keys);
      if (key == null) return;
      _drag = _Drag.draw;
      _drawn = content.notes.length;
      var put = [
        for (var k in _stamp(key)) MidiNote(k, _snap(p.dx / _beatW), _grid, 100)
      ];
      _selected
        ..clear()
        ..addAll([for (var i = 0; i < put.length; i++) _drawn! + i]);
      _write([...content.notes, ...put], transient: true);
    } else {
      _drag = _Drag.box;
      _selected.clear();
    }
    setState(() {});
  }

  void _updateDrag(Offset p, List<int> keys) {
    _to = p;
    var dx = (p.dx - _from.dx) / _beatW;
    switch (_drag) {
      case _Drag.draw:
        var n = _before.length;
        var start = _snap(_from.dx / _beatW);
        var key = _keyAt(_from.dy, keys) ?? 60;
        var end = math.max(start + _grid, _round(p.dx / _beatW));
        _write([
          ..._before.take(n),
          for (var k in _stamp(key)) MidiNote(k, start, end - start, 100)
        ], transient: true);
      case _Drag.paint:
        var key = _keyAt(_from.dy, keys) ?? 60;
        _paintAt(p, _inKey(key));
      case _Drag.erase:
        _eraseAt(p, keys);
      case _Drag.move:
        var steps = _round(dx);
        var rows = ((p.dy - _from.dy) / _rowH).round();
        _write([
          for (var (i, n) in _before.indexed)
            if (_selected.contains(i))
              n.copyWith(
                  start: math.max(0, n.start + steps),
                  key: _inKey(_shiftKey(n.key, rows, keys)))
            else
              n,
        ], transient: true);
      case _Drag.resize:
        _write([
          for (var (i, n) in _before.indexed)
            if (_selected.contains(i))
              n.copyWith(length: math.max(_grid, _round(n.length + dx)))
            else
              n,
        ], transient: true);
      case _Drag.box:
        var box = Rect.fromPoints(_from, p);
        _selected
          ..clear()
          ..addAll([
            for (var (i, n) in _before.indexed)
              if (keys.indexOf(n.key) case var row when row >= 0)
                if (box.overlaps(Rect.fromLTWH(n.start * _beatW, row * _rowH,
                    math.max(4, n.length * _beatW), _rowH)))
                  i,
          ]);
      case _Drag.none:
        break;
    }
    setState(() {});
  }

  /// _shiftKey is [key] moved [rows] rows down the grid as it is drawn --
  /// folded, from one used key to the next.
  int _shiftKey(int key, int rows, List<int> keys) {
    var at = keys.indexOf(key);
    if (at < 0) return key;
    return keys[(at + rows).clamp(0, keys.length - 1)];
  }

  /// _paintAt puts a note of [key] on the grid step under [p], once per
  /// step a Paint drag passes.
  void _paintAt(Offset p, int key) {
    var content = c.rollContent;
    if (content == null) return;
    var step = (p.dx / _beatW / _grid).floor();
    var last = (content.beats / _grid).ceil() - 1;
    if (step < 0 || step > last) return;
    // Every step from the last one painted: a quick drag passes several
    // between two moves of the pointer.
    var from = _painted.isEmpty ? step : _lastPainted;
    var steps = [
      for (var k = math.min(from, step); k <= math.max(from, step); k++)
        if (!_painted.contains(k)) k
    ];
    _lastPainted = step;
    if (steps.isEmpty) return;
    _painted.addAll(steps);
    _write([
      ...content.notes,
      for (var k in steps) MidiNote(key, k * _grid, _grid, 100)
    ], transient: true);
  }

  /// _eraseAt takes out the note under [p].
  void _eraseAt(Offset p, List<int> keys) {
    var content = c.rollContent;
    if (content == null) return;
    var hit = _hit(p, content.notes, keys);
    if (hit == null) return;
    _selected.clear();
    _write([...content.notes]..removeAt(hit.$1), transient: true);
  }

  void _endDrag() {
    if (_drag != _Drag.box && _drag != _Drag.none) c.endInteraction();
    _drag = _Drag.none;
    _drawn = null;
    setState(() {});
  }

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
            // The zoom: from the closest to the whole of it in the width
            // there is -- 32 bars or one.
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
                    // The ruler, over the grid.
                    SizedBox(
                      height: _rulerH,
                      child: Row(children: [
                        // The keys' corner, named as the prototype's.
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
                            // Pressed or dragged, the playhead goes there,
                            // to the grid.
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
                                      // Pressed and dragged, never swiped past: two fingers on
                                      // a trackpad would draw notes as they scrolled.
                                      supportedDevices: dragPointers,
                                      behavior: HitTestBehavior.opaque,
                                      onTapUp: (d) => _tapGrid(
                                          d.localPosition, content, keys),
                                      // Right-clicked, a note is taken out: a double-click would
                                      // hold back every note drawn while it waited.
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
                    // The lanes: velocity, or a controller, each chosen in its
                    // panel at the left; the edge above them drags their height.
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

  /// _clip is the clip the roll shows, or null for a part.
  SessionClip? get _clip {
    var t = c.pianoRoll;
    if (t == null || t.row == null) return null;
    return c.session.at(t.channel, t.row!);
  }

  /// _laneChoices are what a lane can show, with their names: velocity,
  /// each controller -- and, for a clip, each setting of its channel, as
  /// an envelope of the clip's.
  List<(RollLane, String)> _laneChoices() {
    var t = c.pianoRoll;
    var channel = t == null
        ? null
        : c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var returns = c.document.returns;
    return [
      for (var l in RollLane.all) (l, l.label),
      if (_clip != null && channel != null)
        for (var a in automationTargets(channel.mix, returns))
          (RollLane.setting(a.id), settingLabel(a, channel.mix, returns)),
    ];
  }

  /// _putHead puts the playhead at [x] along the ruler, to the grid.
  void _putHead(double x, RollContent content) {
    _focus.requestFocus();
    c.rollCursor = _round(x / _beatW).clamp(0.0, content.beats);
  }

  /// _laneEdge is the edge over the lanes: dragged up, they grow, and the
  /// notes over them give way -- down to the notes' least.
  Widget _laneEdge(MixerLook look, double laneH, double tallest) => MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        child: GestureDetector(
          key: const ValueKey("rollLanesEdge"),
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: (d) {
            _edgeFrom = d.globalPosition.dy;
            _tallFrom = laneH;
          },
          // From where the drag began, not move by move: a move between
          // frames is not lost. Shared between the lanes there are.
          onVerticalDragUpdate: (d) => setState(() => _laneTall =
              (_tallFrom - (d.globalPosition.dy - _edgeFrom) / _lanes.length)
                  .clamp(_laneLeast, math.max(_laneLeast, tallest))),
          child: Container(
            height: _splitH,
            decoration: BoxDecoration(
                color: look.studio.panel,
                border: Border(
                    top: BorderSide(color: look.studio.edge),
                    bottom: BorderSide(color: look.studio.edge))),
          ),
        ),
      );

  /// _foldedLanes is the lanes folded away: a bar naming them, opened again
  /// from its arrow.
  Widget _foldedLanes(MixerLook look, {required bool canOpen}) {
    var studio = look.studio;
    return Container(
      key: const ValueKey("rollLanesFolded"),
      height: _headH,
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: studio.edge))),
      child: InkWell(
        key: const ValueKey("rollLanesOpen-0"),
        onTap: canOpen ? () => setState(() => _lanesOpen = true) : null,
        child: Row(children: [
          SizedBox(
              width: 22,
              child: Icon(Icons.chevron_right,
                  size: 14, color: canOpen ? studio.text : studio.muted)),
          Expanded(
            child: Text(
                canOpen
                    ? _lanes.map((l) => l.label).join(" · ")
                    : "Lanes: make the editor taller to open them",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: studio.muted)),
          ),
        ]),
      ),
    );
  }

  /// _lanePanel is lane [i]'s panel, under the keys: the lanes folded away,
  /// what it shows, a second lane added -- or this one taken away.
  Widget _lanePanel(MixerLook look, int i) {
    var studio = look.studio;
    var lane = _lanes[i];
    var others = {
      for (var (j, l) in _lanes.indexed)
        if (j != i) l
    };
    var choices = _laneChoices();
    var clip = _clip;
    Widget icon(String key, IconData icon, String tip, VoidCallback onTap) =>
        Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(icon, size: 14, color: studio.text),
            ),
          ),
        );
    return Container(
      key: ValueKey("rollLaneHeading-$i"),
      width: _keysW,
      padding: const EdgeInsets.fromLTRB(2, 2, 4, 2),
      decoration: BoxDecoration(
          color: studio.panel,
          border: Border(
              right: BorderSide(color: studio.edge),
              top: i > 0 ? BorderSide(color: studio.edge) : BorderSide.none)),
      // Short, with the app's text large, it scrolls rather than spill.
      child: SingleChildScrollView(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            icon("rollLanesOpen-$i", Icons.expand_more, "Fold the lanes away",
                () => setState(() => _lanesOpen = false)),
            const Spacer(),
            if (i == 0 && _lanes.length < 2)
              icon("rollLaneAdd", Icons.add,
                  "Add a second lane: another controller, or velocity", () {
                setState(() => _lanes
                    .add(RollLane.all.firstWhere((l) => !_lanes.contains(l))));
              }),
            if (i > 0)
              icon("rollLaneRemove", Icons.close, "Take this lane away",
                  () => setState(() => _lanes.removeAt(i))),
          ]),
          // What it shows, as the prototype lists them: each a line, the
          // one shown lit.
          Column(
            key: ValueKey(i == 0 ? "rollLane" : "rollLane2"),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var (l, label) in choices)
                if (!others.contains(l))
                  InkWell(
                    key: ValueKey("rollLaneChoice-$i-$label"),
                    borderRadius: BorderRadius.circular(3),
                    onTap: () => setState(() => _lanes[i] = l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: l == lane
                            ? look.colors.primary.withValues(alpha: 0.28)
                            : null,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: l == lane ? studio.text : studio.muted)),
                    ),
                  ),
            ],
          ),
          // A setting's envelope: the clip's length, or its own.
          if (lane.setting case var key? when clip != null)
            DropdownButton<double>(
              key: ValueKey("rollLaneLength-$i"),
              value: clip.lengthOf(key) ?? 0,
              isDense: true,
              isExpanded: true,
              underline: const SizedBox(),
              iconSize: 14,
              style: TextStyle(fontSize: 10.5, color: studio.text),
              dropdownColor: look.colors.surfaceContainerHigh,
              items: [
                for (var (beats, label)
                    in envelopeLengths(c.document.audio.beatsPerBar))
                  DropdownMenuItem(
                      value: beats ?? 0,
                      child: Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                if (v == null) return;
                c.editClip((x) => x.withLength(key, v == 0 ? null : v));
              },
            ),
        ]),
      ),
    );
  }

  Widget _laneArea(RollContent content, MixerLook look, double width,
      RollLane lane, double laneH) {
    var control = lane.control;
    double valueAt(double y) => (1 - (y - 4) / (laneH - 8)).clamp(0.0, 1.0);
    if (control == null && lane.setting == null) {
      // A bar for each note: dragged, how hard it is played -- every note
      // picked with it, if it is picked.
      void set(Offset p, {bool transient = true}) {
        var i = _laneNote;
        if (i == null) return;
        var v = (1 + valueAt(p.dy) * 126).round();
        var together = _selected.contains(i) ? _selected : {i};
        _write([
          for (var (j, n) in content.notes.indexed)
            together.contains(j) ? n.copyWith(velocity: v) : n,
        ], transient: transient);
      }

      int? noteAt(Offset p) {
        int? best;
        var bestD = 8.0;
        for (var (i, n) in content.notes.indexed) {
          var d = (n.start * _beatW + 2 - p.dx).abs();
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        return best;
      }

      return GestureDetector(
        key: const ValueKey("rollVelocity"),
        supportedDevices: dragPointers,
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (d) {
          _laneNote = noteAt(d.localPosition);
          set(d.localPosition);
        },
        onVerticalDragUpdate: (d) => set(d.localPosition),
        onVerticalDragEnd: (_) {
          if (_laneNote != null) c.endInteraction();
          _laneNote = null;
        },
        onTapUp: (d) {
          _laneNote = noteAt(d.localPosition);
          set(d.localPosition, transient: false);
          _laneNote = null;
        },
        child: CustomPaint(
          size: Size(width, laneH),
          painter: _VelocityPainter(
              content.notes, _beatW, {..._selected}, look.studio),
        ),
      );
    }
    if (lane.setting case var key?) {
      return _settingArea(key, look, width, laneH);
    }
    // A controller's curve: a press adds a point, a drag moves it, a
    // double-click takes it away.
    var points = content.controls[control!] ?? const <ControlPoint>[];
    int? pointAt(Offset p) {
      for (var (i, (t, v)) in points.indexed) {
        var at = Offset(t * _beatW, 4 + (1 - v) * (laneH - 8));
        if ((at - p).distance < 8) return i;
      }
      return null;
    }

    void put(int i, Offset p, {bool transient = true}) {
      // The curve as it is now, not as it was when the lane was last
      // built: a drag's first move can come before the frame that shows
      // the point its press put down.
      var now = c.rollContent?.controls ?? content.controls;
      var next = [...?now[control]];
      if (i < 0 || i >= next.length) return;
      ControlPoint moved = (math.max(0, p.dx / _beatW), valueAt(p.dy));
      next[i] = moved;
      next.sort((a, b) => a.$1.compareTo(b.$1));
      // Dragged past a neighbour, it is still the one being dragged.
      _lanePoint = next.indexOf(moved);
      _writeControls({...now, control: next}, transient: transient);
    }

    return GestureDetector(
      key: ValueKey("rollLane-${control.name}"),
      supportedDevices: dragPointers,
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        var p = d.localPosition;
        if (pointAt(p) != null) return;
        var next = [...points, (math.max(0.0, p.dx / _beatW), valueAt(p.dy))]
          ..sort((a, b) => a.$1.compareTo(b.$1));
        _writeControls({...content.controls, control: next});
      },
      // Right-clicked, a point is taken out.
      onSecondaryTapUp: (d) {
        var i = pointAt(d.localPosition);
        if (i == null) return;
        _writeControls({
          ...content.controls,
          control: [...points]..removeAt(i)
        });
      },
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (d) {
        _lanePoint = pointAt(d.localPosition);
        if (_lanePoint == null) {
          // From where it was pressed: a point there, then dragged.
          var p = d.localPosition;
          var next = [...points, (math.max(0.0, p.dx / _beatW), valueAt(p.dy))]
            ..sort((a, b) => a.$1.compareTo(b.$1));
          c.beginInteraction();
          c.setRollContent(
              controls: {...content.controls, control: next}, transient: true);
          _lanePoint = next.indexOf(
              next.firstWhere((q) => q.$1 == math.max(0.0, p.dx / _beatW)));
        }
      },
      onPanUpdate: (d) {
        var i = _lanePoint;
        if (i != null) put(i, d.localPosition);
      },
      onPanEnd: (_) {
        c.endInteraction();
        _lanePoint = null;
      },
      child: CustomPaint(
        size: Size(width, laneH),
        painter: _CurvePainter(points, control.rest, _beatW, look.studio),
      ),
    );
  }

  /// _settingArea is a clip's envelope of one of its channel's settings,
  /// under its notes: drawn and changed as a controller's curve is, its
  /// points a beat and a height up the setting's range -- one of its own
  /// length drawn again and again along the clip.
  Widget _settingArea(String key, MixerLook look, double width, double laneH) {
    var clip = _clip;
    var t = c.pianoRoll;
    if (clip == null || t == null) return SizedBox(width: width, height: laneH);
    var what = AutomationTarget.parse(key);
    var channel =
        c.timelineChannels.where((l) => l.key == t.channel).firstOrNull;
    var rest = what == null || channel == null
        ? 0.5
        : what.height(what.own(channel.mix));
    var length = clip.lengthOf(key);
    var points = clip.curveOf(key);
    double valueAt(double y) => (1 - (y - 4) / (laneH - 8)).clamp(0.0, 1.0);
    // To the grid, and inside its own length: its points are the first time
    // round, which the rest repeat.
    double beatAt(double x) {
      var b = math.max(0.0, _round(x / _beatW));
      return length == null ? b : b.clamp(0.0, math.max(0.0, length - _grid));
    }

    int? pointAt(Offset p) {
      for (var (i, (b, v)) in points.indexed) {
        var at = Offset(b * _beatW, 4 + (1 - v) * (laneH - 8));
        if ((at - p).distance < 8) return i;
      }
      return null;
    }

    void put(int i, Offset p) {
      var now = [...?_clip?.curveOf(key)];
      if (i < 0 || i >= now.length) return;
      ControlPoint moved = (beatAt(p.dx), valueAt(p.dy));
      now[i] = moved;
      now.sort((a, b) => a.$1.compareTo(b.$1));
      _lanePoint = now.indexOf(moved);
      c.editClip((x) => x.withCurve(key, now), transient: true);
    }

    return GestureDetector(
      key: ValueKey("rollSetting-$key"),
      supportedDevices: dragPointers,
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (pointAt(d.localPosition) != null) return;
        var p = d.localPosition;
        c.editClip((x) => x.withCurve(
            key, [...x.curveOf(key), (beatAt(p.dx), valueAt(p.dy))]));
      },
      // Right-clicked, a point is taken out.
      onSecondaryTapUp: (d) {
        var i = pointAt(d.localPosition);
        if (i == null) return;
        c.editClip((x) => x.withCurve(key, [...x.curveOf(key)]..removeAt(i)));
      },
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (d) {
        c.beginInteraction();
        _lanePoint = pointAt(d.localPosition);
        if (_lanePoint == null) {
          // From where it was pressed: a point there, then dragged.
          var p = d.localPosition;
          ControlPoint added = (beatAt(p.dx), valueAt(p.dy));
          var next = [...points, added]..sort((a, b) => a.$1.compareTo(b.$1));
          c.editClip((x) => x.withCurve(key, next), transient: true);
          _lanePoint = next.indexOf(added);
        }
      },
      onPanUpdate: (d) {
        var i = _lanePoint;
        if (i != null) put(i, d.localPosition);
      },
      onPanEnd: (_) {
        c.endInteraction();
        _lanePoint = null;
      },
      child: CustomPaint(
        size: Size(width, laneH),
        painter:
            _CurvePainter(points, rest, _beatW, look.studio, length: length),
      ),
    );
  }

  Widget _toolbar(MixerLook look, RollContent content, double zoom) {
    var studio = look.studio;
    var small = TextStyle(fontSize: 11, color: studio.text);
    // The prototype's toolbar buttons: flat, the one on filled.
    Widget pill(String label, bool on, VoidCallback onTap,
            {Key? key, String? tip}) =>
        Material(
          color: on ? look.colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: onTap,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: on ? look.colors.onPrimary : studio.muted)),
            ),
          ),
        );
    Widget gap() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: studio.edge);
    // The prototype's drop-downs: as wide as what is picked, and a list
    // under it.
    Widget drop<T>(Key key, T value, List<(String, T)> items,
            ValueChanged<T> onChanged) =>
        MenuAnchor(
          style: MenuStyle(
              backgroundColor:
                  WidgetStatePropertyAll(look.colors.surfaceContainerHigh)),
          builder: (context, menu, _) => InkWell(
            key: key,
            borderRadius: BorderRadius.circular(5),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Container(
              height: 22,
              padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
              decoration: BoxDecoration(
                color: studio.inset,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: studio.edge),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                      items.where((i) => i.$2 == value).firstOrNull?.$1 ?? "",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: small),
                ),
                Icon(Icons.expand_more, size: 13, color: studio.muted),
              ]),
            ),
          ),
          menuChildren: [
            for (var (label, v) in items)
              MenuItemButton(
                onPressed: () => onChanged(v),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            v == value ? FontWeight.w600 : FontWeight.w400)),
              ),
          ],
        );
    // The prototype's Transform and Generate: the notes' tools, on those
    // picked or every one, grouped.
    Widget toolMenu(
            String key, String label, List<(String, List<NoteTool>)> groups) =>
        MenuAnchor(
          style: chainMenuStyle(look),
          builder: (context, menu, _) => InkWell(
            key: ValueKey(key),
            borderRadius: BorderRadius.circular(5),
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            child: Container(
              height: 22,
              padding: const EdgeInsets.fromLTRB(6, 0, 2, 0),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: studio.muted)),
                Icon(Icons.expand_more, size: 13, color: studio.muted),
              ]),
            ),
          ),
          menuChildren: [
            chainMenuHeading(
                look,
                _selected.isEmpty
                    ? "Every note"
                    : "${_selected.length} picked"),
            for (var (i, (title, tools)) in groups.indexed) ...[
              if (i > 0) chainMenuDivider(look),
              chainMenuHeading(look, title),
              for (var t in tools)
                chainMenuItem(look,
                    key: ValueKey("rollTool-${t.name}"),
                    text: t.label,
                    onPressed: () => c.useNoteTool(t, grid: _grid)),
            ],
          ],
        );
    var bars = content.beats / c.document.audio.beatsPerBar;
    List<Widget> left() => [
          // Named by the editor round it, in the strip.
          if (!widget.inClipEditor) ...[
            Text(content.name,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: studio.text)),
            const SizedBox(width: 12),
          ],
          // A part's Play, first where it is always in sight: the timeline
          // from the playhead.
          if (widget.inClipEditor && c.pianoRoll?.row == null) ...[
            pill(c.playing ? "■ Stop" : "▶ Play", c.playing, c.togglePlay,
                key: const ValueKey("partPlay")),
            const SizedBox(width: 8),
          ],
          // The tools, as the prototype groups them: an icon each and the
          // key that picks it.
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: studio.inset,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: studio.edge),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var (tool, icon, letter, key) in [
                (_Tool.select, "select", "V", "rollSelect"),
                (_Tool.draw, "draw", "D", "rollDraw"),
                (_Tool.paint, "paint", "B", "rollPaint"),
                (_Tool.erase, "erase", "E", "rollErase"),
                (_Tool.knife, "knife", "C", "rollKnife"),
                (_Tool.mute, "mute", "M", "rollMute"),
              ])
                Material(
                  color:
                      _tool == tool ? look.colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  child: InkWell(
                    key: ValueKey(key),
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => setState(() => _tool = tool),
                    child: Container(
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ChainIcon(icon,
                            size: 14,
                            color: _tool == tool
                                ? look.colors.onPrimary
                                : studio.muted),
                        const SizedBox(width: 3),
                        Text(letter,
                            style: TextStyle(
                                fontSize: 9,
                                color: (_tool == tool
                                        ? look.colors.onPrimary
                                        : studio.muted)
                                    .withValues(alpha: 0.8))),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
          gap(),
          Text("Grid", style: TextStyle(fontSize: 11, color: studio.muted)),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollGridSize"),
              _grid,
              [for (var (l, b) in rollGrids) (l, b)],
              (v) => setState(() {
                    _grid = v;
                    c.rollStepGrid = v;
                  })),
          const SizedBox(width: 4),
          pill("Quantise", false, _quantise,
              key: const ValueKey("rollQuantise"),
              tip: "Onto the grid: the notes picked, or every one"),
          gap(),
          // The scale: lit, folded to, kept to.
          ChainIcon("scale", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          pill("Show", _scale, () => setState(() => _scale = !_scale),
              key: const ValueKey("rollScale")),
          const SizedBox(width: 2),
          pill("Fold", _fold, () => setState(() => _fold = !_fold),
              key: const ValueKey("rollFold")),
          const SizedBox(width: 2),
          pill("Keep in key", _keep, () => setState(() => _keep = !_keep),
              key: const ValueKey("rollKeep")),
          gap(),
          // What Draw draws, and another channel's notes behind.
          ChainIcon("chord", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollChord"),
              _chord,
              [for (var (i, (name, _)) in rollChords.indexed) (name, i)],
              (v) => setState(() => _chord = v)),
          const SizedBox(width: 8),
          ChainIcon("ghost", size: 14, color: studio.muted),
          const SizedBox(width: 4),
          drop(
              const ValueKey("rollGhost"),
              _ghost ?? "",
              [
                ("No ghosts", ""),
                for (var ch in c.timelineChannels)
                  if (ch.key != c.pianoRoll?.channel &&
                      c.instrumentChannel(ch.key))
                    (ch.name, ch.key),
              ],
              (v) => setState(() => _ghost = v.isEmpty ? null : v)),
          const SizedBox(width: 4),
          // Step input: each key played a note at the cursor, and on.
          pill("Step", c.rollStep, () {
            c.setRollStep(!c.rollStep, grid: _grid);
            _focus.requestFocus();
          }, key: const ValueKey("rollStep")),
          gap(),
          toolMenu("rollTransform", "Transform", [
            (
              "Move",
              [
                NoteTool.quantise,
                NoteTool.swing,
                NoteTool.humanise,
                NoteTool.legato,
                NoteTool.strum,
              ]
            ),
            (
              "Shape",
              [
                NoteTool.reverse,
                NoteTool.invert,
                NoteTool.faster,
                NoteTool.slower,
                NoteTool.crescendo,
                NoteTool.chop,
                NoteTool.join,
                NoteTool.duplicate,
              ]
            ),
            (
              "Pitch",
              [
                NoteTool.up,
                NoteTool.down,
                NoteTool.octaveUp,
                NoteTool.octaveDown,
                NoteTool.fitToScale,
              ]
            ),
          ]),
          const SizedBox(width: 2),
          toolMenu("rollGenerate", "Generate", [
            (
              "Add",
              [
                NoteTool.arpeggiate,
                NoteTool.rhythm,
                NoteTool.fillChords,
                NoteTool.third,
                NoteTool.fifth,
              ]
            ),
            ("Play", [NoteTool.chance, NoteTool.always, NoteTool.mute]),
          ]),
          if (content.clip && !widget.inClipEditor) ...[
            gap(),
            Text("Length", style: TextStyle(fontSize: 11, color: studio.muted)),
            const SizedBox(width: 4),
            drop(
                const ValueKey("rollLength"),
                bars,
                [
                  for (var b in {
                    ...clipBarChoices.map((b) => b.toDouble()),
                    bars
                  })
                    (b == 1 ? "1 bar" : "${_trim(b)} bars", b),
                ],
                (v) =>
                    c.setRollContent(beats: v * c.document.audio.beatsPerBar)),
          ],
          if (!widget.inClipEditor) ...[
            const SizedBox(width: 12),
            pill("Effects", false, () => c.pianoRollShown = false,
                key: const ValueKey("rollToEffects"),
                tip: "Back to the channel's effects"),
          ],
        ];
    // The right end, as the prototype keeps it: the edits and the zoom.
    Widget iconButton(String key, String icon, VoidCallback onTap) => InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
              width: 24,
              height: 22,
              child: Center(
                  child: ChainIcon(icon, size: 14, color: studio.muted))),
        );
    Widget materialButton(String key, IconData icon, VoidCallback onTap) =>
        InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(5),
          onTap: onTap,
          child: SizedBox(
              width: 24,
              height: 22,
              child: Icon(icon, size: 14, color: studio.muted)),
        );
    var right = <Widget>[
      materialButton("rollUndo", Icons.undo, c.undo),
      materialButton("rollRedo", Icons.redo, c.redo),
      gap(),
      materialButton("rollCopy", Icons.content_copy, _copy),
      materialButton("rollPaste", Icons.content_paste, _paste),
      materialButton("rollDelete", Icons.delete_outline, _delete),
      gap(),
      iconButton("rollZoomOut", "zoomout",
          () => setState(() => _zoom = (zoom + 0.1).clamp(0.0, 1.0))),
      SizedBox(
        width: 72,
        // Closest at the left; at the right, the whole of it.
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
          child: Slider(
            key: const ValueKey("rollZoom"),
            value: zoom.clamp(0.0, 1.0),
            onChanged: (v) => setState(() => _zoom = v),
          ),
        ),
      ),
      iconButton("rollZoomIn", "zoomin",
          () => setState(() => _zoom = (zoom - 0.1).clamp(0.0, 1.0))),
    ];
    return Container(
      height: _toolbarH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: studio.edge))),
      child: LayoutBuilder(builder: (context, box) {
        // Room enough, the right end keeps to the right; short of it, it
        // follows the rest.
        var pinned = box.maxWidth >= 640;
        var scroll = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ...left(),
            if (!pinned) ...[gap(), ...right],
          ]),
        );
        if (!pinned) return scroll;
        return Row(children: [
          Expanded(child: scroll),
          gap(),
          ...right,
        ]);
      }),
    );
  }

  /// _status is the roll's foot, as the prototype has it: how many notes,
  /// the tool and the grid, and what the tool does.
  Widget _status(MixerLook look, RollContent content) {
    var studio = look.studio;
    var picked = _selected.length;
    var grid = rollGrids.where((g) => g.$2 == _grid).firstOrNull?.$1 ??
        "${_trim(_grid)} beat";
    var hint = c.rollStep
        ? "Step: A to K play notes at the cursor, held together a chord "
            "· Tab rests · Z X octave"
        : switch (_tool) {
            _Tool.select =>
              "Drag to move · its end to lengthen · Shift-click adds "
                  "· ↑↓ transpose, ⇧ an octave",
            _Tool.draw => "Click draws a note · drag to lengthen it",
            _Tool.paint => "Drag along to lay notes on the grid",
            _Tool.erase => "Click or drag over notes to take them out",
            _Tool.knife => "Click a note to cut it in two there",
            _Tool.mute => "Click a note to mute it, or play it again",
          };
    var mono = TextStyle(
        fontSize: 10.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: studio.muted);
    var strong = mono.copyWith(color: studio.text, fontWeight: FontWeight.w600);
    return Container(
      key: const ValueKey("rollStatus"),
      height: _statusH,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: studio.edge))),
      child: Text.rich(
        TextSpan(style: mono, children: [
          TextSpan(text: "${content.notes.length}", style: strong),
          TextSpan(text: content.notes.length == 1 ? " note" : " notes"),
          if (picked > 0) ...[
            const TextSpan(text: "   "),
            TextSpan(text: "$picked", style: strong),
            const TextSpan(text: " picked"),
          ],
          const TextSpan(text: "   Tool: "),
          TextSpan(text: _tool.name, style: strong),
          const TextSpan(text: "   Grid "),
          TextSpan(text: grid, style: strong),
          TextSpan(text: "   $hint"),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

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

  /// _note is a note's colour: the prototype's MIDI orange.
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
    // Columns: the grid, the beats, the bars.
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
    // Past a clip's end, shaded.
    canvas.drawRect(Rect.fromLTRB(beats * beatW, 0, size.width, size.height),
        Paint()..color = const Color(0x66000000));
    // Another channel's notes, faint, behind these.
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
      // The prototype's notes: the MIDI orange, as solid as the note is
      // likely to play, a line along its foot as long as it is hard.
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
      // Its name, where it is long enough to hold it.
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

/// _HeadPainter is the playhead over the grid -- a line, brighter while it
/// plays -- or over the ruler, a marker: painted again each time it moves
/// on (CanvasController.playheadMoved), with nothing under it built again.
/// pianoRollBuilds counts the roll built, for a test that playing does not
/// build it again at every frame.
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
    // Where it rests, for reference.
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
