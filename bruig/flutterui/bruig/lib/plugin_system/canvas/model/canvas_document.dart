import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sprite_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/tile_map_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_looks.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// canvas_document.dart is a whole canvas: its shape, its background, what is
// on it, and how long it runs for. Immutable: every edit is a new document,
// so undo is a list and a painter never sees one change under it.

/// canvasFormatVersion is bumped when an older build would misread a saved
/// document. Never used to refuse one: every field reader has a fallback.
const int canvasFormatVersion = 1;

/// transitionSoundPrefix starts the id of every transition's sound.
const String transitionSoundPrefix = "transition-sound:";

/// defaultRateFor is how fast a document of this shape and kind runs: a
/// single page is a still at one frame a second, but a document of pages
/// runs at [defaultFrameRate], or its transitions would take a second a frame.
int defaultRateFor(CanvasRatio ratio, CanvasKind kind) =>
    kind.isPages ? defaultFrameRate : defaultFrameRateFor(ratio);

const int defaultFrameRate = 24;

/// defaultFrameCount is one frame: a still.
const int defaultFrameCount = 1;

/// maxFrameCount is the longest one scene may be: twenty minutes at
/// [audioFrameRate], a hundred at 24 a second.
const int maxFrameCount = 144000;

/// maxSceneElements and maxScenes are the most of each a canvas is read
/// with: far more than any canvas made here, and a received one's million
/// shapes would be drawn every frame.
const int maxSceneElements = 10000, maxScenes = 1000;

/// audioFrameRate is the steps a second a piece of sound's timeline counts
/// in: fine enough that any beat lands within a few milliseconds of a step.
const int audioFrameRate = 120;

/// maxSequenceFrames is the longest a whole document may run, every scene
/// end to end. It must stay well above [maxFrameCount], or a run of long
/// scenes is cut short.
const int maxSequenceFrames = maxFrameCount * 100;

/// CanvasBackground is what is behind the whole document: a pattern, a
/// stage or parallax scenery (see [backdrop]), with any picture, drawing and
/// video over it. Each is kept while another is shown, so trying one loses
/// nothing.
class CanvasBackground {
  final ProceduralSpec spec;

  /// picture, video and sound are elements, so their controls and painters
  /// serve here too. Each is stretched to the page when drawn, whatever box
  /// it was saved with; the sound is never drawn.
  final ImageElement? picture;
  final VideoElement? video;
  final AudioElement? sound;

  /// drawing is a vector drawing between the picture and the video.
  final VectorElement? drawing;

  /// backdrop is whether the pattern, [stage] or [parallax] is drawn.
  final BackdropKind backdrop;

  /// stage is the 3D stage, where [backdrop] says so; its camera's keys are
  /// on their own track. Its id is [backgroundStageId], which a character
  /// standing on it names.
  final StageElement? stage;

  /// parallax is the scenery, where [backdrop] says so; its camera's keys are
  /// on their own track under [backgroundParallaxId].
  final ParallaxElement? parallax;

  const CanvasBackground({
    this.spec = const ProceduralSpec(),
    this.picture,
    this.video,
    this.sound,
    this.drawing,
    this.backdrop = BackdropKind.flat,
    this.stage,
    this.parallax,
  });

  bool get isStage => backdrop == BackdropKind.stage;
  bool get isParallax => backdrop == BackdropKind.parallax;

  ParallaxElement parallaxOn(Rect rect) {
    var p = parallax ??
        const ParallaxElement(ElementBase(id: backgroundParallaxId));
    return p.withBase(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height) as ParallaxElement;
  }

  /// stageOn is the stage stretched to a page of [rect], as the picture and
  /// video are.
  StageElement stageOn(Rect rect) {
    var s = stage ?? defaultBackgroundStage;
    return s.withBase(
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height) as StageElement;
  }

  ImageElement? get shownPicture {
    if (picture case var p? when p.hasImage) return p;
    return null;
  }

  bool get isImage => shownPicture != null;

  List<CanvasElement> get media => [
        if (video case var v? when !v.clip.isEmpty) v,
        if (sound case var a? when !a.clip.isEmpty) a,
      ];

  Set<String> get assetIds => {
        ...?shownPicture?.assetIds,
        ...?video?.assetIds,
        ...?drawing?.assetIds,
        ...?parallax?.assetIds,
      };

  Set<String> get mediaIds => {
        ...?video?.mediaIds,
        ...?sound?.mediaIds,
        ...?drawing?.mediaIds,
      };

  CanvasBackground copyWith({
    ProceduralSpec? spec,
    ImageElement? picture,
    VideoElement? video,
    AudioElement? sound,
    VectorElement? drawing,
    bool clearPicture = false,
    bool clearVideo = false,
    bool clearSound = false,
    bool clearDrawing = false,
    BackdropKind? backdrop,
    StageElement? stage,
    ParallaxElement? parallax,
  }) =>
      CanvasBackground(
        backdrop: backdrop ?? this.backdrop,
        stage: stage ?? this.stage,
        parallax: parallax ?? this.parallax,
        spec: spec ?? this.spec,
        picture: clearPicture ? null : picture ?? this.picture,
        video: clearVideo ? null : video ?? this.video,
        sound: clearSound ? null : sound ?? this.sound,
        drawing: clearDrawing ? null : drawing ?? this.drawing,
      );

  Map<String, dynamic> toJson() => {
        "spec": spec.toJson(),
        if (picture != null) "picture": picture!.toJson(),
        if (video != null) "video": video!.toJson(),
        if (sound != null) "sound": sound!.toJson(),
        if (drawing != null) "drawing": drawing!.toJson(),
        if (backdrop != BackdropKind.flat) "backdrop": backdrop.name,
        if (stage != null) "stage": stage!.toJson(),
        if (parallax != null) "parallax": parallax!.toJson(),
      };

  factory CanvasBackground.fromJson(Map<String, dynamic> json) {
    T? element<T>(dynamic raw) =>
        raw is Map<String, dynamic> && elementFromJson(raw) is T
            ? elementFromJson(raw) as T
            : null;
    return CanvasBackground(
      spec: jsonSpec(
          json["spec"], ProceduralSpec.fromJson, const ProceduralSpec()),
      picture: element<ImageElement>(json["picture"]),
      video: element<VideoElement>(json["video"]),
      sound: element<AudioElement>(json["sound"]),
      drawing: element<VectorElement>(json["drawing"]),
      backdrop: BackdropKind.fromName(jsonStr(json["backdrop"])),
      // Read as a stage directly: elementFromJson reads no stage of its own,
      // only one inside a Background element.
      stage: json["stage"] is Map<String, dynamic>
          ? StageElement.fromJson(
              json["stage"] as Map<String, dynamic>,
              ElementBase.fromJson(
                  json["stage"] as Map<String, dynamic>, "3D stage"))
          : null,
      parallax: json["parallax"] is Map<String, dynamic>
          ? ParallaxElement.fromJson(
              json["parallax"] as Map<String, dynamic>,
              ElementBase.fromJson(
                  json["parallax"] as Map<String, dynamic>, "Parallax"))
          : null,
    );
  }
}

