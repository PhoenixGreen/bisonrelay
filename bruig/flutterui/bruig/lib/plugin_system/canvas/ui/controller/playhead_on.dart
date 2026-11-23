// playhead_on.dart is what the editor's playhead is on: the scene's own
// timeline, a frame of the run of every scene, a join's transition watched,
// one element's animation previewed, or the clip slots playing alone.
// Whether it is playing is the timer's, held by the controller beside it.
// A library beside the controller's parts rather than a part: values that
// need nothing of the controller.

/// PlayheadOn is what the playhead is playing or showing. Each case holds
/// what that activity needs and nothing else, and is the same whether the
/// timer runs or not: the timer says whether, this says what. Stopped on
/// the scene, as a canvas opens, it is a bare [OnTimeline].
///
/// The first three ([Showing]) are what the canvas shows. [OnElement] and
/// [OnSlots] are what only a running timer plays, each over what was
/// showing when it began, which shows again when the timer stops.
sealed class PlayheadOn {
  const PlayheadOn();

  /// showing is what the canvas shows: this, or what an element's preview
  /// or the slots play over.
  Showing get showing;

  /// runFrame is the frame of the whole run the canvas shows, or null when
  /// it shows the scene being edited, at the playhead.
  int? get runFrame;

  /// isPreview is whether what plays or shows is a preview rather than the
  /// canvas's own time: one element's animation, or a join's transition. A
  /// run of every scene is not one; nor is a join whose playhead was put by
  /// hand off its transition, which shows the scene.
  bool get isPreview => switch (this) {
        OnElement() => true,
        OnSlots(:var over) => over.isPreview,
        OnJoin(:var at) => at != null,
        OnTimeline() || OnRun() => false,
      };

  /// withShowing is this with [shown] showing: [shown] itself, or the
  /// element's preview or the slots over it.
  PlayheadOn withShowing(Showing shown) => switch (this) {
        Showing() => shown,
        OnElement e =>
          OnElement(id: e.id, frame: e.frame, end: e.end, over: shown),
        OnSlots s => OnSlots(seconds: s.seconds, over: shown),
      };
}

/// Showing is what the canvas shows at the playhead: the scene, or a frame
/// of the run. Each carries the range playing stops at, if one was asked.
sealed class Showing extends PlayheadOn {
  const Showing();

  @override
  Showing get showing => this;

  /// rangeEnd is the frame of the scene that playing stops at (a button's
  /// Play to frame, a Code panel's lesson, a sheet's bars), or null.
  /// Pausing lets go of it.
  int? get rangeEnd;

  /// withRangeEnd is this stopping at [end] instead.
  Showing withRangeEnd(int? end);
}

/// OnTimeline is the playhead on the scene's own timeline: the scene, at
/// the playhead, playing or not.
final class OnTimeline extends Showing {
  const OnTimeline({this.rangeEnd});

  @override
  final int? rangeEnd;

  @override
  int? get runFrame => null;

  @override
  OnTimeline withRangeEnd(int? end) => OnTimeline(rangeEnd: end);
}

/// OnRun is the playhead on frame [at] of the run of every scene, which
/// stops at [end]: Play all playing, or a frame of the run put by hand
/// (stepped to, or scrubbed to inside a transition).
final class OnRun extends Showing {
  const OnRun({required this.at, required this.end, this.rangeEnd});

  final int at;
  final int end;

  @override
  final int? rangeEnd;

  @override
  int? get runFrame => at;

  /// movedTo is this on frame [frame] of the run.
  OnRun movedTo(int frame) => OnRun(at: frame, end: end, rangeEnd: rangeEnd);

  @override
  OnRun withRangeEnd(int? end) => OnRun(at: at, end: this.end, rangeEnd: end);
}

/// OnJoin is the transition after scene [join] watched, playing or paused:
/// frame [at] of the run, to [end], and afterwards back on scene [from]
/// (and on the master, if [fromMaster]).
///
/// [at] is null once the playhead of a paused join was put by hand off the
/// transition: the scene then shows, and plays as on the timeline, while
/// the join is still what Play all plays on from, and its end still goes
/// back to [from].
final class OnJoin extends Showing {
  const OnJoin(
      {required this.at,
      required this.end,
      required this.join,
      required this.from,
      required this.fromMaster,
      this.rangeEnd});

  final int? at;
  final int end;
  final int join;
  final int from;
  final bool fromMaster;

  @override
  final int? rangeEnd;

  @override
  int? get runFrame => at;

  /// movedTo is this on frame [frame] of the run, or off it (null).
  OnJoin movedTo(int? frame) => playedTo(frame, end);

  /// playedTo is this on frame [frame] of the run, stopping at [end].
  OnJoin playedTo(int? frame, int end) => OnJoin(
      at: frame,
      end: end,
      join: join,
      from: from,
      fromMaster: fromMaster,
      rangeEnd: rangeEnd);

  @override
  OnJoin withRangeEnd(int? end) => OnJoin(
      at: at,
      end: this.end,
      join: join,
      from: from,
      fromMaster: fromMaster,
      rangeEnd: end);
}

/// OnElement is element [id]'s animation previewed, at its frame [frame],
/// to [end]: it alone moves, over [over], which stays as it was.
final class OnElement extends PlayheadOn {
  const OnElement(
      {required this.id,
      required this.frame,
      required this.end,
      required this.over});

  final String id;
  final int frame;
  final int end;
  final Showing over;

  @override
  Showing get showing => over;

  @override
  int? get runFrame => over.runFrame;

  /// steppedOn is this a frame further on.
  OnElement steppedOn() =>
      OnElement(id: id, frame: frame + 1, end: end, over: over);
}

/// OnSlots is the clip slots playing alone, on their own clock, [seconds]
/// since they began: the timeline silent and its playhead still, over
/// [over], which stays as it was.
final class OnSlots extends PlayheadOn {
  const OnSlots({required this.seconds, required this.over});

  final double seconds;
  final Showing over;

  @override
  Showing get showing => over;

  @override
  int? get runFrame => over.runFrame;

  /// atSeconds is this with the slots' clock at [seconds].
  OnSlots atSeconds(double seconds) => OnSlots(seconds: seconds, over: over);
}
