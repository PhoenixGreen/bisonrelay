import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:flutter/painting.dart';

// video_painter.dart draws what sits over a video: the big play button, the
// play bar, the time, the mute switch and the volume bar. The picture itself
// is drawn by the image painter -- see _paintVideo in scene_renderer.dart.
//
// The layout is worked out once, in videoParts, and the stage presses the
// same rectangles the painter drew. See audio_painter.dart, which is the same
// arrangement for a speaker.

/// VideoShow is what the painter needs to know about a video right now.
/// Nothing in the document says it: in an exported picture it is the poster
/// and a stopped play bar, and on screen it is whatever the reader has done.
class VideoShow {
  final bool playing;
  final bool muted;
  final double volume;

  /// position is seconds into the file, and start and end the range.
  final double position;
  final double start;
  final double end;

  /// frame is the picture to draw, or null for the poster.
  final ui.Image? frame;

  /// poster is the still of the file that is current, when no frame is.
  final String poster;

  final double opacity;

  /// hidden is a video on the timeline with the playhead outside its span:
  /// not drawn at all, the way a clip is not in a film before it is cut in.
  final bool hidden;

  const VideoShow({
    this.playing = false,
    this.muted = false,
    this.volume = 1,
    this.position = 0,
    this.start = 0,
    this.end = 0,
    this.frame,
    this.poster = "",
    this.opacity = 1,
    this.hidden = false,
  });

  factory VideoShow.idle(VideoElement e) {
    var first = e.clip.playlist.isEmpty ? null : e.clip.playlist.first;
    return VideoShow(
      muted: e.clip.muted,
      volume: e.clip.volume,
      start: first?.start ?? 0,
      end: first == null ? 0 : first.endOr(first.length),
      position: first?.start ?? 0,
      poster: first?.posterId ?? "",
    );
  }

  double get through =>
      end > start ? ((position - start) / (end - start)).clamp(0.0, 1.0) : 0;
}

/// VideoPart is which part of a video a press landed on.
enum VideoPart { picture, bigPlay, playPause, track, mute, volume }

/// videoPartAt is which of [parts] [at] is on, controls before the picture,
/// or null for none. [clickable] is whether the picture itself answers.
VideoPart? videoPartAt(VideoParts parts, Offset at, {required bool clickable}) {
  if (parts.bigPlay case var r? when r.contains(at)) return VideoPart.bigPlay;
  if (parts.playPause case var r? when r.contains(at)) {
    return VideoPart.playPause;
  }
  if (parts.track case var r? when r.contains(at)) return VideoPart.track;
  if (parts.mute case var r? when r.contains(at)) return VideoPart.mute;
  if (parts.volume case var r? when r.contains(at)) return VideoPart.volume;
  // A press on the bar that missed every control is not a press on the
  // picture: somebody aiming at a small button and missing should not stop
  // the video instead.
  if (parts.bar case var r? when r.contains(at)) return null;
  if (clickable && parts.picture.contains(at)) return VideoPart.picture;
  return null;
}

/// VideoParts is where each control is, in document units. Null for one the
/// video does not have, or has no room for.
class VideoParts {
  final Rect picture;
  final Rect? bigPlay;
  final Rect? bar;
  final Rect? playPause;
  final Rect? time;
  final Rect? track;
  final Rect? mute;
  final Rect? volume;

  const VideoParts(this.picture,
      {this.bigPlay,
      this.bar,
      this.playPause,
      this.time,
      this.track,
      this.mute,
      this.volume});
}