/// defaultBackgroundStage is the stage a background first becomes.
const StageElement defaultBackgroundStage =
    StageElement(ElementBase(id: backgroundStageId, name: "3D stage"));

class CanvasDocument {
  /// title is the library name, not the filename (canvas_storage.dart
  /// sanitises one into the other).
  final String title;

  final CanvasSize size;
  final CanvasBackground background;

  /// guides is the grid, guide lines, rulers and snapping.
  final CanvasGuides guides;

  final CanvasKind kind;

  /// pages are the settings only a document of pages reads, carried whatever
  /// the kind so switching to Scenes and back forgets nothing.
  final PagesSpec pages;

  /// masterMix is the master strip every sound is summed through.
  final MasterMix masterMix;

  /// synced is [devices] with each Sync LFO given its rate at this
  /// document's tempo, since the engine knows no tempo; used for playing and
  /// exporting alike.
  List<MixDevice> synced(List<MixDevice> devices) =>
      tempoSynced(devices, audio.tempo, beatsPerBar: audio.beatsPerBar);

  MasterMix get syncedMaster =>
      masterMix.copyWith(devices: synced(masterMix.devices));
  List<ReturnChannel> get syncedReturns => [
        for (var r in returns) r.copyWith(devices: synced(r.devices)),
      ];

  /// audio is tempo, time signature, and how the sound is published.
  final AudioSettings audio;

  /// returns are the mixer's returns A, B, C. A new document has a reverb
  /// and a delay.
  final List<ReturnChannel> returns;

  /// session is the mixer's clip slots and scenes, launched live.
  final SessionGrid session;

  /// controls are each game action and the keys and buttons that press it.
  /// Null for defaultControls.
  final List<ControlAction>? controls;

  /// controlsNow are its controls, or the defaults where it has none.
  List<ControlAction> get controlsNow =>
      controls ??
      (players.length > 1 ? sharedDefaultControls : defaultControls);

  /// playerControls are players two to four's changed controls, by player.
  final Map<int, List<ControlAction>> playerControls;

  List<ControlAction> controlsFor(int player) => player <= 1
      ? controlsNow
      : playerControls[player] ?? defaultControlsFor(player);

  /// players are the players it is played by: one, at least.
  Set<int> get players => {
        1,
        for (var e in elements)
          if (e.base.play.as.moves) e.base.play.player,
      };

  /// counts are the numbers the game keeps, such as coins and lives.
  final List<GameCount> counts;

  /// gameStart is the id of the scene the game starts (and restarts) on, or
  /// "" for the one showing when Play is pressed.
  final String gameStart;

  /// game is whether it is being made into a game: the Game panel shows, and
  /// Play plays it.
  final bool game;

  /// hasCanvas is false for the Ratio "None" a piece of sound starts with.
  /// The size is kept underneath.
  final bool hasCanvas;

  /// scenes are the canvases played, in order. Empty means the one scene in
  /// the fields below. Either way [elements], [frames] and [actions] are the
  /// edited scene's.
  final List<CanvasScene> scenes;

  final int sceneAt;

  /// master is the scene shown on every other, or null. Kept while
  /// [masterOn] is off.
  final CanvasScene? master;
  final bool masterOn;

  /// masterOver draws the master over each scene, as a game's HUD.
  final bool masterOver;

  /// cast are elements kept once for every scene, of which scenes hold
  /// linked copies (see cast.dart). Not drawn themselves.
  final List<CanvasElement> cast;

  /// targets are the page shapes designed for, by ratio key (see shapeKey),
  /// in the reader's order; empty for one shape. Adding one gives every
  /// element a layout seeded from the current shape. See forShape.
  final List<String> targets;

  /// cues are the named moments of the whole run (canvas_cues.dart).
  final List<TimelineCue> cues;

  /// words are the voice-over and when, in frames of the whole run.
  final List<SpokenWord> words;

  /// textStyles are the named text styles, in the order made. Changing one
  /// changes every text that names it (TextElement.style), in every scene.
  final List<NamedTextStyle> textStyles;

  /// scores are the source of each part's notes, from which its instrument
  /// channel and any Sheet music element are made.
  final List<MusicScore> scores;

  /// sheets are the canvas's data: each Data element shows a range of one,
  /// kept in step by data_sync.dart.
  final List<DataSheet> sheets;

  /// onMaster is whether the master is being edited. Kept on the document so
  /// [elements] and the rest answer for the master and every panel edits it
  /// unawares.
  final bool onMaster;

  /// _elements, _frames and _actions hold the scene of a document with no
  /// scene list. Read them through [elements], [frames] and [actions].
  final List<CanvasElement> _elements;

  /// estimate is the file this canvas is meant to become, for the size shown.
  final CanvasEstimate estimate;

  final int _frames;

  /// frameRate is one rate for every scene, bounded by minFrameRate and
  /// maxFrameRate.
  final int frameRate;

  final List<TimelineAction> _actions;

  const CanvasDocument({
    this.title = "Untitled canvas",
    this.size = const CanvasSize(),
    this.background = const CanvasBackground(),
    this.guides = const CanvasGuides(),
    List<CanvasElement> elements = const [],
    this.estimate = const CanvasEstimate(),
    int frames = defaultFrameCount,
    this.frameRate = defaultFrameRate,
    List<TimelineAction> actions = const [],
    this.scenes = const [],
    this.sceneAt = 0,
    this.kind = CanvasKind.scenes,
    this.pages = const PagesSpec(),
    this.masterMix = const MasterMix(),
    this.audio = const AudioSettings(),
    this.returns = defaultReturns,
    this.session = const SessionGrid(),
    this.controls,
    this.playerControls = const {},
    this.game = false,
    this.gameStart = "",
    this.counts = const [],
    this.hasCanvas = true,
    this.master,
    this.masterOn = false,
    this.masterOver = false,
    this.cast = const [],
    this.onMaster = false,
    this.targets = const [],
    this.cues = const [],
    this.words = const [],
    this.textStyles = const [],
    this.scores = const [],
    this.sheets = const [],
  })  : _elements = elements,
        _frames = frames,
        _actions = actions;

