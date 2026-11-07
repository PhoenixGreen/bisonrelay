import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart' show snapNote;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/ui/autotune_card.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// pitch_editor.dart is the Pitch editor, the Auto-tune's notes opened, as
// the prototype's: a channel's recording as notes -- each a blob at the
// note it is heard at, over piano keys and the key's scale -- the pitch as
// sung (red) and as corrected (purple), where each note was heard boxed
// with an arrow to where it goes. Notes are dragged up and down onto the
// scale, split, glued, drawn over by hand or with a line; each has its own
// retune, vibrato, drift, formant, slide and gain in the inspector, and
// the Auto-tune's own Amount and Humanise sit under them. The timing is
// the recording's, kept.

/// PitchTool is what a press on the notes does.
enum PitchTool {
  move("Move", "V", Icons.near_me_outlined),
  split("Split", "C", Icons.content_cut),
  glue("Glue", "G", Icons.link),
  draw("Draw", "P", Icons.gesture),
  line("Line", "L", Icons.show_chart);

  final String label, shortcut;
  final IconData icon;
  const PitchTool(this.label, this.shortcut, this.icon);
}

/// PitchSnap is where a dragged note lands: the key's scale, any
/// semitone, or anywhere.
enum PitchSnap {
  scale("Scale"),
  chromatic("Chromatic"),
  off("Off");

  final String label;
  const PitchSnap(this.label);
}

const _blobInk = Color(0xFFD9669A);
const _amber = Color(0xFFE5A23C);

class PitchEditor extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  const PitchEditor(
      {required this.controller, required this.channel, super.key});

  @override
  State<PitchEditor> createState() => _PitchEditorState();
}

class _PitchEditorState extends State<PitchEditor> {
  CanvasController get c => widget.controller;
  String get key => widget.channel;

  PitchTool _tool = PitchTool.move;
  PitchSnap _snap = PitchSnap.scale;
  Set<int> _picked = {};
  bool _inspector = true;

  /// _rowH and _perSecond are the grid's measures once zoomed; null, they
  /// fit the notes into the room there is.
  double? _rowH, _perSecond;

  /// The key and scale where the channel has no Auto-tune to hold them.
  int _root = 0, _scale = 1;

  final FocusNode _focus = FocusNode(debugLabel: "pitchEditor");
  final ScrollController _across = ScrollController();
  final ScrollController _down = ScrollController();
  final ScrollController _keysDown = ScrollController();

  // A drag: the notes moved and where they were, or a box being drawn, or
  // a pitch being drawn by hand or as a line.
  Offset? _dragFrom;
  Map<int, double> _targetsFrom = {};
  Rect? _box;
  List<(double, double)> _drawing = [];
  (double, double)? _lineFrom, _lineTo;

