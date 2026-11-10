part of '../canvas_controller.dart';

// Clips launched live: the elements' slots and the session view.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

/// OffTimelineItem is one thing Back to the timeline lists: a row playing
/// from its slots ([held] 0), or a channel with [held] settings held by hand
/// off their automation lanes. [key] is the element's id or the channel's.
class OffTimelineItem {
  final String key;
  final String name;
  final int held;
  const OffTimelineItem(this.key, this.name, {this.held = 0});

  bool get isHeld => held > 0;
}

extension CanvasSession on CanvasController {
  /// liveMotion is what the renderer draws the elements off their
  /// timelines from: null with every one on it.
  LiveMotion? get liveMotion {
    LiveMotion? playing = motionPlayer.offTimeline ? motionPlayer : null;
    if (_motionPreview case (var e, var upto)) {
      return MotionPreview(playing, e, upto, pointerAt: _stagePointer);
    }
    // Nothing off its timeline, but something facing the pointer -- or a
    // game going, whose time what moves for ever goes by: the pointer and
    // the game's time alone, so the rest plays from the timeline as it
    // would.
    var running = motionPlayer.running;
    var pointing = _stagePointer != null && _facesPointer;
    if (playing == null && (pointing || running != null)) {
      return PointerLive(pointing ? _stagePointer : null, running: running);
    }
    return playing;
  }

  /// stagePointer is where the pointer is over the page, in its
  /// coordinates, or null off it: for a Look at that faces it. The stage
  /// is drawn again as it moves only where something does.
  Offset? get stagePointer => _stagePointer;
  set stagePointer(Offset? at) {
    if (at == _stagePointer) return;
    _stagePointer = at;
    motionPlayer.pointer = at;
    if (_facesPointer) _notifyView();
  }

  /// _facesPointer is facesPointer of the document, worked out once for
  /// each version of it: the pointer moves far more often than it changes.
  bool get _facesPointer {
    if (!identical(_facesPointerOf, _document)) {
      _facesPointerOf = _document;
      _facesPointerWas = facesPointer(_document);
    }
    return _facesPointerWas;
  }

  /// motionPreview is the element and join the stage previews its motion
  /// chain from, or null for every chain whole.
  (String, int)? get motionPreview => _motionPreview;

  /// previewMotionFrom shows [element] on the stage as its motion chain
  /// stands after its first [upto] pose devices -- or, with null, whole
  /// again. Shown only: nothing is changed.
  void previewMotionFrom(String element, int? upto) {
    _motionPreview = upto == null ? null : (element, upto);
    _previewTicks++;
    notifyListeners();
  }

  /// motionTick goes up as the slots play on, for the stage to paint.
  int get motionTick => motionPlayer.revision + _previewTicks;

  /// pressMotionSlot is slot [slot] of [element] pressed: its clip launched
  /// as it says -- on the next bar, or what it waits for -- or, empty, the
  /// element's clips stopped.
  void pressMotionSlot(String element, int slot) {
    var motion = _document.elementById(element)?.base.motion;
    var clip = motion?.slot(slot);
    if (clip == null) {
      stopMotion(element);
      return;
    }
    pressMotionClip(element, clip.id);
    // Linked: its own sound in the same row with it (Ken, 2026-11-10).
    var own = elementSoundKey(element);
    if (motion!.isLinked(slot) && session.at(own, slot) != null) {
      launchClip(own, slot);
    }
  }

  /// pressMotionClip is [clip] of [element] launched, as its slot would.
  void pressMotionClip(String element, String clip) {
    var c = _document.elementById(element)?.base.motion.clip(clip);
    if (c == null) return;
    var at =
        _launchTime(c.quantise == null ? null : Quantise.fromName(c.quantise));
    motionPlayer.press(_document, _frame, element, clip, at);
    _motionStep();
    notifyListeners();
  }

  /// releaseMotionClip is its slot let go: a gate stops.
  void releaseMotionClip(String element, String clip) {
    motionPlayer.release(_document, element, clip, _sessionNow);
    _motionStep();
    notifyListeners();
  }

  /// stopMotion stops what [element]'s slots play, on the next bar.
  void stopMotion(String element) {
    if (!motionPlayer.isOff(element)) return;
    motionPlayer.stop(element,
        at: playing ? _nextLaunch(_sessionNow) : _sessionNow);
    _motionStep();
    notifyListeners();
  }

  /// motionSlotState is how slot [slot] of [element] is doing: launched,
  /// or -- on its timeline, the playhead going through a placement of its
  /// clip -- playing from there.
  MotionSlotState motionSlotState(String element, int slot) {
    var e = _document.elementById(element) ??
        _masterHeardElement(element);
    var clip = e?.base.motion.slot(slot);
    var live = motionPlayer.slotState(element, clip);
    if (live != MotionSlotState.stopped ||
        e == null ||
        clip == null ||
        !playing ||
        motionPlayer.isOff(element)) {
      return live;
    }
    return placedPlaying(_document, e, clip.id, _frame)
        ? MotionSlotState.playing
        : live;
  }

  /// _masterHeardElement is element [id] on the master drawn over the scene.
  CanvasElement? _masterHeardElement(String id) => _document.editingMaster
      ? null
      : _document.masterScene?.elements.where((e) => e.id == id).firstOrNull;

  /// fireMotionTrigger starts the clips that start on [kind] of [target]:
  /// a click, a key, the scene starting.
  void fireMotionTrigger(ClipTriggerKind kind,
      [String target = "", double? value]) {
    // The scene's elements, and a game's HUD on the master over them.
    var any = [
      ..._document.elements,
      if (!_document.editingMaster) ...?_document.masterScene?.elements,
    ].any((e) =>
        e.base.motion.clips.any((c) => c.triggers.any((t) => t.kind == kind)));
    if (!any) return;
    var at = playing || gaming ? _sessionNow : _sessionStart();
    var wasOff = {
      for (var e in _elementsWithClips())
        if (motionPlayer.isOff(e)) e,
    };
    motionPlayer.fire(_document, _frame, kind, target, at, value: value);
    for (var e in _elementsWithClips()) {
      if (!wasOff.contains(e) && motionPlayer.isOff(e)) _triggeredOff.add(e);
    }
    _motionStep();
    notifyListeners();
  }

  /// _elementsWithClips are the ids of the scene's elements that have clips,
  /// and of the master's drawn over them.
  Iterable<String> _elementsWithClips() => [
        for (var e in [
          ..._document.elements,
          if (!_document.editingMaster) ...?_document.masterScene?.elements,
        ])
          if (e.base.motion.clips.isNotEmpty) e.id,
      ];

  /// _sceneBegins is a scene starting under the editor's Play, as it does
  /// in a published canvas: the clips that start with the scene start. Not
  /// in a game, which starts its scenes itself (see _gameMotionStart), nor
  /// while practising a part.
  void _sceneBegins() {
    if (gaming || _practice != null) return;
    fireMotionTrigger(ClipTriggerKind.sceneStarts);
  }

