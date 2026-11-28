import 'dart:collection';
import 'dart:ui' show Offset, Path, Rect;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show ValueListenable, listEquals, setEquals;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show TimelineAction;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_rulers.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart'
    show SceneTransition;
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart'
    show MetronomeShow;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_transform.dart';

// stage_painter_inputs.dart is what StagePainter draws from: nine values,
// each a record of what one subject of the stage sets and one part of the
// paint reads. A record is equal when every field is, so the painter's
// shouldRepaint compares them whole and a field added to one is compared
// without anything else being written. A list or set inside one is an
// EqualList or EqualSet, compared by what it holds; what cannot be compared
// at all is a NotCompared, with what stands in for it beside it.

/// NotCompared holds what equality cannot look at: a closure, or a list grown
/// in place. Any two are equal, so the record holding one keeps beside it a
/// value that changes whenever its answers do, and says which.
final class NotCompared<T> {
  final T value;
  const NotCompared(this.value);

  @override
  bool operator ==(Object other) => other is NotCompared<T>;

  // Equal to every other, so the same hash for all.
  @override
  int get hashCode => 0;
}

/// EqualList is a list compared by its items, in order. It keeps a copy of
/// what it was made from, so a list changed later cannot change it.
class EqualList<E> extends UnmodifiableListView<E> {
  EqualList(Iterable<E> items) : super(List<E>.of(items, growable: false));

  @override
  bool operator ==(Object other) =>
      other is EqualList<E> && listEquals<E>(this, other);

  @override
  int get hashCode => Object.hashAll(this);
}

/// EqualSet is a set compared by its members. It keeps a copy of what it was
/// made from, as EqualList does.
class EqualSet<E> extends UnmodifiableSetView<E> {
  EqualSet(Iterable<E> members) : super(Set<E>.of(members));

  @override
  bool operator ==(Object other) =>
      other is EqualSet<E> && setEquals<E>(this, other);

  @override
  int get hashCode => Object.hashAllUnordered(this);
}

/// StageInputs is everything StagePainter draws from. Each value is made by
/// its own builder in CanvasStageState (_stagePainter and those after it).
typedef StageInputs = ({
  /// transform is how the page sits in the window: where it is drawn, its
  /// scale, the spread, the overspill and a game's level round it.
  StageTransform transform,
  StageShown shown,
  StageLive live,
  StageSelectionMarks selection,
  StageElementMarks elements,
  StageToolMarks tools,
  StageRetouchMarks retouch,
  StageGuideMarks guides,

  /// text is the text element being typed into, whose words are left to
  /// the editor over the top, or null.
  StageTextEdit? text,
});

/// StageShown is which page is drawn, at which frame, and how it is being
/// played or previewed.
typedef StageShown = ({
  /// document is the page drawn: the controller's, or a game's own view
  /// while it plays.
  CanvasDocument document,
  int frame,

  /// facing is the page drawn beside the one being edited: its index, and
  /// the frame it was left at and is drawn at. Null when the page stands
  /// alone. Drawn only, with no handles, guides or selection, so only one
  /// canvas is edited at a time.
  ({int index, int frame})? facing,

  /// previewAt is a frame of the whole run while a transition is watched,
  /// drawn with the export's own paintSequenceFrame.
  int? previewAt,

  /// previewing is the one element being previewed, at its own frame.
  ({String id, int frame})? previewing,

  /// gameChange is the scene a game is leaving while its transition plays
  /// (as seen, its frame, the transition and how far through), drawn giving
  /// way to [document].
  (CanvasDocument, int, SceneTransition, double, LiveMotion)? gameChange,

  /// camera is how the page is framed while it is seen through a camera:
  /// the scene's while it plays or in camera view, or a game's own. Null
  /// otherwise, so a press lands where the page looks to be.
  (double, Offset)? camera,

  /// directed is whether the page is seen through its Camera, which on a 3D
  /// stage is the stage's camera (see camera_3d.dart).
  bool directed,

  /// markerNote is the marker playback holds at, its label drawn on the
  /// canvas (see marker_note.dart); markerNoteGrip shows its drag grip.
  TimelineAction? markerNote,
  bool markerNoteGrip,
});

