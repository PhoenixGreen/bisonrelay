import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:flutter/painting.dart';

// synth_module_painter.dart draws a synth module (see
// synth_module_element.dart) as the prototype did
// (sheet-music-prototype/index.html, Ken approved 2026-11-14): Analogue, a
// Eurorack-style panel -- printed legends, corner screws, skirted knobs, a
// phosphor screen, a VU meter; Digital, a soft synth's -- dark, arc knobs
// that glow, a big screen in the module's colour. And the cables between
// modules, sagging, coloured by what they carry.
//
// One layout (synthPanelOf) places everything on a panel in its own units,
// 236 across; the painter, the cables and the stage's presses all read it,
// so a jack is pressed where it is drawn.

/// synthPanelWidth is a panel's width in its own units.
const synthPanelWidth = 236.0;

/// SynthPanel is where everything on a kind of module's panel is, in panel
/// units.
class SynthPanel {
  final double height;
  final Rect header;

  /// reset and look are the header's two buttons: ↺ (not on a keyboard or
  /// speaker) and the A/D look switch.
  final Rect? reset;
  final Rect look;
  final Rect? screen;
  final Rect? keys;

  /// options are the choosing setting's buttons, in synthChoices order.
  final List<Rect> options;

  /// knobs are each knob's cell -- dial, name, value -- in synthKnobs
  /// order; dials their dials.
  final List<Rect> knobs;
  final List<Rect> dials;
  final Rect? hint;

  /// ins and outs are each jack's middle, by name.
  final Map<String, Offset> ins, outs;

  const SynthPanel._(
      this.height,
      this.header,
      this.reset,
      this.look,
      this.screen,
      this.keys,
      this.options,
      this.knobs,
      this.dials,
      this.hint,
      this.ins,
      this.outs);

  Size get size => Size(synthPanelWidth, height);
}

/// synthJackRadius is a jack's, in panel units.
const synthJackRadius = 8.0;

double _screenHeight(SynthModuleKind k) => switch (k) {
      SynthModuleKind.osc => 70,
      SynthModuleKind.noise => 48,
      SynthModuleKind.env => 82,
      SynthModuleKind.lfo => 62,
      SynthModuleKind.filter => 82,
      SynthModuleKind.amp => 64,
      SynthModuleKind.out => 76,
      SynthModuleKind.delay || SynthModuleKind.reverb => 56,
      SynthModuleKind.scope => 120,
      SynthModuleKind.keys || SynthModuleKind.mixer => 0,
    };

String? synthHint(SynthModuleKind k) => switch (k) {
      SynthModuleKind.keys => "Gate: held or not. Pitch: which key.",
      SynthModuleKind.amp => "Something in Gain shapes the level.",
      _ => null,
    };

final _panels = <SynthModuleKind, SynthPanel>{};

/// synthPanelOf is [kind]'s panel layout.
SynthPanel synthPanelOf(SynthModuleKind kind) =>
    _panels[kind] ??= _layout(kind);

SynthPanel _layout(SynthModuleKind kind) {
  const w = synthPanelWidth, side = 10.0, gap = 8.0;
  var header = const Rect.fromLTWH(0, 0, w, 38);
  var look = Rect.fromLTWH(w - 14 - 22, 8, 22, 22);
  var reset = kind == SynthModuleKind.keys || kind == SynthModuleKind.out
      ? null
      : Rect.fromLTWH(look.left - 6 - 22, 8, 22, 22);
  var y = header.bottom + gap;
  Rect? screen, keys, hint;
  var sh = _screenHeight(kind);
  if (sh > 0) {
    screen = Rect.fromLTWH(side, y, w - 2 * side, sh);
    y += sh + gap;
  }
  if (kind == SynthModuleKind.keys) {
    keys = Rect.fromLTWH(side, y, w - 2 * side, 64);
    y += 64 + gap;
  }
  var options = <Rect>[];
  if (synthChoiceOf(kind) case var c?) {
    var n = synthChoices[c]!.length;
    var ow = (w - 2 * side - 3 * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      options.add(Rect.fromLTWH(side + i * (ow + 3), y, ow, 32));
    }
    y += 32 + gap;
  }
  var knobs = <Rect>[], dials = <Rect>[];
  var ks = synthKnobs[kind]!;
  if (ks.isNotEmpty) {
    const cw = 54.0, ch = 72.0;
    var x0 = (w - ks.length * cw) / 2;
    for (var i = 0; i < ks.length; i++) {
      var cell = Rect.fromLTWH(x0 + i * cw, y, cw, ch);
      knobs.add(cell);
      dials.add(Rect.fromCenter(
          center: Offset(cell.center.dx, y + 23), width: 46, height: 46));
    }
    y += ch + 4;
  }
  if (synthHint(kind) != null) {
    hint = Rect.fromLTWH(side + 2, y, w - 2 * side - 4, 26);
    y += 26 + 4;
  }
  var rows = math.max(kind.ins.length, kind.outs.length);
  const rowH = 24.0;
  var ins = <String, Offset>{}, outs = <String, Offset>{};
  for (var (i, p) in kind.ins.indexed) {
    ins[p.name] = Offset(side + 14, y + rowH / 2 + i * rowH);
  }
  for (var (i, p) in kind.outs.indexed) {
    outs[p.name] = Offset(w - side - 14, y + rowH / 2 + i * rowH);
  }
  y += rows * rowH + 12;
  return SynthPanel._(y, header, reset, look, screen, keys, options, knobs,
      dials, hint, ins, outs);
}

/// synthPanelFit is how a panel sits in [box]: its scale, and where its
/// top left is. Kept to its shape, in the middle of the box.
(double, Offset) synthPanelFit(Rect box, SynthPanel p) {
  var s = math.min(box.width / p.size.width, box.height / p.size.height);
  var at = box.center - Offset(p.size.width * s / 2, p.size.height * s / 2);
  return (s, at);
}

/// synthToPanel is the panel point under [point] on [e], in document space;
/// null off the panel.
Offset? synthToPanel(SynthModuleElement e, Offset point) {
  var q = synthPanelPoint(e, point);
  return (Offset.zero & synthPanelOf(e.module).size).contains(q) ? q : null;
}

/// synthPanelPoint is [point], in document space, as a point on [e]'s
/// panel -- on it or not: a drag that runs off it.
Offset synthPanelPoint(SynthModuleElement e, Offset point) {
  var p = synthPanelOf(e.module);
  var local = point;
  if (e.rotation != 0) {
    var c = e.bounds.center, a = -e.rotation * math.pi / 180;
    var d = point - c;
    local = c +
        Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
            d.dx * math.sin(a) + d.dy * math.cos(a));
  }
  var (s, at) = synthPanelFit(e.bounds, p);
  return (local - at) / s;
}

/// synthJackAt is jack [port] (an output, with [out]) of [e], in document
/// space.
Offset? synthJackAt(SynthModuleElement e, String port, {required bool out}) {
  var p = synthPanelOf(e.module);
  var j = (out ? p.outs : p.ins)[port];
  if (j == null) return null;
  var (s, at) = synthPanelFit(e.bounds, p);
  var q = at + j * s;
  if (e.rotation == 0) return q;
  var c = e.bounds.center, a = e.rotation * math.pi / 180;
  var d = q - c;
  return c +
      Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
          d.dx * math.sin(a) + d.dy * math.cos(a));
}