  /// _triggeredBack puts what triggers took off the timeline back on it.
  void _triggeredBack() {
    if (_triggeredOff.isEmpty) return;
    for (var e in _triggeredOff) {
      motionPlayer.leave(e);
    }
    _triggeredOff.clear();
    notifyListeners();
  }

  void _motionStep() {
    if (!motionPlayer.offTimeline) return;
    var events = motionPlayer.step(_document, _frame, _sessionNow,
        recording: _recording && !_sessionOnly);
    for (var e in events) {
      if (e is MotionBack) motionPlayer.leave(e.element);
    }
  }

  /// session is the clip slots and the scenes -- see session.dart.
  SessionGrid get session => _document.session;

  /// launchQuantise is what a launch waits for: the next bar, as Ableton's
  /// global quantisation does, or a finer grid, or nothing.
  Quantise get launchQuantise => _launchQuantise;

  set launchQuantise(Quantise q) {
    if (_launchQuantise == q) return;
    _launchQuantise = q;
    notifyListeners();
  }

  /// _sessionNow is where the session's clock is, in seconds. Playing, it
  /// keeps time with the timeline from where Play was pressed, so a clip
  /// launched on a bar is on the timeline's bar -- and goes on through a
  /// loop back (see _sessionClock).
  double get _sessionNow => gaming
      ? _gameClock
      : _sessionOnly
          ? _sessionSeconds
          : playing
              ? _sessionClock + betweenFrames / math.max(1, _document.frameRate)
              : (_frame + betweenFrames) / math.max(1, _document.frameRate);

  /// _gameClock is a game's slots' own clock: seconds since it started. Not
  /// the playhead's, which a Loop on the game's timeline sends back, taking
  /// every playing slot with it.
  double get _gameClock =>
      (gameClockForTest?.call() ?? _gameClockWatch.elapsedMicroseconds) / 1e6;

  /// sessionOnly is whether only the clip slots are playing: launched with
  /// the transport stopped, they run on a clock of their own, the timeline
  /// silent and its playhead where it was. Play, or Back to the timeline,
  /// returns to it.
  bool get sessionOnly => _sessionOnly;

  /// offTimeline is whether what is heard is not the timeline: only the
  /// slots playing, or a channel left for its slots -- what Back to the
  /// timeline lights for.
  bool get offTimeline =>
      _sessionOnly || _offTimeline.isNotEmpty || motionPlayer.offTimeline;

  /// backToTimeline goes back to the timeline: playing only the slots, they
  /// stop; a channel that left it for its slots plays it again.
  void backToTimeline() {
    if (_sessionOnly) {
      pause();
      return;
    }
    // Elements off their timelines for their slots: back on them.
    var moved = motionPlayer.offTimeline;
    motionPlayer.clear();
    _triggeredOff.clear();
    if (_offTimeline.isEmpty) {
      if (moved) notifyListeners();
      return;
    }
    for (var key in [..._offTimeline]) {
      if (_clipChannels[key]?.now != null) stopChannelClips(key);
    }
    _offTimeline.clear();
    _syncTimeline();
    notifyListeners();
  }

  /// offTimelineItems is what Back to the timeline lists (Ken, 2026-11-08):
  /// each row playing from its slots -- an element and its own sound one
  /// item, as they are one row -- then each channel with settings held by
  /// hand off their lanes.
  List<OffTimelineItem> get offTimelineItems {
    var doc = _document;
    String nameOf(String key) {
      if (doc.elementById(key) case var e?)
        return e.name.isEmpty ? key : e.name;
      return timelineChannels.where((c) => c.key == key).firstOrNull?.name ??
          key;
    }

    // The channels playing from their slots: those that left the timeline,
    // or -- only the slots playing -- every one with a clip on.
    var channels = {
      ..._offTimeline,
      if (_sessionOnly)
        for (var e in _clipChannels.entries)
          if (e.value.now != null || e.value.next != null) e.key,
    };
    var elements = {...motionPlayer.offElements};
    for (var key in channels) {
      if (key.startsWith("snd-") && doc.elementById(key.substring(4)) != null) {
        elements.add(key.substring(4));
      }
    }
    return [
      for (var id in elements) OffTimelineItem(id, nameOf(id)),
      for (var key in channels)
        if (!(key.startsWith("snd-") && elements.contains(key.substring(4))))
          OffTimelineItem(key, nameOf(key)),
      for (var e in _overridden.entries)
        if (e.value.isNotEmpty)
          OffTimelineItem(e.key, nameOf(e.key), held: e.value.length),
    ];
  }

  /// fromSlotsOf is the row playing from its slots that [key] -- an
  /// element's id or a channel's -- is part of, an element's own sound being
  /// the element's; null where it plays from the timeline. Its row is
  /// striped and has its own way back (see row_header.dart).
  OffTimelineItem? fromSlotsOf(String key) {
    for (var item in offTimelineItems) {
      if (!item.isHeld && (item.key == key || "snd-${item.key}" == key)) {
        return item;
      }
    }
    return null;
  }

  /// backToTimelineFor sends [item] alone back to the timeline: a row's
  /// clips stopped and its timeline heard again, or a channel's settings
  /// handed back to their lanes.
  void backToTimelineFor(OffTimelineItem item) {
    if (item.isHeld) {
      if (_overridden.remove(item.key) != null) {
        _applyMix();
        notifyListeners();
      }
      return;
    }
    motionPlayer.leave(item.key);
    _triggeredOff.remove(item.key);
    for (var key in {item.key, "snd-${item.key}"}) {
      var playing = _clipChannels[key];
      var off = _offTimeline.remove(key);
      if ((off || _sessionOnly) &&
          (playing?.now != null || playing?.next != null)) {
        stopChannelClips(key, now: true);
      }
    }
    // Only the slots playing, and none left: the slots stop, as Back to the
    // timeline does.
    if (_sessionOnly && offTimelineItems.every((i) => i.isHeld)) {
      pause();
      return;
    }
    _syncTimeline();
    notifyListeners();
  }

  double get _barSeconds => _document.audio.secondsPerBar;

  /// _nextLaunch is the next moment a launch at [now] waits for: on
  /// [quantise] -- a clip's own -- or the song's.
  double _nextLaunch(double now, [Quantise? quantise]) {
    var g = _document.audio.gridSeconds(quantise ?? _launchQuantise);
    if (g == null || g <= 0) return now;
    // A hair past a boundary is on it, not a whole bar from it.
    return ((now - 0.005) / g).ceil() * g;
  }

  /// _sessionStart starts the transport for the session, from the start of
  /// the bar the playhead is in -- a launch with nothing playing is heard at
  /// once, on a bar -- and is where it started.
  double _sessionStart() {
    // The slots on their own, from nought: the timeline stays where it is,
    // and silent -- see sessionOnly.
    _sessionOnly = true;
    _sessionSeconds = 0;
    _startTimer();
    _syncTimeline();
    notifyListeners();
    return 0;
  }

  /// _launchTime is when a launch now is heard: the next boundary, playing;
  /// at once, from a bar, when it starts the transport.
  double _launchTime([Quantise? quantise]) =>
      playing || gaming ? _nextLaunch(_sessionNow, quantise) : _sessionStart();

