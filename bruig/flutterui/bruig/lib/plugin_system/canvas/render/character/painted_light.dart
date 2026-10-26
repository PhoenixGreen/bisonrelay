import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

// painted_light.dart lights a drawn character the way an illustrator
// paints one: every shape of it rounded from its own outline, so the light
// turns softly across a leg or a lock of hair and the shadow comes in from
// its edges, tinted as skin, hair and cloth take it, with a rim of light,
// a sheen on the hair and soft shadows where one part lies over another.
//
// The sketch is drawn once, as flat colour, and as it is drawn every solid
// shape is also laid into two more pictures: how high it is raised from
// its edge -- its outline blurred, kept inside itself -- and what it is
// made of and in what order it was laid down. The shader in
// character_paint.frag lights the colours from those.

/// PaintShader is character_paint.frag, loaded once.
class PaintShader {
  static FragmentProgram? _program;
  static Future<void>? _loading;

  static FragmentProgram? get program => _program;

  static Future<void> load() => _loading ??= () async {
        try {
          _program = await FragmentProgram.fromAsset("shaders/character_paint.frag");
        } catch (e) {
          // Without it the painted style is drawn as soft flat colour.
          _program = null;
        }
      }();
}

/// PaintedMaterial is what a shape is made of, for how it takes light.
enum PaintedMaterial {
  none,
  skin,
  hair,
  cloth,

  /// flat is a feature -- an eye, a mouth, a print -- lit only a little.
  flat,
}

/// PaintedLook is how the light falls and the line is drawn.
class PaintedLook {
  /// light is where the light comes from: x right, y up, z towards the
  /// reader -- above, to the left and in front.
  final List<double> light;
  final double soft;
  final double shift;
  final double round;
  final double rim;
  final double sheen;

  /// line is the line's width, in the figure's own units; ink its colour.
  final double line;
  final Color ink;
  final Color skinShade;
  final Color hairShade;
  final Color clothShade;
  final double contact;

  /// reach is how far a part's shadow falls on what is behind it, in the
  /// figure's own units.
  final double reach;
  const PaintedLook({
    this.light = const [-0.55, 0.6, 0.58],
    this.soft = 0.45,
    this.shift = 0.02,
    this.round = 16,
    this.rim = 0.18,
    this.sheen = 0.2,
    this.line = 1.4,
    this.ink = const Color(0xFF6B4636),
    this.skinShade = const Color(0xFFD48A78),
    this.hairShade = const Color(0xFFA0703F),
    this.clothShade = const Color(0xFFB4B8CE),
    this.contact = 0.55,
    this.reach = 6,
  });
}

/// PaintedBuffers is the two pictures laid down as the sketch is drawn:
/// height, and material and order. Each takes a shape as the drawing's
/// own canvas has it placed -- see [add].
class PaintedBuffers {
  final PictureRecorder _height = PictureRecorder();
  final PictureRecorder _part = PictureRecorder();
  late final Canvas height = Canvas(_height);
  late final Canvas part = Canvas(_part);
  int _order = 1;

  /// add lays a shape into both pictures: [draw] draws it with a paint
  /// onto the canvas it is given, placed by [transform] -- the drawing's
  /// canvas's transform as the shape was drawn -- [bounds] across.
  ///
  /// [round] is how far in from its edge a shape is rounded at most: about
  /// a limb's half-width, so an arm is rounded right across and the wide
  /// front of a dress is full in the middle and turns at its edges.
  void add(Float64List transform, Rect bounds, PaintedMaterial material,
      double round, void Function(Canvas onto, Paint paint) draw) {
    var sigma = math.max(0.8, math.min(math.min(bounds.width, bounds.height) * 0.4, round));
    height
      ..save()
      ..transform(transform)
      ..saveLayer(bounds.inflate(sigma * 3), Paint());
    // Black where the shape is -- it replaces whatever it covers -- then
    // its own outline blurred into it: highest in its middle.
    draw(height, Paint()..color = const Color(0xFF000000));
    draw(
        height,
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
          ..blendMode = BlendMode.srcATop);
    height
      ..restore()
      ..restore();
    part
      ..save()
      ..transform(transform);
    draw(part,
        Paint()..color = Color.fromARGB(255, material.index, _order % 256, _order ~/ 256));
    part.restore();
    _order++;
  }
}