/// SynthShow is what a module is doing, for its screen and keys: the time
/// (an LFO's lamp beats by it), the keys held, where its envelope is, what
/// is coming out of it.
class SynthShow {
  final double seconds;
  final Set<int> held;

  /// level is how loud it is now, nought to one (an amp's or speaker's
  /// meter); env where its envelope is, nought to one, or null with no key.
  final double level;
  final double? env;

  /// wave is a stretch of what is coming out of it, for a live scope.
  final Float32List? wave;
  const SynthShow(
      {this.seconds = 0,
      this.held = const {},
      this.level = 0,
      this.env,
      this.wave});
}

/// synthShowOf is what each module is doing on the stage, set by the
/// controller there (as sheetPlaying is): the keys held, the levels. Null
/// -- in an export -- each is drawn at rest at its frame's time.
SynthShow Function(SynthModuleElement e, int frame)? synthShowOf;

// ------------------------------------------------------------ colours

/// synthSignalColour is a jack's and cable's colour, by what it carries.
Color synthSignalColour(SynthSignal s) => switch (s) {
      SynthSignal.audio => const Color(0xFF2F7FD6),
      SynthSignal.mod => const Color(0xFFC97A12),
      SynthSignal.gate || SynthSignal.pitch => const Color(0xFF1F9D5F),
    };

/// synthAccent is a module's colour on a digital panel.
Color synthAccent(SynthModuleKind k) => switch (k) {
      SynthModuleKind.osc => const Color(0xFF38C6C0),
      SynthModuleKind.filter => const Color(0xFFFF8A3D),
      SynthModuleKind.env => const Color(0xFFA78BFA),
      SynthModuleKind.lfo => const Color(0xFF6EE07A),
      SynthModuleKind.amp => const Color(0xFFFFD34D),
      SynthModuleKind.out => const Color(0xFF5AA9FF),
      SynthModuleKind.keys => const Color(0xFF9AA4B2),
      SynthModuleKind.noise => const Color(0xFFE879A6),
      SynthModuleKind.mixer => const Color(0xFFC0C6D0),
      SynthModuleKind.delay => const Color(0xFF4DD0E1),
      SynthModuleKind.reverb => const Color(0xFFB388FF),
      SynthModuleKind.scope => const Color(0xFF8DFFB0),
    };

/// _panelColours are an analogue panel's face and printing.
(Color, Color) _panelColours(SynthModuleKind k) => switch (k) {
      SynthModuleKind.filter || SynthModuleKind.out => (
          const Color(0xFF1E1E20),
          const Color(0xFFECEBE6)
        ),
      SynthModuleKind.env => (const Color(0xFFECE2C6), const Color(0xFF2B2213)),
      SynthModuleKind.lfo => (const Color(0xFF22414A), const Color(0xFFE8F1EE)),
      SynthModuleKind.keys => (
          const Color(0xFF6B4A2F),
          const Color(0xFFF5EAD8)
        ),
      SynthModuleKind.noise => (
          const Color(0xFF8E2F2A),
          const Color(0xFFF7E9E4)
        ),
      SynthModuleKind.delay => (
          const Color(0xFF2E4A6B),
          const Color(0xFFE6EEF7)
        ),
      SynthModuleKind.reverb => (
          const Color(0xFF4B3A5E),
          const Color(0xFFF0E9F7)
        ),
      SynthModuleKind.scope => (
          const Color(0xFF2A2A2C),
          const Color(0xFFECEBE6)
        ),
      _ => (const Color(0xFFD9D9D5), const Color(0xFF1D1D1B)),
    };

const _phosphor = Color(0xFF8DFFB0);
const _phosphorGlow = Color(0xFF3DFF7A);
const _vuFace = Color(0xFFEFE3BF);

// ------------------------------------------------------------ painting

/// paintSynthModule draws [e] in [box].
void paintSynthModule(ui.Canvas canvas, Rect box, SynthModuleElement e,
    {SynthShow show = const SynthShow()}) {
  var p = synthPanelOf(e.module);
  var (s, at) = synthPanelFit(box, p);
  canvas.save();
  canvas.translate(at.dx, at.dy);
  canvas.scale(s);
  _Panel(canvas, e, p, show).paint();
  canvas.restore();
}

class _Panel {
  final ui.Canvas c;
  final SynthModuleElement e;
  final SynthPanel p;
  final SynthShow show;
  final bool analogue;
  final Color ink, face, accent;

  _Panel(this.c, this.e, this.p, this.show)
      : analogue = e.look == SynthLook.analogue,
        ink = e.look == SynthLook.analogue
            ? _panelColours(e.module).$2
            : const Color(0xFFDFE3EA),
        face = _panelColours(e.module).$1,
        accent = synthAccent(e.module);

  SynthModuleKind get kind => e.module;

  void paint() {
    _body();
    _header();
    if (p.screen case var r?) _screen(r);
    if (p.keys case var r?) _keys(r);
    _options();
    _knobs();
    if (p.hint case var r?) {
      _text(synthHint(kind)!, r.topLeft, 10, ink.withValues(alpha: 0.75),
          maxWidth: r.width);
    }
    _jacks();
    if (e.fixed) {
      // Locked: its controls dimmed, as the prototype's were.
      var top = p.screen?.top ?? p.keys?.top ?? p.header.bottom;
      var bottom = (p.knobs.lastOrNull ?? p.options.lastOrNull)?.bottom ?? top;
      c.drawRect(
          Rect.fromLTRB(4, top - 2, synthPanelWidth - 4, bottom + 2),
          Paint()
            ..color = (analogue ? face : const Color(0xFF14161C))
                .withValues(alpha: 0.4));
    }
  }

