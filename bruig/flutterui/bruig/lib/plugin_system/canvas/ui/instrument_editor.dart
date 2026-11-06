import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart' show DeviceGroup;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart'
    show CanvasDropdown;
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

// instrument_editor.dart is the Instrument editor, in the Chain: how a MIDI
// channel's instrument plays its sound (instrument_shape.dart) -- its volume
// envelope (the sound's own, or set here, its dots dragged), a filter with
// an envelope of its own (its curve dragged), an LFO, and its voices: one at
// a time or many, gliding, the bend wheel's range, tuning and the velocity
// curve -- each a card of knobs over a picture of what it does. And the
// instrument's card in the chain, between its MIDI effects and its sound's.

/// The cards' colours: each its device family's (see deviceGroupLook).
Color get _envelopeAccent => deviceGroupLook(DeviceGroup.dynamics).$2;
Color get _filterAccent => deviceGroupLook(DeviceGroup.filter).$2;
Color get _voicesAccent => deviceGroupLook(DeviceGroup.modulation).$2;

/// seconds is [s] as a reading: milliseconds under one.
String seconds(double s) => s < 1
    ? "${(s * 1000).round()} ms"
    : "${s.toStringAsFixed(s < 10 ? 2 : 1)} s";

/// hertz is [hz] as a reading.
String hertz(double hz) => hz < 1000
    ? "${hz.toStringAsFixed(hz < 10 ? 2 : 0)} Hz"
    : "${(hz / 1000).toStringAsFixed(1)} kHz";

class InstrumentEditor extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  const InstrumentEditor(
      {required this.controller, required this.channel, super.key});

  @override
  State<InstrumentEditor> createState() => _InstrumentEditorState();
}

class _InstrumentEditorState extends State<InstrumentEditor> {
  CanvasController get c => widget.controller;
  String get channel => widget.channel;

  /// _dragging is the envelope's dot being dragged: 0 its peak, 1 where it
  /// meets the sustain, 2 its release's end.
  int? _dragging;

  void _set(InstrumentShape Function(InstrumentShape) change,
      {bool transient = false}) {
    c.beginInteraction();
    c.setInstrumentShape(channel, change, transient: true);
    if (!transient) c.endInteraction();
  }