  /// at is the scene being edited, always a valid index.
  int get at => scenes.isEmpty ? 0 : sceneAt.clamp(0, scenes.length - 1);

  /// editingMaster is whether the master is switched on and being shown.
  bool get editingMaster => onMaster && masterOn && master != null;

  List<CanvasElement> get elements => editingMaster
      ? master!.elements
      : (scenes.isEmpty ? _elements : scenes[at].elements);

  /// frames is the edited scene's length; one means a still. The master's is
  /// the whole sequence, worked out rather than stored.
  int get frames => editingMaster
      ? sequenceFrames
      : (scenes.isEmpty ? _frames : scenes[at].frames);

  List<TimelineAction> get actions => editingMaster
      ? master!.actions
      : (scenes.isEmpty ? _actions : scenes[at].actions);

  /// scene is the scene being edited, never the master even while that is
  /// edited (allScenes depends on it).
  CanvasScene get scene => scenes.isEmpty
      ? CanvasScene(
          id: "scene1", elements: _elements, frames: _frames, actions: _actions)
      : scenes[at];

  /// editing is the master where that is showing, and the scene otherwise.
  CanvasScene get editing => editingMaster ? master! : scene;

  /// sequenceFrames is every scene's length, less the frames transitions
  /// overlap.
  int get sequenceFrames {
    var list = allScenes;
    var total = 0;
    for (var i = 0; i < list.length; i++) {
      total += _stepOf(i);
    }
    return total.clamp(1, maxSequenceFrames).toInt();
  }

  /// playFrames is how long it runs when played or published. The editor's
  /// timeline asks [frames] instead.
  int get playFrames => hasScenes ? sequenceFrames : frames;

  /// offTimeline is whether [clip] has nothing to show at [frame]: before it
  /// starts or after it ends. A master clip runs on the whole run's clock.
  bool offTimeline(MediaClip clip, int frame, {bool onMaster = false}) {
    if (!clip.timed || clip.isEmpty || clip.runLength <= 0) return false;
    var rate = frameRate <= 0 ? 1 : frameRate;
    var run = onMaster && !editingMaster ? startOfScene(at) + frame : frame;
    return clip.momentAt((run - clip.at) / rate) == null;
  }

  int startOfScene(int index) {
    // Every start, worked out once per document: this is asked inside loops
    // over the scenes and their elements.
    var starts = _sceneStarts[this] ??= () {
      var out = [0];
      for (var i = 0; i < allScenes.length; i++) {
        out.add(out.last + _stepOf(i));
      }
      return out;
    }();
    return starts[index.clamp(0, starts.length - 1)];
  }

  /// keepingStarts adjusts scene lengths so every scene also in [before]
  /// starts where it did: a changed transition is absorbed by the scene
  /// before it. Worked front to back. A scene in [fixed] was just sized by
  /// hand and is left alone; one that would fall below a frame gives what it
  /// can.
  CanvasDocument keepingStarts(CanvasDocument before,
      {Set<String> fixed = const {}}) {
    var was = <String, int>{
      for (var (i, s) in before.allScenes.indexed) s.id: before.startOfScene(i),
    };
    var next = this;
    for (var i = 1; i < next.allScenes.length; i++) {
      var list = next.allScenes;
      var want = was[list[i].id];
      var prev = list[i - 1];
      if (want == null || fixed.contains(prev.id)) continue;
      var off = want - next.startOfScene(i);
      if (off == 0) continue;
      var frames = (prev.frames + off).clamp(1, maxFrameCount).toInt();
      next = next.withScene(i - 1, prev.copyWith(frames: frames));
    }
    return next;
  }

  /// transitionSounds are the transitions' sounds, each timed where its
  /// transition starts, less its lead. Made on every ask and never saved, so
  /// a sound is always where its transition is.
  List<AudioElement> get transitionSounds {
    var list = allScenes;
    if (list.length < 2) return const [];
    return [
      for (var i = 0; i < list.length - 1; i++)
        if (transitionAfter(i) case var t when t.on && t.sound.isNotEmpty)
          () {
            var (_, held, frames) = sceneStep(i);
            var starts = startOfScene(i + 1) - (frames - held);
            return AudioElement(
              ElementBase(
                  id: "$transitionSoundPrefix$i",
                  name: t.soundName.isEmpty ? "Transition" : t.soundName,
                  visible: false),
              clip: MediaClip(
                timed: true,
                at: math.max(0, starts - t.soundLead),
                volume: t.soundVolume,
                channel: "transitions",
                channelName: "Transitions",
                playlist: [
                  MediaSource(
                      assetId: t.sound,
                      name: t.soundName,
                      length: t.soundLength)
                ],
              ),
            );
          }(),
    ];
  }

  /// sceneStep is how scene [index] fits into the run: how far the sequence
  /// moves on, how many frames it shares with the next, and how long the
  /// transition lasts. The one answer for length, starts and what is drawn
  /// when, so export and screen agree.
  (int, int, int) sceneStep(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return (0, 0, 0);
    var scene = list[index];
    if (index == list.length - 1) return (scene.frames, 0, 0);

    var over = transitionAfter(index);
    if (!over.on) return (scene.frames, 0, 0);

    // Never more sharing than there is transition to share, and never more
    // than either scene has to give.
    var held = math.min(over.frames,
        math.min(over.overlap, math.min(scene.frames, list[index + 1].frames)));
    // This scene, less the frames the next one starts early by, plus what is
    // left of the transition after the sharing: its own stretch, the leaving
    // scene held on its last frame and the arriving one not started.
    return (scene.frames - held + (over.frames - held), held, over.frames);
  }

  int _stepOf(int index) => sceneStep(index).$1;

  List<CanvasScene> get allScenes => scenes.isEmpty ? [scene] : scenes;

  bool get hasScenes => scenes.length > 1;

  bool get isPages => kind.isPages;

  /// pageCovers is which canvases are covers, from which numbering and
  /// pairing are worked out. See canvas_pages.dart.
  List<PageCover> get pageCovers => [for (var s in allScenes) s.cover];

  /// nameOf is scene [index]'s own name, or its default: for a page, its
  /// number.
  String nameOf(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return "";
    var scene = list[index];
    if (scene.name.isNotEmpty) return scene.name;
    if (isPages && !scene.cover.isCover) {
      var number = pageNumberAt(index);
      if (number != null) return "${kind.oneCap} $number";
    }
    return scene.saysAt(index, kind);
  }

