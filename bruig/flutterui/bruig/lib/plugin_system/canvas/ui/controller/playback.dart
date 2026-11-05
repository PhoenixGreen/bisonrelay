part of '../canvas_controller.dart';

// The view, playback, the control bar's switches and live counters.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasPlayback on CanvasController {
  void resetZoom() {
    _zoom = 1;
    _pan = const Offset2(0, 0);
    _notifyView();
  }

  /// showWhole and fitWidth are the two frame buttons on the band. Each also
  /// clears the zoom, as both buttons promise.
  void showWhole() {
    fit = CanvasFit.whole;
    resetZoom();
  }

  void fitWidth() {
    fit = CanvasFit.width;
    resetZoom();
  }

  void zoomBy(double factor) => zoom = _zoom * factor;

  /// followPan is the view where the page has been scrolled to by hand --
  /// the scroll bars, two fingers, the wheel -- kept so the zoom zooms about
  /// it. Nothing is drawn again for it: the page has moved already.
  void followPan(Offset2 value) => _pan = value;

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

  /// _runsScenes is whether the transport works across the scenes: Play all
  /// scenes, on a scene rather than the master.
  bool get _runsScenes =>
      _playAll && _document.hasScenes && !_document.editingMaster;

  void play() {
    // A stop waiting for an action is waited for no longer.
    _endWait();
    // Playing only the slots: Play is the timeline's -- the slots stop, and
    // the piece plays from its playhead.
    if (_sessionOnly) {
      _haltClips();
      _playback?.cancel();
      _playback = null;
      _sessionOnly = false;
    }
    if (playing) return;
    _playedFrom = (_document.at, _frame);
    // Sounds that start by themselves start with the canvas -- before the
    // checks below, since a page that is a still is still a page with music
    // on it.
    _autoplayAudio();
    // _playback is set below; the timed media are cued once it is.
    scheduleMicrotask(_syncTimeline);

    // The whole document: the playhead runs through the sequence, and the
    // editor follows it to each scene, so panel, timeline and canvas agree.
    // Not while a game plays: the game says which scene is showing.
    if (_playAll && _document.hasScenes && !gaming) {
      if (_document.playFrames <= 1) return;
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
      _loopCounts.clear();
      _startTimer();
      notifyListeners();
      return;
    }

    if (_document.frames <= 1) return;
    _loopCounts.clear();
    _startTimer();
    notifyListeners();
  }

  void _startTimer() {
    _playback?.cancel();
    // Twice a frame, to notice a frame falling due soon after it does; each
    // tick moves the playhead on by however many frames have actually
    // passed. See _tick.
    var interval = Duration(
        microseconds:
            (500000 / _document.frameRate).round().clamp(4000, 500000));
    _clockFrames = 0;
    _clockShift = 0;
    _playWatch = Stopwatch()..start();
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
    // Practising, the clock runs at the tempo set -- see practiceRate.
    var seconds =
        (clockForTest?.call() ?? elapsed) / 1000000 * _clockRate + _clockShift;
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
        if (at != _motionPainted) {
          _motionPainted = at;
          _notifyView();
        }
      }
      // The clips' envelopes of their channels' settings, moving.
      if (_clipChannels.isNotEmpty) _applyMix();
      return;
    }
    var now = seconds * rate;
    var due = now.floor() - _clockFrames;
    // A long stall -- the window dragged, the machine asleep -- is let go
    // rather than raced through: past a few frames behind, it carries on
    // from the clock without playing out what was missed.
    if (due > 6) {
      _clockFrames += due - 6;
      due = 6;
    }
    for (var i = 0; i < due && _playback != null; i++) {
      _clockFrames++;
      _step();
    }
    if (_playback != null) {
      _followSound(now - _clockFrames);
      // A game's slots are stepped by the game: see stepGame.
      if (!gaming && (_clipChannels.isNotEmpty || _clipRecord != null)) {
        _sessionStep(_sessionNow);
      }
      if (!gaming && motionPlayer.offTimeline) _motionStep();
    }
  }

  /// betweenFrames is how far past the frame it is on the playhead has
  /// really got, nought to just under one -- nought when it is not playing.
  /// The playhead moves a whole frame at a time; this is for what is drawn
  /// smoothly between them (see scene_renderer's betweenFrames).
  double get betweenFrames {
    // Only the slots playing, the playhead stands still.
    if (_playback == null || clockForTest != null || _sessionOnly) return 0;
    var rate = math.max(1, _document.frameRate);
    var now =
        (_playWatch.elapsedMicroseconds / 1000000 * _clockRate + _clockShift) *
            rate;
    return (now - _clockFrames).clamp(0.0, 0.999);
  }

  /// playsDrift is whether the scene on the stage has a drift in it --
  /// a picture's, or one of its layers' -- and so wants drawing on every
  /// screen refresh while it plays, not only on each new frame.
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

  /// _followSound keeps the playhead with the sound it is playing.
  ///
  /// The sound plays by the sound card's clock, which does not run at quite
  /// the computer's speed. The playhead's clock is eased a little each tick
  /// toward where the sound has got, so the sound is never moved for drift.
  /// A difference too big to be drift (a hold, a jump) is left for the cue to
  /// put right. [into] is how far past its frame the playhead has got.
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
      _clockShift += ahead * 0.1;
      return;
    }
  }

  void pause() {
    if (_practice != null) _endPractice();
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

  void togglePlay() => playing ? pause() : play();

  /// stopPlaying is the control bar's Stop: playing, back to where Play
  /// started, as a take is gone over again; stopped already, back to the
  /// very start.
  void stopPlaying() {
    // Only the slots playing: they stop, the playhead stays where it is.
    if (_sessionOnly) {
      pause();
      return;
    }
    var from = _playedFrom;
    if (!playing || from == null) {
      stop();
      return;
    }
    pause();
    var (scene, frame) = from;
    if (scene != _document.at && scene < _document.allScenes.length) {
      goToScene(scene);
    }
    this.frame = frame;
  }

  /// metronome is whether a click sounds on every beat while a piece of
  /// sound plays. The editor's, not the document's: it is never exported.
  bool get metronome => _metronome;

  set metronome(bool on) {
    if (_metronome == on) return;
    _metronome = on;
    _syncMetronome();
    notifyListeners();
  }

  /// metronomeAvailable is false where the engine has no click to play --
  /// SoLoud's buses, with the mix engine switched off.
  bool get metronomeAvailable => !(_audio?.metronomeUnavailable ?? false);

  void _syncMetronome() {
    var on = playing &&
        _metronome &&
        _document.kind.isAudio &&
        _previewing == null &&
        _previewAt == null;
    if (!on && _audio == null) return;
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

  /// bandState is how mixer band [section] is shown: whole, minimised to
  /// its least, or hidden -- each band in turn from the rail at the
  /// mixer's right edge, as Ableton's are.
  BandState bandState(MixerSection section) => _bandStates[section]!;

  /// restoreMixer puts the mixer's bands and returns back as they were
  /// left -- see CanvasPreferences.mixerBands -- without notifying, for the
  /// screen to call as it opens. A band left of an unknown name keeps its
  /// own; at least one band is always shown.
  void restoreMixer(List<String> bands, bool returns) {
    for (var (i, s) in MixerSection.values.indexed) {
      if (i >= bands.length) break;
      var state = BandState.values.where((b) => b.name == bands[i]).firstOrNull;
      if (state != null) _bandStates[s] = state;
    }
    if (CanvasController._mainBands
        .every((s) => _bandStates[s] == BandState.hidden)) {
      _bandStates[MixerSection.mixer] = BandState.shown;
    }
    _returnsShown = returns;
  }

  /// mixerBandNames are the bands' states by name, in order, for keeping.
  List<String> get mixerBandNames =>
      [for (var s in MixerSection.values) _bandStates[s]!.name];

  /// toggleMixerSection is a band's rail button: shown, then minimised, then
  /// hidden, then shown again (the sends only shown and hidden). The last of
  /// the clips, devices and mixer bands showing is never hidden: it goes back
  /// to shown instead.
  void toggleMixerSection(MixerSection section) {
    var next = switch (_bandStates[section]!) {
      BandState.shown when section == MixerSection.sends => BandState.hidden,
      BandState.shown => BandState.minimised,
      BandState.minimised => BandState.hidden,
      BandState.hidden => BandState.shown,
    };
    if (next == BandState.hidden &&
        CanvasController._mainBands.contains(section) &&
        CanvasController._mainBands
            .where((s) => s != section)
            .every((s) => _bandStates[s] == BandState.hidden)) {
      next = BandState.shown;
    }
    _bandStates[section] = next;
    notifyListeners();
  }

  /// narrowStrips is which of the mixer's columns are narrow, by key: each
  /// made narrow or wide by itself, or all together -- see setAllNarrow.
  Set<String> get narrowStrips => Set.unmodifiable(_narrowStrips);

  void toggleNarrow(String key) {
    if (!_narrowStrips.remove(key)) _narrowStrips.add(key);
    notifyListeners();
  }

  /// setAllNarrow makes every column in [keys] narrow, or every one wide.
  void setAllNarrow(Iterable<String> keys, bool narrow) {
    narrow ? _narrowStrips.addAll(keys) : _narrowStrips.removeAll(keys);
    notifyListeners();
  }

  /// returnsShown is whether the mixer shows the returns beside the master:
  /// hidden, for the channels' room. What is sent to them is still heard.
  bool get returnsShown => _returnsShown;

  set returnsShown(bool on) {
    if (_returnsShown == on) return;
    _returnsShown = on;
    notifyListeners();
  }

  /// followPlayhead is whether the timeline scrolls to keep the playhead in
  /// view while it plays.
  bool get followPlayhead => _followPlayhead;

  set followPlayhead(bool on) {
    if (_followPlayhead == on) return;
    _followPlayhead = on;
    notifyListeners();
  }

  /// looping is whether playing goes round between [loopRange]'s ends. For
  /// working on a part: the timeline's own Loop action, which a published
  /// piece obeys, is a different thing and is left alone.
  bool get looping => _looping;

  set looping(bool on) {
    if (_looping == on) return;
    _looping = on;
    if (on) _loop ??= _defaultLoop();
    notifyListeners();
  }

  /// loopRange is where the loop starts and how long it is, in frames --
  /// the one set, or until one is, where it would start.
  (int, int) get loopRange {
    var (from, length) = _loop ?? _defaultLoop();
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    return (from, length.clamp(1, frames - from).toInt());
  }

  /// setLoop moves the loop: to start at [from], [length] long.
  void setLoop(int from, int length) {
    var frames = math.max(1, _document.frames);
    from = from.clamp(0, frames - 1).toInt();
    _loop = (from, length.clamp(1, frames - from).toInt());
    notifyListeners();
  }

  /// _defaultLoop is the loop a first press makes. A piece of sound: the
  /// section the playhead is in, or four bars from the bar it is in. Scenes:
  /// the whole scene.
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

  /// addLocator puts a named locator under the playhead -- or, with one
  /// there, leaves it.
  void addLocator() {
    var doc = _document;
    if (doc.actions.any((a) => a.frame == _frame)) return;
    var count =
        doc.actions.where((a) => a.kind == TimelineActionKind.locator).length +
            1;
    apply(doc.copyWith(
        actions: [
      ...doc.actions,
      TimelineAction(
          id: motionId("m"),
          frame: _frame,
          kind: TimelineActionKind.locator,
          label: "Locator $count"),
    ]..sort((a, b) => a.frame.compareTo(b.frame))));
  }

  /// engineLoad is how hard the mix engine is working -- the share of each
  /// block's time spent making it, nought to one -- or null where the
  /// editor's sound is not going through it.
  double? get engineLoad => switch (_audio?.engine) {
        DartAudioEngine e => e.load,
        _ => null,
      };

  void stop() {
    pause();
    stopPreview();
    stopAudio();
    frame = 0;
  }

  /// tickForTest advances the playhead one frame, the way the timer does, so
  /// a test need not wait on a real timer.
  @visibleForTesting
  void tickForTest() => _step();

  @visibleForTesting
  void tickClockForTest() => _tick(0);

  /// _step advances one frame and obeys whatever marker is on the new one.
  /// Markers apply after the advance, so a stop on frame 30 means "having
  /// reached 30, stop".
  void _step() {
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

      // Playing the document rather than watching one join: the editor is
      // walked along with the playhead, and a scene that has been told to
      // hold stops it there.
      if (_playAll) {
        var place = placeInSequence(_document, next);
        if (place.scene != _document.at) {
          var last = _document.allScenes[_document.at];
          if (last.holds) {
            stopPreview();
            return;
          }
          _document = _document.goToScene(place.scene);
          turned = true;
          _audioFollowsPage(turned: true);
          _autoplayAudio();
        }
        _frame =
            place.frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      }
      _syncTimeline();
      _notifyPlayhead(turned);
      return;
    }

    // Waiting to be played: the playhead holds on the note.
    if (_practice != null && _practiceHolds(_frame + 1)) {
      _notifyView();
      return;
    }
    var next = _frame + 1;
    // Round the loop: from its end back to its start -- but only from inside
    // it, so a playhead put past the loop plays on from there.
    if (_looping) {
      var (from, length) = loopRange;
      var end = from + length;
      if (_frame < end && next >= end) next = from;
    }
    if (next >= _document.frames) next = 0;
    var was = _frame;
    _frame = next;
    if (_practice != null) _practiceStep(was, next);

    for (var action in _document.actions) {
      if (action.frame != next) continue;
      switch (action.kind) {
        case TimelineActionKind.stop:
          pause();
          if (action.waitsFor.isNotEmpty) _waitForAction(action.waitsFor);
        case TimelineActionKind.pause:
          // The hold steps the playhead back to where it is for as many ticks
          // as it asks, as a countdown rather than a sleep, so the window
          // stays responsive and the playhead can be dragged out of it.
          var held =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
          if (held < action.holdFrames) _frame = next - 1 < 0 ? 0 : next;
          if (held >= action.holdFrames) _loopCounts.remove(action.frame);
        case TimelineActionKind.loop:
          var count =
              _loopCounts.update(action.frame, (v) => v + 1, ifAbsent: () => 1);
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
    _notifyPlayhead(false);
  }

  /// _notifyPlayhead tells the playhead has moved on: what draws it is
  /// drawn again, but nothing that redraws on a change to the canvas itself
  /// (see revision) -- the settings column, built at every frame of play,
  /// was most of what playing cost. Turned to another scene, everything.
  void _notifyPlayhead(bool turned) {
    if (turned) {
      notifyListeners();
    } else {
      _notifyView();
    }
  }

  /// counterTicks counts how many times the running counters have moved, so
  /// the stage's painter can tell something changed: counts are not in the
  /// document.
  int get counterTicks => _counterTicks;

  /// counterValue is what [e] is showing now: a clock shows the time of day,
  /// anything else wherever its own count has got to.
  double counterValue(CounterElement e) {
    if (!e.live) return e.from;
    if (e.source == CounterSource.clock) return _secondsOfDay();
    // A game's count: where the game has got it, else where it starts.
    if (e.source == CounterSource.game) {
      var count =
          _document.counts.where((c) => c.id == e.gameCount).firstOrNull;
      if (count == null) return e.from;
      return (_game?.countOf(_document, count.id) ?? count.start).toDouble();
    }
    return _counters[e.id] ?? e.from;
  }

  /// counterRunning is whether [e] is counting at this moment.
  ///
  /// The element's own `running` is where it starts; this is where it has got
  /// to. A clock is always running.
  bool counterRunning(CounterElement e) =>
      e.live &&
      (e.source == CounterSource.clock || _countersRunning.contains(e.id));

  /// startCounters gets every counter that says it starts running going, which
  /// is what opening a canvas with a clock on it should do.
  void startCounters() {
    for (var e in _document.elements) {
      if (e is CounterElement && e.live && e.running) _runCounter(e, true);
    }
  }

  /// pressCounterButton is what one of a counter's own buttons does. Returns
  /// true where the press was handled here; Input returns false, and the
  /// caller asks for a number (see setCounterValue).
  bool pressCounterButton(CounterElement e, CounterButton button) {
    if (!e.live) return true;
    switch (button) {
      case CounterButton.startStop:
        _runCounter(e, !_countersRunning.contains(e.id));
        return true;
      case CounterButton.reset:
        _counters[e.id] = e.from;
        _countersSince[e.id] = DateTime.now();
        _counterTicks++;
        notifyListeners();
        return true;
      case CounterButton.input:
        return false;
    }
  }

  /// setCounterValue is the answer to the Set button: the number to count on
  /// from. It does not start or stop anything.
  void setCounterValue(CounterElement e, double value) {
    _counters[e.id] = value;
    _countersSince[e.id] = DateTime.now();
    _counterTicks++;
    notifyListeners();
  }

  void _runCounter(CounterElement e, bool on) {
    if (on) {
      _counters.putIfAbsent(e.id, () => e.from);
      _countersSince[e.id] = DateTime.now();
      _countersRunning.add(e.id);
      _counterTicks++;
      _startCounterTimer();
    } else {
      _countersRunning.remove(e.id);
      if (_countersRunning.isEmpty) {
        _counterTimer?.cancel();
        _counterTimer = null;
      }
    }
    notifyListeners();
  }

  void _startCounterTimer() {
    if (_counterTimer != null) return;
    // Twenty times a second, so a count to two decimal places is seen
    // changing; the cost is a repaint of a number.
    _counterTimer =
        Timer.periodic(const Duration(milliseconds: 50), (_) => tickCounters());
  }

  /// tickCounters moves every running counter on by the time that has passed:
  /// by the clock rather than a fixed step per tick, since the timer loses
  /// time whenever the window is busy.
  @visibleForTesting
  void tickCounters({DateTime? now}) {
    if (_countersRunning.isEmpty) return;
    var at = now ?? DateTime.now();
    var moved = false;
    for (var id in _countersRunning.toList()) {
      var e = _document.elementById(id);
      if (e is! CounterElement || !e.live) {
        _countersRunning.remove(id);
        continue;
      }
      var since = _countersSince[id] ?? at;
      var seconds = at.difference(since).inMicroseconds / 1000000;
      if (seconds <= 0) continue;
      _countersSince[id] = at;

      var value = _counters[id] ?? e.from;
      // Towards the far end, whichever way round the two ends are: the rate
      // is how fast, not which way.
      var step = e.rate.abs() * seconds * (e.span < 0 ? -1 : 1);
      value += step;

      // Stopped at the end, or back round to the start.
      var done = e.span < 0 ? value <= e.to : value >= e.to;
      if (done && e.span != 0) {
        if (e.loop) {
          var over = (value - e.to).abs();
          var span = e.span.abs();
          value = span <= 0 ? e.from : e.from + (over % span) * (e.span.sign);
        } else {
          value = e.to;
          _countersRunning.remove(id);
        }
      }
      _counters[id] = value;
      moved = true;
    }
    if (_countersRunning.isEmpty) {
      _counterTimer?.cancel();
      _counterTimer = null;
    }
    if (moved) {
      _counterTicks++;
      // Counts are not in the canvas: see _notifyPlayhead.
      _notifyView();
    }
  }

  /// _secondsOfDay is the reader's own clock, as a number of seconds.
  double _secondsOfDay() {
    var now = DateTime.now();
    return now.hour * 3600 +
        now.minute * 60 +
        now.second +
        now.millisecond / 1000;
  }

  /// runButtonAction is what pressing a button element does, both in the
  /// editor's preview and in a published interactive canvas. Returns the URL
  /// a link button asked to open, if any, so opening it (leaving the app)
  /// stays the caller's decision.
  String? runButtonAction(ButtonAction action) {
    switch (action.kind) {
      case ButtonActionKind.goToFrame:
        pause();
        frame = action.frame;
      case ButtonActionKind.playFrom:
        frame = action.frame;
        play();
      case ButtonActionKind.playToFrame:
        play();
      case ButtonActionKind.play:
        play();
      case ButtonActionKind.pause:
        pause();
      case ButtonActionKind.togglePlay:
        togglePlay();
      case ButtonActionKind.restart:
        frame = 0;
        play();
      case ButtonActionKind.toggleElement:
        var target = _document.elementById(action.elementId);
        if (target != null) {
          replaceElement(target.withBase(visible: !target.visible));
        }
      case ButtonActionKind.goToScene:
        var to = _document.sceneIndexNamed(action.elementId);
        if (to >= 0) {
          pause();
          goToScene(to);
          frame = 0;
        }
      case ButtonActionKind.openLink:
        return action.url;
      // A sound or a video: the same five things done to either.
      case ButtonActionKind.playSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            _heard();
            unawaited(audio.play(e));
          case VideoElement e:
            _heard();
            unawaited(video.play(e));
        }
      case ButtonActionKind.pauseSound:
        _audio?.pause(action.elementId);
        _video?.pause(action.elementId);
      case ButtonActionKind.toggleSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            _heard();
            unawaited(audio.toggle(e));
          case VideoElement e:
            _heard();
            unawaited(video.toggle(e));
        }
      case ButtonActionKind.stopSound:
        _audio?.stop(action.elementId);
        _video?.stop(action.elementId);
      case ButtonActionKind.muteSound:
        switch (_mediaById(action.elementId)) {
          case AudioElement e:
            audio.toggleMute(e);
          case VideoElement e:
            video.toggleMute(e);
        }
    }
    return null;
  }
}
