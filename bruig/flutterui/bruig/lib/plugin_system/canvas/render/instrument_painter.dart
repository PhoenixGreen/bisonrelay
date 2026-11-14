import 'package:bruig/plugin_system/canvas/model/fretting.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:flutter/painting.dart';

// instrument_painter.dart draws an instrument as what it is played on
// (keys, pads, or strings and frets), with the sounding notes lit.
//
// The keys are laid out once, in keyboardLayout, and the stage hit-tests the
// same rectangles the painter drew, as with audio_painter.dart's controls.

/// KeyRect is one key: where it is, and whether it is a black one.
typedef KeyRect = ({int key, Rect rect, bool black});

/// KeyboardLayout is the keyboard inside an element's box: its name strip
/// along the top, and the keys under it.
class KeyboardLayout {
  final Rect title;
  final Rect board;
  final List<KeyRect> keys;
  const KeyboardLayout(this.title, this.board, this.keys);

  /// keyAt is the key under [p] (a black one before the white under it) and
  /// how far down the key it was pressed, nought to one; further down is
  /// harder. Null where there is no key.
  (int, double)? keyAt(Offset p) {
    for (var black in [true, false]) {
      for (var k in keys) {
        if (k.black != black || !k.rect.contains(p)) continue;
        return (k.key, ((p.dy - k.rect.top) / k.rect.height).clamp(0.0, 1.0));
      }
    }
    return null;
  }
}

/// keyboardLayout lays [part]'s keys, pads, or strings and frets out inside
/// [bounds], one KeyRect per playable place. Without [titled] -- the
/// instrument editor's, which names it elsewhere -- they fill [bounds],
/// with no name strip and no case round them.
KeyboardLayout keyboardLayout(InstrumentPart part, Rect bounds,
    {bool titled = true}) {
  var inset = titled ? math.min(bounds.width, bounds.height) * 0.04 : 0.0;
  var inner = bounds.deflate(inset);
  var titleHeight = titled ? math.min(inner.height * 0.16, 22.0) : 0.0;
  var title = Rect.fromLTWH(inner.left, inner.top, inner.width, titleHeight);
  var board = Rect.fromLTRB(
      inner.left, inner.top + titleHeight, inner.right, inner.bottom);
  switch (part.look) {
    case InstrumentLook.drums:
      // Four by four; on a wide, short board, as the prototype's editor
      // has them, eight by two.
      var cols = board.width > board.height * 2.5 ? 8 : 4;
      var rows = drumPads.length ~/ cols;
      var gap = math.min(board.width, board.height) * 0.03;
      var w = (board.width - gap * (cols - 1)) / cols,
          h = (board.height - gap * (rows - 1)) / rows;
      return KeyboardLayout(title, board, [
        for (var (i, (key, _)) in drumPads.indexed)
          (
            key: key,
            rect: Rect.fromLTWH(board.left + (i % cols) * (w + gap),
                board.top + (i ~/ cols) * (h + gap), w, h),
            black: false,
          ),
      ]);
    case InstrumentLook.guitar || InstrumentLook.bass:
      var strings =
          part.look == InstrumentLook.guitar ? guitarStrings : bassStrings;
      var nut = board.left + board.width * 0.06;
      var band = board.height / strings.length;
      return KeyboardLayout(title, board, [
        for (var (i, open) in strings.indexed)
          for (var f = 0; f <= frets; f++)
            (
              key: open + f,
              // The lowest string at the bottom, as the player sees it.
              rect: Rect.fromLTRB(
                  f == 0 ? board.left : fretX(nut, board.right, f - 1),
                  board.bottom - (i + 1) * band,
                  f == 0 ? nut : fretX(nut, board.right, f),
                  board.bottom - i * band),
              black: false,
            ),
      ]);
    case InstrumentLook.keyboard:
      break;
  }
  var whites = [
    for (var k = part.lowKey; k <= part.highKey; k++)
      if (!isBlackKey(k)) k
  ];
  if (whites.isEmpty) return KeyboardLayout(title, board, const []);
  var w = board.width / whites.length;
  var keys = <KeyRect>[];
  for (var (i, k) in whites.indexed) {
    keys.add((
      key: k,
      rect: Rect.fromLTWH(board.left + i * w, board.top, w, board.height),
      black: false,
    ));
  }
  // A black key sits over the join to the white key after it.
  for (var k = part.lowKey; k <= part.highKey; k++) {
    if (!isBlackKey(k)) continue;
    var before = whites.indexOf(k - 1);
    if (before < 0) continue;
    var x = board.left + (before + 1) * w;
    keys.add((
      key: k,
      rect: Rect.fromLTWH(x - w * 0.3, board.top, w * 0.6, board.height * 0.62),
      black: true,
    ));
  }
  return KeyboardLayout(title, board, keys);
}

