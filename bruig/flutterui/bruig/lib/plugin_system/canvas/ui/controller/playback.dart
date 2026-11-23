part of '../canvas_controller.dart';

// Part of CanvasController: playback. Play, pause, stop and the steps of the
// transport; the timer and the clocks it keeps time by, eased to the sound;
// each frame stepped, with the markers obeyed in play; the editor's loop; the
// metronome kept in step; and telling of the playhead as it moves. Its state
// is _PlaybackState, at the end of this file.

extension CanvasPlayback on CanvasController {
  /// stepFrame moves the playhead, and stops playback first, or the next
  /// tick would undo the step. While Play runs every scene, a step past
  /// either end of a scene goes on into the next or previous one.
  void stepFrame(int by) {
    pause();
    var document = _document;
    if (!_runsScenes) {
      frame = _frame + by;
      return;
    }
    goToRunFrame(document.startOfScene(document.at) + _frame + by);
  }

  /// toStart is the transport's first button: the playhead to the start of
  /// the scene, or, already there while Play runs every scene, to the start
  /// of the scene before, so pressed again and again it walks back through
  /// the run, scenes joined by a cut included.
  void toStart() {
    if (!_runsScenes) {
      stepFrame(-_frame);
      return;
    }
    pause();
    var document = _document;
    var start = document.startOfScene(document.at);
    var here = start + _frame;
    goToRunFrame(here > start
        ? start
        : document.at > 0
            ? document.startOfScene(document.at - 1)
            : 0);
  }

  /// goToRunFrame puts the playhead on frame [run] of the whole run, on
  /// whichever scene that is; inside a transition the canvas shows the
  /// transition, as playing does. Counted in the run's own frames because
  /// scenes overlap where a transition joins them.
  void goToRunFrame(int run) {
    var document = _document;
    run = run.clamp(0, math.max(0, document.playFrames - 1)).toInt();
    var place = placeInSequence(document, run);
    if (place.scene != document.at) goToScene(place.scene);
    frame = place.frame;
    var showing = place.changing ? run : null;
    if (showing != _previewAt) {
      _previewAt = showing;
      notifyListeners();
    }
  }

  /// playsEveryScene is whether Play runs along every scene, one after
  /// another, rather than the scene in front: Play all, on a canvas with
  /// scenes. The timeline is laid along the whole run while it does.
  bool get playsEveryScene => _playAll && _document.hasScenes;

  /// _runsScenes is whether the transport's steps (stepFrame, toStart, Stop)
  /// go on from one scene into the next: [playsEveryScene], on a scene. Not
  /// on the master, whose frames are the run's already.
  bool get _runsScenes => playsEveryScene && !_document.editingMaster;

  /// canPlay is whether Play has more than one frame to run: the whole run
  /// while it plays every scene, else the scene.
  bool get canPlay =>
      (playsEveryScene ? _document.playFrames : _document.frames) > 1;

  void play() {
    // A stop waiting for an action is waited for no longer.
    _endWait();
    // Each Code panel's panes show what the scene shows again, its clock's.
    _forgetCodePicks();
    _codeFull.clear();
    // Playing only the slots: Play is the timeline's -- the slots stop, and
    // the piece plays from its playhead.
    if (_sessionOnly) {
      _haltClips();
      _playback?.cancel();
      _playback = null;
      _sessionOnly = false;
    }
    if (playing) return;
    _playbackState.playedFrom = (_document.at, _frame);
    // A stop's label is shown until it plays again: see holdingMarker.
    _playbackState.stoppedAt = null;
    // The session's clock from the playhead: see _sessionClock.
    _sessionClock = _frame / math.max(1, _document.frameRate);
    // Sounds that start by themselves start with the canvas, before the
    // checks below: a still page can still have music on it.
    _autoplayAudio();
    // _playback is set below; the timed media are cued once it is.
    scheduleMicrotask(_syncTimeline);

    // The whole document: the playhead runs through the sequence, and the
    // editor follows it to each scene, so panel, timeline and canvas agree.
    // Not while a game plays: the game says which scene is showing.
    if (playsEveryScene && !gaming) {
      if (!canPlay) return;
      _previewEnd = _document.playFrames - 1;
      // From the playhead, wherever it has been put: the run's frame under
      // it on the ruler. At the very end, from the start.
      var from = _document.editingMaster
          ? _frame
          : _document.startOfScene(_document.at) + _frame;
      if (from >= _previewEnd) {
        if (!_document.editingMaster && _document.at != 0) goToScene(0);
        _frame = 0;
        from = 0;
      }
      _previewAt = from;
      _playbackState.loopCounts.clear();
      _startTimer();
      notifyListeners();
      if (_frame == 0) _sceneBegins();
      return;
    }

    if (_document.frames <= 1) return;
    _playbackState.loopCounts.clear();
    _startTimer();
    notifyListeners();
    // From the top, the scene starts: what starts with it starts, as it
    // will for whoever the canvas is sent to.
    if (_frame == 0) _sceneBegins();
  }