/// videoParts lays out [e]'s controls over its picture.
VideoParts videoParts(VideoElement e, Rect bounds) {
  var picture = e.look.box.inner(bounds);
  if (picture.width <= 0 || picture.height <= 0) return VideoParts(picture);

  // A link has one thing to press: it opens the video.
  var side = picture.shortestSide * 0.24;
  var big = Rect.fromCenter(center: picture.center, width: side, height: side);
  if (e.isLink) return VideoParts(picture, bigPlay: big);
  // On the timeline the playhead is its control, and it has no other.
  if (e.clip.timed) return VideoParts(picture);

  var wantsBar = e.has(VideoControl.playbar) ||
      e.has(VideoControl.time) ||
      e.has(VideoControl.mute) ||
      e.has(VideoControl.volume);
  if (!wantsBar) {
    return VideoParts(picture,
        bigPlay: e.has(VideoControl.playButton) ? big : null);
  }

  var h = math.max(picture.height * 0.11, picture.shortestSide * 0.08);
  var bar = Rect.fromLTWH(picture.left, picture.bottom - h, picture.width, h);
  var pad = h * 0.25;
  var left = bar.left + pad, right = bar.right - pad;

  Rect? playPause, time, track, mute, volume;
  if (e.has(VideoControl.playbar)) {
    playPause = Rect.fromLTWH(left, bar.top, h, h);
    left += h + pad;
  }
  if (e.has(VideoControl.time) && right - left > h * 3.4) {
    time = Rect.fromLTWH(left, bar.top, h * 3.2, h);
    left += h * 3.2 + pad;
  }
  if (e.has(VideoControl.volume) && right - left > h * 2.6) {
    volume = Rect.fromLTRB(right - h * 2.4, bar.top, right, bar.bottom);
    right -= h * 2.4 + pad;
  }
  if (e.has(VideoControl.mute) && right - left > h) {
    mute = Rect.fromLTRB(right - h, bar.top, right, bar.bottom);
    right -= h + pad;
  }
  if (e.has(VideoControl.playbar) && right - left > h) {
    track = Rect.fromLTRB(left, bar.top, right, bar.bottom);
  }
  return VideoParts(picture,
      bigPlay: e.has(VideoControl.playButton) ? big : null,
      bar: bar,
      playPause: playPause,
      time: time,
      track: track,
      mute: mute,
      volume: volume);
}

/// alongBar is how far along a bar a press at [x] is, nought to one.
double alongBar(Rect bar, double x) {
  var inset = bar.height * 0.3;
  var from = bar.left + inset, to = bar.right - inset;
  if (to <= from) return 0;
  return ((x - from) / (to - from)).clamp(0.0, 1.0);
}

/// clockText is seconds as a reader reads them: 1:05, or 1:02:05.
String clockText(double seconds) {
  var s = seconds.isFinite ? math.max(0, seconds).floor() : 0;
  var h = s ~/ 3600, m = (s ~/ 60) % 60, sec = s % 60;
  var ss = sec.toString().padLeft(2, "0");
  return h > 0 ? "$h:${m.toString().padLeft(2, "0")}:$ss" : "$m:$ss";
}

void paintVideoControls(
    ui.Canvas canvas, VideoElement e, VideoParts parts, VideoShow show) {
  const ink = Color(0xFFFFFFFF);

  // The big button only while stopped: over a playing picture it is a hole
  // in the middle of the thing being watched.
  if (parts.bigPlay case var big? when e.isLink || !show.playing) {
    canvas.drawOval(big, Paint()..color = const Color(0x8C000000));
    _triangle(canvas, big.deflate(big.width * 0.3), ink);
  }

  if (e.isLink) {
    _hostLabel(canvas, parts.picture, VideoHost.of(e.link).label);
    return;
  }

  var bar = parts.bar;
  if (bar == null) return;
  canvas.drawRect(
      Rect.fromLTRB(
          bar.left, bar.top - bar.height * 0.6, bar.right, bar.bottom),
      Paint()
        ..shader = ui.Gradient.linear(
            Offset(0, bar.top - bar.height * 0.6),
            Offset(0, bar.bottom),
            [const Color(0x00000000), const Color(0x99000000)]));

  if (parts.playPause case var r?) {
    var glyph = r.deflate(r.width * 0.28);
    if (show.playing) {
      var w = glyph.width * 0.32;
      for (var x in [glyph.left, glyph.right - w]) {
        canvas.drawRect(
            Rect.fromLTWH(x, glyph.top, w, glyph.height), Paint()..color = ink);
      }
    } else {
      _triangle(canvas, glyph, ink);
    }
  }

  if (parts.time case var r?) {
    var text = "${clockText(show.position - show.start)} / "
        "${clockText(show.end - show.start)}";
    var painter = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: ink,
              fontSize: r.height * 0.36,
              fontFeatures: const [ui.FontFeature.tabularFigures()])),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: r.width);
    painter.paint(canvas, Offset(r.left, r.center.dy - painter.height / 2));
    painter.dispose();
  }

  if (parts.track case var r?) {
    _slider(canvas, r, show.through, show.through, e.accent);
  }

  if (parts.mute case var r?) {
    _speaker(canvas, r.deflate(r.width * 0.24), show.muted, ink);
  }

  if (parts.volume case var r?) {
    _slider(canvas, r, show.muted ? 0 : show.volume, show.volume, e.accent);
  }
}

