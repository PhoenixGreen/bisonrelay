part of 'epub_layers.dart';

// _LayerMaker, which turns each element that moves into a layer: its pictures,
// CSS keyframes, element videos, controls and keyboards. Part of
// epub_layers.dart.

class _LayerMaker {
  final CanvasElement e;
  final CanvasDocument page;
  final int frames;
  final double pixels;
  final CanvasImageSource? images;
  final _Sheets sheets;
  final ui.Canvas Function(ui.PictureRecorder) start;
  final Rect region;
  final Rect pageBox;
  final ElementFilms? films;
  final ExportMedia? media;

  /// below is what is drawn under it, for filming it where there is no clear
  /// background to film it on.
  final List<CanvasElement> below;
  final int index;

  /// clips are the videos made, for the book to carry.
  final List<EpubFile> clips = [];

  /// sounds are the reactions' sound files in the book, by asset.
  final Map<String, String> sounds;

  /// player is whether the reader plays it, as a video of its own.
  final bool player;

  _LayerMaker(this.e, this.page, this.frames, this.pixels, this.images,
      this.sheets, this.start, this.region, this.pageBox,
      {this.films,
      this.media,
      this.below = const [],
      required this.index,
      this.sounds = const {},
      this.player = false});

  int get rate => page.frameRate <= 0 ? 1 : page.frameRate;

  Keyframe poseAt(int f) => poseWithMotion(e, f, page);

  ui.Picture record(int f,
      {bool hovered = false,
      CanvasElement? element,
      VideoShow Function(VideoElement)? videoShow}) {
    var recorder = ui.PictureRecorder();
    paintElement(start(recorder), element ?? e, f,
        frameRate: page.frameRate,
        images: images,
        document: page,
        hovered: hovered,
        videoShow: videoShow,
        poseOutside: true);
    return recorder.endRecording();
  }

  Future<EpubSprite?> picture(int f,
      {bool hovered = false, CanvasElement? element, Rect? crop}) async {
    // Its pictures read first, not their placeholders (see flatten).
    await drawWhenLoaded(
        images, (_) => record(f, hovered: hovered, element: element).dispose());
    var p = record(f, hovered: hovered, element: element);
    try {
      return await sheets.add(p, crop ?? region);
    } finally {
      p.dispose();
    }
  }

  Future<EpubLayer> make({required bool hovers}) async {
    var layer = await _make(hovers: hovers);
    // A Run panel's web page, run live over the picture of its last run;
    // a Code panel's files over its panes, to be scrolled.
    var frames = _liveFrames(e, page, pixels);
    if (frames.isNotEmpty) {
      return EpubLayer(
          id: layer.id,
          visible: layer.visible,
          originX: layer.originX,
          originY: layer.originY,
          pose: layer.pose,
          parts: layer.parts,
          clip: layer.clip,
          hover: layer.hover,
          hoverBox: layer.hoverBox,
          legend: layer.legend,
          switched: layer.switched,
          reactions: layer.reactions,
          controls: layer.controls,
          keyboard: layer.keyboard,
          frames: frames);
    }
    return layer;
  }

  Future<EpubLayer> _make({required bool hovers}) async {
    // A video the reader plays is its own <video> in this layer, poster and
    // all, not a picture of it under a frozen copy of itself.
    if (player) {
      var box = e.bounds;
      return EpubLayer(
        id: e.id,
        visible: e.visible,
        originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
        originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
        pose: _poseKeys(),
      );
    }
    // A score sheet and an instrument: pictures switched on and off and
    // moved by the clock, never a film (see _sheetLayer).
    if (e case SheetElement s) {
      if (await _sheetLayer(s) case var layer?) return layer;
    }
    if (e case AudioElement a when a.instrument != null && a.visible) {
      if (await _keysLayer(a) case var layer?) return layer;
    }
    // A synth's keyboard module: played as an instrument is, its keys
    // sounding the patch its speaker plays.
    if (e case SynthModuleElement k
        when k.module == SynthModuleKind.keys && k.visible) {
      if (await _synthKeysLayer(k) case var layer?) return layer;
    }
    var names = [
      for (var f = 0; f < frames; f++)
        _lookAt(e, f, poseAt(f), frames, page.frameRate,
            poseAt: poseAt, page: page),
    ];
    var changes = names.toSet().length > 1 || media != null;

    var parts = <EpubPart>[];
    EpubClip? clip;
    if (!changes) {
      if (await picture(0) case var s?) parts.add(EpubPart(s));
    } else {
      var css = _cssAble() ? await _cssParts() : null;
      if (css != null) {
        parts = css;
      } else if (films != null) {
        clip = await _film(names);
      }
      if (css == null && clip == null) {
        // Nothing can move it here: it holds still, as it ends up.
        if (await picture(frames - 1) case var s?) parts.add(EpubPart(s));
      }
    }

    var box = e.bounds;
    return EpubLayer(
      id: e.id,
      visible: e.visible,
      // What a keyframe turns and grows it about: its anchor, where it is
      // on the page. See ElementBase.anchorX.
      originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
      originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
      pose: _poseKeys(),
      parts: parts,
      clip: clip,
      // As it looks once arrived: the pointer is on a button that is there.
      hover: hovers ? await picture(frames - 1, hovered: true) : null,
      hoverBox: hovers
          ? Rect.fromLTRB(box.left * pixels, box.top * pixels,
              box.right * pixels, box.bottom * pixels)
          : null,
      legend: [
        for (var (bit, (_, rect)) in _switchable(e).indexed)
          (
            bit,
            Rect.fromLTRB(rect.left * pixels, rect.top * pixels,
                rect.right * pixels, rect.bottom * pixels)
          ),
      ],
      switched: await _legend(),
      reactions: _reactions(),
    );
  }