  void _startTimer() {
    _playback?.cancel();
    // Twice a frame, to notice a frame falling due soon after it does; each
    // tick moves the playhead on by however many frames have actually
    // passed. See _tick.
    var interval = Duration(
        microseconds:
            (500000 / _document.frameRate).round().clamp(4000, 500000));
    _playbackState.clockFrames = 0;
    _playbackState.clockShift = 0;
    _playbackState.clockFrom = 0;
    _playbackState.clockFromFrame = 0;
    _playbackState.clockPace = math.max(1, _document.frameRate) * _clockRate;
    _playbackState.playWatch = Stopwatch()..start();
    // A periodic timer's tick counts the intervals that have passed, not the
    // callbacks that ran, so tick times interval is the time since Play, by
    // the same clock a test's fake time drives.
    _playback = Timer.periodic(
        interval, (t) => _tick(t.tick * interval.inMicroseconds));
  }

  /// _tick moves the playhead on to where the clock says it should be: one
  /// frame at a time, so a marker on a frame passed over is still obeyed.
  void _tick(int elapsed) {
    var rate = math.max(1, _document.frameRate);
    var raw = (clockForTest?.call() ?? elapsed) / 1000000;
    // Practising, the clock runs at the tempo set -- see _clockRate.
    var seconds = raw * _clockRate + _playbackState.clockShift;
    // Only the slots: their clock goes on, the playhead does not.
    if (_sessionOnly) {
      _sessionSeconds = seconds;
      if (_clipChannels.isNotEmpty || _clipRecord != null) {
        _sessionStep(_sessionNow);
      }
      // The elements' slots: painted again as they play, a frame at a time.
      if (motionPlayer.playing) {
        _motionStep();
        var at = (_sessionNow * rate).floor();
        if (at != _playbackState.motionPainted) {
          _playbackState.motionPainted = at;
          _notifyRapid(view: true);
        }
      }
      // The clips' envelopes of their channels' settings, moving.
      if (_clipChannels.isNotEmpty) _applyMix();
      return;
    }
    // Another frame rate or practice speed since the last tick: counted from
    // here at the new pace, as the whole time since Play at the new pace
    // would leave the playhead stalled or leaping.
    var pace = rate * _clockRate;
    if (pace != _playbackState.clockPace) {
      _playbackState
        ..clockPace = pace
        ..clockFrom = raw
        ..clockFromFrame = _playbackState.clockFrames
        ..clockShift = 0;
    }
    var now = _clockAt(raw);
    var due = now.floor() - _playbackState.clockFrames;
    // A long stall -- the window dragged, the machine asleep -- is let go
    // rather than raced through: past a few frames behind, it carries on
    // from the clock without playing out what was missed.
    if (due > 6) {
      _playbackState.clockFrames += due - 6;
      due = 6;
    }
    for (var i = 0; i < due && _playback != null; i++) {
      _playbackState.clockFrames++;
      _step();
    }
    if (_playback != null) {
      _followSound(now - _playbackState.clockFrames);
      // A game's slots are stepped by the game: see stepGame.
      if (!gaming && (_clipChannels.isNotEmpty || _clipRecord != null)) {
        _sessionStep(_sessionNow);
      }
      if (!gaming && motionPlayer.offTimeline) _motionStep();
    }
  }

  /// betweenFrames is how far past its frame the playhead has really got,
  /// nought to just under one (nought when stopped), for what is drawn
  /// smoothly between frames (see scene_renderer's betweenFrames).
  double get betweenFrames {
    // Only the slots playing, the playhead stands still.
    if (_playback == null || clockForTest != null || _sessionOnly) return 0;
    var now = _clockAt(_playbackState.playWatch.elapsedMicroseconds / 1000000);
    return (now - _playbackState.clockFrames).clamp(0.0, 0.999);
  }

