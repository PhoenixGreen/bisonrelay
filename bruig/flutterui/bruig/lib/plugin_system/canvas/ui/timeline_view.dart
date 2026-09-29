import 'dart:math' as math;

import 'package:flutter/gestures.dart';

// timeline_view.dart is which stretch of frames the timeline is showing.
//
// One of these is shared by the keyframe strip and every channel under it.
// Each used to turn frames into pixels on its own, across its own width --
// which could only ever agree while both showed the whole timeline at the
// same width. Zooming, and a column of channel names down the left, would
// each have pulled them out of step; one view that every conversion goes
// through keeps a keyframe and the sound it is timed to on the same line.

/// timelineMinSpan is the fewest frames the timeline zooms in to. Closer than
/// this a frame is wider than anything drawn on it.
const double timelineMinSpan = 8;

/// TimelineView is the frames from [first] across [span] of them.
class TimelineView {
  /// first is the frame at the left edge, fractional while zooming.
  final double first;

  /// span is how many frames the width holds.
  final double span;

  const TimelineView(this.first, this.span);

  /// whole is every frame of a timeline [frames] long.
  factory TimelineView.whole(int frames) =>
      TimelineView(0, math.max(1, frames).toDouble());

  /// isWhole is whether this shows all of a timeline [frames] long.
  bool isWhole(int frames) => first <= 0.001 && span >= frames - 0.001;

  /// xOf is where [frame] -- its left edge -- is across [width].
  double xOf(num frame, double width) =>
      span <= 0 ? 0 : (frame - first) / span * width;

  /// centreOf is the middle of [frame], where its mark is drawn.
  double centreOf(int frame, double width) => xOf(frame + 0.5, width);

  /// frameAt is the frame under [x], clamped to the timeline.
  int frameAt(double x, double width, int frames) {
    if (frames <= 1 || width <= 0) return 0;
    return (first + x / width * span).floor().clamp(0, frames - 1).toInt();
  }

  /// framesPer is how many frames [pixels] is, for a drag.
  double framesPer(double pixels, double width) =>
      width <= 0 ? 0 : pixels / width * span;

  /// fitted is this view kept inside a timeline [frames] long: never wider
  /// than all of it, never narrower than [timelineMinSpan], never past either
  /// end.
  TimelineView fitted(int frames) {
    var total = math.max(1, frames).toDouble();
    var least = math.min(timelineMinSpan, total);
    var s = span.clamp(least, total).toDouble();
    var f = first.clamp(0.0, math.max(0.0, total - s)).toDouble();
    return TimelineView(f, s);
  }

  /// zoomed is closer in by [factor] (below one zooms out), keeping the
  /// frame at [around] under the same place on screen.
  TimelineView zoomed(double factor, double around, int frames) {
    if (factor <= 0) return this;
    var s = span / factor;
    var share = span <= 0 ? 0.5 : (around - first) / span;
    return TimelineView(around - share * s, s).fitted(frames);
  }

  /// scrolled is moved along by [frames] frames.
  TimelineView scrolled(double by, int frames) =>
      TimelineView(first + by, span).fitted(frames);

  /// following is this view moved on, a page at a time, so that [frame] is on
  /// screen: what playback does, so the playhead is never off the end.
  TimelineView following(int frame, int frames) {
    if (frame >= first && frame + 1 <= first + span) return this;
    return TimelineView(frame - span * 0.1, span).fitted(frames);
  }

  @override
  bool operator ==(Object other) =>
      other is TimelineView && other.first == first && other.span == span;

  @override
  int get hashCode => Object.hash(first, span);
}

/// timelinePointers is what may press, drag and scrub on the timeline: the
/// mouse and a finger, not the trackpad. Two fingers on a trackpad are how
/// somebody scrolls the channels up and down, and a drag recognizer takes a
/// trackpad's pan as a drag -- so a swipe over the strip scrubbed the
/// playhead, and one over a sound dragged the sound.
const Set<PointerDeviceKind> timelinePointers = {
  PointerDeviceKind.mouse,
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.unknown,
};