  /// drawn records [paint] on the page's canvas and packs what it drew over
  /// [crop] (document units) as a picture.
  Future<EpubSprite?> drawn(void Function(ui.Canvas c) paint, Rect crop) async {
    var recorder = ui.PictureRecorder();
    paint(start(recorder));
    var p = recorder.endRecording();
    try {
      return await sheets.add(
          p,
          Rect.fromLTRB(crop.left * pixels, crop.top * pixels,
              crop.right * pixels, crop.bottom * pixels));
    } finally {
      p.dispose();
    }
  }

  /// _onOff is a picture's opacity at each frame: there while [on] says.
  List<EpubKey> _onOff(bool Function(int f) on) => _compact([
        for (var f = 0; f < frames; f++) {"opacity": on(f) ? "1" : "0"},
      ]);

  EpubLayer _layerOf(List<EpubPart> parts,
      {List<EpubControl> controls = const [], EpubKeyboard? keyboard}) {
    var box = e.bounds;
    return EpubLayer(
      id: e.id,
      visible: e.visible,
      originX: e.turnedAboutCentre(e.anchorIn(box), box.center).dx * pixels,
      originY: e.turnedAboutCentre(e.anchorIn(box), box.center).dy * pixels,
      pose: _poseKeys(),
      parts: parts,
      controls: controls,
      keyboard: keyboard,
    );
  }

