part of '../canvas_controller.dart';

// Scenes, and the word cues across them.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasScenes on CanvasController {
  /// playAll is whether Play runs the whole document or the scene in front of
  /// the reader. A mode rather than a second button: the answer is usually
  /// the same for a whole sitting.
  bool get playAll => _playAll;

  set playAll(bool value) {
    if (_playAll == value) return;
    _playAll = value;
    // What is picked on other canvases is out of reach again with one scene.
    if (!value) _offCanvas = const {};
    pause();
    stopPreview();
    notifyListeners();
  }

  /// previewAt is the frame of the *whole run* the canvas is showing, or null
  /// when it is showing the scene being edited. How a transition is watched:
  /// the stage draws the sequence with the same function publishing uses
  /// (see paintSequenceFrame).
  int? get previewAt => _previewAt;

  /// previewTransitionAfter plays the join between a scene and the next one:
  /// a little of the scene before it, the transition, and a little of the
  /// scene after.
  void previewTransitionAfter(int index) {
    var document = _document;
    var scenes = document.allScenes;
    if (scenes.length < 2) return;

    // On the shared canvas the bar edits the default every scene starts from,
    // and there is no "this scene" to be after, so the first join stands for
    // all of them.
    if (document.editingMaster) index = 0;
    if (index < 0 || index >= scenes.length - 1) return;

    var over = document.transitionAfter(index);
    var start = document.startOfScene(index + 1);
    // A little of the scene being left, then the join, then a little of the
    // one arriving, so the eye has something to compare the transition with.
    var lead = math.max(6, (document.frameRate * 0.4).round());
    _previewFrom = document.at;
    _previewFromMaster = document.editingMaster;
    _previewAt = math.max(0, start - over.overlap - lead);
    _previewEnd =
        math.min(document.sequenceFrames - 1, start + over.frames + lead);
    _startTimer();
    notifyListeners();
  }

  /// stopPreview puts the canvas back on the scene being edited.
  void stopPreview() {
    if (_previewAt == null) return;
    _previewAt = null;
    pause();
    // Back to the canvas it was started from: playing the document walks the
    // editor through the scenes (see _tick).
    var back = _previewFrom;
    var wasMaster = _previewFromMaster;
    _previewFrom = null;
    _previewFromMaster = false;
    if (back != null && back != _document.at) {
      _document = _document.goToScene(back);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
      _audioFollowsPage(turned: true);
    }
    // And back onto the shared canvas where that is where it started.
    if (wasMaster && !_document.editingMaster) {
      _document = _document.copyWith(onMaster: true);
      _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    }
    notifyListeners();
  }

  /// scenes are the canvases this document plays, in order.
  List<CanvasScene> get scenes => _document.allScenes;

  /// setSceneFrames sets how many frames several scenes have, as one change:
  /// the scene strip's drag between two scenes, which gives one what it takes
  /// from the other. Each is held to at least one frame.
  void setSceneFrames(Map<int, int> lengths, {bool transient = false}) {
    var next = _document;
    for (var entry in lengths.entries) {
      var list = next.allScenes;
      if (entry.key < 0 || entry.key >= list.length) continue;
      var frames = entry.value.clamp(1, maxFrameCount).toInt();
      if (list[entry.key].frames == frames) continue;
      next =
          next.withScene(entry.key, list[entry.key].copyWith(frames: frames));
    }
    apply(next, transient: transient);
  }

  /// setSceneLength sets the length of the scene being edited -- the
  /// timeline's Length field.
  void setSceneLength(int frames, {bool transient = false}) =>
      apply(_document.copyWith(frames: frames), transient: transient);

  /// cues are the run's named moments, in order.
  List<TimelineCue> get cues => _document.cues;

  /// runFrame is the playhead as a frame of the whole run.
  int get runFrame => _document.editingMaster
      ? _frame
      : _document.startOfScene(_document.at) + _frame;

  /// addCue puts a cue at [frame] of the run, the playhead's by default.
  TimelineCue addCue({String name = "", int? frame}) {
    var cue = TimelineCue(
        id: newCueId(),
        name: name.isEmpty ? "Word cue ${cues.length + 1}" : name,
        frame: math.max(0, frame ?? runFrame));
    apply(_document.copyWith(cues: _sortedCues([...cues, cue])));
    return cue;
  }

  void renameCue(String id, String name) => apply(_document.copyWith(cues: [
        for (var c in cues) c.id == id ? c.copyWith(name: name) : c,
      ]));

  /// moveCue puts cue [id] at [frame] of the run, and every element tied to
  /// it moves by as much: its keyframes and its clip placements, wherever in
  /// the run it is.
  void moveCue(String id, int frame, {bool transient = false}) {
    var cue = cues.where((c) => c.id == id).firstOrNull;
    if (cue == null) return;
    frame = math.max(0, frame);
    var by = frame - cue.frame;
    if (by == 0) return;
    var next = _document.copyWith(
        cues: _sortedCues([
      for (var c in cues) c.id == id ? c.copyWith(frame: frame) : c,
    ]));
    var seconds = by / math.max(1, _document.frameRate);
    next = _everyElement(next, (e, start) {
      if (e.base.cue != id) return e;
      var track = e.base.track;
      return e.withBase(
          track: track == null || track.isEmpty ? track : _shifted(track, by),
          motion: e.base.motion.shiftedBy(seconds));
    });
    apply(next, transient: transient);
  }

  /// removeCue takes cue [id] away, and lets go of everything tied to it.
  void removeCue(String id) {
    var next = _document.copyWith(cues: [
      for (var c in cues)
        if (c.id != id) c,
    ]);
    apply(_everyElement(
        next, (e, _) => e.base.cue == id ? e.withBase(cue: "") : e));
  }

  /// cueTo ties element [id] to cue [cueId], or lets it go with null. Tying
  /// moves the element's keyframes and clip placements so the first of them
  /// lands on the cue.
  void cueTo(String id, String? cueId) {
    var cue =
        cueId == null ? null : cues.where((c) => c.id == cueId).firstOrNull;
    apply(_everyElement(_document, (e, start) {
      if (e.id != id) return e;
      if (cue == null) return e.withBase(cue: "");
      // Its first keyframe, or the first of its placed clips, onto the cue.
      var track = e.base.track;
      var placed = e.base.motion.placed;
      var rate = math.max(1, _document.frameRate);
      int? first = track != null && !track.isEmpty
          ? track.keys.first.frame
          : placed.isEmpty
              ? null
              : (placed.map((p) => p.start).reduce(math.min) * rate).round();
      if (first == null) return e.withBase(cue: cue.id);
      var by = cue.frame - start - first;
      return e.withBase(
          cue: cue.id,
          track: track == null || track.isEmpty ? track : _shifted(track, by),
          motion: e.base.motion.shiftedBy(by / rate));
    }));
  }

  /// findCues puts a cue wherever the voice on [clip] starts a line after a
  /// pause, and says how many it found. Cues it found before on the same
  /// clip are replaced; cues added by hand are left alone.
  Future<int> findCues(AudioElement clip) async {
    var source = clip.clip.playlist.firstOrNull;
    if (source == null) return 0;
    var peaks = await _waveformOf(source.assetId);
    if (peaks == null) return 0;
    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    if (length <= 0) return 0;
    // Where the clip's own time starts in the run: on the master its frame
    // is the run's; on a scene, it is counted from that scene's start.
    var offset = 0;
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == clip.id)) {
        offset = _document.startOfScene(i);
      }
    }
    var from = source.start, to = source.end > 0 ? source.end : length;
    var tag = "voice:${clip.id}";
    var found = [
      for (var t in speechStarts(peaks, length))
        if (t >= from && t < to)
          TimelineCue(
              id: "$tag:${newCueId()}",
              name: "",
              frame: offset + clip.clip.at + ((t - from) * rate).round()),
    ];
    var kept = [
      for (var c in cues)
        if (!c.id.startsWith("$tag:")) c,
    ];
    var named = [
      for (var (i, c) in found.indexed) c.copyWith(name: "Line ${i + 1}"),
    ];
    apply(_document.copyWith(cues: _sortedCues([...kept, ...named])));
    return found.length;
  }

  /// words are what the voice-over says, where -- see SpokenWord.
  List<SpokenWord> get words => _document.words;

  /// hearWords listens to the voice on [clip] and keeps what it says, word
  /// by word, then names the clip's cues by the words they start on -- and
  /// finds those cues first if it has none. Null when it worked; otherwise
  /// what stopped it, said for the reader.
  ///
  /// [model] is where the speech model is, when the caller has just fetched
  /// it somewhere other than its usual place.
  Future<String?> hearWords(AudioElement clip, {String? model}) async {
    var source = clip.clip.playlist.firstOrNull;
    if (source == null) return "That sound has nothing in it to hear.";
    var whisper = await whisperPath();
    if (whisper == null) return speechHelp;
    var ffmpeg = await ffmpegPath();
    if (ffmpeg == null) return ffmpegHelp;
    model ??= await speechModelPath();
    if (!await File(model).exists()) return speechModelMissing;
    var file = await CanvasMedia.existingPath(MediaKind.audio, source.assetId);
    if (file == null) return "The recording is missing from the library.";

    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    var from = source.start, to = source.end > 0 ? source.end : length;
    var heard = await listenTo(
        whisper: whisper,
        ffmpeg: ffmpeg,
        model: model,
        audio: file,
        from: from,
        to: to > from ? to : null);
    if (heard == null) return "whisper could not hear that recording.";
    if (heard.isEmpty) return "No words were heard in that recording.";

    var offset = _clipOffset(clip);
    var tag = "voice:${clip.id}";
    var said = [
      for (var w in heard)
        SpokenWord(
            text: w.text,
            frame: offset + clip.clip.at + (w.start * rate).round(),
            end: offset + clip.clip.at + (w.end * rate).round(),
            from: tag),
    ];
    if (!cues.any((c) => c.id.startsWith("$tag:"))) await findCues(clip);
    var all = [
      for (var w in words)
        if (w.from != tag) w,
      ...said,
    ]..sort((a, b) => a.frame.compareTo(b.frame));

    // Each of this clip's cues is named by what is said from it to the next.
    var mine = [
      for (var c in cues)
        if (c.id.startsWith("$tag:")) c,
    ];
    var named = <String, String>{};
    for (var (i, c) in mine.indexed) {
      var until = i + 1 < mine.length ? mine[i + 1].frame : 1 << 30;
      // A third of a second's lead: see saidBetween.
      var name = saidBetween(said, c.frame, until, lead: (rate / 3).round());
      if (name.isNotEmpty) named[c.id] = name;
    }
    apply(_document.copyWith(words: all, cues: [
      for (var c in cues)
        named[c.id] == null ? c : c.copyWith(name: named[c.id]),
    ]));
    return null;
  }

  /// _clipOffset is where [clip]'s own time starts in the run: on the master
  /// its frames are the run's; on a scene, they count from that scene's
  /// start.
  int _clipOffset(CanvasElement clip) {
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == clip.id)) {
        return _document.startOfScene(i);
      }
    }
    return 0;
  }

  /// dimOthers fades everything already on the canvas down to [to] of
  /// itself as element [id] arrives, over [over] frames, and leaves it
  /// there. Returns how many it dimmed. One step to undo.
  ///
  /// "Down to", not "by", so an element dimmed for an earlier beat does not
  /// sink further. What has not arrived yet or has gone is left alone, as are
  /// things that are not drawn (a sound, the backdrop).
  int dimOthers(String id, {double to = 0.3, int over = 12}) {
    var me = _document.elements.where((e) => e.id == id).firstOrNull;
    if (me == null) return 0;
    var rate = _document.frameRate;
    var at = ownSpan(me, MotionKind.arrive, rate)?.$1 ??
        me.base.track?.keys.firstOrNull?.frame ??
        _frame;

    var dimmed = 0;
    CanvasElement dim(CanvasElement e) {
      if (e.id == id || !e.base.visible) return e;
      if (e is AudioElement || e is BackgroundElement) return e;
      var track = e.base.track ?? ElementTrack.empty;
      if (ownSpan(e, MotionKind.arrive, rate) case (var comes, _)
          when comes >= at) {
        return e;
      }
      if (ownSpan(e, MotionKind.leave, rate) case (var from, var took)
          when from + took <= at) {
        return e;
      }
      if (track.at(at).opacity <= to) return e;

      var start = track.keyAt(at) ??
          track.restingAt(at).copyWith(easing: KeyframeEasing.easeInOut);
      var end = track.keyAt(at + over) ?? track.restingAt(at + over);
      var keys = <Keyframe>[
        for (var k in track.keys)
          if (k.frame < at) k,
        start,
        for (var k in track.keys)
          if (k.frame > at && k.frame != at + over)
            k.copyWith(opacity: math.min(k.opacity, to)),
        end.copyWith(opacity: math.min(end.opacity, to)),
      ];
      dimmed++;
      return e.withBase(track: ElementTrack(keys));
    }

    var next = _document;
    for (var e in _document.elements) {
      var changed = dim(e);
      if (!identical(changed, e)) next = next.withElement(changed);
    }
    if (dimmed > 0) apply(next);
    return dimmed;
  }

  String get wordQuery => _wordQuery;

  set wordQuery(String v) {
    if (v == _wordQuery) return;
    _wordQuery = v;
    notifyListeners();
  }

  /// wordsMatching are the words that [query] is found in, ignoring case
  /// and punctuation, in the order they are said: at most [most].
  List<SpokenWord> wordsMatching(String query, {int most = 6}) {
    String plain(String s) =>
        s.toLowerCase().replaceAll(RegExp(r"[^a-z0-9$.]+"), "");
    var q = plain(query);
    if (q.isEmpty) return const [];
    return [
      for (var w in words)
        if (plain(w.text).contains(q)) w,
    ].take(most).toList();
  }

  /// wordInContext is [word] with the words either side of it, to tell one
  /// "the" from another.
  String wordInContext(SpokenWord word) {
    var i = words.indexOf(word);
    if (i < 0) return word.text;
    return [
      if (i > 0) words[i - 1].text,
      word.text,
      if (i + 1 < words.length) words[i + 1].text,
    ].join(" ");
  }

  /// cueOnWord ties element [id] to the moment [word] is said: to a cue
  /// already there, or to a new one named by the word. One step to undo.
  void cueOnWord(String id, SpokenWord word) {
    beginInteraction();
    var cue = cues.where((c) => c.frame == word.frame).firstOrNull ??
        addCue(name: word.text, frame: word.frame);
    cueTo(id, cue.id);
    endInteraction();
  }

  List<TimelineCue> _sortedCues(List<TimelineCue> list) =>
      [...list]..sort((a, b) => a.frame.compareTo(b.frame));

  /// _shifted is [track] moved [by] frames, never before the first frame.
  ElementTrack _shifted(ElementTrack track, int by) {
    var first = track.keys.first.frame;
    by = math.max(by, -first);
    return ElementTrack([
      for (var k in track.keys) k.copyWith(frame: k.frame + by),
    ]);
  }

  /// _everyElement is [doc] with [f] applied to every element of every
  /// scene and of the master. [f] is told the frame of the run its element's
  /// own frames count from.
  CanvasDocument _everyElement(CanvasDocument doc,
      CanvasElement Function(CanvasElement e, int start) f) {
    var scenes = [
      for (var (i, scene) in doc.allScenes.indexed)
        scene.copyWith(elements: [
          for (var e in scene.elements) f(e, doc.startOfScene(i)),
        ]),
    ];
    var next = doc.scenes.isEmpty
        ? doc
            .copyWith(
              onMaster: false,
              elements: scenes.single.elements,
            )
            .copyWith(onMaster: doc.onMaster)
        : doc.withScenes(scenes, at: doc.at);
    if (doc.master case var master?) {
      next = next.copyWith(
          master: master.copyWith(elements: [
        for (var e in master.elements) f(e, 0),
      ]));
    }
    return next;
  }

  /// _waveformOf is [assetId]'s shape, waited for.
  Future<Float32List?> _waveformOf(String assetId) async {
    for (var i = 0; i < 600; i++) {
      var peaks = waveformOf(assetId);
      if (peaks != null || CanvasController._waveforms.containsKey(assetId))
        return peaks;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  /// sceneAt is which one is being edited, and onMaster whether the shared
  /// canvas is showing instead of any of them.
  int get sceneAt => _document.at;

  bool get onMaster => _document.editingMaster;

  /// goToScene shows another canvas. Not an undo step: which scene is shown
  /// is where the reader is, not an edit. The selection is cleared, since
  /// its elements are on the canvas being left.
  void goToScene(int index) {
    var next = _document.goToScene(index).copyWith(onMaster: false);
    if (identical(next, _document)) return;
    if (!_document.editingMaster) _sceneFrames[_document.scene.id] = _frame;
    apply(next, transient: true);
    // Back where it was left on this scene, rather than one playhead clamped
    // to each scene in turn.
    if (_sceneFrames[_document.scene.id] case var kept?) _frame = kept;
    _afterSceneChange();
  }

  /// frameOn is the frame scene [index] is at: the playhead for the scene
  /// being edited, the frame any other was left on, or the playhead's for one
  /// not visited yet. What the facing page is drawn at, so it shows the same
  /// moment of its animation as when it was left.
  int frameOn(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return _frame;
    var scene = list[index];
    var at = !_document.editingMaster && index == _document.at
        ? _frame
        : (_sceneFrames[scene.id] ?? _frame);
    return at.clamp(0, math.max(0, scene.frames - 1)).toInt();
  }

  /// showMaster puts the shared canvas in front of the reader, making one if
  /// there is none and switching it on if it is off.
  void showMaster() {
    var next = _document;
    if (next.master == null) {
      next =
          next.copyWith(master: CanvasScene(id: newSceneId(), name: "Master"));
    }
    apply(next.copyWith(masterOn: true, onMaster: true), transient: true);
    _afterSceneChange();
  }

  /// masterOn switches the shared canvas on and off. Off, it is kept: turning
  /// it off is not the same as throwing away what is on it.
  set masterOn(bool value) {
    if (_document.masterOn == value) return;
    var next = _document.copyWith(masterOn: value);
    if (!value && next.onMaster) next = next.copyWith(onMaster: false);
    apply(next);
    _afterSceneChange();
  }

  /// addScene puts a new canvas after the one being edited and goes to it.
  void addScene() {
    apply(_document.copyWith(onMaster: false).addScene(after: _document.at));
    _afterSceneChange();
  }

  void duplicateScene(int index) {
    apply(_document.copyWith(onMaster: false).duplicateScene(index));
    _afterSceneChange();
  }

  /// copyScene takes a copy of one, to be pasted into this canvas or another.
  void copyScene(int index) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    CanvasController._sceneClipboard = list[index];
    notifyListeners();
  }

  /// pasteScene puts the copied scene in after the one being looked at, with
  /// fresh ids for the scene and its elements so it can be told apart from
  /// the original.
  void pasteScene() {
    var from = CanvasController._sceneClipboard;
    if (from == null) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insert(
        at,
        from.copyWith(
          id: newSceneId(),
          elements: [for (var e in from.elements) e.withId(newElementId())],
        ));
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  /// setShape changes the shape of the page, keeping the layout of the shape
  /// being left. The one route a ratio change takes: both shapes join the
  /// document's targets, which marks them in the ratio list and is what a new
  /// element is laid out for. A document only ever one shape keeps an empty
  /// list.
  void setShape(CanvasSize next, {int? frameRate}) {
    var was = _document.size;
    if (shapeKey(was) == shapeKey(next) && frameRate == null) {
      apply(_document.copyWith(size: next));
      return;
    }
    var moved = _document.forShape(next);
    if (frameRate != null) moved = moved.copyWith(frameRate: frameRate);

    var targets = [...moved.targets];
    for (var key in [shapeKey(was), shapeKey(next)]) {
      if (!targets.contains(key)) targets.add(key);
    }
    apply(moved.copyWith(targets: targets.length > 1 ? targets : const []));
  }

  /// setKind is whether this document is scenes or pages.
  ///
  /// Choosing pages also sets the shape, the rate and the transition, but
  /// only where they have not been decided already (a canvas already on
  /// paper, a rate typed by hand). Nothing is undone on the way back: called
  /// Scenes again, a document keeps its paper, rate and covers.
  void setKind(CanvasKind kind) {
    if (_document.kind == kind) return;
    // What the size is estimated as follows what the document now is: a
    // piece of sound as its sound, anything else as its picture.
    var estimate = _document.estimate.copyWith(
        format: kind.isAudio
            ? EstimateAs.audio
            : _document.isAnimated
                ? EstimateAs.video
                : EstimateAs.png);
    if (kind != CanvasKind.pages) {
      if (kind.isAudio) _openSoundDesk();
      // A piece of sound counts its time in small steps, so a beat lands on
      // one, where nothing is placed in time yet; going back to scenes goes
      // back to a picture's rate. A document with timing keeps its rate, since
      // changing it would move what is placed.
      int? rate;
      if (!_document.hasTiming) {
        if (kind.isAudio) {
          rate = audioFrameRate;
        } else if (_document.kind.isAudio &&
            _document.frameRate == audioFrameRate) {
          rate = defaultRateFor(_document.size.ratio, kind);
        }
      }
      var frames = rate == null
          ? null
          : (_document.frames * rate / math.max(1, _document.frameRate))
              .round()
              .clamp(1, maxFrameCount)
              .toInt();
      var next = _document.copyWith(
          kind: kind,
          frameRate: rate,
          frames: frames,
          // A piece of sound starts with no canvas -- Ratio "None" -- and
          // anything else always has one.
          hasCanvas: !kind.isAudio);
      // The estimate from what the document now is.
      apply(next.copyWith(
          estimate: next.estimate.copyWith(
              format: kind.isAudio
                  ? EstimateAs.audio
                  : next.isAnimated
                      ? EstimateAs.video
                      : EstimateAs.png)));
      return;
    }

    // Paper, unless it is on paper already. A4 at 150dpi: what "a page"
    // means, and small enough for a document of thirty to draw.
    var size = _document.size;
    var onPaper = size.ratio.isPaper;
    var next = onPaper
        ? size
        : size.copyWith(ratio: CanvasRatio.a4, width: a4PageWidth);

    // Pages turn, so they run at film's rate rather than a printed sheet's
    // one frame a second (see defaultRateFor) -- only where the rate is still
    // what the shape gave it.
    var rate = _document.frameRate == defaultFrameRateFor(size.ratio)
        ? defaultRateFor(next.ratio, kind)
        : null;

    // Through setShape, the one place a shape change goes, so the layouts
    // are swapped rather than the elements keeping their screen numbers. One
    // undo step for the whole of it.
    beginInteraction();
    if (!onPaper) setShape(next, frameRate: rate);
    apply(_document.copyWith(
        kind: kind,
        frameRate: onPaper ? rate : null,
        estimate: estimate,
        hasCanvas: true));
    endInteraction();
  }

  /// setAudio changes the document's sound settings: its tempo, metre,
  /// structure, grid and how it is published.
  void setAudio(AudioSettings next, {bool transient = false}) {
    var doc = _document.copyWith(audio: next);
    // A structure longer than the timeline makes the timeline long enough
    // to hold it: the last section is played to its end.
    if (next.sections.isNotEmpty) {
      var need = (next.totalBars * next.secondsPerBar * doc.frameRate)
          .ceil()
          .clamp(1, maxFrameCount)
          .toInt();
      if (need > doc.frames) doc = doc.copyWith(frames: need);
    }
    var tempoWas = _document.audio.secondsPerBeat;
    apply(doc, transient: transient);
    // The timeline's clips at the new tempo: where they play from and to,
    // and -- warped -- made again.
    if (!transient && next.secondsPerBeat != tempoWas) refreshTimelineClips();
  }

  /// addSection adds a section at the end of the structure, named [name].
  void addSection(String name) {
    var a = _document.audio;
    var taken = {for (var s in a.sections) s.id};
    var n = a.sections.length;
    while (taken.contains("section$n")) {
      n++;
    }
    setAudio(a.copyWith(sections: [
      ...a.sections,
      SongSection("section$n",
          name: name,
          bars: a.sections.isEmpty ? 8 : a.sections.last.bars,
          color: a.sections.length % sectionColors.length),
    ]));
  }

  /// goToSection moves the playhead to where section [index] starts.
  void goToSection(int index) {
    var a = _document.audio;
    if (index < 0 || index >= a.sections.length) return;
    frame = (a.startBar(index) * a.secondsPerBar * _document.frameRate)
        .round()
        .clamp(0, math.max(0, _document.frames - 1))
        .toInt();
  }

  /// setHasCanvas gives the document a picture or takes it away -- the
  /// Ratio "None" of a piece of sound. See CanvasDocument.hasCanvas.
  void setHasCanvas(bool has) {
    if (_document.hasCanvas == has) return;
    apply(_document.copyWith(hasCanvas: has));
  }

  /// forgetShape drops a shape from the document's targets, and the layouts
  /// kept for it: for a shape looked at once and not wanted.
  void forgetShape(String key) {
    if (key == shapeKey(_document.size)) return;
    var left = [
      for (var t in _document.targets)
        if (t != key) t
    ];
    CanvasElement dropped(CanvasElement e) => e.base.layouts.containsKey(key)
        ? e.withBase(layouts: {...e.base.layouts}..remove(key))
        : e;
    CanvasScene scene(CanvasScene s) =>
        s.copyWith(elements: [for (var e in s.elements) dropped(e)]);

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(next.withScenes([for (var s in next.allScenes) scene(s)],
        at: next.at).copyWith(targets: left.length > 1 ? left : const []));
  }

  /// resetShape lays this shape out again from another one, by scale: the
  /// same seeding a first visit to a shape gets.
  void resetShape(String from) {
    var here = _document.size;
    var was = sizeForShape(from, here);

    CanvasScene scene(CanvasScene s) {
      // Laid out from the other shape exactly as a first visit to this one
      // would be: the same block, measure and place, so the design inside the
      // boxes is scaled too.
      var had = [
        for (var e in s.elements)
          if (e.base.layouts[from] case var layout?) showing(e, layout) else e,
      ];
      var seed = seedFor(had, was, here);
      return s.copyWith(elements: [
        for (var e in had)
          showing(
              e, seeded(ElementLayout.of(e.base), seed, coversPage(e, was))),
      ]);
    }

    var next = _document.master == null
        ? _document
        : _document.copyWith(master: scene(_document.master!));
    apply(
        next.withScenes([for (var s in next.allScenes) scene(s)], at: next.at));
  }

  /// addScenes puts [scenes] in after the one being looked at, and goes to
  /// the first of them: how a saved scene or saved canvas is dropped in. The
  /// ids are the caller's to make fresh (see SavedPreset.buildScenes).
  void addScenes(List<CanvasScene> scenes) {
    if (scenes.isEmpty) return;
    var list = [..._document.allScenes];
    var at = (_document.sceneAt + 1).clamp(0, list.length).toInt();
    list.insertAll(at, scenes);
    apply(_document.copyWith(onMaster: false).withScenes(list, at: at));
    _afterSceneChange();
  }

  void removeScene(int index) {
    apply(_document.copyWith(onMaster: false).removeScene(index));
    _afterSceneChange();
  }

  void moveScene(int from, int to) {
    apply(_document.moveScene(from, to));
    _afterSceneChange();
  }

  void renameScene(int index, String name) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(name: name.trim())));
  }

  /// setBackground writes the backdrop being edited: the shared canvas's own
  /// while that is the one open, and otherwise the scene's or document's.
  /// The panel edits "the background"; which one is decided here.
  void setBackground(CanvasBackground next, {bool transient = false}) {
    var document = _document;
    if (document.editingMaster) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // The shared canvas's own, where that is the one on screen: a master
    // backdrop is drawn in front of every scene's, so writing the scene's
    // would change nothing visible. See CanvasDocument.editedBackground.
    if (document.sharedBackdrop) {
      apply(document.withMaster(document.master!.copyWith(background: next)),
          transient: transient);
      return;
    }
    // This scene's own, where it has one (that is what is drawn) or where
    // there are several scenes, so an edit does not leak onto all of them.
    // Ownership rather than a scene count, because a scene can own one while
    // being the only scene left. A document with no scenes answers no to
    // both: its reported scene is made up on the spot and owns nothing.
    if (document.scene.background != null || document.hasScenes) {
      apply(
          document.withScene(
              document.at, document.scene.copyWith(background: next)),
          transient: transient);
      return;
    }
    apply(document.copyWith(background: next), transient: transient);
  }

  /// setMasterBackgroundOff leaves every scene its own backdrop, or puts the
  /// shared one back over them. The shared backdrop is kept either way.
  void setMasterBackgroundOff(bool off) {
    var master = _document.master;
    if (master == null) return;
    apply(_document.withMaster(master.copyWith(backgroundOff: off)));
  }

  /// setSceneHolds decides whether playback runs on into the next scene.
  void setSceneHolds(int index, bool holds) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(holds: holds)));
  }

  /// setSceneMasterOff leaves the master canvas off scene [index] -- a
  /// game's title screen without its HUD -- or puts it back.
  void setSceneMasterOff(int index, bool off) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(_document.withScene(index, list[index].copyWith(masterOff: off)));
  }

  /// setSceneCover marks a page as the front or the back of the document: at
  /// most one of each, since the numbering and the pairing are read from
  /// these marks.
  void setSceneCover(int index, PageCover cover) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    var next = [
      for (var (at, scene) in list.indexed)
        at == index
            ? scene.copyWith(cover: cover)
            // Whoever held this mark before gives it up.
            : (cover.isCover && scene.cover == cover
                ? scene.copyWith(cover: PageCover.none)
                : scene),
    ];
    apply(_document.withScenes(next, at: _document.at));
  }

  /// setSceneTransition gives a scene its own way of giving way to the next,
  /// or takes it back to the document's default.
  void setSceneTransition(int index, SceneTransition? transition,
      {bool transient = false}) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    apply(
        _timed(_document.withScene(
            index,
            transition == null
                ? list[index].copyWith(clearTransition: true)
                : list[index].copyWith(transition: transition))),
        transient: transient);
  }

  /// cameraView is whether the canvas shows the scene through its camera
  /// while paused -- stepped and scrubbed, as well as played -- so a camera
  /// can be set up by looking. On while a camera is being set, off at the
  /// next press on the canvas, since the page is drawn moved and a press
  /// would land somewhere other than it looks.
  bool get cameraView => _cameraView;

  set cameraView(bool on) {
    if (on == _cameraView) return;
    _cameraView = on;
    notifyListeners();
  }

  /// setSceneCamera gives scene [index] a slow move, or holds it still with
  /// null. See SceneCamera.
  void setSceneCamera(int index, SceneCamera? camera) {
    var list = _document.allScenes;
    if (index < 0 || index >= list.length) return;
    _cameraView = camera != null;
    apply(_document.withScene(
        index,
        camera == null
            ? list[index].copyWith(clearCamera: true)
            : list[index].copyWith(camera: camera)));
  }

  /// soundEveryTransition puts [like]'s sound -- its file, volume and lead
  /// -- on the default transition and on every scene's own, as one change.
  void soundEveryTransition(SceneTransition like) {
    SceneTransition sounded(SceneTransition t) => t.copyWith(
        sound: like.sound,
        soundName: like.soundName,
        soundLength: like.soundLength,
        soundVolume: like.soundVolume,
        soundLead: like.soundLead);
    var master =
        _document.master ?? CanvasScene(id: newSceneId(), name: "Master");
    var next = _document.copyWith(
        master:
            master.copyWith(transition: sounded(_document.defaultTransition)));
    var list = next.allScenes;
    for (var (i, scene) in list.indexed) {
      if (scene.transition case var t?) {
        next = next.withScene(i, scene.copyWith(transition: sounded(t)));
      }
    }
    apply(next);
  }

  /// _timed is [next] with every scene back at its start: a transition made
  /// longer or shorter is taken from, or given to, the scene before it, so
  /// nothing later in the run moves against the master's voice-over. See
  /// CanvasDocument.keepingStarts.
  CanvasDocument _timed(CanvasDocument next) => next.keepingStarts(_document);

  /// setDefaultTransition changes what every scene without one of its own
  /// uses. It lives on the master canvas, which is where the things shared by
  /// every scene live.
  void setDefaultTransition(SceneTransition transition) {
    var master =
        _document.master ?? CanvasScene(id: newSceneId(), name: "Master");
    apply(_timed(
        _document.copyWith(master: master.copyWith(transition: transition))));
  }

  /// _afterSceneChange puts the editor back on solid ground after a scene
  /// change: no selection of the canvas just left, no frame past the end.
  void _afterSceneChange() {
    _audioFollowsPage(turned: true);
    _syncTimeline();
    _selection = {};
    _backgroundSelected = false;
    _focusedPlayer = null;
    _frame = _frame.clamp(0, math.max(0, _document.frames - 1)).toInt();
    notifyListeners();
  }

  void clearSelection() {
    if (_selection.isEmpty && !_backgroundSelected && _offCanvas.isEmpty) {
      return;
    }
    _backgroundSelected = false;
    _focusedPlayer = null;
    _offCanvas = const {};
    _selection = {};
    _leaveVectorIfUnpicked();
    notifyListeners();
  }

  void selectAll() {
    _backgroundSelected = false;
    _offCanvas = const {};
    // What is on the canvas: a sound on the timeline is not, and taking it
    // in would put the soundtrack one Delete away.
    _selection = {
      for (var e in _document.elements)
        if (!e.locked && !isTimelineSound(e)) e.id,
    };
    notifyListeners();
  }
}
