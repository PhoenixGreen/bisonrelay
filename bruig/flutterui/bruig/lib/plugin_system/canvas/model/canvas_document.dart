import 'dart:convert';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';

// canvas_document.dart is a whole canvas: its shape, its background, what is
// on it, and how long it runs for.
//
// Immutable, like the elements it holds. Every edit is a new document, which
// is what makes undo a list and makes the painter safe to hand a document to
// from a background isolate during export. A mutable scene graph would be the
// obvious thing and would put a "did this change under me" question into every
// one of those places.
//
// The file format is JSON with a version number on it, written to
// "<appDataDir>/canvas". Plain text on purpose: a document is a few kilobytes
// because every element is a description rather than a picture, and a format
// somebody can read in a text editor is a format they can still recover
// something from in ten years.

/// canvasFormatVersion is bumped when a saved document would be read wrongly
/// by an older build. Read on load and never used to refuse a document -- an
/// unknown future version is read as best it can be, since every field reader
/// already falls back when a field is missing or the wrong type.
const int canvasFormatVersion = 1;

/// defaultFrameRate is what a new document plays at.
///
/// Twelve rather than twenty-four or thirty. What gets made here is a tactics
/// diagram or a title moving into place, not film, and twelve is where a GIF
/// stops looking choppy while staying a quarter of the size of a 30fps one --
/// which matters when the result has to fit in a chat message.
const int defaultFrameRate = 12;

/// defaultFrameCount is one second at [defaultFrameRate]. A new document is
/// deliberately a still: one frame's worth of timeline, so the timeline is
/// visible and explains itself without a still picture having to be an
/// animation nobody asked for.
const int defaultFrameCount = 1;

const int maxFrameCount = 3600;

/// CanvasBackground is what is behind everything, covering the whole document.
///
/// Either a picture or a generated pattern, never both -- an image wins when
/// there is one, and clearing it falls back to whatever the pattern was, so
/// trying a photograph behind a design and then changing your mind does not
/// lose the gradient that was there before.
class CanvasBackground {
  final ProceduralSpec spec;

  /// imageAssetId, when set, is drawn instead of the generator.
  final String imageAssetId;
  final ImageFit imageFit;

  const CanvasBackground({
    this.spec = const ProceduralSpec(),
    this.imageAssetId = "",
    this.imageFit = ImageFit.cover,
  });

  bool get isImage => imageAssetId.isNotEmpty;

  CanvasBackground copyWith({
    ProceduralSpec? spec,
    String? imageAssetId,
    ImageFit? imageFit,
  }) =>
      CanvasBackground(
        spec: spec ?? this.spec,
        imageAssetId: imageAssetId ?? this.imageAssetId,
        imageFit: imageFit ?? this.imageFit,
      );

  Map<String, dynamic> toJson() => {
        "spec": spec.toJson(),
        if (isImage) "image": imageAssetId,
        if (isImage) "fit": imageFit.name,
      };

  factory CanvasBackground.fromJson(Map<String, dynamic> json) =>
      CanvasBackground(
        spec: jsonSpec(
            json["spec"], ProceduralSpec.fromJson, const ProceduralSpec()),
        imageAssetId: jsonString(json["image"], ""),
        imageFit: ImageFit.fromName(json["fit"] as String?),
      );
}

/// CanvasDocument is the whole thing.
class CanvasDocument {
  /// title is what the document is called in the library. Not the filename --
  /// see storage/canvas_storage.dart, which sanitises one into the other.
  final String title;

  final CanvasSize size;
  final CanvasBackground background;

  /// guides is the scaffolding the canvas is laid out against -- the grid, the
  /// lines the reader put down, the rulers and what snaps to what. See
  /// [CanvasGuides]; it belongs to the document because it is the reason
  /// everything on the canvas lines up.
  final CanvasGuides guides;

  /// scenes are the canvases this document plays, in order.
  ///
  /// Empty means the one scene held in the fields below, which is what a
  /// document written before scenes existed is and what a new one still is.
  /// That is the whole trick of this change: everything above this file goes
  /// on asking a document for its elements, its length and its actions, and
  /// gets the scene being edited -- so a document with one scene behaves
  /// exactly as it did, and nothing had to learn a new word to keep working.
  final List<CanvasScene> scenes;