  /// _sheetLayer is a score sheet as a book plays it: each systems page and
  /// each lit note a picture shown on cue, the playhead a line moved by the
  /// clock, and its playbar's buttons, which the clock answers.
  Future<EpubLayer?> _sheetLayer(SheetElement s) async {
    var bounds = s.bounds;
    var views = [
      for (var f = 0; f < frames; f++) sheetViewOf(s, bounds, page, f),
    ];
    if (views.any((v) => v == null)) return null;
    var vs = views.cast<SheetView>();
    double pageOf(SheetView v) => v.window.top;
    var parts = <EpubPart>[];
    var sp = vs.first.engraved.options.space;
    // The pages, each as it is at rest.
    var pages = <double, SheetView>{};
    for (var v in vs) {
      pages.putIfAbsent(pageOf(v), () => v);
    }
    for (var MapEntry(key: top, value: v) in pages.entries) {
      var pic = await drawn(
          (c) => paintScoreSheet(c, bounds, s, v,
              lit: const {},
              head: false,
              progress: 0,
              playing: false,
              knob: false,
              practice: false),
          bounds);
      if (pic == null) continue;
      parts.add(EpubPart(pic, keys: _onOff((f) => pageOf(vs[f]) == top)));
      // Each note lit, where it is on this page, while it sounds.
      var lit = <String, Set<int>>{};
      for (var (f, w) in vs.indexed) {
        if (pageOf(w) != top) continue;
        for (var id in sheetSounding(w)) {
          (lit[id] ??= {}).add(f);
        }
      }
      for (var MapEntry(key: id, value: on) in lit.entries) {
        var hit = v.engraved.hits
            .where((h) => h.kind == ScoreHitKind.event && h.event == id)
            .firstOrNull;
        if (hit == null) continue;
        // The head and its stem: up or down from it.
        var r = hit.rect.inflate(sp * 0.2);
        r = Rect.fromLTRB(
            r.left, r.top - sp * 3.6, r.right + sp * 1.6, r.bottom + sp * 3.6);
        var crop = Rect.fromLTRB(
            v.origin.dx + r.left * v.scale,
            v.origin.dy + r.top * v.scale,
            v.origin.dx + r.right * v.scale,
            v.origin.dy + r.bottom * v.scale);
        var pic = await drawn(
            (c) => paintScoreSheet(c, bounds, s, v,
                lit: {id},
                head: false,
                progress: 0,
                playing: false,
                bar: false),
            crop.intersect(bounds));
        if (pic == null) continue;
        parts.add(EpubPart(pic, keys: _onOff(on.contains)));
      }
      // The playhead: one line a system, moved along it.
      if (s.playhead) {
        for (var (si, sys) in v.engraved.systems.indexed) {
          var at = <int, double>{};
          for (var (f, w) in vs.indexed) {
            if (pageOf(w) != top || w.place == null) continue;
            var x = w.engraved.xOf(w.place!.bar, w.place!.at);
            if (x == null || x.$2 != si) continue;
            at[f] = w.origin.dx + (x.$1 + sp * 0.5) * w.scale;
          }
          if (at.isEmpty) continue;
          var x0 = at.values.first;
          var y0 = v.origin.dy + (sys.top) * v.scale;
          var y1 = v.origin.dy + (sys.bottom) * v.scale;
          var line = await drawn((c) {
            var paint = ui.Paint()
              ..color = const ui.Color(0xFFE2622B)
              ..strokeWidth = math.max(1.5, sp * 0.25 * v.scale);
            c.drawLine(Offset(x0, y0), Offset(x0, y1), paint);
          }, Rect.fromLTRB(x0 - sp, y0 - 2, x0 + sp, y1 + 2).intersect(bounds));
          if (line == null) continue;
          parts.add(EpubPart(line,
              keys: _compact([
                for (var f = 0; f < frames; f++)
                  {
                    "opacity": at.containsKey(f) ? "1" : "0",
                    "transform":
                        "translate(${_n(((at[f] ?? x0) - x0) * pixels, 2)}px,0px)",
                  },
              ])));
        }
      }
    }
    // The playbar: the track filled as far as the clock has got.
    var controls = <EpubControl>[];
    if (sheetBarRect(s, bounds) case var bar?) {
      var parts0 = sheetBarParts(bar, practice: false);
      var track = parts0[SheetBarPart.track]!;
      // Its bars as they play: all of them, or the range it shows.
      var (from, to) = sheetFrames(s, page) ?? (0, frames);
      double done(int f) => sheetProgress(s, vs[f]);
      // The filled track, revealed from the left; the knob slid along.
      var line = sheetTrackLine(track);
      var orange = ui.Paint()..color = const ui.Color(0xFFE2622B);
      var fill = await drawn(
          (c) => c.drawRRect(
              ui.RRect.fromRectAndRadius(
                  line, ui.Radius.circular(line.height / 2)),
              orange),
          line.inflate(1));
      if (fill != null) {
        parts.add(EpubPart(fill,
            keys: const [],
            clipKeys: _compact([
              for (var f = 0; f < frames; f++)
                {
                  "clip-path":
                      "inset(0px ${_n((1 - done(f)) * 100, 2)}% 0px 0px)",
                },
            ])));
      }
      var radius = sheetKnobRadius(track);
      var knob = await drawn(
          (c) =>
              c.drawCircle(Offset(line.left, line.center.dy), radius, orange),
          Rect.fromCircle(
              center: Offset(line.left, line.center.dy), radius: radius + 1));
      if (knob != null) {
        parts.add(EpubPart(knob,
            keys: _compact([
              for (var f = 0; f < frames; f++)
                {
                  "transform":
                      "translate(${_n(done(f) * line.width * pixels, 2)}px,0px)",
                },
            ])));
      }
      Rect px(Rect r) => Rect.fromLTRB(
          r.left * pixels, r.top * pixels, r.right * pixels, r.bottom * pixels);
      var onsets = sheetOnsets(s, page).join(",");
      // A pause over the play button while it plays.
      var play = parts0[SheetBarPart.play]!;
      var tint = ui.Color.alphaBlend(
          s.ink.withValues(alpha: 0.07), s.paper.withValues(alpha: 1));
      var u = play.height * 0.16 * pixels;
      var pause = '<span class="pp" style="background:${_cssColour(tint)}">'
          '<span style="left:${_n(play.width * pixels / 2 - u * 0.75, 2)}px;'
          'top:${_n(play.height * pixels / 2 - u * 1.1, 2)}px;'
          'width:${_n(u * 0.5, 2)}px;height:${_n(u * 2.2, 2)}px;'
          'background:${_cssColour(s.ink)}"></span>'
          '<span style="left:${_n(play.width * pixels / 2 + u * 0.25, 2)}px;'
          'top:${_n(play.height * pixels / 2 - u * 1.1, 2)}px;'
          'width:${_n(u * 0.5, 2)}px;height:${_n(u * 2.2, 2)}px;'
          'background:${_cssColour(s.ink)}"></span></span>';
      var first = sheetOnsets(s, page).firstOrNull ?? from;
      controls = [
        EpubControl("goto", px(parts0[SheetBarPart.start]!),
            data: {"frame": "$first"}, label: "To the start"),
        EpubControl("prev", px(parts0[SheetBarPart.back]!),
            data: {"frames": onsets}, label: "A note back"),
        // A range of bars: play starts at its first bar (if the playhead is
        // not in it) and stops at the end of its last.
        s.fromBar > 0 || s.toBar > 0
            ? EpubControl("range", px(play),
                data: {"from": "$from", "to": "$to"},
                inner: pause,
                label: "Play")
            : EpubControl("toggle", px(play), inner: pause, label: "Play"),
        EpubControl("next", px(parts0[SheetBarPart.on]!),
            data: {"frames": onsets}, label: "A note on"),
        EpubControl("seek", px(track),
            data: {"from": "$from", "to": "$to"}, label: "How far it has got"),
      ];
    }
    return _layerOf(parts, controls: controls);
  }

