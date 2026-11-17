import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/mix/device_scope.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;
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

  /// hz is the pitch heard there now, for a device that tunes, or null.
  final double? hz;
  const ScreenMoment(
      {this.t = 0, this.level = 0, this.change, this.live = false, this.hz});
}

/// hasScreen is whether [kind] draws a picture of its own, rather than its
/// levels in and out.
bool hasScreen(DeviceKind kind) => !listensOnly(kind);

/// _noteName writes [text] centred at [at], small, bright where [lit].
void _noteName(Canvas canvas, String text, Offset at, bool lit) {
  var tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: 8,
            color: lit ? const Color(0xFFE6E2F0) : const Color(0xFF6E6A80))),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
}

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
        // Its window: a level scale from silence to full, what is under
        // the threshold shut (down to its floor), what is over it let
        // through. No sound is drawn here: Analyse shows the real one.
        var th = v("threshold"), floor = v("floor");
        double yOf(double db) => 6 + (-db / 80).clamp(0.0, 1.0) * (h - 24);
        var ty = yOf(th);
        canvas.drawRect(Rect.fromLTRB(0, 6, w, ty),
            Paint()..color = const Color(0x225BC46B));
        canvas.drawRect(Rect.fromLTRB(0, ty, w, h - 18),
            Paint()..color = const Color(0x22E0564F));
        for (var db in [0, -20, -40, -60]) {
          _text(canvas, "$db", 4, yOf(db.toDouble()) - 6,
              const Color(0xFF6E6A80));
        }
        var dash = Paint()
          ..color = const Color(0xFFE0564F)
          ..strokeWidth = 1.2;
        for (var x = 26.0; x < w; x += 7) {
          canvas.drawLine(Offset(x, ty), Offset(x + 4, ty), dash);
        }
        // Its floor: how far down it shuts.
        var fy = yOf(floor);
        canvas.drawLine(Offset(26, fy), Offset(w - 6, fy),
            Paint()..color = accent.withValues(alpha: 0.5));
        _text(canvas, "open", w - 34, ty - 15, const Color(0xFF5BC46B));
        _text(canvas, "shut", w - 30, ty + 3, const Color(0xFFE0564F));
        say = "opens above ${th.round()} dB";
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
        // The octave's notes, the key's scale lit; and, sung, the pitch
        // heard and the note it is pulled onto.
        var root = v("key").round();
        var scale = v("scale").round();
        var steps = scale == 0
            ? const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
            : scaleSteps[(scale - 1).clamp(0, scaleSteps.length - 1)];
        var cell = w / 12, top = h * 0.18, bottom = h * 0.78;
        for (var n = 0; n < 12; n++) {
          var inScale = steps.contains((n - root) % 12);
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(n * cell + 1.5, top, cell - 3, bottom - top),
                  const Radius.circular(3)),
              Paint()
                ..color = inScale
                    ? accent.withValues(alpha: n == root ? 0.5 : 0.22)
                    : Colors.white.withValues(alpha: 0.04));
          _noteName(
              canvas,
              const [
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
              ][n],
              Offset(n * cell + cell / 2, bottom + 3),
              inScale);
        }
        var hz = moment.hz;
        if (hz != null && hz > 20) {
          var midi = 69 + 12 * math.log(hz / 440) / math.ln2;
          var to = midi.round();
          // Its nearest in the scale: the note it goes to.
          for (var d = 0; d < 12; d++) {
            if (steps.contains((midi.round() - d - root) % 12)) {
              to = midi.round() - d;
              break;
            }
            if (steps.contains((midi.round() + d - root) % 12)) {
              to = midi.round() + d;
              break;
            }
          }
          double xOf(double m) => ((m % 12) + 0.5) * cell;
          canvas.drawRect(
              Rect.fromLTWH(xOf(midi) - 1, top - 4, 2, bottom - top + 8),
              Paint()..color = const Color(0xFFC45C8A));
          canvas.drawCircle(
              Offset(xOf(to.toDouble()), top + (bottom - top) / 2),
              5,
              Paint()..color = accent);
          var cents = ((midi - to) * 100).round();
          say = "${const [
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
          ][to % 12]}${to ~/ 12 - 1}"
              " · ${cents >= 0 ? "+" : "−"}${cents.abs()}¢ heard";
        } else {
          say = "${device.kind.param("key").reading(v("key"))} "
              "${device.kind.param("scale").reading(v("scale")).toLowerCase()}";
        }
      case DeviceKind.vocoder:
        // Its bands where they sit, from its Low to its High on a scale of
        // pitch (20 Hz to 20 kHz), each a hump as wide as it hears; the
        // carrier's moved up or down by its formant beside.
        var n = v("bands").round(), low = v("low"), high = v("high");
        var shift = math.pow(2, v("formant") / 12).toDouble();
        double xOf(double hz) =>
            8 + (math.log(hz.clamp(20, 20000) / 20) / math.log(1000)) * (w - 16);
        var ratio = math.pow(high / low, 1 / math.max(1, n - 1)).toDouble();
        var base = h - 18, top = 10.0;
        for (var i = 0; i < n; i++) {
          var hz = low * math.pow(ratio, i);
          var x = xOf(hz.toDouble());
          var half = math.max(1.5, (xOf(hz * math.sqrt(ratio)) - x));
          var hump = Path()
            ..moveTo(x - half, base)
            ..quadraticBezierTo(x, top - (base - top) * 0.35, x + half, base);
          canvas.drawPath(
              hump,
              Paint()
                ..color = accent.withValues(alpha: 0.16 + 0.5 * i / n));
          if (shift != 1) {
            var cx = xOf(hz * shift);
            canvas.drawLine(
                Offset(cx, base - 3),
                Offset(cx, base - (base - top) * 0.55),
                Paint()
                  ..color = const Color(0xFF7FC8F8).withValues(alpha: 0.7)
                  ..strokeWidth = 1);
          }
        }
        canvas.drawLine(Offset(0, base), Offset(w, base),
            Paint()..color = const Color(0xFF3E3958));
        var carrier = device.kind.param("carrier").reading(v("carrier"));
        say = "$n bands · carried by ${carrier.toLowerCase()}";
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
        // Its knobs as bars, as far as each is turned.
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