  // The panel itself.
  void _body() {
    var r = Offset.zero & p.size;
    var rr = RRect.fromRectAndRadius(r, Radius.circular(analogue ? 4 : 12));
    c.drawRRect(
        rr.shift(const Offset(0, 4)),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    if (analogue) {
      c.drawRRect(rr, Paint()..color = face);
      // Brushed: faint light and dark bands across.
      c.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(r.topLeft, r.topRight, const [
              Color(0x2EFFFFFF),
              Color(0x0A000000),
              Color(0x1FFFFFFF),
              Color(0x0D000000),
            ], const [
              0,
              0.3,
              0.6,
              1
            ]));
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x59000000));
      for (var o in [
        const Offset(10, 10),
        const Offset(synthPanelWidth - 10, 10),
        Offset(10, p.height - 10),
        Offset(synthPanelWidth - 10, p.height - 10),
      ]) {
        _screw(o);
      }
    } else {
      c.drawRRect(
          rr,
          Paint()
            ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter,
                const [Color(0xFF1B1E26), Color(0xFF14161C)]));
      // The header washed in its colour.
      c.save();
      c.clipRRect(rr);
      c.drawRect(
          p.header,
          Paint()
            ..shader = ui.Gradient.linear(
                p.header.topLeft,
                p.header.topRight,
                [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0)],
                const [0, 0.7]));
      c.restore();
      c.drawLine(
          p.header.bottomLeft,
          p.header.bottomRight,
          Paint()
            ..color = const Color(0xFF2A2F3A)
            ..strokeWidth = 1);
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF2C313D));
    }
  }

  void _screw(Offset o) {
    c.drawCircle(
        o,
        4.5,
        Paint()
          ..shader = ui.Gradient.radial(
              o - const Offset(1.5, 1.5),
              5,
              const [Color(0xFFF4F4F2), Color(0xFF9A9A96), Color(0xFF6D6D6A)],
              const [0, 0.6, 1]));
    c.drawCircle(
        o,
        4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0x40000000));
    var d = Offset(math.cos(0.6), math.sin(0.6)) * 3;
    c.drawLine(
        o - d,
        o + d,
        Paint()
          ..color = const Color(0xFF555555)
          ..strokeWidth = 1.2);
  }

  void _header() {
    var h = p.header;
    var x = analogue ? 20.0 : 12.0;
    var name = _text(
        analogue ? kind.label.toUpperCase() : kind.label,
        Offset(x, h.center.dy),
        analogue ? 11.5 : 12.5,
        analogue ? ink : const Color(0xFFFFFFFF),
        weight: FontWeight.w800,
        mono: analogue,
        spacing: analogue ? 1.6 : 0.2,
        middle: true);
    var legend = _text(
        synthPanelName(kind),
        Offset(x + name.width + 7, h.center.dy),
        9.5,
        analogue ? ink.withValues(alpha: 0.6) : accent,
        weight: FontWeight.w800,
        spacing: 0.8,
        middle: true);
    if (e.fixed) {
      _text("LOCKED", Offset(x + name.width + legend.width + 14, h.center.dy),
          8.5, ink.withValues(alpha: 0.7),
          weight: FontWeight.w800, middle: true);
    }
    _button(p.look, analogue ? "A" : "D", false);
    if (p.reset case var r?) _button(r, "↺", e.changed);
  }

  void _button(Rect r, String label, bool lit) {
    var rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    Color fill, edge, text;
    if (analogue) {
      fill = lit ? const Color(0xFFFF4A2E) : const Color(0x14000000);
      edge = lit ? const Color(0xFFB52F1C) : const Color(0x40000000);
      text = lit ? const Color(0xFFFFFFFF) : ink;
    } else {
      fill = const Color(0xFF232733);
      edge = lit ? accent : const Color(0xFF353B48);
      text = lit ? accent : const Color(0xFFC9CED8);
      if (lit) {
        c.drawRRect(
            rr,
            Paint()
              ..color = accent.withValues(alpha: 0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }
    }
    c.drawRRect(rr, Paint()..color = fill);
    c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edge);
    _text(label, r.center, label == "↺" ? 13 : 10, text,
        weight: FontWeight.w800, centre: true);
  }

  // ------------------------------------------------------------ screens

  void _screen(Rect r) {
    if (kind == SynthModuleKind.amp) {
      _meter(r);
      return;
    }
    var rr = RRect.fromRectAndRadius(r, Radius.circular(analogue ? 6 : 8));
    c.save();
    c.clipRRect(rr);
    c.drawRect(
        r,
        Paint()
          ..color =
              analogue ? const Color(0xFF08150C) : const Color(0xFF0B0D12));
    var grid = Paint()
      ..strokeWidth = analogue ? 0.75 : 0.5
      ..color = analogue ? const Color(0x1A78FFA0) : const Color(0x0DFFFFFF);
    var cols = analogue ? 8 : 10;
    for (var i = 1; i < cols; i++) {
      var x = r.left + i * r.width / cols;
      c.drawLine(Offset(x, r.top), Offset(x, r.bottom), grid);
    }
    for (var i = 1; i < 4; i++) {
      var y = r.top + i * r.height / 4;
      c.drawLine(Offset(r.left, y), Offset(r.right, y), grid);
    }
    switch (kind) {
      case SynthModuleKind.osc:
        _oscScreen(r);
      case SynthModuleKind.noise:
        _noiseScreen(r);
      case SynthModuleKind.env:
        _envScreen(r);
      case SynthModuleKind.lfo:
        _lfoScreen(r);
      case SynthModuleKind.filter:
        _filterScreen(r);
      case SynthModuleKind.out:
        _scope(r);
      case SynthModuleKind.scope:
        _bigScope(r);
      case SynthModuleKind.delay:
        _echoScreen(r);
      case SynthModuleKind.reverb:
        _roomScreen(r);
      default:
    }
    c.restore();
    if (analogue) {
      // The bezel, with the glass's shadow inside it.
      c.drawRRect(
          rr.inflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xFF2A2A29));
    } else {
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF2A2F3A));
    }
  }

  /// _trace draws a screen's line: phosphor green on an analogue panel,
  /// the module's colour with a fill under it on a digital one.
  void _trace(List<Offset> pts, {double? base}) {
    if (pts.length < 2) return;
    var path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var q in pts.skip(1)) {
      path.lineTo(q.dx, q.dy);
    }
    if (!analogue && base != null) {
      var fill = Path.from(path)
        ..lineTo(pts.last.dx, base)
        ..lineTo(pts.first.dx, base)
        ..close();
      var top = pts.map((q) => q.dy).reduce(math.min);
      c.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, base), [
              accent.withValues(alpha: 0.53),
              accent.withValues(alpha: 0.02),
            ]));
    }
    var col = analogue ? _phosphor : accent;
    var glow = analogue ? _phosphorGlow : accent;
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = analogue ? 3 : 3.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = glow.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = analogue ? 1.6 : 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = col);
  }

  void _dot(Offset o, {double r = 3.5}) {
    var glow = analogue ? _phosphorGlow : accent;
    c.drawCircle(
        o,
        r * 1.8,
        Paint()
          ..color = glow.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    c.drawCircle(
        o,
        r,
        Paint()
          ..color =
              analogue ? const Color(0xFFD8FFE4) : const Color(0xFFFFFFFF));
  }

  void _label(String t, Offset o, {bool right = false, Color? colour}) {
    var col = colour ?? (analogue ? _phosphor.withValues(alpha: 0.75) : accent);
    var tp = _layout(t, 8.5, col, weight: FontWeight.w700, mono: true);
    tp.paint(c, right ? o - Offset(tp.width, 0) : o);
  }

  static double _waveAt(String shape, double ph) => switch (shape) {
        "triangle" => 1 - 4 * (ph - 0.5).abs(),
        "sawtooth" => 2 * ph - 1,
        "square" => ph < 0.5 ? 1 : -1,
        _ => math.sin(ph * 2 * math.pi),
      };

  void _oscScreen(Rect r) {
    var wave = show.wave;
    if (wave != null && wave.isNotEmpty && _rms(wave) > 0.002) {
      _liveWave(r, wave);
      _label("LIVE", Offset(r.right - 6, r.top + 5), right: true);
    } else {
      var shape = e.choice("wave");
      if (!analogue) {
        // A wavetable's frames, stacked behind.
        for (var k = 4; k >= 1; k--) {
          var pts = <Offset>[];
          var w = r.width * 0.78;
          for (var x = 0.0; x <= w; x += 2) {
            pts.add(Offset(
                r.left + x + k * r.width * 0.055,
                r.center.dy -
                    k * r.height * 0.07 -
                    _waveAt(shape, (x / w) * 2 % 1) * r.height * 0.26));
          }
          c.drawPoints(
              ui.PointMode.polygon,
              pts,
              Paint()
                ..strokeWidth = 1
                ..color = accent.withValues(alpha: 0.12 + 0.04 * (4 - k)));
        }
      }
      var amp = r.height * 0.36 * (0.4 + 0.6 * e.value("level"));
      _trace([
        for (var x = 0.0; x <= r.width; x += 1.5)
          Offset(r.left + x,
              r.center.dy - _waveAt(shape, (x / r.width) * 2 % 1) * amp)
      ], base: r.center.dy);
    }
    var oct = e.value("octave").round();
    _label("${oct > 0 ? "+" : ""}$oct oct", Offset(r.left + 6, r.bottom - 14));
  }

  void _noiseScreen(Rect r) {
    var rnd = math.Random(7 + (show.seconds * 12).floor());
    var amp = r.height * 0.4 * (0.3 + 0.7 * e.value("level"));
    _trace([
      for (var x = 0.0; x <= r.width; x += 2)
        Offset(r.left + x, r.center.dy - (rnd.nextDouble() * 2 - 1) * amp)
    ], base: r.center.dy);
  }

  double _rms(Float32List w) {
    var s = 0.0;
    for (var v in w) {
      s += v * v;
    }
    return math.sqrt(s / w.length);
  }

  /// _liveWave draws [wave] steadied on a rising zero crossing, as a
  /// scope's trigger does.
  void _liveWave(Rect r, Float32List d) {
    var s0 = 0;
    for (var i = 1; i < d.length ~/ 2; i++) {
      if (d[i - 1] < 0 && d[i] >= 0) {
        s0 = i;
        break;
      }
    }
    var n = math.min(d.length - s0, 512);
    var peak = 0.05;
    for (var i = 0; i < n; i++) {
      peak = math.max(peak, d[s0 + i].abs());
    }
    _trace([
      for (var i = 0; i < n; i++)
        Offset(r.left + i / (n - 1) * r.width,
            r.center.dy - d[s0 + i] / peak * r.height * 0.4)
    ], base: r.center.dy);
  }

  void _scope(Rect r) {
    var wave = show.wave;
    if (!analogue && wave != null && wave.isNotEmpty) {
      // A spectrum's worth of bars under the trace: here its level.
      var bars = 40, bw = (r.width - 8) / bars;
      var rnd = math.Random(3);
      for (var i = 0; i < bars; i++) {
        var h = show.level *
            (r.height - 10) *
            (0.35 + 0.65 * rnd.nextDouble()) *
            math.exp(-i / 18);
        c.drawRect(
            Rect.fromLTWH(r.left + 4 + i * bw, r.bottom - 4 - h, bw - 1.5, h),
            Paint()..color = accent.withValues(alpha: 0.6));
      }
    }
    var pts = <Offset>[];
    for (var i = 0; i < 150; i++) {
      var v = wave == null || wave.isEmpty
          ? 0.0
          : wave[(i / 150 * wave.length).floor()];
      pts.add(
          Offset(r.left + i / 149 * r.width, r.center.dy - v * r.height * 0.9));
    }
    _trace(pts);
  }

  /// _bigScope is the Scope module's screen: what passes through it,
  /// steadied on a rising crossing, [zoom] times closer.
  void _bigScope(Rect r) {
    var wave = show.wave;
    if (wave == null || wave.isEmpty || _rms(wave) < 0.0005) {
      _trace([Offset(r.left, r.center.dy), Offset(r.right, r.center.dy)]);
      _label("NO SIGNAL", Offset(r.left + 6, r.top + 5));
      return;
    }
    var zoom = e.value("zoom");
    var n = (wave.length / zoom).round().clamp(16, wave.length);
    var s0 = 0;
    for (var i = 1; i < wave.length - n; i++) {
      if (wave[i - 1] < 0 && wave[i] >= 0) {
        s0 = i;
        break;
      }
    }
    n = math.min(n, wave.length - s0);
    var peak = 0.05;
    for (var i = 0; i < n; i++) {
      peak = math.max(peak, wave[s0 + i].abs());
    }
    _trace([
      for (var i = 0; i < n; i++)
        Offset(r.left + i / (n - 1) * r.width,
            r.center.dy - wave[s0 + i] / peak * r.height * 0.42)
    ], base: r.center.dy);
    _label("${zoom.toStringAsFixed(1)}×", Offset(r.right - 6, r.top + 5),
        right: true);
  }

  /// _echoScreen draws the delay's repeats: a bar for the sound, then one
  /// each [time] after it, each [feedback] the last's height.
  void _echoScreen(Rect r) {
    var time = e.value("time"), fb = e.value("feedback"), mix = e.value("mix");
    var span = 2.0; // seconds across
    var base = r.bottom - 6;
    var h = r.height - 14;
    var dry = Paint()..color = (analogue ? _phosphor : accent);
    var wet = Paint()
      ..color = (analogue ? _phosphor : accent).withValues(alpha: 0.7);
    var bw = 3.0;
    c.drawRect(
        Rect.fromLTWH(r.left + 6, base - h * (1 - mix), bw, h * (1 - mix)),
        dry);
    var level = mix;
    for (var t = time; t < span && level > 0.01; t += time) {
      var x = r.left + 6 + t / span * (r.width - 12);
      c.drawRect(Rect.fromLTWH(x, base - h * level, bw, h * level), wet);
      level *= fb;
    }
    _label(_secsLabel(time), Offset(r.right - 6, r.top + 5), right: true);
  }

  /// _roomScreen draws the reverb's tail: how long it rings, how dark.
  void _roomScreen(Rect r) {
    var size = e.value("size"), damp = e.value("damp"), mix = e.value("mix");
    var long = 0.15 + 0.85 * size;
    var rnd = math.Random(11);
    var pts = <Offset>[];
    for (var x = 0.0; x <= r.width - 12; x += 2) {
      var t = x / (r.width - 12);
      var env = mix * math.exp(-t / (long * 0.45));
      var jag = 1 - damp * 0.7;
      pts.add(Offset(
          r.left + 6 + x,
          r.center.dy -
              (rnd.nextDouble() * 2 - 1) * env * jag * r.height * 0.42 -
              0));
    }
    _trace(pts, base: r.center.dy);
    _label("${(1 + 4 * size).toStringAsFixed(1)} s",
        Offset(r.right - 6, r.top + 5),
        right: true);
  }

  static String _secsLabel(double v) =>
      v < 1 ? "${(v * 1000).round()} ms" : "${v.toStringAsFixed(2)} s";

  void _lfoScreen(Rect r) {
    var shape = e.choice("shape");
    var amp = r.height * 0.38 * (0.25 + 0.75 * e.value("depth"));
    _trace([
      for (var x = 0.0; x <= r.width; x += 1.5)
        Offset(r.left + x,
            r.center.dy - _waveAt(shape, (x / r.width) * 2 % 1) * amp)
    ], base: r.center.dy);
    var ph = (show.seconds * e.value("rate")) % 2;
    var v = _waveAt(shape, ph % 1);
    _dot(Offset(r.left + ph / 2 * r.width, r.center.dy - v * amp));
    // A lamp beating at the rate, as on the hardware.
    var lamp = Offset(r.right - 9, r.top + 9);
    var on = (v + 1) / 2;
    c.drawCircle(
        lamp,
        3.5,
        Paint()
          ..color = analogue
              ? Color.fromRGBO(255, 74, 46, 0.25 + 0.75 * on)
              : accent.withValues(alpha: 0.3 + 0.7 * on));
    _label("${e.value("rate").toStringAsFixed(2)} Hz",
        Offset(r.left + 6, r.top + 5));
  }

  void _envScreen(Rect r) {
    var p = synthEnvPoints(e, r);
    var pad = p.pad;
    double y(double v) => r.bottom - pad - v * (r.height - 2 * pad);
    var s = e.value("s");
    var x0 = p.x0, xa = p.a.dx, xd = p.ds.dx;
    var xs = xd + p.susW, xr = p.r.dx;
    var pts = [
      Offset(x0, y(0)),
      p.a,
      p.ds,
      Offset(xs, y(s)),
      p.r,
    ];
    _trace(pts, base: y(0));
    if (!analogue) {
      for (var q in [pts[1], pts[2], pts[4]]) {
        c.drawCircle(q, 4, Paint()..color = const Color(0xFF0B0D12));
        c.drawCircle(
            q,
            4,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = accent);
      }
    }
    if (show.env case var level?) {
      // Where the envelope is: on its rise, or its fall.
      var held = show.held.isNotEmpty;
      var x = held
          ? (level >= 1 - 1e-3 ? xa : x0 + (xa - x0) * level)
          : xs + (xr - xs) * (1 - level / math.max(1e-3, s));
      _dot(Offset(x.clamp(x0, xr), y(level)));
    }
    var dim = analogue ? null : const Color(0xFF6B7280);
    for (var (i, t) in ["A", "D", "S", "R"].indexed) {
      var mid = [(x0 + xa) / 2, (xa + xd) / 2, (xd + xs) / 2, (xs + xr) / 2][i];
      _label(t, Offset(mid - 2.5, r.bottom - 11), colour: dim);
    }
  }

  /// _filterScreen draws the filter's response: an analogue two-pole's,
  /// from 20 Hz to 20 kHz across, -36 to +24 dB up.
  void _filterScreen(Rect r) {
    const lo = 20.0, hi = 20000.0, dbHi = 24.0, dbLo = -36.0;
    double fx(double f) =>
        r.left + 7 + math.log(f / lo) / math.log(hi / lo) * (r.width - 14);
    double dby(double db) =>
        r.top + 5 + (dbHi - db) / (dbHi - dbLo) * (r.height - 10);
    var cutoff = e.value("cutoff");
    var q = 0.7 + e.value("res").clamp(0.0, 20.0) * 0.97;
    var type = e.choice("type");
    c.drawLine(
        Offset(r.left, dby(0)),
        Offset(r.right, dby(0)),
        Paint()
          ..strokeWidth = 0.5
          ..color =
              analogue ? const Color(0x408DFFB0) : const Color(0x1FFFFFFF));
    var pts = <Offset>[];
    for (var i = 0; i < 120; i++) {
      var f = lo * math.pow(hi / lo, i / 119);
      var w = f / cutoff;
      var den = math.sqrt(math.pow(1 - w * w, 2) + math.pow(w / q, 2));
      var mag = switch (type) {
        "highpass" => w * w / den,
        "bandpass" => (w / q) / den,
        _ => 1 / den,
      };
      var db = (20 * math.log(math.max(1e-6, mag)) / math.ln10)
          .clamp(dbLo - 6, dbHi);
      pts.add(Offset(fx(f.toDouble()), dby(db)));
    }
    _trace(pts, base: r.bottom - 5);
    if (!analogue) {
      _dot(
          Offset(fx(cutoff),
              dby(type == "bandpass" ? 0 : 20 * math.log(q) / math.ln10)),
          r: 4);
    }
    _label(
        cutoff >= 1000
            ? "${(cutoff / 1000).toStringAsFixed(1)} kHz"
            : "${cutoff.round()} Hz",
        Offset(r.right - 6, r.top + 5),
        right: true);
  }

  /// _meter is the amp's: a VU meter's needle on an analogue panel, a
  /// peak meter's segments on a digital one.
  void _meter(Rect r) {
    var db = 20 * math.log(math.max(1e-5, show.level * 2.5)) / math.ln10;
    var frac = ((db + 40) / 43).clamp(0.0, 1.0);
    var rr = RRect.fromRectAndRadius(r, Radius.circular(analogue ? 6 : 8));
    c.save();
    c.clipRRect(rr);
    if (analogue) {
      c.drawRect(r, Paint()..color = _vuFace);
      var cx = r.center.dx, cy = r.top + r.height * 1.55, rad = r.height * 1.32;
      double ang(double f) => (-38 + f * 76) * math.pi / 180 - math.pi / 2;
      var arc = Rect.fromCircle(center: Offset(cx, cy), radius: rad);
      c.drawArc(
          arc,
          ang(0),
          ang(0.78) - ang(0),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFF2B2418));
      c.drawArc(
          arc,
          ang(0.78),
          ang(1) - ang(0.78),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xFFC2311D));
      for (var (n, f) in const [
        (-20, 0.0),
        (-10, 0.3),
        (-5, 0.5),
        (0, 0.78),
        (3, 1.0)
      ]) {
        var t = ang(f);
        var col = n >= 0 ? const Color(0xFFC2311D) : const Color(0xFF2B2418);
        var dir = Offset(math.cos(t), math.sin(t));
        c.drawLine(
            Offset(cx, cy) + dir * rad,
            Offset(cx, cy) + dir * (rad + 4.5),
            Paint()
              ..strokeWidth = 1
              ..color = col);
        _text(n > 0 ? "+$n" : "$n", Offset(cx, cy) + dir * (rad - 10), 7, col,
            weight: FontWeight.w700, mono: true, centre: true);
      }
      _text("VU", Offset(cx, r.bottom - 8), 8.5, const Color(0xFF2B2418),
          weight: FontWeight.w700, mono: true, centre: true);
      var t = ang(frac);
      c.drawLine(
          Offset(cx, cy),
          Offset(cx, cy) + Offset(math.cos(t), math.sin(t)) * (rad + 3),
          Paint()
            ..strokeWidth = 1.2
            ..color = const Color(0xFF111111));
    } else {
      c.drawRect(r, Paint()..color = const Color(0xFF0B0D12));
      const segs = 30;
      var sw = (r.width - 12) / segs;
      for (var i = 0; i < segs; i++) {
        var f = i / segs;
        var col = f > 0.88
            ? const Color(0xFFFF4D4D)
            : f > 0.7
                ? const Color(0xFFFFD34D)
                : const Color(0xFF3FCF86);
        c.drawRect(
            Rect.fromLTWH(r.left + 6 + i * sw, r.top + r.height * 0.32,
                sw - 1.5, r.height * 0.36),
            Paint()..color = col.withValues(alpha: f < frac ? 1 : 0.13));
      }
      _label(show.level <= 0 ? "-inf dB" : "${db.toStringAsFixed(1)} dB",
          Offset(r.right - 6, r.bottom - 13),
          right: true);
    }
    c.restore();
    c.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = analogue ? 2.5 : 1
          ..color =
              analogue ? const Color(0xFF3A3530) : const Color(0xFF2A2F3A));
  }

  // ------------------------------------------------------------ keys

  /// _keys is the keyboard module's octave, middle C to C: the keys held lit.
  void _keys(Rect r) {
    var whites = synthKeyboardWhites;
    var ww = r.width / whites.length;
    var lit =
        analogue ? const Color(0xFFD6F3E4) : accent.withValues(alpha: 0.6);
    for (var (i, k) in whites.indexed) {
      var key = Rect.fromLTWH(r.left + i * ww, r.top, ww, r.height);
      var rr = RRect.fromRectAndCorners(key.deflate(0.5),
          bottomLeft: const Radius.circular(3),
          bottomRight: const Radius.circular(3));
      c.drawRRect(
          rr,
          Paint()
            ..color = show.held.contains(k)
                ? lit
                : analogue
                    ? const Color(0xFFFFFFFF)
                    : const Color(0xFFE6E8EC));
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFFC9C5BB));
    }
    for (var (k, rect) in synthBlackKeys(r)) {
      c.drawRRect(
          RRect.fromRectAndCorners(rect,
              bottomLeft: const Radius.circular(2),
              bottomRight: const Radius.circular(2)),
          Paint()
            ..color = show.held.contains(k)
                ? const Color(0xFF1F9D5F)
                : analogue
                    ? const Color(0xFF2A2926)
                    : const Color(0xFF0B0D12));
    }
  }

  // ------------------------------------------------------------ choices

  void _options() {
    var name = synthChoiceOf(kind);
    if (name == null) return;
    var opts = synthChoices[name]!;
    var on = e.choice(name);
    if (!analogue && p.options.isNotEmpty) {
      var strip = p.options.first.expandToInclude(p.options.last).inflate(2);
      var rr = RRect.fromRectAndRadius(strip, const Radius.circular(8));
      c.drawRRect(rr, Paint()..color = const Color(0xFF0F1116));
      c.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF2A2F3A));
    }
    for (var (i, r) in p.options.indexed) {
      var v = opts[i], picked = v == on;
      var rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      Color text;
      if (analogue) {
        c.drawRRect(rr, Paint()..color = const Color(0x0F000000));
        c.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0x2E000000));
        var led = Offset(r.left + 7, r.top + 7);
        if (picked) {
          c.drawCircle(
              led,
              5,
              Paint()
                ..color = const Color(0xAAFF4A2E)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        }
        c.drawCircle(
            led,
            2.6,
            Paint()
              ..color =
                  picked ? const Color(0xFFFF4A2E) : const Color(0xFF5B1D14));
        text = ink;
      } else {
        if (picked) {
          c.drawRRect(
              rr,
              Paint()
                ..color = Color.alphaBlend(
                    accent.withValues(alpha: 0.22), const Color(0xFF1B1E26)));
        }
        text = picked ? accent : const Color(0xFF8B93A3);
      }
      _shapeIcon(
          v,
          Rect.fromCenter(
              center: Offset(r.center.dx, r.top + 11), width: 24, height: 10),
          text);
      _text(synthChoiceNames[v] ?? v, Offset(r.center.dx, r.bottom - 8), 8.5,
          text,
          weight: FontWeight.w800, spacing: 0.5, centre: true);
    }
  }

  void _shapeIcon(String v, Rect r, Color col) {
    var path = Path();
    for (var i = 0; i <= 40; i++) {
      var x = i / 40;
      double y;
      if (v == "lowpass" || v == "highpass" || v == "bandpass") {
        var f = v == "lowpass"
            ? (x < .55 ? .25 : .25 + (x - .55) * 1.7) -
                ((x - .55).abs() < .08 ? .18 : 0)
            : v == "highpass"
                ? (x > .45 ? .25 : .25 + (.45 - x) * 1.7) -
                    ((x - .45).abs() < .08 ? .18 : 0)
                : .2 + math.min(.8, (x - .5).abs() * 2.2);
        y = math.min(.98, f);
      } else {
        y = .5 - .42 * _waveAt(v, (x * 1.5) % 1);
      }
      var q = Offset(r.left + x * r.width, r.top + y * r.height);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round
          ..color = col);
  }

  // ------------------------------------------------------------ knobs

  void _knobs() {
    var ks = synthKnobs[kind]!;
    for (var (i, k) in ks.indexed) {
      var dial = p.dials[i], cell = p.knobs[i];
      var t = k.turn(e.value(k.key));
      _knob(dial.center, t);
      _text(k.label.toUpperCase(), Offset(cell.center.dx, dial.bottom + 6), 8.5,
          analogue ? ink : const Color(0xFF9AA3B2),
          weight: FontWeight.w800, spacing: 0.5, centre: true);
      _text(k.show(e.value(k.key)), Offset(cell.center.dx, dial.bottom + 17),
          8.5, analogue ? ink.withValues(alpha: 0.75) : accent,
          mono: true, centre: true);
    }
  }

  void _knob(Offset o, double t) {
    const r = 15.0;
    var ang = (-135 + t * 270) * math.pi / 180 - math.pi / 2;
    Offset at(double a, double rad) =>
        o + Offset(math.cos(a), math.sin(a)) * rad;
    var ptr = Paint()
      ..strokeWidth = analogue ? 2.4 : 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF);
    if (analogue) {
      var tick = Paint()
        ..strokeWidth = 1.1
        ..color = ink.withValues(alpha: 0.8);
      for (var i = 0; i <= 10; i++) {
        var a = (-135 + i * 27) * math.pi / 180 - math.pi / 2;
        c.drawLine(at(a, r + 3), at(a, r + (i % 5 == 0 ? 7.5 : 5.5)), tick);
      }
      c.drawCircle(o, r, Paint()..color = const Color(0xFF2B2B2B));
      c.drawCircle(
          o,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF111111));
      c.drawCircle(
          o,
          r - 4,
          Paint()
            ..shader = ui.Gradient.radial(
                o + const Offset(-2.2, -2.8),
                (r - 4) * 1.4,
                const [Color(0xFF5A5A5A), Color(0xFF262626), Color(0xFF0E0E0E)],
                const [0, 0.6, 1]));
      c.drawLine(at(ang, r - 8), at(ang, r - 1), ptr);
    } else {
      var track = Rect.fromCircle(center: o, radius: r + 4);
      var start = -135 * math.pi / 180 - math.pi / 2;
      c.drawArc(
          track,
          start,
          270 * math.pi / 180,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFF2B303B));
      if (t > 0.004) {
        var sweep = t * 270 * math.pi / 180;
        c.drawArc(
            track,
            start,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5
              ..strokeCap = StrokeCap.round
              ..color = accent.withValues(alpha: 0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        c.drawArc(
            track,
            start,
            sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..strokeCap = StrokeCap.round
              ..color = accent);
      }
      c.drawCircle(o, r - 1, Paint()..color = const Color(0xFF262A34));
      c.drawCircle(
          o,
          r - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF353B48));
      c.drawLine(at(ang, r - 10), at(ang, r - 3), ptr);
    }
  }

  // ------------------------------------------------------------ jacks

  void _jacks() {
    for (var port in kind.ins) {
      var o = p.ins[port.name]!;
      _jack(o, port.signal);
      _text(
          analogue ? port.name.toUpperCase() : port.name,
          o + const Offset(synthJackRadius + 5, 0),
          analogue ? 8.5 : 9.5,
          analogue ? ink : const Color(0xFF9AA3B2),
          weight: FontWeight.w800,
          mono: analogue,
          spacing: analogue ? 0.5 : 0,
          middle: true);
    }
    for (var port in kind.outs) {
      var o = p.outs[port.name]!;
      var label = analogue ? port.name.toUpperCase() : port.name;
      var tp = _layout(label, analogue ? 8.5 : 9.5,
          analogue ? const Color(0xFFECEBE6) : const Color(0xFF9AA3B2),
          weight: FontWeight.w800, mono: analogue, spacing: analogue ? 0.5 : 0);
      if (analogue) {
        // Outputs on a dark tag, as on a Eurorack panel; light on a dark one.
        var dark = face.computeLuminance() < 0.2;
        tp = _layout(label, 8.5,
            dark ? const Color(0xFF1D1D1B) : const Color(0xFFECEBE6),
            weight: FontWeight.w800, mono: true, spacing: 0.5);
        var tag = Rect.fromLTRB(
            o.dx - synthJackRadius - tp.width - 10,
            o.dy - synthJackRadius - 3,
            o.dx + synthJackRadius + 3,
            o.dy + synthJackRadius + 3);
        c.drawRRect(
            RRect.fromRectAndRadius(tag, const Radius.circular(3)),
            Paint()
              ..color =
                  dark ? const Color(0xFFECEBE6) : const Color(0xFF1D1D1B));
      }
      tp.paint(c,
          Offset(o.dx - synthJackRadius - 5 - tp.width, o.dy - tp.height / 2));
      _jack(o, port.signal);
    }
  }

  void _jack(Offset o, SynthSignal s) {
    var col = synthSignalColour(s);
    const r = synthJackRadius;
    if (analogue) {
      c.drawCircle(o, r + 1.5, Paint()..color = col);
      c.drawCircle(
          o,
          r,
          Paint()
            ..shader = ui.Gradient.radial(o, r, const [
              Color(0xFF050505),
              Color(0xFF050505),
              Color(0xFF9FA3A8),
              Color(0xFFD7DADE),
              Color(0xFF7D8187),
            ], const [
              0,
              0.32,
              0.4,
              0.62,
              1
            ]));
    } else {
      c.drawCircle(
          o,
          r + 2,
          Paint()
            ..color = col.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      c.drawCircle(o, r, Paint()..color = const Color(0xFF0B0D12));
      c.drawCircle(
          o,
          r - 1.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = col);
    }
  }

  // ------------------------------------------------------------ text

  TextPainter _layout(String t, double size, Color col,
          {FontWeight weight = FontWeight.w600,
          bool mono = false,
          double spacing = 0,
          double? maxWidth}) =>
      TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                fontSize: size,
                fontWeight: weight,
                fontFamily: mono ? "RobotoMono" : "Inter",
                letterSpacing: spacing,
                height: 1.2,
                color: col)),
        textDirection: TextDirection.ltr,
        maxLines: maxWidth == null ? 1 : 2,
      )..layout(maxWidth: maxWidth ?? double.infinity);

  /// _text draws [t] from [o]: its top left, or (with [middle]) its left
  /// middle, or (with [centre]) its middle.
  TextPainter _text(String t, Offset o, double size, Color col,
      {FontWeight weight = FontWeight.w600,
      bool mono = false,
      double spacing = 0,
      bool middle = false,
      bool centre = false,
      double? maxWidth}) {
    var tp = _layout(t, size, col,
        weight: weight, mono: mono, spacing: spacing, maxWidth: maxWidth);
    tp.paint(
        c,
        centre
            ? o - Offset(tp.width / 2, tp.height / 2)
            : middle
                ? o - Offset(0, tp.height / 2)
                : o);
    return tp;
  }
}