  /// sceneAt is which scene is being edited and played.
  final int sceneAt;

  /// master is the scene whose elements appear on every other one, or null
  /// where there is none. See masterOn: it is kept when switched off, so
  /// turning it off is not the same as throwing it away.
  final CanvasScene? master;
  final bool masterOn;

  /// onMaster is whether the master canvas is the one being edited.
  ///
  /// A document-level fact rather than a flag in the editor, and that is what
  /// makes the master canvas cost almost nothing: with it set, a document
  /// answers for the master when it is asked for its elements, so every
  /// panel, the stage, the layer list and the settings edit the master
  /// without knowing there is such a thing.
  final bool onMaster;

  /// _elements, _frames and _actions hold the single scene of a document that
  /// has no scene list. Read through [elements], [frames] and [actions],
  /// which answer for the scene being edited whichever way the document is
  /// arranged.
  final List<CanvasElement> _elements;

  /// estimate is which file this canvas is meant to become, for the size the
  /// settings band shows. See [CanvasEstimate].
  ///
  /// On the document because it is a decision about the canvas rather than
  /// about the editor: the same design is four hundred kilobytes as a PNG and
  /// forty as a JPEG, and which of those somebody is watching is a fact about
  /// what they are making.
  final CanvasEstimate estimate;

  final int _frames;

