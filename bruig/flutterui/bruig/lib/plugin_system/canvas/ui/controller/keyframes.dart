part of '../canvas_controller.dart';

// Keyframes, and the arrivals and exits laid on them. Part of CanvasController.
// Its state is _KeyframeState, at the end of this file.

/// KeyframeTarget is what the Chain's Keyframes card edits: a team's
/// focused player, a path's points (their times only), or the picked
/// element's own keyframes.
class KeyframeTarget {
  /// name is who it is, kind what ("Image", "Team", "Path").
  final String name;
  final String kind;
  final ElementTrack track;

  /// points is a path's points: timed, holding no values.
  final bool points;

  /// player is the team's player by index, where it is one.
  final int? player;
  const KeyframeTarget(this.name, this.kind, this.track,
      {this.points = false, this.player});
}

extension CanvasKeyframes on CanvasController {
  /// setKeyframe writes the pose at the current frame for one element.
  void setKeyframe(String id, Keyframe key) {
    var element = _document.elementById(id);
    if (element == null) return;
    // Keep what that frame already pinned: a keyframe holds the pose and any
    // channels (a counter's number, a chart's arrival), and writing a pose
    // over it wholesale would throw the channels away.
    var was = element.track?.keyAt(key.frame);
    var merged = was == null || was.values.isEmpty
        ? key
        : key.copyWith(values: {...was.values, ...key.values});
    var track = (element.track ?? ElementTrack.empty).withKey(merged);
    replaceElement(element.withBase(track: track));
  }

  /// applyChartAnimation puts a preset on a chart and lays the two keyframes
  /// that give it a length, as one gesture, since a preset with no
  /// keyframes draws nothing different. They are ordinary keyframes, so the
  /// length is the gap between them.
  ///
  /// A still document is given a second's worth of frames first. [length],
  /// in frames, overrules everything; left out, it comes from the
  /// animation's Length setting if set, else from where the keyframes
  /// already are, so trying one preset after another leaves the timing
  /// alone. applyTextAnimation follows the same rules.
  void applyChartAnimation(ChartElement element, ChartAnimationPreset preset,
          {int? length}) =>
      _layOwn(
          element,
          element.copyWith(
              animation: element.animation.copyWith(preset: preset)),
          MotionKind.arrive,
          none: preset == ChartAnimationPreset.none,
          length: length,
          setLength: element.animation.length);

  /// applyTextAnimation puts a preset on a text element and lays the two
  /// keyframes that give it a length, mirroring applyChartAnimation, so a
  /// headline and a chart arriving together arrive together.
  ///
  /// [length], in frames, overrules everything (zero means the usual two
  /// seconds); it is what the Length setting passes. Left out, it comes from
  /// the animation's Length setting if set, else from where the keyframes
  /// already are.
  void applyTextAnimation(TextElement element, TextAnimationPreset preset,
      {int? length}) {
    var a = element.animation;
    var none = preset == TextAnimationPreset.none;
    // The curve and cutting the preset was designed around, only when the
    // preset changes, so re-laying it does not undo numbers somebody chose.
    // See TextAnimationPreset.wants.
    var changing = !none && preset != a.preset;
    _layOwn(
        element,
        element.copyWith(
            animation: a.copyWith(
                preset: preset,
                ease: changing ? preset.wants : null,
                effect: changing ? preset.effect : null)),
        MotionKind.arrive,
        none: none,
        length: length,
        setLength: a.length);
  }

  /// defaultAnimationFrames is how long an animation runs when nobody has
  /// said: two seconds, as a chart's does.
  int get defaultAnimationFrames =>
      math.max(2, (_document.frameRate * chartAnimationSeconds).round());

  /// keyframeLoop is the picked element's loop as the Keyframes card shows
  /// it (start, stop, cycle and gap), or null where it has none or the card
  /// is on a player or a path.
  (int, int, int, int)? get keyframeLoop {
    var t = keyframeTarget;
    if (t == null || t.points || t.player != null) return null;
    var element = selected;
    if (element == null || !CanvasController.loops(element)) return null;
    var loop = CanvasController.elementLoopOf(element);
    if (!loop.on) return null;
    var (start, end) = loop.span(
        arrived: arrivalEnd(element, document.frameRate),
        last: document.frames - 1);
    return (start, end, loop.cycle, loop.gap);
  }