/// synthKeyboardWhites are the keyboard module's white keys, middle C to C.
const synthKeyboardWhites = [60, 62, 64, 65, 67, 69, 71, 72];

/// synthBlackKeys are the keyboard module's black keys in [r], its keys'
/// place.
List<(int, Rect)> synthBlackKeys(Rect r) {
  var ww = r.width / synthKeyboardWhites.length;
  return [
    for (var (k, after) in const [(61, 0), (63, 1), (66, 3), (68, 4), (70, 5)])
      (
        k,
        Rect.fromLTWH(r.left + (after + 1) * ww - ww * 0.32, r.top, ww * 0.64,
            r.height * 0.58)
      ),
  ];
}

/// synthKeyAt is the keyboard module's key at [q] in [r], its keys' place:
/// a black key over the white under it.
int? synthKeyAt(Rect r, Offset q) {
  if (!r.contains(q)) return null;
  for (var (k, rect) in synthBlackKeys(r)) {
    if (rect.contains(q)) return k;
  }
  var i = ((q.dx - r.left) / (r.width / synthKeyboardWhites.length))
      .floor()
      .clamp(0, synthKeyboardWhites.length - 1);
  return synthKeyboardWhites[i];
}

// ------------------------------------------------------------ cables

/// synthCablePath is a cable from [a] to [b], sagging under its weight as
/// the prototype's did.
Path synthCablePath(Offset a, Offset b, double scale) {
  var sag = math.min(120.0, (b.dx - a.dx).abs() * 0.4 + 40) * scale;
  var reach = 60 * scale;
  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(a.dx + reach, a.dy + sag, b.dx - reach, b.dy + sag, b.dx, b.dy);
}

