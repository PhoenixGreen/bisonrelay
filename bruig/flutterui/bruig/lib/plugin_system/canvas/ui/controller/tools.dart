part of '../canvas_controller.dart';

// Colour replacement, reuse, sound tools, the clip editor, warping and the piano roll.
// Part of CanvasController: the state is the class's, in
// canvas_controller.dart; these are its methods.

extension CanvasTools on CanvasController {
  /// replaceColour makes every use of [from] on the document -- in any
  /// scene, the master, the backgrounds, charts, text and transitions -- [to],
  /// as one change. Opacity is kept: a half-strength shade of [from] becomes
  /// a half-strength shade of [to].
  void replaceColour(Color from, Color to) {
    var next =
        CanvasDocument.fromJson(recoloured(_document.toJson(), from, to));
    apply(next);
  }

  /// textStyles are the document's named text styles.
  List<NamedTextStyle> get textStyles => _document.textStyles;

  /// saveTextStyle makes [e]'s type a named style -- the next "Style N" if
  /// no name is given -- and sets [e] in it.
  String saveTextStyle(TextElement e, {String name = ""}) {
    var taken = {for (var t in textStyles) t.name};
    if (name.isEmpty || taken.contains(name)) {
      for (var n = textStyles.length + 1;; n++) {
        if (!taken.contains("Style $n")) {
          name = "Style $n";
          break;
        }
      }
    }
    var next = _document.copyWith(
        textStyles: [...textStyles, NamedTextStyle(name, e.textSpec)]);
    apply(_replacedAnywhere(next, e.copyWith(style: name)) ?? next);
    return name;
  }