/// neckPlaceAt is the string and fret of [part]'s neck under [p], as
/// [layout] lays it out; null off the neck, or for an instrument with none.
FretPlace? neckPlaceAt(KeyboardLayout layout, InstrumentPart part, Offset p) {
  if (part.look != InstrumentLook.guitar && part.look != InstrumentLook.bass) {
    return null;
  }
  // The neck's places are laid out a string at a time, nut to body.
  for (var (i, k) in layout.keys.indexed) {
    if (k.rect.contains(p)) return (i ~/ (frets + 1), i % (frets + 1));
  }
  return null;
}

/// fretX is where fret [n] is between the nut at [nut] and the end of the
/// neck at [end]: closer together up the neck, as a string's halving is.
double fretX(double nut, double end, int n) {
  double at(int k) => 1 - math.pow(2, -k / 12).toDouble();
  return nut + (end - nut) * at(n) / at(frets);
}

/// paintKeyboard draws [part] inside [bounds], [lit] keys in [accent]; a
/// red mark by the name while [recording].
void paintKeyboard(ui.Canvas canvas, Rect bounds, InstrumentPart part,
    {Set<int> lit = const {},
    Set<int> next = const {},
    Map<int, FretPlace> places = const {},
    Color accent = const Color(0xFF3D7EFF),
    bool recording = false}) {
  var layout = keyboardLayout(part, bounds);
  var radius = math.min(bounds.width, bounds.height) * 0.06;
  canvas.drawRRect(RRect.fromRectAndRadius(bounds, Radius.circular(radius)),
      Paint()..color = const Color(0xFF1C1E24));
  // The name, on the case above the keys.
  var name = TextPainter(
    text: TextSpan(
        text: part.name,
        style: TextStyle(
            fontSize: layout.title.height * 0.62,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFD9DCE2))),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: "…",
  )..layout(maxWidth: math.max(0, layout.title.width - layout.title.height));
  name.paint(
      canvas,
      Offset(layout.title.left + layout.title.height * 0.2,
          layout.title.center.dy - name.height / 2));
  if (recording) {
    canvas.drawCircle(
        Offset(layout.title.right - layout.title.height * 0.5,
            layout.title.center.dy),
        layout.title.height * 0.22,
        Paint()..color = const Color(0xFFFF5A5A));
  }
  if (part.look == InstrumentLook.drums) {
    _paintPads(canvas, layout, lit, next, accent);
    return;
  }
  if (part.look == InstrumentLook.guitar || part.look == InstrumentLook.bass) {
    _paintNeck(canvas, layout, part, lit, next, accent, places);
    return;
  }
  var line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xFF3A3D44);
  for (var black in [false, true]) {
    for (var k in layout.keys) {
      if (k.black != black) continue;
      var on = lit.contains(k.key);
      // Waited for by a practice take: blue, whatever else it is.
      var wanted = next.contains(k.key);
      var r = RRect.fromRectAndCorners(k.rect,
          bottomLeft: Radius.circular(k.rect.width * 0.12),
          bottomRight: Radius.circular(k.rect.width * 0.12));
      var colour = wanted
          ? (black ? const Color(0xFF3D7EFF) : const Color(0xFF9EC0FF))
          : black
              ? (on
                  ? Color.lerp(accent, const Color(0xFF000000), 0.25)!
                  : const Color(0xFF15161A))
              : (on
                  ? Color.lerp(accent, const Color(0xFFFFFFFF), 0.35)!
                  : const Color(0xFFF4F4F1));
      canvas.drawRRect(r, Paint()..color = colour);
      canvas.drawRRect(r, line);
    }
  }
  // Middle C, marked, so a keyboard can be read at a glance.
  for (var k in layout.keys) {
    if (k.key != 60) continue;
    canvas.drawCircle(
        Offset(k.rect.center.dx, k.rect.bottom - k.rect.width * 0.35),
        math.max(1.5, k.rect.width * 0.08),
        Paint()..color = const Color(0xFF9AA0AA));
  }
}