  /// _keysLayer is an instrument as a book plays it: its keys at rest, and
  /// each key it plays lit, a picture of its own there while it sounds.
  Future<EpubLayer?> _keysLayer(AudioElement a) async {
    var part = a.instrument!;
    var bounds = a.bounds;
    var parts = <EpubPart>[];
    var rest = await drawn(
        (c) => paintAudio(c, bounds, a, AudioState(muted: a.clip.muted)),
        bounds);
    if (rest != null) parts.add(EpubPart(rest));
    // The frames each key sounds on: by the right hand, and by the left
    // on a piano's part, each lit in its own colour.
    var on = <int, Set<int>>{}, leftOn = <int, Set<int>>{};
    for (var f = 0; f < frames; f++) {
      var state = AudioState.atFrame(a, f, rate, doc: page);
      for (var k in state.keys) {
        (state.left.contains(k) ? (leftOn[k] ??= {}) : (on[k] ??= {})).add(f);
      }
    }
    var layout = keyboardLayout(part, bounds);
    // Each key lit: shown while the page plays it, and while the reader
    // presses it. White keys first, the black ones over them.
    var lit = <({int key, Rect rect, bool black, EpubSprite lit})>[];
    for (var black in [false, true]) {
      for (var key in layout.keys) {
        if (key.black != black) continue;
        var pic = await drawn(
            (c) => paintAudio(
                c, bounds, a, AudioState(muted: a.clip.muted, keys: {key.key})),
            key.rect);
        if (pic == null) continue;
        lit.add((
          key: key.key,
          rect: Rect.fromLTRB(
              (key.rect.left - bounds.left) * pixels,
              (key.rect.top - bounds.top) * pixels,
              (key.rect.right - bounds.left) * pixels,
              (key.rect.bottom - bounds.top) * pixels),
          black: key.black,
          lit: pic
        ));
        if (on[key.key] case var frames0?) {
          parts.add(EpubPart(pic, keys: _onOff(frames0.contains)));
        }
        if (leftOn[key.key] case var frames1?) {
          var leftPic = await drawn(
              (c) => paintAudio(
                  c,
                  bounds,
                  a,
                  AudioState(
                      muted: a.clip.muted, keys: {key.key}, left: {key.key})),
              key.rect);
          if (leftPic != null) {
            parts.add(EpubPart(leftPic, keys: _onOff(frames1.contains)));
          }
        }
      }
    }
    // Its sound, for the reader to play it.
    EpubKeyboard? keyboard;
    if (await _keySounds(a, [for (var k in lit) k.key])
        case (var file, var low)?) {
      clips.add(file);
      keyboard = EpubKeyboard(
          Rect.fromLTRB(bounds.left * pixels, bounds.top * pixels,
              bounds.right * pixels, bounds.bottom * pixels),
          lit,
          file.href,
          low,
          keyStep);
    }
    return _layerOf(parts, keyboard: keyboard);
  }

  /// _synthKeysLayer is a synth's keyboard module as a book plays it: the
  /// module at rest, each key lit while pressed, and the keys' sounds -- the
  /// patch as set, rendered through the speaker it is patched to (knobs are
  /// not turned in a book). Null where it reaches no speaker.
  Future<EpubLayer?> _synthKeysLayer(SynthModuleElement keys) async {
    var speaker = synthSpeakersHearing(page, keys.id).firstOrNull;
    var ch = speaker == null ? null : page.elementById(speaker.channel);
    if (ch is! AudioElement || ch.instrument == null) return null;
    var bounds = keys.bounds;
    var parts = <EpubPart>[];
    var rest = await drawn((c) => paintSynthModule(c, bounds, keys), bounds);
    if (rest != null) parts.add(EpubPart(rest));
    var panel = synthPanelFor(keys);
    var (s, at) = synthPanelFit(bounds, panel);
    Rect onPage(Rect r) => Rect.fromLTRB(at.dx + r.left * s, at.dy + r.top * s,
        at.dx + r.right * s, at.dy + r.bottom * s);
    var kr = panel.keys!;
    var ww = kr.width / synthKeyboardWhites.length;
    var places = [
      for (var (i, k) in synthKeyboardWhites.indexed)
        (k, Rect.fromLTWH(kr.left + i * ww, kr.top, ww, kr.height), false),
      for (var (k, r) in synthBlackKeys(kr)) (k, r, true),
    ];
    var lit = <({int key, Rect rect, bool black, EpubSprite lit})>[];
    for (var (key, r, black) in places) {
      var rect = onPage(r);
      var pic = await drawn(
          (c) =>
              paintSynthModule(c, bounds, keys, show: SynthShow(held: {key})),
          rect);
      if (pic == null) continue;
      lit.add((
        key: key,
        rect: Rect.fromLTRB(
            (rect.left - bounds.left) * pixels,
            (rect.top - bounds.top) * pixels,
            (rect.right - bounds.left) * pixels,
            (rect.bottom - bounds.top) * pixels),
        black: black,
        lit: pic
      ));
    }
    EpubKeyboard? keyboard;
    if (await _keySounds(ch, [for (var k in lit) k.key])
        case (var file, var low)?) {
      clips.add(file);
      keyboard = EpubKeyboard(
          Rect.fromLTRB(bounds.left * pixels, bounds.top * pixels,
              bounds.right * pixels, bounds.bottom * pixels),
          lit,
          file.href,
          low,
          keyStep);
    }
    return _layerOf(parts, keyboard: keyboard);
  }

  /// _encodedKeys is an instrument's keys as encoded, by what they sound
  /// like: the same piano on every page is encoded once.
  static final _encodedKeys = <String, Uint8List>{};

