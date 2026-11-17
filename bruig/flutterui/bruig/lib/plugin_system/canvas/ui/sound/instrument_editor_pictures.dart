part of 'instrument_editor.dart';

// The pictures the cards' knobs sit over: the volume envelope, the filter
// curve, the LFO, the velocity curve and a sound's key and velocity zones, with
// the drawing helpers they share. Part of instrument_editor.dart.

/// _held is how long, in seconds, the envelope's picture shows the key
/// held between its decay and its release.
const double _held = 0.6;

/// envelopePoints is [s]'s envelope drawn in [size]: seconds to pixels,
/// then where it starts, peaks, meets its sustain, is let go and ends.
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

/// EnvelopePainter draws a volume envelope with three dots to drag, or
/// faint where the sound's own is used.
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

/// filterGain is [s]'s filter's response at [hz], in decibels, as the
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

/// VelocityPainter draws the velocity curve: strike strength across,
/// loudness up.
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

/// ZoneMap is a sound's zones as the Zones card draws them: which sample
/// group plays at each key (21 to 108) and velocity band, and how many
/// layers and key ranges that makes.
class ZoneMap {
  static const lowKey = 21, keys = 88, bands = 16;

  /// cells are the group at each band (from the softest) of each key: the
  /// same number, the same samples.
  final List<List<int>> cells;
  final int layers, ranges;
  const ZoneMap(this.cells, this.layers, this.ranges);
}

final Map<(SoundFont, int, int), ZoneMap> _zoneMaps = {};

/// zoneMap is [font]'s zones for the sound at [bank] and [program], cached.
ZoneMap? zoneMap(SoundFont font, int bank, int program) {
  var key = (font, bank, program);
  if (_zoneMaps[key] case var m?) return m;
  var preset = font.preset(bank, program);
  if (preset == null) return null;
  var groups = <String, int>{};
  int groupOf(int k, int v) {
    var names = [for (var z in font.zones(preset, k, v)) z.sample.name]..sort();
    if (names.isEmpty) return -1;
    return groups.putIfAbsent(names.join("|"), () => groups.length);
  }

  var cells = [
    for (var k = 0; k < ZoneMap.keys; k++)
      [
        for (var b = 0; b < ZoneMap.bands; b++)
          groupOf(ZoneMap.lowKey + k, 1 + b * 8)
      ],
  ];
  // Layers: the most groups any one key changes through, softest to hardest;
  // ranges: the groups along the keys, played moderately hard.
  var layers = 1;
  for (var col in cells) {
    var n = col.where((g) => g >= 0).toSet().length;
    if (n > layers) layers = n;
  }
  var ranges = 0, last = -2;
  for (var col in cells) {
    var g = col[12];
    if (g >= 0 && g != last) ranges++;
    last = g;
  }
  return _zoneMaps[key] = ZoneMap(cells, layers, math.max(1, ranges));
}

/// _ZonesPainter draws a ZoneMap: keys along, velocity up, each sample
/// group its own shade; with none, one zone over all of it.
class _ZonesPainter extends CustomPainter {
  final ZoneMap? map;
  final Color accent, back, text;
  _ZonesPainter(this.map,
      {required this.accent, required this.back, required this.text});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = back);
    var m = map;
    if (m == null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              (Offset.zero & size).deflate(6), const Radius.circular(3)),
          Paint()..color = accent.withValues(alpha: 0.25));
      return;
    }
    var w = size.width / ZoneMap.keys, h = size.height / ZoneMap.bands;
    for (var (k, col) in m.cells.indexed) {
      for (var (b, g) in col.indexed) {
        if (g < 0) continue;
        var shade = 0.25 + 0.6 * ((g * 37) % 11) / 10;
        canvas.drawRect(
            Rect.fromLTWH(k * w, size.height - (b + 1) * h, w + 0.5, h + 0.5),
            Paint()..color = accent.withValues(alpha: shade));
      }
    }
  }

  @override
  bool shouldRepaint(_ZonesPainter old) =>
      old.map != map || old.accent != accent || old.back != back;
}