  /// clipState is how slot [row] of [channel] is doing, for the mixer.
  ClipState clipState(String channel, int row) {
    var rec = _clipRecord;
    if (rec != null && rec.channel == channel && rec.row == row) {
      return rec.started ? ClipState.recording : ClipState.recordQueued;
    }
    var ch = _clipChannels[channel];
    if (ch?.next?.row == row) return ClipState.queued;
    if (ch?.now?.row == row) {
      return ch!.stopAt != null || ch.now!.stopAt != null
          ? ClipState.stopping
          : ClipState.playing;
    }
    return session.at(channel, row) == null
        ? ClipState.empty
        : ClipState.stopped;
  }

  /// clipPlaying is whether [channel] has a clip playing from its slots, or
  /// one about to.
  bool clipPlaying(String channel) {
    var ch = _clipChannels[channel];
    return ch != null && (ch.now != null || ch.next != null);
  }

  /// clipProgress is how far round its loop [channel]'s clip has got,
  /// nought to one, or null where none is playing.
  double? clipProgress(String channel) {
    var now = _clipChannels[channel]?.now;
    if (now == null || now.length <= 0) return null;
    var t = _sessionNow - now.origin;
    if (t < 0) return 0;
    if (!now.loops) return (t / now.length).clamp(0.0, 1.0);
    return ((now.into(t) - now.loopAt) / now.length).clamp(0.0, 1.0);
  }

  /// clipAt is where [channel]'s clip has got to, in beats into what it
  /// plays -- for the clip editor's playhead -- or null where none is
  /// playing.
  double? clipAt(String channel) {
    var now = _clipChannels[channel]?.now;
    if (now == null) return null;
    var t = _sessionNow - now.origin;
    if (t < 0) return null;
    if (!now.loops && t >= now.length) return null;
    return now.into(t) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  /// anyClipPlaying is whether any slot is playing or about to.
  bool get anyClipPlaying => _clipChannels.keys.any(clipPlaying);

  /// sessionActive is whether the slots have anything going on -- playing,
  /// waiting for a bar, recording -- for the mixer to keep drawing them.
  bool get sessionActive => anyClipPlaying || _clipRecord != null;

  /// instrumentChannel is whether [channel] is a MIDI channel.
  bool instrumentChannel(String channel) => _instrumentOf(channel) != null;

  /// pressClip is a press on a clip's slot: what the clip's launch mode says
  /// -- see LaunchMode. On an empty slot, the channel stops; armed, it
  /// records into it. [velocity] is the pad's, nought to 127 -- a click is
  /// a full one -- for the clip's Velocity to set its volume by.
  void pressClip(String channel, int row, {int velocity = 127}) {
    var clip = session.at(channel, row);
    if (_clipRecord case var rec?
        when rec.channel == channel && rec.row == row) {
      _endClipRecord();
      return;
    }
    if (clip == null) {
      if (_armed.contains(channel) && _instrumentOf(channel) != null) {
        recordClip(channel, row);
      } else {
        stopChannelClips(channel);
      }
      return;
    }
    var state = clipState(channel, row);
    if (clip.launch == LaunchMode.toggle &&
        (state == ClipState.playing || state == ClipState.queued)) {
      stopChannelClips(channel);
      return;
    }
    var level = CanvasController.launchLevel(clip, velocity);
    launchClip(channel, row, level: level);
    // An element's own sound, linked: its motion in the same row with it.
    if (soundOwnerOf(_document, channel) case var owner?
        when owner.base.motion.isLinked(row)) {
      if (owner.base.motion.slot(row) case var motion?) {
        pressMotionClip(owner.id, motion.id);
      }
    }
    // Repeat: again on every launch step while it is held -- see
    // _sessionStep.
    if (clip.launch == LaunchMode.repeat) {
      var a = _document.audio;
      var step = a.gridSeconds(clip.quantise ?? _launchQuantise) ?? 0;
      if (step <= 0) step = a.secondsPerBeat;
      _repeats[channel] =
          _Repeat(row, _launchTime(clip.quantise) + step, step, level);
    }
  }

  /// pushClip is a Push's pad in Session mode: slot [row] of the
  /// [column]th channel, as the mixer has them, pressed at [velocity] -- or
  /// let go, at nought.
  void pushClip(int column, int row, int velocity) {
    var lanes = timelineChannels;
    if (column < 0 || column >= lanes.length || row < 0) return;
    var channel = lanes[column].key;
    if (velocity > 0) {
      pressClip(channel, row, velocity: velocity);
    } else {
      releaseClip(channel, row);
    }
  }

  /// pushPad is how slot [row] of the [column]th channel is doing, for its
  /// pad's light.
  PadClip pushPad(int column, int row) {
    var lanes = timelineChannels;
    if (column < 0 || column >= lanes.length || row < 0) return PadClip.empty;
    return switch (clipState(lanes[column].key, row)) {
      ClipState.empty => PadClip.empty,
      ClipState.stopped => PadClip.stopped,
      ClipState.queued || ClipState.recordQueued => PadClip.queued,
      ClipState.playing || ClipState.stopping => PadClip.playing,
      ClipState.recording => PadClip.recording,
    };
  }

  /// releaseClip is a press on a clip let go: a gated clip stops, and a
  /// repeating one stops repeating, and playing.
  void releaseClip(String channel, int row) {
    var clip = session.at(channel, row);
    if (clip == null ||
        (clip.launch != LaunchMode.gate && clip.launch != LaunchMode.repeat)) {
      return;
    }
    if (_repeats[channel]?.row == row) _repeats.remove(channel);
    var ch = _clipChannels[channel];
    if (ch == null) return;
    if (ch.next?.row == row) _cancelNext(ch, restore: true);
    if (ch.now?.row == row) {
      _endPlay(channel, ch.now!, _sessionNow);
      if (ch.now!.voice case var v?) audio.engine.stopSoftly(v, 0.01);
      ch.now = null;
    }
    _syncTimeline();
    notifyListeners();
  }

  /// launchClip plays slot [row] of [channel] from the next launch time --
  /// see launchQuantise -- in place of whatever the channel was playing.
  void launchClip(String channel, int row,
      {double level = 1, Quantise? quantise}) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    var at = _launchTime(quantise ?? clip.quantise);
    unawaited(_startClip(channel, row, clip, at, level: level));
  }

  /// launchScene plays row [row] across every channel, all from the same
  /// moment: a channel with nothing in the row stops.
  // Per-canvas cues (Ken, 2026-11-10): where a game's master has channels
  // or elements with slots of their own, its cues -- the document's,
  // SessionGrid.scenes -- are theirs, and each scene's (CanvasScene.cues)
  // its own channels' and elements': launched, renamed, added and taken
  // away apart. One grid of rows under them all. Where the master has none,
  // the canvas shown has the document's cues, as it always had.

  /// cuesApart is whether the canvas shown has cues of its own, apart from
  /// the master's: a scene, with a master that has slots in use.
  bool get cuesApart => !_document.editingMaster && _masterSlotted;

