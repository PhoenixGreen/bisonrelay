part of '../canvas_controller.dart';

// Staging: lip sync from a take's words, the 3D stage and backdrops a scene is
// filmed on, and the keys the stage's camera and spots take. Part of
// CanvasController: its fields and lifecycle are in canvas_controller.dart.

extension CanvasStaging on CanvasController {
  /// lipSync gives [e] mouths for what [voice] says: from the words (heard
  /// first if need be), or from loudness alone with [words] off. Replaces
  /// its earlier mouths over the stretch, as one undo step. Returns what
  /// stopped it, or how many mouths it laid.
  Future<({String? problem, int mouths})> lipSync(
      CanvasElement e, AudioElement voice,
      {bool words = true, LipSyncFeel feel = const LipSyncFeel()}) async {
    var source = voice.clip.playlist.firstOrNull;
    if (source == null) {
      return (problem: "That sound has nothing in it to hear.", mouths: 0);
    }
    var rate = math.max(1, _document.frameRate);
    var length = source.length > 0 ? source.length : 0.0;
    var from = source.start, to = source.end > 0 ? source.end : length;
    // Where the voice starts and stops in the run, and the character's frames.
    var voiceAt = _clipOffset(voice) + voice.clip.at;
    var voiceEnd = voiceAt + ((to - from) * rate).ceil();
    var mine = _clipOffset(e);

    List<MouthKey> keys;
    if (words) {
      var tag = "voice:${voice.id}";
      // A Speech take knows its words and timing: read, not heard again.
      var said = _takeWords(voice, voiceAt, rate) ??
          [
            for (var w in this.words)
              if (w.from == tag) w,
          ];
      if (said.isEmpty) {
        var problem = await hearWords(voice);
        if (problem != null) return (problem: problem, mouths: 0);
        said = [
          for (var w in this.words)
            if (w.from == tag) w,
        ];
      }
      keys = mouthsFromWords(said, frameRate: rate, feel: feel);
    } else {
      if (length <= 0) {
        return (
          problem: "That recording's length is not known yet.",
          mouths: 0
        );
      }
      var file =
          await CanvasMedia.existingPath(MediaKind.audio, source.assetId);
      if (file == null) {
        return (
          problem: "The recording is missing from the library.",
          mouths: 0
        );
      }
      // A hundred readings a second: the timeline's own waveform is too thin
      // for a mouth on a long recording.
      var count = math.max(1, (length * 100).ceil());
      var peaks = await audio.engine.peaks(file, count);
      if (peaks == null) {
        return (problem: "That recording could not be read.", mouths: 0);
      }
      var a = (from / length * count).floor().clamp(0, count);
      var b = (to / length * count).ceil().clamp(a, count);
      keys = mouthsFromLoudness(Float32List.sublistView(peaks, a, b), to - from,
          startFrame: voiceAt, frameRate: rate, feel: feel);
    }

    // Read again: the character may have been changed while listening.
    var now = _document.elementById(e.id);
    if (now is Character3dElement) {
      // A 3D character's mouths are in seconds of its own scene.
      var local = [
        for (var k in keys)
          if (k.frame - mine >= 0) (t: (k.frame - mine) / rate, shape: k.shape),
      ];
      replaceElement(now.performing(now.performance.withMouths(local,
          from: math.max(0, voiceAt - mine - feel.lead - 1) / rate,
          to: (voiceEnd - mine + 1) / rate)));
      return (problem: null, mouths: local.length);
    }
    return (problem: null, mouths: 0);
  }

  /// _takeWords are [voice]'s words where it is a Speech device's take, as
  /// run frames from [voiceAt], kept by its trim; null for any other sound.
  List<SpokenWord>? _takeWords(AudioElement voice, int voiceAt, int rate) {
    var source = voice.clip.playlist.firstOrNull;
    if (source == null) return null;
    var take = voice.clip.mix.speech?.takes
        .where((t) => t.assetId == source.assetId)
        .firstOrNull;
    if (take == null || take.words.isEmpty) return null;
    var end = source.end > 0 ? source.end : take.length;
    return [
      for (var w in take.words)
        if (w.end > source.start && w.start < end)
          SpokenWord(
              text: w.text,
              frame: voiceAt + ((w.start - source.start) * rate).round(),
              end: voiceAt + ((w.end - source.start) * rate).round(),
              from: "voice:${voice.id}"),
    ];
  }

  /// clearLipSync takes every mouth off [e], a 3D character.
  void clearLipSync(CanvasElement e) => replaceElement(switch (e) {
        Character3dElement c => c.performing(c.performance.withMouths(const [])),
        _ => e,
      });

  /// stageFilmed is [stage] with its camera at [camera]: its own setting
  /// until the camera is keyed, then this frame's key.
  StageElement stageFilmed(StageElement stage, StageCamera camera) {
    var keyed = stage.track?.keys
            .any((k) => k.values.keys.any((c) => c.startsWith("cam."))) ??
        false;
    if (!keyed) return stage.copyWith(camera: camera);
    return stage.withBase(
            track: _pinnedAt(stage.track!, _frame, camera.channels))
        as StageElement;
  }

  /// stageOf is the stage called [id] as it is drawn on this canvas: a
  /// Background element showing one, or the background behind the canvas.
  StageElement? stageOf(String id) => stageNamed(id, _document.elements,
      backdrop: _document.drawnBackground, page: _document.size.rect);

  /// putStage writes [stage] back where it lives (see putBackdrop), its
  /// settings and its camera's keys both.
  void putStage(StageElement stage, {bool transient = false}) =>
      putBackdrop(stage, transient: transient);

