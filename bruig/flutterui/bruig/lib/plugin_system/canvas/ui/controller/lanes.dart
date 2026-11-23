part of '../canvas_controller.dart';

// Part of CanvasController: the timeline's lanes -- the effects strip they
// open, cues on the ruler, their heights, folds and header, whether they
// scroll to follow the playhead, and a locator put on the ruler -- and what
// is drawn in them: waveforms and ducking. Its state is _LaneState, at the
// end of this file.

extension CanvasLanes on CanvasController {
  /// effectsOf is the strip whose chain of effects the effects panel shows,
  /// by key or mixerMasterKey, or null for none chosen yet.
  String? get effectsOf => _effectsOf;

  set effectsOf(String? key) {
    if (key == _effectsOf) return;
    _effectsOf = key;
    notifyListeners();
  }

  /// restoreShown puts back whether the cues showed, from the preferences,
  /// without notifying: it runs while the page is being built.
  void restoreShown({required bool cues}) {
    _laneState.cuesShown = cues;
  }

  /// cuesShown is whether the cues are marked on the timeline's ruler.
  bool get cuesShown => _laneState.cuesShown;

  set cuesShown(bool shown) {
    if (shown == _laneState.cuesShown) return;
    _laneState.cuesShown = shown;
    notifyListeners();
  }

  void foldDevice(String id, bool folded) {
    if (folded ? !foldedDevices.add(id) : !foldedDevices.remove(id)) return;
    notifyListeners();
  }

  /// laneSize is the height every channel is, unless one has been dragged:
  /// see laneSizeHeights.
  int get laneSize => _laneSize;

  /// nextLaneSize steps every channel to the next of laneSizeHeights, round
  /// to the first, putting back any dragged one: the button means them all.
  void nextLaneSize() {
    // Three: small, medium and large.
    _laneSize = (_laneSize + 1) % 3;
    laneHeights.clear();
    notifyListeners();
  }

  /// headerWidth is the column of channel strips down the left of the
  /// timeline, dragged anywhere from an icon's width to the whole strip.
  double get headerWidth => _headerWidth;

  set headerWidth(double value) {
    var next = value.clamp(timelineHeaderMin, timelineHeaderMax).toDouble();
    if (next == _headerWidth) return;
    _headerWidth = next;
    notifyListeners();
  }

  /// rowFolded is whether timeline row [key] (an element's id, a channel's
  /// key, "scenes") is folded to one line: as the channel height says (S
  /// folds every row) unless its own arrow turned it. The height button, or
  /// another canvas (whose rows may share keys), puts them all back.
  bool rowFolded(String key) {
    _foldsNow();
    return (laneSize == 0) != _laneState.flippedRows.contains(key);
  }

  /// toggleRowFold is row [key]'s fold arrow.
  void toggleRowFold(String key) {
    _foldsNow();
    if (!_laneState.flippedRows.remove(key)) {
      _laneState.flippedRows.add(key);
    }
    notifyListeners();
  }

  void _foldsNow() {
    var at = (folder, name, laneSize);
    if (_laneState.flippedRowsAt == at) return;
    _laneState.flippedRowsAt = at;
    _laneState.flippedRows.clear();
  }

  /// followsAtFirst is whether a session starts following the playhead.
  static const followsAtFirst = true;

  /// followPlayhead is whether the timeline scrolls to follow the playhead.
  bool get followPlayhead => _laneState.followPlayhead;

  set followPlayhead(bool on) {
    if (_laneState.followPlayhead == on) return;
    _laneState.followPlayhead = on;
    notifyListeners();
  }

  /// addLocator puts a named locator under the playhead, unless a marker is
  /// there: see markerAdded.
  void addLocator() {
    var doc = _document;
    var next = markerAdded(doc.actions, _frame, TimelineActionKind.locator,
        id: motionId("m"));
    if (next != null) apply(doc.copyWith(actions: next));
  }