  /// useTextStyle sets text [id] in style [name], or lets it keep its own
  /// type with an empty name.
  void useTextStyle(String id, String name) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! TextElement) return e;
      return style == null
          ? e.copyWith(style: "")
          : e.copyWith(style: name, textSpec: style.spec);
    }));
  }

  /// updateTextStyle makes style [name] [spec], and restyles every text set
  /// in it, in every scene and on the master, as one change.
  void updateTextStyle(String name, TextSpec spec) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == name ? NamedTextStyle(name, spec) : t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberSpec: e.numberStyle == name ? spec : null,
            affixSpec: e.wordStyle == name ? spec : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return e.copyWith(textSpec: spec);
    }));
  }

  /// useCounterStyle sets counter [id]'s number -- or its [words] -- in
  /// style [name], or lets it keep its own type with an empty name.
  void useCounterStyle(String id, String name, {bool words = false}) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! CounterElement) return e;
      var link = style == null ? "" : name;
      return words
          ? e.copyWith(wordStyle: link, affixSpec: style?.spec)
          : e.copyWith(numberStyle: link, numberSpec: style?.spec);
    }));
  }

  /// saveCounterStyle makes counter [e]'s number type -- or its [words]'
  /// -- a named style, the next "Style N", and sets it in it.
  String saveCounterStyle(CounterElement e, {bool words = false}) {
    var taken = {for (var t in textStyles) t.name};
    var name = "";
    for (var n = textStyles.length + 1;; n++) {
      if (!taken.contains("Style $n")) {
        name = "Style $n";
        break;
      }
    }
    var spec = words ? e.affixSpec : e.numberSpec;
    var next = _document
        .copyWith(textStyles: [...textStyles, NamedTextStyle(name, spec)]);
    var linked =
        words ? e.copyWith(wordStyle: name) : e.copyWith(numberStyle: name);
    apply(_replacedAnywhere(next, linked) ?? next);
    return name;
  }

  /// renameTextStyle renames a style, and every text set in it with it.
  void renameTextStyle(String from, String to, {bool transient = false}) {
    if (to.isEmpty || textStyles.any((t) => t.name == to)) return;
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == from ? NamedTextStyle(to, t.spec) : t,
    ]);
    apply(
        _everyElement(next, (e, _) {
          if (e is CounterElement) {
            return e.copyWith(
                numberStyle: e.numberStyle == from ? to : null,
                wordStyle: e.wordStyle == from ? to : null);
          }
          if (e is! TextElement || e.style != from) return e;
          return e.copyWith(style: to);
        }),
        transient: transient);
  }

  /// removeTextStyle forgets style [name]; the texts set in it keep their
  /// type as their own.
  void removeTextStyle(String name) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles)
        if (t.name != name) t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberStyle: e.numberStyle == name ? "" : null,
            wordStyle: e.wordStyle == name ? "" : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return e.copyWith(style: "");
    }));
  }

  /// staggerArrivals has the elements [ids] come in one after another, [gap]
  /// frames apart, in order across the canvas -- left to right, or top to
  /// bottom where [downwards]. The first keeps its timing; each later one's
  /// keyframes move so its arrival starts [gap] after the one before's.
  void staggerArrivals(List<String> ids, int gap, {bool downwards = false}) {
    var rate = math.max(1, _document.frameRate);
    // Its arrival's start; or, with none, its first keyframe or clip.
    int? arrivalOf(CanvasElement e) {
      if (ownSpan(e, MotionKind.arrive, rate) case (var at, _)) return at;
      var keys = e.base.track?.keys ?? const <Keyframe>[];
      if (keys.isNotEmpty) return keys.first.frame;
      var placed = e.base.motion.placed;
      if (placed.isEmpty) return null;
      return (placed.map((p) => p.start).reduce(math.min) * rate).round();
    }

    var picked = [
      for (var id in ids)
        if (_document.elementById(id) case var e? when arrivalOf(e) != null) e,
    ];
    if (picked.length < 2) return;
    picked.sort((a, b) => downwards
        ? a.base.y.compareTo(b.base.y)
        : a.base.x.compareTo(b.base.x));

    var first = arrivalOf(picked.first)!;
    var next = _document;
    for (var (i, e) in picked.indexed) {
      var by = first + i * gap - arrivalOf(e)!;
      if (by == 0) continue;
      // Keyframes and clips alike: whatever it does moves with it.
      var track = e.base.track;
      next = next.withElement(e.withBase(
          track: track == null || track.isEmpty ? track : _shifted(track, by),
          motion: e.base.motion.shiftedBy(by / rate)));
    }
    apply(next);
  }

  /// _runStartOf is the frame of the run element [id]'s own frames count
  /// from: its scene's start, or nought on the master.
  int _runStartOf(String id) {
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == id)) {
        return _document.hasScenes ? _document.startOfScene(i) : 0;
      }
    }
    return 0;
  }

  /// newChannelName is "Channel" and the next number not already taken. A
  /// channel holds sound, and a video's soundtrack beside it, so it is not
  /// "Audio".
  String newChannelName() {
    var taken = {for (var c in timelineChannels) c.name};
    for (var n = 1;; n++) {
      if (!taken.contains("Channel $n")) return "Channel $n";
    }
  }

  /// newChannelId is an id for a channel not made yet.
  String newChannelId() => "ch${newElementId()}";

  /// moveClipToChannel puts [lane]'s sound on [to] -- taking its name and its
  /// strip -- or, with none, on a channel of its own. The channel it leaves
  /// is gone if it was the last thing on it.
  void moveClipToChannel(TimedLane lane, TimelineChannel? to,
      {bool transient = false}) {
    var e = lane.element;
    if ((e is! AudioElement && e is! VideoElement) || !lane.editable) return;
    // Onto a channel of its own canvas: a channel is the clips on it, and
    // one holding a scene's clip and the master's would be two canvases'.
    if (to != null && to.first.scene != lane.scene) return;
    var clip = lane.clip;
    var moved = to == null
        ? clip.copyWith(
            channel: newChannelId(),
            channelName: newChannelName(),
            mix: const ChannelMix())
        : clip.copyWith(channel: to.key, channelName: to.name, mix: to.mix);
    _setClips([(lane.element, moved)], transient: transient);
  }

  /// splitClip cuts [lane]'s sound in two at [frame] of the scene: what is
  /// before stays, and what is after becomes a sound of its own on the same
  /// channel, starting where the cut was. The knife.
  bool splitClip(TimedLane lane, int frame) {
    var e = lane.element;
    // A sound, or a video -- whose two halves are two videos in the same
    // place on the canvas, each on screen while its half plays.
    if ((e is! AudioElement && e is! VideoElement) ||
        !lane.editable ||
        e.locked) {
      return false;
    }
    var clip = lane.clip;
    CanvasElement withClip(MediaClip c) => switch (e) {
          VideoElement v => v.copyWith(clip: c),
          AudioElement a => a.copyWith(clip: c),
          _ => e,
        };
    // Both halves on one channel. A video put on the timeline from its
    // settings has none of its own -- its lane is keyed by its id -- so it
    // is given one here, or the half after the cut would be a lane apart.
    if (clip.channel.isEmpty) {
      clip = clip.copyWith(
          channel: newChannelId(),
          channelName: clip.channelName.isNotEmpty ? clip.channelName : e.name);
    }
    var rate = math.max(1, _document.frameRate);
    var into = (frame - (clip.at - lane.offset)) / rate;
    if (into <= 0.05 || into >= clip.runLength - 0.05) return false;
    var from = 0.0;
    for (var (i, source) in clip.playlist.indexed) {
      var span = source.span;
      if (into < from + span) {
        var cut = source.start + (into - from);
        var before = [
          ...clip.playlist.take(i),
          source.copyWith(end: cut),
        ];
        var after = [
          source.copyWith(start: cut),
          ...clip.playlist.skip(i + 1),
        ];
        var first = withClip(
            clip.copyWith(playlist: before, fadeOut: 0, loop: MediaLoop.none));
        var second = withClip(clip.copyWith(
                playlist: after,
                fadeIn: 0,
                at: clip.at + (into * rate).round()))
            .withId(newElementId());
        var replaced = _replacedAnywhere(_document, first);
        var both =
            replaced == null ? null : _addedBeside(replaced, first.id, second);
        if (both == null) return false;
        apply(both);
        // Picked where it can be: on the canvas being edited.
        if (_document.elements.any((x) => x.id == second.id)) {
          selectOnly(second.id);
        }
        return true;
      }
      from += span;
    }
    return false;
  }

  /// selectedChannels are the channels picked -- by their strips, by a sound
  /// on them, or by a box dragged across them -- which a cut at the playhead
  /// is made on.
  Set<String> get selectedChannels => _selectedChannels;

  /// selectedChannel is the one channel picked, where one is; setting it
  /// picks that alone.
  String? get selectedChannel =>
      _selectedChannels.isEmpty ? null : _selectedChannels.first;

  set selectedChannel(String? key) =>
      selectChannels(key == null ? const {} : {key});

  void selectChannels(Set<String> keys) {
    if (setEquals(keys, _selectedChannels)) return;
    _selectedChannels = {...keys};
    // One channel picked -- on the timeline or in the mixer -- is the one
    // the effects panel shows.
    if (keys.length == 1) _effectsOf = keys.first;
    notifyListeners();
  }

  /// toggleChannel adds [key] to the channels picked, or takes it out.
  void toggleChannel(String key) {
    var next = {..._selectedChannels};
    if (!next.remove(key)) next.add(key);
    selectChannels(next);
  }

  /// cutAtPlayhead cuts the selected channel -- or the channel of the sound
  /// selected -- where the playhead is: every sound on it the playhead is
  /// part way through. The knife's key.
  bool cutAtPlayhead() {
    var keys = {..._selectedChannels};
    if (keys.isEmpty) {
      var picked = clipSelection;
      for (var lane in timedLanes) {
        if (picked.contains(lane.element.id)) keys.add(lane.channelKey);
      }
    }
    var cut = false;
    for (var channel in timelineChannels) {
      if (!keys.contains(channel.key) || channel.locked) continue;
      for (var lane in channel.lanes) {
        // Fresh each time: a cut changes the document the next one reads.
        var now = timedLanes.where((l) => l.element.id == lane.element.id);
        if (now.isEmpty) continue;
        if (splitClip(now.first, _frame)) cut = true;
      }
    }
    return cut;
  }

  /// lockChannel locks or unlocks every sound on [channel]: locked, none of
  /// them is moved, trimmed, faded, cut or dropped onto.
  void lockChannel(TimelineChannel channel, bool locked) {
    var next = _document;
    for (var lane in channel.lanes) {
      if (!lane.editable) continue;
      next = _replacedAnywhere(next, lane.element.withBase(locked: locked)) ??
          next;
    }
    apply(next);
  }

  /// renameChannel names [channel], on every sound it holds.
  void renameChannel(TimelineChannel channel, String name) {
    var named = name.trim();
    if (named.isEmpty) return;
    _setClips([
      for (var lane in channel.lanes)
        if (lane.editable)
          (lane.element, lane.clip.copyWith(channelName: named)),
    ]);
  }

  /// snapping is whether a sound dragged on the timeline lands on the
  /// seconds and the playhead when it comes near them.
  bool get snapping => _snapping;

  set snapping(bool value) {
    if (_snapping == value) return;
    _snapping = value;
    notifyListeners();
  }

  /// timelineTool is what a press on a sound on the timeline does: take hold
  /// of it, or cut it in two.
  TimelineTool get timelineTool => _timelineTool;

  set timelineTool(TimelineTool value) {
    if (_timelineTool == value) return;
    _timelineTool = value;
    notifyListeners();
  }

  /// setLaneHeight changes one channel's height.
  void setLaneHeight(String channel, double height) {
    laneHeights[channel] = height;
    notifyListeners();
  }

  /// mixerOpen is whether the mixer is shown, under the canvas. The
  /// reader's, kept by the screen -- see panelState.
  bool get mixerOpen => _mixerOpen;

  set mixerOpen(bool open) {
    if (open == _mixerOpen) return;
    _mixerOpen = open;
    if (!open) {
      _mixerMinimised = false;
      _mixerSmallest = false;
    } else {
      _dockOpening(DockPanel.mixer);
    }
    notifyListeners();
  }

  /// mixerSmallest is the mixer smaller still than minimised: its strips
  /// without their names, and without the rail of bands down its right --
  /// only what each channel is doing. Dragged down past its least, or the
  /// Mixer button's step after minimised.
  bool get mixerSmallest => _mixerOpen && _mixerSmallest;

  set mixerSmallest(bool on) {
    if (on == _mixerSmallest) return;
    _mixerSmallest = on;
    if (on) _mixerOpen = true;
    notifyListeners();
  }

  /// mixerMinimised is the mixer folded to its shortest: one line of
  /// channels, each its name over its meter on its side -- as it is dragged
  /// all the way down. Open still.
  bool get mixerMinimised => _mixerOpen && _mixerMinimised;

  set mixerMinimised(bool on) {
    if (on == _mixerMinimised) return;
    _mixerMinimised = on;
    if (on) _mixerOpen = true;
    notifyListeners();
  }

  /// panelState is how the panels under the canvas were left, whatever
  /// canvas is open -- the mixer open, minimised or smallest, the effects
  /// open, the devices folded, the channels' size and the strip column's
  /// width -- for the screen to keep. See restorePanels.
  Map<String, dynamic> get panelState => {
        "mixer": !_mixerOpen
            ? "hidden"
            : _mixerSmallest
                ? "smallest"
                : _mixerMinimised
                    ? "minimised"
                    : "shown",
        "effects": _effectsOpen,
        "rows": _rowsShown,
        "slots": _slotsBeside,
        "animation": _animationOpen,
        "folded": [...foldedDevices]..sort(),
        "laneSize": _laneSize,
        "header": _headerWidth,
      };

  /// restorePanels puts the panels back as [state] -- from panelState --
  /// says, without telling anyone: the screen does it as it opens.
  void restorePanels(Map<String, dynamic> state) {
    switch (state["mixer"]) {
      case "shown":
        _mixerOpen = true;
      case "minimised":
        _mixerOpen = _mixerMinimised = true;
      case "smallest":
        _mixerOpen = _mixerMinimised = _mixerSmallest = true;
    }
    if (state["effects"] == true) _effectsOpen = true;
    if (state["rows"] case bool rows) _rowsShown = rows;
    if (state["slots"] == true) _slotsBeside = true;
    if (state["animation"] == true && !_effectsOpen) _animationOpen = true;
    // As many as fit their places.
    _dockSettle();
    if (state["folded"] case List folded) {
      foldedDevices
        ..clear()
        ..addAll(folded.whereType<String>());
    }
    if (state["laneSize"] case int size when size >= 0 && size < 3) {
      _laneSize = size;
    }
    if (state["header"] case num width) {
      _headerWidth =
          width.toDouble().clamp(timelineHeaderMin, timelineHeaderMax);
    }
  }

  /// canvasView is how this canvas was being looked at -- its channels'
  /// heights, its narrow strips, the timeline's zoom and the effects'
  /// channel -- for the screen to keep with its name. See restoreCanvasView.
  Map<String, dynamic> get canvasView => {
        if (laneHeights.isNotEmpty)
          "lanes": {
            for (var e in laneHeights.entries)
              e.key: double.parse(e.value.toStringAsFixed(1))
          },
        if (_narrowStrips.isNotEmpty) "narrow": [..._narrowStrips]..sort(),
        if (timelineView case var v?)
          "view": [
            double.parse(v.first.toStringAsFixed(2)),
            double.parse(v.span.toStringAsFixed(2))
          ],
        if (_effectsOf case var e?) "effectsOf": e,
      };

  /// restoreCanvasView looks at this canvas as [state] -- from canvasView
  /// -- says: nothing for one never looked at.
  void restoreCanvasView(Map<String, dynamic> state) {
    laneHeights.clear();
    if (state["lanes"] case Map lanes) {
      for (var e in lanes.entries) {
        if (e.key is String && e.value is num) {
          laneHeights[e.key as String] = (e.value as num).toDouble();
        }
      }
    }
    _narrowStrips
      ..clear()
      ..addAll([
        if (state["narrow"] case List narrow) ...narrow.whereType<String>()
      ]);
    timelineView = switch (state["view"]) {
      [num first, num span] when span > 0 =>
        TimelineView(first.toDouble(), span.toDouble()),
      _ => null,
    };
    timelineViewSet++;
    if (state["effectsOf"] case String e) _effectsOf = e;
    notifyListeners();
  }

  /// effectsChannel is the strip the timeline's effects button opens: the
  /// channel picked -- in the mixer or on the timeline -- or the master
  /// when that is what is picked, or else the channel of the sound picked,
  /// or else the master.
  String get effectsChannel {
    var channels = timelineChannels;
    if (selectedChannel case var k?) {
      if (k == mixerMasterKey ||
          k == sceneBusKey ||
          channels.any((c) => c.key == k) ||
          returnOf(k) != null) {
        return k;
      }
    }
    var picked = clipSelection;
    for (var lane in timedLanes) {
      if (picked.contains(lane.element.id)) return lane.channelKey;
    }
    return mixerMasterKey;
  }

  /// effectsOpen is whether the effects panel is shown: the chain of
  /// effectsOf, in a panel of its own over the mixer.
  bool get effectsOpen => _effectsOpen;

  set effectsOpen(bool open) {
    if (open == _effectsOpen) return;
    _effectsOpen = open;
    if (open) {
      _animationOpen = false;
      _chainMotion = false;
      _dockOpening(DockPanel.chain);
    }
    notifyListeners();
  }

  /// effectsFocus is the device the effects panel was last asked to show --
  /// "eq", "comp", "duck" ... -- and effectsFocusCount how many times it has
  /// been asked, so asking for the same one again scrolls to it again.
  String? get effectsFocus => _effectsFocus;

  int get effectsFocusCount => _effectsFocusCount;

  /// openEffects shows [key]'s chain in the effects panel, unfolded on and
  /// scrolled to [device] where one is given.
  void openEffects(String key, {String? device}) {
    if (device != null) {
      foldedDevices.remove(device);
      _effectsFocus = device;
      _effectsFocusCount++;
      // Speech and its Vocaliser are the Speech view's; anything else is in
      // the chain.
      _speechShown = device == "speech" || device == "vocaliser";
    }
    _effectsOf = key;
    _effectsOpen = true;
    _animationOpen = false;
    _chainMotion = false;
    _dockOpening(DockPanel.chain);
    notifyListeners();
  }

  /// editorWide is whether the editor in the effects strip -- a clip's, or
  /// a part's piano roll -- is widened: every setting, and the most room.
  bool get editorWide => _editorWide;

  void toggleEditorWide() {
    _editorWide = !_editorWide;
    _editorWidth = null;
    _effectsFocus = _clipEditorShown ? "clip" : "roll";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// editorWidth is how wide the editor has been dragged by its right edge
  /// -- or null, as Wider or Narrower has it. Kept while the canvas is open.
  double? get editorWidth => _editorWidth;

  set editorWidth(double? width) {
    if (width == _editorWidth) return;
    _editorWidth = width;
    notifyListeners();
  }

  /// closeEditor takes the editor out of the effects strip.
  void closeEditor() {
    _clipEditorShown = false;
    _pianoRollShown = false;
    _speechShown = false;
    notifyListeners();
  }

  /// speechShown is whether the Chain's sound is on the channel's Speech:
  /// see showSpeech.
  bool get speechShown => _speechShown;

  /// showSpeech opens [key]'s Speech in the Chain: its script, its takes and
  /// its voice -- what makes its clips -- and Sing, the Vocaliser. Not steps
  /// of its chain: what they make plays through it.
  void showSpeech(String key) {
    _effectsOf = key;
    _effectsOpen = true;
    _animationOpen = false;
    _chainMotion = false;
    _clipEditorShown = false;
    _pianoRollShown = false;
    _speechShown = true;
    _effectsFocus = "speech";
    _effectsFocusCount++;
    _dockOpening(DockPanel.chain);
    notifyListeners();
  }

  /// clipEditing is the slot the clip editor is open on -- a channel and a
  /// row -- or null where none is, or its clip has gone. It shares the
  /// effects panel with the chain: [clipEditorShown] says which shows.
  PianoRollTarget? get clipEditing {
    var t = _clipEditing;
    if (t == null || t.row == null) return null;
    if (session.at(t.channel, t.row!) == null) return null;
    return t;
  }

  bool get clipEditorShown => _clipEditorShown && clipEditing != null;

  set clipEditorShown(bool on) {
    if (on == _clipEditorShown) return;
    _clipEditorShown = on;
    notifyListeners();
  }

  /// editedClip is the clip the editor is open on.
  SessionClip? get editedClip {
    var t = clipEditing;
    return t == null ? null : session.at(t.channel, t.row!);
  }

  /// openClipEditor opens the clip editor on [channel]'s slot [row], in the
  /// effects panel -- a MIDI clip's notes in the piano roll beside it.
  void openClipEditor(String channel, int row) {
    var clip = session.at(channel, row);
    if (clip == null) return;
    _clipEditing = PianoRollTarget(channel, row);
    if (clip.midi && _instrumentOf(channel) != null) {
      _pianoRoll = PianoRollTarget(channel, row);
    }
    rollSelected.clear();
    _clipCursor = 0;
    _effectsOf = channel;
    _effectsOpen = true;
    // One detail panel: the Chain on its sound.
    _animationOpen = false;
    _chainMotion = false;
    _pianoRollShown = false;
    _speechShown = false;
    _clipEditorShown = true;
    // First in the strip: scrolled to.
    _effectsFocus = "clip";
    _effectsFocusCount++;
    notifyListeners();
  }

  /// editClip changes the clip the editor is open on: one change to undo
  /// -- or, [transient], part of a drag that is.
  void editClip(SessionClip Function(SessionClip clip) change,
      {bool transient = false}) {
    var t = clipEditing;
    if (t == null) return;
    var clip = session.at(t.channel, t.row!)!;
    apply(
        _document.copyWith(
            session: session.put(t.channel, t.row!, change(clip))),
        transient: transient);
    if (!transient) _warpSoon();
  }

  /// previewClip plays the open clip now -- not on the next bar -- to hear
  /// it while it is edited: with the transport stopped, on its own, the
  /// timeline silent (see sessionOnly). Pressed while it plays, it stops.
  void previewClip() {
    var t = clipEditing;
    var clip = editedClip;
    if (t == null || clip == null) return;
    var state = clipState(t.channel, t.row!);
    if (state == ClipState.playing || state == ClipState.queued) {
      var ch = _clipChannels[t.channel];
      if (ch != null) {
        _cancelNext(ch);
        _stopChannelAt(t.channel, _sessionNow);
      }
      notifyListeners();
      return;
    }
    var at = playing ? _sessionNow : _sessionStart();
    unawaited(_startClip(t.channel, t.row!, clip, at));
  }

  /// clipPreviewing is whether the open clip is playing, for its editor's
  /// Play to show Stop.
  bool get clipPreviewing {
    var t = clipEditing;
    if (t == null) return false;
    var state = clipState(t.channel, t.row!);
    return state == ClipState.playing || state == ClipState.queued;
  }

  /// selectedSlot is the clip slot last clicked: picked out in the mixer,
  /// and -- as Ableton's Clip View always shows the clip selected -- the one
  /// in the clip editor, where that is open.
  (String, int)? get selectedSlot => _selectedSlot;

  void selectSlot(String channel, int row) {
    _selectedSlot = (channel, row);
    if (_clipEditorShown && session.at(channel, row) != null) {
      openClipEditor(channel, row);
      return;
    }
    notifyListeners();
  }

  /// canMoveClip is whether [channel]'s slots can take clip [clip]: a MIDI
  /// clip on a MIDI channel, a sound on an audio one.
  bool canMoveClip(SessionClip clip, String channel) =>
      clip.midi == instrumentChannel(channel);

  /// moveClip moves the clip in [fromChannel]'s slot [fromRow] to
  /// [toChannel]'s [toRow] -- in place of what was there -- or, with
  /// [copy], puts a copy of it there. One change to undo.
  void moveClip(String fromChannel, int fromRow, String toChannel, int toRow,
      {bool copy = false}) {
    var clip = session.at(fromChannel, fromRow);
    if (clip == null || !canMoveClip(clip, toChannel)) return;
    if (fromChannel == toChannel && fromRow == toRow) return;
    var moved = copy ? clip.copyWith(id: newElementId()) : clip;
    // A clip playing from either slot stops: it is somewhere else now.
    for (var (ch, row) in [(fromChannel, fromRow), (toChannel, toRow)]) {
      var playing = _clipChannels[ch];
      if (playing != null &&
          (playing.now?.row == row || playing.next?.row == row) &&
          !(copy && ch == fromChannel && row == fromRow)) {
        _stopChannelAt(ch, _sessionNow);
      }
    }
    var grid = session.put(toChannel, toRow, moved);
    if (!copy) grid = grid.put(fromChannel, fromRow, null);
    apply(_document.copyWith(session: grid));
    // The editor follows the clip it was showing.
    if (!copy &&
        _clipEditing?.channel == fromChannel &&
        _clipEditing?.row == fromRow) {
      _clipEditing = PianoRollTarget(toChannel, toRow);
      if (moved.midi) _pianoRoll = PianoRollTarget(toChannel, toRow);
    }
    _selectedSlot = (toChannel, toRow);
    notifyListeners();
  }

  /// _editClipById changes clip [id], wherever it is now: for a change
  /// that took a while -- a sound reversed, cropped, its tempo heard --
  /// while the editor may have moved on to another clip.
  void _editClipById(String id, SessionClip Function(SessionClip clip) change) {
    if (session.find(id) case (var channel, var row)?) {
      setSessionClip(channel, row, change(session.at(channel, row)!));
      _warpSoon();
    }
  }

  /// scaleOf is the scale [channel] is in: its Scale effect's, or C major.
  (int, List<int>) scaleOf(String channel) {
    var scale = _instrumentOf(channel)
        ?.instrument
        ?.effects
        .where((m) => m.on && m.kind == MidiEffectKind.scale)
        .firstOrNull;
    if (scale == null) return (0, scaleSteps[0]);
    return (
      scale.choice("root"),
      scaleSteps[scale.choice("scale").clamp(0, scaleSteps.length - 1)]
    );
  }

  /// useNoteTool uses [tool] on the open MIDI clip's picked notes -- or all
  /// of them.
  void useNoteTool(NoteTool tool) {
    var t = clipEditing;
    var clip = editedClip;
    // A part's notes, in its piano roll.
    var roll = pianoRoll;
    if (pianoRollShown && roll != null && roll.row == null) {
      var content = rollContent!;
      setRollContent(
          notes: applyNoteTool(tool, content.notes, rollSelected,
              scale: scaleOf(roll.channel),
              loopEnd: content.beats,
              seed: _noteToolPresses++));
      return;
    }
    if (t == null || clip == null || !clip.midi) return;
    var bpb = _document.audio.beatsPerBar;
    var notes = applyNoteTool(tool, clip.notes, rollSelected,
        scale: scaleOf(t.channel),
        loopEnd: clip.loopEnd(bpb),
        seed: _noteToolPresses++);
    editClip((c) => c.copyWith(notes: notes));
  }

  /// _keepSound stores [wav] -- a WAV file's bytes -- as a new sound in
  /// the library -- see speechStore -- answering its id, or null.
  Future<String?> _keepSound(Uint8List wav) async {
    var dir = await Directory.systemTemp.createTemp("canvas-clip");
    try {
      var file = File(path.join(dir.path, "clip.wav"));
      await file.writeAsBytes(wav, flush: true);
      return await CanvasController.speechStore(file.path);
    } finally {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  /// reverseClip plays the open audio clip backwards: a reversed copy of
  /// its file, made and kept in the library, the original kept too -- so
  /// pressed again, it is the original once more. Answers why not.
  Future<String?> reverseClip() async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    if (clip.reversedOf case var original?) {
      _editClipById(
          clip.id,
          (c) => _markersMirrored(
              c.copyWith(sound: original, clearReversed: true),
              _spanOf(original)));
      return null;
    }
    var audio = await CanvasController.clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    var n = l.length;
    // Turned round and written out away from the app's own isolate, as it
    // was read.
    var id = await _keepSound(await _reversedWavAway(l, r));
    if (id == null || _disposed) return "The reversed sound could not be kept.";
    var length = n / mixRate;
    var end = sound.end > 0 ? sound.end : length;
    var reversed = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (reversed)",
        start: math.max(0, length - end),
        end: math.max(0, length - sound.start),
        length: length);
    _editClipById(
        clip.id,
        (c) => _markersMirrored(
            c.copyWith(sound: reversed, reversedOf: sound), end - sound.start));
    return null;
  }

  /// _spanOf is how long [sound] plays, in seconds.
  double _spanOf(MediaSource sound) => sound.end > 0
      ? sound.end - sound.start
      : math.max(0, sound.length - sound.start);

  /// _markersMirrored is [clip] with its warp markers turned round with its
  /// sound ([seconds] of it played): a moment from its start becomes that
  /// moment from its end. Its end is pinned too, where its start was, since
  /// past the last marker a sound goes at its tempo; without it a sound
  /// reversed twice would not be as it was.
  SessionClip _markersMirrored(SessionClip clip, double seconds) {
    if (clip.markers.isEmpty || seconds <= 0) return clip;
    var last = clip.warpMap.beatAt(seconds);
    return clip.copyWith(markers: [
      for (var m in clip.markers)
        if (m.seconds > 0 && m.seconds < seconds - 1e-6)
          (seconds: seconds - m.seconds, beat: last - m.beat),
      (seconds: seconds, beat: last),
    ]);
  }

  /// cropClip keeps only what the open clip plays -- from its start, or its
  /// loop's start where that is earlier, to its loop's end -- as a new file
  /// for an audio clip, or the notes there for a MIDI one, and moves its
  /// start and loop to match. Answers why not.
  Future<String?> cropClip() async {
    var clip = editedClip;
    if (clip == null) return null;
    var bpb = _document.audio.beatsPerBar;
    var spb = math.max(0.001, _document.audio.secondsPerBeat);
    var from = clip.loop ? math.min(clip.start, clip.loopStart) : clip.start;
    var to = clip.loopEnd(bpb);
    if (to <= from) return null;
    SessionClip moved(SessionClip c) =>
        c.copyWith(start: c.start - from, loopStart: c.loopStart - from);
    if (clip.midi) {
      _editClipById(
          clip.id,
          (c) => moved(c).copyWith(notes: [
                for (var n in c.notes)
                  if (n.end > from && n.start < to)
                    n.copyWith(
                        start: math.max(0, n.start - from),
                        length: math.min(n.end, to) - math.max(n.start, from)),
              ]));
      return null;
    }
    var sound = clip.sound;
    if (sound == null) return null;
    var audio = await CanvasController.clipAudio(sound.assetId);
    if (audio == null) return "Its sound could not be read.";
    var (l, r) = audio;
    // Where its beats are in its sound: by its warp map, warped; at the
    // song's tempo -- faster with its pitch -- not.
    var speed = math.pow(2, (clip.pitch + clip.cents / 100) / 12).toDouble();
    double sourceOf(double beat) =>
        clip.warp ? clip.warpMap.sourceAt(beat) : beat * spb * speed;
    var s0 = sourceOf(from), s1 = sourceOf(to);
    var a = ((sound.start + s0) * mixRate).round().clamp(0, l.length);
    var b = ((sound.start + s1) * mixRate).round().clamp(a, l.length);
    if (b - a < 1) return "There is no sound there to keep.";
    var id = await _keepSound(await _wavAway(
        Float32List.sublistView(l, a, b), Float32List.sublistView(r, a, b)));
    if (id == null || _disposed) return "The cropped sound could not be kept.";
    var cropped = MediaSource(
        assetId: id,
        name: "${sound.name.isEmpty ? "Clip" : sound.name} (cropped)",
        length: (b - a) / mixRate);
    // Its warp markers moved with it, and its end pinned where it was.
    var markers = [
      for (var m in clip.markers)
        if (m.seconds > s0 + 1e-6 && m.seconds < s1 - 1e-6)
          (seconds: m.seconds - s0, beat: m.beat - from),
      if (clip.warp && clip.markers.isNotEmpty)
        (seconds: s1 - s0, beat: to - from),
    ];
    _editClipById(
        clip.id,
        (c) => moved(c)
            .copyWith(sound: cropped, clearReversed: true, markers: markers));
    return null;
  }

  /// _playedSound is what audio [clip] plays: its own sound, or -- warped,
  /// or moved in pitch -- that rendered at the song's tempo, made now where
  /// it has not been. See warp.dart.
  Future<MediaSource?> _playedSound(SessionClip clip) async {
    if (!clip.needsRender || clip.sound == null) return clip.sound;
    var spb = _document.audio.secondsPerBeat;
    var signature = clip.warpSignature(spb);
    // Rendered already -- and still there: a file the library swept away
    // is rendered again, not played as silence.
    if (clip.warpedFor == signature && clip.warped != null) {
      if (await CanvasMedia.existingPath(
              MediaKind.audio, clip.warped!.assetId) !=
          null) {
        return clip.warped;
      }
    }
    return _warpingNow[signature] ??= _warp(clip, signature).whenComplete(() {
      _warpingNow.remove(signature);
    });
  }

  Future<MediaSource?> _warp(SessionClip clip, String signature) async {
    var sound = clip.sound!;
    warping.add(clip.id);
    notifyListeners();
    try {
      var audio = await CanvasController.clipAudio(sound.assetId);
      if (audio == null || _disposed) return null;
      var (l, r) = audio;
      var length = l.length / mixRate;
      var from = sound.start, to = sound.end > 0 ? sound.end : length;
      var spb = _document.audio.secondsPerBeat;
      var map = clip.warpMap;
      var (warp, mode) = (clip.warp, clip.warpMode);
      var semitones = clip.pitch + clip.cents / 100;
      // Faded where it is played from and round: as _startClip has them.
      var loopAt = clip.loopStart * spb;
      var fades = clip.fade
          ? (
              ins: [clip.start * spb, if (clip.loop) loopAt],
              outs: [
                loopAt + math.max(0.05, clip.bars * _barSeconds),
              ],
            )
          : null;
      var (wav, frames) = await _warpedWavAway(l, r, from, to, warp, mode, map,
          spb, semitones, clip.envelopes, fades);
      var id = await CanvasController.partStore(wav);
      if (id == null || _disposed) return null;
      var warped = MediaSource(
          assetId: id,
          name: "${sound.name.isEmpty ? "Clip" : sound.name} (warped)",
          length: frames / mixRate);
      // Written onto the clip as it is now, if it is still there and still
      // wants this: not a change of its own to undo -- the file follows
      // the clip.
      if (session.find(clip.id) case (var ch, var row)?) {
        var now = session.at(ch, row)!;
        if (now.warpSignature(spb) == signature) {
          apply(
              _document.copyWith(
                  session: session.put(ch, row,
                      now.copyWith(warped: warped, warpedFor: signature))),
              transient: true);
        }
      }
      return warped;
    } catch (exception) {
      debugPrint("Unable to warp the clip: $exception");
      return null;
    } finally {
      warping.remove(clip.id);
      if (!_disposed) notifyListeners();
    }
  }

  /// _warpSoon warps every clip that needs it, a moment after the last
  /// change -- so a clip is ready before it is launched.
  void _warpSoon() {
    _warpTimer?.cancel();
    _warpTimer = Timer(const Duration(milliseconds: 400), () async {
      for (var (_, _, clip) in session.clips) {
        if (_disposed) return;
        if (clip.needsRender) await _playedSound(clip);
      }
    });
  }

  /// setWarp switches the open audio clip's warping on or off. On for the
  /// first time, its tempo is heard first -- see estimateTempo.
  Future<String?> setWarp(bool on) async {
    var clip = editedClip;
    var sound = clip?.sound;
    if (clip == null || clip.midi || sound == null) return null;
    var bpm = clip.bpm;
    if (on && bpm == 0) {
      var audio = await CanvasController.clipAudio(sound.assetId);
      if (audio == null) return "Its sound could not be read.";
      var (l, r) = audio;
      var from = (sound.start * mixRate).round().clamp(0, l.length);
      var to = sound.end > 0
          ? (sound.end * mixRate).round().clamp(from, l.length)
          : l.length;
      var near = _document.audio.tempo;
      var bpb = _document.audio.beatsPerBar;
      var sl = Float32List.sublistView(l, from, to);
      var sr = Float32List.sublistView(r, from, to);
      bpm = await _tempoAway(sl, sr, near, bpb);
      if (_disposed) return null;
    }
    _editClipById(clip.id, (c) => c.copyWith(warp: on, bpm: bpm));
    return null;
  }

  /// clipPlayhead is where the open clip is playing, in beats into it --
  /// what its Set buttons take -- or null where it is not playing.
  double? get clipPlayhead {
    var t = clipEditing;
    if (t == null) return null;
    var ch = _clipChannels[t.channel]?.now;
    if (ch == null || ch.row != t.row) return null;
    return clipAt(t.channel);
  }

  /// pianoRoll is what the piano roll edits: a MIDI clip in a slot, or a
  /// MIDI channel's part -- or null for nothing opened yet. It shares the
  /// effects panel with the chain: [pianoRollShown] says which shows.
  PianoRollTarget? get pianoRoll {
    var t = _pianoRoll;
    if (t == null || _instrumentOf(t.channel) == null) return null;
    if (t.row case var row? when session.at(t.channel, row) == null) {
      return null;
    }
    return t;
  }

  bool get pianoRollShown => _pianoRollShown && pianoRoll != null;

  set pianoRollShown(bool on) {
    if (on == _pianoRollShown) return;
    _pianoRollShown = on;
    notifyListeners();
  }

  /// openPianoRoll opens the piano roll on MIDI channel [channel]'s part,
  /// or on its clip in slot [row], in the effects panel.
  void openPianoRoll(String channel, {int? row}) {
    // A clip's notes are in its clip editor.
    if (row != null) {
      openClipEditor(channel, row);
      return;
    }
    if (_instrumentOf(channel) == null) return;
    _pianoRoll = PianoRollTarget(channel, row);
    _effectsOf = channel;
    _effectsOpen = true;
    // One detail panel: the Chain on its sound.
    _animationOpen = false;
    _chainMotion = false;
    _pianoRollShown = true;
    _speechShown = false;
    _clipEditorShown = false;
    _effectsFocus = "roll";
    _effectsFocusCount++;
    rollSelected.clear();
    notifyListeners();
  }

  /// rollContent is what the piano roll shows, in beats: the notes, the
  /// controllers' curves, and how long it is -- a clip's length, or a
  /// part's, to the end of the bar after its last note and never under
  /// four bars.
  RollContent? get rollContent {
    var t = pianoRoll;
    if (t == null) return null;
    var a = _document.audio;
    if (t.row case var row?) {
      // To its loop's end: a loop moved on shows where it starts from.
      var clip = session.at(t.channel, row)!;
      return RollContent(clip.notes, clip.controls, clip.loopEnd(a.beatsPerBar),
          name: clip.name.isEmpty ? "Clip" : clip.name, clip: true);
    }
    var e = _instrumentOf(t.channel)!;
    var part = e.instrument!;
    var spb = math.max(0.001, a.secondsPerBeat);
    var notes = [
      for (var n in part.notes)
        MidiNote(n.key, n.start / spb, n.length / spb, n.velocity),
    ];
    var end = notes.isEmpty ? 0.0 : notes.map((n) => n.end).reduce(math.max);
    var bars = math.max(4, (end / a.beatsPerBar).ceil() + 1);
    return RollContent(
        notes,
        {
          for (var c in part.controls.entries)
            c.key: [for (var (t, v) in c.value) (t / spb, v)],
        },
        bars * a.beatsPerBar.toDouble(),
        name: "${e.name} part",
        clip: false);
  }

  /// setRollContent writes what the piano roll changed: notes and curves in
  /// beats, and -- for a clip -- its length in beats.
  void setRollContent(
      {List<MidiNote>? notes,
      Map<MidiControl, List<ControlPoint>>? controls,
      double? beats,
      bool transient = false}) {
    var t = pianoRoll;
    if (t == null) return;
    var a = _document.audio;
    if (t.row case var row?) {
      var clip = session.at(t.channel, row)!;
      apply(
          _document.copyWith(
              session: session.put(
                  t.channel,
                  row,
                  clip.copyWith(
                      notes: notes,
                      controls: controls,
                      bars: beats == null
                          ? null
                          : (beats - clip.loopStart) / a.beatsPerBar))),
          transient: transient);
      return;
    }
    var e = _instrumentOf(t.channel)!;
    var spb = math.max(0.001, a.secondsPerBeat);
    var part = e.instrument!.copyWith(
      notes: notes == null
          ? null
          : [
              for (var n in notes)
                MidiNote(n.key, n.start * spb, n.length * spb, n.velocity),
            ],
      controls: controls == null
          ? null
          : {
              for (var c in controls.entries)
                c.key: [for (var (t, v) in c.value) (t * spb, v)],
            },
    );
    setInstrument(e, part, transient: transient);
  }

  /// rollCursor is where in what the piano roll shows a paste goes, in
  /// beats: for a part, the playhead's place in it -- set, it moves the
  /// playhead, and Play starts there; for a clip, a marker of its own, its
  /// loop playing on regardless.
  double get rollCursor {
    var t = pianoRoll;
    if (t == null) return 0;
    if (t.row != null) return _clipCursor;
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  set rollCursor(double beats) {
    var t = pianoRoll;
    if (t == null) return;
    beats = math.max(0, beats);
    if (t.row != null) {
      if (beats == _clipCursor) return;
      _clipCursor = beats;
      notifyListeners();
      return;
    }
    var e = _instrumentOf(t.channel)!;
    frame = e.clip.at +
        (beats * _document.audio.secondsPerBeat * _document.frameRate).round();
  }

  /// movePart moves the piano roll's part along the timeline by [bars],
  /// never before the start.
  void movePart(int bars) {
    var t = pianoRoll;
    if (t == null || t.row != null) return;
    var e = _instrumentOf(t.channel)!;
    var a = _document.audio;
    var by =
        (bars * a.beatsPerBar * a.secondsPerBeat * _document.frameRate).round();
    setTimedClip(e, e.clip.copyWith(at: math.max(0, e.clip.at + by)));
  }

  /// rollPlayhead is where playing has got in what the piano roll shows,
  /// in beats, or null where it is not playing.
  double? get rollPlayhead {
    var t = pianoRoll;
    if (t == null || !playing) return null;
    if (t.row case var row?) {
      var ch = _clipChannels[t.channel];
      if (ch?.now?.row != row) return null;
      var p = clipProgress(t.channel);
      var c = rollContent;
      return p == null || c == null ? null : p * c.beats;
    }
    var e = _instrumentOf(t.channel)!;
    return _nowInPart(e) / math.max(0.001, _document.audio.secondsPerBeat);
  }

  /// pickStrip picks the channel [key] -- or the master, mixerMasterKey --
  /// from the mixer: picked on the timeline too, and its chain the one the
  /// effects panel shows.
  void pickStrip(String key) {
    if (selectedChannel == key && _effectsOf == key) return;
    _effectsOf = key;
    selectedChannel = key;
    notifyListeners();
  }

  /// effectsOf is the strip whose chain of effects the effects panel shows,
  /// by key or mixerMasterKey, or null for none chosen yet.
  String? get effectsOf => _effectsOf;

  set effectsOf(String? key) {
    if (key == _effectsOf) return;
    _effectsOf = key;
    notifyListeners();
  }

  /// keyframesShown is whether the timeline shows its row of keyframes:
  /// hidden for room, the ruler and the channels stay.
  bool get keyframesShown => _keyframesShown;

  set keyframesShown(bool shown) {
    if (shown == _keyframesShown) return;
    _keyframesShown = shown;
    notifyListeners();
  }

  /// restoreShown puts back which timeline rows were showing, as the
  /// preferences kept them -- without notifying, as restoreFit, because it
  /// runs while the page is being built.
  void restoreShown({required bool keyframes, required bool cues}) {
    _keyframesShown = keyframes;
    _cuesShown = cues;
  }

  /// cuesShown is whether the cues are marked on the timeline's ruler.
  bool get cuesShown => _cuesShown;

  set cuesShown(bool shown) {
    if (shown == _cuesShown) return;
    _cuesShown = shown;
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
  /// to the first after the last -- putting back any dragged one, as the
  /// button means all of them.
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

  /// waveformOf is [assetId]'s shape, as peaks from nought to one across the
  /// whole file, or null until it has been read -- it is read on first asking,
  /// off the main thread, and the timeline is told when it arrives.
  Float32List? waveformOf(String assetId) {
    if (CanvasController._waveforms.containsKey(assetId))
      return CanvasController._waveforms[assetId];
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
  /// id, wherever that is: the canvas being edited, the master seen from a
  /// scene, or another scene; null where it is none of them. A clip on a
  /// scene is held within that scene's frames; the master's goes where it is
  /// put.
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
    var going = playing && !_sessionOnly;
    var ducks = _duckEnvelopes();
    var rate = math.max(1, _document.frameRate);
    for (var (e, at) in _joinedCuts(_timedOnScreen.toList())) {
      // Practising, the timeline's sounds are quiet: the piece is played
      // live -- the hand not being practised -- at the practice tempo.
      var moment = at == null || _practice != null ? null : _momentOf(e, at);
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

  /// _duckEnvelopes is how far each channel is ducked over the run -- see
  /// duckEnvelopes -- worked out again only when the document has changed or
  /// a recording's shape has been read since.
  Map<String, List<GainPoint>> _duckEnvelopes() {
    if (identical(_duckFor, _document) &&
        _duckWaves == CanvasController._waveforms.length) {
      return _ducks;
    }
    _duckFor = _document;
    _duckWaves = CanvasController._waveforms.length;
    _ducks = duckEnvelopes(_document, waveformOf);
    return _ducks;
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

  /// _joinedCuts is the timeline's sounds as they are played: a sound cut in
  /// two, its halves still end to end on one channel, is played as the one
  /// sound it was. The second half is cued with nothing, and the first runs
  /// on through the join; played as two, the frame-stepped playhead would
  /// make a skip at the cut.
  ///
  /// Only where nothing would be lost by it: the same file, the second
  /// starting in it where the first stops and on the timeline where the
  /// first ends, no fade at the join, neither looping. The level is whichever
  /// half the playhead is in, so each half's volume line still holds.
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