  /// frameRate belongs to the document rather than to a scene: it is how fast
  /// the whole thing plays, and two scenes running at different speeds would
  /// be two films.
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
    this.master,
    this.masterOn = false,
    this.onMaster = false,
  })  : _elements = elements,
        _frames = frames,
        _actions = actions;

  /// at is the scene being edited, always a real place in the list.
  int get at => scenes.isEmpty ? 0 : sceneAt.clamp(0, scenes.length - 1);

  /// editingMaster is whether the master canvas is what the editor is
  /// showing: switched on, and asked for.
  bool get editingMaster => onMaster && masterOn && master != null;

  /// elements, frames and actions are the scene being edited. See [scenes].
  List<CanvasElement> get elements => editingMaster
      ? master!.elements
      : (scenes.isEmpty ? _elements : scenes[at].elements);

  /// frames is the length of the scene being edited. One means a still.
  ///
  /// The master canvas is as long as the whole sequence, worked out rather
  /// than stored: it is the thing every scene plays under, so its length is
  /// not its own to keep and has to follow scenes being added, removed and
  /// made longer.
  int get frames => editingMaster
      ? sequenceFrames
      : (scenes.isEmpty ? _frames : scenes[at].frames);

  List<TimelineAction> get actions => editingMaster
      ? master!.actions
      : (scenes.isEmpty ? _actions : scenes[at].actions);

  /// scene is the scene being edited -- never the master, which is not one
  /// of the scenes however much of the editor it is standing in for. Asked
  /// for the master while it was showing, allScenes answered with it and the
  /// scene it was covering disappeared out of the list.
  CanvasScene get scene => scenes.isEmpty
      ? CanvasScene(
          id: "scene1", elements: _elements, frames: _frames, actions: _actions)
      : scenes[at];

  /// editing is the canvas in front of the reader: the master where that is
  /// showing, and the scene otherwise.
  CanvasScene get editing => editingMaster ? master! : scene;

  /// sequenceFrames is how long the whole document runs for: every scene, and
  /// the frames a transition takes off where two of them overlap.
  int get sequenceFrames {
    var list = allScenes;
    var total = 0;
    for (var i = 0; i < list.length; i++) {
      total += _stepOf(i);
    }
    return total.clamp(1, maxFrameCount).toInt();
  }

  /// playFrames is how long this document runs for when it is played or
  /// published: the whole sequence where there are scenes, and the one
  /// scene's own length where there are not.
  ///
  /// Asked by the export and by anything that plays the document through. The
  /// editor's timeline asks [frames] instead, which is the canvas in front of
  /// the reader -- the two are the same thing until a document has a second
  /// scene, and then they are exactly not.
  int get playFrames => hasScenes ? sequenceFrames : frames;

  /// startOfScene is the frame the sequence reaches [index] on.
  int startOfScene(int index) {
    var reached = 0;
    for (var i = 0; i < index && i < allScenes.length; i++) {
      reached += _stepOf(i);
    }
    return reached;
  }

  /// sceneStep is how a scene fits into the run: how far the sequence moves
  /// on before the next one starts, how many frames the two scenes share, and
  /// how long the transition between them lasts.
  ///
  /// One answer, asked by the length of the document, by where each scene
  /// starts and by what is drawn at a given moment -- see placeInSequence,
  /// which used to work it out a second time. Two opinions about where scene
  /// four starts is a canvas that exports differently from the one on screen,
  /// and they had already drifted: this one counted a transition longer than
  /// its overlap as taking no time at all.
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
    // This scene, less the frames the next one starts early by, plus whatever
    // is left of the transition once the sharing has ended -- which is its
    // own stretch of time, with the scene leaving held on its last frame and
    // the one arriving not started.
    return (scene.frames - held + (over.frames - held), held, over.frames);
  }

  /// _stepOf is the first of those three: how far the run moves on.
  int _stepOf(int index) => sceneStep(index).$1;

  /// allScenes is every scene in order, whichever way the document is
  /// arranged. What the Scenes panel lists and what a whole-document export
  /// plays through.
  List<CanvasScene> get allScenes => scenes.isEmpty ? [scene] : scenes;

  /// hasScenes is whether this document is more than one canvas. The parts of
  /// the editor that only exist for scenes -- the counter in the bar, the
  /// transitions on the timeline -- ask this rather than counting.
  bool get hasScenes => scenes.length > 1;

  /// masterScene is the shared canvas when it is switched on, and null
  /// otherwise. Asked by the painter, which must not draw a master that has
  /// been turned off.
  CanvasScene? get masterScene => masterOn ? master : null;

  /// drawnBackground is what is actually behind the canvas being shown.
  ///
  /// Three answers in order: the shared canvas's own while the master is
  /// switched on, then this scene's own, then the document's. So a backdrop
  /// put on the master comes and goes with it, a scene given its own keeps
  /// it, and a document that has never been asked the question goes on
  /// showing the one background it has always had.
  CanvasBackground get drawnBackground => editingMaster
      ? (master!.background ?? background)
      : (masterScene?.sharedBackground ?? scene.background ?? background);

  /// ownBackground is the backdrop the canvas being edited owns: its own
  /// where it has been given one, and the document's until then.
  ///
  /// What the settings panel shows and edits. Not [drawnBackground], which
  /// answers what is *on screen* -- while the shared canvas has a backdrop
  /// that is the master's, and a panel that showed it would be offering to
  /// edit one canvas's settings from another canvas's panel.
  CanvasBackground get ownBackground => editingMaster
      ? (master!.background ?? background)
      : (scene.background ?? background);

  /// backgroundOf is the backdrop of one scene, for the painter that draws
  /// the whole run rather than the canvas in front of the reader.
  CanvasBackground backgroundOf(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return background;
    return masterScene?.sharedBackground ??
        list[index].background ??
        background;
  }

  /// defaultTransition is what a scene with no transition of its own uses:
  /// the master scene's, or a cut.
  SceneTransition get defaultTransition =>
      master?.transition ?? SceneTransition.cut;

  /// transitionAfter is how scene [index] gives way to the next one.
  SceneTransition transitionAfter(int index) {
    var list = allScenes;
    if (index < 0 || index >= list.length) return SceneTransition.cut;
    return list[index].transition ?? defaultTransition;
  }

  /// sceneNamed finds a scene by id or by name, for a button that goes to
  /// one. By id first: a name can be changed and can be shared by two
  /// scenes, and an action that quietly went somewhere else after a rename
  /// would be worse than one that stopped working.
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

  /// durationSeconds is what the timeline reports and what the GIF export
  /// uses to work out its frame delays.
  double get durationSeconds => frames / (frameRate <= 0 ? 1 : frameRate);

  /// assetIds is every stored picture this document refers to.
  ///
  /// What a sweep of the picture store measures against: anything not named
  /// by some saved document is a picture nothing can ever show again, and is
  /// deleted. So anything missed here is a picture that quietly disappears
  /// between one session and the next.
  ///
  /// Which is what happened twice over. It read `elements`, and that is the
  /// scene being edited rather than all of them, so every picture in every
  /// other scene -- and on the shared canvas -- was fair game while scene one
  /// was open. And it knew about a background's own picture but not about the
  /// ones its rings carry, so an icon vanished on the next restart.
  Set<String> get assetIds {
    var ids = <String>{};

    void fromBackground(CanvasBackground? bg) {
      if (bg == null) return;
      if (bg.imageAssetId.isNotEmpty) ids.add(bg.imageAssetId);
      for (var icon in bg.spec.rings.icons) {
        if (icon.asset.isNotEmpty) ids.add(icon.asset);
      }
    }

    void fromElements(List<CanvasElement> list) {
      for (var e in list) {
        ids.addAll(e.assetIds);
        // A background *element* carries a design of its own, and that design
        // can carry pictures too.
        if (e is BackgroundElement) {
          for (var icon in e.spec.rings.icons) {
            if (icon.asset.isNotEmpty) ids.add(icon.asset);
          }
        }
      }
    }

    fromBackground(background);
    // Every scene, not the one being looked at -- allScenes answers with the
    // document's own single canvas where there are no scenes.
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

  /// hasKeyframes is whether anything in this document moves.
  ///
  /// Asks the players as well as the elements, for the same reason
  /// [lastAnimatedFrame] does: a team's movement lives on its players, so a
  /// pitch full of runs looks like a still from the outside.
  bool get hasKeyframes {
    for (var e in elements) {
      if (e.track?.isEmpty == false) return true;
      if (e is TeamElement) {
        for (var p in e.players) {
          if (p.track?.isEmpty == false) return true;
        }
      }
    }
    return false;
  }

  /// withoutKeyframes is this document with every track taken off.
  ///
  /// Paths keep their points. A point is where the curve goes rather than a
  /// pose, so clearing the animation should leave the routes drawn and empty
  /// -- re-applying one is a button press, redrawing it is not.
  CanvasDocument withoutKeyframes() => copyWith(elements: [
        for (var e in elements)
          if (e is TeamElement)
            e.copyWith(players: [
              for (var p in e.players) p.copyWith(clearTrack: true),
            ]).withBase(clearTrack: true)
          else
            e.withBase(clearTrack: true),
      ]);

  /// lastAnimatedFrame is the furthest frame any element has a keyframe on.
  ///
  /// Asked so the timeline can point out a document whose length is shorter
  /// than the animation drawn on it -- keyframes past the end are not lost,
  /// they are simply never reached, and that is confusing enough to be worth
  /// saying out loud rather than silently trimming somebody's work.
  int get lastAnimatedFrame {
    var last = 0;
    for (var e in elements) {
      var f = e.track?.lastFrame ?? 0;
      if (f > last) last = f;
      // A team's movement is on its players, not on the team, so asking the
      // element alone would report a pitch full of runs as a still.
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
    for (var e in elements) {
      if (e.id == id) return e;
    }
    return null;
  }

  int indexOf(String id) => elements.indexWhere((e) => e.id == id);

  /// copyWith changes the document, and where it is given elements, a length
  /// or actions those go to the scene being edited.
  ///
  /// That is what keeps every caller working. An edit is still "a document
  /// with this element replaced"; which canvas it lands on is this file's
  /// business rather than every panel's.
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
    CanvasScene? master,
    bool clearMaster = false,
    bool? masterOn,
    bool? onMaster,
  }) {
    var list = scenes ?? this.scenes;
    var index = (sceneAt ?? this.sceneAt)
        .clamp(0, math.max(0, list.length - 1))
        .toInt();

    // Into the master canvas, when that is the one being edited. Its length
    // is not its own -- see frames -- so a length written here is dropped
    // rather than kept and quietly ignored.
    var onIt = onMaster ?? this.onMaster;
    var shared = clearMaster ? null : (master ?? this.master);
    if (onIt &&
        shared != null &&
        master == null &&
        (elements != null || actions != null)) {
      shared = shared.copyWith(elements: elements, actions: actions);
    }

    // Into the scene being edited, where there is a list of them.
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
      // document with no scene list has. It did: the two are held in
      // different places and both were being written.
      elements: list.isEmpty
          ? (onIt && shared != null ? _elements : (elements ?? _elements))
          : const [],
      estimate: estimate ?? this.estimate,
      frames: list.isEmpty
          ? (onIt && shared != null
              ? _frames
              : (frames ?? _frames).clamp(1, maxFrameCount).toInt())
          : 1,
      frameRate: (frameRate ?? this.frameRate).clamp(1, 60),
      actions: list.isEmpty
          ? (onIt && shared != null ? _actions : (actions ?? _actions))
          : const [],
      scenes: list,
      sceneAt: index,
      master: shared,
      masterOn: masterOn ?? this.masterOn,
      onMaster: onIt,
    );
  }

  /// withScenes is this document as a list of scenes, whichever way it was
  /// arranged before.
  ///
  /// Everything that adds, removes or reorders scenes goes through here, so
  /// that a document with one scene in its old shape becomes a list the
  /// moment a second one is wanted -- and nowhere else has to know there were
  /// two shapes.
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
      master: master,
      masterOn: masterOn,
      onMaster: onMaster,
    );
  }

  /// withScene replaces one scene.
  CanvasDocument withScene(int index, CanvasScene next) {
    var list = [...allScenes];
    if (index < 0 || index >= list.length) return this;
    list[index] = next;
    return withScenes(list);
  }

  /// addScene puts a new empty canvas after [after], or at the end.
  CanvasDocument addScene({int? after, String name = ""}) {
    var list = [...allScenes];
    var to =
        after == null ? list.length : (after + 1).clamp(0, list.length).toInt();
    list.insert(to, CanvasScene(id: newSceneId(), name: name, frames: frames));
    return withScenes(list, at: to);
  }

  /// duplicateScene copies one, elements and all, under new ids.
  ///
  /// New ids for the elements as well as for the scene: two scenes holding
  /// the same element id would be one element in two places, and editing it
  /// in one would edit it in the other.
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

  /// removeScene takes one out. The last one left stays: a document with no
  /// canvas in it is not a document.
  CanvasDocument removeScene(int index) {
    var list = [...allScenes];
    if (list.length <= 1 || index < 0 || index >= list.length) return this;
    list.removeAt(index);
    return withScenes(list, at: math.min(sceneAt, list.length - 1));
  }

  /// moveScene reorders, which is the order they play in.
  CanvasDocument moveScene(int from, int to) {
    var list = [...allScenes];
    if (from < 0 || from >= list.length) return this;
    var moved = list.removeAt(from);
    list.insert(to.clamp(0, list.length).toInt(), moved);
    return withScenes(list, at: to.clamp(0, list.length - 1).toInt());
  }

  /// goToScene is which one is being edited and played.
  CanvasDocument goToScene(int index) {
    if (scenes.isEmpty) return this;
    return copyWith(sceneAt: index.clamp(0, scenes.length - 1).toInt());
  }

  /// withMaster changes the shared canvas, making one if there is none.
  CanvasDocument withMaster(CanvasScene next) =>
      copyWith(master: next, masterOn: masterOn);

  /// withElement replaces the element sharing [element]'s id, or does nothing
  /// if it has since been deleted.
  ///
  /// Doing nothing is deliberate. A settings control that is still holding a
  /// deleted element -- which happens, because a panel is torn down one frame
  /// after the delete -- must not put it back.
  CanvasDocument withElement(CanvasElement element) {
    var i = indexOf(element.id);
    if (i < 0) return this;
    var next = [...elements];
    next[i] = element;
    return copyWith(elements: next);
  }

  CanvasDocument addElement(CanvasElement element) =>
      copyWith(elements: [...elements, element]);

  /// removeElement takes an element out, and takes the references to it with
  /// it.
  ///
  /// A text element attached to a line it names, or flowing its overflow into
  /// a box it names, is holding an id -- and an id that names nothing is a
  /// setting that cannot be seen or undone: the words fell back to their own
  /// box on the canvas while the panel still said they were placed by a line,
  /// and the fields for moving them were not there.
  ///
  /// A button's action is deliberately not cleaned up here: an action
  /// pointing at something that has gone is a button that does nothing, which
  /// is exactly what deleting its target should leave behind.
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

  /// toJson writes the file.
  ///
  /// A document of one scene with no master is written exactly as it was
  /// before scenes existed: elements, frames and actions at the top level. So
  /// a canvas made in this build opens in an older one, and -- more to the
  /// point -- every canvas already saved opens here unchanged. The scene list
  /// appears only once there is something a single scene cannot say.
  Map<String, dynamic> toJson() {
    var one = scenes.length <= 1 && master == null;
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
      "elements": elements.map((e) => e.toJson()).toList(),
      if (!one) ...{
        "scenes": [for (var s in allScenes) s.toJson()],
        if (sceneAt != 0) "sceneAt": at,
        if (master != null) "master": master!.toJson(),
        if (masterOn) "masterOn": true,
        if (onMaster) "onMaster": true,
      },
      // The one scene's own name and settings, which the top-level fields
      // cannot carry. Written for a single scene as well, so naming the first
      // scene of a document is not what turns it into a scene list.
      if (one && (scene.name.isNotEmpty || scene.holds || scene.custom))
        "scene": {
          if (scene.name.isNotEmpty) "name": scene.name,
          "id": scene.id,
          if (scene.holds) "holds": true,
          if (scene.custom) "transition": scene.transition!.toJson(),
        },
    };
  }

  String encode() => const JsonEncoder.withIndent("  ").convert(toJson());

  factory CanvasDocument.fromJson(Map<String, dynamic> json) {
    var raw = json["elements"];
    var acts = json["actions"];

    // A scene list, where there is one. Everything else -- the page, the
    // guides, what it will be published as -- belongs to the document and is
    // read the same way either way.
    var sceneList = json["scenes"];
    var scenes = <CanvasScene>[
      if (sceneList is List)
        for (var it in sceneList)
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
            for (var e in raw)
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
      // One scene with something to say for itself: held as a list of one, so
      // there is somewhere to keep it.
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

    return CanvasDocument(
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
      frameRate: jsonInt(json["frameRate"], defaultFrameRate).clamp(1, 60),
      actions: scenes.isEmpty ? actions : const [],
      scenes: scenes,
      sceneAt: jsonInt(json["sceneAt"], 0),
      master: json["master"] is Map<String, dynamic>
          ? CanvasScene.fromJson(json["master"] as Map<String, dynamic>)
          : null,
      masterOn: jsonBool(json["masterOn"], false),
      onMaster: jsonBool(json["onMaster"], false),
    );
  }

  /// decode reads a saved file, returning null rather than throwing.
  ///
  /// A document that will not parse is a document the user still has on disk,
  /// and the right response is to say so and leave the file alone -- not to
  /// crash the page it was opened from, and certainly not to overwrite it with
  /// an empty canvas.
  static CanvasDocument? decode(String text) {
    try {
      var json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return CanvasDocument.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}

/// _withoutLinksTo is [e] with any reference to the element [id] dropped.
CanvasElement _withoutLinksTo(CanvasElement e, String id) {
  if (e is! TextElement) return e;
  var next = e;
  if (next.curve?.elementId == id) next = next.copyWith(clearCurve: true);
  if (next.flowTo == id) next = next.copyWith(flowTo: "");
  return next;
}

/// elementFromJson turns one saved element back into the right subclass.
///
/// An unknown kind becomes a plain rectangle rather than being dropped. A
/// document written by a newer build and opened here has an element in it
/// somewhere; leaving a visible placeholder where it was is recoverable, and
/// silently deleting it is not.
CanvasElement elementFromJson(Map<String, dynamic> json) {
  var kind = ElementKind.values.firstWhere(
    (k) => k.name == json["kind"],
    orElse: () => ElementKind.shape,
  );
  var base = ElementBase.fromJson(json, kind.label);
  switch (kind) {
    case ElementKind.text:
      return TextElement.fromJson(json, base);
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
  }
}