  /// pageNumberAt is the number on page [index], or null for a cover or a
  /// document of scenes.
  int? pageNumberAt(int index) =>
      isPages ? pageNumberFor(pageCovers, index, pages) : null;

  /// pageNumber is the number on the edited page, which a master page
  /// number reads. Never null on the master, where an undrawn number could
  /// not be found to move: it borrows the first number printed.
  int? get pageNumber {
    var here = pageNumberAt(at);
    if (here != null || !editingMaster) return here;
    for (var i = 0; i < allScenes.length; i++) {
      var number = pageNumberAt(i);
      if (number != null) return number;
    }
    return pages.startAt;
  }

  /// pageIsLeftHand is whether the edited page is a left-hand leaf, from
  /// which a mirrored number is drawn. Never on the master: it is placed as a
  /// right-hand page so a mirrored element stays under the pointer.
  bool get pageIsLeftHand => isPages && !editingMaster && pageIsLeft(at);

  /// facingAt is the page beside [index] when facing pages are on, or null.
  int? facingAt(int index) =>
      isPages && pages.facing ? facingPage(pageCovers, index) : null;

  /// facingIsLeft is whether [index] is the left leaf of its spread.
  bool? facingIsLeft(int index) =>
      isPages && pages.facing ? leftOfSpread(pageCovers, index) : null;

  /// spreadOf is the left and right leaves shown with page [index], either
  /// null where empty (a lone leaf still has a side, so its transition is
  /// drawn in the book). Null where facing pages are off.
  (int?, int?)? spreadOf(int index) {
    if (!isPages || !pages.facing) return null;
    var list = allScenes;
    if (index < 0 || index >= list.length) return null;
    var beside = facingAt(index);
    if (beside != null) {
      return beside > index ? (index, beside) : (beside, index);
    }
    return pageIsLeft(index) ? (index, null) : (null, index);
  }

  bool get hasSpread {
    if (!isPages || !pages.facing) return false;
    for (var i = 0; i < allScenes.length; i++) {
      if (facingAt(i) != null) return true;
    }
    return false;
  }

  /// masterScene is the master when switched on and not left off by this
  /// scene, else null.
  CanvasScene? get masterScene => masterOn && !scene.masterOff ? master : null;

  /// drawnBackground is what is behind the shown canvas: the master's while
  /// the master is on, then the scene's own, then the document's.
  CanvasBackground get drawnBackground => editingMaster
      ? (master!.background ?? background)
      : (masterScene?.sharedBackground ?? scene.background ?? background);

  /// ownBackground is this canvas's own backdrop, or the document's until it
  /// has one: what the layers list names.
  CanvasBackground get ownBackground => editingMaster
      ? (master!.background ?? background)
      : (scene.background ?? background);

  /// editedBackground is [drawnBackground], even when it is the master's
  /// (see [sharedBackdrop]): editing [ownBackground] under a master's
  /// backdrop would change nothing visible.
  CanvasBackground get editedBackground => drawnBackground;

  /// hasTiming is whether anything in any scene is placed in frames (a
  /// keyframe, sound or video), which a frame-rate change would move. Clips
  /// are in seconds and do not count.
  bool get hasTiming {
    for (var e in [
      for (var scene in allScenes) ...scene.elements,
      ...?master?.elements,
    ]) {
      if (e.track?.keys.isNotEmpty ?? false) return true;
      var clip = switch (e) {
        AudioElement a => a.clip,
        VideoElement v => v.clip,
        _ => null,
      };
      if (clip != null && clip.timed && !clip.isEmpty) return true;
    }
    return false;
  }

  /// sharedBackdrop is whether the backdrop on screen is the master's.
  bool get sharedBackdrop =>
      !editingMaster && masterScene?.sharedBackground != null;

  /// backgroundOf is scene [index]'s backdrop, for the whole-run painter.
  CanvasBackground backgroundOf(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return background;
    return masterScene?.sharedBackground ??
        list[index].background ??
        background;
  }

  /// defaultTransition is the master scene's transition, or a cut.
  SceneTransition get defaultTransition =>
      master?.transition ?? SceneTransition.cut;

  SceneTransition transitionAfter(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return SceneTransition.cut;
    return list[index].transition ?? defaultTransition;
  }

  /// sceneIndexNamed finds a scene by id, then by name (a name can change or
  /// be shared), or -1.
  int sceneIndexNamed(String idOrName) {
    var list = allScenes;
    for (var (i, s) in list.indexed) {
      if (s.id == idOrName) return i;
    }
    for (var (i, s) in list.indexed) {
      if (s.name.isNotEmpty && s.name == idOrName) return i;
    }
    return -1;
  }

  bool get isAnimated => frames > 1;

  double get durationSeconds => frames / (frameRate <= 0 ? 1 : frameRate);

  /// assetIds is every stored picture in every scene and the master,
  /// backgrounds and rings included. The picture-store sweep deletes what no
  /// saved document names, so a picture missed here is lost on restart.
  Set<String> get assetIds {
    var ids = <String>{};

    // Including the RingPick pictures an icon may be drawn as.
    void fromIcons(List<RingIcon> icons) {
      for (var icon in icons) {
        if (icon.asset.isNotEmpty) ids.add(icon.asset);
        for (var pick in icon.also) {
          if (pick.asset.isNotEmpty) ids.add(pick.asset);
        }
      }
    }

    void fromBackground(CanvasBackground? bg) {
      if (bg == null) return;
      ids.addAll(bg.assetIds);
      fromIcons(bg.spec.rings.icons);
    }

    void fromElements(List<CanvasElement> list) {
      for (var e in list) {
        ids.addAll(e.assetIds);
        // A background element's design can carry pictures too.
        if (e is BackgroundElement) fromIcons(e.spec.rings.icons);
      }
    }

    fromBackground(background);
    for (var one in allScenes) {
      fromElements(one.elements);
      fromBackground(one.background);
    }
    if (master != null) {
      fromElements(master!.elements);
      fromBackground(master!.background);
    }
    return ids;
  }

  /// mediaIds is every stored sound or video in every scene and the master:
  /// what the media-store sweep keeps and a bundle carries.
  Set<String> get mediaIds => {
        ...background.mediaIds,
        ...session.mediaIds,
        for (var one in allScenes) ...[
          for (var e in one.elements) ...e.mediaIds,
          ...?one.background?.mediaIds,
        ],
        if (master != null) ...[
          for (var e in master!.elements) ...e.mediaIds,
          ...?master!.background?.mediaIds,
        ],
      };