  /// moveKeyframeLoopEnd puts an end of the loop's bar on [frame]: its
  /// start, or ([end]) its stop, never past each other. Transient: the drag
  /// is one change, between beginInteraction and endInteraction.
  void moveKeyframeLoopEnd(bool end, int frame) {
    var element = selected;
    var bar = keyframeLoop;
    if (element == null || bar == null) return;
    var loop = CanvasController.elementLoopOf(element);
    var (start, stop, _, _) = bar;
    setElementLoop(
        element,
        end
            ? loop.copyWith(to: math.max(start, frame - 1), repeats: 0)
            : loop.copyWith(from: math.min(stop, frame)),
        transient: true);
  }

  /// _showOwn shows [element]'s own [kind], just laid down, in the Chain:
  /// its clip picked, so the cards after it are that clip's, not another's.
  void _showOwn(String element, MotionKind kind) {
    var e = _document.elementById(element);
    if (e == null) return;
    if (ownClipOf(e, kind) case (var c, var p)) {
      pickMotion(element, c.id, placement: p.id);
    }
  }

  /// setElementLoop gives [element] [loop], [transient] while a drag on its
  /// bar is still making it. See ElementLoop.
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

  /// applyElementAnimation puts an arrival on a shape or picture and lays
  /// the keyframe pair that runs it, by [applyTextAnimation]'s rules: what
  /// is already laid down wins, the Length setting is for a new one, and
  /// None takes the keyframes away.
  void applyElementAnimation(
      CanvasElement element, ElementAnimationPreset preset,
      {int? length}) {
    if (!CanvasController.animates(element)) return;
    var was = CanvasController.elementAnimationOf(element);
    var none = preset == ElementAnimationPreset.none;
    // Its own curve and way of cutting, only where the preset is changing:
    // Build up and Break apart differ only in these.
    var changing = !none && preset != was.preset;
    _layOwn(
        element,
        CanvasController._withElementAnimation(
            element,
            was.copyWith(
                preset: preset,
                ease: changing ? preset.wants : null,
                effect: changing ? preset.effect : null)),
        MotionKind.arrive,
        none: none,
        length: length,
        setLength: was.length);
  }

  /// elementAnimationSpan is where [element]'s arrival sits on the timeline:
  /// its start frame and length. See textAnimationSpan, which reads the same
  /// channel.
  (int?, int?) elementAnimationSpan(CanvasElement element) =>
      switch (ownSpan(element, MotionKind.arrive, _document.frameRate)) {
        (var from, var length) => (from, length),
        null => (null, null),
      };

  /// anchorShown is whether [id]'s anchor point is drawn on the stage, to be
  /// dragged unless locked. A way of looking, not part of the design: not
  /// saved, not undone.
  bool anchorShown(String id) => _keyframes.anchorsShown.contains(id);

  void showAnchor(String id, bool shown) {
    if (shown
        ? !_keyframes.anchorsShown.add(id)
        : !_keyframes.anchorsShown.remove(id)) {
      return;
    }
    notifyListeners();
  }

  /// previewSpanOf is the stretch of the scene a Preview of [element] plays:
  /// its arrival, way out and loops (its own and, for a drawing, its
  /// shapes'), twice round, with a moment after. Two seconds from the start
  /// where it has none.
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

  /// previewing is the element being previewed and its frame while a Preview
  /// plays: that element runs through its animation and everything else
  /// stays as at the playhead, which does not move. See previewElement.
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

  /// applyElementExit is the way out for a shape or picture, on its own
  /// keyframe pair (see newExitSpan).
  void applyElementExit(CanvasElement element, ElementAnimationPreset preset) {
    if (!CanvasController.animates(element)) return;
    var was = CanvasController.elementAnimationOf(element);
    _layOwn(
        element,
        CanvasController._withElementAnimation(
            element, was.copyWith(exit: preset)),
        MotionKind.leave,
        none: preset == ElementAnimationPreset.none,
        setLength: was.length);
  }