  /// keyStep is how far apart each key's sound is in an instrument's file:
  /// a note held a second, and its ring.
  static const keyStep = 1.6;

  /// _keySounds is [a]'s keys from the lowest of [keys] to the highest, as
  /// [a] plays them, [keyStep] seconds apart in one file (AAC with ffmpeg,
  /// else WAV), with the lowest's number; null where unplayable.
  Future<(EpubFile, int)?> _keySounds(AudioElement a, List<int> keys) async {
    if (keys.isEmpty) return null;
    var part = a.instrument!;
    var low = keys.reduce(math.min), high = keys.reduce(math.max);
    var notes = [
      for (var k = low; k <= high; k++)
        MidiNote(k, (k - low) * keyStep, 1.0, 100),
    ];
    try {
      var bank = await soundBankPath();
      var wav = await partWav(
          part.copyWith(notes: notes, effects: const [], controls: const {}),
          bankPath:
              part.sound == InstrumentSound.bank && await File(bank).exists()
                  ? bank
                  : null);
      var ffmpeg = films?.ffmpeg ?? await ffmpegPath();
      // Named by what it sounds like, not by the element: a book whose every
      // lesson has the same piano carries its keys once (the writer keeps
      // one file per name), not once a page -- ten copies made a 17 MB
      // book of a 7 MB one (Ken, 2026-11-19).
      var sound = sha1.convert(wav).toString().substring(0, 16);
      var stem = "media/keys-$sound";
      if (ffmpeg == null) return (EpubFile("$stem.wav", wav, "audio/wav"), low);
      if (_encodedKeys[sound] case var done?) {
        return (EpubFile("$stem.m4a", done, "audio/mp4"), low);
      }
      var work = await Directory.systemTemp.createTemp("canvas-keys");
      try {
        var input = path.join(work.path, "keys.wav");
        var output = path.join(work.path, "keys.m4a");
        await File(input).writeAsBytes(wav);
        var run = await Process.run(ffmpeg, [
          "-hide_banner", "-loglevel", "error", "-y", //
          "-i", input, "-ac", "1", "-c:a", "aac", "-b:a", "96k", output,
        ]);
        if (run.exitCode != 0) {
          return (EpubFile("$stem.wav", wav, "audio/wav"), low);
        }
        var bytes = await File(output).readAsBytes();
        // Kept for the pages after this one with the same keys, so they
        // are encoded once; only the last few, as a book has few pianos.
        if (_encodedKeys.length >= 8) _encodedKeys.remove(_encodedKeys.keys.first);
        _encodedKeys[sound] = bytes;
        return (EpubFile("$stem.m4a", bytes, "audio/mp4"), low);
      } finally {
        await work.delete(recursive: true);
      }
    } catch (exception) {
      debugPrint("Unable to sound the keys: $exception");
      return null;
    }
  }

  /// _reactions are [e]'s clips started by a click or a clip, each sampled
  /// frame by frame alone, with the sound linked with it in its row.
  List<EpubReaction> _reactions() {
    var out = <EpubReaction>[];
    var m = e.base.motion;
    for (var c in _reactionClips(e)) {
      var n = math.max(1, (c.span * rate).round());
      // The element with this clip alone on its timeline, from frame 0, on the
      // page, so a Go to finds what it goes to.
      var alone = e.withBase(
          motion: m.copyWith(placed: [
        ClipPlacement(id: "rx-${c.id}", clip: c.id, layer: c.layer, start: 0),
      ]));
      var on = page.withElement(alone);
      var css = [
        for (var f = 0; f <= n; f++)
          if (poseWithMotion(alone, f, on) case var k)
            {
              "transform": "translate(${_n(k.dx * pixels, 2)}px,"
                  "${_n(k.dy * pixels, 2)}px) rotate(${_n(k.rotate, 3)}deg) "
                  "scale(${_n(k.scale, 4)})",
              "opacity": _n(k.opacity.clamp(0.0, 1.0).toDouble(), 3),
            },
      ];
      var row = m.slots.indexOf(c.id);
      var own = e is VideoElement && (e as VideoElement).clip.channel.isEmpty
          ? e.id
          : "snd-${e.id}";
      var linked =
          row >= 0 && m.isLinked(row) ? page.session.at(own, row) : null;
      var file = linked?.sound == null ? null : sounds[linked!.sound!.assetId];
      for (var t in c.triggers) {
        var on = switch (t.kind) {
          ClipTriggerKind.clicked when t.target.isNotEmpty =>
            "click:${t.target}",
          ClipTriggerKind.clipEnds => "end:${t.target}",
          _ => null,
        };
        if (on == null) continue;
        out.add(EpubReaction(c.id, on, n, _compact(css),
            sound: file,
            volume: linked == null
                ? 1
                : math.pow(10, linked.gain / 20).clamp(0.0, 1.0).toDouble()));
      }
    }
    return out;
  }