/// paintPlayingSurface draws [part]'s pads, or its neck, as [layout] has
/// them, with no case or name: the instrument editor's, under its own
/// toolbar. A keyboard is the editor's own to draw.
/// A drum pad shows its name and, from [letters], the computer key that
/// plays it; [face] and [ink] are the pads' own colour and their writing.
void paintPlayingSurface(
    ui.Canvas canvas, KeyboardLayout layout, InstrumentPart part,
    {Set<int> lit = const {},
    Map<int, FretPlace> places = const {},
    Color accent = const Color(0xFF3D7EFF),
    Map<int, String> letters = const {},
    Color face = _padFace,
    Color ink = _padInk}) {
  if (part.look == InstrumentLook.drums) {
    _paintPads(canvas, layout, lit, const {}, accent,
        letters: letters, face: face, ink: ink);
  } else if (part.look == InstrumentLook.guitar ||
      part.look == InstrumentLook.bass) {
    _paintNeck(canvas, layout, part, lit, const {}, accent, places);
  }
}

const Color _padFace = Color(0xFF2E3138);
const Color _padInk = Color(0xFFD9DCE2);

/// padFamily is the colour of drum [key]'s family, along its pad's top: the
/// kick red, snares and hand claps amber, toms violet, hats and cymbals
/// teal, the rest of the percussion green.
Color padFamily(int key) => switch (key) {
      35 || 36 => const Color(0xFFE0756A),
      37 || 38 || 39 || 40 => const Color(0xFFE0A84F),
      41 || 43 || 45 || 47 || 48 || 50 => const Color(0xFF9A92EA),
      42 || 44 || 46 || 49 || 51 || 52 || 53 || 55 || 57 || 59 =>
        const Color(0xFF5CC6B8),
      _ => const Color(0xFF8BC46B),
    };

/// _paintPads draws the kit's pads: each a raised square with its family's
/// colour along its top, its name, and -- from [letters] -- a key cap with
/// the computer key that plays it. Struck, it lights in [accent] and
/// glows; waited for ([next]), blue.
void _paintPads(ui.Canvas canvas, KeyboardLayout layout, Set<int> lit,
    Set<int> next, Color accent,
    {Map<int, String> letters = const {},
    Color face = _padFace,
    Color ink = _padInk}) {
  for (var (i, k) in layout.keys.indexed) {
    var on = lit.contains(k.key), wanted = next.contains(k.key);
    var rect = k.rect.deflate(math.min(1.5, k.rect.shortestSide * 0.03));
    var radius = Radius.circular(
        math.min(8.0, math.max(2.0, rect.shortestSide * 0.12)));
    var r = RRect.fromRectAndRadius(rect, radius);
    var family = padFamily(k.key);
    var fill = wanted
        ? const Color(0xFF3D7EFF)
        : on
            ? accent
            : face;
    // Struck: a glow round it first.
    if (on || wanted) {
      canvas.drawRRect(
          r.inflate(1.5),
          Paint()
            ..color = fill.withValues(alpha: 0.55)
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, rect.shortestSide * 0.08));
    }
    // Raised: lighter at the top, darker at its foot.
    canvas.drawRRect(
        r,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(fill, const Color(0xFFFFFFFF), on ? 0.18 : 0.07)!,
                Color.lerp(fill, const Color(0xFF000000), on ? 0.05 : 0.22)!,
              ]).createShader(rect));
    canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = on || wanted
              ? Color.lerp(fill, const Color(0xFFFFFFFF), 0.45)!
              : Color.lerp(face, const Color(0xFF000000), 0.35)!);
    // Its family, a band along its top.
    var band = math.max(2.0, rect.height * 0.06);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, band),
        Paint()..color = on ? const Color(0xCCFFFFFF) : family);
    canvas.restore();
    var lightInk = on || wanted ? const Color(0xFFFFFFFF) : ink;
    var pad = math.max(3.0, rect.shortestSide * 0.08);
    // The key that plays it, as a cap in its top corner.
    var letter = letters[k.key];
    var capped = false;
    if (letter != null && rect.height >= 22 && rect.width >= 26) {
      var size = (rect.shortestSide * 0.2).clamp(8.0, 12.0);
      var cap = TextPainter(
        text: TextSpan(
            text: letter,
            style: TextStyle(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: lightInk)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      var side = math.max(cap.width, cap.height) + 4;
      var box = Rect.fromLTWH(
          rect.right - pad - side, rect.top + band + pad * 0.6, side, side);
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()
            ..color = const Color(0xFF000000)
                .withValues(alpha: on ? 0.18 : 0.28));
      canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = lightInk.withValues(alpha: 0.45));
      cap.paint(canvas,
          box.center - Offset(cap.width / 2, cap.height / 2));
      capped = true;
    }
    // Its name, at its foot.
    var name = TextPainter(
      text: TextSpan(
          text: drumPads.elementAtOrNull(i)?.$2 ?? "",
          style: TextStyle(
              fontSize: (rect.height * 0.17).clamp(7.0, 12.0),
              fontWeight: FontWeight.w600,
              color: lightInk.withValues(alpha: on || wanted ? 1 : 0.85))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: math.max(0, rect.width - pad * 2));
    // Too short for both: the name only where the cap leaves room.
    if (capped && rect.height < name.height * 2 + band + pad * 2) continue;
    name.paint(
        canvas, Offset(rect.left + pad, rect.bottom - name.height - pad * 0.8));
  }
}