/// SynthCable is one cable as drawn: from an output to an input.
typedef SynthCable = ({
  SynthModuleElement from,
  String out,
  SynthModuleElement into,
  String input,
  Offset a,
  Offset b,
  SynthSignal signal,
});

/// synthCables are the cables between the visible modules in [elements].
List<SynthCable> synthCables(List<CanvasElement> elements) {
  var mods = {
    for (var e in elements)
      if (e is SynthModuleElement && e.visible) e.id: e
  };
  var out = <SynthCable>[];
  for (var into in mods.values) {
    for (var MapEntry(key: input, value: plug) in into.inputs.entries) {
      var from = mods[plug.module];
      if (from == null) continue;
      var port = from.module.output(plug.port);
      var a = synthJackAt(from, plug.port, out: true);
      var b = synthJackAt(into, input, out: false);
      if (port == null || a == null || b == null) continue;
      out.add((
        from: from,
        out: plug.port,
        into: into,
        input: input,
        a: a,
        b: b,
        signal: port.signal
      ));
    }
  }
  return out;
}

/// synthScaleOf is a module's panel scale on the canvas.
double synthScaleOf(SynthModuleElement e) =>
    synthPanelFit(e.bounds, synthPanelOf(e.module)).$1;

/// paintSynthCables draws the cables between the modules in [elements],
/// over them all, as cables hang over a rack.
void paintSynthCables(ui.Canvas canvas, List<CanvasElement> elements,
    {SynthCable? lifted}) {
  for (var cable in synthCables(elements)) {
    var s = (synthScaleOf(cable.from) + synthScaleOf(cable.into)) / 2;
    paintSynthCable(
        canvas, cable.a, cable.b, synthSignalColour(cable.signal), s,
        faded: identical(cable, lifted));
  }
}

