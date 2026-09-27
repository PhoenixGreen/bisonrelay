import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart'
    show BackgroundRemoval;
import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:flutter/painting.dart';

// audio_painter.dart draws an Audio element: its icon in whichever state the
// sound is in, and the mute switch and volume bar beside it when it has them.
//
// The layout is worked out once, in audioParts, and the stage presses the same
// rectangles the painter drew -- a second opinion about where the volume bar
// is would be a bar that sets the volume from somewhere slightly to its left.

/// AudioState is what the painter needs to know about the sound. Nothing in
/// the document says it: in an exported picture it is the idle state the
/// author set up, and on screen it is whatever the reader has done.
class AudioState {
  final bool playing;
  final bool muted;
  final double volume;

  const AudioState({this.playing = false, this.muted = false, this.volume = 1});

  factory AudioState.idle(AudioElement e) =>
      AudioState(muted: e.clip.muted, volume: e.clip.volume);
}

/// AudioParts is where each piece of the element is, in document units.
class AudioParts {
  final Rect icon;
  final Rect? mute;

  /// volume is the whole bar, which is what is pressed; the track drawn is a
  /// thinner line through its middle.
  final Rect? volume;

  const AudioParts(this.icon, this.mute, this.volume);
}

/// audioParts lays out [e] inside [bounds].
///
/// The icon is a square as tall as the room inside the box. With nothing
/// beside it, it is centred -- a speaker on its own is a round button, not a
/// button pushed into the corner of an empty pill.
AudioParts audioParts(AudioElement e, Rect bounds) {
  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) {
    return AudioParts(inner, null, null);
  }
  var side = math.min(inner.height, inner.width);
  var beside = e.has(AudioControl.mute) || e.has(AudioControl.volume);
  if (!beside) {
    return AudioParts(
        Rect.fromCenter(center: inner.center, width: side, height: side),
        null,
        null);
  }

  var icon = Rect.fromLTWH(inner.left, inner.center.dy - side / 2, side, side);
  var gap = side * 0.25;
  var x = icon.right + gap;
  Rect? mute;
  if (e.has(AudioControl.mute) && x + side * 0.7 <= inner.right) {
    var s = side * 0.7;
    mute = Rect.fromLTWH(x, inner.center.dy - s / 2, s, s);
    x = mute.right + gap;
  }
  Rect? volume;
  if (e.has(AudioControl.volume) && inner.right - x > side * 0.5) {
    // As tall as the icon to press, however thin it is drawn: a bar a few
    // pixels high is a bar nobody can hit.
    volume = Rect.fromLTRB(x, icon.top, inner.right, icon.bottom);
  }
  return AudioParts(icon, mute, volume);
}

/// volumeAt is the volume a press at [x] on [bar] asks for.
double volumeAt(Rect bar, double x) {
  var inset = bar.height * 0.2;
  var from = bar.left + inset, to = bar.right - inset;
  if (to <= from) return 1;
  return ((x - from) / (to - from)).clamp(0.0, 1.0);
}

void paintAudio(ui.Canvas canvas, Rect bounds, AudioElement e, AudioState state,
    {CanvasImageSource? images}) {
  paintBox(canvas, bounds, e.box, images);
  var parts = audioParts(e, bounds);
  if (parts.icon.width <= 0) return;

  var picture = state.muted && e.mutedPicture.isNotEmpty
      ? e.mutedPicture
      : !state.playing && e.pausedPicture.isNotEmpty
          ? e.pausedPicture
          : e.picture;
  var drawnPicture =
      picture.isNotEmpty && _paintPicture(canvas, parts.icon, picture, images);
  if (!drawnPicture) {
    _paintGlyph(canvas, parts.icon.deflate(parts.icon.width * 0.18), e, state);
  }
  // A picture of the reader's own for "muted" says so itself. Without one, a
  // picture is struck through like the drawn icons are.
  if (state.muted && (drawnPicture ? e.mutedPicture.isEmpty : false)) {
    _strike(canvas, parts.icon.deflate(parts.icon.width * 0.15), e);
  }

  if (parts.mute case var m?) _paintMute(canvas, m, e, state);
  if (parts.volume case var v?) _paintVolume(canvas, v, e, state);
}

