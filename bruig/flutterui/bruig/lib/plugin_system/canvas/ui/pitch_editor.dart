import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart' show snapNote;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show InstrumentPart;
import 'package:bruig/plugin_system/canvas/model/speech_spec.dart'
    show TimedWord;
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

/// _Grip is what of a note a drag takes hold of, besides the note: an edge
/// to stretch it by, or a fade's handle.
enum _Grip { start, end, fadeIn, fadeOut }

/// _blobH is how tall a note is drawn on rows [rowH] apart: taller than
/// its row, so its sound drawn inside it reads.
double _blobH(double rowH) => math.max(14.0, rowH * 1.25);

const _blobInk = Color(0xFFD9669A);
const _soundInk = Color(0xFFF4B3D0);
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

  // An edge or a fade being dragged, and the note the pointer is over.
  (int, _Grip)? _gripping;
  int? _hover;
  MouseCursor _cursor = MouseCursor.defer;

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
    if (_sounding case var held?) c.audio.noteOff(key, held);
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
              SizedBox(
                  width: _inspectorW,
                  child: _inspectorPanel(look, edit, track)),
            ],
          ]),
        ),
        Container(height: 1, color: s.edge),
        _statusLine(s, edit),
      ]),
    );
  }

  // ---- The toolbar: the clip editor's bar of small buttons (see
  // ClipEditor._tb), so it fits its room as the prototype's does.

  Widget _tb(MixerLook look, String key, String label, VoidCallback? tap,
      {bool on = false, IconData? icon, String? tip, bool menu = false}) {
    var s = look.studio;
    var ink = tap == null
        ? s.muted.withValues(alpha: 0.5)
        : on
            ? look.colors.onPrimary
            : s.text;
    return Tooltip(
      message: tip ?? label,
      child: InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(5),
        onTap: tap,
        child: Container(
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 5 : 7),
          decoration: BoxDecoration(
              color: on ? look.colors.primary : null,
              borderRadius: BorderRadius.circular(5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) Icon(icon, size: 14, color: ink),
            if (icon != null && label.isNotEmpty) const SizedBox(width: 4),
            if (label.isNotEmpty)
              Text(label, style: TextStyle(fontSize: 11, color: ink)),
            if (menu) Icon(Icons.arrow_drop_down, size: 16, color: ink),
          ]),
        ),
      ),
    );
  }

  Widget _tbGroup(MixerLook look, List<Widget> children) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
            border: Border.all(color: look.studio.edge),
            borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _tbGap(MixerLook look) => Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: look.studio.edge);

  Widget _tbMenu(MixerLook look, String key, String label, List<Widget> items,
          {IconData? icon, String? tip}) =>
      MenuAnchor(
        menuChildren: items,
        builder: (context, menu, _) => _tb(
            look, key, label, () => menu.isOpen ? menu.close() : menu.open(),
            icon: icon, tip: tip, menu: true),
      );

  MenuItemButton _menuItem(String key, String label, VoidCallback? tap,
          {bool on = false, String? hint}) =>
      MenuItemButton(
        key: ValueKey(key),
        leadingIcon: Icon(on ? Icons.check : null, size: 14),
        onPressed: tap,
        child: hint == null
            ? Text(label)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(label),
                    Text(hint,
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF9A98A6))),
                  ]),
      );

  void _toMidi(BuildContext context) {
    var why = c.notesToMidi(key, root: _rootNow, steps: _steps);
    try {
      var snack = SnackBarModel.of(context);
      why == null
          ? snack.success("Its notes are on a new MIDI channel")
          : snack.error(why);
    } catch (_) {}
  }

  Widget _toolbar(BuildContext context, MixerLook look, PitchEdit edit) {
    var keyNames = DeviceKind.autoTune.param("key").choices;
    var scaleNames = DeviceKind.autoTune.param("scale").choices;
    var asSung = c.pitchHeardAsSung(key);
    return SizedBox(
      height: 32,
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              // The tools, an icon each: the prototype's, their keys in
              // their tips.
              _tbGroup(look, [
                for (var t in PitchTool.values)
                  _tb(look, "pitchTool-${t.name}", "",
                      () => setState(() => _tool = t),
                      on: _tool == t,
                      icon: t.icon,
                      tip: "${t.label} (${t.shortcut})"),
              ]),
              _tbGap(look),
              // Where a dragged note lands, and the key and scale it is
              // the Auto-tune's own.
              _tbMenu(
                  look,
                  "pitchSnap",
                  _snap == PitchSnap.off ? "Free" : _snap.label,
                  [
                    for (var m in PitchSnap.values)
                      _menuItem("pitchSnap-${m.name}", m.label,
                          () => setState(() => _snap = m),
                          on: _snap == m),
                  ],
                  icon: Icons.straighten,
                  tip: "Where a dragged note lands"),
              _tbMenu(
                  look,
                  "pitchKeyScale",
                  "${keyNames[_rootNow]} "
                      "${scaleNames[_scaleNow].toLowerCase()}",
                  [
                    SubmenuButton(
                      menuChildren: [
                        for (var (i, n) in keyNames.indexed)
                          _menuItem(
                              "pitchKeyItem-$i", n, () => _setTune("key", i),
                              on: i == _rootNow),
                      ],
                      child: const Text("Key"),
                    ),
                    SubmenuButton(
                      menuChildren: [
                        for (var (i, n) in scaleNames.indexed)
                          _menuItem("pitchScaleItem-$i", n,
                              () => _setTune("scale", i),
                              on: i == _scaleNow),
                      ],
                      child: const Text("Scale"),
                    ),
                  ],
                  icon: Icons.music_note_outlined,
                  tip: _tune == null
                      ? "The notes' key and scale"
                      : "The Auto-tune's key and scale"),
              _tbGap(look),
              _tbGroup(look, [
                _tb(look, "pitchHearCorrected", "Corrected",
                    () => c.hearPitchAsSung(key, false),
                    on: !asSung, tip: "Hear it corrected"),
                _tb(look, "pitchHearSung", "As sung",
                    () => c.hearPitchAsSung(key, true),
                    on: asSung, tip: "Hear it as it was sung"),
              ]),
              _tbGap(look),
              _tb(look, "pitchCorrectAll", "Correct all", () {
                _edit((e) => e.copyWith(notes: [
                      for (var n in e.notes)
                        n.movedTo(_snap == PitchSnap.off
                            ? n.sung.roundToDouble()
                            : _snapped(n.sung))
                    ]));
              }, tip: "Every note onto the nearest of the scale"),
              _tb(look, "pitchQuantise", "Quantise", _quantise,
                  tip: "Each note's start onto the nearest sixteenth of the "
                      "song -- the picked ones, or all -- its sound "
                      "stretched to end where it did"),
              _tbMenu(
                  look,
                  "pitchMore",
                  "",
                  [
                    _menuItem(
                        "pitchToMidi", "Notes to MIDI", () => _toMidi(context),
                        hint: "A MIDI channel playing these notes"),
                    _menuItem("pitchReset", "As recorded", () {
                      setState(() => _picked = {});
                      c.forgetPitch(key);
                    }, hint: "Every note as it was sung"),
                  ],
                  icon: Icons.more_horiz,
                  tip: "Notes to MIDI, as recorded"),
              _tb(look, "pitchUndo", "", c.canUndo ? c.undo : null,
                  icon: Icons.undo, tip: "Undo (⌘Z)"),
            ]),
          ),
        ),
        // The view, pinned right as the prototype's.
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _tb(look, "pitchRowsSmaller", "",
                () => setState(() => _rowH = math.max(6, (_rowH ?? 16) - 3)),
                icon: Icons.unfold_less, tip: "Smaller rows"),
            _tb(look, "pitchRowsTaller", "",
                () => setState(() => _rowH = math.min(48, (_rowH ?? 16) + 3)),
                icon: Icons.unfold_more, tip: "Taller rows"),
            _tb(look, "pitchTimeOut", "",
                () => setState(() => _perSecond = (_perSecond ?? 120) / 1.4),
                icon: Icons.zoom_out, tip: "Less time across"),
            _tb(look, "pitchTimeIn", "",
                () => setState(() => _perSecond = (_perSecond ?? 120) * 1.4),
                icon: Icons.zoom_in, tip: "More time across"),
            _tb(
                look,
                "pitchFit",
                "",
                () => setState(() {
                      _rowH = null;
                      _perSecond = null;
                    }),
                icon: Icons.fit_screen_outlined,
                tip: "Fit the notes"),
            _tb(look, "pitchInspectorToggle", "",
                () => setState(() => _inspector = !_inspector),
                on: _inspector,
                icon: Icons.view_sidebar_outlined,
                tip: _inspector
                    ? "Hide the note settings"
                    : "Show the note settings"),
          ]),
        ),
      ]),
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
        words: c.pitchWordsOf(key) ?? const [],
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
        // Its sound drawn in each note: the original's, as each is heard.
        peaks: c.waveformOf(edit.original) ?? c.waveformOf(source.assetId),
        fileLength: fileLength <= 0 ? length : fileLength,
        hover: _hover,
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
        child: MouseRegion(
          cursor: _cursor,
          onHover: (h) =>
              _hovered(h.localPosition, notes, yOf, perSecond, rowH),
          onExit: (_) {
            if (_hover != null || _cursor != MouseCursor.defer) {
              setState(() {
                _hover = null;
                _cursor = MouseCursor.defer;
              });
            }
          },
          child: GestureDetector(
            key: const ValueKey("pitchGrid"),
            supportedDevices: dragPointers,
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (d) => _tap(d.localPosition, edit, yOf, tOf, perSecond,
                rowH, spb, startsAt),
            onPanStart: (d) => _panStart(
                d.localPosition, edit, yOf, mOf, tOf, perSecond, rowH),
            onPanUpdate: (d) => _panUpdate(d.localPosition, rowH, mOf, tOf),
            onPanEnd: (_) => _panEnd(edit, yOf, perSecond, rowH),
            child: CustomPaint(size: Size(width, height), painter: grid),
          ),
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
            // Pressed, a key sounds its note, as the prototype's do.
            child: Listener(
              onPointerDown: (d) =>
                  _sound((top - (d.localPosition.dy / rowH).floor()).round()),
              onPointerUp: (_) => _sound(null),
              onPointerCancel: (_) => _sound(null),
              child: CustomPaint(
                key: const ValueKey("pitchKeys"),
                size: Size(_keysW, height),
                painter: _KeysPainter(top, bottom, rowH, _inScale, _rootNow, s),
              ),
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
      if (t < n.heardStart - 0.02 || t > n.heardEnd + 0.02) continue;
      var d = (p.dy - yOf(_shown(n))).abs();
      if (d <= math.max(rowH, 10) && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// _gripAt is the edge or fade handle of a note at [p], if any: a fade's
  /// handle a small square on its top edge, its edges either side.
  (int, _Grip)? _gripAt(Offset p, List<PitchNote> notes,
      double Function(double) yOf, double perSecond, double rowH) {
    var h = _blobH(rowH);
    for (var (i, n) in notes.indexed) {
      var y = yOf(_shown(n));
      var top = y - h / 2, bottom = y + h / 2;
      if (p.dy < top - 6 || p.dy > bottom + 2) continue;
      var x0 = n.heardStart * perSecond, x1 = n.heardEnd * perSecond;
      if (p.dx < x0 - 6 || p.dx > x1 + 6) continue;
      if ((p - Offset(x0 + n.fadeIn * perSecond, top)).distance <= 6) {
        return (i, _Grip.fadeIn);
      }
      if ((p - Offset(x1 - n.fadeOut * perSecond, top)).distance <= 6) {
        return (i, _Grip.fadeOut);
      }
      if (p.dy < top) continue;
      var edge = math.min(5.0, (x1 - x0) / 4);
      if ((p.dx - x0).abs() <= edge) return (i, _Grip.start);
      if ((p.dx - x1).abs() <= edge) return (i, _Grip.end);
    }
    return null;
  }

  void _hovered(Offset p, List<PitchNote> notes, double Function(double) yOf,
      double perSecond, double rowH) {
    var grip = _tool == PitchTool.move
        ? _gripAt(p, notes, yOf, perSecond, rowH)
        : null;
    var over = grip?.$1 ?? _noteAt(p, notes, yOf, perSecond, rowH);
    var cursor =
        grip == null ? MouseCursor.defer : SystemMouseCursors.resizeLeftRight;
    if (over != _hover || cursor != _cursor) {
      setState(() {
        _hover = over;
        _cursor = cursor;
      });
    }
  }

  /// _fitted is [n] with its fades no longer than it is heard for.
  static PitchNote _fitted(PitchNote n) {
    var room = n.heardLength;
    var both = n.fadeIn + n.fadeOut;
    if (both <= room || both <= 0) return n;
    return n.copyWith(
        fadeIn: n.fadeIn * room / both, fadeOut: n.fadeOut * room / both);
  }

  /// _stretchedTo is note [i] of [notes] heard to end at [to]: not before
  /// it has started, nor past the next note's start.
  static PitchNote _stretchedTo(List<PitchNote> notes, int i, double to) {
    var n = notes[i];
    var next = i + 1 < notes.length ? notes[i + 1].heardStart : double.infinity;
    to = math.max(n.heardStart + 0.05, math.min(to, next));
    return _fitted((to - n.end).abs() < 0.003
        ? n.copyWith(clearEndAt: true)
        : n.copyWith(endAt: to));
  }

  /// _dragGrip moves note [i]'s [grip] to [t] seconds: an edge stretches
  /// its sound to fill where it now is, a handle sets a fade.
  void _dragGrip(int i, _Grip grip, double t) {
    _edit((e) {
      if (i >= e.notes.length) return e;
      var n = e.notes[i];
      PitchNote m;
      switch (grip) {
        case _Grip.start:
          var before = i > 0 ? e.notes[i - 1].heardEnd : 0.0;
          var at = math.min(math.max(t, before), n.heardEnd - 0.05);
          m = (at - n.start).abs() < 0.003
              ? n.copyWith(clearStartAt: true)
              : n.copyWith(startAt: at);
        case _Grip.end:
          m = _stretchedTo(e.notes, i, t);
        case _Grip.fadeIn:
          m = n.copyWith(
              fadeIn: (t - n.heardStart)
                  .clamp(0.0, math.max(0.0, n.heardLength - n.fadeOut))
                  .toDouble());
        case _Grip.fadeOut:
          m = n.copyWith(
              fadeOut: (n.heardEnd - t)
                  .clamp(0.0, math.max(0.0, n.heardLength - n.fadeIn))
                  .toDouble());
      }
      return e.copyWith(notes: [...e.notes]..[i] = _fitted(m));
    }, transient: true);
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
        // An edge to stretch it by, or a fade's handle.
        if (_gripAt(p, edit.notes, yOf, perSecond, rowH) case (var i, var g)?) {
          setState(() {
            _gripping = (i, g);
            if (!_picked.contains(i)) _picked = {i};
          });
          c.beginInteraction();
          return;
        }
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
        if (_gripping case (var i, var g)?) {
          _dragGrip(i, g, tOf(p.dx));
          return;
        }
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
                        // The first of them heard where it lands.
                        if (i == _targetsFrom.keys.first) {
                          _sound(want.round());
                        }
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
        if (_gripping != null) {
          setState(() => _gripping = null);
          c.endInteraction();
          return;
        }
        if (_box case var box?) {
          setState(() {
            _box = null;
            var inside = {
              for (var (i, n) in edit.notes.indexed)
                if (box.overlaps(Rect.fromLTRB(
                    n.heardStart * perSecond,
                    yOf(_shown(n)) - rowH / 2,
                    n.heardEnd * perSecond,
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
          _sound(null);
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

  /// _quantise moves each note's start -- the picked ones, or every one --
  /// onto the nearest sixteenth of the song, as it falls on the timeline:
  /// not before the note before it ends, nor too near its own end.
  void _quantise() {
    var e = c.pitchElementOf(key);
    var source = c.pitchSourceOf(key);
    if (e == null || source == null) return;
    var spb = math.max(0.001, c.document.audio.secondsPerBeat);
    var grid = spb / 4;
    var startsAt = e.clip.at / c.document.frameRate - source.start;
    _edit((edit) {
      var out = <PitchNote>[];
      for (var (i, n) in edit.notes.indexed) {
        if (_picked.isNotEmpty && !_picked.contains(i)) {
          out.add(n);
          continue;
        }
        var at = ((startsAt + n.start) / grid).round() * grid - startsAt;
        var least = out.isEmpty ? 0.0 : out.last.heardEnd;
        at = at.clamp(least, math.max(least, n.heardEnd - 0.05)).toDouble();
        out.add((at - n.start).abs() < 0.0005
            ? n.copyWith(clearStartAt: true)
            : n.copyWith(startAt: at));
      }
      return edit.copyWith(notes: out);
    });
  }

  /// _sounding is the key heard now -- pressed, or a note dragged to it.
  int? _sounding;

  /// _sound plays [key] on the piano, through the channel -- the one before
  /// let go -- or, null, lets go.
  void _sound(int? key) {
    if (key == _sounding) return;
    if (_sounding case var was?) c.audio.noteOff(key0, was);
    _sounding = key;
    if (key != null && key >= 0 && key < 128) {
      unawaited(c.audio.noteOn(key0, const InstrumentPart(), key, 96));
    }
  }

  /// key0 is the channel the keys are heard through.
  String get key0 => widget.channel;

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

  // ---- The inspector: compact, as the clip editor's, so a picked note's
  // settings fit without scrolling.

  static const double _inspectorW = 226;

  Widget _inspectorPanel(MixerLook look, PitchEdit edit, List<double?> track) {
    var s = look.studio;
    var head = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: s.muted);
    var body = TextStyle(fontSize: 11, height: 1.35, color: s.text);
    var picked = [for (var i in _picked) edit.notes[i]];
    var tune = _tune;
    return Container(
      key: const ValueKey("pitchInspector"),
      color: s.panel,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (picked.isEmpty) ...[
            Text("THE WHOLE CLIP", style: head),
            const SizedBox(height: 4),
            Text(
                "Pick a note to set its own retune, vibrato, drift, "
                "formant, length and fades. Drag it up or down to move it, "
                "its edges to stretch it, and the squares on its top edge "
                "to fade it.",
                style: body),
            const SizedBox(height: 4),
            Text(
                "Red is what was sung, purple what is heard. A dashed box "
                "shows where a note was sung.",
                style: body.copyWith(color: s.muted)),
          ] else
            ..._noteSettings(look, edit, picked, head, body),
          if (tune != null) ...[
            const SizedBox(height: 8),
            Tooltip(
                message: "These are the Auto-tune device's own knobs",
                child: Text("EVERY NOTE", style: head)),
            const SizedBox(height: 2),
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
        _tb(look, k, label, () => _eachPicked(f));
    void each(PitchNote Function(PitchNote n, double v) f, double v,
            {bool transient = false}) =>
        _eachPicked((n) => _fitted(f(n, v)), transient: transient);
    Widget slider(String label, String k, double value, double min, double max,
            String reading, PitchNote Function(PitchNote n, double v) f) =>
        _slider(look, label, k, value, min, max, reading,
            (v, {transient = false}) => each(f, v, transient: transient));
    // A length a picked note is stretched to: each from where it starts,
    // none past the next.
    void stretchTo(double v, {bool transient = false}) => _edit(
        (e) => e.copyWith(notes: [
              for (var (i, m) in e.notes.indexed)
                _picked.contains(i)
                    ? _stretchedTo(e.notes, i, m.heardStart + m.length * v)
                    : m
            ]),
        transient: transient);
    var target = _shown(n);
    var targetNote = target.round();
    var room = math.max(0.05, n.heardLength);
    var mono = TextStyle(
        fontSize: 11,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: s.text);
    return [
      Text(
          picked.length == 1
              ? "NOTE ${first + 1} OF ${edit.notes.length}"
              : "${picked.length} PICKED",
          key: const ValueKey("pitchPickedTitle"),
          style: head),
      const SizedBox(height: 4),
      // Where it goes, and where it was heard: one row.
      SizedBox(
        height: 24,
        child: Row(children: [
          _tb(
              look,
              "pitchTargetDown",
              "",
              () => _eachPicked((m) => m.copyWith(
                  shift: m.shift + _stepped(_shown(m), false) - m.target)),
              icon: Icons.remove,
              tip: "Down a note"),
          Expanded(
            child: Text(
                "${noteName(targetNote)}"
                "${(target - targetNote).abs() > 0.005 ? " ${cents(target - targetNote)}" : ""}",
                key: const ValueKey("pitchTarget"),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(fontWeight: FontWeight.w600)),
          ),
          _tb(
              look,
              "pitchTargetUp",
              "",
              () => _eachPicked((m) => m.copyWith(
                  shift: m.shift + _stepped(_shown(m), true) - m.target)),
              icon: Icons.add,
              tip: "Up a note"),
          const SizedBox(width: 6),
          Flexible(
            child: Text("sung ${noteName(sung)} ${cents(n.sung - sung)}",
                key: const ValueKey("pitchHeardAs"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: sungInk, fontSize: 10.5)),
          ),
        ]),
      ),
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
      // Its timing: how long it is heard, stretched by its edges, and its
      // fades, set by the squares on its top edge.
      _slider(
          look,
          "Length",
          "pitchStretch",
          n.stretch,
          0.5,
          2,
          "${n.heardLength.toStringAsFixed(2)}s",
          (v, {transient = false}) =>
              stretchTo((v - 1).abs() < 0.02 ? 1 : v, transient: transient)),
      slider("Fade in", "pitchFadeIn", n.fadeIn, 0, room,
          "${(n.fadeIn * 1000).round()} ms", (m, v) => m.copyWith(fadeIn: v)),
      slider("Fade out", "pitchFadeOut", n.fadeOut, 0, room,
          "${(n.fadeOut * 1000).round()} ms", (m, v) => m.copyWith(fadeOut: v)),
      const SizedBox(height: 4),
      Wrap(spacing: 2, runSpacing: 2, children: [
        button("Reset", "pitchResetNote", (m) => m.reset),
        button("Flatten", "pitchFlatten",
            (m) => m.copyWith(wobble: 0, vibrato: 0)),
        button("Natural", "pitchNatural",
            (m) => m.copyWith(wobble: 1, vibrato: 1, retuneMs: 60)),
        button("Clear drawing", "pitchClearDrawing",
            (m) => m.copyWith(curve: const [])),
      ]),
    ];
  }

  /// _slider is one of the inspector's settings on a short row: its label,
  /// a thin slider, and its reading.
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
    return SizedBox(
      height: 20,
      child: Row(children: [
        SizedBox(
            width: 58,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: s.muted))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
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
            width: 50,
            child: Text(reading,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(
                    fontSize: 10.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: s.text))),
      ]),
    );
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

  /// words are what was said in the recording, timed in it: each note's
  /// lyric, the word it starts in.
  final List<TimedWord> words;

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

  /// peaks are the original's loudness, [fileLength] seconds of it: drawn
  /// inside each note, as it is heard.
  final Float32List? peaks;
  final double fileLength;

  /// hover is the note the pointer is over: its handles shown, as a picked
  /// note's are.
  final int? hover;
  final StudioColors s;
  _PitchGrid(
      {required this.notes,
      required this.shown,
      this.words = const [],
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
      this.peaks,
      this.fileLength = 0,
      this.hover,
      required this.s});

  double _y(double m) => (top - m) * rowH + rowH / 2;

  /// _loudest is the original's loudest peak, its sound drawn to it.
  late final double _loudest = () {
    var most = 0.0;
    for (var v in peaks ?? Float32List(0)) {
      if (v > most) most = v;
    }
    return most;
  }();

  /// _peakAt is how loud the original is [t] seconds in, nought to one.
  double _peakAt(double t) {
    var p = peaks;
    if (p == null || p.isEmpty || fileLength <= 0 || _loudest <= 0) return 0;
    var i = (t / fileLength * p.length).floor();
    if (i < 0 || i >= p.length) return 0;
    return p[i] / _loudest;
  }

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
      // Where it is heard -- moved by Quantise timing, or stretched by its
      // edges -- and, boxed, where it was sung.
      var x0 = n.heardStart * perSecond, x1 = n.heardEnd * perSecond;
      var sungX = n.start * perSecond, sungX1 = n.end * perSecond;
      var target = shown[i];
      var y = _y(target);
      var h = _blobH(rowH);
      var moved = (target - n.sung).abs() > 0.12 || n.timed;
      if (moved) {
        var hy = _y(n.sung);
        var bh = math.max(6.0, h * 0.6);
        _dashed(canvas, Rect.fromLTRB(sungX, hy - bh / 2, sungX1, hy + bh / 2),
            sungInk.withValues(alpha: 0.8));
        if ((target - n.sung).abs() > 0.12) {
          // The arrow, from the box to the note.
          var ax = x0 + math.min(14, (x1 - x0) / 2);
          var from = Offset(ax, hy + (target > n.sung ? -bh / 2 : bh / 2));
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
        }
        // How far from its own note it was sung.
        var cents = ((n.sung - n.sung.round()) * 100).round();
        if (cents != 0 && sungX1 - sungX > 26) {
          _label(canvas, "${cents > 0 ? "+" : "−"}${cents.abs()}",
              Offset(sungX1 - 2, hy - bh / 2 - 1), _amber,
              right: true);
        }
      }
      var playing = on != null && on >= n.heardStart && on <= n.heardEnd;
      var lit = picked.contains(i);
      // Square, as Ken asked: a box the note's length and a little over its
      // row, its fill faint so its sound reads through.
      var box = Rect.fromLTRB(x0, y - h / 2, math.max(x0 + 4, x1), y + h / 2);
      canvas.drawRect(
          box,
          Paint()
            ..color = _blobInk.withValues(
                alpha: playing ? 0.34 : (n.edited ? 0.24 : 0.16)));
      // Its sound, as heard: where in the original each moment is from,
      // faded and made louder or softer as it is.
      if (peaks != null && x1 - x0 > 2) {
        var gain = math.pow(10, n.gainDb / 20).toDouble();
        var half = h / 2 - 1.5;
        var wave = Paint()
          ..color = _soundInk.withValues(alpha: playing ? 0.95 : 0.8)
          ..strokeWidth = 1.2;
        for (var x = x0 + 1; x < x1 - 0.5; x += 1.5) {
          var t = x / perSecond;
          var from = n.sourceAt(t);
          if (from == null) continue;
          var amp = math.min(1.0, _peakAt(from) * gain * n.fadeAt(t));
          var a = math.max(0.6, amp * half);
          canvas.drawLine(Offset(x, y - a), Offset(x, y + a), wave);
        }
      }
      // Its fades: the corner cut off, as a clip's.
      var fi = n.fadeIn * perSecond, fo = n.fadeOut * perSecond;
      var shade = Paint()..color = s.display.withValues(alpha: 0.55);
      var ramp = Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1;
      if (fi > 0.5) {
        canvas.drawPath(
            Path()
              ..moveTo(box.left, box.top)
              ..lineTo(box.left + fi, box.top)
              ..lineTo(box.left, box.bottom)
              ..close(),
            shade);
        canvas.drawLine(box.bottomLeft, Offset(box.left + fi, box.top), ramp);
      }
      if (fo > 0.5) {
        canvas.drawPath(
            Path()
              ..moveTo(box.right, box.top)
              ..lineTo(box.right - fo, box.top)
              ..lineTo(box.right, box.bottom)
              ..close(),
            shade);
        canvas.drawLine(box.bottomRight, Offset(box.right - fo, box.top), ramp);
      }
      canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = lit ? 2 : 1
            ..color = lit ? Colors.white : _blobInk.withValues(alpha: 0.9));
      // Picked or pointed at: its handles -- the fades' squares on its top
      // edge, and its edges' grips to stretch it by.
      if (lit || hover == i) {
        var handle = Paint()..color = Colors.white;
        var rim = Paint()
          ..style = PaintingStyle.stroke
          ..color = _blobInk;
        for (var at in [box.left + fi, box.right - fo]) {
          var r =
              Rect.fromCenter(center: Offset(at, box.top), width: 7, height: 7);
          canvas.drawRect(r, handle);
          canvas.drawRect(r, rim);
        }
        var grip = Paint()..color = Colors.white.withValues(alpha: 0.85);
        var gh = math.max(4.0, h * 0.45);
        canvas.drawRect(Rect.fromLTWH(box.left + 2, y - gh / 2, 2, gh), grip);
        canvas.drawRect(Rect.fromLTWH(box.right - 4, y - gh / 2, 2, gh), grip);
      }
      // Stretched: by how much, in its corner.
      if ((n.stretch - 1).abs() > 0.01 && x1 - x0 > 44) {
        _label(canvas, "×${n.stretch.toStringAsFixed(2)}",
            Offset(box.right - 4, box.bottom - 1), Colors.white,
            right: true);
      }
      // Its lyric under it, as the prototype's: the word it starts in.
      if (words.isNotEmpty && x1 - x0 > 12) {
        var said = words
            .where((w) => w.start <= n.start + 0.05 && w.end > n.start)
            .firstOrNull;
        if (said != null) {
          var tp = TextPainter(
              text: TextSpan(
                  text: said.text,
                  style: TextStyle(fontSize: 10, color: s.text)),
              maxLines: 1,
              ellipsis: "…",
              textDirection: TextDirection.ltr)
            ..layout(maxWidth: math.max(12, x1 - x0));
          tp.paint(canvas, Offset(x0 + 1, y + h / 2 + 1));
        }
      }
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