/// paintSynthCable draws one cable from [a] to [b], with its plugs.
void paintSynthCable(ui.Canvas canvas, Offset a, Offset b, Color col, double s,
    {bool faded = false, bool dashed = false}) {
  var path = synthCablePath(a, b, s);
  if (!dashed) {
    canvas.drawPath(
        path.shift(Offset(0, 3 * s)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * s
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x33000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 * s));
  }
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4 * s
    ..strokeCap = StrokeCap.round
    ..color = col.withValues(alpha: faded ? 0.3 : 0.88);
  if (dashed) {
    for (var m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 12 * s) {
        canvas.drawPath(m.extractPath(d, d + 6 * s), line);
      }
    }
  } else {
    canvas.drawPath(path, line);
  }
  for (var o in [a, b]) {
    canvas.drawCircle(
        o, 4.5 * s, Paint()..color = col.withValues(alpha: faded ? 0.3 : 1));
    canvas.drawCircle(o, 2 * s, Paint()..color = const Color(0xFF111111));
  }
}

// ------------------------------------------------------------ presses

/// SynthPartKind is what on a panel can be pressed.
enum SynthPartKind { key, knob, option, jack, reset, look, screen }

/// SynthPart is what is under a press on a module: a key (by number), a
/// knob or option (by place), a jack (by name, and whether an output), or
/// a header button.
class SynthPart {
  final SynthPartKind kind;
  final int index;
  final String port;
  final bool out;
  const SynthPart(this.kind,
      {this.index = 0, this.port = "", this.out = false});