/// analysedAsWave is whether [kind]'s display, on, draws the sound's wave
/// before and after it (a drive's or a crusher's change is in its shape),
/// rather than its level over the last few seconds.
bool analysedAsWave(DeviceKind kind) =>
    kind == DeviceKind.saturator ||
    kind == DeviceKind.overdrive ||
    kind == DeviceKind.bitCrusher;

/// DeviceAnalysisPainter draws what [device] is doing to the real sound
/// (Ken, 2026-11-08): [scope] as the engine kept it -- see device_scope.dart
/// -- or nothing yet. A gate its level against its threshold and whether
/// it is open; a vocoder its bands as loud as each is; a drive or crusher
/// the wave going in and coming out; everything else its level going in
/// and coming out over the last three seconds, so a reverb's tail and a
/// delay's echoes show after the sound.
class DeviceAnalysisPainter extends CustomPainter {
  final MixDevice device;
  final ScopeReading? scope;
  final Color accent;
  final Color back;

  /// stamp changes with each reading, so a new one is drawn.
  final int stamp;
  DeviceAnalysisPainter(this.device, this.scope, this.accent, this.back,
      {this.stamp = 0});

  static const _before = Color(0xFFD8D4E4);
  static const _muted = Color(0xFF8E8A9C);

  /// _floorDb is the quietest drawn: the centre line.
  static const double _floorDb = -60;