  // The last tap, for a double-click on a note.
  int? _lastTapNote;
  DateTime _lastTapAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    _down.addListener(() {
      if (_keysDown.hasClients && _down.hasClients) {
        _keysDown.jumpTo(_down.offset);
      }
    });
  }

  @override
  void dispose() {
    // Left, it is heard corrected again: As sung is only for listening.
    if (c.pitchHeardAsSung(key)) c.hearPitchAsSung(key, false);
    _focus.dispose();
    _across.dispose();
    _down.dispose();
    _keysDown.dispose();
    super.dispose();
  }

  // ---- The key and scale: the Auto-tune's, where it has one.

  int? get _tuneIndex {
    var devices = c.devicesOf(key);
    for (var (i, d) in devices.indexed) {
      if (d.kind == DeviceKind.autoTune) return i;
    }
    return null;
  }

  MixDevice? get _tune =>
      _tuneIndex == null ? null : c.devicesOf(key)[_tuneIndex!];

  int get _rootNow => _tune?.value("key").round() ?? _root;
  int get _scaleNow => _tune?.value("scale").round() ?? _scale;

  List<int> get _steps => _scaleNow == 0
      ? const []
      : scaleSteps[(_scaleNow - 1).clamp(0, scaleSteps.length - 1)];

  bool _inScale(int n) =>
      _steps.isEmpty || _steps.contains((n - _rootNow) % 12);

  void _setTune(String param, int value) {
    var i = _tuneIndex;
    if (i == null) {
      setState(() => param == "key" ? _root = value : _scale = value);
      return;
    }
    var devices = c.devicesOf(key);
    c.beginInteraction();
    c.setDevicesOf(
        key, [...devices]..[i] = devices[i].withValue(param, value.toDouble()));
    c.endInteraction();
  }

  void _setTuneValue(String param, double value, {bool transient = false}) {
    var i = _tuneIndex;
    if (i == null) return;
    var devices = c.devicesOf(key);
    c.beginInteraction();
    c.setDevicesOf(key, [...devices]..[i] = devices[i].withValue(param, value),
        transient: true);
    if (!transient) c.endInteraction();
  }

  /// _snapped is [m] where the snap puts it.
  double _snapped(double m) => switch (_snap) {
        PitchSnap.scale => snapNote(m, _rootNow, _steps),
        PitchSnap.chromatic => m.roundToDouble(),
        PitchSnap.off => m,
      };

  /// _stepped is [m] a note up ([up]) or down: the next of the scale, or a
  /// semitone.
  double _stepped(double m, bool up) {
    if (_snap != PitchSnap.scale) return m + (up ? 1 : -1);
    var n = m.round();
    for (var d = 1; d <= 12; d++) {
      var k = up ? n + d : n - d;
      if (_inScale(k)) return k.toDouble();
    }
    return m + (up ? 1 : -1);
  }

  /// _shown is where note [n] is heard: where it was moved to, or -- left
  /// as sung -- where the channel's Auto-tune pulls it.
  double _shown(PitchNote n) {
    if (n.edited) return n.target;
    var tune = _tune;
    if (tune == null || !tune.on) return n.sung;
    return n.sung +
        (snapNote(n.sung, _rootNow, _steps) - n.sung) * tune.value("amount");
  }

  void _edit(PitchEdit Function(PitchEdit e) change,
          {bool transient = false}) =>
      c.editPitch(key, change, transient: transient);

  void _eachPicked(PitchNote Function(PitchNote n) change,
      {bool transient = false}) {
    _edit(
        (e) => e.copyWith(notes: [
              for (var (i, n) in e.notes.indexed)
                _picked.contains(i) ? change(n) : n
            ]),
        transient: transient);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: pitchTracksRead,
        builder: (context, _, __) => ListenableBuilder(
          listenable: c,
          builder: (context, _) => _body(context),
        ),
      );

  Widget _body(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var hint = TextStyle(fontSize: 12, color: s.muted);
    var source = c.pitchSourceOf(key);
    if (source == null) {
      return Center(
          child: Text("No recording on this channel to tune", style: hint));
    }
    var track = c.pitchTrackOf(key);
    var edit = c.pitchEditOf(key);
    if (edit == null || track == null) {
      return Center(
        child: track == null
            ? Text(
                c.pitchUnreadable(key)
                    ? "Its recording could not be read"
                    : "Reading its pitch…",
                style: hint)
            : FilledButton(
                key: const ValueKey("pitchFind"),
                onPressed: () => c.findPitchNotes(key),
                child: const Text("Find its notes")),
      );
    }
    _picked = {
      for (var i in _picked)
        if (i < edit.notes.length) i
    };
    return Focus(
      focusNode: _focus,
      onKeyEvent: (_, e) => _key(e, edit),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _toolbar(context, look, edit),
        Container(height: 1, color: s.edge),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _canvas(look, edit, track, source.length)),
            if (_inspector) ...[
              Container(width: 1, color: s.edge),
              SizedBox(width: 238, child: _inspectorPanel(look, edit, track)),
            ],
          ]),
        ),
        Container(height: 1, color: s.edge),
        _statusLine(s, edit),
      ]),
    );
  }

  // ---- The toolbar.

  Widget _toolbar(BuildContext context, MixerLook look, PitchEdit edit) {
    var s = look.studio;
    var text = TextStyle(fontSize: 11.5, color: s.text);
    var muted = TextStyle(fontSize: 11, color: s.muted);
    Widget toggle(String label, bool on, VoidCallback tap, String k,
            {IconData? icon, String? tip, String? keyHint}) =>
        Tooltip(
          message: tip ?? "",
          child: InkWell(
            key: ValueKey(k),
            borderRadius: BorderRadius.circular(5),
            onTap: tap,
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: on ? look.colors.primary : null,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 13, color: on ? look.colors.onPrimary : s.text),
                  const SizedBox(width: 4),
                ],
                Text(label,
                    style: text.copyWith(
                        color: on ? look.colors.onPrimary : s.text)),
                if (keyHint != null) ...[
                  const SizedBox(width: 4),
                  Text(keyHint,
                      style: muted.copyWith(
                          fontSize: 9.5,
                          color: on
                              ? look.colors.onPrimary.withValues(alpha: 0.7)
                              : s.muted)),
                ],
              ]),
            ),
          ),
        );
    Widget group(List<Widget> children) => Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: s.edge),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: children),
        );
    Widget gap() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: s.edge);
    Widget act(String label, String k, VoidCallback? tap, {String? tip}) =>
        Tooltip(
          message: tip ?? "",
          child: TextButton(
            key: ValueKey(k),
            style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: s.text,
                textStyle: const TextStyle(fontSize: 11.5)),
            onPressed: tap,
            child: Text(label),
          ),
        );
    Widget icon(IconData i, String k, String tip, VoidCallback? tap) =>
        IconButton(
          key: ValueKey(k),
          tooltip: tip,
          iconSize: 16,
          visualDensity: VisualDensity.compact,
          color: s.text,
          icon: Icon(i),
          onPressed: tap,
        );
    var keyNames = DeviceKind.autoTune.param("key").choices;
    var scaleNames = DeviceKind.autoTune.param("scale").choices;
    var asSung = c.pitchHeardAsSung(key);
    return SizedBox(
      height: 34,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(children: [
          group([
            for (var t in PitchTool.values)
              toggle(t.label, _tool == t, () => setState(() => _tool = t),
                  "pitchTool-${t.name}",
                  icon: t.icon, keyHint: t.shortcut),
          ]),
          gap(),
          Text("Snap to", style: muted),
          const SizedBox(width: 6),
          group([
            for (var m in PitchSnap.values)
              toggle(m.label, _snap == m, () => setState(() => _snap = m),
                  "pitchSnap-${m.name}"),
          ]),
          gap(),
          // The key and scale: the Auto-tune's own.
          MenuAnchor(
            menuChildren: [
              SubmenuButton(
                menuChildren: [
                  for (var (i, n) in keyNames.indexed)
                    MenuItemButton(
                      key: ValueKey("pitchKeyItem-$i"),
                      leadingIcon:
                          Icon(i == _rootNow ? Icons.check : null, size: 14),
                      onPressed: () => _setTune("key", i),
                      child: Text(n),
                    ),
                ],
                child: const Text("Key"),
              ),
              SubmenuButton(
                menuChildren: [
                  for (var (i, n) in scaleNames.indexed)
                    MenuItemButton(
                      key: ValueKey("pitchScaleItem-$i"),
                      leadingIcon:
                          Icon(i == _scaleNow ? Icons.check : null, size: 14),
                      onPressed: () => _setTune("scale", i),
                      child: Text(n),
                    ),
                ],
                child: const Text("Scale"),
              ),
            ],
            builder: (context, menu, _) => toggle(
                "${keyNames[_rootNow]} ${scaleNames[_scaleNow].toLowerCase()}",
                false,
                () => menu.isOpen ? menu.close() : menu.open(),
                "pitchKeyScale",
                icon: Icons.music_note_outlined,
                tip: _tune == null
                    ? "The notes' key and scale"
                    : "The Auto-tune's key and scale"),
          ),
          gap(),
          Text("Hear", style: muted),
          const SizedBox(width: 6),
          group([
            toggle("Corrected", !asSung, () => c.hearPitchAsSung(key, false),
                "pitchHearCorrected"),
            toggle("As sung", asSung, () => c.hearPitchAsSung(key, true),
                "pitchHearSung"),
          ]),
          gap(),
          act("Correct every note", "pitchCorrectAll", () {
            _edit((e) => e.copyWith(notes: [
                  for (var n in e.notes)
                    n.movedTo(_snap == PitchSnap.off
                        ? n.sung.roundToDouble()
                        : _snapped(n.sung))
                ]));
          }, tip: "Every note onto the nearest of the scale"),
          act("Notes to MIDI", "pitchToMidi", () {
            var why = c.notesToMidi(key, root: _rootNow, steps: _steps);
            try {
              var snack = SnackBarModel.of(context);
              why == null
                  ? snack.success("Its notes are on a new MIDI channel")
                  : snack.error(why);
            } catch (_) {}
          }, tip: "A MIDI channel playing these notes"),
          act("As recorded", "pitchReset", () {
            setState(() => _picked = {});
            c.forgetPitch(key);
          }, tip: "Every note as it was sung"),
          icon(Icons.undo, "pitchUndo", "Undo", c.canUndo ? c.undo : null),
          gap(),
          icon(Icons.remove, "pitchRowsSmaller", "Smaller rows",
              () => setState(() => _rowH = math.max(6, (_rowH ?? 16) - 3))),
          icon(Icons.add, "pitchRowsTaller", "Taller rows",
              () => setState(() => _rowH = math.min(48, (_rowH ?? 16) + 3))),
          icon(Icons.zoom_out, "pitchTimeOut", "Less time across",
              () => setState(() => _perSecond = (_perSecond ?? 120) / 1.4)),
          icon(Icons.zoom_in, "pitchTimeIn", "More time across",
              () => setState(() => _perSecond = (_perSecond ?? 120) * 1.4)),
          icon(
              Icons.fit_screen_outlined,
              "pitchFit",
              "Fit the notes",
              () => setState(() {
                    _rowH = null;
                    _perSecond = null;
                  })),
          icon(
              _inspector ? Icons.chevron_right : Icons.view_sidebar_outlined,
              "pitchInspectorToggle",
              _inspector ? "Hide the inspector" : "Show the inspector",
              () => setState(() => _inspector = !_inspector)),
        ]),
      ),
    );
  }

  // ---- The canvas: ruler, keys, notes, voice.

  static const double _rulerH = 20, _keysW = 46, _voiceH = 30;

  Widget _canvas(
      MixerLook look, PitchEdit edit, List<double?> track, double fileLength) {
    var s = look.studio;
    var notes = edit.notes;
    // Rows from three under the lowest note to three over the highest.
    var low = notes.isEmpty
        ? 48.0
        : notes.map((n) => math.min(n.sung, n.target)).reduce(math.min) - 3;
    var high = notes.isEmpty
        ? 72.0
        : notes.map((n) => math.max(n.sung, n.target)).reduce(math.max) + 3;
    var top = high.ceilToDouble(), bottom = low.floorToDouble();
    var length = math.max(0.5, track.length * 0.02);
    var source = c.pitchSourceOf(key)!;
    var e = c.pitchElementOf(key)!;
    // Where the recording's seconds fall on the timeline's beats.
    var spb = c.document.audio.secondsPerBeat;
    var perBar = c.document.audio.beatsPerBar;
    var startsAt = e.clip.at / c.document.frameRate - source.start;
    var heard = _heardTrack(edit, track);
    var playhead = c.pitchPlayhead(key);
    return LayoutBuilder(builder: (context, box) {
      var gridH = math.max(40.0, box.maxHeight - _rulerH - _voiceH);
      var gridW = math.max(40.0, box.maxWidth - _keysW);
      var rowH = _rowH ?? math.max(8.0, gridH / (top - bottom));
      var perSecond = _perSecond ?? math.max(30.0, gridW / length);
      var width = length * perSecond;
      var height = (top - bottom) * rowH;
      double yOf(double m) => (top - m) * rowH + rowH / 2;
      double mOf(double y) => top - (y - rowH / 2) / rowH;
      double tOf(double x) => x / perSecond;
      var grid = _PitchGrid(
        notes: notes,
        shown: [for (var n in notes) _shown(n)],
        track: track,
        heard: heard,
        top: top,
        bottom: bottom,
        perSecond: perSecond,
        rowH: rowH,
        picked: _picked,
        inScale: _inScale,
        root: _rootNow,
        beatAt: (k) => k * spb - startsAt,
        perBar: perBar,
        playhead: playhead,
        box: _box,
        drawing: _drawing,
        line: _lineFrom == null || _lineTo == null
            ? null
            : (_lineFrom!, _lineTo!),
        s: s,
      );
      Widget gestures = Listener(
        onPointerDown: (d) {
          _focus.requestFocus();
          if (d.buttons == kSecondaryMouseButton) {
            var i = _noteAt(d.localPosition, notes, yOf, perSecond, rowH);
            if (i != null && notes[i].curve.isNotEmpty) {
              _edit((e) => e.copyWith(
                  notes: [...e.notes]..[i] =
                      e.notes[i].copyWith(curve: const [])));
            }
          }
        },
        onPointerSignal: (signal) {
          if (signal is! PointerScrollEvent) return;
          var keys = HardwareKeyboard.instance;
          if (!keys.isMetaPressed && !keys.isControlPressed) return;
          GestureBinding.instance.pointerSignalResolver.register(signal, (_) {
            setState(() => _rowH =
                (rowH * (signal.scrollDelta.dy < 0 ? 1.12 : 1 / 1.12))
                    .clamp(6.0, 48.0));
          });
        },
        child: GestureDetector(
          key: const ValueKey("pitchGrid"),
          supportedDevices: dragPointers,
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (d) => _tap(
              d.localPosition, edit, yOf, tOf, perSecond, rowH, spb, startsAt),
          onPanStart: (d) =>
              _panStart(d.localPosition, edit, yOf, mOf, tOf, perSecond, rowH),
          onPanUpdate: (d) => _panUpdate(d.localPosition, rowH, mOf, tOf),
          onPanEnd: (_) => _panEnd(edit, yOf, perSecond, rowH),
          child: CustomPaint(size: Size(width, height), painter: grid),
        ),
      );
      return Stack(children: [
        Positioned.fill(child: ColoredBox(color: s.display)),
        // The keys, scrolled up and down with the notes.
        Positioned(
          left: 0,
          top: _rulerH,
          width: _keysW,
          height: gridH,
          child: SingleChildScrollView(
            controller: _keysDown,
            physics: const NeverScrollableScrollPhysics(),
            child: CustomPaint(
              key: const ValueKey("pitchKeys"),
              size: Size(_keysW, height),
              painter: _KeysPainter(top, bottom, rowH, _inScale, _rootNow, s),
            ),
          ),
        ),
        Positioned(
          left: _keysW,
          top: 0,
          right: 0,
          bottom: 0,
          child: Scrollbar(
            controller: _across,
            child: SingleChildScrollView(
              controller: _across,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(width, gridW),
                child: Column(children: [
                  // The ruler: bars and beats; pressed, the playhead put
                  // there.
                  GestureDetector(
                    key: const ValueKey("pitchRuler"),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      var t = tOf(d.localPosition.dx);
                      c.frame = ((startsAt + t) * c.document.frameRate)
                          .round()
                          .clamp(0, math.max(0, c.document.frames - 1));
                    },
                    child: CustomPaint(
                      size: Size(math.max(width, gridW), _rulerH),
                      painter: _RulerPainter(
                          perSecond: perSecond,
                          beatAt: (k) => k * spb - startsAt,
                          perBar: perBar,
                          length: length,
                          playhead: playhead,
                          s: s),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _down,
                      child:
                          Align(alignment: Alignment.topLeft, child: gestures),
                    ),
                  ),
                  // The voice: the recording's shape under its notes.
                  CustomPaint(
                    key: const ValueKey("pitchVoice"),
                    size: Size(math.max(width, gridW), _voiceH),
                    painter: _VoicePainter(
                        peaks: c.waveformOf(source.assetId),
                        perSecond: perSecond,
                        fileLength: fileLength <= 0 ? length : fileLength,
                        s: s),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          left: 4,
          bottom: 8,
          child: Text("voice", style: TextStyle(fontSize: 10, color: s.muted)),
        ),
        // What is heard: which line is which, or the note heard now.
        Positioned(
          right: 10,
          top: _rulerH + 2,
          child: IgnorePointer(
            child: Text(_readout(heard, playhead),
                key: const ValueKey("pitchReadout"),
                style: TextStyle(
                    fontSize: 10.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: s.muted)),
          ),
        ),
      ]);
    });
  }

  /// _heardTrack is the pitch heard, moment by moment: the notes as made,
  /// then pulled by the channel's Auto-tune where it is on.
  List<double?> _heardTrack(PitchEdit edit, List<double?> track) {
    var moved = editedTrack(edit, track);
    var tune = _tune;
    return tune == null || !tune.on ? moved : correctedTrack(tune, moved);
  }

  String _readout(List<double?> heard, double? playhead) {
    if (!c.playing || playhead == null) {
      return "red: as sung · purple: corrected";
    }
    var i = (playhead / 0.02).round();
    var m = i >= 0 && i < heard.length ? heard[i] : null;
    if (m == null) return "now: –";
    var n = m.round();
    var cents = ((m - n) * 100).round();
    return "now ${noteName(n)} ${cents >= 0 ? "+" : "−"}${cents.abs()} ct";
  }

  // ---- Presses.

  int? _noteAt(Offset p, List<PitchNote> notes, double Function(double) yOf,
      double perSecond, double rowH) {
    var t = p.dx / perSecond;
    int? best;
    var bestD = double.infinity;
    for (var (i, n) in notes.indexed) {
      if (t < n.start - 0.02 || t > n.end + 0.02) continue;
      var d = (p.dy - yOf(_shown(n))).abs();
      if (d <= math.max(rowH, 10) && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  void _tap(
      Offset p,
      PitchEdit edit,
      double Function(double) yOf,
      double Function(double) tOf,
      double perSecond,
      double rowH,
      double spb,
      double startsAt) {
    var i = _noteAt(p, edit.notes, yOf, perSecond, rowH);
    var shift = HardwareKeyboard.instance.isShiftPressed;
    switch (_tool) {
      case PitchTool.split:
        if (i != null) {
          // At the nearest eighth of a beat, where that is inside it.
          var t = tOf(p.dx);
          var eighth = spb / 2;
          var snapped = ((startsAt + t) / eighth).round() * eighth - startsAt;
          var n = edit.notes[i];
          var at =
              snapped > n.start + 0.03 && snapped < n.end - 0.03 ? snapped : t;
          _edit((e) => e.split(i, at));
        }
      case PitchTool.glue:
        if (i != null) _edit((e) => e.glue(i));
      case PitchTool.move:
        // Twice on a note: back to the nearest note.
        var now = DateTime.now();
        if (i != null &&
            i == _lastTapNote &&
            now.difference(_lastTapAt) < const Duration(milliseconds: 350)) {
          _edit((e) => e.copyWith(
              notes: [...e.notes]..[i] = e.notes[i].movedTo(
                  _snap == PitchSnap.off
                      ? e.notes[i].sung.roundToDouble()
                      : _snapped(e.notes[i].sung))));
          _lastTapNote = null;
          return;
        }
        _lastTapNote = i;
        _lastTapAt = now;
        setState(() {
          if (i == null) {
            if (!shift) _picked = {};
          } else if (shift) {
            _picked = {..._picked}..toggle(i);
          } else {
            _picked = {i};
          }
        });
      case PitchTool.draw:
      case PitchTool.line:
        break;
    }
  }

  void _panStart(
      Offset p,
      PitchEdit edit,
      double Function(double) yOf,
      double Function(double) mOf,
      double Function(double) tOf,
      double perSecond,
      double rowH) {
    _dragFrom = p;
    switch (_tool) {
      case PitchTool.move:
        var i = _noteAt(p, edit.notes, yOf, perSecond, rowH);
        if (i == null) {
          // On nothing: a box to pick by.
          setState(() => _box = Rect.fromPoints(p, p));
          return;
        }
        setState(() {
          if (!_picked.contains(i)) {
            _picked = HardwareKeyboard.instance.isShiftPressed
                ? {..._picked, i}
                : {i};
          }
        });
        _targetsFrom = {for (var j in _picked) j: _shown(edit.notes[j])};
        c.beginInteraction();
      case PitchTool.draw:
        setState(() => _drawing = [(tOf(p.dx), mOf(p.dy))]);
      case PitchTool.line:
        setState(() {
          _lineFrom = (tOf(p.dx), mOf(p.dy));
          _lineTo = _lineFrom;
        });
      case PitchTool.split:
      case PitchTool.glue:
        _dragFrom = null;
    }
  }

  void _panUpdate(Offset p, double rowH, double Function(double) mOf,
      double Function(double) tOf) {
    var from = _dragFrom;
    if (from == null) return;
    switch (_tool) {
      case PitchTool.move:
        if (_box != null) {
          setState(() => _box = Rect.fromPoints(from, p));
          return;
        }
        if (_targetsFrom.isEmpty) return;
        var by = -(p.dy - from.dy) / rowH;
        var alt = HardwareKeyboard.instance.isAltPressed;
        _edit(
            (e) => e.copyWith(notes: [
                  for (var (i, n) in e.notes.indexed)
                    if (_targetsFrom[i] case var was?)
                      () {
                        var want = was + by;
                        // Onto the scale, or a semitone; free with Alt.
                        if (!alt) want = _snapped(want);
                        return n.copyWith(shift: n.shift + want - n.target);
                      }()
                    else
                      n
                ]),
            transient: true);
      case PitchTool.draw:
        var t = tOf(p.dx);
        if (_drawing.isNotEmpty && t <= _drawing.last.$1) return;
        setState(() => _drawing = [..._drawing, (t, mOf(p.dy))]);
      case PitchTool.line:
        setState(() => _lineTo = (tOf(p.dx), mOf(p.dy)));
      case PitchTool.split:
      case PitchTool.glue:
        break;
    }
  }

  void _panEnd(PitchEdit edit, double Function(double) yOf, double perSecond,
      double rowH) {
    if (_dragFrom == null) return;
    _dragFrom = null;
    switch (_tool) {
      case PitchTool.move:
        if (_box case var box?) {
          setState(() {
            _box = null;
            var inside = {
              for (var (i, n) in edit.notes.indexed)
                if (box.overlaps(Rect.fromLTRB(
                    n.start * perSecond,
                    yOf(_shown(n)) - rowH / 2,
                    n.end * perSecond,
                    yOf(_shown(n)) + rowH / 2)))
                  i
            };
            _picked = HardwareKeyboard.instance.isShiftPressed
                ? {..._picked, ...inside}
                : inside;
          });
          return;
        }
        if (_targetsFrom.isNotEmpty) {
          _targetsFrom = {};
          c.endInteraction();
        }
      case PitchTool.draw:
        _drawInto(_drawing);
        setState(() => _drawing = []);
      case PitchTool.line:
        var a = _lineFrom, b = _lineTo;
        setState(() => _lineFrom = _lineTo = null);
        if (a == null || b == null) return;
        var (t0, m0) = a.$1 <= b.$1 ? a : b;
        var (t1, m1) = a.$1 <= b.$1 ? b : a;
        if (t1 - t0 < 0.02) return;
        var steps = ((t1 - t0) / 0.02).ceil();
        _drawInto([
          for (var k = 0; k <= steps; k++)
            (t0 + (t1 - t0) * k / steps, m0 + (m1 - m0) * k / steps)
        ]);
      case PitchTool.split:
      case PitchTool.glue:
        break;
    }
  }

  /// _drawInto gives each note the part of [points] over it as its drawn
  /// pitch, in place of what was drawn there before.
  void _drawInto(List<(double, double)> points) {
    if (points.length < 2) return;
    _edit((e) => e.copyWith(notes: [
          for (var n in e.notes)
            () {
              var over = [
                for (var p in points)
                  if (p.$1 >= n.start && p.$1 <= n.end) p
              ];
              return over.length < 2 ? n : n.copyWith(curve: over);
            }()
        ]));
  }

  KeyEventResult _key(KeyEvent e, PitchEdit edit) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    var keys = HardwareKeyboard.instance;
    var k = e.logicalKey;
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        k == LogicalKeyboardKey.keyZ) {
      keys.isShiftPressed ? c.redo() : c.undo();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      if (_picked.isEmpty) return KeyEventResult.ignored;
      var up = k == LogicalKeyboardKey.arrowUp;
      _eachPicked((n) =>
          n.copyWith(shift: n.shift + _stepped(_shown(n), up) - n.target));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      setState(() => _picked = {});
      return KeyEventResult.handled;
    }
    for (var t in PitchTool.values) {
      if (k.keyLabel.toUpperCase() == t.shortcut) {
        setState(() => _tool = t);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---- The inspector.

  Widget _inspectorPanel(MixerLook look, PitchEdit edit, List<double?> track) {
    var s = look.studio;
    var head = TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: s.muted);
    var body = TextStyle(fontSize: 11.5, height: 1.4, color: s.text);
    var picked = [for (var i in _picked) edit.notes[i]];
    var tune = _tune;
    return Container(
      key: const ValueKey("pitchInspector"),
      color: s.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (picked.isEmpty) ...[
            Text("THE WHOLE CLIP", style: head),
            const SizedBox(height: 6),
            Text(
                "Pick a note to set its own retune, vibrato, drift and "
                "formant. Drag it up or down to move it; shift-click or drag "
                "a box to pick several.",
                style: body),
            const SizedBox(height: 6),
            Text(
                "The red line is what was sung. The purple line is what you "
                "hear after correction. A dashed box shows where a note was "
                "heard, with an arrow to where it is going.",
                style: body),
          ] else
            ..._noteSettings(look, edit, picked, head, body),
          if (tune != null) ...[
            const SizedBox(height: 14),
            Text("EVERY NOTE", style: head),
            const SizedBox(height: 4),
            _slider(
                look,
                "Amount",
                "pitchAmount",
                tune.value("amount"),
                0,
                1,
                "${(tune.value("amount") * 100).round()}%",
                (v, {transient = false}) =>
                    _setTuneValue("amount", v, transient: transient)),
            _slider(
                look,
                "Humanise",
                "pitchHumanise",
                tune.value("humanise"),
                0,
                1,
                "${(tune.value("humanise") * 100).round()}%",
                (v, {transient = false}) =>
                    _setTuneValue("humanise", v, transient: transient)),
            Text("These are the Auto-tune device's own knobs.",
                style: body.copyWith(color: s.muted, fontSize: 11)),
          ],
        ]),
      ),
    );
  }

  List<Widget> _noteSettings(MixerLook look, PitchEdit edit,
      List<PitchNote> picked, TextStyle head, TextStyle body) {
    var s = look.studio;
    var n = picked.first;
    var first = _picked.reduce(math.min);
    var sung = n.sung.round();
    String cents(double v) {
      var c = (v * 100).round();
      return "${c >= 0 ? "+" : "−"}${c.abs()} ct";
    }

    Widget button(String label, String k, PitchNote Function(PitchNote) f) =>
        OutlinedButton(
          key: ValueKey(k),
          style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: s.text,
              side: BorderSide(color: s.edge),
              textStyle: const TextStyle(fontSize: 11)),
          onPressed: () => _eachPicked(f),
          child: Text(label),
        );
    void each(PitchNote Function(PitchNote n, double v) f, double v,
            {bool transient = false}) =>
        _eachPicked((n) => f(n, v), transient: transient);
    Widget slider(String label, String k, double value, double min, double max,
            String reading, PitchNote Function(PitchNote n, double v) f) =>
        _slider(look, label, k, value, min, max, reading,
            (v, {transient = false}) => each(f, v, transient: transient));
    var target = _shown(n);
    var targetNote = target.round();
    return [
      Text(
          picked.length == 1
              ? "NOTE ${first + 1} OF ${edit.notes.length}"
              : "${picked.length} PICKED",
          key: const ValueKey("pitchPickedTitle"),
          style: head),
      const SizedBox(height: 8),
      Row(children: [
        Text("Target", style: body.copyWith(color: s.muted)),
        const Spacer(),
        IconButton(
          key: const ValueKey("pitchTargetDown"),
          tooltip: "Down a note",
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          color: s.text,
          icon: const Icon(Icons.remove),
          onPressed: () => _eachPicked((m) => m.copyWith(
              shift: m.shift + _stepped(_shown(m), false) - m.target)),
        ),
        Text(
            "${noteName(targetNote)}"
            "${(target - targetNote).abs() > 0.005 ? " ${cents(target - targetNote)}" : ""}",
            key: const ValueKey("pitchTarget"),
            style: body.copyWith(fontWeight: FontWeight.w600)),
        IconButton(
          key: const ValueKey("pitchTargetUp"),
          tooltip: "Up a note",
          iconSize: 15,
          visualDensity: VisualDensity.compact,
          color: s.text,
          icon: const Icon(Icons.add),
          onPressed: () => _eachPicked((m) => m.copyWith(
              shift: m.shift + _stepped(_shown(m), true) - m.target)),
        ),
      ]),
      Row(children: [
        Text("Heard as", style: body.copyWith(color: s.muted)),
        const Spacer(),
        Text("${noteName(sung)} ${cents(n.sung - sung)}",
            key: const ValueKey("pitchHeardAs"),
            style: body.copyWith(color: sungInk)),
      ]),
      const SizedBox(height: 6),
      slider("Retune", "pitchRetune", n.retuneMs, 0, 400,
          "${n.retuneMs.round()} ms", (m, v) => m.copyWith(retuneMs: v)),
      slider("Vibrato", "pitchVibrato", n.vibrato, 0, 2,
          "${(n.vibrato * 100).round()}%", (m, v) => m.copyWith(vibrato: v)),
      slider("Drift kept", "pitchWobble", n.wobble, 0, 2,
          "${(n.wobble * 100).round()}%", (m, v) => m.copyWith(wobble: v)),
      slider(
          "Formant",
          "pitchFormant",
          n.formant,
          -12,
          12,
          "${n.formant >= 0 ? "+" : "−"}${n.formant.abs().toStringAsFixed(1)} st",
          (m, v) => m.copyWith(formant: (v * 2).roundToDouble() / 2)),
      slider("Slide in", "pitchSlide", n.slideMs, 0, 400,
          "${n.slideMs.round()} ms", (m, v) => m.copyWith(slideMs: v)),
      slider(
          "Gain",
          "pitchGain",
          n.gainDb,
          -24,
          12,
          "${n.gainDb.toStringAsFixed(1)} dB",
          (m, v) => m.copyWith(gainDb: (v * 2).roundToDouble() / 2)),
      const SizedBox(height: 6),
      Wrap(spacing: 5, runSpacing: 5, children: [
        button("Reset note", "pitchResetNote", (m) => m.reset),
        button("Flatten", "pitchFlatten",
            (m) => m.copyWith(wobble: 0, vibrato: 0)),
        button("Natural", "pitchNatural",
            (m) => m.copyWith(wobble: 1, vibrato: 1, retuneMs: 60)),
        button("Clear drawing", "pitchClearDrawing",
            (m) => m.copyWith(curve: const [])),
      ]),
    ];
  }

  Widget _slider(
      MixerLook look,
      String label,
      String k,
      double value,
      double min,
      double max,
      String reading,
      void Function(double v, {bool transient}) set) {
    var s = look.studio;
    return Row(children: [
      SizedBox(
          width: 64,
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: s.muted))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
          child: Slider(
            key: ValueKey(k),
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: correctedInk,
            onChangeStart: (_) => c.beginInteraction(),
            onChanged: (v) => set(v, transient: true),
            onChangeEnd: (_) => c.endInteraction(),
          ),
        ),
      ),
      SizedBox(
          width: 52,
          child: Text(reading,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                  fontSize: 10.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: s.text))),
    ]);
  }

  // ---- The status line.

  Widget _statusLine(StudioColors s, PitchEdit edit) {
    var tip = switch (_tool) {
      PitchTool.move => "Drag a note up or down to change it · double-click "
          "to go back to the nearest note · right-click clears a drawn "
          "curve · ⌘ scroll for row height",
      PitchTool.split => "Click a note to cut it in two, at the nearest "
          "eighth of a beat",
      PitchTool.glue => "Click a note to join it to the next",
      PitchTool.draw => "Drag across notes to draw the pitch they sing · "
          "right-click a note to clear it",
      PitchTool.line => "Drag from where a slide starts to where it ends",
    };
    var style = TextStyle(fontSize: 10.5, color: s.muted);
    return SizedBox(
      height: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: Text(tip,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          const SizedBox(width: 8),
          Text(
              edit.stale
                  ? "Making it…"
                  : "${edit.notes.length} notes, "
                      "${edit.notes.where((n) => n.edited).length} changed",
              key: const ValueKey("pitchStatus"),
              style: style),
        ]),
      ),
    );
  }
}

