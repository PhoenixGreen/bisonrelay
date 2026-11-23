// playhead_on.dart is what the editor's playhead is on: the scene's own
// timeline, a frame of the run of every scene, a join's transition watched,
// one element's animation previewed, or the clip slots playing alone.
// Whether it is playing is the timer's, held by the controller beside it,
// with the frame a play is to stop at. A library beside the controller's
// parts rather than a part: values that need nothing of the controller.

/// PlayheadOn is what the playhead is playing or showing. Each case holds
/// what that activity needs and nothing else, and is the same whether the
/// timer runs or not: the timer says whether, this says what. Stopped on
/// the scene, as a canvas opens, it is [OnTimeline].
///
/// The first three ([Showing]) are what the canvas shows. [OnElement] and
/// [OnSlots] are what only a running timer plays, always over the scene:
/// each begins by ending a join watched or a frame of the run held, and the
/// scene shows again when the timer stops.
sealed class PlayheadOn {
  const PlayheadOn();

  /// showing is what the canvas shows: this, or the scene under an
  /// element's preview or the slots.
  Showing get showing;

  /// runFrame is the frame of the whole run the canvas shows, or null when
  /// it shows the scene being edited, at the playhead.
  int? get runFrame;

  /// isPreview is whether what plays or shows is a preview rather than the
  /// canvas's own time: one element's animation, or a join's transition. A
  /// run of every scene is not one, nor are the slots alone.
  bool get isPreview => switch (this) {
        OnElement() || OnJoin() => true,
        OnTimeline() || OnRun() || OnSlots() => false,
      };
}

/// Showing is what the canvas shows at the playhead: the scene, or a frame
/// of the run.
sealed class Showing extends PlayheadOn {
  const Showing();

  @override
  Showing get showing => this;
}

/// OnTimeline is the playhead on the scene's own timeline: the scene, at
/// the playhead, playing or not.
final class OnTimeline extends Showing {
  const OnTimeline();

  @override
  int? get runFrame => null;
}

/// OnRun is the playhead on frame [at] of the run of every scene: Play all
/// playing, or a frame of the run put by hand (stepped to, or scrubbed to
/// inside a transition). It plays to the end of the run, which is worked
/// out from the document as it is then, not kept.
final class OnRun extends Showing {
  const OnRun(this.at);

  final int at;

  @override
  int? get runFrame => at;

  /// movedTo is this on frame [frame] of the run.
  OnRun movedTo(int frame) => OnRun(frame);
}

/// OnJoin is the transition after scene [join] watched, playing or paused:
/// frame [at] of the run, to [end], and afterwards back on scene [from]
/// (and on the master, if [fromMaster]). A playhead put by hand off the
/// transition ends the watching, so [at] is always a frame of the run.
final class OnJoin extends Showing {
  const OnJoin(
      {required this.at,
      required this.end,
      required this.join,
      required this.from,
      required this.fromMaster});

  final int at;
  final int end;
  final int join;
  final int from;
  final bool fromMaster;

  @override
  int? get runFrame => at;

  /// movedTo is this on frame [frame] of the run.
  OnJoin movedTo(int frame) => playedTo(frame, end);

  /// playedTo is this on frame [frame] of the run, stopping at [end].
  OnJoin playedTo(int frame, int end) => OnJoin(
      at: frame, end: end, join: join, from: from, fromMaster: fromMaster);
}

/// OnElement is element [id]'s animation previewed, at its frame [frame],
/// to [end]: it alone moves, over the scene, which stays as it was.
final class OnElement extends PlayheadOn {
  const OnElement({required this.id, required this.frame, required this.end});

  final String id;
  final int frame;
  final int end;

  @override
  Showing get showing => const OnTimeline();

  @override
  int? get runFrame => null;

  /// steppedOn is this a frame further on.
  OnElement steppedOn() => OnElement(id: id, frame: frame + 1, end: end);
}

/// OnSlots is the clip slots playing alone, on their own clock, [seconds]
/// since they began: the timeline silent and its playhead still, over the
/// scene, which stays as it was.
final class OnSlots extends PlayheadOn {
  const OnSlots({required this.seconds});

  final double seconds;

  @override
  Showing get showing => const OnTimeline();

  @override
  int? get runFrame => null;

  /// atSeconds is this with the slots' clock at [seconds].
  OnSlots atSeconds(double seconds) => OnSlots(seconds: seconds);
}