  /// _legend is the chart with each set of its key's series switched, by
  /// mask: a picture for each, as it is once it has grown.
  Future<Map<int, EpubSprite>> _legend() async {
    var chart = e;
    var series = _switchable(chart);
    if (chart is! ChartElement || series.isEmpty) return const {};
    var out = <int, EpubSprite>{};
    for (var mask = 1; mask < 1 << series.length; mask++) {
      var flipped = [...chart.data.series];
      for (var (bit, (at, _)) in series.indexed) {
        if (mask & (1 << bit) != 0) {
          flipped[at] = flipped[at].copyWith(hidden: !flipped[at].hidden);
        }
      }
      var switched = chart.copyWith(data: chart.data.copyWith(series: flipped));
      if (await picture(frames - 1, element: switched) case var s?) {
        out[mask] = s;
      }
    }
    return out;
  }

  /// _poseKeys is where the element is, frame by frame, as CSS about its
  /// centre -- or nothing, where it stays where it was put.
  List<EpubKey> _poseKeys() {
    var css = [
      for (var f = 0; f < frames; f++)
        if (poseAt(f) case var k)
          {
            "transform": "translate(${_n(k.dx * pixels, 2)}px,"
                "${_n(k.dy * pixels, 2)}px) rotate(${_n(k.rotate, 3)}deg) "
                "scale(${_n(k.scale, 4)})",
            "opacity": _n(k.opacity.clamp(0.0, 1.0).toDouble(), 3),
          },
    ];
    var keys = _compact(css);
    if (keys.length == 1 &&
        keys.single.css["transform"] ==
            "translate(0px,0px) rotate(0deg) scale(1)" &&
        keys.single.css["opacity"] == "1") {
      return const [];
    }
    return keys;
  }

  /// _cssAble is whether everything [e] does besides its pose is a motion
  /// the renderer applies through applyMotionSpec, which CSS can do too.
  bool _cssAble() {
    // Nothing but the arrival and the leaving changes.
    String others(int f) {
      var v = {...poseAt(f).values}
        ..remove(KeyframeChannel.reveal)
        ..remove(KeyframeChannel.close);
      var keys = v.keys.toList()..sort();
      return keys.map((k) => "$k=${v[k]}").join(";");
    }

    var first = others(0);
    for (var f = 1; f < frames; f++) {
      if (others(f) != first) return false;
    }
    switch (e) {
      case TextElement t:
        var a = t.animation;
        return t.wordsSetIn(page) != WordsSet.onLine &&
            (!a.on || wholeBlockMotion(a.preset.motion)) &&
            (!a.closes || wholeBlockMotion(a.exit.motion)) &&
            // A part of the words with an animation of its own moves on its
            // own clock inside the element's -- filmed, not cut.
            t.parts.every(
                (part) => part.animation.preset == TextAnimationPreset.none);
      case ChartElement _:
      case TeamElement _:
      case BackgroundElement _:
        return false;
      default:
        var a = _elementAnimation(e);
        return a != null && !a.cuts;
    }
  }