extension on Set<int> {
  void toggle(int i) => contains(i) ? remove(i) : add(i);
}

// ---- Painters.

class _KeysPainter extends CustomPainter {
  final double top, bottom, rowH;
  final bool Function(int) inScale;
  final int root;
  final StudioColors s;
  _KeysPainter(
      this.top, this.bottom, this.rowH, this.inScale, this.root, this.s);

  static const _black = {1, 3, 6, 8, 10};

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = top.toInt(); k > bottom; k--) {
      var y = (top - k) * rowH;
      var black = _black.contains(k % 12);
      var rect = Rect.fromLTWH(0, y, size.width - 4, rowH);
      canvas.drawRect(
          rect,
          Paint()
            ..color =
                black ? const Color(0xFF26262C) : const Color(0xFFE8E6EE));
      canvas.drawLine(Offset(0, y), Offset(size.width - 4, y),
          Paint()..color = const Color(0xFF9A98A6));
      // Its mark: in the key's scale, the key's own stronger.
      if (inScale(k)) {
        canvas.drawRect(
            Rect.fromLTWH(size.width - 4, y + 1, 3, rowH - 2),
            Paint()
              ..color = correctedInk.withValues(
                  alpha: (k - root) % 12 == 0 ? 1 : 0.6));
      }
      if (k % 12 == 0 || rowH >= 14) {
        var tp = TextPainter(
            text: TextSpan(
                text: noteName(k),
                style: TextStyle(
                    fontSize: math.min(10, rowH * 0.7),
                    color: black
                        ? const Color(0xFFCFCDD8)
                        : const Color(0xFF4A4857))),
            textDirection: TextDirection.ltr)
          ..layout();
        if (tp.height <= rowH + 2) {
          tp.paint(canvas,
              Offset(size.width - 8 - tp.width, y + rowH / 2 - tp.height / 2));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) =>
      old.top != top ||
      old.bottom != bottom ||
      old.rowH != rowH ||
      old.root != root ||
      old.inScale != inScale;
}

class _RulerPainter extends CustomPainter {
  final double perSecond, length;
  final double Function(int beat) beatAt;
  final int perBar;
  final double? playhead;
  final StudioColors s;
  _RulerPainter(
      {required this.perSecond,
      required this.beatAt,
      required this.perBar,
      required this.length,
      required this.playhead,
      required this.s});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.panel);
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), Paint()..color = s.edge);
    var first = 0;
    while (beatAt(first) > 0) {
      first--;
    }
    while (beatAt(first + 1) < 0) {
      first++;
    }
    for (var k = first; beatAt(k) <= length + 1; k++) {
      var x = beatAt(k) * perSecond;
      if (x < -1 || x > size.width) continue;
      var bar = k % perBar == 0;
      canvas.drawLine(Offset(x, bar ? 4 : size.height - 6),
          Offset(x, size.height), Paint()..color = bar ? s.muted : s.edge);
      if (bar) {
        var tp = TextPainter(
            text: TextSpan(
                text: "${k ~/ perBar + 1}",
                style: TextStyle(fontSize: 10, color: s.text)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(x + 3, 3));
      }
    }
    if (playhead case var t?) {
      var x = t * perSecond;
      var path = Path()
        ..moveTo(x - 5, 0)
        ..lineTo(x + 5, 0)
        ..lineTo(x, 7)
        ..close();
      canvas.drawPath(path, Paint()..color = s.text);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.perSecond != perSecond ||
      old.playhead != playhead ||
      old.length != length;
}

class _VoicePainter extends CustomPainter {
  final Float32List? peaks;
  final double perSecond, fileLength;
  final StudioColors s;
  _VoicePainter(
      {required this.peaks,
      required this.perSecond,
      required this.fileLength,
      required this.s});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.panel);
    canvas.drawLine(
        const Offset(0, 0.5), Offset(size.width, 0.5), Paint()..color = s.edge);
    var p = peaks;
    var mid = size.height / 2;
    if (p == null || p.isEmpty) {
      canvas.drawLine(
          Offset(0, mid), Offset(size.width, mid), Paint()..color = s.edge);
      return;
    }
    var paint = Paint()
      ..color = _blobInk.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 2) {
      var t = x / perSecond;
      if (t > fileLength) break;
      var i = (t / fileLength * p.length).floor().clamp(0, p.length - 1);
      var h = p[i] * (size.height / 2 - 3);
      canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
    }
  }

  @override
  bool shouldRepaint(_VoicePainter old) =>
      old.peaks != peaks || old.perSecond != perSecond;
}