void _paintNeck(ui.Canvas canvas, KeyboardLayout layout, InstrumentPart part,
    Set<int> lit, Set<int> next, Color accent,
    [Map<int, FretPlace> placed = const {}]) {
  var board = layout.board;
  var strings =
      part.look == InstrumentLook.guitar ? guitarStrings : bassStrings;
  var nut = board.left + board.width * 0.06;
  canvas.drawRect(Rect.fromLTRB(nut, board.top, board.right, board.bottom),
      Paint()..color = const Color(0xFF5A3A22));
  // Inlays, where a neck has them.
  var band = board.height / strings.length;
  var dot = Paint()..color = const Color(0xFFE8DCC4);
  for (var f in const [3, 5, 7, 9, 12, 15]) {
    if (f > frets) continue;
    var x = (fretX(nut, board.right, f - 1) + fretX(nut, board.right, f)) / 2;
    var r = band * 0.16;
    if (f == 12) {
      canvas.drawCircle(Offset(x, board.top + board.height * 0.25), r, dot);
      canvas.drawCircle(Offset(x, board.top + board.height * 0.75), r, dot);
    } else {
      canvas.drawCircle(Offset(x, board.center.dy), r, dot);
    }
  }
  for (var f = 1; f <= frets; f++) {
    var x = fretX(nut, board.right, f);
    canvas.drawLine(Offset(x, board.top), Offset(x, board.bottom),
        Paint()
          ..color = const Color(0xFFB8B8B8)
          ..strokeWidth = 1.5);
  }
  canvas.drawRect(Rect.fromLTRB(nut - 3, board.top, nut, board.bottom),
      Paint()..color = const Color(0xFFEDE6D6));
  for (var (i, _) in strings.indexed) {
    var y = board.bottom - (i + 0.5) * band;
    canvas.drawLine(Offset(board.left, y), Offset(board.right, y),
        Paint()
          ..color = const Color(0xFFD9D4C8)
          ..strokeWidth = 1 + (strings.length - i) * 0.35);
  }
  // Where each note sounding is played: a finger on its fret, or a ring at
  // the nut for an open string -- where it was pressed, or as the part is
  // fingered; the rest placed together, as a hand would hold them.
  for (var (keys, colour) in [(lit, accent), (next, const Color(0xFF3D7EFF))]) {
    var own = {
      for (var k in keys)
        if (placed[k] case var p?) k: p
    };
    var rest = neckPlaces(keys.where((k) => !own.containsKey(k)), strings,
        busy: {for (var p in own.values) p.$1});
    for (var (string, fret) in [...own.values, ...rest]) {
      var y = board.bottom - (string + 0.5) * band;
      var x = fret == 0
          ? (board.left + nut) / 2
          : (fretX(nut, board.right, fret - 1) +
                  fretX(nut, board.right, fret)) /
              2;
      canvas.drawCircle(Offset(x, y), band * 0.32, Paint()..color = colour);
    }
  }
}