/// _paintGlyph draws the built-in icon for [e] in [r].
void _paintGlyph(ui.Canvas canvas, Rect r, AudioElement e, AudioState state) {
  var on = state.playing;
  var ink = on ? e.accent : e.iconColor;
  var fill = Paint()..color = ink;
  var line = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = r.width * 0.09
    ..strokeCap = StrokeCap.round;
  Offset p(double x, double y) =>
      Offset(r.left + r.width * x, r.top + r.height * y);

  switch (e.glyph) {
    case AudioGlyph.speaker:
      // The box and cone in the icon colour whatever the state: it is the
      // waves that say whether anything is coming out of it.
      canvas.drawPath(
          Path()
            ..moveTo(p(0.05, 0.36).dx, p(0.05, 0.36).dy)
            ..lineTo(p(0.25, 0.36).dx, p(0.25, 0.36).dy)
            ..lineTo(p(0.5, 0.12).dx, p(0.5, 0.12).dy)
            ..lineTo(p(0.5, 0.88).dx, p(0.5, 0.88).dy)
            ..lineTo(p(0.25, 0.64).dx, p(0.25, 0.64).dy)
            ..lineTo(p(0.05, 0.64).dx, p(0.05, 0.64).dy)
            ..close(),
          Paint()..color = e.iconColor);
      if (state.muted) {
        var cross = Paint()
          ..color = e.iconColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = r.width * 0.08
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p(0.64, 0.36), p(0.92, 0.64), cross);
        canvas.drawLine(p(0.92, 0.36), p(0.64, 0.64), cross);
        return;
      }
      // One, two or three waves by how loud it is, so the icon answers "how
      // loud" as well as "is it on".
      var waves = state.volume <= 0
          ? 0
          : state.volume < 0.34
              ? 1
              : state.volume < 0.67
                  ? 2
                  : 3;
      var wave = Paint()
        ..color = on ? e.accent : e.iconColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r.width * 0.07
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < waves; i++) {
        var reach = r.width * (0.18 + 0.14 * i);
        canvas.drawArc(Rect.fromCircle(center: p(0.5, 0.5), radius: reach),
            -math.pi / 4, math.pi / 2, false, wave);
      }
    case AudioGlyph.note:
      canvas.drawOval(
          Rect.fromCenter(
              center: p(0.3, 0.78),
              width: r.width * 0.3,
              height: r.height * 0.22),
          fill);
      canvas.drawOval(
          Rect.fromCenter(
              center: p(0.78, 0.66),
              width: r.width * 0.3,
              height: r.height * 0.22),
          fill);
      line.strokeWidth = r.width * 0.07;
      canvas.drawLine(p(0.43, 0.76), p(0.43, 0.16), line);
      canvas.drawLine(p(0.91, 0.64), p(0.91, 0.06), line);
      canvas.drawPath(
          Path()
            ..moveTo(p(0.43, 0.16).dx, p(0.43, 0.16).dy)
            ..lineTo(p(0.91, 0.06).dx, p(0.91, 0.06).dy)
            ..lineTo(p(0.91, 0.2).dx, p(0.91, 0.2).dy)
            ..lineTo(p(0.43, 0.3).dx, p(0.43, 0.3).dy)
            ..close(),
          fill);
      if (state.muted) _strike(canvas, r, e);
    case AudioGlyph.headphones:
      canvas.drawArc(
          Rect.fromLTRB(p(0.08, 0.1).dx, p(0.08, 0.1).dy, p(0.92, 0.9).dx,
              p(0.92, 0.9).dy),
          math.pi,
          math.pi,
          false,
          line);
      for (var x in [0.06, 0.72]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(
                    p(x, 0.5).dx, p(x, 0.5).dy, r.width * 0.22, r.height * 0.4),
                Radius.circular(r.width * 0.06)),
            fill);
      }
      if (state.muted) _strike(canvas, r, e);
    case AudioGlyph.mic:
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(p(0.34, 0.04).dx, p(0.34, 0.04).dy, p(0.66, 0.6).dx,
                  p(0.66, 0.6).dy),
              Radius.circular(r.width * 0.16)),
          fill);
      canvas.drawArc(
          Rect.fromLTRB(
              p(0.2, 0.2).dx, p(0.2, 0.2).dy, p(0.8, 0.74).dx, p(0.8, 0.74).dy),
          0,
          math.pi,
          false,
          line);
      canvas.drawLine(p(0.5, 0.74), p(0.5, 0.94), line);
      canvas.drawLine(p(0.32, 0.94), p(0.68, 0.94), line);
      if (state.muted) _strike(canvas, r, e);
    case AudioGlyph.play:
      // The one glyph that says what pressing it will do rather than what it
      // is: a triangle to start, two bars to stop.
      if (on) {
        for (var x in [0.18, 0.58]) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(p(x, 0.1).dx, p(x, 0.1).dy, r.width * 0.24,
                      r.height * 0.8),
                  Radius.circular(r.width * 0.05)),
              fill);
        }
      } else {
        canvas.drawPath(
            Path()
              ..moveTo(p(0.2, 0.08).dx, p(0.2, 0.08).dy)
              ..lineTo(p(0.92, 0.5).dx, p(0.92, 0.5).dy)
              ..lineTo(p(0.2, 0.92).dx, p(0.2, 0.92).dy)
              ..close(),
            fill);
      }
      if (state.muted) _strike(canvas, r, e);
  }
}