  @override
  bool operator ==(Object other) =>
      other is SynthPart &&
      other.kind == kind &&
      other.index == index &&
      other.port == port &&
      other.out == out;

  @override
  int get hashCode => Object.hash(kind, index, port, out);

  @override
  String toString() => "SynthPart($kind, $index, $port, $out)";
}

/// synthPartAt is what on [e] is under [point], in document space: null on
/// the panel itself (its header, its legends), which a press picks and
/// moves.
SynthPart? synthPartAt(SynthModuleElement e, Offset point) {
  var q = synthToPanel(e, point);
  if (q == null) return null;
  var p = synthPanelOf(e.module);
  const reach = synthJackRadius + 5;
  for (var MapEntry(:key, :value) in p.ins.entries) {
    if ((q - value).distance <= reach) {
      return SynthPart(SynthPartKind.jack, port: key);
    }
  }
  for (var MapEntry(:key, :value) in p.outs.entries) {
    if ((q - value).distance <= reach) {
      return SynthPart(SynthPartKind.jack, port: key, out: true);
    }
  }
  if (p.reset case var r? when r.inflate(2).contains(q)) {
    return const SynthPart(SynthPartKind.reset);
  }
  if (p.look.inflate(2).contains(q)) return const SynthPart(SynthPartKind.look);
  if (p.keys case var r?) {
    if (synthKeyAt(r, q) case var k?) {
      return SynthPart(SynthPartKind.key, index: k);
    }
  }
  for (var (i, r) in p.options.indexed) {
    if (r.contains(q)) return SynthPart(SynthPartKind.option, index: i);
  }
  if (synthScreenGrab(e, q) case var g?) {
    return SynthPart(SynthPartKind.screen, port: g);
  }
  for (var (i, r) in p.knobs.indexed) {
    if (r.contains(q)) return SynthPart(SynthPartKind.knob, index: i);
  }
  return null;
}

