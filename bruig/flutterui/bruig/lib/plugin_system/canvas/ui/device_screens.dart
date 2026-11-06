import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/modulation.dart'
    show lfoValue, macroKnobs;
import 'package:flutter/material.dart';

// device_screens.dart is what each device draws on its screen in the Chain:
// a reverb its decay, a delay its echoes, a gate its threshold over the
// sound, a filter its curve, a modulation its wave, a drive its curve, and
// so on -- each from the device's own settings, moving with the sound while
// it plays. Drawn the same way for every kind: a dark screen, a faint grid,
// the picture in the device's colour, and a reading along its foot.

/// ScreenMoment is what a screen is drawn at: [t] seconds of playing (to
/// move an LFO along), [level] how loud it is going in, nought to one, and
/// [change] what the device does to the level, in decibels, or null when
/// nothing is playing through it.
class ScreenMoment {
  final double t;
  final double level;
  final double? change;
  final bool live;
  const ScreenMoment(
      {this.t = 0, this.level = 0, this.change, this.live = false});
}

/// hasScreen is whether [kind] draws a picture of its own, rather than its
/// levels in and out.
bool hasScreen(DeviceKind kind) => !listensOnly(kind);

/// DeviceScreenPainter draws [device]'s screen at [moment].
class DeviceScreenPainter extends CustomPainter {
  final MixDevice device;
  final ScreenMoment moment;
  final Color accent;
  final Color back;
  DeviceScreenPainter(this.device, this.moment, this.accent, this.back);