  /// lastAnimatedFrame is the furthest frame any keyframe, clip or marker is
  /// on, so the settings bar can warn of a scene shorter than its animation.
  int get lastAnimatedFrame {
    var last = 0;
    var rate = math.max(1, frameRate);
    for (var e in elements) {
      var f = e.track?.lastFrame ?? 0;
      if (f > last) last = f;
      // Where each placed clip ends (pins aside).
      var m = e.base.motion;
      for (var p in m.placed) {
        var c = m.clip(p.clip);
        if (c == null) continue;
        var end = ((p.start + (p.length ?? c.span)) * rate).ceil();
        if (end > last) last = end;
      }
      // A team's movement is on its players' tracks.
      if (e is TeamElement) {
        for (var p in e.players) {
          var pf = p.track?.lastFrame ?? 0;
          if (pf > last) last = pf;
        }
      }
    }
    for (var a in actions) {
      if (a.frame > last) last = a.frame;
    }
    return last;
  }

  CanvasElement? elementById(String id) {
    var list = elements;
    if (list.length < 16) {
      for (var e in list) {
        if (e.id == id) return e;
      }
      return null;
    }
    // Cached per list: asked over and over while a frame is drawn, and lists
    // of elements are replaced, never changed.
    var byId = _byId[list] ??= () {
      var out = <String, CanvasElement>{};
      for (var e in list) {
        out.putIfAbsent(e.id, () => e);
      }
      return out;
    }();
    return byId[id];
  }

  int indexOf(String id) => elements.indexWhere((e) => e.id == id);

  /// copyWith sends elements, a length or actions to the scene being edited
  /// (or the master), so callers need not know which.
  CanvasDocument copyWith({
    String? title,
    CanvasSize? size,
    CanvasBackground? background,
    CanvasGuides? guides,
    List<CanvasElement>? elements,
    CanvasEstimate? estimate,
    int? frames,
    int? frameRate,
    List<TimelineAction>? actions,
    List<CanvasScene>? scenes,
    int? sceneAt,
    CanvasKind? kind,
    PagesSpec? pages,
    MasterMix? masterMix,
    AudioSettings? audio,
    List<ReturnChannel>? returns,
    SessionGrid? session,
    List<ControlAction>? controls,
    Map<int, List<ControlAction>>? playerControls,
    bool? game,
    String? gameStart,
    List<GameCount>? counts,
    bool? hasCanvas,
    CanvasScene? master,
    bool clearMaster = false,
    bool? masterOn,
    bool? masterOver,
    List<CanvasElement>? cast,
    bool? onMaster,
    List<String>? targets,
    List<TimelineCue>? cues,
    List<SpokenWord>? words,
    List<NamedTextStyle>? textStyles,
    List<MusicScore>? scores,
    List<DataSheet>? sheets,
  }) {
    var list = scenes ?? this.scenes;
    var index = (sceneAt ?? this.sceneAt)
        .clamp(0, math.max(0, list.length - 1))
        .toInt();

    // Into the master when it is edited. A length is dropped: the master's
    // is the sequence's.
    var shared = clearMaster ? null : (master ?? this.master);
    var onIt = (onMaster ?? this.onMaster) &&
        (masterOn ?? this.masterOn) &&
        shared != null;
    if (onIt && master == null && (elements != null || actions != null)) {
      shared = shared.copyWith(elements: elements, actions: actions);
    }

    if (!onIt &&
        list.isNotEmpty &&
        (elements != null || frames != null || actions != null)) {
      var at = list[index];
      list = [...list];
      list[index] = at.copyWith(
        elements: elements,
        frames: frames,
        actions: actions,
      );
    }

    return CanvasDocument(
      title: title ?? this.title,
      size: size ?? this.size,
      background: background ?? this.background,
      guides: guides ?? this.guides,
      // An edit meant for the master must not also land on the one scene a
      // document with no scene list has.
      elements: list.isEmpty
          ? (onIt && shared != null ? _elements : (elements ?? _elements))
          : const [],
      estimate: estimate ?? this.estimate,
      frames: list.isEmpty
          ? (onIt && shared != null
              ? _frames
              : (frames ?? _frames).clamp(1, maxFrameCount).toInt())
          : 1,
      frameRate:
          (frameRate ?? this.frameRate).clamp(minFrameRate, maxFrameRate),
      actions: list.isEmpty
          ? (onIt && shared != null ? _actions : (actions ?? _actions))
          : const [],
      scenes: list,
      sceneAt: index,
      kind: kind ?? this.kind,
      pages: pages ?? this.pages,
      masterMix: masterMix ?? this.masterMix,
      audio: audio ?? this.audio,
      returns: returns ?? this.returns,
      session: session ?? this.session,
      controls: controls ?? this.controls,
      playerControls: playerControls ?? this.playerControls,
      game: game ?? this.game,
      gameStart: gameStart ?? this.gameStart,
      counts: counts ?? this.counts,
      hasCanvas: hasCanvas ?? this.hasCanvas,
      master: shared,
      masterOn: masterOn ?? this.masterOn,
      masterOver: masterOver ?? this.masterOver,
      cast: cast ?? this.cast,
      onMaster: onIt,
      targets: targets ?? this.targets,
      cues: cues ?? this.cues,
      words: words ?? this.words,
      textStyles: textStyles ?? this.textStyles,
      scores: scores ?? this.scores,
      sheets: sheets ?? this.sheets,
    );
  }

  /// withScenes is this document as a scene list. Everything that adds,
  /// removes or reorders scenes goes through here.
  CanvasDocument withScenes(List<CanvasScene> next, {int? at}) {
    if (next.isEmpty) return this;
    return CanvasDocument(
      title: title,
      size: size,
      background: background,
      guides: guides,
      estimate: estimate,
      frameRate: frameRate,
      scenes: next,
      sceneAt: (at ?? sceneAt).clamp(0, next.length - 1).toInt(),
      kind: kind,
      pages: pages,
      masterMix: masterMix,
      audio: audio,
      returns: returns,
      session: session,
      controls: controls,
      playerControls: playerControls,
      game: game,
      gameStart: gameStart,
      counts: counts,
      hasCanvas: hasCanvas,
      master: master,
      masterOn: masterOn,
      masterOver: masterOver,
      cast: cast,
      onMaster: onMaster,
      targets: targets,
      cues: cues,
      words: words,
      textStyles: textStyles,
      scores: scores,
      sheets: sheets,
    );
  }

