import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_background.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_cues.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_pages.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/data_sheet.dart';
import 'package:bruig/plugin_system/canvas/model/data_sync.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/element_reading.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/music_score.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_rings.dart';
import 'package:bruig/plugin_system/canvas/model/responsive_layout.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/model/text_fields.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

// What a document is made of and read with, so whatever imports a document
// has them: its background, its limits, and reading an element by kind.
export 'package:bruig/plugin_system/canvas/model/canvas_background.dart';
export 'package:bruig/plugin_system/canvas/model/canvas_limits.dart';
export 'package:bruig/plugin_system/canvas/model/element_reading.dart';

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

/// _bareMasters are masters with their elements taken off, as a cover shows
/// them: one each, so a cover's master keeps its identity across frames.
final _bareMasters = Expando<CanvasScene>("bareMaster");

/// CanvasDocument is a whole canvas: its page, its scenes and what is on
/// them, its sound, its data and its game. Immutable: every edit is a new
/// document, so undo is a list of them and a painter never sees one change
/// under it.
///
/// The fields come first, then the constructor, then what is worked out
/// from them by topic: the scene being edited, the run of scenes, pages,
/// backgrounds, what is stored, changing it, and saving.
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

  /// scenesBus is the Scenes strip: the scenes' own sound -- the transitions'
  /// -- summed through one strip on its way to the master, for the whole
  /// canvas. Each scene had a strip of its own, so a fader moved on one
  /// scene left every other transition as it was (Ken, 2026-11-24). As made,
  /// neutral.
  final ChannelMix scenesBus;

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

  /// playerControls are players two to four's changed controls, by player.
  final Map<int, List<ControlAction>> playerControls;

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
    this.scenesBus = const ChannelMix(),
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

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = CanvasDocument();

  // --------------------------------------------------------------------------
  // The mixer as played, and the game's controls
  // --------------------------------------------------------------------------

  /// synced is [devices] with each Sync LFO given its rate at this
  /// document's tempo, since the engine knows no tempo; used for playing and
  /// exporting alike.
  List<MixDevice> synced(List<MixDevice> devices) =>
      tempoSynced(devices, audio.tempo, beatsPerBar: audio.beatsPerBar);

  /// syncedMaster and syncedReturns are the mixer's as played: the very
  /// same objects where no LFO is synced, so the runtime knows them again.
  MasterMix get syncedMaster {
    var devices = synced(masterMix.devices);
    return identical(devices, masterMix.devices)
        ? masterMix
        : masterMix.copyWith(devices: devices);
  }

  List<ReturnChannel> get syncedReturns => [
        for (var r in returns)
          if (synced(r.devices) case var d when !identical(d, r.devices))
            r.copyWith(devices: d)
          else
            r,
      ];

  /// controlsNow are its controls, or the defaults where it has none.
  List<ControlAction> get controlsNow =>
      controls ??
      (players.length > 1 ? sharedDefaultControls : defaultControls);

  /// controlsFor is the controls [player] plays with.
  List<ControlAction> controlsFor(int player) => player <= 1
      ? controlsNow
      : playerControls[player] ?? defaultControlsFor(player);

  /// players are the players it is played by: one, at least.
  Set<int> get players => {
        1,
        for (var e in elements)
          if (e.base.play.as.moves) e.base.play.player,
      };

  // --------------------------------------------------------------------------
  // The scene being edited
  // --------------------------------------------------------------------------

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
          id: _onlySceneId,
          elements: _elements,
          frames: _frames,
          actions: _actions)
      : scenes[at];

  /// editing is the master where that is showing, and the scene otherwise.
  CanvasScene get editing => editingMaster ? master! : scene;

  // --------------------------------------------------------------------------
  // The run of scenes: lengths, starts and transitions
  // --------------------------------------------------------------------------

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
            var step = sceneStep(i);
            var starts = startOfScene(i + 1) - (step.transition - step.shared);
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
  /// moves on (advance), how many frames it shares with the next (shared),
  /// and how long the transition lasts (transition). The one answer for
  /// length, starts and what is drawn when, so export and screen agree.
  ({int advance, int shared, int transition}) sceneStep(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) {
      return (advance: 0, shared: 0, transition: 0);
    }
    var scene = list[index];
    var over = transitionAfter(index);
    if (index == list.length - 1 || !over.on) {
      return (advance: scene.frames, shared: 0, transition: 0);
    }

    // Never more sharing than there is transition to share, and never more
    // than either scene has to give.
    var held = math.min(over.frames,
        math.min(over.overlap, math.min(scene.frames, list[index + 1].frames)));
    // This scene, less the frames the next one starts early by, plus what is
    // left of the transition after the sharing: its own stretch, the leaving
    // scene held on its last frame and the arriving one not started.
    return (
      advance: scene.frames - held + (over.frames - held),
      shared: held,
      transition: over.frames,
    );
  }

  int _stepOf(int index) => sceneStep(index).advance;

  List<CanvasScene> get allScenes => scenes.isEmpty ? [scene] : scenes;

  bool get hasScenes => scenes.length > 1;

  bool get isPages => kind.isPages;

  // --------------------------------------------------------------------------
  // Pages: numbers, covers and spreads
  // --------------------------------------------------------------------------

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
  ({int? left, int? right})? spreadOf(int index) {
    if (!isPages || !pages.facing) return null;
    var list = allScenes;
    if (index < 0 || index >= list.length) return null;
    var beside = facingAt(index);
    if (beside != null) {
      return beside > index
          ? (left: index, right: beside)
          : (left: beside, right: index);
    }
    return pageIsLeft(index)
        ? (left: index, right: null)
        : (left: null, right: index);
  }

  bool get hasSpread {
    if (!isPages || !pages.facing) return false;
    for (var i = 0; i < allScenes.length; i++) {
      if (facingAt(i) != null) return true;
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // The master, and what is behind a scene
  // --------------------------------------------------------------------------

  /// masterScene is the master when switched on and not left off by this
  /// scene, else null.
  CanvasScene? get masterScene {
    if (!masterOn || scene.masterOff) return null;
    var m = master;
    // A cover keeps the master's backdrop but not what is on it (see
    // PagesSpec.masterOnCovers).
    if (m != null && isPages && scene.cover.isCover && !pages.masterOnCovers) {
      return _bareMasters[m] ??= m.copyWith(elements: const []);
    }
    return m;
  }

  /// pageFields is what the fields of a text on the shown canvas are filled
  /// from (text_fields.dart): its page number and values, the words of the
  /// texts on it, and on the master, a mark for each.
  PageFields get pageFields {
    var count = 0;
    for (var i = 0; i < allScenes.length; i++) {
      if (pageNumberAt(i) != null) count++;
    }
    var words = scene.elements;
    return PageFields(
      page: pageNumberAt(at),
      pages: count,
      values: scene.values,
      master: editingMaster,
      textOf: (name) {
        for (var e in words) {
          if (e is! TextElement) continue;
          if (e.name == name) return e.text;
          for (var item in e.items) {
            if (item.name == name) return item.text;
          }
        }
        return null;
      },
    );
  }

  /// drawnBackground is what is behind the shown canvas: the master's while
  /// the master is on, then the scene's own, then the document's.
  CanvasBackground get drawnBackground => editingMaster
      ? (master!.background ?? background)
      : (masterScene?.sharedBackground ?? scene.background ?? background);

  /// editedBackground is the backdrop the settings, the Colour panel and
  /// the layers list show, and the settings change: [drawnBackground], even
  /// when that is the master's (see [sharedBackdrop]). Changing the scene's
  /// own under a master's backdrop would change nothing visible.
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

  // --------------------------------------------------------------------------
  // What it keeps in the stores, and finding an element
  // --------------------------------------------------------------------------

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

  /// storedIds is everything this document keeps in the stores, pictures
  /// and media both: what a tidy of the stores must leave alone while it is
  /// open.
  Set<String> get storedIds => {...assetIds, ...mediaIds};

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

  /// elementInAnyScene is the element with [id] in whichever scene holds
  /// it, where [elementById] looks only in the one being edited.
  CanvasElement? elementInAnyScene(String id) {
    for (var scene in allScenes) {
      for (var e in scene.elements) {
        if (e.id == id) return e;
      }
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // Changing it
  // --------------------------------------------------------------------------

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
    ChannelMix? scenesBus,
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
          ? (onIt ? _elements : (elements ?? _elements))
          : const [],
      estimate: estimate ?? this.estimate,
      frames: list.isEmpty
          ? (onIt
              ? _frames
              : (frames ?? _frames).clamp(1, maxFrameCount).toInt())
          : 1,
      frameRate:
          (frameRate ?? this.frameRate).clamp(minFrameRate, maxFrameRate),
      actions:
          list.isEmpty ? (onIt ? _actions : (actions ?? _actions)) : const [],
      scenes: list,
      sceneAt: index,
      kind: kind ?? this.kind,
      pages: pages ?? this.pages,
      masterMix: masterMix ?? this.masterMix,
      scenesBus: scenesBus ?? this.scenesBus,
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

  /// mapColours is the document with every colour of its design put
  /// through [f], or this very document where none changed (the
  /// controller's edits compare by identity, so a replace that finds nothing
  /// is no edit). It maps the background, every scene (or the one scene of a
  /// document with none), the master (hidden while off), the cast, the text
  /// styles and the sheets' colour rules. The cast and the text styles are
  /// taken as hidden: neither is drawn itself, and what is drawn from them
  /// (linked copies, the texts set in a style) holds its own colours, mapped
  /// where it stands. The sheets' are shown: what tables and charts draw
  /// from them is worked out again, not mapped.
  CanvasDocument mapColours(ColourMap f) {
    var hidden = f.shownOnlyIf(false);
    var p = ColourPass(f);
    var background = p.part(this.background, (b) => b.mapColours(f));
    var scenes = p.list(this.scenes, (s) => s.mapColours(f));
    var elements = p.list(_elements, (e) => e.mapColours(f));
    var master =
        p.partOrNone(this.master, (m) => m.mapColours(f.shownOnlyIf(masterOn)));
    var cast = p.list(this.cast, (e) => e.mapColours(hidden));
    var textStyles = p.list(this.textStyles, (s) => s.mapColours(hidden));
    var sheets = p.list(this.sheets, (s) => s.mapColours(f));
    if (!p.changed) return this;
    var next = copyWith(
      background: background,
      scenes: scenes,
      master: master,
      cast: cast,
      textStyles: textStyles,
      sheets: sheets,
    );
    if (identical(elements, _elements)) return next;
    // copyWith sends elements to the master while it is edited, and the one
    // scene's are wanted: put them there with the master off, then back.
    return next
        .copyWith(onMaster: false, elements: elements)
        .copyWith(onMaster: onMaster);
  }

  /// withScenes is this document as a scene list. Everything that adds,
  /// removes or reorders scenes goes through here.
  CanvasDocument withScenes(List<CanvasScene> next, {int? at}) =>
      next.isEmpty ? this : copyWith(scenes: next, sceneAt: at ?? sceneAt);

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
    var list = elements;
    var i = indexOf(element.id);
    if (i < 0) return this;
    var next = [...list];
    next[i] = element;
    // The id index carried over with the one entry changed, rather than
    // built again from nothing by the first elementById of the new list:
    // a drag step is a withElement, and every reader asks.
    if (_byId[list] case var old? when identical(old[element.id], list[i])) {
      _byId[next] = Map.of(old)..[element.id] = element;
    }
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

  // --------------------------------------------------------------------------
  // Saving and reading
  // --------------------------------------------------------------------------

  /// toJson writes a document of one plain scene with no master with its
  /// elements, frames and actions at the top level; a scene list appears
  /// only when one scene cannot say something, and then nothing of a scene
  /// is written at the top level.
  Map<String, dynamic> toJson() {
    var one = scenes.length <= 1 && master == null && _plain(scene);
    var own = one ? scene.toJson() : const <String, dynamic>{};
    return {
      "version": canvasFormatVersion,
      "title": title,
      "size": size.toJson(),
      "background": background.toJson(),
      if (!guides.isDefault) "guides": guides.toJson(),
      if (estimate.toJson().isNotEmpty) "estimate": estimate.toJson(),
      "frameRate": frameRate,
      // The one scene's own, which a scene list carries otherwise.
      if (one)
        for (var key in _atTopKeys)
          if (key != "id" && own.containsKey(key)) key: own[key],
      if (targets.isNotEmpty) "targets": targets,
      if (cues.isNotEmpty) "cues": [for (var c in cues) c.toJson()],
      if (words.isNotEmpty) "words": [for (var w in words) w.toJson()],
      if (textStyles.isNotEmpty)
        "textStyles": [for (var t in textStyles) t.toJson()],
      if (scores.isNotEmpty) "scores": [for (var s in scores) s.toJson()],
      if (sheets.isNotEmpty) "sheets": [for (var s in sheets) s.toJson()],

      if (kind != _defaults.kind) "kind": kind.name,
      if (!pages.isDefault) "pages": pages.toJson(),
      if (!masterMix.isDefault) "masterMix": masterMix.toJson(),
      if (!scenesBus.isDefault) "scenesBus": scenesBus.toJson(),
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
        if (sceneAt != _defaults.sceneAt) "sceneAt": at,
        if (master != null) "master": master!.toJson(),
        if (masterOn) "masterOn": true,
        if (onMaster) "onMaster": true,
      },
      // The scene's own name and settings, so naming it does not make a
      // scene list.
      if (own.keys.any(_inSceneKey.contains) || scene.id != _onlySceneId)
        "scene": {
          "id": scene.id,
          for (var key in _inSceneKey)
            if (own.containsKey(key)) key: own[key],
        },
    };
  }

  /// _atTopKeys are the keys of a saved scene that a document of one scene
  /// writes at its own top level, and _inSceneKey those it writes under
  /// "scene". fromJson reads exactly these back.
  static const _atTopKeys = {"id", "elements", "frames", "actions"};

  /// _onlySceneId is the id of the scene of a document with no scene list.
  static const _onlySceneId = "scene1";
  static const _inSceneKey = {"name", "holds", "transition"};

  /// _plain is whether [s] saves nothing but what the one-scene form
  /// carries. Worked out from what the scene writes, so a setting added to
  /// CanvasScene makes a scene list by itself and is never left out.
  static bool _plain(CanvasScene s) => s
      .toJson()
      .keys
      .every((key) => _atTopKeys.contains(key) || _inSceneKey.contains(key));

  String encode() => const JsonEncoder.withIndent("  ").convert(toJson());

  /// _olderScenesBus is the strip a file from before scenesBus kept on each
  /// scene: the first scene's that changed anything, which now stands for
  /// them all (most were the same strip set scene by scene), or null.
  static ChannelMix? _olderScenesBus(Map<String, dynamic> json) {
    var raw = [
      ...?(json["scenes"] is List ? json["scenes"] as List : null),
      json["scene"],
    ];
    for (var s in raw.take(maxScenes + 1)) {
      if (s is! Map) continue;
      var bus = jsonSpec(s["bus"], ChannelMix.fromJson, null);
      if (bus != null && !bus.isDefault) return bus;
    }
    return null;
  }

  factory CanvasDocument.fromJson(Map<String, dynamic> json) {
    var scenes =
        jsonObjects(json["scenes"], CanvasScene.fromJson, most: maxScenes);

    // A document saved as one scene: its elements, length and actions are
    // at the top level, and its id and own settings (see _inSceneKey)
    // under "scene". With any of those it is a list of one.
    var elements = const <CanvasElement>[];
    var actions = const <TimelineAction>[];
    var frames = defaultFrameCount;
    if (scenes.isEmpty) {
      var only = CanvasScene.fromJson({
        "id": _onlySceneId,
        ...?jsonMap(json["scene"]),
        for (var key in _atTopKeys)
          if (key != "id") key: json[key],
      });
      if (only.name.isNotEmpty ||
          only.holds ||
          only.custom ||
          only.id != _onlySceneId) {
        scenes = [only];
      } else {
        elements = only.elements;
        actions = only.actions;
        frames = only.frames;
      }
    }

    // Tables and charts saved without sheets are given sheets of their own.
    return dataRefreshed(sourcesAdopted(dataAdopted(CanvasDocument(
      title: jsonString(json["title"], _defaults.title),
      size: jsonSpec(json["size"], CanvasSize.fromJson, _defaults.size),
      background: jsonSpec(
          json["background"], CanvasBackground.fromJson, _defaults.background),
      guides: jsonSpec(json["guides"], CanvasGuides.fromJson, _defaults.guides),
      elements: elements,
      estimate: jsonSpec(
          json["estimate"], CanvasEstimate.fromJson, _defaults.estimate),
      frames: frames,
      frameRate: jsonInt(json["frameRate"], _defaults.frameRate)
          .clamp(minFrameRate, maxFrameRate),
      actions: actions,
      scenes: scenes,
      sceneAt: jsonInt(json["sceneAt"], _defaults.sceneAt),
      kind: CanvasKind.fromName(jsonStr(json["kind"])),
      pages: jsonSpec(json["pages"], PagesSpec.fromJson, _defaults.pages),
      masterMix:
          jsonSpec(json["masterMix"], MasterMix.fromJson, _defaults.masterMix),
      scenesBus: jsonSpec(json["scenesBus"], ChannelMix.fromJson, null) ??
          _olderScenesBus(json) ??
          _defaults.scenesBus,
      audio: AudioSettings.fromJson(json["audio"]),
      hasCanvas: json["noCanvas"] != true,
      returns: json["returns"] is List
          ? jsonList(json["returns"], ReturnChannel.fromJson, most: maxReturns)
          : defaultReturns,
      session: SessionGrid.fromJson(json["session"]),
      game: json["game"] == true,
      gameStart: jsonString(json["gameStart"], _defaults.gameStart),
      masterOver: json["masterOver"] == true,
      playerControls: {
        if (json["playerControls"] case Map raw)
          for (var MapEntry(key: p, value: list) in raw.entries)
            if (int.tryParse("$p") case var n? when n >= 2 && n <= 4)
              if (list is List) n: jsonList(list, ControlAction.fromJson),
      },
      counts: jsonList(json["counts"], GameCount.fromJson),
      controls: json["controls"] is List
          ? jsonList(json["controls"], ControlAction.fromJson)
          : null,
      master: jsonSpec(json["master"], CanvasScene.fromJson, null),
      masterOn: jsonBool(json["masterOn"], false),
      cast: jsonObjects(json["cast"], elementFromJson, most: maxSceneElements),
      // Only where there is a master, switched on, to be on.
      onMaster: jsonBool(json["onMaster"], false) &&
          jsonBool(json["masterOn"], false) &&
          json["master"] is Map<String, dynamic>,
      targets: jsonList(json["targets"], jsonStr),
      cues: jsonList(json["cues"], TimelineCue.fromJson)
        ..sort((a, b) => a.frame.compareTo(b.frame)),
      words: jsonList(json["words"], SpokenWord.fromJson)
        ..sort((a, b) => a.frame.compareTo(b.frame)),
      textStyles: jsonList(json["textStyles"], NamedTextStyle.fromJson),
      scores: jsonObjects(json["scores"], MusicScore.fromJson),
      sheets: jsonList(json["sheets"], DataSheet.fromJson),
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

/// _byId is each list of elements' index by id (see elementById), and
/// _sceneStarts each document's scene starts (see startOfScene).
final Expando<Map<String, CanvasElement>> _byId = Expando("elementsById");
final Expando<List<int>> _sceneStarts = Expando("sceneStarts");

CanvasElement _withoutLinksTo(CanvasElement e, String id) {
  if (e is! TextElement) return e;
  var next = e;
  if (next.curve?.elementId == id) next = next.copyWith(clearCurve: true);
  if (next.flowTo == id) next = next.copyWith(flowTo: "");
  return next;
}

/// NamedTextStyle is one of the document's text styles: a name and its type.
class NamedTextStyle {
  final String name;
  final TextSpec spec;
  const NamedTextStyle(this.name, this.spec);

  NamedTextStyle mapColours(ColourMap f) {
    var next = spec.mapColours(f);
    return identical(next, spec) ? this : NamedTextStyle(name, next);
  }

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