  /// waveformOf is [assetId]'s peaks (0 to 1) across the file, or null until
  /// read: read off the main thread on first asking, the timeline told then.
  Float32List? waveformOf(String assetId) {
    if (CanvasController._waveforms.containsKey(assetId)) {
      return CanvasController._waveforms[assetId];
    }
    if (CanvasController._readingWaveform.add(assetId)) _readWaveform(assetId);
    return null;
  }

  Future<void> _readWaveform(String assetId) async {
    Float32List? peaks;
    try {
      var path = await CanvasMedia.existingPath(MediaKind.audio, assetId);
      if (path != null) peaks = await audio.engine.peaks(path, waveformPoints);
    } catch (exception) {
      debugPrint("Unable to read the shape of $assetId: $exception");
    }
    CanvasController._waveforms[assetId] = peaks;
    CanvasController._readingWaveform.remove(assetId);
    if (!_disposedForWaveform) notifyListeners();
  }

  /// setTimedClip writes a clip moved or trimmed on the Channels strip back
  /// to whatever holds it: an element on this canvas, or the backdrop.
  void setTimedClip(CanvasElement e, MediaClip clip, {bool transient = false}) {
    var next = switch (e) {
      VideoElement v => v.copyWith(clip: clip),
      AudioElement a => a.copyWith(clip: clip),
      _ => null,
    };
    if (next == null) return;
    var anywhere = _replacedAnywhere(_document, next);
    if (anywhere != null) {
      apply(anywhere, transient: transient);
      return;
    }
    var bg = _document.drawnBackground;
    if (bg.video?.id == e.id && next is VideoElement) {
      setBackground(bg.copyWith(video: next), transient: transient);
    } else if (bg.sound?.id == e.id && next is AudioElement) {
      setBackground(bg.copyWith(sound: next), transient: transient);
    }
  }

