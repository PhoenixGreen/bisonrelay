import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:flutter/painting.dart';

// instrument_painter.dart draws an instrument as the keyboard it is played
// on: its keys from the lowest to the highest the part says, those
// sounding lit -- the notes under the playhead, and any held down.
//
// The keys are laid out once, in keyboardLayout, and the stage presses the
// same rectangles the painter drew, as audio_painter.dart does for a
// speaker's controls.

/// KeyRect is one key: where it is, and whether it is a black one.
typedef KeyRect = ({int key, Rect rect, bool black});

/// KeyboardLayout is the keyboard inside an element's box: its name strip
/// along the top, and the keys under it.
class KeyboardLayout {
  final Rect title;
  final Rect board;
  final List<KeyRect> keys;
  const KeyboardLayout(this.title, this.board, this.keys);

  /// keyAt is the key under [p], a black one before the white under it, or
  /// null. [depth] is how far down the key it was pressed, nought to one --
  /// further down, harder.
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

/// keyboardLayout lays [part]'s keys out inside [bounds] -- or its pads, or
/// its strings and frets: whatever it is played on, a key a place.
KeyboardLayout keyboardLayout(InstrumentPart part, Rect bounds) {
  var inset = math.min(bounds.width, bounds.height) * 0.04;
  var inner = bounds.deflate(inset);
  var titleHeight = math.min(inner.height * 0.16, 22.0);
  var title = Rect.fromLTWH(inner.left, inner.top, inner.width, titleHeight);
  var board = Rect.fromLTRB(
      inner.left, inner.top + titleHeight, inner.right, inner.bottom);
  switch (part.look) {
    case InstrumentLook.drums:
      var gap = math.min(board.width, board.height) * 0.03;
      var w = (board.width - gap * 3) / 4, h = (board.height - gap * 3) / 4;
      return KeyboardLayout(title, board, [
        for (var (i, (key, _)) in drumPads.indexed)
          (
            key: key,
            rect: Rect.fromLTWH(board.left + (i % 4) * (w + gap),
                board.top + (i ~/ 4) * (h + gap), w, h),
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
    _paintNeck(canvas, layout, part, lit, next, accent);
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

void _paintPads(ui.Canvas canvas, KeyboardLayout layout, Set<int> lit,
    Set<int> next, Color accent) {
  for (var (i, k) in layout.keys.indexed) {
    var on = lit.contains(k.key), wanted = next.contains(k.key);
    var r = RRect.fromRectAndRadius(
        k.rect, Radius.circular(k.rect.shortestSide * 0.12));
    canvas.drawRRect(
        r,
        Paint()
          ..color = wanted
              ? const Color(0xFF3D7EFF)
              : on
                  ? accent
                  : const Color(0xFF2E3138));
    var name = TextPainter(
      text: TextSpan(
          text: drumPads[i].$2,
          style: TextStyle(
              fontSize: math.max(7, k.rect.height * 0.18),
              fontWeight: FontWeight.w600,
              color: on || wanted
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFFB8BDC6))),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: "…",
    )..layout(maxWidth: k.rect.width * 0.9);
    name.paint(
        canvas,
        Offset(k.rect.center.dx - name.width / 2,
            k.rect.bottom - name.height - k.rect.height * 0.08));
  }
}

void _paintNeck(ui.Canvas canvas, KeyboardLayout layout, InstrumentPart part,
    Set<int> lit, Set<int> next, Color accent) {
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
  // the nut for an open string.
  for (var (keys, colour) in [(lit, accent), (next, const Color(0xFF3D7EFF))]) {
    for (var key in keys) {
      var at = fretFor(key, strings);
      if (at == null) continue;
      var (string, fret) = at;
      var y = board.bottom - (string + 0.5) * band;
      var x = fret == 0
          ? (board.left + nut) / 2
          : (fretX(nut, board.right, fret - 1) + fretX(nut, board.right, fret)) /
              2;
      canvas.drawCircle(Offset(x, y), band * 0.32, Paint()..color = colour);
    }
  }
}
