import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show noteNames;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show dragPointers;
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// pitch_editor.dart is the Pitch editor: a channel's recording as notes,
// each a blob at the pitch it is sung at, over the pitch as sung (grey)
// and as it will be heard (coloured) -- moved up and down a semitone at a
// time (or freely, with Alt), split, glued, straightened onto its note,
// its own wobble kept or smoothed, made louder or softer.

/// PitchTool is what a press on a note does.
enum PitchTool { move, split, glue }

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
  int? _picked;

  /// _perSecond and _perTone are the grid's measures: a semitone at least
  /// 14 high, taller to fill the room there is.
  static const double _perSecond = 120, _keysW = 40;
  double _perTone = 14;

  /// The drag of a note: where it started, and its target then.
  double? _dragFrom;
  double _targetFrom = 0;

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
    var hint = TextStyle(fontSize: 12, color: look.studio.muted);
    var source = c.pitchSourceOf(key);
    if (source == null) {
      return Center(
          child: Text("No recording on this channel to tune", style: hint));
    }
    var track = c.pitchTrackOf(key);
    var edit = c.pitchEditOf(key);
    if (edit == null) {
      return Center(
        child: track == null
            ? Text("Reading its pitch…", style: hint)
            : FilledButton(
                key: const ValueKey("pitchFind"),
                onPressed: () => c.findPitchNotes(key),
                child: const Text("Find its notes")),
      );
    }
    var notes = edit.notes;
    if (_picked != null && _picked! >= notes.length) _picked = null;
    // The rows: from below the lowest note to above the highest.
    var low = notes.isEmpty
        ? 48.0
        : notes.map((n) => math.min(n.sung, n.target)).reduce(math.min) - 4;
    var high = notes.isEmpty
        ? 72.0
        : notes.map((n) => math.max(n.sung, n.target)).reduce(math.max) + 4;
    var top = high.ceilToDouble(), bottom = low.floorToDouble();
    var length = track == null ? 0.0 : track.length * 0.02;
    var width = math.max(400.0, length * _perSecond + 40);
    double yOf(double midi) => (top - midi) * _perTone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _toolbar(look, edit),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              _perTone = math.max(14.0, (box.maxHeight - 2) / (top - bottom));
              var height = (top - bottom) * _perTone;
              return SingleChildScrollView(
                child: SizedBox(
                  height: height,
                  child: Row(children: [
                    SizedBox(
                      width: _keysW,
                      child: CustomPaint(
                          painter:
                              _KeysPainter(top, bottom, _perTone, look.studio)),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: GestureDetector(
                          supportedDevices: dragPointers,
                          key: const ValueKey("pitchGrid"),
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onTapUp: (d) => _tap(d.localPosition, edit, yOf),
                          onVerticalDragStart: (d) =>
                              _dragStart(d.localPosition, edit, yOf),
                          onVerticalDragUpdate: (d) =>
                              _dragUpdate(d.localPosition),
                          onVerticalDragEnd: (_) => _dragEnd(),
                          child: CustomPaint(
                            size: Size(width, height),
                            painter: _PitchPainter(
                              notes: notes,
                              track: track ?? const [],
                              top: top,
                              bottom: bottom,
                              perSecond: _perSecond,
                              perTone: _perTone,
                              picked: _picked,
                              studio: look.studio,
                              accent: look.colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }),
          ),
          if (_picked case var i?) _inspector(look, edit, i),
        ]),
      ),
    ]);
  }

  /// _noteAt is the note under [p], at its blob, or null.
  int? _noteAt(Offset p, PitchEdit edit, double Function(double) yOf) {
    var t = p.dx / _perSecond;
    for (var (i, n) in edit.notes.indexed) {
      if (t < n.start || t > n.end) continue;
      if ((p.dy - yOf(n.target)).abs() <= _perTone) return i;
    }
    return null;
  }

  void _tap(Offset p, PitchEdit edit, double Function(double) yOf) {
    var i = _noteAt(p, edit, yOf);
    switch (_tool) {
      case PitchTool.split:
        if (i != null) {
          c.editPitch(key, (e) => e.split(i, p.dx / _perSecond));
        }
      case PitchTool.glue:
        if (i != null) c.editPitch(key, (e) => e.glue(i));
      case PitchTool.move:
        setState(() => _picked = i);
    }
  }

  void _dragStart(Offset p, PitchEdit edit, double Function(double) yOf) {
    if (_tool != PitchTool.move) return;
    var i = _noteAt(p, edit, yOf);
    setState(() => _picked = i);
    if (i == null) return;
    _dragFrom = p.dy;
    _targetFrom = edit.notes[i].target;
    c.beginInteraction();
  }

  void _dragUpdate(Offset p) {
    var i = _picked, from = _dragFrom;
    if (i == null || from == null) return;
    var want = _targetFrom - (p.dy - from) / _perTone;
    // A semitone at a time, unless Alt is held.
    if (!HardwareKeyboard.instance.isAltPressed) want = want.roundToDouble();
    c.editPitch(key, (e) {
      var n = e.notes[i];
      var centred = n.sung + (n.sung.roundToDouble() - n.sung) * n.straighten;
      return e.copyWith(
          notes: [...e.notes]..[i] = n.copyWith(shift: want - centred));
    }, transient: true);
  }

  void _dragEnd() {
    if (_dragFrom == null) return;
    _dragFrom = null;
    c.endInteraction();
  }

  Widget _toolbar(MixerLook look, PitchEdit edit) {
    Widget pill(String label, bool on, VoidCallback onTap, Key key) => Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ChoiceChip(
            key: key,
            label: Text(label, style: const TextStyle(fontSize: 11.5)),
            selected: on,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => onTap(),
          ),
        );
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (var (t, label, k) in [
            (PitchTool.move, "Move", "pitchMove"),
            (PitchTool.split, "Split", "pitchSplit"),
            (PitchTool.glue, "Glue", "pitchGlue"),
          ])
            pill(label, _tool == t, () => setState(() => _tool = t),
                ValueKey(k)),
          const SizedBox(width: 10),
          TextButton(
            key: const ValueKey("pitchStraightenAll"),
            onPressed: () => c.editPitch(
                key,
                (e) => e.copyWith(
                    notes: [for (var n in e.notes) n.copyWith(straighten: 1)])),
            child: const Text("Straighten all"),
          ),
          TextButton(
            key: const ValueKey("pitchReset"),
            onPressed: () {
              setState(() => _picked = null);
              c.forgetPitch(key);
            },
            child: const Text("As recorded"),
          ),
          const SizedBox(width: 10),
          Text(
              edit.stale
                  ? "Making it…"
                  : "${edit.notes.length} notes, "
                      "${edit.notes.where((n) => n.edited).length} changed",
              key: const ValueKey("pitchStatus"),
              style: TextStyle(fontSize: 11.5, color: look.studio.muted)),
        ]),
      ),
    );
  }

  Widget _inspector(MixerLook look, PitchEdit edit, int i) {
    var n = edit.notes[i];
    var style = TextStyle(fontSize: 11.5, color: look.studio.text);
    Widget slider(String label, String key, double value, double min,
            double max, String reading, PitchNote Function(double) apply) =>
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("$label  $reading", style: style),
          Slider(
            key: ValueKey(key),
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChangeStart: (_) => c.beginInteraction(),
            onChanged: (v) => c.editPitch(this.key,
                (e) => e.copyWith(notes: [...e.notes]..[i] = apply(v)),
                transient: true),
            onChangeEnd: (_) => c.endInteraction(),
          ),
        ]);
    var sung = n.sung.round();
    return Container(
      key: const ValueKey("pitchInspector"),
      width: 220,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: look.studio.edge))),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "Sung ${noteNames[sung % 12]}${sung ~/ 12 - 1}"
              " ${_cents(n.sung - sung)}",
              style: style.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          slider(
              "Shift",
              "pitchShift",
              n.shift,
              -12,
              12,
              "${n.shift >= 0 ? "+" : ""}${n.shift.toStringAsFixed(1)} st",
              (v) => n.copyWith(shift: (v * 10).roundToDouble() / 10)),
          slider(
              "Straighten",
              "pitchStraighten",
              n.straighten,
              0,
              1,
              "${(n.straighten * 100).round()}%",
              (v) => n.copyWith(straighten: v)),
          slider("Wobble kept", "pitchWobble", n.wobble, 0, 2,
              "${(n.wobble * 100).round()}%", (v) => n.copyWith(wobble: v)),
          slider(
              "Gain",
              "pitchGain",
              n.gainDb,
              -24,
              12,
              "${n.gainDb.toStringAsFixed(1)} dB",
              (v) => n.copyWith(gainDb: (v * 2).roundToDouble() / 2)),
        ]),
      ),
    );
  }

  static String _cents(double semitones) {
    var c = (semitones * 100).round();
    return c == 0 ? "" : "${c > 0 ? "+" : "−"}${c.abs()}¢";
  }
}