  /// _clockAt is the frame, with its fraction, the clock says the playhead
  /// has reached [raw] seconds after Play: counted on from where it was at
  /// the last change of pace (see _tick).
  double _clockAt(double raw) {
    var s = _playbackState;
    var rate = math.max(1, _document.frameRate);
    return s.clockFromFrame +
        ((raw - s.clockFrom) * _clockRate + s.clockShift) * rate;
  }

  /// playsDrift is whether the stage's scene has a drift (a picture's or a
  /// layer's) and so redraws at every screen refresh while playing.
  bool get playsDrift {
    for (var e in _document.elements) {
      if (e is! ImageElement) continue;
      var loop = e.animation.loop;
      if (loop.on && loop.preset.drifts) return true;
      for (var l in e.layers) {
        if (l.loop.on && l.loop.preset.drifts) return true;
      }
    }
    return false;
  }

  /// _followSound keeps the playhead with the sound it is playing. The sound
  /// runs by the sound card's clock, not quite the computer's, so the
  /// playhead's clock is eased toward it each tick and the sound is never
  /// moved for drift. A bigger gap (a hold, a jump) is left for the cue.
  /// [into] is how far past its frame the playhead has got.
  void _followSound(double into) {
    var a = _audio;
    if (a == null) return;
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      if (at == null || e is! AudioElement || !a.isPlaying(e.id)) continue;
      var clip = e.clip;
      if (clip.loop != MediaLoop.none) continue;
      var position = a.positionOf(e.id), index = a.indexOf(e.id);
      if (position == null || index == null || index >= clip.playlist.length) {
        continue;
      }
      var before = 0.0;
      for (var s in clip.playlist.take(index)) {
        before += s.span;
      }
      var heard =
          clip.at + (before + position - clip.playlist[index].start) * rate;
      var ahead = (heard - (at + into)) / rate;
      if (ahead.abs() > 0.25) return;
      _playbackState.clockShift += ahead * 0.1;
      return;
    }
  }

  void pause() {
    _rangeEnd = null;
    if (_practice != null) _endPractice();
    if (_slowSheet != null) {
      _slowRelease();
      _slowSheet = null;
    }
    // Stopped, the slots stop with it -- and a recording is kept: what was
    // played is in the part, and what the slots played on the timeline.
    // Not a game's: its sounds go on through a Stop on its timeline -- the
    // title waiting for a jump -- and stop when the game does.
    if (!gaming) _haltClips();
    // The elements' slots: playing only them, back to the timeline; over
    // the timeline, stopped where they are, off it until Back.
    if (!gaming && motionPlayer.offTimeline) {
      if (_sessionOnly) {
        motionPlayer.clear();
      } else {
        motionPlayer.halt(_document, _frame, _sessionNow);
      }
    }
    if (_recording) {
      _recording = false;
      _keepTake();
    }
    _playback?.cancel();
    _playback = null;
    _sessionOnly = false;
    _previewing = null;
    // A run of every scene, stopped, is the scene it stopped on at the frame
    // it stopped at, which is where the playhead already is; holding the
    // run's frame would keep the canvas drawing it while editing. Watching
    // one join is different: it puts itself back. See stopPreview.
    if (_playAll && _previewFrom == null) _previewAt = null;
    _syncTimeline();
    notifyListeners();
  }

  /// togglePlay is the play bar's Play button, and Space, MIDI's play, a
  /// button element's Play or pause and the piano roll's pill with it: the
  /// timeline plays or pauses. Only the slots playing, it plays the
  /// timeline rather than stopping them. In a game, a pause holds the game
  /// too, and Play lets both go; the timeline stopped on a marker in a game
  /// still only plays on.
  void togglePlay() {
    if (gaming && (_gamePaused || playing)) {
      gamePaused = !_gamePaused;
      return;
    }
    playing && !_sessionOnly ? pause() : play();
  }

  /// stopPlaying is the control bar's Stop: playing, back to where Play
  /// started, to go over a take again; stopped, back to the very start.
  void stopPlaying() {
    // Only the slots playing, or one element previewed: they stop, and the
    // playhead, which they did not move, stays where it is.
    if (_sessionOnly || _previewing != null) {
      pause();
      return;
    }
    // Watching a join: back on the scene it was watched from, as its own
    // end would put it, not where an earlier Play began.
    if (_previewAt != null && _previewFrom != null) {
      stopPreview();
      return;
    }
    var from = _playbackState.playedFrom;
    if (!playing || from == null) {
      stop();
      // Every scene playing: the start of the whole run.
      if (_runsScenes) goToRunFrame(0);
      return;
    }
    pause();
    _triggeredBack();
    var (scene, frame) = from;
    if (scene != _document.at && scene < _document.allScenes.length) {
      goToScene(scene);
    }
    this.frame = frame;
  }

  /// metronome is whether a click sounds on every beat while any canvas
  /// plays (every one has a tempo, on the play bar). The editor's, not the
  /// document's: it is never exported.
  bool get metronome => _playbackState.metronome;

  set metronome(bool on) {
    if (_playbackState.metronome == on) return;
    _playbackState.metronome = on;
    _syncMetronome();
    notifyListeners();
  }

  void _syncMetronome() {
    var sheet = _clicking;
    // Not while one element or one join is previewed; every scene playing
    // also runs on _previewAt, told apart by having no _previewFrom.
    var on = playing &&
        (_playbackState.metronome || sheet != null) &&
        _previewing == null &&
        (_previewAt == null || _previewFrom == null);
    if (!on && _audio == null) return;
    // A sheet's: on its score's beat, from its part's start, at its speed.
    if (sheet case (_, var score, var ch)?) {
      var rate = _clockRate;
      var (beats, unit) = score.timeAt(0);
      var spb = 60 / score.tempoAt(0) * 4 / unit;
      var t = (_frame - ch.clip.at) / math.max(1, _document.frameRate);
      audio.metronome(
          on: on, at: t / rate, secondsPerBeat: spb / rate, beatsPerBar: beats);
      return;
    }
    var a = _document.audio;
    audio.metronome(
        on: on,
        // On the slots' own clock, when only they play.
        at: _sessionOnly
            ? _sessionSeconds
            : _frame / math.max(1, _document.frameRate),
        secondsPerBeat: a.secondsPerBeat,
        beatsPerBar: a.beatsPerBar);
  }

  /// looping is whether playing goes round between [loopRange]'s ends. For
  /// working on a part: the timeline's own Loop action, which a published
  /// piece obeys, is a different thing and is left alone.
  bool get looping => _playbackState.looping;

  set looping(bool on) {
    if (_playbackState.looping == on) return;
    _playbackState.looping = on;
    if (on) _playbackState.loop ??= _defaultLoop();
    notifyListeners();
  }

  /// loopRange is the loop's start and length in frames: the one set, or
  /// where one would start.
  ({int from, int length}) get loopRange {
    var (from, length) = _playbackState.loop ?? _defaultLoop();
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    return (from: from, length: length.clamp(1, frames - from).toInt());
  }

  void setLoop(int from, int length) {
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    _playbackState.loop = (from, length.clamp(1, frames - from).toInt());
    notifyListeners();
  }

  /// _defaultLoop is the loop a first press makes: for sound, the section
  /// the playhead is in, or four bars from its bar; for scenes, the scene.
  (int, int) _defaultLoop() {
    var doc = _document;
    var rate = math.max(1, doc.frameRate);
    if (!doc.kind.isAudio) return (0, math.max(1, doc.frames));
    var a = doc.audio;
    var barFrames = a.secondsPerBar * rate;
    var bar = (_frame / barFrames + 1e-6).floor();
    for (var i = 0; i < a.sections.length; i++) {
      var start = a.startBar(i);
      if (bar >= start && bar < start + a.sections[i].bars) {
        return (
          (start * barFrames).round(),
          (a.sections[i].bars * barFrames).round()
        );
      }
    }
    return ((bar * barFrames).round(), (4 * barFrames).round());
  }

  void stop() {
    pause();
    _triggeredBack();
    stopPreview();
    stopAudio();
    frame = 0;
  }

  /// tickForTest advances one frame as the timer does, for tests.
  @visibleForTesting
  void tickForTest() => _step();

  @visibleForTesting
  void tickClockForTest() => _tick(0);

  /// _step advances one frame, then obeys the marker on the new one, so a
  /// stop on frame 30 means "having reached 30, stop".
  void _step() {
    // The session's clock goes on a frame, wherever the playhead goes.
    _sessionClock += 1 / math.max(1, _document.frameRate);
    // Previewing one element: it alone moves on, and the playhead stays.
    if (_previewing case var one?) {
      if (one.frame + 1 > _previewingEnd) {
        pause();
        return;
      }
      _previewing = (id: one.id, frame: one.frame + 1);
      notifyListeners();
      return;
    }
    // Watching a transition: the playhead is running through the whole
    // document rather than through the scene, and it stops at the end of the
    // stretch that was asked for rather than looping.
    var preview = _previewAt;
    if (preview != null) {
      var next = preview + 1;
      if (next > _previewEnd) {
        stopPreview();
        return;
      }
      _previewAt = next;
      var turned = false;

      // Playing the document, not one join: the editor walks along with the
      // playhead, and a scene told to hold stops it there.
      if (_playAll) {
        var place = placeInSequence(_document, next);
        // A range to play on the scene it was asked on (a button's Play to
        // frame, a sheet's bars): it stops at its end.
        if (_rangeEnd case var end?
            when place.scene == _document.at && place.frame >= end) {
          _rangeEnd = null;
          pause();
          return;
        }
        if (place.scene != _document.at) {
          var last = _document.allScenes[_document.at];
          if (last.holds) {
            stopPreview();
            return;
          }
          // As a turn by hand (goToScene): the frame the scene was left on
          // kept, and nothing on it left picked. The next scene plays from
          // the run's frame, not the one it was last left on.
          if (!_document.editingMaster) {
            _sceneFrames[_document.scene.id] = _frame;
          }
          _document = _document.goToScene(place.scene);
          _selection = {};
          _motionPicks = const {};
          _offCanvas = const {};
          _backgroundSelected = false;
          _focusedPlayer = null;
          turned = true;
          _audioFollowsPage(turned: true);
          _autoplayAudio();
        }
        _frame =
            place.frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      }
      _syncTimeline();
      _notifyPlayhead(turned);
      // The next scene begun: the last one's elements are not on it, and
      // what starts with this one starts.
      if (turned) {
        _triggeredBack();
        _sceneBegins();
      }
      return;
    }

    // Waiting to be played: the playhead holds on the note.
    if (_practice != null && _practiceHolds(_frame + 1)) {
      _notifyView();
      return;
    }
    // Held at a pause marker: the playhead stays on it a tick at a time, as
    // a countdown rather than a sleep, so the window stays responsive and
    // the playhead can be dragged out of it.
    for (var action in _document.actions) {
      if (action.kind != TimelineActionKind.pause || action.frame != _frame) {
        continue;
      }
      var key = (action.kind, action.frame);
      var held = _playbackState.loopCounts[key];
      if (held == null) continue;
      if (held < action.holdFrames) {
        _playbackState.loopCounts[key] = held + 1;
        return;
      }
      _playbackState.loopCounts.remove(key);
    }
    var next = _frame + 1;
    // Round the loop: from its end back to its start -- but only from inside
    // it, so a playhead put past the loop plays on from there.
    if (_playbackState.looping) {
      var (:from, :length) = loopRange;
      var end = from + length;
      if (_frame < end && next >= end) next = from;
    }
    // Off the end and round to the start: the scene begins again, where the
    // loop going round does not.
    var wrapped = next >= _document.frames;
    if (wrapped) next = 0;
    var was = _frame;
    // Playing a sheet's range of bars: it stops at the end of the last.
    if (_rangeEnd case var end? when next >= end || next < was) {
      _rangeEnd = null;
      _frame = math.max(0, end - 1);
      pause();
      return;
    }
    _frame = next;
    if (_practice != null) _practiceStep(was, next);
    if (_slowSheet != null) _slowStep(was, next);

    for (var action in _document.actions) {
      if (action.frame != next) continue;
      switch (action.kind) {
        case TimelineActionKind.stop:
          pause();
          _playbackState.stoppedAt = next;
          if (action.waitsFor.isNotEmpty) _waitForAction(action.waitsFor);
        case TimelineActionKind.pause:
          // Arrived: held here from the next tick, for as many as it asks.
          if (action.holdFrames > 0) {
            _playbackState.loopCounts[(action.kind, action.frame)] = 0;
          }
        case TimelineActionKind.loop:
          var count = _playbackState.loopCounts.update(
              (action.kind, action.frame), (v) => v + 1,
              ifAbsent: () => 1);
          if (action.repeats == 0 || count <= action.repeats) {
            _frame = action.target.clamp(0, _document.frames - 1).toInt();
          }
        case TimelineActionKind.jump:
          _frame = action.target.clamp(0, _document.frames - 1).toInt();
        case TimelineActionKind.locator:
          break;
      }
    }
    _syncTimeline();
    _synthLanesLive();
    _notifyPlayhead(false);
    if (wrapped) _sceneBegins();
  }

  /// holdingMarker is the marker playback is held at, whose label is shown
  /// on the canvas: a stop it stopped on, until it plays again or the
  /// playhead moves; a pause, as long as it holds. Null otherwise.
  TimelineAction? get holdingMarker {
    for (var a in _document.actions) {
      if (a.frame != _frame || a.label.isEmpty || !a.showLabel) continue;
      if (a.kind == TimelineActionKind.stop &&
          !playing &&
          _playbackState.stoppedAt == a.frame) {
        return a;
      }
      if (a.kind == TimelineActionKind.pause &&
          playing &&
          _playbackState.loopCounts.containsKey((a.kind, a.frame))) {
        return a;
      }
    }
    return null;
  }

  /// _notifyPlayhead tells that the playhead moved: what draws it redraws,
  /// not what follows the canvas itself (see revision; the settings column
  /// would cost most of playing). Turned to another scene, everything.
  void _notifyPlayhead(bool turned) {
    playheadMoved.value++;
    if (turned) {
      notifyListeners();
    } else {
      _playbackState.playheadOnly = true;
      try {
        _notifyRapid(view: true);
      } finally {
        _playbackState.playheadOnly = false;
      }
    }
  }

  /// notifyingPlayhead is whether only the playhead moving is being told
  /// of: what does not follow it (an unautomated mixer) need not rebuild.
  bool get notifyingPlayhead => _playbackState.playheadOnly;
}

