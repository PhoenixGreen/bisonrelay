part of '../canvas_controller.dart';

// Keyframes, and the arrivals and exits laid on them.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasKeyframes on CanvasController {
  /// setKeyframe writes the pose at the current frame for one element.
  void setKeyframe(String id, Keyframe key) {
    var element = _document.elementById(id);
    if (element == null) return;
    // Whatever that frame already pinned is kept: a keyframe holds the pose
    // and any channels (a counter's number, a chart's arrival), and writing a
    // pose over it wholesale would throw the channels away.
    var was = element.track?.keyAt(key.frame);
    var merged = was == null || was.values.isEmpty
        ? key
        : key.copyWith(values: {...was.values, ...key.values});
    var track = (element.track ?? ElementTrack.empty).withKey(merged);
    replaceElement(element.withBase(track: track));
  }

  /// applyChartAnimation puts a preset on a chart and lays the two keyframes
  /// that give it a length: one gesture, since a preset with no keyframes
  /// draws nothing different. The keyframes are ordinary ones, so the
  /// animation's length is the gap between them, dragged like anything else.
  ///
  /// A still document is given a second's worth of frames first. [length] is
  /// how many frames it takes, and overrules everything else; left out, it
  /// comes from the animation's own Length setting where one has been asked
  /// for, and otherwise from where the keyframes already are, so trying one
  /// preset after another leaves the timing alone. See applyTextAnimation,
  /// which follows the same rules.
  void applyChartAnimation(ChartElement element, ChartAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == ChartAnimationPreset.none) {
      // The reveal keyframes go with it and nothing else does: a chart moved
      // or faded by hand keeps that when None is chosen.
      replaceElement(withoutOwn(
          element.copyWith(
              animation: element.animation.copyWith(preset: preset)),
          MotionKind.arrive));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere; otherwise from this frame, so
    // the playhead does not jump.
    var (was, wasFor) = elementAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    var next = withOwnSpan(
        element.copyWith(animation: element.animation.copyWith(preset: preset)),
        MotionKind.arrive,
        from,
        to,
        document.frameRate);
    apply(document.withElement(next));
    endInteraction();
  }

  /// applyTextAnimation puts a preset on a text element and lays the two
  /// keyframes that give it a length. The same channels, stagger and
  /// timeline as applyChartAnimation, which it mirrors, so a headline and a
  /// chart arriving together arrive together.
  ///
  /// [length] is how many frames it takes, and overrules everything else:
  /// zero means the usual two seconds, and it is what the Length setting
  /// passes. Left out, it comes from the animation's own Length setting where
  /// one has been asked for, and otherwise from where the keyframes already
  /// are.
  void applyTextAnimation(TextElement element, TextAnimationPreset preset,
      {int? length}) {
    beginInteraction();

    if (preset == TextAnimationPreset.none) {
      replaceElement(withoutOwn(
          element.copyWith(
              animation: element.animation.copyWith(preset: preset)),
          MotionKind.arrive));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    // Where it already is, if it is anywhere: choosing a different preset
    // keeps the length that has been set.
    var (was, wasFor) = textAnimationSpan(element);
    var from = was ?? _frame.clamp(0, document.frames - 2);
    // Whatever is already on the timeline wins: trying the next preset must
    // not shove laid-down keyframes about. The Length setting is for laying a
    // new one down (as after the keyframes have been deleted).
    var span = wasFor ??
        length ??
        (element.animation.length > 0
            ? element.animation.length
            : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    apply(document.withElement(withOwnSpan(
        element.copyWith(
            animation: element.animation.copyWith(
                preset: preset,
                // The curve and cutting the preset was designed around, only
                // where the preset is actually changing, so re-laying the
                // keyframes does not undo numbers somebody chose. See
                // TextAnimationPreset.wants and its effect.
                ease: preset == element.animation.preset ? null : preset.wants,
                effect:
                    preset == element.animation.preset ? null : preset.effect)),
        MotionKind.arrive,
        from,
        to,
        document.frameRate)));
    endInteraction();
  }

  /// textAnimationSpan is where [element]'s arrival sits on the timeline: the
  /// frame it starts on and how many frames it takes, or nulls where it has
  /// no keyframes yet. Read from the keyframes, which can be dragged, rather
  /// than a number kept beside them that would go stale.
  (int?, int?) textAnimationSpan(TextElement element) =>
      switch (ownSpan(element, MotionKind.arrive, _document.frameRate)) {
        (var from, var length) => (from, length),
        null => (null, null),
      };

  /// defaultAnimationFrames is how long an animation runs for when nobody
  /// has said: the same two seconds a chart's uses.
  int get defaultAnimationFrames =>
      math.max(2, (_document.frameRate * chartAnimationSeconds).round());

  /// setElementLoop gives [element] [loop] -- [transient] while a drag on
  /// its bar is still making it. See ElementLoop.
  void setElementLoop(CanvasElement element, ElementLoop loop,
      {bool transient = false}) {
    // Words and charts keep theirs in animations of their own.
    if (element is TextElement) {
      replaceElement(
          element.copyWith(animation: element.animation.copyWith(loop: loop)),
          transient: transient);
      return;
    }
    if (element is ChartElement) {
      replaceElement(
          element.copyWith(animation: element.animation.copyWith(loop: loop)),
          transient: transient);
      return;
    }
    if (!CanvasController.animates(element)) return;
    var was = CanvasController.elementAnimationOf(element);
    replaceElement(
        CanvasController._withElementAnimation(
            element, was.copyWith(loop: loop)),
        transient: transient);
  }

  /// applyElementAnimation puts an arrival on a shape or a picture and lays
  /// the pair of keyframes that runs it, by the rules of
  /// [applyTextAnimation]: whatever is already laid down wins, the Length
  /// setting is for laying a new one down, and None takes the keyframes away.
  void applyElementAnimation(
      CanvasElement element, ElementAnimationPreset preset,
      {int? length}) {
    if (!CanvasController.animates(element)) return;
    beginInteraction();
    var was = CanvasController.elementAnimationOf(element);

    if (preset == ElementAnimationPreset.none) {
      replaceElement(withoutOwn(
          CanvasController._withElementAnimation(
              element, was.copyWith(preset: preset)),
          MotionKind.arrive));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds));
    }

    var (wasAt, wasFor) = elementAnimationSpan(element);
    var from = wasAt ?? _frame.clamp(0, document.frames - 2);
    var span = wasFor ??
        length ??
        (was.length > 0 ? was.length : defaultAnimationFrames);
    span = math.max(1, span == 0 ? defaultAnimationFrames : span);
    if (document.frames - 1 < from + span) {
      document = document.copyWith(frames: from + span + 1);
    }
    var to = from + span;
    if (to <= from) {
      from = 0;
      to = document.frames - 1;
    }

    // The preset's own curve and way of cutting, only where the preset is
    // actually changing, so re-laying the keyframes does not undo numbers
    // somebody set. Build up and Break apart differ only in these.
    var changing = preset != was.preset;
    apply(document.withElement(withOwnSpan(
        CanvasController._withElementAnimation(
            element,
            was.copyWith(
                preset: preset,
                ease: changing ? preset.wants : null,
                effect: changing ? preset.effect : null)),
        MotionKind.arrive,
        from,
        to,
        document.frameRate)));
    endInteraction();
  }

  /// elementAnimationSpan is where [element]'s arrival sits on the timeline:
  /// the frame it starts on and how many frames it takes. See
  /// textAnimationSpan, which reads the same channel for the same reasons.
  (int?, int?) elementAnimationSpan(CanvasElement element) =>
      switch (ownSpan(element, MotionKind.arrive, _document.frameRate)) {
        (var from, var length) => (from, length),
        null => (null, null),
      };

  /// anchorShown is whether [id]'s anchor point is drawn on the stage, where
  /// it can be dragged unless it is locked. A way of looking rather than
  /// part of the design: not saved, and not undone.
  bool anchorShown(String id) => _anchorsShown.contains(id);

  void showAnchor(String id, bool shown) {
    if (shown ? !_anchorsShown.add(id) : !_anchorsShown.remove(id)) return;
    notifyListeners();
  }

  /// setElementArrivalTiming moves [element]'s arrival on the timeline: to
  /// start [delay] frames into the scene, and to take [length] frames --
  /// either or both, the other left where it is. The scene grows to hold it.
  /// Part of whatever change is under way: the caller begins and ends it.
  void setElementArrivalTiming(CanvasElement element,
      {int? delay, int? length}) {
    var (at, span) = elementAnimationSpan(element);
    if (at == null || span == null) return;
    var from = math.max(0, delay ?? at);
    var took = math.max(1, length ?? span);
    if (from == at && took == span) return;
    var document = _document;
    if (from + took > document.frames - 1) {
      document = document.copyWith(frames: from + took + 1);
    }
    var next = withOwnSpan(
        element, MotionKind.arrive, from, from + took, document.frameRate);
    // And what the next one is laid down with, so that trying another
    // preset keeps the length that was typed.
    if (length != null) {
      next = switch (next) {
        TextElement t =>
          t.copyWith(animation: t.animation.copyWith(length: took)),
        ChartElement c =>
          c.copyWith(animation: c.animation.copyWith(length: took)),
        _ => CanvasController._withElementAnimation(
            next,
            CanvasController.elementAnimationOf(element)
                .copyWith(length: took)),
      };
    }
    apply(document.withElement(next), transient: true);
  }

  /// previewSpanOf is the stretch of the scene a Preview of [element] plays:
  /// its arrival, its way out, and its loops -- its own and, for a drawing,
  /// its shapes' -- twice round, with a moment after. Two seconds from the
  /// start where it has none of them.
  (int, int) previewSpanOf(CanvasElement element) {
    var last = math.max(0, _document.frames - 1);
    var rate = math.max(1, _document.frameRate);
    int? start, end;
    void take(int a, int b) {
      start = math.min(start ?? a, a);
      end = math.max(end ?? b, b);
    }

    var (at, span) = elementAnimationSpan(element);
    if (at != null && span != null) take(at, at + span);
    if (ownSpan(element, MotionKind.leave, rate) case (var from, var length)) {
      take(from, from + length);
    }
    var arrived = ownEnd(element, rate);
    var loops = [
      CanvasController.elementLoopOf(element),
      if (element is VectorElement)
        for (var d in vectorDrawn(element.shapes ?? const []))
          if (d.style.animation case var own?
              when d.style.owns.contains(ShapeAnimationPart.looping))
            own.loop,
    ];
    for (var loop in loops) {
      if (!loop.on) continue;
      var (from, to) = loop.span(arrived: arrived, last: last);
      take(from, math.min(to, from + 2 * (loop.cycle + loop.gap) - loop.gap));
    }
    var a = start ?? 0;
    var b = end ?? a + rate * 2;
    b = math.min(last, b + (rate * 0.3).round());
    if (b <= a) b = math.min(last, a + 1);
    return (math.min(a, last), b);
  }

  /// previewing is the one element being previewed and the frame it is at, while
  /// a Preview plays: that element runs through its animation and everything
  /// else stays as it is at the playhead, which does not move. See
  /// previewElement.
  ({String id, int frame})? get previewing => _previewing;

  /// previewElement plays [id]'s animation, and nothing else's, once. See
  /// previewing. Anything else playing stops first; pausing stops it.
  void previewElement(String id) {
    var element = _document.elementById(id);
    if (element == null) return;
    pause();
    stopPreview();
    var (from, to) = previewSpanOf(element);
    _previewing = (id: id, frame: from);
    _previewingEnd = to;
    _startTimer();
    notifyListeners();
  }

  /// applyElementExit is the way out for a shape or a picture, on its own
  /// pair of keyframes at the end of the timeline. See applyTextExit.
  void applyElementExit(CanvasElement element, ElementAnimationPreset preset) {
    if (!CanvasController.animates(element)) return;
    beginInteraction();
    var was = CanvasController.elementAnimationOf(element);

    if (preset == ElementAnimationPreset.none) {
      replaceElement(withoutOwn(
          CanvasController._withElementAnimation(
              element, was.copyWith(exit: preset)),
          MotionKind.leave));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    var (wasFrom, wasTo) =
        switch (ownSpan(element, MotionKind.leave, document.frameRate)) {
      (var from, var length) => (from, from + length),
      null => (null, null),
    };

    var span = was.length > 0 ? was.length : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = ownEnd(element, document.frameRate) ?? 0;
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    apply(document.withElement(withOwnSpan(
        CanvasController._withElementAnimation(
            element, was.copyWith(exit: preset)),
        MotionKind.leave,
        from,
        to,
        document.frameRate)));
    endInteraction();
  }

  /// applyTextExit is the way out, on its own pair of keyframes at the end of
  /// the timeline. See applyChartExit.
  void applyTextExit(TextElement element, TextAnimationPreset preset) {
    beginInteraction();

    if (preset == TextAnimationPreset.none) {
      replaceElement(withoutOwn(
          element.copyWith(animation: element.animation.copyWith(exit: preset)),
          MotionKind.leave));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    // Where the exit already is, if it is anywhere, as for the arrival: a
    // laid-down exit stays where it was put however many presets are tried.
    var (wasFrom, wasTo) =
        switch (ownSpan(element, MotionKind.leave, document.frameRate)) {
      (var from, var length) => (from, from + length),
      null => (null, null),
    };

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = wasTo ?? document.frames - 1;
    var entranceEnds = ownEnd(element, document.frameRate) ?? 0;
    var from = wasFrom != null && wasTo != null && wasTo > wasFrom
        ? wasFrom
        : math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    apply(document.withElement(withOwnSpan(
        element.copyWith(animation: element.animation.copyWith(exit: preset)),
        MotionKind.leave,
        from,
        to,
        document.frameRate)));
    endInteraction();
  }

  /// applyChartExit puts a closing preset on a chart and lays the pair of
  /// keyframes that runs it, at the end of the timeline rather than the
  /// playhead: a closing animation is the thing that happens last. It never
  /// starts before the entrance has finished (see _afterEntrance).
  void applyChartExit(ChartElement element, ChartAnimationPreset preset) {
    beginInteraction();

    if (preset == ChartAnimationPreset.none) {
      // The keys go with it, or the chart would be pinned at "gone" for the
      // end of the timeline.
      replaceElement(withoutOwn(
          element.copyWith(animation: element.animation.copyWith(exit: preset)),
          MotionKind.leave));
      endInteraction();
      return;
    }

    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2, document.frameRate * chartAnimationSeconds * 2));
    }

    var span = element.animation.length > 0
        ? element.animation.length
        : defaultAnimationFrames;
    var to = document.frames - 1;
    // Clear of the entrance, which is whatever the reveal channel already
    // reaches.
    var entranceEnds = ownEnd(element, document.frameRate) ?? 0;
    var from = math.max(entranceEnds + 1, to - span);
    if (from >= to) from = math.max(0, to - 1);

    apply(document.withElement(withOwnSpan(
        element.copyWith(animation: element.animation.copyWith(exit: preset)),
        MotionKind.leave,
        from,
        to,
        document.frameRate)));
    endInteraction();
  }

  /// shiftKeyframes moves a whole band of keyframes by [delta] frames: the two
  /// ends of an animation are one thing (see KeyframeBand). Refused rather
  /// than clamped when either end would run off the timeline, so the band
  /// never silently squashes.
  void shiftKeyframes(String id, List<int> frames, int delta) {
    if (delta == 0 || frames.isEmpty) return;
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    var moving = [
      for (var frame in frames)
        if (track.keyAt(frame) != null) track.keyAt(frame)!,
    ];
    if (moving.length != frames.length) return;
    for (var key in moving) {
      var at = key.frame + delta;
      if (at < 0 || at > _document.frames - 1) return;
    }

    var next = track;
    for (var key in moving) {
      next = next.withoutFrame(key.frame);
    }
    for (var key in moving) {
      next = next.withKey(key.copyWith(frame: key.frame + delta));
    }
    replaceElement(element.withBase(track: next));
  }

  /// removeKeyframe drops the pose at [frame], and the track entirely when it
  /// was the last one, so no empty track is saved.
  void removeKeyframe(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;

    replaceElement(withoutHalfAnimations(element, track.withoutFrame(frame)));
  }

  /// setKeyframeEasing writes how the element travels *out* of a keyframe.
  /// Easing belongs to the keyframe it leaves, so copied keyframes keep it.
  /// [all] sets every keyframe on the element, and [channel] narrows that to
  /// the keyframes carrying one thing (a counter's number, say), leaving a
  /// move laid by hand alone.
  void setKeyframeEasing(
    CanvasElement element,
    KeyframeEasing easing, {
    bool all = false,
    String? channel,
  }) {
    var track = element.track;
    if (track == null) return;
    var next = track;
    for (var key in track.keys) {
      if (!all && key.frame != _frame) continue;
      if (channel != null && !key.values.containsKey(channel)) continue;
      next = next.withKey(key.copyWith(easing: easing));
    }
    if (identical(next, track)) return;
    replaceElement(element.withBase(track: next));
  }

  /// clearPose takes the *pose* off one frame and leaves whatever else that
  /// keyframe pinned: what the position-size-angle-fade diamond does, so a
  /// counter's number or a chart's arrival on the same frame is kept.
  /// Deleting the keyframe on the timeline still deletes all of it.
  void clearPose(String id, int frame) {
    var element = _document.elementById(id);
    var track = element?.track;
    if (element == null || track == null) return;
    var here = track.keyAt(frame);
    if (here == null) return;
    if (here.values.isEmpty) {
      removeKeyframe(id, frame);
      return;
    }
    replaceElement(element.withBase(
        track: track.withKey(Keyframe(frame: frame, values: here.values))));
  }

  /// withoutOwnPreset is [e] with its own arrival (or way out) gone and that
  /// setting back to None: taken off the timeline, an arrival is none at
  /// all, and the next preset is laid down afresh.
  CanvasElement withoutOwnPreset(CanvasElement e, MotionKind kind) {
    var arrive = kind == MotionKind.arrive;
    var out = withoutOwn(e, kind);
    if (out is TextElement) {
      return out.copyWith(
          animation: out.animation.copyWith(
              preset: arrive ? TextAnimationPreset.none : null,
              exit: arrive ? null : TextAnimationPreset.none));
    }
    if (out is ChartElement) {
      return out.copyWith(
          animation: out.animation.copyWith(
              preset: arrive ? ChartAnimationPreset.none : null,
              exit: arrive ? null : ChartAnimationPreset.none));
    }
    if (!CanvasController.animates(out)) return out;
    var was = CanvasController.elementAnimationOf(out);
    return CanvasController._withElementAnimation(
        out,
        arrive
            ? was.copyWith(preset: ElementAnimationPreset.none)
            : was.copyWith(exit: ElementAnimationPreset.none));
  }

  /// withoutHalfAnimations takes away any arrival or exit that has lost one
  /// of its two keyframes, and turns the setting back to None. An animation
  /// is a pair; an orphan left on the timeline would show nothing, and the
  /// next preset would be laid out against it.
  CanvasElement withoutHalfAnimations(
      CanvasElement element, ElementTrack next) {
    var lost = <String>{};
    for (var channel in [KeyframeChannel.reveal, KeyframeChannel.close]) {
      var count = 0;
      for (var key in next.keys) {
        if (key.values.containsKey(channel)) count++;
      }
      if (count > 0 && count < 2) lost.add(channel);
    }

    for (var channel in lost) {
      for (var key in next.keys) {
        if (!key.values.containsKey(channel)) continue;
        var without = key.withoutValue(channel);
        next = without.isRest && without.frame != 0
            ? next.withoutFrame(key.frame)
            : next.withKey(without);
      }
    }

    var out = element;
    if (out is TextElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? TextAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? TextAnimationPreset.none
            : null,
      ));
    } else if (out is ChartElement) {
      out = out.copyWith(
          animation: out.animation.copyWith(
        preset: lost.contains(KeyframeChannel.reveal)
            ? ChartAnimationPreset.none
            : null,
        exit: lost.contains(KeyframeChannel.close)
            ? ChartAnimationPreset.none
            : null,
      ));
    }

    return next.isEmpty
        ? out.withBase(clearTrack: true)
        : out.withBase(track: next);
  }
}