  /// _cssParts is [e] as pictures moved by CSS, read off the renderer frame
  /// by frame, or null where what it does cannot be read that way.
  Future<List<EpubPart>?> _cssParts() async {
    // Ask the renderer, frame by frame, what it moves and how, only over the
    // stretch where the element arrives or leaves.
    var span = _valuedSpan(e, frames, poseAt);
    if (span == null) return null;
    var calls = <int, List<MotionCall>>{};
    for (var f = math.max(0, span.$1);
        f <= math.min(frames - 1, span.$2 + 1);
        f++) {
      var seen = <MotionCall>[];
      motionProbe = seen.add;
      try {
        record(f).dispose();
      } finally {
        motionProbe = null;
      }
      calls[f] = seen;
    }

    // The pieces: whatever the renderer moved, known by where it was before
    // it moved it (the same box at every frame).
    String keyOf(MotionCall c) {
      var b = c.before;
      return "${c.box.left.toStringAsFixed(2)},${c.box.top.toStringAsFixed(2)},"
          "${c.box.width.toStringAsFixed(2)},${c.box.height.toStringAsFixed(2)}"
          "@${[
        b[0],
        b[1],
        b[4],
        b[5],
        b[12],
        b[13]
      ].map((v) => v.toStringAsFixed(3)).join(",")}";
    }

    var pieces = <String, MotionCall>{};
    for (var list in calls.values) {
      for (var c in list) {
        pieces.putIfAbsent(keyOf(c), () => c);
      }
    }
    if (pieces.isEmpty) return null;
    var byPiece = e is TextElement &&
        (e as TextElement).animation.preset.scope != TextAnimationScope.block;
    // A whole-element motion that moves it in several pieces (columns, each
    // on its own) would cut the picture wrongly.
    if (!byPiece && pieces.length > 1) return null;

    // As it is once arrived, and what of it never moves at all: a box behind
    // text, say, which is there before the words are.
    Keyframe settledWith(double reveal) => Keyframe(frame: 0, values: {
          ...poseAt(0).values,
          KeyframeChannel.reveal: reveal,
          KeyframeChannel.close: 0,
        });
    // Its clips set aside: these are it at one fixed pose.
    var settled = e.withBase(
        track: ElementTrack([settledWith(1)]), motion: ElementMotion.none);
    var bare = e.withBase(
        track: ElementTrack([settledWith(0)]), motion: ElementMotion.none);

    var parts = <EpubPart>[];
    if (await picture(0, element: bare) case var s?) parts.add(EpubPart(s));

    // Text in a box arriving word by word: the words are cut from it
    // drawn boxless, the box a picture of its own from the arrival's
    // start, so it does not go in slices with them.
    var words = settled;
    if (byPiece && settled is TextElement) {
      var t = settled;
      var b = t.box;
      if (b.fill.a > 0 || (b.borderWidth > 0 && b.borderColor.a > 0)) {
        const none = ui.Color(0x00000000);
        words = t.copyWith(
            box: b.copyWith(
                fill: none,
                borderColor: none,
                flatFill: true,
                flatBorder: true));
        var boxOnly = t.copyWith(textSpec: t.textSpec.copyWith(color: none));
        if (await picture(0, element: boxOnly) case var s?) {
          var from = math.max(0, span.$1);
          parts.add(EpubPart(s, keys: [
            const EpubKey(0, {"opacity": "0"}),
            if (from > 1) EpubKey(from - 1, const {"opacity": "0"}),
            EpubKey(from, const {"opacity": "1"}),
            // Held to the last frame: a last key short of it runs on to the
            // style written inline, the first key's, hidden.
            if (frames - 1 > from) EpubKey(frames - 1, const {"opacity": "1"}),
          ]));
        }
      }
    }

    var whole = record(0, element: words);
    try {
      for (var entry in pieces.entries) {
        var c = entry.value;
        // A piece is its box, and a little above and below it for what reaches
        // past a line, as the renderer clips each piece.
        var crop = byPiece
            ? _mapRect(
                c.before,
                Rect.fromLTRB(c.box.left, c.box.top - c.box.height * 0.3,
                    c.box.right, c.box.bottom + c.box.height * 0.3))
            : region;
        var sprite = await sheets.add(whole, crop);
        if (sprite == null) continue;
        parts.add(_moved(sprite, entry.key, calls, keyOf));
      }
    } finally {
      whole.dispose();
    }
    return parts;
  }

  /// _moved is one piece's keyframes, from what the renderer did to it.
  EpubPart _moved(EpubSprite sprite, String key,
      Map<int, List<MotionCall>> calls, String Function(MotionCall) keyOf) {
    var blurs = false, clips = false;
    var at = <int, MotionCall>{};
    for (var MapEntry(key: f, value: list) in calls.entries) {
      for (var c in list) {
        if (keyOf(c) == key) {
          at[f] = c;
          if (c.blur > 0) blurs = true;
          if (c.clip != null) clips = true;
        }
      }
    }
    // Where the renderer did not move it, it is either there or not.
    bool there(int f) {
      var v = poseAt(f).values;
      return (v[KeyframeChannel.reveal] ?? 1) >= 1 &&
          (v[KeyframeChannel.close] ?? 0) <= 0;
    }

    const everything = "polygon(-100000px -100000px, 100000px -100000px, "
        "100000px 100000px, -100000px 100000px)";
    var looks = <Map<String, String>>[];
    var frames_ = <Map<String, String>>[];
    for (var f = 0; f < frames; f++) {
      var c = at[f];
      if (c == null) {
        looks.add({
          "transform": "matrix(1,0,0,1,0,0)",
          "opacity": there(f) ? "1" : "0",
          if (blurs) "filter": "blur(0px)",
        });
        if (clips) frames_.add({"clip-path": everything});
        continue;
      }
      var m = _mul(c.after, _invert(c.before));
      var scale = math
          .sqrt((c.before[0] * c.before[5] - c.before[1] * c.before[4]).abs());
      looks.add({
        "transform": "matrix(${_n(m[0], 5)},${_n(m[1], 5)},${_n(m[4], 5)},"
            "${_n(m[5], 5)},${_n(m[12], 2)},${_n(m[13], 2)})",
        "opacity": _n(c.frame.alpha.clamp(0.0, 1.0).toDouble(), 3),
        if (blurs) "filter": "blur(${_n(c.blur * scale, 2)}px)",
      });
      if (clips) {
        var clip = c.clip;
        if (clip == null) {
          frames_.add({"clip-path": everything});
        } else {
          var corners = [
            clip.topLeft,
            clip.topRight,
            clip.bottomRight,
            clip.bottomLeft,
          ].map((p) => _mapPoint(c.before, p) - Offset(sprite.x, sprite.y));
          frames_.add({
            "clip-path":
                "polygon(${corners.map((p) => "${_n(p.dx, 2)}px ${_n(p.dy, 2)}px").join(", ")})",
          });
        }
      }
    }
    return EpubPart(sprite,
        keys: _compact(looks), clipKeys: clips ? _compact(frames_) : const []);
  }

  /// _film makes [e]'s change a video of it alone, over its frames.
  Future<EpubClip?> _film(List<String> names) async {
    var films = this.films!;
    int a, b;
    if (media != null) {
      a = 0;
      b = frames - 1;
    } else {
      var changed = [
        for (var i = 1; i < names.length; i++)
          if (names[i] != names[i - 1]) i,
      ];
      if (changed.isEmpty) return null;
      a = changed.first - 1;
      b = changed.last;
    }
    // Even sides: neither encoder takes an odd one.
    var box = Rect.fromLTWH(region.left, region.top,
        (region.width / 2).ceil() * 2.0, (region.height / 2).ceil() * 2.0);
    var w = box.width.round(), h = box.height.round();

    // What is under it, holding still: with HEVC alpha, only for half-clear
    // pixels (see _solidOrClear); without, it is filmed over this.
    ui.Picture under;
    {
      var recorder = ui.PictureRecorder();
      var canvas = start(recorder);
      paintCanvasDocument(canvas, page,
          part: CanvasPaintPart.backdrop, images: images);
      _paintFacing(canvas, page, index, images);
      for (var x in below) {
        paintElement(canvas, x, 0,
            frameRate: page.frameRate, images: images, document: page);
      }
      under = recorder.endRecording();
    }

    Directory? work;
    Process? running;
    try {
      work = await Directory.systemTemp.createTemp("canvas-element-film");
      var out = path.join(work.path, "clip.mp4");
      var process = running = await Process.start(films.ffmpeg, [
        "-hide_banner", "-loglevel", "error", "-y", //
        "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "${w}x$h",
        "-r", "$rate", "-i", "-",
        // Tagged sRGB, as drawn: untagged, a reader assumes the TV
        // curve and the film stops matching the element's picture.
        "-vf",
        [
          if (!films.alpha) "scale=out_color_matrix=bt709:out_range=tv",
          "setparams=color_primaries=bt709:color_trc=iec61966-2-1:"
              "colorspace=bt709:range=tv",
        ].join(","),
        if (films.alpha) ...[
          "-c:v",
          "hevc_videotoolbox",
          "-q:v",
          "60",
          "-alpha_quality",
          "0.9",
          "-tag:v",
          "hvc1",
        ] else ...[
          "-c:v",
          "libx264",
          "-preset",
          "veryfast",
          "-crf",
          "18",
          "-pix_fmt",
          "yuv420p",
        ],
        // A picture whole every second, so a page that jumps to a frame
        // finds it without decoding from the start.
        "-g", "$rate",
        "-movflags", "+faststart+write_colr",
        out,
      ]);
      var errors = StringBuffer();
      process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(errors.write);
      Future<Uint8List?> pixels(ui.Picture over, {bool onPage = false}) async {
        var recorder = ui.PictureRecorder();
        var canvas = ui.Canvas(recorder)..translate(-box.left, -box.top);
        if (onPage) canvas.drawPicture(under);
        canvas.drawPicture(over);
        var framed = recorder.endRecording();
        try {
          var image = await framed.toImage(w, h);
          try {
            var raw = await image.toByteData(
                format: ui.ImageByteFormat.rawStraightRgba);
            return raw?.buffer.asUint8List();
          } finally {
            image.dispose();
          }
        } finally {
          framed.dispose();
        }
      }

      for (var f = a; f <= b; f++) {
        var show = media == null ? null : await media!.at(f);
        var p = record(f, videoShow: show);
        try {
          var onPage = await pixels(p, onPage: true);
          if (onPage == null) break;
          if (films.alpha) {
            var alone = await pixels(p);
            if (alone == null) break;
            _solidOrClear(alone, onPage);
            process.stdin.add(alone);
          } else {
            process.stdin.add(onPage);
          }
          await process.stdin.flush();
        } finally {
          p.dispose();
        }
      }
      await process.stdin.close();
      if (await process.exitCode != 0 || !await File(out).exists()) {
        debugPrint("Unable to film ${e.id} for the book: $errors");
        return null;
      }
      var href = "media/p$index-${_safe(e.id)}.mp4";
      clips.add(EpubFile(href, await File(out).readAsBytes(), "video/mp4"));
      return EpubClip(href, a, b - a + 1, box,
          before: await picture(a), after: await picture(b));
    } catch (exception) {
      debugPrint("Unable to film ${e.id} for the book: $exception");
      // Not left waiting on its input for as long as the app runs.
      running?.kill();
      return null;
    } finally {
      under.dispose();
      try {
        await work?.delete(recursive: true);
      } catch (_) {}
    }
  }
}