class _PitchGrid extends CustomPainter {
  final List<PitchNote> notes;

  /// shown is where each note is heard: see _shown.
  final List<double> shown;
  final List<double?> track, heard;
  final double top, bottom, perSecond, rowH;
  final Set<int> picked;
  final bool Function(int) inScale;
  final int root;
  final double Function(int beat) beatAt;
  final int perBar;
  final double? playhead;
  final Rect? box;
  final List<(double, double)> drawing;
  final ((double, double), (double, double))? line;
  final StudioColors s;
  _PitchGrid(
      {required this.notes,
      required this.shown,
      required this.track,
      required this.heard,
      required this.top,
      required this.bottom,
      required this.perSecond,
      required this.rowH,
      required this.picked,
      required this.inScale,
      required this.root,
      required this.beatAt,
      required this.perBar,
      required this.playhead,
      required this.box,
      required this.drawing,
      required this.line,
      required this.s});

  double _y(double m) => (top - m) * rowH + rowH / 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.display);
    // A row a semitone: the scale's shaded, the key's own darker.
    for (var k = top.toInt(); k > bottom; k--) {
      var y = (top - k) * rowH;
      if (inScale(k)) {
        canvas.drawRect(
            Rect.fromLTWH(0, y, size.width, rowH),
            Paint()
              ..color = correctedInk.withValues(
                  alpha: (k - root) % 12 == 0 ? 0.12 : 0.055));
      }
      canvas.drawLine(Offset(0, y), Offset(size.width, y),
          Paint()..color = s.edge.withValues(alpha: k % 12 == 0 ? 0.8 : 0.3));
    }
    // Beats and bars.
    var length = size.width / perSecond;
    var first = 0;
    while (beatAt(first) > 0) {
      first--;
    }
    for (var k = first; beatAt(k) <= length; k++) {
      var x = beatAt(k) * perSecond;
      if (x < 0) continue;
      canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = s.edge.withValues(alpha: k % perBar == 0 ? 0.9 : 0.35));
    }
    // The notes, at the notes they go to; where each was heard, boxed,
    // with an arrow from there.
    var on = playhead;
    for (var (i, n) in notes.indexed) {
      var x0 = n.start * perSecond, x1 = n.end * perSecond;
      var target = shown[i];
      var y = _y(target);
      var h = math.max(6.0, rowH * 0.8);
      var moved = (target - n.sung).abs() > 0.12;
      if (moved) {
        var hy = _y(n.sung);
        _dashed(canvas, Rect.fromLTRB(x0, hy - h / 2, x1, hy + h / 2),
            sungInk.withValues(alpha: 0.8));
        // The arrow, from the box to the note.
        var ax = x0 + math.min(14, (x1 - x0) / 2);
        var from = Offset(ax, hy + (target > n.sung ? -h / 2 : h / 2));
        var to = Offset(ax, y + (target > n.sung ? h / 2 : -h / 2));
        var arrow = Paint()
          ..color = _amber
          ..strokeWidth = 1.4;
        canvas.drawLine(from, to, arrow);
        var dir = target > n.sung ? -1 : 1;
        canvas.drawPath(
            Path()
              ..moveTo(to.dx, to.dy)
              ..lineTo(to.dx - 3.5, to.dy - 5 * dir)
              ..lineTo(to.dx + 3.5, to.dy - 5 * dir)
              ..close(),
            Paint()..color = _amber);
        // How far from its own note it was sung.
        var cents = ((n.sung - n.sung.round()) * 100).round();
        if (cents != 0 && x1 - x0 > 26) {
          _label(canvas, "${cents > 0 ? "+" : "−"}${cents.abs()}",
              Offset(x1 - 2, hy - h / 2 - 1), _amber,
              right: true);
        }
      }
      var playing = on != null && on >= n.start && on <= n.end;
      var blob = RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, y - h / 2, math.max(x0 + 4, x1), y + h / 2),
          Radius.circular(h / 2));
      canvas.drawRRect(
          blob,
          Paint()
            ..color = _blobInk.withValues(
                alpha: playing ? 0.75 : (n.edited ? 0.5 : 0.35)));
      canvas.drawRRect(
          blob,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = picked.contains(i) ? 2 : 1
            ..color = picked.contains(i)
                ? Colors.white
                : _blobInk.withValues(alpha: 0.9));
      // A drawn pitch over it.
      if (n.curve.length >= 2) {
        var path = Path()
          ..moveTo(n.curve.first.$1 * perSecond, _y(n.curve.first.$2));
        for (var (t, m) in n.curve.skip(1)) {
          path.lineTo(t * perSecond, _y(m));
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white.withValues(alpha: 0.85));
      }
    }
    // As sung, red; as heard, purple, glowing.
    _curve(canvas, track, sungInk.withValues(alpha: 0.85), 1.2);
    _curve(canvas, heard, correctedInk.withValues(alpha: 0.35), 5);
    _curve(canvas, heard, correctedInk, 1.8);
    // Being drawn.
    if (drawing.length >= 2) {
      var path = Path()
        ..moveTo(drawing.first.$1 * perSecond, _y(drawing.first.$2));
      for (var (t, m) in drawing.skip(1)) {
        path.lineTo(t * perSecond, _y(m));
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }
    if (line case ((var t0, var m0), (var t1, var m1))?) {
      canvas.drawLine(
          Offset(t0 * perSecond, _y(m0)),
          Offset(t1 * perSecond, _y(m1)),
          Paint()
            ..strokeWidth = 2
            ..color = Colors.white);
    }
    if (box case var b?) {
      canvas.drawRect(b, Paint()..color = Colors.white.withValues(alpha: 0.08));
      canvas.drawRect(
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.white.withValues(alpha: 0.6));
    }
    if (on != null) {
      var x = on * perSecond;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          Paint()..color = s.text.withValues(alpha: 0.8));
    }
  }

  void _curve(Canvas canvas, List<double?> m, Color colour, double width) {
    var paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = colour;
    Path? path;
    for (var (i, p) in m.indexed) {
      if (p == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      var o = Offset(i * 0.02 * perSecond, _y(p));
      if (path == null) {
        path = Path()..moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  void _dashed(Canvas canvas, Rect r, Color colour) {
    var paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    void run(Offset a, Offset b) {
      var d = (b - a).distance;
      var dir = (b - a) / d;
      for (var u = 0.0; u < d; u += 6) {
        canvas.drawLine(a + dir * u, a + dir * math.min(d, u + 3), paint);
      }
    }

    run(r.topLeft, r.topRight);
    run(r.topRight, r.bottomRight);
    run(r.bottomRight, r.bottomLeft);
    run(r.bottomLeft, r.topLeft);
  }

  void _label(Canvas canvas, String text, Offset at, Color colour,
      {bool right = false}) {
    var tp = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontSize: 9.5, color: colour)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(
        canvas, Offset(right ? at.dx - tp.width : at.dx, at.dy - tp.height));
  }

  @override
  bool shouldRepaint(_PitchGrid old) => true;
}