  static double _db(double gain) =>
      gain <= 1e-6 ? -120 : 20 * math.log(gain) / math.ln10;

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var grid = Paint()..color = Color.lerp(back, Colors.white, 0.06)!;
    for (var i = 1; i < 8; i++) {
      canvas.drawRect(
          Rect.fromLTWH((i * w / 8).roundToDouble(), 0, 1, h), grid);
    }
    canvas.drawRect(Rect.fromLTWH(0, (h / 2).roundToDouble(), w, 1), grid);
    var s = scope;
    if (s == null) {
      _text(canvas, "Listening…", 6, h - 15, _muted);
      return;
    }
    switch (device.kind) {
      case DeviceKind.vocoder:
        _bands(canvas, size, s);
      case _ when analysedAsWave(device.kind):
        _wave(canvas, size, s);
      default:
        _levels(canvas, size, s);
    }
  }

  /// _y is how far from the centre a level of [gain] reaches, on a decibel
  /// scale: [_floorDb] at the centre, nought at the edge.
  double _reach(double gain, double half) =>
      ((_db(gain) - _floorDb) / -_floorDb).clamp(0.0, 1.0) * half;

  void _levels(Canvas canvas, Size size, ScopeReading s) {
    var w = size.width, h = size.height, mid = h / 2, half = h / 2 - 3;
    var n = s.inPeaks.length;
    Path band(Float32List peaks) {
      var p = Path()..moveTo(0, mid);
      for (var i = 0; i < n; i++) {
        p.lineTo(w * i / (n - 1), mid - _reach(peaks[i], half));
      }
      for (var i = n - 1; i >= 0; i--) {
        p.lineTo(w * i / (n - 1), mid + _reach(peaks[i], half));
      }
      return p..close();
    }

    // Coming out, filled in the device's colour; going in, an outline over
    // it -- what it cut is inside the line, what it added outside.
    canvas.drawPath(
        band(s.outPeaks), Paint()..color = accent.withValues(alpha: 0.7));
    canvas.drawPath(
        band(s.inPeaks),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _before.withValues(alpha: 0.75));
    if (device.kind == DeviceKind.gate) {
      // Its threshold, either side: what is quieter shuts it.
      var th = device.value("threshold");
      var y = _reach(math.pow(10, th / 20).toDouble(), half);
      var dash = Paint()
        ..color = const Color(0xFFE0564F)
        ..strokeWidth = 1;
      for (var x = 0.0; x < w; x += 7) {
        canvas.drawLine(Offset(x, mid - y), Offset(x + 4, mid - y), dash);
        canvas.drawLine(Offset(x, mid + y), Offset(x + 4, mid + y), dash);
      }
      var open = (s.own?.isNotEmpty ?? false) ? s.own![0] : 0.0;
      var lit = open > 0.5;
      canvas.drawCircle(
          Offset(w - 10, 10),
          4,
          Paint()
            ..color = lit ? const Color(0xFF5BC46B) : const Color(0xFF4A2F3A));
      _text(canvas, lit ? "open" : "shut", w - 44, 4, lit ? const Color(0xFF5BC46B) : _muted);
    }
    // The change it makes, over the last half second.
    var last = math.max(1, n ~/ 6);
    var inPeak = 0.0, outPeak = 0.0;
    for (var i = n - last; i < n; i++) {
      inPeak = math.max(inPeak, s.inPeaks[i]);
      outPeak = math.max(outPeak, s.outPeaks[i]);
    }
    _legend(canvas, size,
        inPeak > 1e-4 ? _db(outPeak) - _db(inPeak) : null);
  }

  void _wave(Canvas canvas, Size size, ScopeReading s) {
    var w = size.width, h = size.height, mid = h / 2;
    // Steady: drawn from where the sound going in last rose through
    // nought, ten milliseconds of it at 48 kHz.
    const span = 480;
    var wave = s.inWave, out = s.outWave;
    var start = math.max(0, wave.length - span - 1);
    for (var i = wave.length - span - 1; i > wave.length ~/ 3; i--) {
      if (wave[i - 1] < 0 && wave[i] >= 0) {
        start = i;
        break;
      }
    }
    var peak = 1e-3;
    for (var i = start; i < start + span && i < wave.length; i++) {
      peak = math.max(peak, math.max(wave[i].abs(), out[i].abs()));
    }
    var scale = (h / 2 - 6) / peak;
    Path line(Float32List x) {
      var p = Path();
      for (var i = 0; i < span && start + i < x.length; i++) {
        var px = w * i / (span - 1), py = mid - x[start + i] * scale;
        i == 0 ? p.moveTo(px, py) : p.lineTo(px, py);
      }
      return p;
    }

    canvas.drawPath(
        line(wave),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _before.withValues(alpha: 0.5));
    canvas.drawPath(
        line(out),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..color = accent);
    var n = s.inPeaks.length, last = math.max(1, n ~/ 6);
    var inPeak = 0.0, outPeak = 0.0;
    for (var i = n - last; i < n; i++) {
      inPeak = math.max(inPeak, s.inPeaks[i]);
      outPeak = math.max(outPeak, s.outPeaks[i]);
    }
    _legend(canvas, size,
        inPeak > 1e-4 ? _db(outPeak) - _db(inPeak) : null);
  }

  void _bands(Canvas canvas, Size size, ScopeReading s) {
    var w = size.width, h = size.height;
    var own = s.own;
    if (own == null || own.length < 2) {
      _levels(canvas, size, s);
      return;
    }
    var n = own.length ~/ 2;
    var bw = (w - 8) / n;
    double up(double gain) =>
        ((_db(gain * 4) - _floorDb) / -_floorDb).clamp(0.0, 1.0) * (h - 22);
    for (var i = 0; i < n; i++) {
      var x = 4 + i * bw;
      var voice = up(own[i]);
      var carrier = up(own[n + i]);
      // The voice in that band, as loud as it is: what the carrier is
      // shaped to; the carrier's own level a tick over it.
      canvas.drawRect(
          Rect.fromLTWH(x + 1, h - 16 - voice, math.max(1, bw - 2), voice),
          Paint()
            ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [accent, accent.withValues(alpha: 0.25)])
                .createShader(Rect.fromLTWH(x, h - 16 - voice, bw, voice + 1)));
      canvas.drawRect(Rect.fromLTWH(x + 1, h - 17 - carrier, math.max(1, bw - 2), 1.5),
          Paint()..color = _before.withValues(alpha: 0.8));
    }
    _text(canvas, device.kind.param("low").reading(device.value("low")),
        4, h - 14, _muted);
    var hi = device.kind.param("high").reading(device.value("high"));
    _text(canvas, hi, w - 6 - hi.length * 5.6, h - 14, _muted);
  }

  /// _legend names the two, and says what it changes the level by.
  void _legend(Canvas canvas, Size size, double? change) {
    var h = size.height;
    canvas.drawRect(Rect.fromLTWH(6, h - 11, 8, 3), Paint()..color = _before);
    _text(canvas, "in", 17, h - 15, _muted);
    canvas.drawRect(Rect.fromLTWH(32, h - 11, 8, 3), Paint()..color = accent);
    _text(canvas, "out", 43, h - 15, _muted);
    if (change != null) {
      var text =
          "${change >= 0 ? "+" : "−"}${change.abs().toStringAsFixed(1)} dB";
      _text(
          canvas,
          text,
          size.width - 8 - text.length * 5.6,
          h - 15,
          change > 0.05
              ? const Color(0xFFE2B04A)
              : change < -0.05
                  ? _before
                  : const Color(0xFFE8E4EE));
    }
  }

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
  bool shouldRepaint(DeviceAnalysisPainter old) =>
      old.stamp != stamp ||
      old.scope != scope ||
      old.device != device ||
      old.accent != accent ||
      old.back != back;
}