  /// applyTextExit is the way out for text, on its own keyframe pair (see
  /// newExitSpan).
  void applyTextExit(TextElement element, TextAnimationPreset preset) =>
      _layOwn(
          element,
          element.copyWith(animation: element.animation.copyWith(exit: preset)),
          MotionKind.leave,
          none: preset == TextAnimationPreset.none,
          setLength: element.animation.length);

  /// applyChartExit puts a closing preset on a chart on its own keyframe
  /// pair (see newExitSpan), never starting before the entrance has
  /// finished (see _afterEntrance).
  void applyChartExit(ChartElement element, ChartAnimationPreset preset) =>
      _layOwn(
          element,
          element.copyWith(animation: element.animation.copyWith(exit: preset)),
          MotionKind.leave,
          none: preset == ChartAnimationPreset.none,
          setLength: element.animation.length);

  /// _layOwn chooses any element's own arrival or leaving ([kind]): [next]
  /// is [element] with it chosen. None takes its clip away and nothing else,
  /// so a move or fade made by hand stays. Otherwise its clip is laid where
  /// it already is, keeping its length, so trying presets leaves the timing
  /// alone; with none, an arrival goes from the playhead, [length] frames
  /// long (or [setLength], or two seconds), and a leaving clear of the
  /// arrival (see newExitSpan). A still document is given frames first.
  void _layOwn(CanvasElement element, CanvasElement next, MotionKind kind,
      {required bool none, int? length, int setLength = 0}) {
    beginInteraction();
    if (none) {
      replaceElement(withoutOwn(next, kind));
      endInteraction();
      return;
    }
    var leaving = kind == MotionKind.leave;
    var document = _document;
    if (!document.isAnimated) {
      document = document.copyWith(
          frames: math.max(2,
              document.frameRate * chartAnimationSeconds * (leaving ? 2 : 1)));
    }
    var rate = document.frameRate;
    var had = ownSpan(element, kind, rate);
    var wanted = setLength > 0 ? setLength : defaultAnimationFrames;
    int from, to;
    if (leaving) {
      (from, to) = switch (had) {
        (var f, var l) when l > 0 => (f, f + l),
        _ => newExitSpan(ownEnd(element, rate) ?? 0, wanted, document),
      };
    } else {
      from = had?.$1 ?? _frame.clamp(0, document.frames - 2);
      var span = had?.$2 ?? length ?? wanted;
      span = math.max(1, span == 0 ? defaultAnimationFrames : span);
      if (document.frames - 1 < from + span) {
        document = document.copyWith(frames: from + span + 1);
      }
      to = from + span;
      if (to <= from) {
        from = 0;
        to = document.frames - 1;
      }
    }
    apply(document.withElement(withOwnSpan(next, kind, from, to, rate)));
    endInteraction();
    _showOwn(element.id, kind);
  }

  /// shiftKeyframes moves a band of keyframes by [delta] frames: the two
  /// ends of an animation are one thing. Refused, not clamped, when either
  /// end would run off the timeline, so the band never silently squashes.
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

  /// setKeyframeEasing writes how the element travels *out* of a keyframe:
  /// easing belongs to the keyframe it leaves, so copied keyframes keep it.
  /// [all] sets every keyframe on the element; [channel] narrows that to
  /// keyframes carrying one thing (a counter's number, say), leaving a move
  /// laid by hand alone.
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

  /// withoutOwnPreset is [e] with its own arrival (or way out) removed and
  /// that setting back to None, so the next preset is laid afresh.
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

  /// withTrackOrNone is [element] with [next] as its keyframes, or none at
  /// all if [next] is empty, so no empty track is saved.
  CanvasElement withTrackOrNone(CanvasElement element, ElementTrack next) =>
      next.isEmpty
          ? element.withBase(clearTrack: true)
          : element.withBase(track: next);

  // ---- the Chain's Keyframes card ----------------------------------------

