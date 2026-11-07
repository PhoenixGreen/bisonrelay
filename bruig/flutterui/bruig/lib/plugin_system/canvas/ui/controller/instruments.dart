part of '../canvas_controller.dart';

// Sound on the timeline, and the instruments played into it.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasInstruments on CanvasController {
  /// audio is what is playing. Made the first time anything asks, so a
  /// canvas with no sound on it never opens a sound device.
  AudioRuntime get audio => _audio ??= AudioRuntime(
      engine: _audioEngine ??
          (useMixEngine ? sharedMixEngine : SoLoudAudioEngine()),
      locate: (id) => CanvasMedia.existingPath(MediaKind.audio, id))
    ..addListener(notifyListeners);

  /// audioRevision changes whenever any sound's or video's state does, so
  /// the stage's painter knows to draw the speakers and the frames again.
  int get audioRevision => (_audio?.revision ?? 0) + (_video?.revision ?? 0);

  /// video plays the canvas's videos, through the same sound runtime as
  /// everything else. Made the first time anything asks, like [audio].
  VideoRuntime get video => _video ??= VideoRuntime(
      frames: _frameSource ?? FfmpegFrames(ffmpegPath),
      audio: audio,
      locate: (id) => CanvasMedia.existingPath(MediaKind.video, id))
    // A video's frames are not changes to the canvas: see _notifyPlayhead.
    ..addListener(_notifyView);

  /// videoShow is how [e] should be drawn now: its frame and its play bar.
  VideoShow videoShow(VideoElement e) {
    // On the timeline, outside its span, it is not there at all.
    if (e.clip.timed && !e.isLink) {
      var at = _timedFrame(e.id);
      if (at == null || _momentOf(e, at) == null) {
        return const VideoShow(hidden: true);
      }
    }
    var v = _video;
    if (v == null) return VideoShow.idle(e);
    var view = v.view(e);
    return VideoShow(
      playing: view.playing,
      muted: view.muted,
      volume: view.volume,
      position: view.position,
      start: view.start,
      end: view.end,
      frame: view.frame,
      poster: view.poster,
      opacity: view.opacity,
    );
  }

  /// pressVideo is a press on [part] of [e], [along] of the way along it
  /// for the two bars. Returns the address a link video asked to open, for
  /// the caller to ask about -- leaving the app is not decided down here.
  String? pressVideo(VideoElement e, VideoPart part, {double along = 0}) {
    var current = _mediaById(e.id);
    if (current is VideoElement) e = current;
    if (e.isLink) return linkAt(e.link, e.linkStart);
    // On the timeline it is the playhead's, and nothing on it is pressed.
    if (e.clip.timed) return null;
    switch (part) {
      case VideoPart.picture:
      case VideoPart.bigPlay:
      case VideoPart.playPause:
        _heard();
        unawaited(video.toggle(e));
      case VideoPart.track:
        unawaited(video.seekTo(e, along));
      case VideoPart.mute:
        video.toggleMute(e);
      case VideoPart.volume:
        video.setVolume(e, along);
        if (along > 0 && video.view(e).muted) video.setMuted(e, false);
    }
    return null;
  }

  /// audioUnavailable is whether the sound device could not be opened, for
  /// the settings to say so.
  bool get audioUnavailable => _audio?.unavailable ?? false;

  /// stopAudio stops every sound the canvas is playing.
  void stopAudio() {
    _video?.stopAll();
    _audio?.stopAll();
  }

  /// leavePage is the Canvas page left. The session outlives the page, but
  /// nothing of it goes on with no page to see or stop it: not the playhead
  /// (whose every frame would cue the sounds again), a game and its keys, a
  /// stop waiting for one, the slots, a voice being heard, the counters'
  /// clock, an arpeggio or a held note -- nor the pictures the renderer kept.
  void leavePage() {
    if (gaming) gaming = false;
    _endWait();
    if (playing) pause();
    motionPlayer.clear();
    _triggeredOff.clear();
    stopHearing();
    _counterTimer?.cancel();
    _counterTimer = null;
    for (var MapEntry(key: id, value: live) in _arps.entries) {
      live.timer?.cancel();
      if ((live.sounding, _document.elementById(id))
          case (var k?, AudioElement e)) {
        audio.noteOff(CanvasController._channelOf(e), k);
      }
    }
    _arps.clear();
    for (var MapEntry(key: id, value: held) in _sounded.entries) {
      if (_document.elementById(id) case AudioElement e) {
        var channel = CanvasController._channelOf(e);
        for (var k in held.values.expand((keys) => keys)) {
          audio.noteOff(channel, k);
        }
      }
    }
    _sounded.clear();
    _soundCount.clear();
    _sustained.clear();
    stopAudio();
    clearRenderCaches();
    images.release();
  }

  /// audioState is how [e]'s sound is doing, for the icon to show.
  AudioState audioState(AudioElement e) {
    if (e.instrument case var part?) {
      // An instrument's keys: the notes under the playhead, and any held.
      var seconds = (_frame - e.clip.at) / math.max(1, _document.frameRate);
      var practised = _practised;
      return AudioState(
          playing: playing,
          keys: {...part.sounding(seconds), ...?_held[e.id]},
          recording: _recording && _recordsInto(e),
          next: practised != null && practised.$2.id == e.id
              ? {for (var i in _waiting) part.notes[i].key}
              : const {});
    }
    var a = _audio;
    if (a == null) return AudioState.idle(e);
    var v = a.view(e);
    return AudioState(playing: v.playing, muted: v.muted, volume: v.volume);
  }

  /// heldKeys is [id]'s keys held down now.
  Set<int> heldKeys(String id) => Set.unmodifiable(_held[id] ?? const {});

  /// noteOn presses [key] on instrument [e]: heard at once, through its
  /// channel, and written down while recording.
  void noteOn(AudioElement e, int key, {int velocity = 100}) {
    var part = e.instrument;
    if (part == null) return;
    if (!(_held.putIfAbsent(e.id, () => {})).add(key)) return;
    _heard();
    _soundOn(e, part, key, velocity);
    if (_practice != null) _practiceHeard(e, key);
    // Step input: written at the piano roll's cursor.
    stepNoteOn(CanvasController._channelOf(e), key, velocity);
    // Into the slot being recorded, where it is this channel's; otherwise
    // into the part, with Record.
    if (_clipRecord?.channel == CanvasController._channelOf(e)) {
      _clipNoteOn(e, key, velocity);
    } else if (_recording && playing && _recordsInto(e)) {
      (_take[e.id] ??= {})[key] = (_nowInPart(e), velocity);
    }
    _keysChanged();
  }

  /// _keysChanged tells of a key pressed or let go: only the stage, which
  /// lights it, while nothing else shows it -- the whole editor while it
  /// is being recorded, practised or stepped in.
  void _keysChanged() {
    keysHeld.value++;
    if (_recording || _clipRecord != null || _practice != null || _rollStep) {
      notifyListeners();
    }
  }

  /// armed is which MIDI channels are armed, by channel key: what a MIDI
  /// keyboard plays, and what a recording writes into. The session's, as
  /// solo is.
  Set<String> get armed => Set.unmodifiable(_armed);

  /// toggleArm arms or disarms a MIDI channel. One at a time, as a keyboard
  /// plays one instrument: arming another disarms the last.
  void toggleArm(String key) {
    if (!_armed.remove(key)) {
      _armed
        ..clear()
        ..add(key);
    }
    notifyListeners();
  }

  /// midiNote is a key on a MIDI keyboard, pressed or -- at a velocity of
  /// nought -- let go: played on every MIDI channel that hears it -- see
  /// midiHearers -- as a key pressed on the canvas is. [from] is the
  /// keyboard's name; null asks for MidiInput's own.
  void midiNote(int key, int velocity, {String? from}) {
    if (velocity <= 0) {
      // Let go wherever it was pressed, whatever has changed since.
      for (var e in [..._document.elements]) {
        if (e is AudioElement && (_held[e.id]?.contains(key) ?? false)) {
          noteOff(e, key);
        }
      }
      return;
    }
    for (var e in midiHearers(from ?? MidiInput.shared.device?.name)) {
      noteOn(e, key, velocity: velocity);
    }
  }

  /// midiHearers are the instruments a note from the keyboard [from] is
  /// played on: each whose input takes it and whose Monitor says to -- In,
  /// always; Auto, while armed. With nothing armed and none on In, the one
  /// picked or the first, unless it is set Off: a keyboard plugged in plays
  /// something without anything being set up first.
  List<AudioElement> midiHearers(String? from) {
    bool takes(InstrumentPart p) =>
        p.input != noInput &&
        (p.input.isEmpty || from == null || p.input == from);
    var out = <AudioElement>[];
    for (var e in _document.elements) {
      if (e is! AudioElement) continue;
      var p = e.instrument;
      if (p == null || !takes(p)) continue;
      var hears = switch (p.monitor) {
        MidiMonitor.input => true,
        MidiMonitor.auto => _armed.contains(CanvasController._channelOf(e)),
        MidiMonitor.off => false,
      };
      if (hears) out.add(e);
    }
    if (out.isEmpty && _armed.isEmpty) {
      var picked = selected;
      for (var e in [
        if (picked is AudioElement && picked.instrument != null) picked,
        ..._document.elements.whereType<AudioElement>(),
      ]) {
        var p = e.instrument;
        if (p != null && p.monitor != MidiMonitor.off && takes(p)) {
          out.add(e);
          break;
        }
      }
    }
    return out;
  }

  /// midiControl is a keyboard's controller moved -- the mod wheel, the
  /// pitch bend, an expression pedal: heard on every channel that hears
  /// its notes, and written into the part while Record is on.
  void midiControl(MidiControl control, double value, {String? from}) {
    for (var e in midiHearers(from ?? MidiInput.shared.device?.name)) {
      audio.control(CanvasController._channelOf(e), control, value);
      if (_recording && playing && _recordsInto(e)) {
        (_controlTake[e.id] ??= {})
            .putIfAbsent(control, () => [])
            .add((_nowInPart(e), value));
      }
    }
  }

  /// controlOn moves [control] on instrument [e] alone -- its editor's bend
  /// and mod wheels -- heard at once.
  void controlOn(AudioElement e, MidiControl control, double value) =>
      audio.control(CanvasController._channelOf(e), control, value);

  /// liveScale is the scale a keyboard plays in -- a Push's pads are laid
  /// out in it: the Scale effect of the channel it plays, or C major.
  (int, List<int>) get liveScale {
    for (var e in midiHearers(MidiInput.shared.device?.name)) {
      var scale = e.instrument!.effects
          .where((m) => m.on && m.kind == MidiEffectKind.scale)
          .firstOrNull;
      if (scale != null) {
        return (
          scale.choice("root"),
          scaleSteps[scale.choice("scale").clamp(0, scaleSteps.length - 1)]
        );
      }
    }
    return (0, scaleSteps[0]);
  }

  void sustain(bool down) {
    if (_sustain == down) return;
    _sustain = down;
    if (down) return;
    var let = {..._sustained};
    _sustained.clear();
    for (var entry in let.entries) {
      var e = _document.elementById(entry.key);
      if (e is! AudioElement) continue;
      for (var key in entry.value) {
        noteOff(e, key);
      }
    }
  }

  void _soundOn(AudioElement e, InstrumentPart part, int key, int velocity) {
    var channel = CanvasController._channelOf(e);
    var keys = liveKeys(part.effects, key, velocity);
    if (arpeggiatorOf(part.effects) case var arp?) {
      var live = _arps[e.id] ??= _LiveArp(Arpeggio(arp));
      live.pressed[key] = [for (var (k, _) in keys) k];
      live.velocity = velocity;
      live.timer ??= _startArp(e, live);
      return;
    }
    var counts = _soundCount.putIfAbsent(channel, () => {});
    _sounded.putIfAbsent(e.id, () => {})[key] = [for (var (k, _) in keys) k];
    for (var (k, v) in keys) {
      var n = counts[k] = (counts[k] ?? 0) + 1;
      if (n == 1) unawaited(audio.noteOn(channel, part, k, v));
    }
  }

  void _soundOff(AudioElement e, int key) {
    var channel = CanvasController._channelOf(e);
    if (_arps[e.id] case var live?) {
      live.pressed.remove(key);
      if (live.pressed.isEmpty) {
        live.timer?.cancel();
        _arps.remove(e.id);
        if (live.sounding case var k?) audio.noteOff(channel, k);
      }
      return;
    }
    var keys = _sounded[e.id]?.remove(key) ?? [key];
    var counts = _soundCount[channel] ?? {};
    for (var k in keys) {
      var n = (counts[k] ?? 1) - 1;
      if (n <= 0) {
        counts.remove(k);
        audio.noteOff(channel, k);
      } else {
        counts[k] = n;
      }
    }
  }

  /// _startArp plays [live]'s held keys one at a time, a step apart at the
  /// tempo, each for the step's gate.
  Timer _startArp(AudioElement e, _LiveArp live) {
    var part = e.instrument!;
    var arp = arpeggiatorOf(part.effects)!;
    var stepSeconds = arpStepSeconds(arp, _document.audio.secondsPerBeat);
    var step = Duration(microseconds: (stepSeconds * 1e6).round());
    var gate = Duration(
        microseconds:
            (stepSeconds * arp.value("gate").clamp(0.1, 1.0) * 1e6).round());
    var channel = CanvasController._channelOf(e);
    void play() {
      if (live.sounding case var k?) audio.noteOff(channel, k);
      live.sounding = null;
      var held = [for (var keys in live.pressed.values) ...keys];
      var key = live.player.next(held);
      if (key == null) return;
      live.sounding = key;
      unawaited(audio.noteOn(channel, part, key, live.velocity));
      Timer(gate, () {
        if (live.sounding == key) {
          audio.noteOff(channel, key);
          live.sounding = null;
        }
      });
    }

    play();
    return Timer.periodic(step, (_) => play());
  }

  /// noteOff lets [key] go.
  void noteOff(AudioElement e, int key) {
    if (_sustain && (_held[e.id]?.contains(key) ?? false)) {
      _sustained.putIfAbsent(e.id, () => {}).add(key);
      return;
    }
    if (!(_held[e.id]?.remove(key) ?? false)) return;
    stepNoteOff(key);
    _soundOff(e, key);
    _clipNoteOff(e, key);
    if (_take[e.id]?.remove(key) case (var start, var velocity)?) {
      var length = math.max(0.02, _nowInPart(e) - start);
      (_taken[e.id] ??= []).add(MidiNote(key, start, length, velocity));
    }
    _keysChanged();
  }

  /// _nowInPart is where the playhead is in [e]'s part, in seconds.
  double _nowInPart(AudioElement e) =>
      math.max(0, (_frame + betweenFrames - e.clip.at)) /
      math.max(1, _document.frameRate);

  /// recording is the control bar's Record: while it is on and the canvas
  /// plays, what is played on an instrument is written into its part.
  bool get recording => _recording;

  set recording(bool on) {
    if (_recording == on) return;
    _recording = on;
    if (on) {
      _take.clear();
      _taken.clear();
      _controlTake.clear();
      if (!playing) play();
    } else {
      _keepTake();
    }
    notifyListeners();
  }

  /// _recordsInto is whether a recording writes into [e]: its channel is
  /// armed, or none is and every instrument played is.
  bool _recordsInto(AudioElement e) =>
      _armed.isEmpty || _armed.contains(CanvasController._channelOf(e));

  /// _keepTake writes what was recorded into each part -- one change to
  /// undo -- notes still held ending where the playhead is.
  void _keepTake() {
    for (var e in _take.entries) {
      var el = _document.elementById(e.key);
      if (el is! AudioElement) continue;
      for (var k in e.value.entries) {
        var (start, velocity) = k.value;
        (_taken[e.key] ??= []).add(MidiNote(
            k.key, start, math.max(0.02, _nowInPart(el) - start), velocity));
      }
    }
    _take.clear();
    var moved = motionPlayer.takeLog(_document, _sessionNow);
    if (_taken.isEmpty &&
        _clipLog.isEmpty &&
        _controlTake.isEmpty &&
        moved.isEmpty) {
      return;
    }
    var next = _writeClipLog(_document);
    // What the elements' slots played, as clips on their rows.
    next = writeMotionTakes(next, moved, () => motionId("p"));
    // The controllers moved, into each part's curves: over the stretch
    // recorded, what was there before is replaced.
    for (var e in _controlTake.entries) {
      var el = next.elementById(e.key);
      if (el is! AudioElement || el.instrument == null) continue;
      var part = el.instrument!;
      var controls = {...part.controls};
      for (var c in e.value.entries) {
        var took = c.value;
        var from = took.first.$1, to = took.last.$1;
        controls[c.key] = [
          for (var p in controls[c.key] ?? const <ControlPoint>[])
            if (p.$1 < from || p.$1 > to) p,
          ...took,
        ]..sort((a, b) => a.$1.compareTo(b.$1));
      }
      next = next.withElement(
          el.copyWith(instrument: part.copyWith(controls: controls)));
    }
    _controlTake.clear();
    for (var e in _taken.entries) {
      var el = next.elementById(e.key);
      if (el is! AudioElement || el.instrument == null) continue;
      var part = el.instrument!;
      next = next.withElement(el.copyWith(
          instrument: part.copyWith(
              notes: [...part.notes, ...e.value]
                ..sort((a, b) => a.start.compareTo(b.start)))));
    }
    _taken.clear();
    apply(next);
  }
}