class _KeysPainter extends CustomPainter {
  final double top, bottom, perTone;
  final StudioColors studio;
  _KeysPainter(this.top, this.bottom, this.perTone, this.studio);

  @override
  void paint(Canvas canvas, Size size) {
    for (var k = top.toInt(); k > bottom; k--) {
      var y = (top - k) * perTone;
      if (k % 12 != 0) continue;
      var tp = TextPainter(
          text: TextSpan(
              text: "C${k ~/ 12 - 1}",
              style: TextStyle(fontSize: 10, color: studio.muted)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(4, y + perTone / 2 - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_KeysPainter old) =>
      old.top != top || old.bottom != bottom;
}

class _PitchPainter extends CustomPainter {
  final List<PitchNote> notes;
  final List<double?> track;
  final double top, bottom, perSecond, perTone;
  final int? picked;
  final StudioColors studio;
  final Color accent;
  _PitchPainter(
      {required this.notes,
      required this.track,
      required this.top,
      required this.bottom,
      required this.perSecond,
      required this.perTone,
      required this.picked,
      required this.studio,
      required this.accent});

  double _y(double midi) => (top - midi) * perTone + perTone / 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    // A row a semitone; C picked out.
    for (var k = top.toInt(); k > bottom; k--) {
      var y = (top - k) * perTone;
      canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = k % 12 == 0
                ? studio.edge
                : studio.edge.withValues(alpha: 0.35));
    }
    // The pitch as sung, grey.
    var sung = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = studio.muted.withValues(alpha: 0.7);
    _curve(canvas, sung, (i, p) => p);
    // As it will be heard, in each note: its target, its wobble kept.
    var heard = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = accent;
    _curve(canvas, heard, (i, p) {
      var t = i * 0.02;
      var n = notes.where((n) => t >= n.start && t <= n.end).firstOrNull;
      return n == null ? null : n.target + (p - n.sung) * n.wobble;
    });
    // The notes, at their targets.
    for (var (i, n) in notes.indexed) {
      var r = RRect.fromRectAndRadius(
          Rect.fromLTWH(n.start * perSecond, _y(n.target) - perTone * 0.42,
              math.max(4, n.length * perSecond), perTone * 0.84),
          Radius.circular(perTone * 0.42));
      canvas.drawRRect(
          r, Paint()..color = accent.withValues(alpha: n.edited ? 0.38 : 0.22));
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = i == picked ? 2 : 1
            ..color =
                i == picked ? studio.text : accent.withValues(alpha: 0.8));
    }
  }

  void _curve(
      Canvas canvas, Paint paint, double? Function(int i, double p) at) {
    Path? path;
    for (var (i, p) in track.indexed) {
      var v = p == null ? null : at(i, p);
      if (v == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      var o = Offset(i * 0.02 * perSecond, _y(v));
      if (path == null) {
        path = Path()..moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PitchPainter old) => true;
}