  @override
  Widget build(BuildContext context) {
    var part = c.instrumentOf(channel)?.instrument;
    if (part == null) return const SizedBox();
    var shape = part.shape;
    var look = MixerLook.of(context);
    var ink = look.studio.text;
    var muted = TextStyle(fontSize: 11.5, color: look.studio.muted);
    return Column(children: [
      // What it plays, and a way back to the sound as it is.
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: Row(children: [
          Text("Sound", style: muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(part.name,
                key: const ValueKey("instrumentEditorSound"),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: ink)),
          ),
          if (!shape.plain)
            TextButton(
              key: const ValueKey("instrumentPlain"),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: look.colors.primary),
              onPressed: () => _set((_) => const InstrumentShape()),
              child: const Text("As the sound is"),
            ),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, room) {
          const least = 236.0;
          var cards = [
            _envelopeCard(look, shape),
            _filterCard(look, shape),
            _lfoCard(look, shape),
            _voicesCard(look, shape),
          ];
          // Side by side to fill the room; scrolled across where it is
          // too narrow for them.
          if (room.maxWidth >= least * cards.length + 30) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Row(children: [
                for (var card in cards)
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: card)),
              ]),
            );
          }
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
            children: [
              for (var card in cards)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: SizedBox(width: least, child: card)),
            ],
          );
        }),
      ),
    ]);
  }

  /// _card is one of the editor's cards: its title in [accent], a picture,
  /// then its choice and knobs, scrolled where they will not fit.
  Widget _card(MixerLook look,
      {required String id,
      required String title,
      required Color accent,
      required Widget picture,
      required Widget choice,
      required List<Widget> knobs,
      bool dim = false}) {
    return Container(
      key: ValueKey(id),
      decoration: BoxDecoration(
        color: look.studio.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: look.studio.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 2, color: accent),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: look.studio.text)),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, room) {
            var tall = (room.maxHeight * 0.32).clamp(44.0, 96.0);
            return SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(height: tall, child: picture),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: choice,
                    ),
                    Opacity(
                      opacity: dim ? 0.4 : 1,
                      child: IgnorePointer(
                        ignoring: dim,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 8,
                            children: knobs,
                          ),
                        ),
                      ),
                    ),
                  ]),
            );
          }),
        ),
      ]),
    );
  }

  Widget _knob(
          MixerLook look,
          String key,
          String label,
          String text,
          double value,
          double initial,
          double min,
          double max,
          Color accent,
          InstrumentShape Function(InstrumentShape, double) change,
          {bool log = false,
          bool bipolar = false}) =>
      DeviceKnob(
        key: ValueKey(key),
        label: label,
        text: text,
        value: value,
        initial: initial,
        min: min,
        max: max,
        log: log,
        bipolar: bipolar,
        accent: accent,
        ink: look.studio.text,
        onChanged: (v, {transient = false}) =>
            _set((s) => change(s, v), transient: transient),
        onCommit: c.endInteraction,
      );

  Widget _envelopeCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _envelopeAccent;
    return _card(
      look,
      id: "instrumentEnvelopeCard",
      title: "Volume envelope",
      accent: a,
      dim: !s.envelope,
      picture: LayoutBuilder(builder: (context, room) {
        var size = room.biggest;
        var points = envelopePoints(s, size);
        return GestureDetector(
          key: const ValueKey("instrumentEnvelopeGraph"),
          // The dot nearest where it was pressed, not where the drag began.
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          onPanStart: s.envelope
              ? (e) {
                  var best = -1;
                  var near = 18.0;
                  for (var (i, p)
                      in [points.$3, points.$4, points.$6].indexed) {
                    var dist = (p - e.localPosition).distance;
                    if (dist < near) {
                      near = dist;
                      best = i;
                    }
                  }
                  if (best >= 0) setState(() => _dragging = best);
                }
              : null,
          onPanUpdate: (e) {
            var i = _dragging;
            if (i == null) return;
            var (scale, _, _, _, _, _) = points;
            var t = math.max(0.0, (e.localPosition.dx - 6) / scale);
            var level = (1 - (e.localPosition.dy - 6) / (size.height - 12))
                .clamp(0.0, 1.0);
            _set(
                (x) => switch (i) {
                      0 => x.copyWith(attack: t),
                      1 => x.copyWith(decay: t - x.attack, sustain: level),
                      _ => x.copyWith(release: t - x.attack - x.decay - _held),
                    },
                transient: true);
          },
          onPanEnd: (_) {
            if (_dragging == null) return;
            setState(() => _dragging = null);
            c.endInteraction();
          },
          child: CustomPaint(
            painter: EnvelopePainter(s,
                accent: a,
                back: look.studio.inset,
                faint: !s.envelope,
                text: look.studio.muted),
          ),
        );
      }),
      choice: CanvasDropdown<bool>(
        key: const ValueKey("instrumentEnvelope"),
        label: "",
        value: s.envelope,
        tight: true,
        width: 200,
        options: const [
          (false, "The sound's own"),
          (true, "Set here"),
        ],
        onChanged: (v) => _set((x) => x.copyWith(envelope: v)),
      ),
      knobs: [
        _knob(look, "instrumentAttack", "Attack", seconds(s.attack), s.attack,
            d.attack, 0.001, 10, a, (x, v) => x.copyWith(attack: v),
            log: true),
        _knob(look, "instrumentDecay", "Decay", seconds(s.decay), s.decay,
            d.decay, 0.01, 20, a, (x, v) => x.copyWith(decay: v),
            log: true),
        _knob(
            look,
            "instrumentSustain",
            "Sustain",
            "${(s.sustain * 100).round()}%",
            s.sustain,
            d.sustain,
            0,
            1,
            a,
            (x, v) => x.copyWith(sustain: v)),
        _knob(look, "instrumentRelease", "Release", seconds(s.release),
            s.release, d.release, 0.01, 20, a, (x, v) => x.copyWith(release: v),
            log: true),
      ],
    );
  }

  Widget _filterCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _filterAccent;
    var on = s.filter != SynthFilter.off;
    return _card(
      look,
      id: "instrumentFilterCard",
      title: "Filter",
      accent: a,
      dim: !on,
      picture: LayoutBuilder(builder: (context, room) {
        var w = room.maxWidth;
        return GestureDetector(
          key: const ValueKey("instrumentFilterGraph"),
          // The dot nearest where it was pressed, not where the drag began.
          dragStartBehavior: DragStartBehavior.down,
          behavior: HitTestBehavior.opaque,
          // Across for its corner, up and down for its resonance.
          onPanStart: on ? (_) => c.beginInteraction() : null,
          onPanUpdate: on
              ? (e) {
                  var u = (e.localPosition.dx / w).clamp(0.0, 1.0);
                  _set(
                      (x) => x.copyWith(
                          cutoff: 20 * math.pow(1000, u).toDouble(),
                          resonance: x.resonance - e.delta.dy / 120),
                      transient: true);
                }
              : null,
          onPanEnd: on ? (_) => c.endInteraction() : null,
          child: CustomPaint(
            painter: FilterPainter(s,
                accent: a, back: look.studio.inset, text: look.studio.muted),
          ),
        );
      }),
      choice: CanvasDropdown<SynthFilter>(
        key: const ValueKey("instrumentFilter"),
        label: "",
        value: s.filter,
        tight: true,
        width: 200,
        options: [for (var f in SynthFilter.values) (f, f.label)],
        onChanged: (v) => _set((x) => x.copyWith(filter: v)),
      ),
      knobs: [
        _knob(look, "instrumentCutoff", "Cutoff", hertz(s.cutoff), s.cutoff,
            d.cutoff, 20, 20000, a, (x, v) => x.copyWith(cutoff: v),
            log: true),
        _knob(
            look,
            "instrumentResonance",
            "Resonance",
            "${(s.resonance * 100).round()}%",
            s.resonance,
            d.resonance,
            0,
            1,
            a,
            (x, v) => x.copyWith(resonance: v)),
        _knob(
            look,
            "instrumentFilterEnvelope",
            "Envelope",
            "${s.filterEnvelope >= 0 ? "+" : ""}"
                "${(s.filterEnvelope * 4).toStringAsFixed(1)} oct",
            s.filterEnvelope,
            d.filterEnvelope,
            -1,
            1,
            a,
            (x, v) => x.copyWith(filterEnvelope: v),
            bipolar: true),
        _knob(
            look,
            "instrumentFilterDecay",
            "Decay",
            seconds(s.filterDecay),
            s.filterDecay,
            d.filterDecay,
            0.01,
            10,
            a,
            (x, v) => x.copyWith(filterDecay: v),
            log: true),
      ],
    );
  }

  Widget _lfoCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = modulationColour;
    return _card(
      look,
      id: "instrumentLfoCard",
      title: "LFO",
      accent: a,
      picture: CustomPaint(
        painter: LfoPainter(s,
            accent: a, back: look.studio.inset, text: look.studio.muted),
      ),
      choice: CanvasDropdown<LfoTarget>(
        key: const ValueKey("instrumentLfoTarget"),
        label: "Moves",
        value: s.lfoTarget,
        tight: true,
        width: 200,
        options: [for (var t in LfoTarget.values) (t, t.label)],
        onChanged: (v) => _set((x) => x.copyWith(lfoTarget: v)),
      ),
      knobs: [
        _knob(look, "instrumentLfoRate", "Rate", hertz(s.lfoRate), s.lfoRate,
            d.lfoRate, 0.05, 30, a, (x, v) => x.copyWith(lfoRate: v),
            log: true),
        _knob(
            look,
            "instrumentLfoDepth",
            "Depth",
            "${(s.lfoDepth * 100).round()}%",
            s.lfoDepth,
            d.lfoDepth,
            0,
            1,
            a,
            (x, v) => x.copyWith(lfoDepth: v)),
      ],
    );
  }

  Widget _voicesCard(MixerLook look, InstrumentShape s) {
    const d = InstrumentShape();
    var a = _voicesAccent;
    return _card(
      look,
      id: "instrumentVoicesCard",
      title: "Voices",
      accent: a,
      picture: CustomPaint(
        painter: VelocityPainter(s,
            accent: a, back: look.studio.inset, text: look.studio.muted),
      ),
      choice: Tooltip(
        message: s.mode.hint,
        child: CanvasDropdown<VoiceMode>(
          key: const ValueKey("instrumentVoiceMode"),
          label: "",
          value: s.mode,
          tight: true,
          width: 200,
          options: [for (var m in VoiceMode.values) (m, m.label)],
          onChanged: (v) => _set((x) => x.copyWith(mode: v)),
        ),
      ),
      knobs: [
        // A glide is from one note to the next: one voice's.
        Opacity(
          opacity: s.mode == VoiceMode.poly ? 0.4 : 1,
          child: _knob(look, "instrumentGlide", "Glide", seconds(s.glide),
              s.glide, d.glide, 0, 5, a, (x, v) => x.copyWith(glide: v)),
        ),
        if (s.mode == VoiceMode.poly)
          _knob(
              look,
              "instrumentVoices",
              "Voices",
              "${s.voices}",
              s.voices.toDouble(),
              d.voices.toDouble(),
              1,
              64,
              a,
              (x, v) => x.copyWith(voices: v.round())),
        _knob(
            look,
            "instrumentBend",
            "Bend",
            "±${s.bendRange.round()} st",
            s.bendRange,
            d.bendRange,
            0,
            24,
            a,
            (x, v) => x.copyWith(bendRange: v.roundToDouble())),
        _knob(
            look,
            "instrumentTune",
            "Tune",
            "${s.tune >= 0 ? "+" : ""}${s.tune.round()} ct",
            s.tune,
            d.tune,
            -100,
            100,
            a,
            (x, v) => x.copyWith(tune: v.roundToDouble()),
            bipolar: true),
        _knob(
            look,
            "instrumentVelocity",
            "Velocity",
            s.velocityCurve.abs() < 0.01
                ? "As played"
                : s.velocityCurve > 0
                    ? "Harder"
                    : "Lighter",
            s.velocityCurve,
            d.velocityCurve,
            -1,
            1,
            a,
            (x, v) => x.copyWith(velocityCurve: v),
            bipolar: true),
      ],
    );
  }
}