/// StageLive is what is drawn from outside the document: pictures, the
/// rasterised backgrounds, and the session's state of what plays, sounds
/// and counts. Its closures are not compared; each has a tick beside it
/// that changes whenever its answers do.
typedef StageLive = ({
  /// images are the pictures, arriving after the frame that asked for
  /// them; the painter listens to it.
  CanvasImageSource images,

  /// backgrounds is the editor's rasterised background, or null in a test;
  /// the painter listens to it.
  ProceduralCache? backgrounds,

  /// between is how far past the frame the playhead has got while playing
  /// (see scene_renderer's betweenFrames), listened to; null when nothing
  /// is drawn between.
  ValueListenable<double>? between,

  /// drafting draws rasterised work (adjustments, effects) smaller during a
  /// gesture; see RasterCache.drafting.
  bool drafting,

  /// hoveredButton is the button element under the pointer, drawn lit.
  String? hoveredButton,

  /// counterHover is the run under the pointer and which of its
  /// buttons, drawn lit; id null and button -1 when there is none.
  ({String? id, int button}) counterHover,

  /// liveMotion is what plays from slots; motionTick rises as it plays on
  /// and stands in for it.
  NotCompared<LiveMotion?> liveMotion,
  int motionTick,

  /// counterValue is what a live counter shows now, and counterRunning
  /// whether it runs: session state, not design. counterTick changes when
  /// a running counter moves, and stands in for both.
  NotCompared<double Function(CounterElement)> counterValue,
  NotCompared<bool Function(CounterElement)> counterRunning,
  int counterTick,

  /// metronomeShow is how each metronome is going: session state, for which
  /// keysTick stands in (it rises as one swings).
  NotCompared<MetronomeShow Function(MetronomeElement)> metronomeShow,

  /// audioState is each speaker's sound and videoShow each video's frame;
  /// audioRevision changes with either, and stands in for both.
  NotCompared<AudioState Function(AudioElement)> audioState,
  NotCompared<VideoShow Function(VideoElement)> videoShow,
  int audioRevision,

  /// keysTick is the controller's keysHeld, changing as a key is pressed or
  /// let go, as a synth's screens tick while a note sounds (which the
  /// renderer reads from the controller rather than from here) and as a
  /// metronome swings.
  int keysTick,

  /// spritePaintTick changes with each stroke on a sprite being painted,
  /// whose pixels are not the document's until the pen lifts; -1 when none.
  int spritePaintTick,

  /// tilePaintTick changes with each change to a map being painted; -1
  /// when none.
  int tilePaintTick,
});

/// StageSelectionMarks is the selection as the stage marks it: its box,
/// handles and ring, each element of several outlined, a reused element's
/// copies, its motion trail, and its anchors.
typedef StageSelectionMarks = ({
  /// ids is the elements selected.
  EqualSet<String> ids,

  /// bounds is the box round the selection in document units, or null when
  /// it has none.
  Rect? bounds,

  /// frame is the selection box's turn and slant, as the stage's own hit
  /// test lays it (CanvasStageState._frameOfSelection), so handles are
  /// drawn where they are taken (see stageHandleAt).
  BoxFrame frame,

  /// showHandles is false for something whose size and angle belong to
  /// another element (text riding a line): its handles would do nothing.
  bool showHandles,

  /// showHelpers draws the selection box, handles and rotation ring, and
  /// every mark on elements. A flag of its own: the selection's box is
  /// drawn from [bounds], so emptying the selection would not hide them.
  bool showHelpers,

  /// pickedCopies are the picked copies of a reused element (paintCopies).
  EqualSet<String> pickedCopies,

  /// trail shows the selected element's trail and onion skin while the
  /// Chain is open on its motion (see paintTrail).
  bool trail,

  /// anchors are the anchor points shown, on the page.
  EqualList<({Offset at, bool locked})> anchors,
});