/// _solidOrClear makes each pixel of [alone] clear or solid, a half-clear
/// one taking its colour over the page from [onPage]: Apple Books treats
/// video as premultiplied, so half-clear pixels come out too bright.
/// Exact because what is under the element holds still.
void _solidOrClear(Uint8List alone, Uint8List onPage) {
  var mine = alone.buffer.asUint32List(alone.offsetInBytes, alone.length >> 2);
  var page =
      onPage.buffer.asUint32List(onPage.offsetInBytes, onPage.length >> 2);
  for (var i = 0; i < mine.length; i++) {
    var a = mine[i] >> 24;
    if (a == 0) {
      mine[i] = 0;
    } else if (a != 0xFF) {
      mine[i] = page[i] | 0xFF000000;
    }
  }
}

/// _elementAnimation is the arrival of the kinds that have one of their own.
ElementAnimation? _elementAnimation(CanvasElement e) => switch (e) {
      ShapeElement e => e.animation,
      ImageElement e => e.animation,
      VectorElement e => e.animation,
      LineElement e => e.animation,
      PathElement e => e.animation,
      TableElement e => e.animation,
      CounterElement e => e.animation,
      ButtonElement e => e.animation,
      AudioElement e => e.animation,
      VideoElement e => e.animation,
      Character3dElement e => e.animation,
      _ => null,
    };