/// _held is how long the envelope's picture shows the key held, in
/// seconds, between its decay and its release.
const double _held = 0.6;

/// envelopePoints is [s]'s envelope drawn in [size]: seconds to pixels, then
/// where it starts, peaks, meets its sustain, is let go and ends.
(double, Offset, Offset, Offset, Offset, Offset) envelopePoints(
    InstrumentShape s, Size size) {
  var span = math.max(2.2, s.attack + s.decay + _held + s.release);
  var scale = (size.width - 12) / span;
  double y(double level) => size.height - 6 - level * (size.height - 12);
  var x0 = 6.0;
  return (
    scale,
    Offset(x0, y(0)),
    Offset(x0 + s.attack * scale, y(1)),
    Offset(x0 + (s.attack + s.decay) * scale, y(s.sustain)),
    Offset(x0 + (s.attack + s.decay + _held) * scale, y(s.sustain)),
    Offset(x0 + (s.attack + s.decay + _held + s.release) * scale, y(0)),
  );
}

/// _screen draws a card's picture's ground: its colour, and a faint grid.
void _screen(Canvas canvas, Size size, Color back) {
  var r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
  canvas.drawRRect(r, Paint()..color = back);
  var grid = Paint()..color = Color.lerp(back, Colors.white, 0.06)!;
  for (var i = 1; i < 6; i++) {
    canvas.drawRect(
        Rect.fromLTWH((i * size.width / 6).roundToDouble(), 0, 1, size.height),
        grid);
  }
  for (var i = 1; i < 3; i++) {
    canvas.drawRect(
        Rect.fromLTWH(0, (i * size.height / 3).roundToDouble(), size.width, 1),
        grid);
  }
}