  /// keyframeTarget is what the Keyframes card edits, or null: nothing
  /// picked, or what is picked moved by a path, whose points are its timing.
  KeyframeTarget? get keyframeTarget {
    var team = focusedTeam;
    var index = focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      if (pathDriving(team.id, playerIndex: index) != null) return null;
      var spot = team.players[index];
      var teamName = team.base.name.isEmpty ? team.id : team.base.name;
      return KeyframeTarget(
          "$teamName · ${spot.name}", "Team", spot.track ?? ElementTrack.empty,
          player: index);
    }
    var e = selected;
    if (e == null) return null;
    var name = e.base.name.isEmpty ? e.id : e.base.name;
    if (e is PathElement) {
      return KeyframeTarget(name, "Path",
          ElementTrack([for (var n in e.nodes) Keyframe(frame: n.frame)]),
          points: true);
    }
    if (pathDriving(e.id) != null) return null;
    return KeyframeTarget(name, e.kind.label, e.track ?? ElementTrack.empty);
  }

  /// writeTargetTrack puts [track] back on the Keyframes card's target, or
  /// no track if it is empty. Not for a path, whose points are written by
  /// moveTargetKeyframes.
  void writeTargetTrack(ElementTrack track) {
    var team = focusedTeam;
    var index = focusedPlayer;
    if (team != null && index != null && index < team.players.length) {
      var spot = team.players[index];
      replaceElement(team.withPlayer(
          index,
          track.isEmpty
              ? spot.copyWith(clearTrack: true)
              : spot.copyWith(track: track)));
      return;
    }
    var e = selected;
    if (e == null || e is PathElement) return;
    replaceElement(withTrackOrNone(e, track));
  }

  /// moveTargetKeyframes moves the keyframes at [frames] by [by], keeping
  /// their spacing: all of them, or none (returning false) where one would
  /// land on another keyframe or off the scene.
  bool moveTargetKeyframes(List<int> frames, int by) {
    var t = keyframeTarget;
    if (t == null || frames.isEmpty) return false;
    if (by == 0) return true;
    var moving = frames.toSet();
    var last = _document.frames - 1;
    var rest = {
      for (var k in t.track.keys)
        if (!moving.contains(k.frame)) k.frame
    };
    for (var f in moving) {
      var to = f + by;
      if (to < 0 || to > last || rest.contains(to)) return false;
    }
    var e = selected;
    if (t.points && e is PathElement) {
      // One point at a time, the far end first, so none passes another.
      var order = moving.toList()..sort();
      if (by > 0) order = order.reversed.toList();
      var path = e;
      for (var f in order) {
        var i = path.nodeIndexAtFrame(f);
        if (i == null) return false;
        path = path.retimeNode(i, f + by);
      }
      replaceElement(path);
      applyPathFollow(path);
      return true;
    }
    var next = t.track;
    var keys = [
      for (var f in moving)
        if (t.track.keyAt(f) case var k?) k
    ];
    for (var k in keys) {
      next = next.withoutFrame(k.frame);
    }
    for (var k in keys) {
      next = next.withKey(k.copyWith(frame: k.frame + by));
    }
    writeTargetTrack(next);
    return true;
  }

  /// removeTargetKeyframes deletes the keyframes at [frames] (a path's
  /// points there).
  void removeTargetKeyframes(Iterable<int> frames) {
    var t = keyframeTarget;
    if (t == null) return;
    var e = selected;
    if (t.points && e is PathElement) {
      var path = e;
      for (var f in frames.toList()..sort((a, b) => b - a)) {
        var i = path.nodeIndexAtFrame(f);
        if (i != null) path = path.withoutNode(i);
      }
      replaceElement(path);
      applyPathFollow(path);
      return;
    }
    var next = t.track;
    for (var f in frames) {
      next = next.withoutFrame(f);
    }
    writeTargetTrack(next);
  }

  /// toggleTargetKeyframe is the card's diamond: removes the keyframe at the
  /// playhead, or adds one holding the pose there (a point, on a path). Its
  /// values are set in the element's settings, or in Curves.
  void toggleTargetKeyframe() {
    var t = keyframeTarget;
    if (t == null) return;
    var e = selected;
    if (t.points && e is PathElement) {
      var i = e.nodeIndexAtFrame(_frame);
      var next = i == null ? e.insertAtFrame(_frame) : e.withoutNode(i);
      if (identical(next, e)) return;
      replaceElement(next);
      applyPathFollow(next);
      return;
    }
    if (t.track.keyAt(_frame) != null) {
      writeTargetTrack(t.track.withoutFrame(_frame));
    } else {
      writeTargetTrack(t.track.withKey(t.track.isEmpty
          ? Keyframe(frame: _frame)
          : t.track.at(_frame).copyWith(frame: _frame)));
    }
  }

  /// copyTargetKeys keeps the keyframes at [frames], relative to the first,
  /// to paste at the playhead, and returns how many.
  int copyTargetKeys(Iterable<int> frames) {
    var t = keyframeTarget;
    if (t == null || t.points) return 0;
    var sorted = frames.toList()..sort();
    if (sorted.isEmpty) return 0;
    _keyframes.keyClipboard = [
      for (var f in sorted)
        if (t.track.keyAt(f) case var k?) (f - sorted.first, k)
    ];
    return _keyframes.keyClipboard.length;
  }

  bool get hasCopiedKeys => _keyframes.keyClipboard.isNotEmpty;

  /// pasteTargetKeys lays the copied keyframes down from the playhead,
  /// keeping their spacing: the frames they landed on, or why not (no room
  /// before the scene ends, or a keyframe already there).
  (List<int>, String?) pasteTargetKeys() {
    var t = keyframeTarget;
    if (t == null || t.points || _keyframes.keyClipboard.isEmpty) {
      return (const [], null);
    }
    var at = _frame;
    var wanted = [for (var (offset, _) in _keyframes.keyClipboard) at + offset];
    if (wanted.last > _document.frames - 1) {
      return (const [], "There is not room for that before the scene ends.");
    }
    var taken = [
      for (var f in wanted)
        if (t.track.keyAt(f) != null) f
    ];
    if (taken.isNotEmpty) {
      return (
        const [],
        "Frame${taken.length == 1 ? "" : "s"} ${taken.join(", ")} already "
            "${taken.length == 1 ? "has a keyframe" : "have keyframes"}: move "
            "the playhead clear of them."
      );
    }
    var next = t.track;
    for (var (offset, k) in _keyframes.keyClipboard) {
      next = next.withKey(k.copyWith(frame: at + offset));
    }
    writeTargetTrack(next);
    return (wanted, null);
  }

  /// easeTargetKeyframes sets how each keyframe at [frames] eases to the
  /// next.
  void easeTargetKeyframes(Iterable<int> frames, KeyframeEasing easing) {
    var t = keyframeTarget;
    if (t == null || t.points) return;
    var next = t.track;
    for (var f in frames) {
      if (t.track.keyAt(f) case var k?) {
        next = next.withKey(k.copyWith(easing: easing));
      }
    }
    writeTargetTrack(next);
  }
}

/// exitHoldSeconds is how long something is up between its arrival and a
/// new exit laid for it.
const double exitHoldSeconds = 2;

/// newExitSpan is where a new exit [span] frames long goes after an arrival
/// ending at [entranceEnds]: exitHoldSeconds after it, so what arrives is
/// up long enough to read, or at the scene's end where it is too short.
(int, int) newExitSpan(int entranceEnds, int span, CanvasDocument document) {
  var last = math.max(1, document.frames - 1);
  var from = entranceEnds + 1 + (exitHoldSeconds * document.frameRate).round();
  if (from + span <= last) return (from, from + span);
  var to = last;
  from = math.max(entranceEnds + 1, to - span);
  if (from >= to) from = math.max(0, to - 1);
  return (from, to);
}

/// _KeyframeState is what CanvasKeyframes keeps between calls, here beside the code that
/// uses it. The controller holds one, as _keyframes; most fields are read and
/// set through CanvasKeyframes's getters and setters above, which say what each is.
class _KeyframeState {
  /// keyClipboard is the keyframes copied in the Chain's Keyframes card,
  /// each relative to the first: see copyTargetKeys.
  List<(int, Keyframe)> keyClipboard = const [];

  final Set<String> anchorsShown = {};
}
