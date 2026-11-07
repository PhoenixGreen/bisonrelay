part of '../canvas_controller.dart';

// The Speech device, phrasing, hearing takes, MIDI files and the Vocaliser.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasSpeech on CanvasController {
  /// speechOf is channel [channel]'s Speech device, or null for none.
  SpeechSpec? speechOf(String channel) =>
      timelineChannels.where((c) => c.key == channel).firstOrNull?.mix.speech;

  /// setSpeech puts a Speech device on [channel] -- or changes it, or with
  /// null takes it off.
  void setSpeech(String channel, SpeechSpec? spec, {bool transient = false}) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    if (lane == null) return;
    // Taken off: its view and its Phrasing go with it, back to the chain --
    // not left open on a "Speak a script" with no tab to leave by.
    if (spec == null) {
      _speechShown = false;
      if (_phrasing?.channel == channel) _phrasing = null;
    }
    setChannelMix(
        lane,
        spec == null
            ? lane.mix.copyWith(noSpeech: true)
            : lane.mix.copyWith(speech: spec),
        transient: transient);
  }

  /// speechLineState is "speaking" or "waiting" for a line in the queue,
  /// or null.
  String? speechLineState(String channel, SpeechLine line) {
    var queue = speechQueue[channel];
    if (queue == null) return null;
    var key = CanvasController.speechLineKey(line);
    if (_speakingNow[channel]?.contains(key) ?? false) return "speaking";
    return queue.contains(key) ? "waiting" : null;
  }

  /// stopSpeaking stops what [channel] is speaking, and lets go of the
  /// sections waiting: the program speaking is ended, and nothing it was
  /// part way through is kept. The takes already made stay.
  void stopSpeaking(String channel) {
    var stop = _speechStops[channel];
    if (stop == null) return;
    speechQueue[channel]?.clear();
    stop.stop();
    notifyListeners();
  }

  /// _lineSpeech is [channel]'s device with its lines set out -- those of
  /// its script, where it has none yet.
  SpeechSpec? _lineSpeech(String channel) {
    var spec = speechOf(channel);
    if (spec == null || spec.lines.isNotEmpty) return spec;
    var lines = spec.shownLines;
    if (lines.isEmpty) return spec;
    spec = spec.copyWith(lines: lines);
    setSpeech(channel, spec, transient: true);
    return spec;
  }

  /// speakLines speaks [lines] of [channel] -- by default, every line with
  /// no take yet -- in the background, each into a slot of its own: the
  /// one it is to replace, or else its first free one. Nothing is put on
  /// the timeline, nor in the Audio library: see saveTake, addTake and
  /// joinSpeech. Lines asked for while it runs join the queue. Answers why
  /// not, where it could not.
  Future<String?> speakLines(String channel, {List<SpeechLine>? lines}) async {
    var spec = _lineSpeech(channel);
    if (spec == null) return null;
    var wanted = lines ??
        [
          for (var l in spec.lines)
            if (l.takes.isEmpty) l
        ];
    var queue = speechQueue[channel];
    var running = queue != null;
    queue ??= speechQueue[channel] = [];
    for (var l in wanted) {
      var key = CanvasController.speechLineKey(l);
      if (!queue.contains(key)) queue.add(key);
    }
    notifyListeners();
    if (running) return null;
    String? problem;
    try {
      while (queue.isNotEmpty && !_disposed) {
        var now = speechOf(channel);
        if (now == null) break;
        SpeechLine? lineOf(String k) => now.lines
            .where((l) => CanvasController.speechLineKey(l) == k)
            .firstOrNull;
        // Lines edited away while they waited are not spoken, nor those
        // with no slot to go into.
        var into = _speechInto[channel] ?? const {};
        queue.removeWhere((k) {
          var l = lineOf(k);
          return l == null || (into[k] == null && l.freeSlot < 0);
        });
        if (queue.isEmpty) break;
        var engine = CanvasController.speechEngineFor(now);
        var stop = engine.stopper = _speechStops[channel] = SpeechStop();
        // Every line waiting, at once, where the engine does better so;
        // else the first.
        var keys = engine.batches ? [...queue] : [queue.first];
        var lines = [for (var k in keys) lineOf(k)!];
        _speakingNow[channel] = {...keys};
        notifyListeners();
        var audios = engine.batches
            ? await engine.speakLines(now, lines)
            // Another seed each time: a take replacing one is not the same.
            : [
                await engine.speakLine(now, lines.single,
                    seed: 1 + _seeds.nextInt(1 << 30))
              ];
        if (_disposed) return null;
        if (stop.stopped) break;
        for (var (i, key) in keys.indexed) {
          if (!await _keepLineTake(channel, key, audios[i])) {
            problem = "The take could not be kept.";
            break;
          }
          queue.remove(key);
          _speechInto[channel]?.remove(key);
          notifyListeners();
        }
        if (problem != null) break;
      }
    } on SpeechException catch (e) {
      // Stopped, it is as asked: nothing to say.
      if (!(_speechStops[channel]?.stopped ?? false)) problem = e.message;
    } catch (e) {
      debugPrint("Unable to speak a line: $e");
      problem = "The voice could not speak: $e";
    } finally {
      _speechStops.remove(channel);
      speechQueue.remove(channel);
      _speechInto.remove(channel);
      _speakingNow.remove(channel);
      if (!_disposed) notifyListeners();
    }
    return problem;
  }

  /// _keepLineTake keeps [audio] as a take of [channel]'s line [key], in
  /// the slot it was to replace or its first free one, picked. Kept apart
  /// from the library -- see speechTakeStore. Whether it could be kept; a
  /// line edited away meanwhile is let go.
  Future<bool> _keepLineTake(
      String channel, String key, SpokenAudio audio) async {
    var id = await CanvasController.speechTakeStore(wav16(audio.l, audio.r));
    if (id == null) return false;
    // Where the line is now: it may have moved while it was spoken.
    var after = speechOf(channel);
    if (after == null) return true;
    var at =
        after.lines.indexWhere((l) => CanvasController.speechLineKey(l) == key);
    if (at < 0) return true;
    var line = after.lines[at];
    var slot = _speechInto[channel]?[key] ?? line.freeSlot;
    if (slot < 0) return true;
    var l = line.withSlot(
        slot, SpeechTake(id, audio.seconds, audio.words, exact: audio.exact));
    // A change of its own, not transient: with no gesture open, a transient
    // take would be taken away by the next Undo of anything.
    setSpeech(
        channel,
        after.copyWith(lines: [
          for (var (i, x) in after.lines.indexed) i == at ? l : x,
        ]));
    return true;
  }

  /// anotherTake speaks [line] of [channel] again into slot [slot] -- one
  /// not in use -- or its first free one. With all three in use, it says
  /// so: a take is only replaced by the reader, with replaceTake.
  Future<String?> anotherTake(String channel, SpeechLine line, {int? slot}) {
    var into = slot != null && line.slot(slot) == null ? slot : line.freeSlot;
    if (into < 0) {
      return Future.value(
          "All three slots are in use: pick one, and Replace it.");
    }
    (_speechInto[channel] ??= {})[CanvasController.speechLineKey(line)] = into;
    return speakLines(channel, lines: [line]);
  }

  /// replaceTake speaks line [index] of [channel] again into slot [slot],
  /// in place of the take there.
  Future<String?> replaceTake(String channel, int index, int slot) {
    var spec = _lineSpeech(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) {
      return Future.value(null);
    }
    var line = spec.lines[index];
    (_speechInto[channel] ??= {})[CanvasController.speechLineKey(line)] = slot;
    return speakLines(channel, lines: [line]);
  }

  /// speechReplacing is the slot line [line] of [channel] is being spoken
  /// into, while it waits or is spoken -- or null.
  int? speechReplacing(String channel, SpeechLine line) {
    var key = CanvasController.speechLineKey(line);
    if (!(speechQueue[channel]?.contains(key) ?? false)) return null;
    return _speechInto[channel]?[key] ?? line.freeSlot;
  }

  /// _slotTake is line [index]'s slot [slot] on [channel], with the device
  /// and the line -- or null for none there.
  (SpeechSpec, SpeechLine, SpeechTake)? _slotTake(
      String channel, int index, int slot) {
    var spec = speechOf(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) return null;
    var line = spec.lines[index];
    var take = line.slot(slot);
    return take == null ? null : (spec, line, take);
  }

  void _setSlot(String channel, int index, int slot, SpeechTake? take,
      {bool transient = false}) {
    var spec = speechOf(channel);
    if (spec == null || index >= spec.lines.length) return;
    setSpeech(
        channel,
        spec.copyWith(lines: [
          for (var (i, l) in spec.lines.indexed)
            i == index ? l.withSlot(slot, take) : l
        ]),
        transient: transient);
  }

  /// chooseTake picks slot [slot] of line [index]: the take "Add all
  /// lines" puts on the timeline.
  void chooseTake(String channel, int index, int slot) {
    var spec = speechOf(channel);
    if (spec == null || index < 0 || index >= spec.lines.length) return;
    var line = spec.lines[index];
    if (line.slot(slot) == null || line.chosen == slot) return;
    setSpeech(
        channel,
        spec.copyWith(lines: [
          for (var (i, l) in spec.lines.indexed)
            i == index ? l.copyWith(chosen: slot) : l
        ]));
  }

  /// removeTake empties slot [slot] of line [index]: one change to undo.
  /// Its file goes at the next tidy, once nothing has it -- unless it was
  /// saved, when the library keeps it.
  void removeTake(String channel, int index, int slot) {
    if (_slotTake(channel, index, slot) == null) return;
    beginInteraction();
    _setSlot(channel, index, slot, null, transient: false);
    endInteraction();
  }

  /// phrasing is the take the Speech device's Phrasing is open on: a
  /// channel's section, and its slot -- which may have no take yet.
  ({String channel, int line, int slot})? get phrasing => _phrasing;

  /// phrasingTake is the take Phrasing is open on, as it is now.
  SpeechTake? get phrasingTake {
    var p = _phrasing;
    return p == null ? null : _slotTake(p.channel, p.line, p.slot)?.$3;
  }

  /// openPhrasing opens Phrasing on slot [slot] of [channel]'s section
  /// [line] -- in the Speech device, in place of its sections -- and reads
  /// the take as spoken. Another take, its words picked afresh.
  void openPhrasing(String channel, int line, int slot) {
    var next = (channel: channel, line: line, slot: slot);
    if (next == _phrasing) return;
    _phrasing = next;
    phrasingPicked = const {0};
    notifyListeners();
    if (phrasingTake case var take?) unawaited(_readSpoken(take.asSpoken));
  }

  /// closePhrasing goes back to the device's sections.
  void closePhrasing() {
    if (_phrasing == null) return;
    _phrasing = null;
    notifyListeners();
  }

  /// pickWords picks [words] -- [adding] them to those picked, or, a word
  /// already picked, taking it off.
  void pickWords(Iterable<int> words, {bool adding = false}) {
    var next = <int>{};
    if (adding) {
      next.addAll(phrasingPicked);
      for (var w in words) {
        if (!next.remove(w)) next.add(w);
      }
      // The last added first: its settings shown.
      var added = words.where(next.contains).toList();
      if (added.isNotEmpty) next = {added.last, ...next};
    } else {
      next.addAll(words);
    }
    if (next.isEmpty) return;
    phrasingPicked = next;
    notifyListeners();
  }

  /// readingOf is what was heard of [take] as spoken -- its pitch, each
  /// word's loudness -- or null until it has been read.
  TakeReading? readingOf(SpeechTake take) => _readings[take.asSpoken.assetId];

  /// _readSpoken reads [spoken] -- a take as the voice spoke it -- once:
  /// its sound, or null where its file could not be.
  Future<Float32List?> _readSpoken(SpeechTake spoken) async {
    var id = spoken.assetId;
    Float32List? pcm;
    try {
      pcm = await CanvasController.takeAudio(id);
    } catch (exception) {
      debugPrint("A take could not be read: $exception");
    }
    if (_disposed) return pcm;
    if (pcm == null) {
      if (_unreadTakes.add(id)) notifyListeners();
      return null;
    }
    if (!_readings.containsKey(id) && _readingTakes.add(id)) {
      var words = spoken.words;
      var sound = pcm;
      try {
        _readings[id] = await Isolate.run(() => readTake(sound, words));
      } catch (exception) {
        debugPrint("A take could not be read: $exception");
        _unreadTakes.add(id);
      } finally {
        _readingTakes.remove(id);
      }
      if (!_disposed) notifyListeners();
    }
    return pcm;
  }

  /// readPhrasingTake starts reading the take Phrasing is open on, where it
  /// is not read or being read: one spoken after Phrasing was opened.
  void readPhrasingTake() {
    var spoken = phrasingTake?.asSpoken;
    if (spoken == null) return;
    var id = spoken.assetId;
    if (_readings.containsKey(id) ||
        _readingTakes.contains(id) ||
        _unreadTakes.contains(id)) {
      return;
    }
    unawaited(_readSpoken(spoken));
  }

  /// phrasingUnread is whether the take Phrasing is open on could not be
  /// read.
  bool get phrasingUnread =>
      _unreadTakes.contains(phrasingTake?.asSpoken.assetId);

  /// shapeWords shapes several words of the take Phrasing is open on, by
  /// their places in it, as one change. Its sound is made again a moment
  /// after the last change.
  void shapeWords(Map<int, WordShape> next, {bool transient = false}) {
    var p = _phrasing;
    var take = phrasingTake;
    if (p == null || take == null) return;
    var shapes = [
      for (var i = 0; i < take.asSpoken.words.length; i++)
        next[i] ?? take.shapeOf(i)
    ];
    _setSlot(p.channel, p.line, p.slot, take.withShapes(shapes),
        transient: transient);
    _shapeSoon();
  }

  /// resetPhrasing puts every word of the take back as it was spoken: one
  /// change to undo.
  void resetPhrasing() {
    var p = _phrasing;
    var take = phrasingTake;
    if (p == null || take == null || !take.shaped) return;
    _setSlot(p.channel, p.line, p.slot, take.withShapes(const []),
        transient: false);
    _shapeSoon();
  }

  /// _shapeSoon makes the open take's sound again, a moment after the last
  /// change: ready to hear by the time it is asked for.
  void _shapeSoon() {
    _shapeTimer?.cancel();
    _shapeTimer = Timer(const Duration(milliseconds: 300), () {
      var p = _phrasing;
      if (p != null) unawaited(shapedTake(p.channel, p.line, p.slot));
    });
  }

  /// shapedTake is slot [slot]'s take of [channel]'s section [index], its
  /// sound made from its shapes first where it is not yet -- what is
  /// heard, saved, put on the timeline or joined.
  Future<SpeechTake?> shapedTake(String channel, int index, int slot) async {
    var key = "$channel/$index/$slot";
    for (var running = _shaping[key];
        running != null;
        running = _shaping[key]) {
      await running;
    }
    var take = _slotTake(channel, index, slot)?.$3;
    if (take == null || !take.needsShaping) return take;
    var job = _shapeTake(channel, index, slot, take);
    _shaping[key] = job;
    try {
      return await job;
    } finally {
      _shaping.remove(key);
    }
  }

  Future<SpeechTake?> _shapeTake(
      String channel, int index, int slot, SpeechTake take) async {
    var spoken = take.asSpoken;
    SpeechTake? made;
    if (!take.shaped) {
      made = spoken;
    } else {
      var pcm = await _readSpoken(spoken);
      var reading = _readings[spoken.assetId];
      if (pcm == null || reading == null || _disposed) return take;
      var words = spoken.words, shapes = take.shapes;
      var shaped =
          await Isolate.run(() => shapeTake(pcm, words, shapes, reading));
      var id = await CanvasController.speechTakeStore(
          wav16(shaped.sound, shaped.sound));
      if (id == null || _disposed) return take;
      made = take.madeAs(id, shaped.sound.length / mixRate, shaped.words);
    }
    // Shaped again meanwhile: that is made next.
    var now = _slotTake(channel, index, slot)?.$3;
    if (now == null || now.shapesKey != take.shapesKey) return now;
    // The sound of the shaping, not a change of its own: Undo of the
    // shaping takes this with it, and it is made again when wanted.
    _setSlot(channel, index, slot, made, transient: true);
    return made;
  }

  /// hearSlot plays slot [slot]'s take of [channel]'s section [index] --
  /// shaped, or, [spoken], as the voice spoke it -- from [at] seconds into
  /// it; or, playing, stops it.
  Future<String?> hearSlot(String channel, int index, int slot,
      {bool spoken = false, double at = 0}) async {
    var take = spoken
        ? _slotTake(channel, index, slot)?.$3.asSpoken
        : await shapedTake(channel, index, slot);
    if (take == null) return null;
    return hearTake(take.assetId, at: at);
  }

  /// saveTake puts slot [slot]'s take of line [index] in the Audio library,
  /// answering it saved -- or why not.
  Future<(SpeechTake?, String?)> saveTake(
      String channel, int index, int slot) async {
    await shapedTake(channel, index, slot);
    var found = _slotTake(channel, index, slot);
    if (found == null) return (null, null);
    var (spec, line, take) = found;
    if (take.saved) return (take, null);
    var file = await CanvasController.takePath(take.assetId);
    if (file == null) return (null, "The take's file could not be found.");
    var id = await CanvasController.speechStore(file);
    if (id == null || _disposed) return (null, "The take could not be saved.");
    await CanvasController.speechLibrary(
        id,
        "${spec.voiceName.isEmpty ? "Speech" : spec.voiceName} · line "
        "${index + 1} · take ${String.fromCharCode(65 + slot)} · "
        "${CanvasController._firstWords(line.text)}",
        take.length);
    var saved = take.copyWith(assetId: id, saved: true);
    _setSlot(channel, index, slot, saved);
    return (saved, null);
  }

  /// addTake puts slot [slot]'s take of line [index] on the timeline, in a
  /// clip of its own at the playhead -- saved to the Audio library first,
  /// and kept with the device so a character's lips follow it. One change
  /// to undo.
  Future<String?> addTake(String channel, int index, int slot) async {
    var (take, problem) = await saveTake(channel, index, slot);
    if (take == null) return problem;
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    var spec = lane?.mix.speech;
    if (lane == null || spec == null || _disposed) return null;
    beginInteraction();
    var mix = lane.mix.copyWith(
        speech: spec.copyWith(takes: [
      for (var t in spec.takes)
        if (t.assetId != take.assetId) t,
      take,
    ]));
    setChannelMix(lane, mix, transient: true);
    addElement(channelClip(_document, _frame,
        source: MediaSource(
            assetId: take.assetId,
            name: "Line ${index + 1} · take ${String.fromCharCode(65 + slot)}",
            length: take.length),
        channel: channel,
        channelName: lane.name,
        mix: mix));
    endInteraction();
    return null;
  }

  /// setSpeechLines changes [channel]'s lines -- a direction, own words, a
  /// join or a split -- the script written from them.
  void setSpeechLines(String channel, List<SpeechLine> lines) {
    var spec = speechOf(channel);
    if (spec == null) return;
    setSpeech(channel, spec.withLines(lines));
  }

  /// joinSpeechLine makes line [index] and the next one line, to be spoken
  /// as one: its direction the first's, its takes none yet.
  void joinSpeechLine(String channel, int index) {
    var lines = _lineSpeech(channel)?.lines;
    if (lines == null || index < 0 || index + 1 >= lines.length) return;
    var a = lines[index], b = lines[index + 1];
    setSpeechLines(channel, [
      ...lines.take(index),
      SpeechLine("${a.text} ${b.text}", direction: a.direction, own: a.own),
      ...lines.skip(index + 2),
    ]);
  }

  /// splitSpeechLine cuts line [index] in two at speechSplitAt, each with
  /// its direction and no takes yet.
  void splitSpeechLine(String channel, int index) {
    var lines = _lineSpeech(channel)?.lines;
    if (lines == null || index < 0 || index >= lines.length) return;
    var l = lines[index];
    var at = CanvasController.speechSplitAt(l.text);
    if (at == null) return;
    setSpeechLines(channel, [
      ...lines.take(index),
      SpeechLine(l.text.substring(0, at).trim(),
          direction: l.direction, own: l.own),
      SpeechLine(l.text.substring(at).trim(),
          direction: l.direction, own: l.own),
      ...lines.skip(index + 1),
    ]);
  }

  Future<String?> _keepWav(Uint8List wav, String name) async {
    var dir = await Directory.systemTemp.createTemp("canvas-take");
    try {
      var file = File(path.join(dir.path, "$name.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await CanvasController.speechStore(file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  /// joinSpeech is "Add all lines to the timeline": [channel]'s lines,
  /// each its slot picked, a pause between each two, given the finish --
  /// the room and the speaker boost -- in the channel's clip: the one it
  /// made before, its sound changed, or a new one at the playhead. Saved
  /// to the Audio library; nothing goes on the timeline but by this, or a
  /// slot's own addTake. One change to undo.
  Future<String?> joinSpeech(String channel) async {
    var spec = speechOf(channel);
    if (spec == null || !joining.add(channel)) return null;
    notifyListeners();
    try {
      // Each take as it is shaped.
      for (var (i, l) in spec.lines.indexed) {
        if (l.take != null) await shapedTake(channel, i, l.chosen);
      }
      spec = speechOf(channel);
      if (spec == null) return null;
      var takes = [
        for (var l in spec.lines)
          if (l.take case var t?) t
      ];
      if (takes.isEmpty) return null;
      var sounds = <Float32List>[];
      for (var t in takes) {
        var sound = await CanvasController.takeAudio(t.assetId);
        if (sound == null) return "A take's file could not be read.";
        sounds.add(sound);
      }
      // Joined and finished in an isolate of its own: on the app's, the
      // finish holds everything up for seconds on a long script.
      var joined = await CanvasController._joinAway(sounds, takes, spec.speed,
          room: spec.room, boost: spec.boost);
      if (_disposed) return null;
      var id = await _keepWav(joined.wav, "speech");
      if (id == null || _disposed) return "The clip could not be kept.";
      var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
      var now = lane?.mix.speech;
      if (lane == null || now == null) return null;
      var old = _document.elements
          .whereType<AudioElement>()
          .where((e) => e.id == now.clip)
          .firstOrNull;
      var oldId = old?.clip.playlist.firstOrNull?.assetId;
      var take =
          SpeechTake(id, joined.seconds, joined.words, exact: joined.exact);
      beginInteraction();
      var kept = now.copyWith(takes: [
        for (var t in now.takes)
          if (t.assetId != oldId) t,
        take,
      ]);
      var source =
          MediaSource(assetId: id, name: "Speech", length: joined.seconds);
      if (old != null) {
        setChannelMix(lane, lane.mix.copyWith(speech: kept), transient: true);
        var e = _document.elements
            .whereType<AudioElement>()
            .where((e) => e.id == old.id)
            .first;
        replaceElement(e.copyWith(
            clip: e.clip.copyWith(playlist: [
          source.copyWith(name: e.clip.playlist.firstOrNull?.name),
          ...e.clip.playlist.skip(1),
        ])));
      } else {
        var clip = channelClip(_document, _frame,
            source: source,
            channel: channel,
            channelName: lane.name,
            mix: lane.mix);
        kept = kept.copyWith(clip: clip.id);
        var mix = lane.mix.copyWith(speech: kept);
        setChannelMix(lane, mix, transient: true);
        addElement(clip.copyWith(clip: clip.clip.copyWith(mix: mix)));
      }
      endInteraction();
      // The clip in the Audio library: this one in place of the last.
      if (oldId != null && oldId != id)
        await CanvasController.speechUnlist(oldId);
      await CanvasController.speechLibrary(
          id,
          "Speech · ${now.voiceName.isEmpty ? "voice" : now.voiceName} · "
          "${CanvasController._firstWords(now.lines.map((l) => l.text).join(" "))}",
          joined.seconds);
      return null;
    } catch (e) {
      debugPrint("Unable to join the lines: $e");
      return "The lines could not be joined: $e";
    } finally {
      joining.remove(channel);
      if (!_disposed) notifyListeners();
    }
  }

  /// speechHeard is what is being heard on its own, outside the mix: a
  /// take's asset id, or "voice:" and the voice previewed -- null for
  /// nothing. speechPreviewing is the voice being spoken for its preview.
  String? get speechHeard => _speechHeard;

  /// hearTake plays take [assetId] on its own, from [at] seconds into it
  /// -- or, playing, stops it. Answers why not, where it could not.
  Future<String?> hearTake(String assetId, {double at = 0}) async {
    if (_speechHeard == assetId) {
      stopHearing();
      return null;
    }
    var file = await CanvasController.takePath(assetId);
    if (file == null) return "The take's file could not be found.";
    return _hear(file, assetId, at: at);
  }

  /// heardSeconds is how far into what is being heard on its own it has
  /// played -- or null, with nothing heard.
  double? get heardSeconds {
    var v = _heardVoice;
    if (v == null || _speechHeard == null) return null;
    return audio.engine.position(v);
  }

  Future<String?> _hear(String file, String what, {double at = 0}) async {
    stopHearing();
    var engine = audio.engine;
    if (!await engine.start()) return "There is no sound to play it on.";
    var track = await engine.open(file);
    if (track == null || _disposed) return "It could not be played.";
    _heardTrack = track;
    _heardVoice = engine.play(track, volume: 1, at: at);
    _speechHeard = what;
    _heardWatch = Timer.periodic(const Duration(milliseconds: 250), (_) {
      var v = _heardVoice;
      if (v == null || !engine.alive(v)) stopHearing();
    });
    notifyListeners();
    return null;
  }

  /// stopHearing stops what is being heard on its own.
  void stopHearing() {
    _heardWatch?.cancel();
    _heardWatch = null;
    var voice = _heardVoice, track = _heardTrack;
    _heardVoice = null;
    _heardTrack = null;
    if (voice != null) audio.engine.stop(voice);
    if (track != null) audio.engine.close(track);
    if (_speechHeard != null) {
      _speechHeard = null;
      if (!_disposed) notifyListeners();
    }
  }

  /// previewVoice speaks speechSample in [voice] -- channel [channel]'s
  /// device's engine, language and feel, its finish too -- and plays it; or,
  /// playing, stops it. Not kept: nothing is added to the library.
  Future<String?> previewVoice(String channel, String voice) async {
    var what = "voice:$voice";
    if (_speechHeard == what) {
      stopHearing();
      return null;
    }
    var now = speechOf(channel);
    if (now == null || speechPreviewing != null) return null;
    var spec = now.copyWith(voice: voice);
    var key = [
      spec.engine.name,
      voice,
      spec.language,
      spec.speed.toStringAsFixed(2),
      spec.steadiness.toStringAsFixed(2),
      spec.expression.toStringAsFixed(2),
      spec.room.toStringAsFixed(2),
      spec.boost,
    ].join("|");
    var file = _previews[key];
    if (file == null || !await File(file).exists()) {
      speechPreviewing = voice;
      notifyListeners();
      try {
        var said = await CanvasController.speechEngineFor(spec)
            .speakLine(spec, const SpeechLine(CanvasController.speechSample));
        var finished = await CanvasController._joinAway([
          said.l
        ], [
          SpeechTake("", said.seconds, said.words, exact: said.exact)
        ], spec.speed, room: spec.room, boost: spec.boost);
        if (_disposed) return null;
        _previewDir ??= await Directory.systemTemp.createTemp("canvas-voices");
        file = path.join(_previewDir!.path, "voice-${_previews.length}.wav");
        await File(file).writeAsBytes(finished.wav, flush: true);
        _previews[key] = file;
      } on SpeechException catch (e) {
        return e.message;
      } catch (e) {
        debugPrint("Unable to preview a voice: $e");
        return "The voice could not speak: $e";
      } finally {
        speechPreviewing = null;
        if (!_disposed) notifyListeners();
      }
    }
    if (_disposed) return null;
    return _hear(file, what);
  }

  /// addMidiChannelFrom makes a MIDI channel playing MIDI file [source],
  /// from [frame] -- the playhead with none -- named after the file.
  Future<AudioElement?> addMidiChannelFrom(MediaSource source,
      {int? frame, bool onCanvas = true}) async {
    var read = await CanvasController.midiOfAsset(source.assetId);
    if (read == null || _disposed) return null;
    var e = newInstrument(_document);
    var part = e.instrument!.copyWith(notes: read.notes);
    e = e
        .copyWith(instrument: part, clip: e.clip.copyWith(at: frame ?? _frame))
        .rebase(e.base.copyWith(
            name: source.name.isEmpty ? "MIDI file" : source.name,
            visible: onCanvas &&
                (_document.hasCanvas ||
                    !_document.kind.isAudio))) as AudioElement;
    addElement(e);
    return e;
  }

  /// putMidiOn adds MIDI file [assetId]'s notes to MIDI channel [channel]'s
  /// part, from [frame]: one change to undo.
  Future<bool> putMidiOn(String channel, String assetId, int frame) async {
    var read = await CanvasController.midiOfAsset(assetId);
    var e = _instrumentOf(channel);
    if (read == null || e == null || _disposed) return false;
    var rate = math.max(1, _document.frameRate);
    var offset = math.max(0, frame - e.clip.at) / rate;
    var part = e.instrument!;
    setInstrument(
        e,
        part.copyWith(
            notes: [
          ...part.notes,
          for (var n in read.notes) n.copyWith(start: n.start + offset),
        ]..sort((a, b) => a.start.compareTo(b.start))));
    return true;
  }

  /// midiClipFromFile fills slot [row] of MIDI channel [channel] with MIDI
  /// file [assetId]'s notes, in beats, as many whole bars long as they are.
  Future<bool> midiClipFromFile(String channel, int row, String assetId,
      {String name = ""}) async {
    var read = await CanvasController.midiOfAsset(assetId);
    if (read == null || _instrumentOf(channel) == null || _disposed) {
      return false;
    }
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var notes = [
      for (var n in read.notes)
        n.copyWith(start: n.start / spb, length: n.length / spb),
    ];
    var end = notes.isEmpty ? 0.0 : notes.map((n) => n.end).reduce(math.max);
    var index = timelineChannels.indexWhere((c) => c.key == channel);
    setSessionClip(
        channel,
        row,
        SessionClip(
          id: newElementId(),
          name: name.isEmpty ? "MIDI file" : name,
          color: math.max(0, index) % sectionColors.length,
          midi: true,
          notes: notes,
          bars: math
              .max(1, (end / _document.audio.beatsPerBar).ceil())
              .toDouble(),
        ));
    return true;
  }

  /// vocaliserOf is channel [channel]'s Vocaliser, or null for none.
  VocaliserSpec? vocaliserOf(String channel) => timelineChannels
      .where((c) => c.key == channel)
      .firstOrNull
      ?.mix
      .vocaliser;

  /// setVocaliser puts a Vocaliser on [channel], changes it, or with null
  /// takes it off.
  void setVocaliser(String channel, VocaliserSpec? spec,
      {bool transient = false}) {
    var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
    if (lane == null) return;
    setChannelMix(
        lane,
        spec == null
            ? lane.mix.copyWith(noVocaliser: true)
            : lane.mix.copyWith(vocaliser: spec),
        transient: transient);
  }

  /// midiChannels are the MIDI channels there are, by key and name: what
  /// a Vocaliser can sing the notes of.
  List<(String, String)> get midiChannels => [
        for (var c in timelineChannels)
          if (instrumentChannel(c.key)) (c.key, c.name),
      ];

  /// singsWhat is what [channel]'s Vocaliser sings, in a line -- the latest
  /// take on the timeline, else its sections' chosen takes, one after
  /// another -- or null, with nothing spoken yet.
  String? singsWhat(String channel) {
    var spec = speechOf(channel);
    if (spec == null) return null;
    if (spec.takes.lastOrNull case var t?) {
      return "Sings Take ${spec.takes.length}: ${t.words.length} words.";
    }
    var takes = [
      for (var l in spec.lines)
        if (l.take case var t?) t
    ];
    if (takes.isEmpty) return null;
    var words = takes.fold(0, (n, t) => n + t.words.length);
    return "Sings the sections' takes, ${takes.length} of them: "
        "$words words.";
  }

  /// _singSource is what [channel] sings: the latest take on the timeline,
  /// or its sections' chosen takes, shaped, a quarter of a second apart --
  /// its sound and its words. Null with nothing to sing, or unreadable.
  Future<(Float32List, List<TimedWord>)?> _singSource(String channel) async {
    var spec = speechOf(channel);
    if (spec == null) return null;
    if (spec.takes.lastOrNull case var t?) {
      var sound = await CanvasController.takeAudio(t.assetId);
      return sound == null ? null : (sound, t.words);
    }
    var sound = <double>[];
    var words = <TimedWord>[];
    for (var (i, l) in spec.lines.indexed) {
      if (l.take == null) continue;
      var t = await shapedTake(channel, i, l.chosen);
      if (t == null) continue;
      var part = await CanvasController.takeAudio(t.assetId);
      if (part == null) return null;
      if (sound.isNotEmpty) sound.addAll(Float32List((0.25 * mixRate).round()));
      var at = sound.length / mixRate;
      for (var w in t.words) {
        words.add((text: w.text, start: w.start + at, end: w.end + at));
      }
      sound.addAll(part);
    }
    return words.isEmpty ? null : (Float32List.fromList(sound), words);
  }

  /// sing sings [channel]'s Speech -- see singsWhat -- to its Vocaliser's
  /// melody -- a MIDI channel's notes -- into a new clip on the channel
  /// where the melody starts. One change to undo. Answers why not, where
  /// it could not.
  Future<String?> sing(String channel) async {
    var spec = vocaliserOf(channel);
    if (spec == null) return null;
    if (singsWhat(channel) == null) {
      return "Nothing to sing yet: speak a take with this channel's "
          "Speech device first.";
    }
    var melodyKey = spec.melody.isNotEmpty
        ? spec.melody
        : midiChannels.firstOrNull?.$1 ?? "";
    var tune = _instrumentOf(melodyKey);
    if (tune == null || tune.instrument!.notes.isEmpty) {
      return "Nothing to sing to: pick a MIDI channel with notes on it.";
    }
    if (!singing.add(channel)) return null;
    notifyListeners();
    try {
      var said = await _singSource(channel);
      if (said == null) return "The take's file could not be read.";
      var (source, words) = said;
      var rate = math.max(1, _document.frameRate);
      var partStart = tune.clip.at / rate;
      var melody = melodyOf(tune.instrument!.notes);
      var sung = assignSyllables(syllablesOf(words), melody);
      if (sung.isEmpty) return "The take has no words to sing.";
      var settings =
          SingSettings(vibrato: spec.vibrato, glideSeconds: spec.glide);
      var out = await _sungAway(source, sung, settings);
      if (_disposed) return null;
      var dir = await Directory.systemTemp.createTemp("canvas-sung");
      String? id;
      try {
        var file = File(path.join(dir.path, "sung.wav"));
        await file.writeAsBytes(wav16(out, out), flush: true);
        id = await CanvasController.speechStore(file.path);
      } finally {
        await dir.delete(recursive: true).catchError((_) => dir);
      }
      if (id == null || _disposed) return "The sung take could not be kept.";
      var lane = timelineChannels.where((c) => c.key == channel).firstOrNull;
      if (lane == null) return null;
      var count = _document.elements
              .whereType<AudioElement>()
              .where((e) =>
                  e.clip.playlist.any((s) => s.name.startsWith("Sung take")))
              .length +
          1;
      addElement(channelClip(
          _document, ((partStart + melody.first.start) * rate).round(),
          source: MediaSource(
              assetId: id,
              name: "Sung take $count",
              length: out.length / 48000),
          channel: channel,
          channelName: lane.name,
          mix: lane.mix));
      return null;
    } catch (e) {
      debugPrint("Unable to sing: $e");
      return "It could not be sung: $e";
    } finally {
      singing.remove(channel);
      if (!_disposed) notifyListeners();
    }
  }

  /// renderParts plays every instrument's part that needs it into its
  /// clip's file, now.
  Future<void> renderParts() async {
    _partTimer?.cancel();
    for (var e in [..._document.elements]) {
      if (e is! AudioElement) continue;
      // As its macros turn it: see macroedPart.
      var part = e.instrument == null
          ? null
          : macroedPart(CanvasController._channelOf(e), e.instrument!);
      var spb = _document.audio.secondsPerBeat;
      if (part == null || !part.needsPlayingAt(spb)) continue;
      var signature = part.signatureAt(spb);
      // Played on the piano of our own for want of the bank: again only
      // once the bank is here.
      var stood = "$signature~";
      var wantsBank = part.sound == InstrumentSound.bank;
      var bankHere = wantsBank && await CanvasController.bankReady();
      if (part.rendered == stood && !bankHere) continue;
      if (!_rendering.add(signature)) continue;
      try {
        var bank = bankHere ? await soundBankPath() : null;
        // Through its MIDI effects: what is played, not what is written.
        var wav = await CanvasController.partRenderer(part.played(spb),
            bankPath: bank);
        var id = await CanvasController.partStore(wav);
        if (id == null || _disposed) continue;
        // Written onto the element as it is now -- if it still sounds the
        // same: changed again meanwhile, that change plays next.
        var now = _document.elementById(e.id);
        if (now is! AudioElement ||
            now.instrument == null ||
            macroedPart(CanvasController._channelOf(now), now.instrument!)
                    .signatureAt(spb) !=
                signature) {
          continue;
        }
        var clip = now.clip.copyWith(timed: true, playlist: [
          MediaSource(
              assetId: id,
              name: "${part.name} part",
              length: part.played(spb).length),
        ]);
        // Not a change of its own to undo: the file follows the notes.
        apply(
            _document.withElement(now.copyWith(
                clip: clip,
                instrument: now.instrument!.copyWith(
                    rendered: wantsBank && !bankHere ? stood : signature))),
            transient: true);
      } catch (exception) {
        debugPrint("Unable to play the part: $exception");
      } finally {
        _rendering.remove(signature);
      }
    }
  }

  /// pressAudio is a press on one of [e]'s own controls. [volume] is where
  /// on the volume bar, for that one.
  void pressAudio(AudioElement e, AudioControl part, {double? volume}) {
    var current = _audioById(e.id) ?? e;
    switch (part) {
      case AudioControl.playPause:
        _heard();
        unawaited(audio.toggle(current));
      case AudioControl.mute:
        audio.toggleMute(current);
      case AudioControl.volume:
        if (volume == null) return;
        audio.setVolume(current, volume);
        // Turning it up is asking to hear it.
        if (volume > 0 && audio.view(current).muted) {
          audio.setMuted(current, false);
        }
    }
  }

  /// _mediaById is an Audio or Video element on the canvas showing or on the
  /// master: what a button's media action is aimed at.
  CanvasElement? _mediaById(String id) {
    for (var e in [
      ..._document.elements,
      ...?_document.masterScene?.elements,
      ..._document.drawnBackground.media,
    ]) {
      if (e.id == id && (e is AudioElement || e is VideoElement)) return e;
    }
    return null;
  }

  /// _audioById finds an audio element on the canvas showing or on the
  /// master: the two places a button on this page could mean.
  AudioElement? _audioById(String id) {
    for (var e in _document.elements) {
      if (e is AudioElement && e.id == id) return e;
    }
    for (var e in _document.masterScene?.elements ?? const <CanvasElement>[]) {
      if (e is AudioElement && e.id == id) return e;
    }
    return null;
  }

  /// _pageAudio is every sound that belongs to what is on screen: the canvas
  /// showing, and the master under it.
  Iterable<AudioElement> get _pageAudio sync* {
    for (var e in _document.elements) {
      if (e is AudioElement) yield e;
    }
    if (!_document.editingMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (e is AudioElement) yield e;
      }
    }
  }

  /// _audioFollowsPage stops whatever does not belong on the canvas now
  /// showing. [turned] is whether the page actually changed: a master sound
  /// set to stop at the join stops then, and not when an unrelated edit is
  /// made.
  void _audioFollowsPage({required bool turned}) {
    var a = _audio;
    if (a == null) return;
    bool media(CanvasElement e) => e is AudioElement || e is VideoElement;
    // On the master's timeline, a clip runs on the run's clock under every
    // scene, so a turn is nothing to it: stopped at the turn, the timeline
    // would start it again at once, heard as a restart.
    bool carries(CanvasElement e) => switch (e) {
          AudioElement e => e.clip.acrossPages || e.clip.timed,
          VideoElement e => e.clip.acrossPages || e.clip.timed,
          _ => false,
        };
    // The background's too: what is drawn is what plays. A master's shared
    // backdrop is the master's, and carries on across a turn on the same
    // terms as anything else on the master.
    var fromMaster = _document.editingMaster || _document.sharedBackdrop;
    var keep = <String>{
      for (var e in _document.elements)
        if (media(e)) e.id,
      for (var e in _document.masterScene?.elements ?? const <CanvasElement>[])
        if (media(e) && (!turned || carries(e))) e.id,
      for (var e in _document.drawnBackground.media)
        if (!turned || !fromMaster || carries(e)) e.id,
    };
    _video?.keepOnly(keep.contains);
    // A video's sound goes where its video goes -- see VideoRuntime.
    a.keepOnly((id) => keep.contains(VideoRuntime.videoOfSound(id) ?? id));
  }

  /// _timedOnScreen is every piece of media on the timeline that is on
  /// screen, and the frame of *its* timeline the playhead is at: the scene's,
  /// or for media on the master and its backdrop the whole run's.
  Iterable<(CanvasElement, int)> get _timedOnScreen sync* {
    bool timed(CanvasElement e) => switch (e) {
          VideoElement v => v.clip.timed && !v.isLink && !v.clip.isEmpty,
          // An instrument is on its channel before it has a note: a MIDI
          // channel waiting to be played into. So is an empty audio
          // channel, named and waiting for a sound -- see
          // addEmptyAudioChannel.
          AudioElement a => a.clip.timed &&
              (!a.clip.isEmpty ||
                  a.instrument != null ||
                  a.clip.channelName.isNotEmpty),
          _ => false,
        };
    var onMaster = _document.editingMaster;
    var run = onMaster
        ? _frame
        : _previewAt ?? _document.startOfScene(_document.at) + _frame;
    for (var e in _document.elements) {
      if (timed(e)) yield (e, onMaster ? run : _frame);
    }
    if (!onMaster) {
      for (var e
          in _document.masterScene?.elements ?? const <CanvasElement>[]) {
        if (timed(e)) yield (e, run);
      }
    }
    var fromMaster = onMaster || _document.sharedBackdrop;
    for (var e in _document.drawnBackground.media) {
      if (timed(e)) yield (e, fromMaster ? run : _frame);
    }
    // The transitions' own sounds, on the run's timeline like the master's.
    for (var e in _document.transitionSounds) {
      yield (e, run);
    }
  }

  /// timedLanes is the media on the timeline that is on screen, for the
  /// Channels strip: each clip, how far its timeline is ahead of the scene's
  /// (the start of this scene in the run, for media that follows the run),
  /// and whether it can be changed from here.
  List<TimedLane> get timedLanes {
    var document = _document;
    var here = {for (var e in document.elements) e.id};
    // The master's, from any scene: its channels are every scene's, so a
    // game's sounds on it can be changed while the game is played on another.
    // A change is written back to the master: see _replacedAnywhere.
    var master = {...?document.master?.elements.map((e) => e.id)};
    var backdrop = {for (var e in document.drawnBackground.media) e.id};
    var onMaster = document.editingMaster;
    var fromMaster = onMaster || document.sharedBackdrop;
    // Which canvas each clip is on, for the strip's label: the master, or the
    // scene being edited.
    int sceneOf(CanvasElement e) => onMaster ||
            (!here.contains(e.id) && !backdrop.contains(e.id)) ||
            (backdrop.contains(e.id) && fromMaster)
        ? -1
        : document.at;
    // While every scene plays, every clip on the timeline can be moved and
    // trimmed from it -- the master's included, wherever it is seen from.
    var lanes = [
      for (var (e, at) in _timedOnScreen)
        TimedLane(
          e,
          offset: at - _frame,
          // A transition's sound belongs to its transition, and is changed
          // there.
          editable: !e.id.startsWith(transitionSoundPrefix) &&
              (allChannels ||
                  here.contains(e.id) ||
                  master.contains(e.id) ||
                  backdrop.contains(e.id)),
          scene: sceneOf(e),
        ),
    ];
    // Every other scene's as well, where that has been asked for: each at its
    // place in the run, to be moved, trimmed and cut from here, held to its
    // own scene. Not played from here: a clip is played on its own scene.
    if (allChannels && document.hasScenes) {
      var base = onMaster ? 0 : document.startOfScene(document.at);
      for (var (i, scene) in document.allScenes.indexed) {
        if (!onMaster && i == document.at) continue;
        var offset = base - document.startOfScene(i);
        for (var e in scene.elements) {
          var clip = switch (e) {
            VideoElement v when !v.isLink => v.clip,
            AudioElement a => a.clip,
            _ => null,
          };
          if (clip == null || !clip.timed || clip.isEmpty) continue;
          lanes.add(TimedLane(e, offset: offset, scene: i));
        }
      }
    }
    return lanes;
  }

  /// allChannels is whether the timeline lists every scene's channels, or
  /// only the scene being edited and the master's. It is Play all scenes:
  /// watching the whole run is when every scene's sound is wanted in view.
  bool get allChannels => _playAll;

  /// timelineReach is how many frames the timeline shows: the scene's, or
  /// further where a clip on it runs on past the scene's end -- so the rest
  /// of a long video or song can be scrolled to, seen and trimmed. The frames
  /// past the scene are drawn as out of it; nothing plays there.
  int get timelineReach {
    var most = _document.frames;
    var rate = math.max(1, _document.frameRate);
    for (var lane in timedLanes) {
      var clip = lane.clip;
      if (clip.isEmpty || clip.runLength <= 0) continue;
      var end = clip.at - lane.offset + (clip.runLength * rate).ceil();
      if (end > most) most = end;
    }
    return most;
  }

  /// interactiveLanes are the sounds on the canvas that play when pressed:
  /// this canvas's, and the master's seen from it. Each is on a channel so
  /// every sound has the same strip and effects; the timeline shows the
  /// channel greyed, since there is nothing on it to place in time.
  List<TimedLane> get interactiveLanes {
    var document = _document;
    var here = {for (var e in document.elements) e.id};
    var onMaster = document.editingMaster;
    var pressed = <CanvasElement>[
      for (var e in _pageAudio)
        if (!e.clip.timed && !e.clip.isEmpty) e,
      // And a video's sound -- not a link's, which plays on its own site.
      for (var e in [
        ...document.elements,
        if (!onMaster) ...?document.masterScene?.elements,
      ])
        if (e is VideoElement && !e.isLink && !e.clip.timed && !e.clip.isEmpty)
          e,
    ];
    var master = {...?document.master?.elements.map((e) => e.id)};
    return [
      for (var e in pressed)
        TimedLane(e,
            editable: here.contains(e.id) || master.contains(e.id),
            scene: onMaster || !here.contains(e.id) ? -1 : document.at),
    ];
  }

  /// timelineChannels is the timeline's channels, each with the sounds on it,
  /// in the order they first appear. A channel is its sounds: one with none
  /// left is gone, and the empty lane under the last is where a new channel
  /// is started.
  List<TimelineChannel> get timelineChannels {
    // Asked for many times a frame -- by the timeline, the mixer, the
    // strips -- and the same until one of these changes.
    var key = (_document, _frame, _playAll, _previewAt, _channelOrder);
    if (_channels case (var k, var known)
        when CanvasController._sameChannelKey(k, key)) {
      return known;
    }
    var made = _makeTimelineChannels();
    _channels = (key, made);
    return made;
  }

  List<TimelineChannel> _makeTimelineChannels() {
    var by = <String, List<TimedLane>>{};
    for (var lane in [...timedLanes, ...interactiveLanes]) {
      (by[lane.channelKey] ??= []).add(lane);
    }
    var found = [
      for (var entry in by.entries) TimelineChannel(entry.key, entry.value),
    ];
    // By scene (S1, S2, S3, the master's last), and in the order each was
    // first met within a scene, so the list does not reshuffle at every turn
    // of the page.
    var met = {for (var (i, c) in found.indexed) c.key: i};
    // The sounds played by pressing them after all those on the timeline.
    int rank(TimelineChannel c) {
      var scene = c.first.scene;
      return (c.interactive ? 1 << 22 : 0) + (scene < 0 ? 1 << 20 : scene);
    }

    found.sort((a, b) {
      var by = rank(a).compareTo(rank(b));
      return by != 0 ? by : met[a.key]!.compareTo(met[b.key]!);
    });
    if (_channelOrder.isEmpty) return found;
    // Then as they have been dragged into: the channels that have been
    // placed take the places such channels have in that order, among
    // themselves, and a channel never placed keeps its own.
    var placed = {for (var (i, k) in _channelOrder.indexed) k: i};
    var moved = [
      for (var c in found)
        if (placed.containsKey(c.key)) c
    ]..sort((a, b) => placed[a.key]!.compareTo(placed[b.key]!));
    var next = 0;
    return [
      for (var c in found) placed.containsKey(c.key) ? moved[next++] : c,
    ];
  }

  /// moveChannel puts the channel [key] at [to] in the list -- the strip
  /// dragged up or down.
  void moveChannel(String key, int to) {
    var keys = [for (var c in timelineChannels) c.key];
    var from = keys.indexOf(key);
    if (from < 0) return;
    keys.removeAt(from);
    keys.insert(to.clamp(0, keys.length).toInt(), key);
    // The ones not in view now -- another scene's, with every scene off --
    // keep the places they were given.
    _channelOrder = [
      ...keys,
      for (var k in _channelOrder)
        if (!keys.contains(k)) k,
    ];
    notifyListeners();
  }

  /// channelLevels is how loud [channel] is now: what comes out of its
  /// strip, which every sound on it plays through.
  (double, double) channelLevels(TimelineChannel channel) =>
      levels(channel.key);

  /// _setClips writes several clips at once, as one change: every sound on a
  /// channel when its strip is changed, say. Media on the backdrop has a lane
  /// of its own and is written through the backdrop.
  void _setClips(List<(CanvasElement, MediaClip)> changes,
      {bool transient = false}) {
    var next = _document;
    for (var (e, clip) in changes) {
      var changed = switch (e) {
        VideoElement v => v.copyWith(clip: clip),
        AudioElement a => a.copyWith(clip: clip),
        _ => null,
      };
      if (changed == null) continue;
      var anywhere = _replacedAnywhere(next, changed);
      if (anywhere != null) {
        next = anywhere;
      } else if (changes.length == 1) {
        setTimedClip(e, clip, transient: transient);
        return;
      }
    }
    apply(next, transient: transient);
  }
}