void _say(Canvas canvas, String text, Offset at, Color color) {
  var p = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: 10, color: color)),
      textDirection: TextDirection.ltr)
    ..layout();
  p.paint(canvas, at);
}

/// _line strokes [path] in [accent], filled faintly beneath down to [floor].
void _line(Canvas canvas, Path path, Color accent, double floor,
    {double alpha = 1}) {
  var b = path.getBounds();
  var fill = Path.from(path)
    ..lineTo(b.right, floor)
    ..lineTo(b.left, floor)
    ..close();
  canvas.drawPath(
      fill, Paint()..color = accent.withValues(alpha: 0.18 * alpha));
  canvas.drawPath(
      path,
      Paint()
        ..color = accent.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round);
}

/// EnvelopePainter draws a volume envelope: up, down to its sustain, held,
/// released -- its three dots to drag, or faint where the sound's own is
/// used.
class EnvelopePainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  final bool faint;

  /// dots is whether its dots are drawn to drag: not on the chain's card.
  final bool dots;
  EnvelopePainter(this.shape,
      {required this.accent,
      required this.back,
      required this.text,
      this.faint = false,
      this.dots = true});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var (_, a, b, c, d, e) = envelopePoints(shape, size);
    var path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..lineTo(e.dx, e.dy);
    _line(canvas, path, accent, size.height - 6, alpha: faint ? 0.3 : 1);
    if (faint) {
      _say(canvas, "As the sound has it", const Offset(8, 4), text);
      return;
    }
    if (!dots) return;
    for (var p in [b, c, e]) {
      canvas.drawCircle(p, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
          p,
          4.5,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(EnvelopePainter old) =>
      old.shape != shape ||
      old.faint != faint ||
      old.dots != dots ||
      old.accent != accent;
}

/// filterGain is [s]'s filter's response at [hz], in decibels: the
/// analogue two-pole it is modelled on.
double filterGain(InstrumentShape s, double hz) {
  if (s.filter == SynthFilter.off) return 0;
  var w = hz / s.cutoff;
  var q = math.sqrt1_2 * math.pow(28, s.resonance);
  var den = math.sqrt(math.pow(1 - w * w, 2) + math.pow(w / q, 2));
  var g = switch (s.filter) {
    SynthFilter.lowPass => 1 / den,
    SynthFilter.highPass => w * w / den,
    SynthFilter.bandPass => (w / q) / den,
    SynthFilter.off => 1.0,
  };
  return 20 * math.log(math.max(g, 1e-6)) / math.ln10;
}

/// FilterPainter draws the filter's curve, 20Hz to 20kHz across, -36dB to
/// +24dB up, with its corner marked.
class FilterPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  FilterPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    double y(double db) =>
        (size.height - 4) -
        (db.clamp(-36.0, 24.0) + 36) / 60 * (size.height - 8);
    var path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      var hz = 20 * math.pow(1000, x / size.width).toDouble();
      var yy = y(filterGain(shape, hz));
      x == 0 ? path.moveTo(x, yy) : path.lineTo(x, yy);
    }
    var on = shape.filter != SynthFilter.off;
    _line(canvas, path, accent, size.height, alpha: on ? 1 : 0.3);
    if (!on) {
      _say(canvas, "Off: the sound as it is", const Offset(8, 4), text);
      return;
    }
    var cx = math.log(shape.cutoff / 20) / math.log(1000) * size.width;
    canvas.drawCircle(Offset(cx, y(filterGain(shape, shape.cutoff))), 4.5,
        Paint()..color = Colors.white);
    _say(canvas, hertz(shape.cutoff), const Offset(8, 4), text);
  }

  @override
  bool shouldRepaint(FilterPainter old) => old.shape != shape;
}