  /// forShape lays the document out for another page shape, master included:
  /// each element stores its place under the old shape and takes the new
  /// one's, or a scaled copy. See responsive_layout.dart.
  CanvasDocument forShape(CanvasSize next) {
    var from = shapeKey(size), to = shapeKey(next);
    if (from == to) return copyWith(size: next);

    // Seeded per scene, from that scene's design. See seedFor.
    CanvasScene moved(CanvasScene scene) {
      var seed = seedFor(scene.elements, size, next);
      return scene.copyWith(elements: [
        for (var e in scene.elements)
          movedTo(e, from, to, seed: seed, covers: coversPage(e, size)),
      ]);
    }

    var shared = master == null ? null : moved(master!);
    return withScenes([for (var scene in allScenes) moved(scene)], at: at)
        .copyWith(size: next, master: shared);
  }

  CanvasDocument withScene(int index, CanvasScene next) {
    var list = [...allScenes];
    if (index < 0 || index >= list.length) return this;
    list[index] = next;
    return withScenes(list);
  }

  /// addScene puts an empty canvas after [after], or at the end, with a plain
  /// backdrop: the document's could be from long ago. A master's backdrop
  /// still covers it.
  CanvasDocument addScene({int? after, String name = ""}) {
    // Scenes relying on the document's backdrop take a copy first, so nothing
    // on screen changes and it stops being a live fallback.
    var list = [
      for (var scene in allScenes)
        scene.background == null
            ? scene.copyWith(background: background)
            : scene,
    ];
    var to =
        after == null ? list.length : (after + 1).clamp(0, list.length).toInt();
    list.insert(
        to,
        CanvasScene(
          id: newSceneId(),
          name: name,
          frames: frames,
          background: const CanvasBackground(),
        ));
    return withScenes(list, at: to);
  }

  /// scenesFrom is a document of only scenes [first] to [last], for
  /// publishing part of it, so no exporter needs a range.
  CanvasDocument scenesFrom(int first, int last) {
    var list = allScenes;
    var from = first.clamp(0, list.length - 1).toInt();
    var to = last.clamp(from, list.length - 1).toInt();
    if (from == 0 && to == list.length - 1) return this;
    return withScenes(list.sublist(from, to + 1), at: 0);
  }

  /// duplicateScene copies one under new ids: two scenes sharing an element
  /// id would edit as one.
  CanvasDocument duplicateScene(int index) {
    var list = [...allScenes];
    if (index < 0 || index >= list.length) return this;
    var from = list[index];
    var copy = from.copyWith(
      id: newSceneId(),
      name: from.name.isEmpty ? "" : "${from.name} copy",
      elements: [for (var e in from.elements) e.withId(newElementId())],
    );
    list.insert(index + 1, copy);
    return withScenes(list, at: index + 1);
  }

  /// removeScene takes one out; the last one left stays.
  CanvasDocument removeScene(int index) {
    var list = [...allScenes];
    if (list.length <= 1 || index < 0 || index >= list.length) return this;
    list.removeAt(index);
    return withScenes(list, at: math.min(sceneAt, list.length - 1));
  }

  /// moveScene reorders, which sets the playing order.
  CanvasDocument moveScene(int from, int to) {
    var list = [...allScenes];
    if (from < 0 || from >= list.length) return this;
    var moved = list.removeAt(from);
    list.insert(to.clamp(0, list.length).toInt(), moved);
    return withScenes(list, at: to.clamp(0, list.length - 1).toInt());
  }

  CanvasDocument goToScene(int index) {
    if (scenes.isEmpty) return this;
    return copyWith(sceneAt: index.clamp(0, scenes.length - 1).toInt());
  }

  /// withMaster changes the master, making one if there is none.
  CanvasDocument withMaster(CanvasScene next) =>
      copyWith(master: next, masterOn: masterOn);

  /// withElement replaces the element with [element]'s id, or does nothing
  /// if deleted: a panel torn down after a delete must not restore it.
  CanvasDocument withElement(CanvasElement element) {
    var i = indexOf(element.id);
    if (i < 0) return this;
    var next = [...elements];
    next[i] = element;
    return copyWith(elements: next);
  }

  CanvasDocument addElement(CanvasElement element) =>
      copyWith(elements: [...elements, laidOut(element)]);

  /// laidOut gives [element] a layout on every target shape, seeded from the
  /// current one. addElement goes through here.
  CanvasElement laidOut(CanvasElement element) => withLayoutsFor(
        element,
        size,
        targets,
        sizeOf: (key) => sizeForShape(key, size),
      );

  /// removeElement takes an element out, and texts that name it (attached to
  /// a line, flowing into a box): a dangling id is a setting the panel could
  /// neither show nor undo. A button's action is left: pointing at nothing,
  /// it does nothing.
  CanvasDocument removeElement(String id) => copyWith(elements: [
        for (var e in elements)
          if (e.id != id) _withoutLinksTo(e, id),
      ]);

  /// reorder moves the element at [from] to [to] in paint order.
  CanvasDocument reorder(int from, int to) {
    if (from < 0 || from >= elements.length) return this;
    var next = [...elements];
    var moved = next.removeAt(from);
    next.insert(to.clamp(0, next.length), moved);
    return copyWith(elements: next);
  }