void _triangle(ui.Canvas canvas, Rect r, Color color) {
  canvas.drawPath(
      Path()
        ..moveTo(r.left + r.width * 0.12, r.top)
        ..lineTo(r.right, r.center.dy)
        ..lineTo(r.left + r.width * 0.12, r.bottom)
        ..close(),
      Paint()..color = color);
}

/// _slider draws a bar with [filled] of it in the accent and the knob at
/// [knob].
void _slider(
    ui.Canvas canvas, Rect r, double filled, double knob, Color accent) {
  var thick = math.max(1.5, r.height * 0.1);
  var inset = r.height * 0.3;
  var from = Offset(r.left + inset, r.center.dy);
  var to = Offset(r.right - inset, r.center.dy);
  canvas.drawLine(
      from,
      to,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round);
  if (filled > 0) {
    canvas.drawLine(
        from,
        Offset.lerp(from, to, filled.clamp(0.0, 1.0))!,
        Paint()
          ..color = accent
          ..strokeWidth = thick
          ..strokeCap = StrokeCap.round);
  }
  canvas.drawCircle(Offset.lerp(from, to, knob.clamp(0.0, 1.0))!,
      r.height * 0.16, Paint()..color = const Color(0xFFFFFFFF));
}

void _speaker(ui.Canvas canvas, Rect r, bool muted, Color ink) {
  Offset p(double x, double y) =>
      Offset(r.left + r.width * x, r.top + r.height * y);
  canvas.drawPath(
      Path()
        ..moveTo(p(0.05, 0.35).dx, p(0.05, 0.35).dy)
        ..lineTo(p(0.28, 0.35).dx, p(0.28, 0.35).dy)
        ..lineTo(p(0.55, 0.1).dx, p(0.55, 0.1).dy)
        ..lineTo(p(0.55, 0.9).dx, p(0.55, 0.9).dy)
        ..lineTo(p(0.28, 0.65).dx, p(0.28, 0.65).dy)
        ..lineTo(p(0.05, 0.65).dx, p(0.05, 0.65).dy)
        ..close(),
      Paint()..color = ink);
  var line = Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = r.width * 0.09
    ..strokeCap = StrokeCap.round;
  if (muted) {
    canvas.drawLine(p(0.68, 0.36), p(0.95, 0.64), line);
    canvas.drawLine(p(0.95, 0.36), p(0.68, 0.64), line);
  } else {
    canvas.drawArc(
        Rect.fromCircle(center: p(0.55, 0.5), radius: r.width * 0.28),
        -math.pi / 4,
        math.pi / 2,
        false,
        line);
  }
}

/// _hostLabel says where a linked video lives, in the corner of its poster,
/// so a reader knows pressing it leaves the canvas for somewhere else.
void _hostLabel(ui.Canvas canvas, Rect picture, String host) {
  var size = math.max(8.0, picture.shortestSide * 0.07);
  var painter = TextPainter(
    text: TextSpan(
        text: host,
        style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: size,
            fontWeight: FontWeight.w600)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: picture.width * 0.8);
  var pad = size * 0.5;
  var chip = Rect.fromLTWH(picture.left + pad, picture.top + pad,
      painter.width + pad * 2, painter.height + pad);
  canvas.drawRRect(RRect.fromRectAndRadius(chip, Radius.circular(pad)),
      Paint()..color = const Color(0x99000000));
  painter.paint(canvas, Offset(chip.left + pad, chip.top + pad / 2));
  painter.dispose();
}