/// _PlaybackState is what CanvasPlayback keeps between calls, here beside the code that
/// uses it. The controller holds one, as _playbackState; most fields are read and
/// set through CanvasPlayback's getters and setters above, which say what each is.
class _PlaybackState {
  /// playheadOnly is set only while _notifyPlayhead tells of a frame of
  /// play: see notifyingPlayhead.
  bool playheadOnly = false;

  /// loopCounts is how often each loop marker has fired, for repeat limits,
  /// and how long each pause marker has held. By kind and frame, so a pause
  /// and a loop on one frame count apart: a marker's id can be empty in an
  /// older file.
  final Map<(TimelineActionKind, int), int> loopCounts = {};

  /// stoppedAt is the frame a stop marker last stopped playback on.
  int? stoppedAt;

  /// clockFrames is how many frames the playhead has moved since playback
  /// started. It keeps time by the clock, not by counting ticks, which come
  /// late when the app is busy and would leave it behind the sound.
  int clockFrames = 0;

  /// clockPace is the frames a second of the clock the playhead is counted
  /// at (frame rate times practice speed); clockFrom and clockFromFrame are
  /// the clock's seconds since Play and clockFrames when it was last set,
  /// counted on from there (see _clockAt).
  double clockPace = 0;
  double clockFrom = 0;
  int clockFromFrame = 0;

  /// playWatch is the time since Play, read between ticks (betweenFrames).
  Stopwatch playWatch = Stopwatch();

  /// clockShift is how far, in seconds, the playhead's clock has been moved
  /// to keep with the sound -- see _followSound.
  double clockShift = 0;

  /// playedFrom is the scene and frame the last Play started from.
  (int, int)? playedFrom;

  /// metronome is the play bar's switch: see CanvasPlayback.metronome.
  bool metronome = false;

  /// looping and loop are the editor's loop: whether play goes round, and
  /// the start and length set, if one has been (see loopRange).
  bool looping = false;

  (int, int)? loop;

  /// motionPainted is the last slot-clock frame painted, slots alone playing.
  int motionPainted = -1;
}