  /// toJson writes a document of one plain scene with no master with its
  /// elements, frames and actions at the top level; a scene list appears
  /// only when one scene cannot say something.
  Map<String, dynamic> toJson() {
    var one = scenes.length <= 1 && master == null && _plain(scene);
    return {
      "version": canvasFormatVersion,
      "title": title,
      "size": size.toJson(),
      "background": background.toJson(),
      if (!guides.isDefault) "guides": guides.toJson(),
      if (estimate.toJson().isNotEmpty) "estimate": estimate.toJson(),
      "frames": frames,
      "frameRate": frameRate,
      if (actions.isNotEmpty)
        "actions": actions.map((a) => a.toJson()).toList(),
      "elements": [for (var e in elements) e.toJson()],
      if (targets.isNotEmpty) "targets": targets,
      if (cues.isNotEmpty) "cues": [for (var c in cues) c.toJson()],
      if (words.isNotEmpty) "words": [for (var w in words) w.toJson()],
      if (textStyles.isNotEmpty)
        "textStyles": [for (var t in textStyles) t.toJson()],
      if (scores.isNotEmpty) "scores": [for (var s in scores) s.toJson()],
      if (sheets.isNotEmpty) "sheets": [for (var s in sheets) s.toJson()],

      if (kind != CanvasKind.scenes) "kind": kind.name,
      if (!pages.isDefault) "pages": pages.toJson(),
      if (!masterMix.isDefault) "masterMix": masterMix.toJson(),
      if (!audio.isDefault) "audio": audio.toJson(),
      if (!hasCanvas) "noCanvas": true,
      if (!_sameReturns(returns, defaultReturns))
        "returns": [for (var r in returns) r.toJson()],
      if (!session.isEmpty) "session": session.toJson(),
      if (controls case var c?) "controls": [for (var a in c) a.toJson()],
      if (game) "game": true,
      if (gameStart.isNotEmpty) "gameStart": gameStart,
      if (masterOver) "masterOver": true,
      if (cast.isNotEmpty) "cast": [for (var e in cast) e.toJson()],
      if (playerControls.isNotEmpty)
        "playerControls": {
          for (var MapEntry(key: p, value: list) in playerControls.entries)
            "$p": [for (var a in list) a.toJson()],
        },
      if (counts.isNotEmpty) "counts": [for (var c in counts) c.toJson()],
      if (!one) ...{
        "scenes": [for (var s in allScenes) s.toJson()],
        if (sceneAt != 0) "sceneAt": at,
        if (master != null) "master": master!.toJson(),
        if (masterOn) "masterOn": true,
        if (onMaster) "onMaster": true,
      },
      // The scene's own name and settings, so naming it does not make a
      // scene list.
      if (one && (scene.name.isNotEmpty || scene.holds || scene.custom))
        "scene": {
          if (scene.name.isNotEmpty) "name": scene.name,
          "id": scene.id,
          if (scene.holds) "holds": true,
          if (scene.custom) "transition": scene.transition!.toJson(),
        },
    };
  }

  /// _plain is whether [s] holds nothing the top-level fields and "scene"
  /// cannot carry.
  static bool _plain(CanvasScene s) =>
      s.background == null &&
      !s.backgroundOff &&
      !s.masterOff &&
      s.gameSounds.isEmpty &&
      s.gameSoundsAtEnd.isEmpty &&
      !s.cover.isCover &&
      s.camera == null;

  String encode() => const JsonEncoder.withIndent("  ").convert(toJson());

  factory CanvasDocument.fromJson(Map<String, dynamic> json) {
    var raw = json["elements"];
    var acts = json["actions"];

    var sceneList = json["scenes"];
    var scenes = <CanvasScene>[
      if (sceneList is List)
        for (var it in sceneList.take(maxScenes))
          if (it is Map<String, dynamic>) CanvasScene.fromJson(it),
    ];

    // The single scene's own settings, for a document that is one canvas.
    var only = json["scene"];
    var name = "";
    var id = "scene1";
    var holds = false;
    SceneTransition? transition;
    if (only is Map<String, dynamic>) {
      name = jsonString(only["name"], "");
      id = jsonString(only["id"], "scene1");
      holds = jsonBool(only["holds"], false);
      if (only["transition"] is Map<String, dynamic>) {
        transition = SceneTransition.fromJson(
            only["transition"] as Map<String, dynamic>);
      }
    }

    var elements = raw is List
        ? [
            for (var e in raw.take(maxSceneElements))
              if (e is Map<String, dynamic>) elementFromJson(e),
          ]
        : const <CanvasElement>[];
    var actions = acts is List
        ? [
            for (var a in acts)
              if (a is Map<String, dynamic>) TimelineAction.fromJson(a),
          ]
        : const <TimelineAction>[];
    var frames =
        jsonInt(json["frames"], defaultFrameCount).clamp(1, maxFrameCount);

    if (scenes.isEmpty && (name.isNotEmpty || holds || transition != null)) {
      // One scene with settings of its own: a list of one.
      scenes = [
        CanvasScene(
          id: id,
          name: name,
          elements: elements,
          frames: frames,
          actions: actions,
          holds: holds,
          transition: transition,
        ),
      ];
    }

    // Tables and charts saved without sheets are given sheets of their own.
    return dataRefreshed(sourcesAdopted(dataAdopted(CanvasDocument(
      title: jsonString(json["title"], "Untitled canvas"),
      size: jsonSpec(json["size"], CanvasSize.fromJson, const CanvasSize()),
      background: jsonSpec(json["background"], CanvasBackground.fromJson,
          const CanvasBackground()),
      guides:
          jsonSpec(json["guides"], CanvasGuides.fromJson, const CanvasGuides()),
      elements: scenes.isEmpty ? elements : const [],
      estimate: jsonSpec(
          json["estimate"], CanvasEstimate.fromJson, const CanvasEstimate()),
      frames: scenes.isEmpty ? frames : 1,
      frameRate: jsonInt(json["frameRate"], defaultFrameRate)
          .clamp(minFrameRate, maxFrameRate),
      actions: scenes.isEmpty ? actions : const [],
      scenes: scenes,
      sceneAt: jsonInt(json["sceneAt"], 0),
      kind: CanvasKind.fromName(jsonStr(json["kind"])),
      pages: json["pages"] is Map<String, dynamic>
          ? PagesSpec.fromJson(json["pages"] as Map<String, dynamic>)
          : const PagesSpec(),
      masterMix:
          jsonSpec(json["masterMix"], MasterMix.fromJson, const MasterMix()),
      audio: AudioSettings.fromJson(json["audio"]),
      hasCanvas: json["noCanvas"] != true,
      returns: json["returns"] is List
          ? [
              for (var r in (json["returns"] as List).take(maxReturns))
                if (ReturnChannel.fromJson(r) case var ret?) ret,
            ]
          : defaultReturns,
      session: SessionGrid.fromJson(json["session"]),
      game: json["game"] == true,
      gameStart: jsonString(json["gameStart"], ""),
      masterOver: json["masterOver"] == true,
      playerControls: {
        if (json["playerControls"] case Map raw)
          for (var MapEntry(key: p, value: list) in raw.entries)
            if (int.tryParse("$p") case var n? when n >= 2 && n <= 4)
              if (list case List actions)
                n: [
                  for (var a in actions)
                    if (ControlAction.fromJson(a) case var action?) action,
                ],
      },
      counts: [
        if (json["counts"] case List raw)
          for (var c in raw)
            if (GameCount.fromJson(c) case var count?) count,
      ],
      controls: json["controls"] is List
          ? [
              for (var a in json["controls"] as List)
                if (ControlAction.fromJson(a) case var action?) action,
            ]
          : null,
      master: json["master"] is Map<String, dynamic>
          ? CanvasScene.fromJson(json["master"] as Map<String, dynamic>)
          : null,
      masterOn: jsonBool(json["masterOn"], false),
      cast: [
        if (json["cast"] is List)
          for (var e in json["cast"] as List)
            if (e is Map<String, dynamic>) elementFromJson(e),
      ],
      // Only where there is a master, switched on, to be on.
      onMaster: jsonBool(json["onMaster"], false) &&
          jsonBool(json["masterOn"], false) &&
          json["master"] is Map<String, dynamic>,
      targets: [
        if (json["targets"] is List)
          for (var t in json["targets"] as List)
            if (t is String) t,
      ],
      cues: [
        if (json["cues"] is List)
          for (var c in json["cues"] as List)
            if (TimelineCue.fromJson(c) case var cue?) cue,
      ]..sort((a, b) => a.frame.compareTo(b.frame)),
      words: [
        if (json["words"] is List)
          for (var w in json["words"] as List)
            if (SpokenWord.fromJson(w) case var word?) word,
      ]..sort((a, b) => a.frame.compareTo(b.frame)),
      textStyles: [
        if (json["textStyles"] is List)
          for (var t in json["textStyles"] as List)
            if (NamedTextStyle.fromJson(t) case var style?) style,
      ],
      scores: [
        if (json["scores"] is List)
          for (var s in json["scores"] as List)
            if (s is Map<String, dynamic>) MusicScore.fromJson(s),
      ],
      sheets: [
        if (json["sheets"] is List)
          for (var s in json["sheets"] as List)
            if (DataSheet.fromJson(s) case var sheet?) sheet,
      ],
    ))));
  }