/// synthJackUnder is the jack under [point] among [elements]' modules:
/// the module, the jack, and whether it is an output.
(SynthModuleElement, String, bool)? synthJackUnder(
    List<CanvasElement> elements, Offset point) {
  for (var e in elements.reversed) {
    if (e is! SynthModuleElement || !e.visible) continue;
    var part = synthPartAt(e, point);
    if (part != null && part.kind == SynthPartKind.jack) {
      return (e, part.port, part.out);
    }
  }
  return null;
}

// ------------------------------------------------------------ screens dragged

/// synthEnvPoints are an envelope screen's corners in [r] for [e]: where
/// the attack peaks, where the decay meets the sustain, and where the
/// release ends -- as _envScreen draws them.
({
  Offset a,
  Offset ds,
  Offset r,
  double x0,
  double seg,
  double susW,
  double pad
}) synthEnvPoints(SynthModuleElement e, Rect r) {
  const pad = 9.0;
  var susW = r.width * 0.16;
  var seg = (r.width - 2 * pad - susW) / 3;
  double w(String k) => math.sqrt(e.value(k) / _envMax[k]!) * seg;
  double y(double v) => r.bottom - pad - v * (r.height - 2 * pad);
  var x0 = r.left + pad, xa = x0 + w("a"), xd = xa + w("d");
  var xs = xd + susW;
  return (
    a: Offset(xa, y(1)),
    ds: Offset(xd, y(e.value("s"))),
    r: Offset(xs + w("r"), y(0)),
    x0: x0,
    seg: seg,
    susW: susW,
    pad: pad,
  );
}

const _envMax = {"a": 3.0, "d": 3.0, "r": 4.0};

/// synthScreenGrab is what on a digital envelope or filter screen is
/// under panel point [q]: an envelope's corner ("a", "ds", "r") or the
/// filter's curve ("f"). Null on an analogue panel, which is only looked
/// at, as hardware's is.
String? synthScreenGrab(SynthModuleElement e, Offset q) {
  if (e.look != SynthLook.digital) return null;
  var r = synthPanelOf(e.module).screen;
  if (r == null || !r.inflate(4).contains(q)) return null;
  if (e.module == SynthModuleKind.filter) return "f";
  if (e.module != SynthModuleKind.env) return null;
  var p = synthEnvPoints(e, r);
  var near = [("a", p.a), ("ds", p.ds), ("r", p.r)]
    ..sort((x, y) => (x.$2 - q).distance.compareTo((y.$2 - q).distance));
  return (near.first.$2 - q).distance <= 20 ? near.first.$1 : null;
}

/// synthScreenDragged is [e] with what [grab] took on its screen dragged
/// to panel point [q]: an envelope's attack, decay and sustain, or
/// release; the filter's cutoff (across) and resonance (up).
SynthModuleElement synthScreenDragged(
    SynthModuleElement e, String grab, Offset q) {
  var r = synthPanelOf(e.module).screen!;
  if (e.module == SynthModuleKind.filter) {
    const lo = 20.0, hi = 20000.0, dbHi = 24.0, dbLo = -36.0;
    var f = lo *
        math.pow(hi / lo, ((q.dx - r.left - 7) / (r.width - 14)).clamp(0, 1));
    var db = dbHi - (q.dy - r.top - 5) / (r.height - 10) * (dbHi - dbLo);
    var res = (math.pow(10, db / 20) - 0.7) / 0.97;
    return e
        .withValue("cutoff", f.clamp(40, 16000).toDouble())
        .withValue("res", res.clamp(0.1, 20).toDouble());
  }
  var p = synthEnvPoints(e, r);
  double inv(double dx, String k) =>
      (_envMax[k]! * math.pow(math.max(0.0, dx) / p.seg, 2))
          .clamp(k == "a" ? 0.001 : 0.01, _envMax[k]!)
          .toDouble();
  return switch (grab) {
    "a" => e.withValue("a", inv(q.dx - p.x0, "a")),
    "ds" => e.withValue("d", inv(q.dx - p.a.dx, "d")).withValue("s",
        ((r.bottom - p.pad - q.dy) / (r.height - 2 * p.pad)).clamp(0.0, 1.0)),
    "r" => e.withValue("r", inv(q.dx - (p.ds.dx + p.susW), "r")),
    _ => e,
  };
}
