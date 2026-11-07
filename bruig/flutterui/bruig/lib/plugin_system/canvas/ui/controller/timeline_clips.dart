part of '../canvas_controller.dart';

// timeline_clips.dart makes a sound on the timeline a clip, as one in a slot
// is (Ken: "a clip and a timeline clip are interchangeable"): opened in the
// clip editor with the same settings -- warp, pitch, gain, fades,
// envelopes, its start and its loop -- kept on its source (MediaSource
// .clip), with its own sound the original. What the timeline plays is the
// clip rendered (see _playedSound), between its start and its loop's end.

/// timelineRow is the clip editor's row for a sound on the timeline, not in
/// a slot.
const int timelineRow = -1;

extension CanvasTimelineClips on CanvasController {
  /// timelineSoundOf is the sound on [channel]'s timeline the clip editor
  /// opens on: its first that is a file -- not an instrument, nor a voice.
  /// The one picked first, where the channel has several.
  AudioElement? timelineSoundOf(String channel) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    AudioElement? first;
    for (var l in lane?.lanes ?? const <TimedLane>[]) {
      if (l.element case AudioElement a
          when a.instrument == null &&
              a.clip.playlist.isNotEmpty &&
              a.clip.playlist.first.assetId.isNotEmpty) {
        if (selection.contains(a.id)) return a;
        first ??= a;
      }
    }
    return first;
  }

  /// timelineClipOf is [e]'s sound as a clip: its settings, or -- never
  /// opened in the editor -- ones made from it as it plays now.
  SessionClip timelineClipOf(AudioElement e) {
    var source = e.clip.playlist.first;
    // Its fades are the timeline's own, dragged there or set here: one
    // pair, played as the sound plays, not rendered.
    if (source.clip case var clip?) {
      return clip.copyWith(fadeIn: e.clip.fadeIn, fadeOut: e.clip.fadeOut);
    }
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var span = source.span > 0 ? source.span : source.length;
    return SessionClip(
      id: "timeline:${e.id}",
      name: e.name,
      sound: source.copyWith(clearClip: true),
      bars: math.max(1 / bpb, span / spb / bpb),
      loop: false,
      // As loud as it plays, and faded as it is.
      gain: (gainToDb(e.clip.volume) * 10).roundToDouble() / 10,
      fadeIn: e.clip.fadeIn,
      fadeOut: e.clip.fadeOut,
    );
  }

  /// editTimelineClip changes [e]'s sound as a clip, as editClip does a
  /// slot's: one change to undo, or -- [transient] -- part of a drag.
  void editTimelineClip(
      AudioElement e, SessionClip Function(SessionClip clip) change,
      {bool transient = false}) {
    if (e.clip.playlist.isEmpty) return;
    _setTimelineClip(e, change(timelineClipOf(e)), transient: transient);
  }

  /// _timelineOwner is the sound on the timeline whose clip is [id], or
  /// null.
  AudioElement? _timelineOwner(String id) {
    for (var e in _document.elements) {
      if (e is! AudioElement || e.instrument != null) continue;
      if (e.clip.playlist.isEmpty) continue;
      var clip = e.clip.playlist.first.clip;
      if (clip?.id == id || "timeline:${e.id}" == id) return e;
    }
    return null;
  }

  /// _setTimelineClip writes [clip] onto [e]: its settings kept on its
  /// source, and the source what it plays -- its sound as it is, where it
  /// needs nothing made, or as last rendered. An undo step unless
  /// [transient]; rendered again a moment after the last change.
  void _setTimelineClip(AudioElement e, SessionClip clip,
      {bool transient = false, bool render = true}) {
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var bpb = _document.audio.beatsPerBar;
    var sound = clip.sound;
    if (sound == null) return;
    var was = e.clip.playlist.first;
    // The fades are the timeline's (see timelineClipOf); the rest is made.
    var fades = (clip.fadeIn, clip.fadeOut);
    clip = _rendered(clip);
    MediaSource played;
    if (!clip.needsRender) {
      // Its own sound, from its start to its loop's end, at its own speed.
      played = sound.copyWith(
          start: sound.start + clip.start * spb,
          end: sound.start + clip.loopEnd(bpb) * spb,
          clip: clip);
    } else if (clip.warped case var made?
        when clip.warpedFor == clip.warpSignature(spb)) {
      // Rendered onto the song's beats: its start and loop's end there.
      played = made.copyWith(
          start: clip.start * spb, end: clip.loopEnd(bpb) * spb, clip: clip);
    } else {
      // Being made: what it played until it is.
      played = was.copyWith(clip: clip);
    }
    replaceElement(
        e.copyWith(
            clip: e.clip.copyWith(
                playlist: [played, ...e.clip.playlist.skip(1)],
                // Its gain the clip's, and its fades the timeline's.
                volume: dbToGain(clip.gain),
                fadeIn: fades.$1,
                fadeOut: fades.$2)),
        transient: transient);
    if (render && !transient && clip.needsRender) _renderTimelineSoon(e.id);
  }

  /// _rendered is [clip] as its sound is made: without its fades, which
  /// the timeline plays.
  SessionClip _rendered(SessionClip clip) =>
      clip.copyWith(fadeIn: 0, fadeOut: 0, fade: false);

  void _renderTimelineSoon(String id) {
    _timelineRenders[this]?.cancel();
    _timelineRenders[this] = Timer(const Duration(milliseconds: 400), () {
      unawaited(renderTimelineClip(id));
    });
  }

  /// renderTimelineClip makes sound [id]'s clip's sound -- warped, pitched,
  /// faded, enveloped -- where it has changed, and plays it: not an undo
  /// step of its own, as the clip's change is.
  Future<void> renderTimelineClip(String id) async {
    var e = _document.elementById(id);
    if (e is! AudioElement || e.clip.playlist.isEmpty) return;
    var clip = e.clip.playlist.first.clip;
    if (clip == null || !clip.needsRender) return;
    var spb = _document.audio.secondsPerBeat;
    var signature = clip.warpSignature(spb);
    var made = await _playedSound(clip);
    if (made == null || _disposed) return;
    // Changed again meanwhile: made next.
    var now = _document.elementById(id);
    if (now is! AudioElement || now.clip.playlist.isEmpty) return;
    var current = now.clip.playlist.first.clip;
    if (current == null || current.warpSignature(spb) != signature) return;
    // With the timeline's fades, as they are now.
    _setTimelineClip(
        now, timelineClipOf(now).copyWith(warped: made, warpedFor: signature),
        transient: true, render: false);
  }
}

/// _timelineRenders are each controller's waits before rendering a
/// timeline clip again.
final Expando<Timer> _timelineRenders = Expando("timelineRenders");