  /// _masterSlotted is whether the master is on and has channels, or
  /// elements with slots: what its cues launch.
  bool get _masterSlotted {
    var m = _document.master;
    if (!_document.masterOn || m == null) return false;
    return m.elements.any((e) =>
        e is AudioElement || e.base.motion.slots.any((s) => s.isNotEmpty));
  }

  /// cueNames are the cues of the canvas shown -- or, [master], of the
  /// master -- a name a row ("" for one named by its number).
  List<String> cueNames({bool master = false}) {
    var rows = session.rows;
    if (master || !cuesApart) return session.scenes;
    var own = _document.scene.cues ?? const <String>[];
    return [for (var i = 0; i < rows; i++) i < own.length ? own[i] : ""];
  }

  /// cueName is cue [row]'s name, or its number.
  String cueName(int row, {bool master = false}) {
    var names = cueNames(master: master);
    return row < names.length && names[row].isNotEmpty
        ? names[row]
        : "${row + 1}";
  }

  /// _cueChannels are the channels a cue of the canvas shown, or [master]'s,
  /// launches: all of them, where the canvas has no cues apart.
  Iterable<TimelineChannel> _cueChannels(bool master) {
    if (!cuesApart && !master) return timelineChannels;
    var mine = _masterChannelKeys;
    return timelineChannels.where((c) => mine.contains(c.key) == master);
  }

  /// _masterChannelKeys are the master's channels, by key.
  Set<String> get _masterChannelKeys => {
        for (var e in _document.master?.elements ?? const <CanvasElement>[])
          if (e is AudioElement) CanvasController._channelOf(e),
      };

  /// _cueElements are the elements a cue launches the slots of: the canvas
  /// shown's -- with the master's drawn over it, where it has no cues
  /// apart -- or, [master], the master's.
  List<CanvasElement> _cueElements(bool master) {
    if (master && cuesApart) return _masterHeard;
    if (cuesApart) return _document.elements;
    return _withMaster;
  }

  /// launchScene launches cue [row] of the canvas shown.
  void launchScene(int row) => launchCue(row);

  /// launchCue launches cue [row] -- of the canvas shown, or [master]'s --
  /// every one of its channels' and elements' clips in that row from the
  /// next bar.
  void launchCue(int row, {bool master = false}) {
    var at = _launchTime();
    for (var c in _cueChannels(master)) {
      var clip = session.at(c.key, row);
      if (clip != null) {
        unawaited(_startClip(c.key, row, clip, at));
      } else {
        _stopChannelAt(c.key, at);
      }
    }
    // The cue's row of every element's slots, too. An element with nothing
    // in it goes on as it is: a picture has no reason to stop moving
    // because a cue has nothing new for it.
    for (var e in _cueElements(master)) {
      if (e.base.motion.slot(row) case var clip?) {
        motionPlayer.launch(_document, _frame, e.id, clip.id, at);
      }
    }
    _motionStep();
    _sceneLaunched = row;
    _cueLaunchedMaster = master && cuesApart;
    notifyListeners();
  }

  /// sceneLaunched is the cue of the canvas shown last launched, to light.
  int? get sceneLaunched => cueLaunched();

  /// cueLaunched is the cue last launched of the canvas shown, or [master]'s.
  int? cueLaunched({bool master = false}) {
    if (!anyClipPlaying && !motionPlayer.playing) return null;
    return _cueLaunchedMaster == (master && cuesApart) ? _sceneLaunched : null;
  }

  /// stopChannelClips stops what [channel] plays from its slots, at the
  /// next launch time.
  void stopChannelClips(String channel, {bool now = false}) {
    _repeats.remove(channel);
    if (!clipPlaying(channel)) return;
    _stopChannelAt(
        channel, playing && !now ? _nextLaunch(_sessionNow) : _sessionNow);
    notifyListeners();
  }

  /// stopAllClips stops every channel's slots, at the next launch time.
  void stopAllClips() {
    var at = playing ? _nextLaunch(_sessionNow) : _sessionNow;
    for (var key in [..._clipChannels.keys]) {
      _stopChannelAt(key, at);
    }
    // A Repeat pad still held repeats nothing more.
    _repeats.clear();
    motionPlayer.stopAll(at);
    _motionStep();
    if (_clipRecord != null) _endClipRecord();
    notifyListeners();
  }

  void _stopChannelAt(String channel, double at) {
    var ch = _clipChannels[channel];
    if (ch == null) return;
    _cancelNext(ch);
    var now = ch.now;
    if (now == null) return;
    ch.stopAt = at;
    if (now.voice case var v?) {
      audio.engine
          .stopIn(v, math.max(0, at - _sessionNow - audio.engine.latency));
    }
  }

  /// _cancelNext takes back what [ch] was about to launch. With [restore],
  /// what was to have stopped for it plays on: its stop was set for the
  /// launch and cannot be taken back, so it is set going again from where
  /// it is. Without, something else is about to stop it or take over.
  void _cancelNext(_ClipChannel ch, {bool restore = false}) {
    var next = ch.next;
    if (next == null) return;
    ch.next = null;
    if (next.voice case var v?) audio.engine.stop(v);
    if (!restore) return;
    if (ch.now case var now? when ch.stopAt == null) {
      if (now.voice case var v? when now.loops) {
        unawaited(_restart(ch, now));
        audio.engine.stop(v);
      }
    }
  }

  /// _restart sets [play] going again where it has got to: its stop, set
  /// for a launch since taken back, undone.
  Future<void> _restart(_ClipChannel ch, _ClipPlay play) async {
    var clip = session.at(ch.channel, play.row);
    var sound = play.sound ?? clip?.sound;
    if (clip == null || sound == null) return;
    var track = await audio.trackOf(sound.assetId);
    if (track == null || ch.now != play) return;
    var into = play.into(_sessionNow + audio.engine.latency - play.origin);
    play.voice = audio.engine.launch(track,
        volume: _gainOf(clip) * play.level,
        delay: 0,
        at: sound.start + into,
        loop: (
          sound.start + play.loopAt,
          sound.start + play.loopAt + play.length
        ),
        channel: ch.channel);
  }

