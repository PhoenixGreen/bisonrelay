import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:flutter/painting.dart';

// metronome_painter.dart draws a Metronome element as a clockwork one: a
// wooden pyramid, a cream face with its scale, the pendulum (its weight
// lower the faster it goes), a lamp that flashes the beat, and on its base
// the tempo and its buttons. Laid out 200 by 320 (metronomeLayout), fitted
// to its box; the stage's presses read the same layout.

const _metronomeSize = Size(200, 320);

/// MetronomePart is one of the buttons on a metronome's base.
enum MetronomePart { slower, faster, play, tap, beats }

/// MetronomeLayout is where everything on a metronome is, in its units.
class MetronomeLayout {
  /// body is its case and face the dial behind the arm; the arm swings
  /// [arm] long from [pivot]; [lamp] is where the beat flashes; [base] and
  /// its [readout] and [buttons] are the foot with the tempo on it.
  final Path body, face;
  final Offset pivot, lamp;
  final double arm;
  final Rect base, readout;
  final Map<MetronomePart, Rect> buttons;
  const MetronomeLayout(this.body, this.face, this.pivot, this.lamp, this.arm,
      this.base, this.readout, this.buttons);
}

final MetronomeLayout metronomeLayout = () {
  var body = Path()
    ..moveTo(72, 8)
    ..lineTo(128, 8)
    ..lineTo(186, 236)
    ..lineTo(14, 236)
    ..close();
  var face = Path()
    ..moveTo(82, 34)
    ..lineTo(118, 34)
    ..lineTo(164, 222)
    ..lineTo(36, 222)
    ..close();
  var base = const Rect.fromLTWH(4, 236, 192, 80);
  return MetronomeLayout(body, face, const Offset(100, 208),
      const Offset(100, 22), 176, base, const Rect.fromLTWH(58, 244, 84, 34), {
    MetronomePart.slower: const Rect.fromLTWH(14, 244, 40, 34),
    MetronomePart.faster: const Rect.fromLTWH(146, 244, 40, 34),
    MetronomePart.play: const Rect.fromLTWH(14, 282, 56, 28),
    MetronomePart.tap: const Rect.fromLTWH(74, 282, 52, 28),
    MetronomePart.beats: const Rect.fromLTWH(130, 282, 56, 28),
  });
}();

/// metronomeFit is how a metronome sits in [box]: its scale and top left.
(double, Offset) metronomeFit(Rect box) {
  var s = math.min(
      box.width / _metronomeSize.width, box.height / _metronomeSize.height);
  return (
    s,
    box.center -
        Offset(_metronomeSize.width * s / 2, _metronomeSize.height * s / 2)
  );
}

/// metronomePartAt is the button of [e] under [point], or null, with [e]
/// drawn in [box] when that is not its resting place.
MetronomePart? metronomePartAt(MetronomeElement e, Offset point, {Rect? box}) {
  var (s, at) = metronomeFit(box ?? e.bounds);
  var q = (point - at) / s;
  for (var MapEntry(:key, :value) in metronomeLayout.buttons.entries) {
    if (value.inflate(2).contains(q)) return key;
  }
  return null;
}

/// MetronomeShow is how a metronome is going: whether it is, and how many
/// beats it has gone (a fraction between).
class MetronomeShow {
  final bool going;
  final double beats;
  const MetronomeShow({this.going = false, this.beats = 0});
}

/// metronomeAngle is the pendulum's angle [beats] beats in, in radians: at
/// one side on each beat, the other on the next.
double metronomeAngle(double beats) => -0.42 * math.cos(math.pi * beats);

/// paintMetronome draws [e] fitted to [box], going as [show] says: its
/// body, its pendulum, its lamp and its base, in that order, each in the
/// layout's units.
void paintMetronome(ui.Canvas canvas, Rect box, MetronomeElement e,
    {MetronomeShow show = const MetronomeShow()}) {
  var (s, at) = metronomeFit(box);
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.scale(s);
  // The wood's shade, for its edges and its base.
  var dark = Color.lerp(e.body, const Color(0xFF000000), 0.35)!;
  _paintBody(canvas, e, dark);
  _paintPendulum(canvas, e, show);
  _paintLamp(canvas, e, show);
  _paintBase(canvas, e, show, dark);
  canvas.restore();
}

/// _paintBody is the wooden pyramid, its shadow and a grain of light
/// across it, and the cream face with its scale.
void _paintBody(ui.Canvas canvas, MetronomeElement e, Color dark) {
  var l = metronomeLayout;
  var wood = e.body;
  var light = Color.lerp(wood, const Color(0xFFFFFFFF), 0.18)!;
  canvas.drawPath(
      l.body.shift(const Offset(0, 5)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  canvas.drawPath(
      l.body,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(14, 0), const Offset(186, 0),
            [dark, light, wood, dark], const [0, 0.35, 0.65, 1]));
  canvas.drawPath(
      l.body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = dark);
  canvas.drawPath(l.face, Paint()..color = const Color(0xFFF1E7D2));
  canvas.drawPath(
      l.face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000));
  var tick = Paint()
    ..strokeWidth = 1
    ..color = const Color(0xAA3A2A1A);
  for (var i = 0; i <= 14; i++) {
    var y = 48 + i * 11.0;
    var half = i % 2 == 0 ? 9.0 : 5.0;
    canvas.drawLine(Offset(100 - half, y), Offset(100 + half, y), tick);
  }
}