/// _lit is the last few figures lit, by what they were drawn from: the
/// picture and where it went against the figure's own corner. A canvas
/// drawn again -- a selection, a hover, a figure dragged along -- draws the
/// picture it already has.
final Map<String, (Rect, Image)> _lit = {};
const int _litKept = 12;

/// paintPainted draws [figure] -- the sketch, drawn as flat colour onto
/// the canvas it is given, laying its shapes into the buffers -- lit as
/// [look] says, filling [room] on [onto]. False when the shader is not
/// loaded: nothing is drawn, and the caller draws it as it would have.
///
/// [key] is everything the figure is drawn from but where it is: drawn
/// again from the same, it is the picture made last time, put where
/// [room] is now.
bool paintPainted(Canvas onto, Rect room, PaintedLook look,
    void Function(Canvas flat, PaintedBuffers buffers) figure,
    {String? key}) {
  var program = PaintShader.program;
  if (program == null) {
    PaintShader.load();
    return false;
  }
  var m = onto.getTransform();
  var seen = math.sqrt(m[0] * m[0] + m[1] * m[1]).clamp(0.25, 8.0);
  var full = key == null ? null : "$key|${seen.toStringAsFixed(3)}|${room.size}";
  if (full != null) {
    if (_lit.remove(full) case (var at, var image)?) {
      _lit[full] = (at, image);
      onto.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          at.shift(room.topLeft),
          Paint()..filterQuality = FilterQuality.medium);
      return true;
    }
  }
  // Drawn a little larger than it is seen -- the light is soft, and every
  // pixel more is more to blur -- and no bigger than sensible.
  var scale = seen * 1.25;
  var longest = math.max(room.width, room.height) * scale;
  if (longest > 1800) scale *= 1800 / longest;
  var w = math.max(1, (room.width * scale).ceil());
  var h = math.max(1, (room.height * scale).ceil());
  var flatRecorder = PictureRecorder();
  var flat = Canvas(flatRecorder)
    ..scale(scale)
    ..translate(-room.left, -room.top);
  var buffers = PaintedBuffers();
  figure(flat, buffers);
  var albedo = flatRecorder.endRecording().toImageSync(w, h);
  var height = buffers._height.endRecording().toImageSync(w, h);
  var part = buffers._part.endRecording().toImageSync(w, h);

  var shader = program.fragmentShader();
  var k = 0;
  void f(double v) => shader.setFloat(k++, v);
  void colour(Color c) {
    f(c.r);
    f(c.g);
    f(c.b);
  }

  f(w.toDouble());
  f(h.toDouble());
  for (var v in look.light) {
    f(v);
  }
  f(look.soft);
  f(look.shift);
  f(look.round);
  f(look.rim);
  f(look.sheen);
  f(look.line * scale);
  f(look.ink.r);
  f(look.ink.g);
  f(look.ink.b);
  f(look.ink.a);
  colour(look.skinShade);
  colour(look.hairShade);
  colour(look.clothShade);
  f(look.contact);
  f(look.reach * scale);
  shader.setImageSampler(0, albedo, filterQuality: FilterQuality.none);
  shader.setImageSampler(1, height, filterQuality: FilterQuality.low);
  shader.setImageSampler(2, part, filterQuality: FilterQuality.none);
  var lit = PictureRecorder();
  Canvas(lit).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..shader = shader);
  var picture = lit.endRecording().toImageSync(w, h);
  onto.drawImageRect(picture, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), room,
      Paint()..filterQuality = FilterQuality.medium);
  for (var i in [albedo, height, part]) {
    i.dispose();
  }
  if (full != null) {
    _lit[full] = (Offset.zero & room.size, picture);
    while (_lit.length > _litKept) {
      var first = _lit.keys.first;
      _lit.remove(first)!.$2.dispose();
    }
  } else {
    picture.dispose();
  }
  return true;
}