  /// _startClip plays [clip] on [channel] from [at], session seconds: the
  /// file opened -- a MIDI clip played into one first -- and started by the
  /// engine to the frame, the clip before it stopped on the same frame.
  Future<void> _startClip(String channel, int row, SessionClip clip, double at,
      {double? origin, _ClipPlay? carries, double level = 1}) async {
    var ch = _clipChannels[channel] ??= _ClipChannel(channel);
    _cancelNext(ch);
    ch.stopAt = null;
    var spb = _document.audio.secondsPerBeat;
    var loopLength = math.max(0.05, clip.bars * _barSeconds);
    var loopAt = clip.loopStart * spb;
    // From its start: on into its loop, or -- not looping -- to the loop's
    // end. A start past the loop's end is the loop's start.
    var startAt = clip.start * spb;
    if (clip.loop && startAt >= loopAt + loopLength) startAt = loopAt;
    var play = _ClipPlay(
        clip.id,
        row,
        at,
        clip.loop ? loopLength : math.max(0.05, loopAt + loopLength - startAt),
        clip.loop,
        startAt: startAt,
        loopAt: loopAt)
      ..level = carries?.level ?? level;
    // Legato: on from where the clip it takes over from had got to.
    if (clip.legato) {
      if ((ch.now ?? ch.next) case var was?) play.origin = was.origin;
    }
    if (origin != null) play.origin = origin;
    if (carries != null) {
      play
        ..followed = carries.followed
        ..followFrom = carries.followFrom;
    }
    // What it takes over from, remembered now: by the time its file is open
    // the clock may already have put it in that one's place, and that one,
    // still sounding, must still be stopped.
    var replaced = ch.now;
    ch.next = play;
    notifyListeners();
    // Still the channel's -- about to play, or by now playing: a launch on
    // a bar already reached is moved on to it before its file is open.
    bool still() =>
        !_disposed &&
        identical(_clipChannels[channel], ch) &&
        (ch.next == play || ch.now == play);
    var sound =
        clip.midi ? await _clipSound(channel, clip) : await _playedSound(clip);
    play.sound = sound;
    if (!still()) return;
    var track = sound == null || !await audio.ready()
        ? null
        : await audio.trackOf(sound.assetId);
    if (!still()) return;
    var latency = audio.engine.latency;
    var delay = at - _sessionNow - latency;
    var into = 0.0;
    if (delay < 0) {
      // Late -- the file took a while to open: started where it would have
      // got to, so it is still in time. Not a game's sound played once --
      // a coin's chime -- which is heard whole, its start not cut off.
      into = gaming && !clip.loop ? 0 : -delay;
      delay = 0;
    }
    for (var was in {replaced, ch.now}) {
      if (was == null || identical(was, play)) continue;
      if (was.voice case var v?) audio.engine.stopIn(v, delay);
    }
    if (track != null && sound != null) {
      // How far into it it is when it is heard: late, or taken over.
      var t = at - play.origin + into;
      if (!play.loops && t >= play.length) return;
      var voice = audio.engine.launch(track,
          volume: _gainOf(clip) * play.level,
          delay: delay,
          at: sound.start + play.into(t),
          loop: play.loops
              ? (
                  sound.start + play.loopAt,
                  sound.start + play.loopAt + play.length
                )
              : null,
          channel: channel);
      if (voice != null && !play.loops) {
        audio.engine.stopIn(voice, delay + play.length - t);
      }
      play.voice = voice;
    }
  }

  /// _playKey is what [clip] sounds like, for telling an edit that changes
  /// it -- its sound, where it starts and goes round, how loud, how it is
  /// warped, its notes -- from one that does not: its name, its colour.
  String _playKey(SessionClip clip) => [
        clip.midi
            ? "${clip.notes.map((n) => n.toJson().join(",")).join(";")}:"
                "${controlsToJson(clip.controls)}"
            : "${clip.sound?.assetId}:${clip.sound?.start}:${clip.sound?.end}",
        clip.start,
        clip.loopStart,
        clip.bars,
        clip.loop,
        clip.gain,
        if (!clip.midi) clip.warpSignature(_document.audio.secondsPerBeat),
      ].join("|");

  /// _followEdits plays each clip that is playing as it now is, where it
  /// was changed since [before]: from where it had got to, so an edit --
  /// reversed, its loop moved, its notes -- is heard at once, not at its
  /// next launch.
  void _followEdits(CanvasDocument before) {
    if (_clipChannels.isEmpty || identical(before.session, session)) return;
    for (var ch in [..._clipChannels.values]) {
      var now = ch.now;
      if (now == null || ch.stopAt != null) continue;
      var clip = _clipById(now.clipId);
      if (clip == null) continue;
      SessionClip? was;
      for (var (_, _, c) in before.session.clips) {
        if (c.id == now.clipId) was = c;
      }
      if (was == null || _playKey(was) == _playKey(clip)) continue;
      unawaited(_startClip(ch.channel, now.row, clip, _sessionNow,
          origin: now.origin, carries: now));
    }
  }

  /// _gainOf is [clip]'s gain as a level.
  double _gainOf(SessionClip clip) => math.pow(10, clip.gain / 20).toDouble();

  /// _follow does [clip]'s follow action, played on [ch] as [play], at
  /// [due]: see FollowAction.
  void _follow(_ClipChannel ch, _ClipPlay play, SessionClip clip, double due) {
    // A launch already waiting is what the player chose: it goes ahead.
    if (ch.next != null) return;
    var rows = [
      for (var r = 0; r < session.rows; r++)
        if (session.at(ch.channel, r) != null) r
    ];
    var here = rows.indexOf(play.row);
    if (rows.isEmpty || here < 0) return;
    int? row;
    switch (clip.follow) {
      case FollowAction.none:
        return;
      case FollowAction.stop:
        _stopChannelAt(ch.channel, due);
        return;
      case FollowAction.again:
        row = play.row;
      case FollowAction.next:
        row = rows[(here + 1) % rows.length];
      case FollowAction.previous:
        row = rows[(here - 1 + rows.length) % rows.length];
      case FollowAction.first:
        row = rows.first;
      case FollowAction.last:
        row = rows.last;
      case FollowAction.any:
        row = rows[_followDice.nextInt(rows.length)];
      case FollowAction.other:
        if (rows.length < 2) return;
        var others = [...rows]..remove(play.row);
        row = others[_followDice.nextInt(others.length)];
    }
    var next = session.at(ch.channel, row)!;
    unawaited(_startClip(ch.channel, row, next, due));
  }

  /// _sessionStep moves the slots on to [now]: a launch due starts, a stop
  /// due stops, a clip played once ends, a recording due starts or ends.
  /// Every tick, while playing.
  void _sessionStep(double now) {
    var moved = false;
    // The Repeat clips held: launched again a moment before each step, so
    // they are heard on it.
    for (var MapEntry(key: channel, value: r) in [..._repeats.entries]) {
      // Never so early that it takes the place of the one before, still
      // waiting to be heard: at most half a step ahead.
      if (now + math.min(0.25, r.step / 2) < r.nextAt) continue;
      var clip = session.at(channel, r.row);
      if (clip == null) {
        _repeats.remove(channel);
        continue;
      }
      unawaited(_startClip(channel, r.row, clip, r.nextAt, level: r.level));
      r.nextAt += r.step;
    }
    for (var ch in _clipChannels.values) {
      if (ch.next case var next? when now + 0.001 >= next.from) {
        if (ch.now case var was?) _endPlay(ch.channel, was, next.from);
        // Left the timeline for its slots, until Back to the timeline.
        if (!_sessionOnly) _offTimeline.add(ch.channel);
        ch.now = next;
        ch.next = null;
        ch.stopAt = null;
        moved = true;
      }
      var cur = ch.now;
      if (cur == null) continue;
      // Its follow action, set up a moment before it is due -- so its
      // launch is heard on time.
      if (!cur.followed && ch.stopAt == null) {
        var clip = _clipById(cur.clipId);
        if (clip != null && clip.follow != FollowAction.none) {
          var after = clip.followBars != null
              ? clip.followBars! * _barSeconds
              : cur.length;
          var due = cur.followFrom + math.max(0.05, after);
          if (now + 0.25 >= due) {
            cur.followed = true;
            _follow(ch, cur, clip, due);
          }
        }
      }
      var ends = ch.stopAt ?? (cur.loops ? null : cur.origin + cur.length);
      if (ends != null && now + 0.001 >= ends) {
        _endPlay(ch.channel, cur, ends);
        ch.now = null;
        ch.stopAt = null;
        moved = true;
      }
    }
    if (_clipRecord case var rec?) {
      if (rec.until case var until? when now + 0.001 >= until) {
        _finishClipRecord(rec, until);
        moved = true;
      } else if (!rec.started && now + 0.001 >= rec.from) {
        rec.started = true;
        moved = true;
      }
    }
    if (moved) {
      _syncTimeline();
      notifyListeners();
    }
  }