  /// _replacedAnywhere is [doc] with [next] in place of the element of its
  /// id: on the canvas edited, the master seen from a scene, or another
  /// scene; null if none. A scene's clip is held within its frames; the
  /// master's goes where put.
  CanvasDocument? _replacedAnywhere(CanvasDocument doc, CanvasElement next) {
    List<CanvasElement> swapped(List<CanvasElement> list) =>
        [for (var e in list) e.id == next.id ? next : e];
    CanvasElement held(CanvasElement e, int frames) => switch (e) {
          VideoElement v when v.clip.timed => v.copyWith(
              clip: v.clip.copyWith(
                  at: v.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          AudioElement a when a.clip.timed => a.copyWith(
              clip: a.clip.copyWith(
                  at: a.clip.at.clamp(0, math.max(0, frames - 1)).toInt())),
          _ => e,
        };
    var onMaster = doc.editingMaster;
    if (doc.elements.any((x) => x.id == next.id)) {
      return doc.withElement(onMaster ? next : held(next, doc.frames));
    }
    var master = doc.master;
    if (!onMaster &&
        master != null &&
        master.elements.any((x) => x.id == next.id)) {
      return doc.copyWith(
          master: master.copyWith(elements: swapped(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!onMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == next.id)) continue;
      next = held(next, scene.frames);
      return doc.withScene(
          i, scene.copyWith(elements: swapped(scene.elements)));
    }
    return null;
  }

  /// _addedBeside is [doc] with [added] put on whichever canvas [besideId]
  /// is on, just after it -- the second half of a clip cut in two.
  CanvasDocument? _addedBeside(
      CanvasDocument doc, String besideId, CanvasElement added) {
    List<CanvasElement> after(List<CanvasElement> list) => [
          for (var e in list) ...[e, if (e.id == besideId) added],
        ];
    if (doc.elements.any((x) => x.id == besideId)) {
      return doc.addElement(added);
    }
    var master = doc.master;
    if (!doc.editingMaster &&
        master != null &&
        master.elements.any((x) => x.id == besideId)) {
      return doc.copyWith(
          master: master.copyWith(elements: after(master.elements)));
    }
    for (var (i, scene) in doc.allScenes.indexed) {
      if (!doc.editingMaster && i == doc.at) continue;
      if (!scene.elements.any((x) => x.id == besideId)) continue;
      return doc.withScene(i, scene.copyWith(elements: after(scene.elements)));
    }
    return null;
  }

  int? _timedFrame(String id) {
    for (var (e, at) in _timedOnScreen) {
      if (e.id == id) return at;
    }
    return null;
  }

  ClipMoment? _momentOf(CanvasElement e, int frame) {
    var clip = switch (e) {
      VideoElement v => v.clip,
      AudioElement a => a.clip,
      _ => null,
    };
    if (clip == null) return null;
    var rate = _document.frameRate <= 0 ? 1 : _document.frameRate;
    return clip.momentAt((frame - clip.at) / rate);
  }

  /// _syncTimeline puts every timed piece of media where the playhead is:
  /// playing if it is playing, held on the frame under it if not, silent and
  /// out of sight outside its span.
  void _syncTimeline() {
    _applyMix();
    _syncMetronome();
    // Playing only the slots, the timeline is not playing.
    var going = timelinePlaying;
    var ducks = _duckEnvelopes();
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      // Practising, the timeline's sounds are quiet: the piece is played
      // live -- the hand not being practised -- at the practice tempo.
      // So too played slower or faster than real time (see playSheet).
      var moment = at == null || _practice != null || _slowSheet != null
          ? null
          : _momentOf(e, at);
      // A channel playing from its slots is not playing the timeline.
      if (moment != null && (_clipChannels.isNotEmpty || offTimeline)) {
        var clip = switch (e) {
          AudioElement a => a.clip,
          VideoElement v => v.clip,
          _ => null,
        };
        var key = clip == null || clip.channel.isEmpty ? e.id : clip.channel;
        if (_sessionSilenced(key)) moment = null;
      }
      // Turned down while a channel that ducks the others is speaking -- see
      // Ducking.
      if (moment != null && ducks.isNotEmpty) {
        var clip = switch (e) {
          AudioElement a => a.clip,
          VideoElement v => v.clip,
          _ => null,
        };
        var key = clip == null || clip.channel.isEmpty ? e.id : clip.channel;
        if (ducks[key] case var env?) {
          var run = (_runStartOf(e.id) + at!) / rate;
          moment = ClipMoment(
              moment.index, moment.time, moment.gain * envelopeAt(env, run));
        }
      }
      switch (e) {
        case VideoElement v:
          video.cue(v, moment, playing: going);
        case AudioElement a:
          audio.cue(a, moment, playing: going);
      }
    }
  }

  /// _duckEnvelopes is how far each channel is ducked over the run, redone
  /// only when the document changes or a recording's shape is read.
  Map<String, List<GainPoint>> _duckEnvelopes() {
    if (identical(_laneState.duckFor, _document) &&
        _laneState.duckWaves == CanvasController._waveforms.length) {
      return _laneState.ducks;
    }
    _laneState.duckFor = _document;
    _laneState.duckWaves = CanvasController._waveforms.length;
    _laneState.ducks = duckEnvelopes(_document, waveformOf);
    return _laneState.ducks;
  }

  /// duckEnvelopeOf is how far channel [key] is ducked over the run, for the
  /// timeline to draw, or null where nothing ducks it.
  List<GainPoint>? duckEnvelopeOf(String key) => _duckEnvelopes()[key];

  /// duckersOf is the channels that duck channel [key] -- each with its
  /// Ducker on -- whether or not [key] is left out of it (see Ducking).
  List<TimelineChannel> duckersOf(String key) => [
        for (var c in timelineChannels)
          if (c.key != key && c.mix.duck.on) c,
      ];

  /// setDuckedBy puts channel [key] in or out of every Ducker that would
  /// turn it down: the switch of its Ducker card.
  void setDuckedBy(String key, bool ducked) {
    beginInteraction();
    for (var voice in duckersOf(key)) {
      // Read afresh: each write is a new document.
      var now = timelineChannels.where((c) => c.key == voice.key).firstOrNull;
      if (now == null) continue;
      var duck = now.mix.duck;
      var except = [
        for (var k in duck.except)
          if (k != key) k,
        if (!ducked) key,
      ];
      setChannelMix(now, now.mix.copyWith(duck: duck.copyWith(except: except)),
          transient: true, anywhere: true);
    }
    endInteraction();
  }

  /// _joinedCuts is the timeline's sounds as played: a sound cut in two, its
  /// halves still end to end on one channel, plays as one sound -- the
  /// second cued with nothing, the first running on through the join --
  /// since the frame-stepped playhead would make a skip at the cut. Only
  /// where nothing is lost: the same file, the second starting in it where
  /// the first stops and on the timeline where the first ends, no fade at
  /// the join, neither looping. The level is the half the playhead is in,
  /// so each half's volume line holds.
  List<(CanvasElement, int?)> _joinedCuts(List<(CanvasElement, int)> items) {
    var rate = math.max(1, _document.frameRate);
    bool joins(AudioElement a, AudioElement b) {
      var x = a.clip, y = b.clip;
      if (x.channel.isEmpty || x.channel != y.channel) return false;
      if (x.playlist.length != 1 || y.playlist.length != 1) return false;
      if (x.loop != MediaLoop.none || y.loop != MediaLoop.none) return false;
      if (x.fadeOut > 0 || y.fadeIn > 0 || x.muted != y.muted) return false;
      var s = x.playlist.single, t = y.playlist.single;
      if (s.assetId != t.assetId || s.end <= 0) return false;
      if ((t.start - s.end).abs() > 0.002) return false;
      return (y.at - (x.at + s.span * rate)).abs() <= 1;
    }

    var out = <(CanvasElement, int?)>[];
    var sounds = <int, List<AudioElement>>{};
    for (var (e, at) in items) {
      if (e is AudioElement && e.clip.timed) {
        (sounds[at] ??= []).add(e);
      } else {
        out.add((e, at));
      }
    }
    for (var MapEntry(key: at, value: list) in sounds.entries) {
      list.sort((a, b) => a.clip.at.compareTo(b.clip.at));
      var used = <String>{};
      for (var (i, head) in list.indexed) {
        if (!used.add(head.id)) continue;
        var chain = [head];
        for (var next in list.skip(i + 1)) {
          if (used.contains(next.id) || !joins(chain.last, next)) continue;
          chain.add(next);
          used.add(next.id);
        }
        if (chain.length == 1) {
          out.add((head, at));
          continue;
        }
        var here = chain.lastWhere((c) => c.clip.at <= at, orElse: () => head);
        var whole = head.clip.copyWith(
          playlist: [
            head.clip.playlist.single
                .copyWith(end: chain.last.clip.playlist.single.end),
          ],
          fadeOut: chain.last.clip.fadeOut,
          volume: here.clip.volume,
        );
        out.add((head.copyWith(clip: whole), at));
        for (var rest in chain.skip(1)) {
          out.add((rest, null));
        }
      }
    }
    return out;
  }
}

/// _LaneState is what CanvasLanes keeps between calls, here beside the code that
/// uses it. The controller holds one, as _laneState; most fields are read and
/// set through CanvasLanes's getters and setters above, which say what each is.
class _LaneState {
  bool cuesShown = true;

  /// flippedRows are the timeline rows whose own arrow turned their fold
  /// from what the channel height says, and flippedRowsAt what they were
  /// turned under (folder, name and channel height): any other, and they
  /// are let go. See rowFolded.
  final Set<String> flippedRows = {};

  (String?, String?, int)? flippedRowsAt;

  /// followPlayhead is whether the timeline scrolls with the playhead.
  bool followPlayhead = CanvasLanes.followsAtFirst;

  CanvasDocument? duckFor;

  int duckWaves = -1;

  Map<String, List<GainPoint>> ducks = const {};
}
