part of '../canvas_controller.dart';

// A canvas played as a game, and practising.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasGame on CanvasController {
  /// gameTabOpen is whether the Game tab is showing: the stage draws what a
  /// game touches while it is -- see gameTouchArea.
  bool get gameTabOpen => _gameTabOpen;

  set gameTabOpen(bool on) {
    if (on == _gameTabOpen) return;
    _gameTabOpen = on;
    notifyListeners();
  }

  /// gaming is whether the canvas is being played as a game: what is set to
  /// be played answers the keys and the controllers, and the view follows
  /// the player. See canvas_game.dart.
  bool get gaming => _game != null;

  /// game is the game going, or null.
  GameRun? get game => _game;

  /// gameView is the canvas as the game has it now, for the stage to draw
  /// -- or null, not playing.
  CanvasDocument? get gameView => _gameView;

  /// makingGame is whether the canvas is being made into a game -- see
  /// CanvasDocument.game. Stopped being one, it stops being played.
  set makingGame(bool on) {
    if (on == _document.game) return;
    if (!on) gaming = false;
    apply(_document.copyWith(game: on));
  }

  set gaming(bool on) {
    if (on == gaming) return;
    if (on) {
      // On the scene it starts on -- a title screen, a menu -- and back to
      // the one being worked on after.
      _sceneBeforeGame = _document.at;
      var start = _document.gameStart.isEmpty
          ? -1
          : _document.sceneIndexNamed(_document.gameStart);
      if (start >= 0 && start != _document.at) goToScene(start);
      // From its beginning -- a title, a wait for Space -- not wherever the
      // playhead was left while it was being made.
      frame = 0;
      var run = GameRun();
      _game = run;
      _gameClockWatch
        ..reset()
        ..start();
      unawaited(run.listen());
      HardwareKeyboard.instance.addHandler(_gameKey);
      _gameWatch
        ..reset()
        ..start();
      _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        var dt = _gameWatch.elapsedMicroseconds / 1e6;
        _gameWatch
          ..reset()
          ..start();
        stepGame(math.min(dt, 0.05));
      });
      if (!playing) play();
      // And the sounds the scene it starts on asks for -- after Play, which
      // stops slots playing on their own.
      _gameSceneSounds();
      _gameMotionStart();
    } else {
      // The game's slots stop with it, at once rather than on the next bar,
      // while it is still a game on its own clock.
      _haltClips();
      // Its elements' slots too: back on their timelines.
      motionPlayer.clear();
      for (var id in _gameSounded) {
        audio.stop(id);
      }
      _gameSounded.clear();
      _gameClockWatch.stop();
      // Held by a pause, let go: the engine is everyone's.
      if (_gamePaused) {
        if (audio.engine case DartAudioEngine e) e.held = false;
      }
      HardwareKeyboard.instance.removeHandler(_gameKey);
      _gameTimer?.cancel();
      _gameTimer = null;
      _game?.dispose();
      _game = null;
      _gameView = null;
      _gamePaused = false;
      if (playing) pause();
      if (_sceneBeforeGame case var at? when at != _document.at) {
        goToScene(at);
      }
      _sceneBeforeGame = null;
    }
    notifyListeners();
  }

  /// gamePaused is whether a game being played is held: the bodies still,
  /// the timeline stopped, until it is let go again.
  bool get gamePaused => _gamePaused;

  set gamePaused(bool on) {
    if (!gaming || on == _gamePaused) return;
    _gamePaused = on;
    // Its sound held with it -- every voice where it is -- and its slots'
    // clock, so they go on from there.
    if (audio.engine case DartAudioEngine e) e.held = on;
    if (on) {
      _gameClockWatch.stop();
      if (playing) pause();
    } else {
      _gameClockWatch.start();
      // From now, not from when it was held: no leap forward on letting go.
      _gameWatch
        ..reset()
        ..start();
      play();
    }
    notifyListeners();
  }

  /// stepGame moves the game on by [dt] seconds.
  void stepGame(double dt) {
    var run = _game;
    if (run == null) return;
    // Its slots, on its own clock -- held or not, stopped on its timeline
    // or not.
    if (_clipChannels.isNotEmpty) {
      _sessionStep(_sessionNow);
      _applyMix();
    }
    if (_gamePaused) return;
    // The elements' slots on the game's clock, before the bodies move
    // against where they have got to.
    if (motionPlayer.offTimeline) _motionStep();
    run.step(_document, _frame, dt, live: liveMotion);
    // What the game asked for: a sound, another scene, the end.
    var asked = [...run.events];
    run.events.clear();
    for (var event in asked) {
      if (event.sound case var ref?) gameSound(ref, from: event.soundFrom);
      // Another scene: a chosen one, the next -- the game over after the
      // last -- or, started again, the game's first.
      if (event.scene case var id?) _gameScene(run, id);
      if (event.next) {
        var next = _document.at + 1;
        if (next >= _document.allScenes.length) {
          gaming = false;
          return;
        }
        goToScene(next);
        frame = 0;
        run.newScene();
        _gameSceneSounds();
        _gameMotionStart();
      }
      if (event.restart && _document.gameStart.isNotEmpty) {
        _gameScene(run, _document.gameStart);
      }
      if (event.press case var id?) {
        _gamePress(run, id);
        // Pressed in a game is clicked: its clips that start on that.
        fireMotionTrigger(ClipTriggerKind.clicked, id);
      }
      if (event.touched case var id?) {
        fireMotionTrigger(ClipTriggerKind.touched, id);
      }
      if (event.counted case (var id, var value)) {
        fireMotionTrigger(ClipTriggerKind.count, id, value.toDouble());
      }
      if (event.stop) {
        gaming = false;
        return;
      }
    }
    _gameView =
        spoken(run.view(_document, frame: _frame, playing: _touchClipPlaying));
    // A step of the game is not a change to the canvas: see _notifyPlayhead.
    _notifyView();
  }

  /// waitingFor is the action a stop is waiting for, by id, or null.
  String? get waitingFor => _waitingFor;

  /// _waitForAction holds a stop until [id] is pressed -- on the keyboard
  /// or a controller -- and then plays on. Play pressed meanwhile ends the
  /// wait too.
  void _waitForAction(String id) {
    _endWait();
    _waitingFor = id;
    HardwareKeyboard.instance.addHandler(_waitKey);
    var input = GameInput();
    try {
      _waitPads = Gamepads.normalizedEvents.listen((e) {
        input.gamepad(e);
        var action = _waitedAction;
        if (action != null && action.pad.any(input.pad.contains)) {
          _goOnFromWait();
        }
      });
    } catch (exception) {
      debugPrint("Controllers are not available: $exception");
    }
  }

  ControlAction? get _waitedAction =>
      _document.controlsNow.where((a) => a.id == _waitingFor).firstOrNull;

  bool _waitKey(KeyEvent event) => waitKey(event);

  /// waitKey is a key while a stop waits: the waited action's, pressed,
  /// plays on.
  @visibleForTesting
  bool waitKey(KeyEvent event) {
    var action = _waitedAction;
    if (action == null || event is! KeyDownEvent) return false;
    if (!action.keys.contains(event.logicalKey.keyId)) return false;
    _goOnFromWait();
    return true;
  }

  void _goOnFromWait() {
    _endWait();
    play();
  }

  void _endWait() {
    if (_waitingFor == null) return;
    _waitingFor = null;
    HardwareKeyboard.instance.removeHandler(_waitKey);
    unawaited(_waitPads?.cancel());
    _waitPads = null;
  }

  /// _gameScene goes to the scene [id] -- by id or name -- for the game:
  /// its players where they were put, the counts carried on.
  void _gameScene(GameRun run, String id) {
    var to = _document.sceneIndexNamed(id);
    if (to < 0) return;
    goToScene(to);
    // From its beginning, not the frame it was left on while it was made.
    frame = 0;
    run.newScene();
    _gameSceneSounds();
    _gameMotionStart();
  }

  /// _touchClipPlaying is whether [id] is playing a clip a touch started --
  /// a coin's pop -- for which a pickup taken stays in view.
  bool _touchClipPlaying(String id) {
    var e = _document.elementById(id);
    if (e == null) return false;
    var onTouch = {
      for (var c in e.base.motion.clips)
        if (c.triggers.any((t) => t.kind == ClipTriggerKind.touched)) c.id,
    };
    return onTouch.isNotEmpty && motionPlayer.isPlaying(id, only: onTouch);
  }

  /// _gameMotionStart is a scene beginning in a game: its elements' slots
  /// cleared, and the clips that start with the scene started.
  void _gameMotionStart() {
    motionPlayer.clear();
    fireMotionTrigger(ClipTriggerKind.sceneStarts);
  }

  /// gameSound plays what a game asks for by [ref] -- see gameSoundOf: a
  /// sound on the canvas, from its start; a mixer slot, at once unless its
  /// own Launch waits for a beat or a bar; or a channel's slots stopped, at
  /// once.
  ///
  /// [from], given, is where across the page the sound is set off -- an
  /// instance of an element reused, touched -- for a sound placed on the
  /// canvas to be heard from there.
  void gameSound(String ref, {double? from}) {
    switch (gameSoundOf(ref)) {
      case GameSoundElement(:var id):
        if (_audioById(id) case var sound?) {
          var channel = CanvasController._channelOf(sound);
          if (from != null && sound.clip.place.by == PlaceBy.canvas) {
            _soundFrom[channel] =
                heardAcross(_document, from, sound.clip.place);
          } else {
            _soundFrom.remove(channel);
          }
          audio.stop(id);
          _gameSounded.add(id);
          unawaited(audio.play(sound));
        }
      case GameSoundSlot(:var clip):
        if (session.find(clip) case (var channel, var row)) {
          var c = session.at(channel, row)!;
          launchClip(channel, row, quantise: c.quantise ?? Quantise.off);
        }
      case GameSoundStop(:var channel):
        stopChannelClips(channel, now: true);
      case null:
        break;
    }
  }

  /// spoken is [doc] with each character that speaks for a channel -- see
  /// CharacterPerformance.speaksFor -- speaking while a slot is heard on
  /// it: its mouth the take's at the moment it has got to, and shown. [doc]
  /// itself where nobody is speaking.
  CanvasDocument spoken(CanvasDocument doc) {
    if (_clipChannels.isEmpty) return doc;
    var changed = false;
    List<CanvasElement> speaking(List<CanvasElement> elements) => [
          for (var e in elements)
            if (e is Character3dElement && e.performance.speaksFor.isNotEmpty)
              (_speaking3dAs(e) ?? e)
            else
              e,
        ];
    var elements = speaking(doc.elements);
    for (var (i, e) in elements.indexed) {
      if (!identical(e, doc.elements[i])) changed = true;
    }
    var out = changed ? doc.copyWith(elements: elements) : doc;
    if (doc.masterScene case var m? when !doc.editingMaster) {
      var mine = speaking(m.elements);
      var any = false;
      for (var (i, e) in mine.indexed) {
        if (!identical(e, m.elements[i])) any = true;
      }
      if (any) out = out.withMaster(m.copyWith(elements: mine));
    }
    return out;
  }

  /// _speaking3dAs is 3D character [e] saying what its channel's slot says
  /// now, and shown while it does -- or null where nothing is heard on it.
  Character3dElement? _speaking3dAs(Character3dElement e) {
    var mouth = _heardMouth(e.performance.speaksFor);
    if (mouth == null) return null;
    // Held from long before whatever frame of its scene is drawn: it is
    // the mouth now, wherever its scene has got to.
    var spoke =
        e.performing(e.performance.copyWith(mouths: [(t: -1e6, shape: mouth)]));
    return e.visible
        ? spoke
        : spoke.withBase(visible: true) as Character3dElement;
  }

  /// _heardMouth is the mouth channel [key]'s slot says now, or null where
  /// nothing is heard on it.
  MouthShape? _heardMouth(String key) {
    var ch = _clipChannels[key];
    var play = ch?.now;
    if (ch == null || play == null || play.sound == null) return null;
    var now = _sessionNow;
    var t = now - play.origin;
    if (now < play.from || (!play.loops && t >= play.length)) return null;
    if (ch.stopAt case var stop? when now >= stop) return null;
    var rate = math.max(1, _document.frameRate);
    var sound = play.sound!;
    var heard = ((sound.start + play.into(t)) * rate).floor();
    var mouth = MouthShape.rest;
    for (var k in _slotMouths(play.clipId, sound, rate) ?? const <MouthKey>[]) {
      if (k.frame > heard) break;
      mouth = k.shape;
    }
    return mouth;
  }

  /// _slotMouths are the mouths of the slot [clipId] playing [sound], by
  /// its file's frames: from its words, where it is a Speech device's take
  /// -- found on any channel -- or from its loudness, read once in the
  /// background (null until it has been).
  List<MouthKey>? _slotMouths(String clipId, MediaSource sound, int rate) {
    var key = "$clipId:${sound.assetId}:$rate";
    if (_mouthsOfSlots.containsKey(key)) return _mouthsOfSlots[key];
    SpeechTake? take;
    for (var e in [
      ..._document.elements,
      for (var sc in _document.allScenes) ...sc.elements,
      ...?_document.master?.elements,
    ]) {
      if (e is! AudioElement) continue;
      var speech = e.clip.mix.speech;
      for (var t in [
        ...?speech?.takes,
        for (var l in speech?.lines ?? const <SpeechLine>[]) ...l.takes,
      ]) {
        if (t.assetId == sound.assetId && t.words.isNotEmpty) take = t;
      }
    }
    if (take != null) {
      var words = [
        for (var w in take.words)
          SpokenWord(
              text: w.text,
              frame: (w.start * rate).round(),
              end: (w.end * rate).round(),
              from: "slot:$clipId"),
      ];
      return _mouthsOfSlots[key] = mouthsFromWords(words, frameRate: rate);
    }
    _mouthsOfSlots[key] = null;
    unawaited(() async {
      var length = sound.length;
      if (length <= 0) return;
      var file = await CanvasMedia.existingPath(MediaKind.audio, sound.assetId);
      if (file == null || _disposed) return;
      var count = math.max(1, (length * 100).ceil());
      var peaks = await audio.engine.peaks(file, count);
      if (peaks == null || _disposed) return;
      _mouthsOfSlots[key] = mouthsFromLoudness(peaks, length,
          startFrame: 0, frameRate: rate, feel: const LipSyncFeel());
      notifyListeners();
    }());
    return null;
  }

  /// _gameSceneSounds is what each channel does as a game comes to the
  /// scene showing: see CanvasScene.gameSounds.
  void _gameSceneSounds() {
    for (var MapEntry(key: channel, value: does)
        in _document.scene.gameSounds.entries) {
      gameSound(does == "stop" ? gameSoundStop(channel) : does);
    }
  }

  /// _gamePress is [id] pressed by an action while the game plays: what a
  /// click on it would do -- a Button's own action, else the press it was
  /// given. Shown or hidden is the game's, not the document's: stopped, the
  /// gate is where it was put. A link is not followed mid-game.
  void _gamePress(GameRun run, String id) {
    var e = _document.elementById(id);
    if (e == null) return;
    if (e.base.play.pressSound case var ref when ref.isNotEmpty) {
      gameSound(ref);
    }
    var action = e is ButtonElement ? e.action : e.base.play.press;
    switch (action.kind) {
      case ButtonActionKind.toggleElement:
        if (action.elementId.isNotEmpty) run.toggle(action.elementId);
      case ButtonActionKind.goToScene:
        _gameScene(run, action.elementId);
      case ButtonActionKind.openLink:
        break;
      default:
        runButtonAction(action);
    }
  }

  /// _gameKey is [gameKey], as a key handler.
  bool _gameKey(KeyEvent event) => gameKey(event);

  /// gameKey is a key while playing: held, let go, and taken where it
  /// presses one of the actions, so Space jumps rather than pausing.
  /// Escape stops the game.
  @visibleForTesting
  bool gameKey(KeyEvent event) {
    var run = _game;
    if (run == null) return false;
    var id = event.logicalKey.keyId;
    if (escStopsGame &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      gaming = false;
      return true;
    }
    var bound = _document.players
        .any((p) => _document.controlsFor(p).any((a) => a.keys.contains(id)));
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      run.input.keys.add(id);
      // The clips that start on this key.
      if (event is KeyDownEvent) {
        fireMotionTrigger(ClipTriggerKind.key, motionKeyName(event.logicalKey));
      }
    } else if (event is KeyUpEvent) {
      run.input.keys.remove(id);
    }
    return bound;
  }

  /// practising is the Sheet music being practised, or null.
  String? get practising => _practice;

  double get _clockRate {
    var sheet = _practice == null ? null : _document.elementById(_practice!);
    return sheet is SheetElement ? sheet.tempo : 1;
  }

  /// _practised is the sheet being practised, the instrument it follows,
  /// and its part -- or null where one of them has gone.
  (SheetElement, AudioElement, InstrumentPart)? get _practised {
    var sheet = _practice == null ? null : _document.elementById(_practice!);
    if (sheet is! SheetElement) return null;
    var inst = _document.elementById(sheet.follows);
    if (inst is! AudioElement || inst.instrument == null) return null;
    return (sheet, inst, inst.instrument!);
  }

  int _noteFrame(AudioElement inst, MidiNote n) =>
      inst.clip.at + (n.start * math.max(1, _document.frameRate)).round();

  int _noteEndFrame(AudioElement inst, MidiNote n) =>
      inst.clip.at + (n.end * math.max(1, _document.frameRate)).round();

  /// importScore puts MusicXML [score] into the part of the instrument
  /// [sheet] shows, in place of its notes -- laid on this canvas's tempo,
  /// so its bars are this canvas's bars -- and writes [sheet] in its key.
  /// One change to undo. Answers why not.
  String? importScore(SheetElement sheet, MusicXmlScore score) {
    var e = _document.elementById(sheet.follows);
    if (e is! AudioElement || e.instrument == null) {
      return "Choose the instrument it shows first.";
    }
    var notes = score.played(_document.audio.tempo);
    var next = _document
        .withElement(
            e.copyWith(instrument: e.instrument!.copyWith(notes: notes)))
        .withElement(sheet.copyWith(
            key: score.fifths,
            title: sheet.title.isEmpty ? score.title : null));
    apply(next);
    return null;
  }

  /// exportScore is the part [sheet] shows, as MusicXML -- written as it is
  /// engraved -- or null where it shows none.
  String? exportScore(SheetElement sheet) {
    var e = _document.elementById(sheet.follows);
    if (e is! AudioElement || e.instrument == null) return null;
    var audio = _document.audio;
    return scoreToMusicXml(sheetScore(e.instrument!, audio, fifths: sheet.key),
        title: sheet.title, tempo: audio.tempo);
  }

  /// startPractice starts a take on [sheet]: the marks cleared, playing
  /// from the playhead.
  void startPractice(SheetElement sheet) {
    if (playing) pause();
    _marks.clear();
    _wrongKeys.clear();
    _waiting.clear();
    _found.clear();
    _practice = sheet.id;
    sheetMarksOf = _sheetMarks;
    play();
    notifyListeners();
  }

  /// stopPractice ends the take, its marks left to look at.
  void stopPractice() => pause();

  void _endPractice() {
    var p = _practised;
    if (p != null) {
      for (var k in _accompanying) {
        audio.noteOff(CanvasController._channelOf(p.$2), k);
      }
    }
    _accompanying.clear();
    _waiting.clear();
    _practice = null;
    // The take's marks stay on the score until the next.
  }

  SheetMarks _sheetMarks(SheetElement e) => SheetMarks(
      marks: Map.of(_marks),
      waiting: _practice == e.id ? Set.of(_waiting) : const {},
      wrongKeys: Map.of(_wrongKeys));

  /// practiceScore is the take so far: how many right, how many wrong.
  (int, int) get practiceScore => (
        _marks.values.where((m) => m == NoteMark.right).length,
        _marks.values.where((m) => m == NoteMark.wrong).length
      );

  /// _practiceHolds is whether the playhead holds before [next], waiting
  /// to be played -- Wait for me, a note of the player's there unplayed.
  bool _practiceHolds(int next) {
    var p = _practised;
    if (p == null) return false;
    var (sheet, inst, part) = p;
    if (sheet.mode != PracticeMode.wait) return false;
    if (_waiting.isNotEmpty) return true;
    for (var (i, n) in part.notes.indexed) {
      if (!CanvasController._mine(sheet, n) || _found.contains(i)) continue;
      // Due on the frame it is on, or the one it is going to.
      var f = _noteFrame(inst, n);
      if (f >= _frame && f <= next) _waiting.add(i);
    }
    return _waiting.isNotEmpty;
  }

  /// _practiceStep is the playhead gone from [was] to [now]: the other
  /// hand's notes started and stopped, and -- playing along -- the notes
  /// gone by unplayed marked missed.
  void _practiceStep(int was, int now) {
    var p = _practised;
    if (p == null) return;
    var (sheet, inst, part) = p;
    var channel = CanvasController._channelOf(inst);
    if (now < was) {
      // Round a loop: everything let go, and the take begun again -- the
      // notes from where it starts again marked afresh, each time round.
      for (var k in _accompanying) {
        audio.noteOff(channel, k);
      }
      _accompanying.clear();
      _waiting.clear();
      for (var (i, n) in part.notes.indexed) {
        if (_noteFrame(inst, n) >= now) {
          _marks.remove(i);
          _wrongKeys.remove(i);
          _found.remove(i);
        }
      }
    }
    var rate = math.max(1, _document.frameRate);
    for (var (i, n) in part.notes.indexed) {
      var start = _noteFrame(inst, n), end = _noteEndFrame(inst, n);
      if (!CanvasController._mine(sheet, n)) {
        // Each stretch from where it was up to where it is, so a note on
        // the very first frame is played, and none twice.
        if (start >= was && start < now) {
          unawaited(audio.noteOn(
              channel, macroedPart(channel, part), n.key, n.velocity));
          _accompanying.add(n.key);
        }
        if (end >= was && end < now && _accompanying.remove(n.key)) {
          audio.noteOff(channel, n.key);
        }
        continue;
      }
      if (sheet.mode == PracticeMode.along &&
          !_marks.containsKey(i) &&
          now - start > 0.25 * rate &&
          was - start <= 0.25 * rate) {
        _marks[i] = NoteMark.missed;
      }
    }
  }

  /// _practiceHeard is [key] played on [inst]: right, if it is a note of
  /// the player's due now; wrong, if one is due and this is not it.
  void _practiceHeard(AudioElement inst, int key) {
    var p = _practised;
    if (p == null || p.$2.id != inst.id) return;
    var (sheet, followed, part) = p;
    if (sheet.mode == PracticeMode.listen) return;
    if (sheet.mode == PracticeMode.wait) {
      if (_waiting.isEmpty) return;
      var hit = _waiting.where((i) => part.notes[i].key == key).firstOrNull;
      if (hit != null) {
        // Found: it goes on. Right only where it was right the first time:
        // a wrong key before it stays marked, so the score says how the take
        // really went.
        _waiting.remove(hit);
        _found.add(hit);
        _marks.putIfAbsent(hit, () => NoteMark.right);
      } else {
        var first = _waiting.first;
        _marks.putIfAbsent(first, () => NoteMark.wrong);
        _wrongKeys[first] = key;
      }
      return;
    }
    // Playing along: the nearest of the player's notes due within a quarter
    // of a second either way.
    var rate = math.max(1, _document.frameRate);
    var now = _frame + betweenFrames;
    int? due;
    var best = double.infinity;
    for (var (i, n) in part.notes.indexed) {
      if (!CanvasController._mine(sheet, n) || _marks.containsKey(i)) continue;
      var d = (_noteFrame(followed, n) - now).abs() / rate;
      if (d > 0.25) continue;
      if (n.key == key) {
        _marks[i] = NoteMark.right;
        return;
      }
      if (d < best) {
        best = d;
        due = i;
      }
    }
    if (due != null) {
      _marks[due] = NoteMark.wrong;
      _wrongKeys[due] = key;
    }
  }

  /// addMidiChannel adds a MIDI channel: an instrument on a channel of its
  /// own, to be played into live from a MIDI keyboard, with Record. On a
  /// piece of sound with no canvas it lives on the timeline alone; on a
  /// canvas, its keyboard is on the canvas too. Picked, so a MIDI keyboard
  /// plays it and its settings are open. [onCanvas] false keeps its keyboard
  /// off the page whatever the canvas.
  AudioElement addMidiChannel({bool onCanvas = true}) {
    var e = newInstrument(_document);
    // Named for what it plays, numbered where that is taken: Piano, Piano 2.
    var taken = {for (var c in timelineChannels) c.name};
    var name = e.name;
    for (var n = 2; taken.contains(name); n++) {
      name = "${e.name} $n";
    }
    e = e.rebase(e.base.copyWith(
        name: name,
        visible: onCanvas &&
            (_document.hasCanvas || !_document.kind.isAudio))) as AudioElement;
    addElement(e);
    return e;
  }

  /// addEmptyAudioChannel adds an audio channel with nothing on it yet: a
  /// named lane for sounds to be dropped onto, and a strip in the mixer --
  /// its clip slots, its effects -- ready before there is a sound.
  AudioElement addEmptyAudioChannel() {
    var taken = {for (var c in timelineChannels) c.name};
    var name = "Audio";
    for (var n = 2; taken.contains(name); n++) {
      name = "Audio $n";
    }
    var e = AudioElement(
      ElementBase(id: newElementId(), name: name, visible: false),
      clip: MediaClip(timed: true, channelName: name),
      controls: const [],
    );
    addElement(e);
    return e;
  }

  /// setInstrument changes [e]'s part.
  void setInstrument(AudioElement e, InstrumentPart part,
      {bool transient = false}) {
    var current = _document.elementById(e.id);
    if (current is! AudioElement) return;
    replaceElement(current.copyWith(instrument: part), transient: transient);
  }

  /// _scheduleParts plays, a moment after the last change, any instrument
  /// whose sound file is not its part any more.
  void _scheduleParts() {
    var waiting = _document.elements.any((e) =>
        e is AudioElement &&
        e.instrument != null &&
        macroedPart(CanvasController._channelOf(e), e.instrument!)
            .needsPlayingAt(_document.audio.secondsPerBeat));
    if (!waiting) return;
    _partTimer?.cancel();
    _partTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(renderParts());
    });
  }
}