/// StageElementMarks is what is marked on elements other than by the
/// selection's box: every element's box, cameras, game touch areas, a
/// text's flow links and grips, a chart's labels, a table's column rules, a
/// Layout's lines, and a path's points.
typedef StageElementMarks = ({
  /// showAllBounds outlines every element rather than only the selected one.
  bool showAllBounds,

  /// camerasShown is whether each Camera's frame is drawn over the page:
  /// the stage's rule, which its hit test asks too (_camerasShown).
  bool camerasShown,

  /// touchAreas are each played element's touch area, drawn while the Game
  /// tab is open (see gameTouchArea).
  EqualList<Rect> touchAreas,

  /// flowGrips are the two dots on a selected text box.
  TextFlowGrips? flowGrips,

  /// flowLines are the links between text boxes worth drawing this frame.
  EqualList<FlowLine> flowLines,

  /// flowDrag is the link being dragged, from its box to the pointer.
  FlowLine? flowDrag,

  /// chartLabels is the boxes of the selected chart's placed labels, in its
  /// box (laid on the page by [partsPlace]), outlined to show they can be
  /// taken hold of, each with whether it has a resize grip (see
  /// chartLabelResizes).
  EqualList<({Rect rect, bool grip})> chartLabels,

  /// layout is the selected Layout's picked cell and the lines that can be
  /// dragged, in document units (stage_layouts.dart).
  LayoutMarks? layout,

  /// tableColumns is where a selected table's column rules are, in its box
  /// (laid on the page by [partsPlace]), each given a drag grip.
  EqualList<(double, double, double)> tableColumns,

  /// partsPlace is where the painter lays out the chart or table whose
  /// [chartLabels] or [tableColumns] are shown (ElementPlace), so their
  /// marks sit on the parts as drawn; null for neither.
  ElementPlace? partsPlace,

  /// selectedPath is the selected path, drawn with points and handles.
  /// Compared by identity: the document keeps the element it holds.
  PathElement? selectedPath,

  /// pathPlace is where the painter lays [selectedPath] out on this frame
  /// (ElementPlace), so its points are drawn where it is drawn.
  ElementPlace? pathPlace,
});

/// LayoutMarks is what the stage shows of a selected Layout: its lines
/// that can be dragged, and its picked cell's outline, in document units.
typedef LayoutMarks = ({
  EqualList<(Offset, Offset)> lines,

  /// picked is the picked cell's outline. A Path cannot be compared, so
  /// pickedCell stands in for it: the outline follows from that cell and
  /// the Layout, which the document and the selection hold.
  NotCompared<Path?> picked,
  String? pickedCell,

  /// knobs is each Panels cut's own: its turn knob, and its gutter knob
  /// with the gutter's two edges beside it (see stage_layouts.dart).
  EqualList<LayoutCutKnobs> knobs,

  /// badges is each cell's place in the reading order, at its middle.
  EqualList<LayoutBadge> badges,
});

/// LayoutBadge is a cell's reading number on the stage: [number] null for
/// one left out; [ordering] while the order is being clicked.
typedef LayoutBadge = ({Offset at, int? number, bool ordering});

/// LayoutCutKnobs is where one cut's knobs are on the page: [turn] tilts
/// it, [gutter] widens its gutter, whose edges run [edgeA] and [edgeB].
typedef LayoutCutKnobs = ({
  Offset turn,
  Offset gutter,
  (Offset, Offset) edgeA,
  (Offset, Offset) edgeB,
});

/// StageToolMarks is what the tool in hand draws over the page: a drawing
/// edited point by point, a picture's layers or its reframing, the knife,
/// a drawing's text caret, and the box being dragged.
typedef StageToolMarks = ({
  /// vector is the drawing being edited point by point, drawn in place of
  /// a selection box.
  StageVectorEdit? vector,

  /// layers is the layers of the picture being edited. It has no equality
  /// of its own and is made afresh at each build, so the stage repaints at
  /// every build while it is shown.
  StageLayers? layers,

  /// framing is a picture being repositioned inside its frame.
  StageFraming? framing,

  /// knife is the knife's line, on the page, while being drawn.
  EqualList<Offset> knife,

  /// caret is a drawing's text caret, top to bottom, on the page.
  (Offset, Offset)? caret,

  /// marquee is the box being dragged, whichever kind it is, on the page.
  Rect? marquee,
});

/// StageVectorEdit is a drawing being edited point by point, with its picked
/// shape and point.
typedef StageVectorEdit = ({
  VectorElement element,
  int shape,
  VectorPick? pick,
  EqualSet<VectorPick> picks,

  /// boxing is whether a box is being dragged over its points, and boxed
  /// the points inside it, shown picked.
  bool boxing,
  EqualSet<VectorPick> boxed,

  /// bare puts the points and their box away (tint, or the pencil with
  /// points hidden).
  bool bare,

  /// mirror is the pencil's mirror lines, or null for another tool.
  ({bool across, bool down})? mirror,

  /// shapeBox is the box round the picked shape, in the drawing's units,
  /// and turnable whether it has a turn knob.
  Rect? shapeBox,
  bool turnable,

  /// combining is the shapes picked to combine, for the combine tool.
  EqualSet<int>? combining,
});