  /// decode returns null rather than throwing, so a file that will not parse
  /// is reported and left alone, never overwritten.
  static CanvasDocument? decode(String text) {
    try {
      var json = finiteJson(jsonDecode(text));
      if (json is! Map<String, dynamic>) return null;
      return CanvasDocument.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

final Expando<Map<String, CanvasElement>> _byId = Expando("elementsById");

final Expando<List<int>> _sceneStarts = Expando("sceneStarts");

/// finiteJson is [json] with non-finite numbers (1e999 reads as infinity)
/// dropped from maps and made nought in lists.
Object? finiteJson(Object? json) => switch (json) {
      Map m => <String, dynamic>{
          for (var e in m.entries)
            if (!(e.value is double && !(e.value as double).isFinite))
              "${e.key}": finiteJson(e.value),
        },
      List l => [
          for (var x in l) x is double && !x.isFinite ? 0 : finiteJson(x),
        ],
      _ => json,
    };

CanvasElement _withoutLinksTo(CanvasElement e, String id) {
  if (e is! TextElement) return e;
  var next = e;
  if (next.curve?.elementId == id) next = next.copyWith(clearCurve: true);
  if (next.flowTo == id) next = next.copyWith(flowTo: "");
  return next;
}

/// elementFromJson builds the right subclass. An unknown kind (from a newer
/// build) becomes a plain shape, a visible placeholder, not dropped.
CanvasElement elementFromJson(Map<String, dynamic> json) {
  var kind = ElementKind.values.firstWhere(
    (k) => k.name == json["kind"],
    orElse: () => ElementKind.shape,
  );
  var base = ElementBase.fromJson(json, kind.label);
  switch (kind) {
    case ElementKind.text:
      // Its type's shadow, glow and outline read as layer looks
      // (text_looks.dart).
      return textLooksLifted(TextElement.fromJson(json, base));
    case ElementKind.image:
      return ImageElement.fromJson(json, base);
    case ElementKind.shape:
      return ShapeElement.fromJson(json, base);
    case ElementKind.line:
      return LineElement.fromJson(json, base);
    case ElementKind.chart:
      return ChartElement.fromJson(json, base);
    case ElementKind.table:
      return TableElement.fromJson(json, base);
    case ElementKind.button:
      return ButtonElement.fromJson(json, base);
    case ElementKind.background:
      return BackgroundElement.fromJson(json, base);
    case ElementKind.player:
      return TeamElement.fromJson(json, base);
    case ElementKind.path:
      return PathElement.fromJson(json, base);
    case ElementKind.counter:
      return CounterElement.fromJson(json, base);
    case ElementKind.audio:
      return AudioElement.fromJson(json, base);
    case ElementKind.video:
      return VideoElement.fromJson(json, base);
    case ElementKind.vector:
      return VectorElement.fromJson(json, base);
    case ElementKind.character3d:
      return Character3dElement.fromJson(json, base);
    case ElementKind.sheet:
      return SheetElement.fromJson(json, base);
    case ElementKind.camera:
      return CameraElement.fromJson(json, base);
    case ElementKind.object3d:
      return Object3dElement.fromJson(json, base);
    // Never saved alone (a background carries them), so read as an unknown
    // kind: a placeholder.
    case ElementKind.stage:
    case ElementKind.parallax:
      return ShapeElement.fromJson(json, base);
    case ElementKind.sprite:
      return SpriteElement.fromJson(json, base);
    case ElementKind.tileMap:
      return TileMapElement.fromJson(json, base);
    case ElementKind.synth:
      return SynthModuleElement.fromJson(json, base) ??
          ShapeElement.fromJson(json, base);
    case ElementKind.synthTask:
      return SynthTaskElement.fromJson(json, base);
    case ElementKind.metronome:
      return MetronomeElement.fromJson(json, base);
    case ElementKind.code:
      return CodeElement.fromJson(json, base);
    case ElementKind.codeRun:
      return CodeRunElement.fromJson(json, base);
    case ElementKind.codeTask:
      return CodeTaskElement.fromJson(json, base);
  }
}

/// NamedTextStyle is one of the document's text styles: a name and its type.
class NamedTextStyle {
  final String name;
  final TextSpec spec;
  const NamedTextStyle(this.name, this.spec);

  Map<String, dynamic> toJson() => {"name": name, "spec": spec.toJson()};

  static NamedTextStyle? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    var name = jsonString(json["name"], "");
    if (name.isEmpty || json["spec"] is! Map<String, dynamic>) return null;
    return NamedTextStyle(
        name, TextSpec.fromJson(json["spec"] as Map<String, dynamic>));
  }
}

bool _sameReturns(List<ReturnChannel> a, List<ReturnChannel> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i].toKey() == b[i].toKey()]
        .every((same) => same);