  /// _endPlay notes [play] as played to [to], for Record to write down.
  void _endPlay(String channel, _ClipPlay play, double to) {
    if (!_recording || to <= play.from) return;
    var clip = _clipById(play.clipId);
    if (clip != null) _clipLog.add(_ClipPlayed(channel, clip, play.from, to));
  }

  SessionClip? _clipById(String id) {
    for (var (_, _, c) in session.clips) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// _haltClips stops everything the slots play, at once: the transport
  /// has stopped.
  void _haltClips() {
    var now = _sessionNow;
    for (var ch in _clipChannels.values) {
      if (ch.next?.voice case var v?) audio.engine.stop(v);
      if (ch.now case var cur?) {
        _endPlay(ch.channel, cur, ch.stopAt ?? now);
        if (cur.voice case var v?) audio.engine.stopSoftly(v, 0.02);
      }
      // Forgotten, so a launch still opening its file (a hit just before the
      // game ended) finds it is not wanted and is not heard after the end.
      ch.next = null;
      ch.now = null;
    }
    _clipChannels.clear();
    // Held Repeat pads too: their next repeat was on the clock now stopped.
    _repeats.clear();
    if (_clipRecord case var rec?) {
      if (rec.started) {
        _finishClipRecord(rec, now, launch: false);
      } else {
        _clipRecord = null;
      }
    }
  }

  /// _sessionSilenced is whether [key]'s timeline is quiet: a channel
  /// playing from its slots is not playing the timeline, as Ableton's is
  /// not -- until its slots are stopped.
  bool _sessionSilenced(String key) =>
      _sessionOnly ||
      _offTimeline.contains(key) ||
      (_clipChannels[key]?.now != null &&
          _clipChannels[key]!.now!.from <= _sessionNow + 0.001);

  /// recordClip records what is played on [channel]'s instrument into its
  /// empty slot [row], from the next launch time until it is pressed again
  /// -- then rounded up to whole bars, and played round at once.
  void recordClip(String channel, int row) {
    if (_instrumentOf(channel) == null || session.at(channel, row) != null) {
      return;
    }
    if (_clipRecord != null) _endClipRecord();
    if (!_armed.contains(channel)) {
      _armed
        ..clear()
        ..add(channel);
    }
    var at = _launchTime();
    _stopChannelAt(channel, at);
    _clipRecord = _ClipRecord(channel, row, at);
    notifyListeners();
  }

  /// _endClipRecord ends the recording at the end of the bar it is in.
  void _endClipRecord() {
    var rec = _clipRecord;
    if (rec == null) return;
    if (!rec.started || !playing) {
      _clipRecord = null;
      notifyListeners();
      return;
    }
    var bar = math.max(0.05, _barSeconds);
    var bars = math.max(1, ((_sessionNow - rec.from) / bar - 0.02).ceil());
    rec.until = rec.from + bars * bar;
    notifyListeners();
  }

  /// _finishClipRecord makes what was recorded into the slot's clip -- one
  /// change to undo -- and, with [launch], plays it round from [until].
  void _finishClipRecord(_ClipRecord rec, double until, {bool launch = true}) {
    _clipRecord = null;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    for (var h in rec.held.entries) {
      var (start, velocity) = h.value;
      rec.notes.add(MidiNote(h.key, start,
          math.max(0.02, (until - rec.from) / spb - start), velocity));
    }
    // To the end of the bar it reached, as Stop record ends it (see
    // _endClipRecord): stopped part way into a bar, its notes stay inside.
    var bars = math
        .max(
            1, ((until - rec.from) / math.max(0.05, _barSeconds) - 0.02).ceil())
        .toDouble();
    var index = timelineChannels.indexWhere((c) => c.key == rec.channel);
    var clip = SessionClip(
      id: newElementId(),
      name: "Recording",
      color: math.max(0, index) % sectionColors.length,
      midi: true,
      notes: rec.notes..sort((a, b) => a.start.compareTo(b.start)),
      bars: bars,
    );
    apply(_document.copyWith(session: session.put(rec.channel, rec.row, clip)));
    if (launch && playing) {
      unawaited(_startClip(rec.channel, rec.row, clip, until));
    }
  }

  /// _clipNoteOn and _clipNoteOff write a key played on [e] into the slot
  /// being recorded, where it is [e]'s channel's.
  void _clipNoteOn(AudioElement e, int key, int velocity) {
    var rec = _clipRecord;
    if (rec == null ||
        !rec.started ||
        rec.channel != CanvasController._channelOf(e)) return;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    rec.held[key] = ((_sessionNow - rec.from) / spb, velocity);
  }

  void _clipNoteOff(AudioElement e, int key) {
    var rec = _clipRecord;
    if (rec == null || rec.channel != CanvasController._channelOf(e)) return;
    if (rec.held.remove(key) case (var start, var velocity)?) {
      var spb = math.max(0.001, _document.audio.secondsPerBeat);
      var end = (_sessionNow - rec.from) / spb;
      rec.notes
          .add(MidiNote(key, start, math.max(0.02, end - start), velocity));
    }
  }

  /// setSessionClip puts [clip] in slot [row] of [channel], or empties it.
  void setSessionClip(String channel, int row, SessionClip? clip) {
    if (clip == null) {
      var ch = _clipChannels[channel];
      if (ch != null && (ch.now?.row == row || ch.next?.row == row)) {
        _stopChannelAt(channel, _sessionNow);
      }
    }
    apply(_document.copyWith(session: session.put(channel, row, clip)));
  }

  /// soundsOf are the sounds on [channel]'s timeline, each once: what an
  /// audio channel's empty slot offers to hold.
  List<MediaSource> soundsOf(String channel) {
    var seen = <String>{};
    var out = <MediaSource>[];
    for (var c in timelineChannels) {
      if (c.key != channel) continue;
      for (var lane in c.lanes) {
        var e = lane.element;
        if (e is AudioElement && e.instrument != null) continue;
        for (var s in lane.clip.playlist) {
          var id =
              e is VideoElement && s.soundId.isNotEmpty ? s.soundId : s.assetId;
          if (seen.add("$id:${s.start}:${s.end}")) {
            out.add(id == s.assetId ? s : s.copyWith(assetId: id));
          }
        }
      }
    }
    return out;
  }

  /// clipFromSound fills slot [row] of [channel] with [sound]: as long in
  /// whole bars as it nearly is, a loop made to the tempo -- and otherwise
  /// as long as it is (see barsFor), so a line spoken or a sound effect,
  /// played once, is not cut short.
  void clipFromSound(String channel, int row, MediaSource sound) {
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: sound.name,
          color: math.max(0, index) % sectionColors.length,
          sound: sound,
          bars: barsFor(sound.span, math.max(0.05, _barSeconds)),
        ));
  }

  /// newMidiClip fills slot [row] of a MIDI channel with an empty clip of
  /// [bars] -- or with the channel's part, with [fromPart].
  void newMidiClip(String channel, int row,
      {double bars = 1, bool fromPart = false}) {
    var e = _instrumentOf(channel);
    if (e == null) return;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var notes = fromPart
        ? [
            for (var n in e.instrument!.notes)
              n.copyWith(start: n.start / spb, length: n.length / spb),
          ]
        : <MidiNote>[];
    if (fromPart && notes.isNotEmpty) {
      var end = notes.map((n) => n.end).reduce(math.max);
      bars = math.max(1, (end / _document.audio.beatsPerBar).ceil()).toDouble();
    }
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: fromPart ? "${e.name} part" : "MIDI clip",
          color: math.max(0, index) % sectionColors.length,
          midi: true,
          notes: notes,
          // Its controllers' curves with it, in beats as its notes are.
          controls: fromPart
              ? {
                  for (var c in e.instrument!.controls.entries)
                    c.key: [for (var (t, v) in c.value) (t / spb, v)],
                }
              : const {},
          bars: bars,
        ));
  }

  /// makeSessionClip puts a clip in the empty slot [row] of [channel], as a
  /// double-click there does (Ken, 2026-11-08, as the motion slots): on a
  /// MIDI channel an empty one to draw notes into, on an audio channel one
  /// of the channel's sound -- its first; a slot's menu has the rest. It is
  /// picked. False where there is no sound to make one of.
  bool makeSessionClip(String channel, int row) {
    if (session.at(channel, row) != null) return false;
    if (instrumentChannel(channel)) {
      newMidiClip(channel, row);
    } else {
      var sounds = soundsOf(channel);
      if (sounds.isEmpty) return false;
      clipFromSound(channel, row, sounds.first);
    }
    selectSlot(channel, row);
    return true;
  }

  /// emptySlotOf is the first empty slot of [channel], or null when every
  /// one is full.
  int? emptySlotOf(String channel) {
    for (var row = 0; row < session.rows; row++) {
      if (session.at(channel, row) == null) return row;
    }
    return null;
  }

  /// partToSlot copies the piano roll's part into the first empty slot of
  /// its channel and opens it there, in the clip editor: launched from its
  /// slot, with the launch settings a part, playing with the timeline, has
  /// none of.
  void partToSlot() {
    var t = pianoRoll;
    if (t == null || t.row != null) return;
    var row = emptySlotOf(t.channel);
    if (row == null) return;
    newMidiClip(t.channel, row, fromPart: true);
    openClipEditor(t.channel, row);
  }

  /// addClipScene, removeClipScene and renameClipScene change the session
  /// grid's rows -- not the canvas's own scenes. Added at the end, a cue
  /// goes after the slots shown, named by its number so it is one of them
  /// (see slotsShown, which leaves out empty cues past the last used).
  void addClipScene({int? after, bool master = false}) {
    if (!cuesApart) {
      var at = after == null ? slotsShown : after + 1;
      var grid = session.withScene(after: at - 1);
      if (after == null) grid = grid.renameScene(at, "${at + 1}");
      // The elements' slots move down with the cues under it.
      apply(everyMotion(
          _document.copyWith(session: grid), (m) => m.withCueAt(at)));
      return;
    }
    var at = after == null ? slotsShown : after + 1;
    var keys = {for (var c in _cueChannels(master)) c.key};
    var names = [...cueNames(master: master)]
      ..insert(at.clamp(0, cueNames(master: master).length), "");
    if (after == null) names[at] = "${at + 1}";
    apply(_cuesMoved(names, master, keys,
        (list) => list.length <= at ? list : ([...list]..insert(at, null)),
        (m) => m.withCueAt(at)));
  }

  void removeClipScene(int row, {bool master = false}) {
    var keys = {for (var c in _cueChannels(master)) c.key};
    for (var key in [..._clipChannels.keys]) {
      if (cuesApart && !keys.contains(key)) continue;
      var ch = _clipChannels[key]!;
      if (ch.now?.row == row || ch.next?.row == row) {
        _stopChannelAt(key, _sessionNow);
      }
    }
    if (cueNames(master: master).length <= 1) return;
    for (var e in _cueElements(master)) {
      if (e.base.motion.slot(row) case var clip?) {
        motionPlayer.stop(e.id, layer: clip.layer, at: _sessionNow);
      }
    }
    if (!cuesApart) {
      apply(everyMotion(_document.copyWith(session: session.withoutScene(row)),
          (m) => m.withoutCue(row)));
      return;
    }
    var names = [...cueNames(master: master)]..removeAt(row);
    apply(_cuesMoved(names, master, keys,
        (list) => list.length <= row ? list : ([...list]..removeAt(row)),
        (m) => m.withoutCue(row)));
  }

  void renameClipScene(int row, String name, {bool master = false}) {
    if (!cuesApart || master) {
      apply(_document.copyWith(session: session.renameScene(row, name)));
      return;
    }
    var names = [...cueNames()];
    if (row < 0 || row >= names.length) return;
    names[row] = name.trim();
    apply(_document.withScene(
        _document.at, _document.scene.copyWith(cues: names)));
  }

  /// _cuesMoved is the document with the cues of the canvas shown -- or,
  /// [master], the master's -- now [names]: the slots of channels [keys]
  /// moved by [slots], and of its elements by [motion]; the other canvas's
  /// left where they are, and as many rows as anything has.
  CanvasDocument _cuesMoved(
      List<String> names,
      bool master,
      Set<String> keys,
      List<SessionClip?> Function(List<SessionClip?> list) slots,
      ElementMotion Function(ElementMotion m) motion) {
    var moved = {
      for (var e in session.slots.entries)
        e.key: keys.contains(e.key) ? slots(e.value) : e.value,
    }..removeWhere((_, l) => l.every((c) => c == null));
    var doc = _document;
    var rows = names.length;
    for (var l in moved.values) {
      rows = math.max(rows, l.length);
    }
    List<String> padded(List<String> l, int n) =>
        [for (var i = 0; i < n; i++) i < l.length ? l[i] : ""];
    List<CanvasElement> stepped(List<CanvasElement> list) => [
          for (var e in list)
            if (e.base.motion.isEmpty)
              e
            else
              e.withBase(motion: motion(e.base.motion)),
        ];
    if (master) {
      rows = math.max(rows, cueNames().length);
      doc = doc.copyWith(
          session: SessionGrid(scenes: padded(names, rows), slots: moved));
      if (doc.master case var m?) {
        doc = doc.copyWith(master: m.copyWith(elements: stepped(m.elements)));
      }
    } else {
      rows = math.max(rows, session.scenes.length);
      doc = doc.copyWith(
          session:
              SessionGrid(scenes: padded(session.scenes, rows), slots: moved),
          elements: stepped(doc.elements));
      doc = doc.withScene(doc.at, doc.scene.copyWith(cues: names));
    }
    return doc;
  }

  /// instrumentOf is [channel]'s instrument, for a MIDI channel, or null.
  AudioElement? instrumentOf(String channel) => _instrumentOf(channel);

  /// setChannelPart changes the part of MIDI channel [channel]'s instrument
  /// -- its input, its Monitor, its MIDI effects -- by [change].
  void setChannelPart(
      String channel, InstrumentPart Function(InstrumentPart part) change,
      {bool transient = false}) {
    var e = _instrumentOf(channel);
    if (e == null) return;
    // Held keys go on sounding: each is let go as it was sounded (see
    // _soundOff), so a knob turned while a chord is held does not cut it.
    setInstrument(e, change(e.instrument!), transient: transient);
  }

  /// _withMaster are the scene's elements and the master's drawn over them.
  List<CanvasElement> get _withMaster => [
        ..._document.elements,
        if (!_document.editingMaster) ...?_document.masterScene?.elements,
      ];

  /// _instrumentOf is [channel]'s instrument, for a MIDI channel: in the
  /// scene, or on the master -- where a game keeps the channels every scene
  /// shares, its music and its effects. The master's even on a scene that
  /// does not draw it (CanvasScene.masterOff, a title with no HUD): a
  /// slot's channel is the document's. Ember Vale's music, all of it on
  /// the master, was never heard: its MIDI slots found nothing to play them.
  AudioElement? _instrumentOf(String channel) {
    for (var e in [
      ..._document.elements,
      if (!_document.editingMaster && _document.masterOn)
        ...?_document.master?.elements,
    ]) {
      if (e is AudioElement &&
          e.instrument != null &&
          CanvasController._channelOf(e) == channel) {
        return e;
      }
    }
    return null;
  }

  /// _clipSound is a MIDI clip's notes played into a file by [channel]'s
  /// instrument -- once for each way it sounds, and kept on the clip, so it
  /// is played again only when it changes. Null for a clip with nothing in
  /// it, or nothing to play it.
  Future<MediaSource?> _clipSound(String channel, SessionClip clip) async {
    var e = _instrumentOf(channel);
    if (e == null || clip.notes.isEmpty) return null;
    var spb = _document.audio.secondsPerBeat;
    var part = macroedPart(channel, e.instrument!);
    var signature = clip.signature(part, spb);
    if (clip.rendered == signature && clip.sound != null) return clip.sound;
    try {
      var bankHere = part.sound == InstrumentSound.bank &&
          await CanvasController.bankReady();
      var wav = await CanvasController.partRenderer(
          clip.partOf(part, spb).played(spb),
          bankPath: bankHere ? await soundBankPath() : null);
      var id = await CanvasController.partStore(wav);
      if (id == null || _disposed) return null;
      var sound = MediaSource(assetId: id, name: "${clip.name} (played)");
      // Written onto the clip as it is now, if it is still there: not a
      // change of its own to undo -- the file follows the notes.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        if (now.signature(part, spb) == signature) {
          apply(
              _document.copyWith(
                  session: session.put(ch, row,
                      now.copyWith(sound: sound, rendered: signature))),
              transient: true);
        }
      }
      return sound;
    } catch (exception) {
      debugPrint("Unable to play the clip: $exception");
      return null;
    }
  }

  /// placeSessionClip puts slot [row] of [channel] onto its lane, or
  /// [onto]'s (another channel of its kind), at [frame], as it would be had
  /// it been launched there with Record on: once through, its length long.
  void placeSessionClip(String channel, int row, int frame, {String? onto}) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    var from = math.max(0, frame) / math.max(1, _document.frameRate);
    var length = math.max(0.05, clip.bars * _document.audio.secondsPerBar);
    var kept = [..._clipLog];
    _clipLog
      ..clear()
      ..add(_ClipPlayed(onto ?? channel, clip, from, from + length));
    var next = _writeClipLog(_document);
    _clipLog
      ..clear()
      ..addAll(kept);
    apply(next);
  }

  /// _writeClipLog writes what the slots played while Record was on onto
  /// the timeline: an audio clip as its sound, round as many times as it
  /// went, on its channel; a MIDI clip's notes into its channel's part.
  /// Part of the take: one change with it.
  CanvasDocument _writeClipLog(CanvasDocument doc) {
    if (_clipLog.isEmpty) return doc;
    var rate = math.max(1, doc.frameRate);
    var spb = math.max(0.001, doc.audio.secondsPerBeat);
    var next = doc;
    for (var played in _clipLog) {
      var clip = played.clip;
      var pieces = clipPieces(
          clip, played.to - played.from, spb, doc.audio.secondsPerBar);
      if (clip.midi) {
        var e = next.elements
            .whereType<AudioElement>()
            .where((a) =>
                a.instrument != null &&
                CanvasController._channelOf(a) == played.channel)
            .firstOrNull;
        if (e == null) continue;
        var base = e.clip.at / rate;
        var added = <MidiNote>[];
        for (var (from, to, heard) in pieces) {
          for (var n in clip.notes) {
            var at = n.start * spb;
            if (at < from - 1e-6 || at >= to - 1e-6) continue;
            var start = played.from + heard + at - from;
            var len = math.min(n.length * spb, played.to - start);
            if (start - base < 0 || len <= 0) continue;
            added.add(MidiNote(
                n.key, start - base, len, n.velocity, n.muted, n.chance));
          }
        }
        var part = e.instrument!;
        next = next.withElement(e.copyWith(
            instrument: part.copyWith(
                notes: [...part.notes, ...added]
                  ..sort((a, b) => a.start.compareTo(b.start)))));
      } else if ((clip.needsRender
              ? (clip.warped ?? _clipById(clip.id)?.warped)
              : clip.sound)
          case var sound?) {
        var playlist = <MediaSource>[];
        var full = sound.span > 0 ? sound.span : double.infinity;
        for (var (from, to, _) in pieces) {
          if (from >= full || to - from < 0.01) continue;
          playlist.add(sound.copyWith(
              start: sound.start + from,
              end: sound.start + math.min(to, full)));
        }
        if (playlist.isEmpty) continue;
        next = next.addElement(AudioElement(
          ElementBase(
              id: newElementId(),
              name: clip.name.isEmpty ? "Clip" : clip.name,
              visible: false),
          clip: MediaClip(
              playlist: playlist,
              timed: true,
              at: (played.from * rate).round(),
              channel: played.channel),
          controls: const [],
        ));
      }
    }
    _clipLog.clear();
    return next;
  }
}