/// _paintPendulum is its arm, swung as far as [show] has it, and the
/// weight, nearer the pivot the faster it goes.
void _paintPendulum(ui.Canvas canvas, MetronomeElement e, MetronomeShow show) {
  var l = metronomeLayout;
  var angle = show.going ? metronomeAngle(show.beats) : 0.0;
  var dir = Offset(math.sin(angle), -math.cos(angle));
  var tip = l.pivot + dir * l.arm;
  canvas.drawLine(
      l.pivot,
      tip,
      Paint()
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF8D9096));
  canvas.drawLine(
      l.pivot,
      tip,
      Paint()
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE3E5E8));
  var fast = (e.bpm - metronomeSlowest) / (metronomeFastest - metronomeSlowest);
  var weightAt = l.pivot + dir * (150 - 100 * fast.clamp(0.0, 1.0));
  canvas.save();
  canvas.translate(weightAt.dx, weightAt.dy);
  canvas.rotate(angle);
  var weight = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 26, height: 18),
      const Radius.circular(3));
  canvas.drawRRect(
      weight,
      Paint()
        ..shader = ui.Gradient.linear(
            const Offset(-13, 0),
            const Offset(13, 0),
            const [Color(0xFF8C8F94), Color(0xFFEDEEF0), Color(0xFF7D8085)],
            const [0, 0.45, 1]));
  canvas.drawRRect(
      weight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF55585E));
  canvas.restore();
  canvas.drawCircle(l.pivot, 4.5, Paint()..color = const Color(0xFF55585E));
}

/// _paintLamp is the lamp: flashing on each beat, brightest on the bar's
/// first.
void _paintLamp(ui.Canvas canvas, MetronomeElement e, MetronomeShow show) {
  var l = metronomeLayout;
  var since = show.beats - show.beats.floorToDouble();
  var downbeat = e.beats > 1 && show.beats.floor() % e.beats == 0;
  var glow = show.going ? math.max(0.0, 1 - since * 3) : 0.0;
  var lampColour =
      downbeat ? e.accent : Color.lerp(e.accent, const Color(0xFFFFE6B0), 0.5)!;
  if (glow > 0) {
    canvas.drawCircle(
        l.lamp,
        11,
        Paint()
          ..color = lampColour.withValues(alpha: 0.6 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }
  canvas.drawCircle(
      l.lamp,
      5.5,
      Paint()
        ..color = Color.lerp(
            Color.lerp(lampColour, const Color(0xFF000000), 0.55)!,
            lampColour,
            glow)!);
}

/// _paintBase is the base: the tempo's readout and its word, and the
/// buttons, play lit while it goes.
void _paintBase(
    ui.Canvas canvas, MetronomeElement e, MetronomeShow show, Color dark) {
  var l = metronomeLayout;
  var baseRR = RRect.fromRectAndRadius(l.base, const Radius.circular(8));
  canvas.drawRRect(baseRR, Paint()..color = dark);
  canvas.drawRRect(
      baseRR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x66000000));
  canvas.drawRRect(RRect.fromRectAndRadius(l.readout, const Radius.circular(5)),
      Paint()..color = const Color(0xFF14110E));
  _text(canvas, "${e.bpm.round()}", l.readout.center - const Offset(0, 5), 17,
      show.going ? e.accent : const Color(0xFFF1E7D2),
      weight: FontWeight.w800, mono: true);
  _text(canvas, tempoWord(e.bpm).toUpperCase(),
      l.readout.center + const Offset(0, 10), 7.5, const Color(0xAAF1E7D2),
      weight: FontWeight.w700);
  for (var MapEntry(key: p, value: r) in l.buttons.entries) {
    _paintButton(canvas, e, p, r, on: p == MetronomePart.play && show.going);
  }
}

/// _paintButton is button [p] of [e], in [r], lit where [on].
void _paintButton(ui.Canvas canvas, MetronomeElement e, MetronomePart p, Rect r,
    {required bool on}) {
  var rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
  canvas.drawRRect(
      rr, Paint()..color = on ? e.accent : const Color(0xFFF1E7D2));
  canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x55000000));
  var ink = on ? const Color(0xFFFFFFFF) : const Color(0xFF2A1F16);
  switch (p) {
    case MetronomePart.slower:
      _text(canvas, "−", r.center, 18, ink, weight: FontWeight.w800);
    case MetronomePart.faster:
      _text(canvas, "+", r.center, 18, ink, weight: FontWeight.w800);
    case MetronomePart.play:
      if (on) {
        canvas.drawRect(
            Rect.fromCenter(center: r.center, width: 10, height: 10),
            Paint()..color = ink);
      } else {
        canvas.drawPath(
            Path()
              ..moveTo(r.center.dx - 5, r.center.dy - 6)
              ..lineTo(r.center.dx + 7, r.center.dy)
              ..lineTo(r.center.dx - 5, r.center.dy + 6)
              ..close(),
            Paint()..color = ink);
      }
    case MetronomePart.tap:
      _text(canvas, "TAP", r.center, 10, ink, weight: FontWeight.w800);
    case MetronomePart.beats:
      _text(canvas, e.beats == 1 ? "1 BEAT" : "${e.beats}/4", r.center, 10, ink,
          weight: FontWeight.w800);
  }
}

void _text(ui.Canvas canvas, String t, Offset c, double size, Color colour,
    {FontWeight weight = FontWeight.w600, bool mono = false}) {
  var tp = labelPainter(t,
      size: size,
      colour: colour,
      family: mono ? "RobotoMono" : "Inter",
      weight: weight,
      height: 1.1);
  tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
}