  double v(String id) => device.value(id);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var grid = Paint()..color = Color.lerp(back, Colors.white, 0.06)!;
    for (var i = 1; i < 8; i++) {
      canvas.drawRect(
          Rect.fromLTWH((i * w / 8).roundToDouble(), 0, 1, h), grid);
    }
    for (var i = 1; i < 4; i++) {
      canvas.drawRect(
          Rect.fromLTWH(0, (i * h / 4).roundToDouble(), w, 1), grid);
    }
    var t = moment.t, live = moment.live ? 1.0 : 0.0;
    String? say;
    switch (device.kind) {
      case DeviceKind.reverb:
        var size2 = v("size"), pre = v("predelay") / 400;
        var decay = 0.15 + size2 * 0.6;
        double at(double x) =>
            h -
            4 -
            (h - 10) * 0.9 * math.exp(-x / decay) * (x < pre ? 0.05 : 1);
        _fill(canvas, w, h, at, accent);
        _line(canvas, w, at, accent, 1.8);
        say = "decay ${(0.4 + size2 * 3.6).toStringAsFixed(1)} s";
      case DeviceKind.delay:
        var time = v("time"), fb = v("feedback"), pp = v("pingpong") > 0.5;
        for (var i = 0; i < 12; i++) {
          var x = 8 + i * time / 2000 * (w - 16) * 1.6;
          if (x > w - 4) break;
          var bar = (h - 20) * math.pow(fb, i).toDouble();
          var side = pp && i.isOdd;
          canvas.drawRect(
              Rect.fromLTWH(x, side ? 6 : h - 6 - bar, 4, bar),
              Paint()
                ..color = i == 0
                    ? const Color(0xFF7FC8F8)
                    : side
                        ? Color.lerp(accent, Colors.white, 0.3)!
                        : accent);
        }
        say = "${time.round()} ms · ${(fb * 100).round()}% back";
      case DeviceKind.gate:
        var th = v("threshold");
        var ty = h / 2 - (th + 80) / 80 * h / 2;
        canvas.drawRect(Rect.fromLTRB(0, ty, w, h - ty),
            Paint()..color = const Color(0x22E0564F));
        _line(
            canvas,
            w,
            (x) =>
                h / 2 +
                math.sin(x * 80 + t * 6) *
                    h *
                    0.36 *
                    (0.3 + 0.7 * math.sin(x * 5 + t).abs()) *
                    (0.2 + 0.8 * math.max(live, moment.level)),
            const Color(0xFF4F8FD6),
            1.1);
        var dash = Paint()
          ..color = const Color(0xFFE0564F)
          ..strokeWidth = 1;
        for (var x = 0.0; x < w; x += 7) {
          canvas.drawLine(Offset(x, ty), Offset(x + 4, ty), dash);
          canvas.drawLine(Offset(x, h - ty), Offset(x + 4, h - ty), dash);
        }
        say = "shut below ${th.round()} dB";
      case DeviceKind.autoFilter:
        var type = v("type").round(), res = v("res"), amount = v("amount");
        var f0 = v("freq") *
            math.pow(
                2, amount * 2 * math.sin(t * v("rate") * 2 * math.pi) * live);
        var xc = math.log(f0.clamp(20, 20000) / 20) / math.log(1000);
        double at(double x) {
          var d = x - xc;
          var lp = d < 0 ? 0.0 : d * h * 2.2, hp = d > 0 ? 0.0 : -d * h * 2.2;
          var base = type == 0
              ? lp
              : type == 1
                  ? hp
                  : lp + hp;
          return (h * 0.38 + base - res * h * 0.3 * math.exp(-d * d * 400))
              .clamp(2.0, h);
        }

        _fill(canvas, w, h, at, accent);
        _line(canvas, w, at, accent, 2);
        say = "${_hz(f0.toDouble())}${amount > 0 ? " · moving" : ""}";
      case DeviceKind.chorus || DeviceKind.flanger || DeviceKind.phaser:
        var rate = v("rate"), depth = v("depth");
        double at(double x) =>
            h / 2 - math.sin(x * math.pi * 4) * h * 0.38 * depth;
        _fill(canvas, w, h, at, accent, alpha: 0.12);
        _line(canvas, w, at, accent, 2);
        var u = (t * rate / 2) % 1;
        _dot(canvas, Offset(u * w, at(u)), 4, const Color(0xFFE2B04A));
        say = "${rate.toStringAsFixed(2)} Hz";
      case DeviceKind.autoPan:
        var p = math.sin(t * v("rate") * 2 * math.pi) * v("amount") * live;
        var line = Paint()..color = const Color(0xFF3E3958);
        canvas.drawLine(Offset(20, h / 2), Offset(w - 20, h / 2), line);
        _text(canvas, "L", 6, h / 2 - 6, const Color(0xFF8E8A9C));
        _text(canvas, "R", w - 12, h / 2 - 6, const Color(0xFF8E8A9C));
        _dot(canvas, Offset(w / 2 + p * (w / 2 - 24), h / 2), 6, accent);
      case DeviceKind.saturator || DeviceKind.overdrive:
        var drive = v("drive");
        var amt = device.kind == DeviceKind.saturator ? drive / 12 : drive * 3;
        var diag = Paint()..color = const Color(0xFF3E3958);
        canvas.drawLine(Offset(0, h), Offset(w, 0), diag);
        double tanh(double x) {
          var e = math.exp(2 * x);
          return (e - 1) / (e + 1);
        }

        _line(
            canvas,
            w,
            (x) =>
                h / 2 -
                tanh((x * 2 - 1) * (1 + amt)) / tanh(1 + amt) * h * 0.42,
            accent,
            2.2);
        say = "in → out";
      case DeviceKind.bitCrusher:
        var bits = v("bits"), steps = math.pow(2, math.min(6, bits)).toDouble();
        _line(
            canvas,
            w,
            (x) =>
                h / 2 -
                (math.sin(x * math.pi * 4 + t * 3) * steps).round() /
                    steps *
                    h *
                    0.38,
            accent,
            1.6);
        say = "${bits.round()} bits";
      case DeviceKind.autoTune:
        _line(
            canvas,
            w,
            (x) =>
                h / 2 -
                math.sin(x * 9 + t * 2) * h * 0.2 -
                math.sin(x * 27) * 5,
            const Color(0x99C45C8A),
            1.3);
        _line(
            canvas,
            w,
            (x) =>
                h / 2 - ((math.sin(x * 9 + t * 2) * h * 0.2) / 9).round() * 9,
            accent,
            2);
        say = "sung · corrected";
      case DeviceKind.vocoder:
        var n = v("bands").round();
        for (var i = 0; i < n; i++) {
          var bar = (h - 10) *
              (0.2 + 0.7 * math.sin(i * 0.7 + t * (1 + i % 3)).abs()) *
              (0.25 + 0.75 * math.max(live, moment.level));
          canvas.drawRect(
              Rect.fromLTWH(4 + i * (w - 8) / n, h - 4 - bar,
                  math.max(1, (w - 8) / n - 2), bar),
              Paint()..color = accent);
        }
        say = "$n bands";
      case DeviceKind.lfo:
        // Two of its cycles, and where it is now on them.
        var shape = v("shape").round(), rate = v("rate"), phase = v("phase");
        var wave = Path();
        for (var i = 0; i <= 160; i++) {
          var x = w * i / 160;
          var y = h / 2 - lfoValue(shape, 2 * i / 160 + phase) * (h / 2 - 6);
          i == 0 ? wave.moveTo(x, y) : wave.lineTo(x, y);
        }
        canvas.drawPath(
            wave,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = accent);
        var now = rate * t;
        var at = (now % 2) / 2;
        canvas.drawCircle(
            Offset(
                w * at, h / 2 - lfoValue(shape, 2 * at + phase) * (h / 2 - 6)),
            3.5,
            Paint()..color = live > 0 ? Colors.white : accent);
        say = rate < 10
            ? "${rate.toStringAsFixed(2)} Hz"
            : "${rate.toStringAsFixed(1)} Hz";
      case DeviceKind.split:
        // The sound dividing into its branches and joining again.
        var mode = v("mode").round();
        var names = splitBranchNames(mode, device.branches.length);
        var line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent;
        var rows = names.isEmpty ? 1 : names.length;
        for (var (i, name) in (names.isEmpty ? ["Through"] : names).indexed) {
          var y = h * (i + 1) / (rows + 1);
          var path = Path()
            ..moveTo(6, h / 2)
            ..quadraticBezierTo(w * 0.2, y, w * 0.3, y)
            ..lineTo(w * 0.7, y)
            ..quadraticBezierTo(w * 0.8, y, w - 6, h / 2);
          canvas.drawPath(path, line);
          var tp = TextPainter(
              text: TextSpan(
                  text: name, style: TextStyle(fontSize: 9.5, color: accent)),
              textDirection: TextDirection.ltr)
            ..layout();
          tp.paint(canvas, Offset(w / 2 - tp.width / 2, y - tp.height - 1));
        }
      case DeviceKind.macro:
        // Its four knobs as bars, as far as each is turned.
        var bar = (w - 10) / macroKnobs;
        for (var i = 0; i < macroKnobs; i++) {
          var x = 5 + i * bar;
          var full = Rect.fromLTWH(x + 3, 8, bar - 6, h - 16);
          canvas.drawRRect(
              RRect.fromRectAndRadius(full, const Radius.circular(3)),
              Paint()..color = accent.withValues(alpha: 0.15));
          var up = v("m${i + 1}");
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTRB(full.left, full.bottom - full.height * up,
                      full.right, full.bottom),
                  const Radius.circular(3)),
              Paint()..color = accent);
        }
      case DeviceKind.follower:
        // A sound coming and going, and the follower rising to it and
        // falling after: its attack and release, to the scale of a second.
        var rise = v("attack") / 1000, fall = v("release") / 1000;
        var path = Path()..moveTo(0, h - 6);
        var env = 0.0;
        for (var i = 0; i <= 200; i++) {
          var sec = i / 200;
          var on = sec > 0.15 && sec < 0.45 ? 1.0 : 0.0;
          var step = 1 / 200;
          var k = on > env
              ? 1 - math.exp(-step / math.max(0.001, rise))
              : 1 - math.exp(-step / math.max(0.001, fall));
          env += (on - env) * k;
          path.lineTo(w * sec, h - 6 - env * (h - 14));
        }
        canvas.drawRect(Rect.fromLTRB(w * 0.15, 8, w * 0.45, h - 6),
            Paint()..color = accent.withValues(alpha: 0.12));
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..color = accent);
        say = "×${v("gain").toStringAsFixed(1)}";
      case DeviceKind.utility:
        var width = v("width");
        var c = Offset(w / 2, h - 6);
        var ring = Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF3E3958);
        canvas.drawLine(c, Offset(w / 2, 6), ring);
        canvas.drawLine(c, Offset(w / 2 - (h - 12), 6), ring);
        canvas.drawLine(c, Offset(w / 2 + (h - 12), 6), ring);
        var rnd = math.Random(7);
        var dots = Paint()..color = accent.withValues(alpha: 0.6);
        for (var i = 0; i < 140; i++) {
          var a = rnd.nextDouble() * math.pi,
              r = rnd.nextDouble() *
                  (h - 14) *
                  math.max(0.2, live) *
                  width /
                  1.4;
          canvas.drawRect(
              Rect.fromLTWH(w / 2 + math.cos(a) * r * 0.6,
                  h - 6 - math.sin(a) * r, 1.6, 1.6),
              dots);
        }
        say = "width ${(width * 100).round()}%";
      case DeviceKind.tuner ||
            DeviceKind.spectrum ||
            DeviceKind.scope ||
            DeviceKind.stereoImage ||
            DeviceKind.loudness:
        break;
    }
    // Its reading, and what it does to the level while something plays.
    var change = moment.change;
    if (say != null) {
      _text(canvas, say, 6, h - 15, const Color(0xFF8E8A9C));
    }
    if (change != null) {
      var text =
          "${change >= 0 ? "+" : "−"}${change.abs().toStringAsFixed(1)} dB";
      _text(
          canvas,
          text,
          w - 8 - text.length * 5.6,
          5,
          change > 0.05
              ? const Color(0xFFE2B04A)
              : change < -0.05
                  ? const Color(0xFF7FC8F8)
                  : const Color(0xFFE8E4EE));
    }
  }

  static String _hz(double hz) => hz >= 1000
      ? "${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)} kHz"
      : "${hz.round()} Hz";

  void _line(Canvas canvas, double w, double Function(double) y, Color colour,
      double width) {
    var p = Path();
    for (var x = 0.0; x <= w; x += 2) {
      var yy = y(x / w);
      x == 0 ? p.moveTo(x, yy) : p.lineTo(x, yy);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round
          ..color = colour);
  }

  void _fill(Canvas canvas, double w, double h, double Function(double) y,
      Color colour,
      {double alpha = 0.22}) {
    var p = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 2) {
      p.lineTo(x, y(x / w));
    }
    p
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
        p,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colour.withValues(alpha: alpha),
                colour.withValues(alpha: 0)
              ]).createShader(Rect.fromLTWH(0, 0, w, h)));
  }

  void _dot(Canvas canvas, Offset at, double r, Color colour) =>
      canvas.drawCircle(at, r, Paint()..color = colour);

  void _text(Canvas canvas, String text, double x, double y, Color colour) {
    var tp = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                fontSize: 10,
                color: colour,
                fontFeatures: const [FontFeature.tabularFigures()])),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(DeviceScreenPainter old) =>
      old.device != device ||
      old.moment.t != moment.t ||
      old.moment.change != moment.change ||
      old.accent != accent ||
      old.back != back;
}