/// LfoPainter draws two of the LFO's cycles, as tall as its depth.
class LfoPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  LfoPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var mid = size.height / 2;
    var depth = math.max(0.06, shape.lfoDepth) * (mid - 6);
    var path = Path();
    for (var x = 0.0; x <= size.width; x += 2) {
      var yy = mid - math.sin(x / size.width * 4 * math.pi) * depth;
      x == 0 ? path.moveTo(x, yy) : path.lineTo(x, yy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = accent.withValues(alpha: shape.lfoDepth > 0 ? 1 : 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    _say(
        canvas,
        shape.lfoDepth > 0
            ? "Moves the ${shape.lfoTarget.label.toLowerCase()}"
            : "No depth: it moves nothing",
        const Offset(8, 4),
        text);
  }

  @override
  bool shouldRepaint(LfoPainter old) => old.shape != shape;
}

/// VelocityPainter draws the velocity curve: how hard a key is struck
/// across, how loud it is heard up, the straight line as played.
class VelocityPainter extends CustomPainter {
  final InstrumentShape shape;
  final Color accent, back, text;
  VelocityPainter(this.shape,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    _screen(canvas, size, back);
    var w = size.width - 8, h = size.height - 8;
    canvas.drawLine(Offset(4, size.height - 4), Offset(size.width - 4, 4),
        Paint()..color = text.withValues(alpha: 0.4));
    var path = Path();
    for (var i = 1; i <= 127; i += 2) {
      var x = 4 + (i / 127) * w;
      var y = size.height - 4 - shape.velocity(i) / 127 * h;
      i == 1 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    _line(canvas, path, accent, size.height - 4);
    _say(
        canvas,
        "${shape.mode.label} · "
        "${shape.mode == VoiceMode.poly ? "${shape.voices} voices" : "glide ${seconds(shape.glide)}"}",
        const Offset(8, 4),
        text);
  }

  @override
  bool shouldRepaint(VelocityPainter old) => old.shape != shape;
}

/// InstrumentDevice is the instrument's card in the chain, after its MIDI
/// effects and before its sound's devices: its envelope, filter and voices
/// at a glance, and the way into its editor.
class InstrumentDevice extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final DeviceSkin skin;

  const InstrumentDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.skin,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var part = controller.instrumentOf(channel)?.instrument;
    if (part == null) return const SizedBox();
    var s = part.shape;
    var look = MixerLook.of(context);
    var muted = TextStyle(fontSize: 11, color: skin.ink.withValues(alpha: 0.7));
    return DeviceFrame(
      id: "instrumentCard",
      title: part.name,
      skin: skin,
      icon: Icons.piano,
      accent: _envelopeAccent,
      folded: folded,
      onFold: onFold,
      width: 210,
      height: height,
      foldedBody: Center(
        child: RotatedBox(
          quarterTurns: 3,
          child:
              Text(part.name, style: TextStyle(fontSize: 11, color: skin.ink)),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: CustomPaint(
              painter: EnvelopePainter(s,
                  accent: _envelopeAccent,
                  back: look.studio.inset,
                  faint: !s.envelope,
                  dots: false,
                  text: look.studio.muted),
            ),
          ),
          const SizedBox(height: 6),
          Text(
              s.filter == SynthFilter.off
                  ? "No filter"
                  : "${s.filter.label} · ${hertz(s.cutoff)}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted),
          Text(
              s.mode == VoiceMode.poly
                  ? "Poly · ${s.voices} voices"
                  : "${s.mode.label} · glide ${seconds(s.glide)}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey("instrumentEdit"),
            style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: skin.ink),
            onPressed: () => controller.showInstrument(channel),
            icon: const Icon(Icons.tune, size: 14),
            label: const Text("Edit"),
          ),
        ]),
      ),
    );
  }
}