  /// parallaxOf is the parallax scenery [id] as drawn, as [stageOf] is.
  ParallaxElement? parallaxOf(String id) {
    if (id == backgroundParallaxId) {
      var bg = _document.drawnBackground;
      return bg.isParallax ? bg.parallaxOn(_document.size.rect) : null;
    }
    if (_document.elementById(id) case BackgroundElement b
        when b.isParallax) {
      return b.parallaxed;
    }
    return null;
  }

  /// parallaxFilmed is [p] with its camera at [camera], as [stageFilmed].
  ParallaxElement parallaxFilmed(ParallaxElement p, ParallaxCamera camera) {
    if (!_cameraKeyed(p)) return p.copyWith(camera: camera);
    return p.withBase(track: _pinnedAt(p.track!, _frame, camera.channels))
        as ParallaxElement;
  }

  /// putBackdrop writes a stage or a parallax back where it lives: its
  /// Background element, or the background behind the canvas.
  void putBackdrop(CanvasElement backdrop, {bool transient = false}) {
    var bg = _document.editedBackground;
    switch (backdrop) {
      case StageElement s when s.id == backgroundStageId:
        setBackground(bg.copyWith(backdrop: BackdropKind.stage, stage: s),
            transient: transient);
        return;
      case ParallaxElement p when p.id == backgroundParallaxId:
        setBackground(
            bg.copyWith(backdrop: BackdropKind.parallax, parallax: p),
            transient: transient);
        return;
    }
    if (_document.elementById(backdrop.id) case BackgroundElement b) {
      switch (backdrop) {
        case StageElement s:
          replaceElement(b.withStage(s), transient: transient);
          return;
        case ParallaxElement p:
          replaceElement(b.withParallax(p), transient: transient);
          return;
      }
    }
    replaceElement(backdrop, transient: transient);
  }

  /// panAcross keys [p]'s camera to travel [distance] design units across
  /// the scene, from the first frame to the last.
  void panAcross(ParallaxElement p, double distance) {
    var last = math.max(1, _document.frames - 1);
    var from = p.cameraAt(0);
    var track = _pinnedAt(p.track ?? ElementTrack.empty, 0, from.channels);
    track =
        _pinnedAt(track, last, from.copyWith(x: from.x + distance).channels);
    putBackdrop(p.withBase(track: track));
  }

  bool _cameraKeyed(CanvasElement e) =>
      e.track?.keys.any((k) => k.values.keys.any((c) => c.startsWith("cam."))) ??
      false;

  /// _cameraNow and _cameraRest are a filmed backdrop's camera on this frame
  /// and its own setting, as keyframe channels.
  Map<String, double> _cameraNow(CanvasElement e) => switch (e) {
        StageElement s => s.cameraAt(_frame).channels,
        ParallaxElement p => p.cameraAt(_frame).channels,
        _ => const {},
      };

  Map<String, double> _cameraRest(CanvasElement e) => switch (e) {
        StageElement s => s.camera.channels,
        ParallaxElement p => p.camera.channels,
        _ => const {},
      };

  /// keyCamera keys [stage]'s camera on this frame, and on the first frame
  /// the first time, so the move starts where the camera was.
  void keyCamera(CanvasElement stage) {
    var track = stage.track ?? ElementTrack.empty;
    if (!_cameraKeyed(stage) && _frame != 0) {
      track = _pinnedAt(track, 0, _cameraRest(stage));
    }
    putBackdrop(
        stage.withBase(track: _pinnedAt(track, _frame, _cameraNow(stage))));
  }

  bool hasCameraKey(CanvasElement stage) =>
      stage.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("cam.")) ??
      false;

  void clearCameraKey(CanvasElement stage) {
    var track = stage.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.copyWith(values: {
      for (var v in at.values.entries)
        if (!v.key.startsWith("cam.")) v.key: v.value,
    });
    putBackdrop(stage.withBase(
        track: without.isRest && without.frame != 0
            ? track.withoutFrame(_frame)
            : track.withKey(without)));
  }

  bool spotKeyed(CanvasElement e) =>
      e.track?.keys.any((k) => k.values.keys.any((c) => c.startsWith("spot."))) ??
      false;

  /// spotted is [e] standing at [spot]: its own spot until keyed, then this
  /// frame's key. Its stage and how it stands are never keyed.
  CanvasElement spotted(CanvasElement e, StageSpot spot) {
    var own = e.base.spot;
    if (own == null || !spotKeyed(e)) return e.withBase(spot: spot);
    var kept = e.withBase(
        spot: own.copyWith(stage: spot.stage, stand: spot.stand));
    return kept.withBase(track: _pinnedAt(e.track!, _frame, spot.channels));
  }

  /// keySpot keys [e]'s spot here, and the first time frame 0 too.
  void keySpot(CanvasElement e) {
    var spot = e.spotAt(_frame);
    if (spot == null) return;
    var track = e.track ?? ElementTrack.empty;
    if (!spotKeyed(e) && _frame != 0) {
      track = _pinnedAt(track, 0, e.base.spot!.channels);
    }
    replaceElement(e.withBase(track: _pinnedAt(track, _frame, spot.channels)));
  }

  bool hasSpotKey(CanvasElement e) =>
      e.track
          ?.keyAt(_frame)
          ?.values
          .keys
          .any((c) => c.startsWith("spot.")) ??
      false;

  void clearSpotKey(CanvasElement e) {
    var track = e.track;
    var at = track?.keyAt(_frame);
    if (track == null || at == null) return;
    var without = at.copyWith(values: {
      for (var v in at.values.entries)
        if (!v.key.startsWith("spot.")) v.key: v.value,
    });
    replaceElement(e.withBase(
        track: without.isRest && without.frame != 0
            ? track.withoutFrame(_frame)
            : track.withKey(without)));
  }
}