/// StageFraming is a picture being repositioned inside its frame. [src] is
/// the whole picture and [dst] where all of it lands, larger than [frame];
/// drawn faintly, so what is dragged out of shot stays visible.
typedef StageFraming = ({
  ui.Image image,
  Rect src,
  Rect dst,

  /// frame is the element's rectangle: the part of [dst] kept, drawn at full
  /// strength by the renderer underneath.
  Rect frame,

  /// rotation is the element's, in radians.
  double rotation,

  /// pivot is the middle of the element's frame, which is not the picture's
  /// middle in a frame grown round layers.
  Offset? pivot,
  bool flipX,
  bool flipY,
});

/// StageRetouchMarks is the retouching brush on a picture: what a held
/// stroke would do, and the stroke being drawn.
typedef StageRetouchMarks = ({
  /// preview is a picture of what a held stroke would do, its source
  /// rectangle and where it is drawn in canvas units; null when nothing is
  /// held. A placement, not a destination: "fill the box" crops the
  /// picture, so stretching the preview into the element would misplace
  /// the tint.
  ({ui.Image image, Rect src, Rect dst})? preview,

  /// stroke is the retouching stroke being drawn, in canvas coordinates,
  /// with radius its width and keeps which way it works. Drawn here because
  /// changing the picture reprocesses every pixel; the picture catches up
  /// when the pointer comes up. The stroke is one list, grown in place and
  /// handed to each painter in turn, so strokeLength, how many points it
  /// had when this was made, stands in for it.
  NotCompared<List<Offset>> stroke,
  int strokeLength,
  double radius,
  bool keeps,
});

/// StageGuideMarks is the grid, the guides, what a drag is caught on, and
/// the rulers.
typedef StageGuideMarks = ({
  /// canvas is the canvas's grid and the reader's guide lines: drawn here,
  /// never by the renderer, so nothing published has a grid. Compared by
  /// identity: the document keeps one until they change.
  CanvasGuides canvas,

  /// inView is whether the grid and guides are drawn: not while the page
  /// plays (see CanvasStageState._guidesInView). The rulers stay.
  bool inView,

  /// snapped is the line or lines a drag is caught on, drawn bright so a
  /// snap is never a mysterious jump.
  SnapLines? snapped,

  /// rulers is which edges carry a ruler: the person's, not the canvas's
  /// (CanvasController.rulers), so not in [canvas].
  CanvasRulers rulers,
});

/// StageTextEdit is the text element being typed into and the piece of it
/// the editor is on.
typedef StageTextEdit = ({String element, String? item});

/// StageWarp is a warp grid as the stage draws it; see StageLayers.warp.
class StageWarp {
  final List<List<Offset>> lines;
  final List<Offset> points;
  final Set<int> picks;
  final List<Offset>? box;
  final Offset? knob;
  const StageWarp(
      {required this.lines,
      required this.points,
      required this.picks,
      this.box,
      this.knob});
}

/// StageLayers is what the stage draws over a picture whose layers are being
/// edited, in document units: the corners of every layer not picked, and the
/// picked one's corners, handles and knob. A picked base picture has its
/// frame as its corners and no handles: the frame is resized as the element.
class StageLayers {
  final List<List<Offset>> others;
  final List<Offset>? picked;

  /// chosen are the layers picked with [picked], outlined without handles:
  /// they move with it.
  final List<List<Offset>> chosen;
  final List<Offset> handles;
  final Offset? knob;

  /// masking is the layer whose mask a mask tool is working on, and how the
  /// mask is to be shown; ring is the brush, centre and radius.
  final ({ImageElement element, String layer, MaskView view})? masking;
  final (Offset, double)? ring;

  /// trail is a quick-select stroke being drawn: points, radius, and whether
  /// it takes away.
  final (List<Offset>, double, bool)? trail;

  /// marker is where the clone tool copies from.
  final Offset? marker;

  /// lasso is the outline of a lasso being drawn, in document units.
  final List<Offset>? lasso;

  /// warp is a picture's warp grid being worked on, in document units: its
  /// lines, curved as the picture bends, its points and picks, and with two
  /// or more picked the box to size and turn them by.
  final StageWarp? warp;

  const StageLayers(
      {this.others = const [],
      this.picked,
      this.chosen = const [],
      this.handles = const [],
      this.knob,
      this.masking,
      this.ring,
      this.trail,
      this.marker,
      this.lasso,
      this.warp});
}