/// _strike draws the line through a muted icon, with a gap either side of it
/// in the box's own colour so it reads against the icon it crosses.
void _strike(ui.Canvas canvas, Rect r, AudioElement e) {
  var from = r.topLeft, to = r.bottomRight;
  if (e.box.fill.a > 0) {
    canvas.drawLine(
        from,
        to,
        Paint()
          ..color = e.box.fill
          ..strokeWidth = r.width * 0.2
          ..strokeCap = StrokeCap.round);
  }
  canvas.drawLine(
      from,
      to,
      Paint()
        ..color = e.iconColor
        ..strokeWidth = r.width * 0.08
        ..strokeCap = StrokeCap.round);
}

void _paintMute(ui.Canvas canvas, Rect r, AudioElement e, AudioState state) {
  var ring = Paint()
    ..color = state.muted ? e.accent : e.iconColor.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = r.width * 0.07;
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          r.deflate(r.width * 0.04), Radius.circular(r.width * 0.25)),
      ring);
  _paintGlyph(
      canvas,
      r.deflate(r.width * 0.22),
      AudioElement(e.base,
          glyph: AudioGlyph.speaker,
          iconColor: e.iconColor,
          accent: e.accent,
          box: e.box),
      AudioState(muted: state.muted, volume: state.volume));
}

void _paintVolume(
    ui.Canvas canvas, Rect bar, AudioElement e, AudioState state) {
  var thick = math.max(2.0, bar.height * 0.14);
  var inset = bar.height * 0.2;
  var from = Offset(bar.left + inset, bar.center.dy);
  var to = Offset(bar.right - inset, bar.center.dy);
  var track = Paint()
    ..color = e.iconColor.withValues(alpha: 0.3)
    ..strokeWidth = thick
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(from, to, track);
  var level = state.muted ? 0.0 : state.volume.clamp(0.0, 1.0);
  var at = Offset.lerp(from, to, state.volume.clamp(0.0, 1.0))!;
  if (level > 0) {
    canvas.drawLine(
        from,
        Offset.lerp(from, to, level)!,
        Paint()
          ..color = e.accent
          ..strokeWidth = thick
          ..strokeCap = StrokeCap.round);
  }
  canvas.drawCircle(at, bar.height * 0.2, Paint()..color = e.iconColor);
}

/// _paintPicture draws a stored picture contained in [r], the drawing where
/// it is one. False where there is nothing to draw yet.
bool _paintPicture(
    ui.Canvas canvas, Rect r, String id, CanvasImageSource? images) {
  var vector = images?.resolveVector(id);
  if (vector != null && !_usable(vector.size)) vector = null;
  var bitmap =
      vector == null ? images?.resolve(id, const BackgroundRemoval()) : null;
  if (vector == null && bitmap == null) return false;
  var size =
      vector?.size ?? Size(bitmap!.width.toDouble(), bitmap.height.toDouble());
  if (!_usable(size)) return false;
  var scale = math.min(r.width / size.width, r.height / size.height);
  var at = Rect.fromCenter(
      center: r.center, width: size.width * scale, height: size.height * scale);
  if (vector != null) {
    canvas.save();
    canvas.translate(at.left, at.top);
    canvas.scale(scale, scale);
    canvas.drawPicture(vector.picture);
    canvas.restore();
  } else {
    canvas.drawImageRect(bitmap!, Offset.zero & size, at,
        Paint()..filterQuality = FilterQuality.medium);
  }
  return true;
}

bool _usable(Size s) =>
    s.width.isFinite && s.height.isFinite && s.width > 0 && s.height > 0;
