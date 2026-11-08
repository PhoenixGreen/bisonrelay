import 'package:clock/clock.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/ui/orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_gizmo.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_nav_controls.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/vector_element.dart';
import 'package:bruig/plugin_system/canvas/model/vector_cut.dart';
import 'package:bruig/plugin_system/canvas/model/vector_text.dart';
import 'package:bruig/plugin_system/canvas/model/font_files.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart';
import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/ui/quick_fill.dart';
import 'package:bruig/plugin_system/canvas/ui/tablet_input.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/image_editing.dart';
import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/image_masking.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_items.dart';
import 'package:bruig/plugin_system/canvas/ui/vector_shapes.dart';
import 'package:bruig/plugin_system/canvas/model/vector_brush.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/procedural_cache.dart';
import 'package:bruig/plugin_system/canvas/render/audio_painter.dart';
import 'package:bruig/plugin_system/canvas/render/video_key.dart';
import 'package:bruig/plugin_system/canvas/render/video_painter.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/text_items.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/render/text_flow.dart';
import 'package:bruig/plugin_system/canvas/render/team_painter.dart';
import 'package:bruig/plugin_system/canvas/render/vector_paths.dart';
import 'package:bruig/plugin_system/canvas/render/vector_painter.dart'
    show vectorLinePath, vectorShapePath;
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/instances.dart'
    show CopyValue, InstanceSet;
import 'package:bruig/plugin_system/canvas/ui/motion_editing.dart'
    show MotionEditing;
import 'package:bruig/plugin_system/canvas/ui/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

// canvas_stage.dart is the canvas you can touch: the document drawn, with
// selection handles over it and every gesture that moves something.
//
// It draws through the same scene_renderer.dart the export uses, under one
// transform, so nothing here decides how an element looks. What it owns is
// which element is under the pointer, what dragging a handle means, and where
// the handles go. Next door: stage_painter.dart draws, given values this file
// has decided; stage_parts.dart answers drags that move a piece inside an
// element (a chart's title, a table's column rules); stage_geometry.dart is
// the sizes both halves agree on.
//
// Two coordinate spaces. Document space is where elements live and never
// changes with the view; stage space is pixels on screen. Everything the
// pointer says arrives in stage space and is converted once, at the top of
// each gesture handler. Handles are the exception: drawn and hit-tested in
// stage space, so they stay one size on screen at every zoom.

/// _DragMode is what the pointer is currently doing.
enum _DragMode {
  none,

  /// copies is copies of an element reused dragged on their own -- those
  /// picked, or made by an Alt-drag. See _moveCopies.
  copies,

  /// skew is a side handle dragged to slant the element. See _applySkew.
  skew,

  /// copySize and copyTurn are the box of the one copy picked (see _oneCopy)
  /// taken by a handle: a corner or side sizes that copy alone, the ring
  /// turns it -- its own Size and Turn. See _applyCopyBox.
  copySize,
  copyTurn,

  /// warpMove, warpScale and warpTurn carry a warp grid's picked points:
  /// dragged, sized about the middle of their box, or turned about it.
  /// warpMarquee is a box dragged out to pick the points in it.
  warpMove,
  warpScale,
  warpTurn,
  warpMarquee,

  /// anchor is an element's anchor point being dragged. See
  /// ElementBase.anchorX.
  anchor,
  move,
  resize,
  rotate,
  marquee,
  pan,
  player,
  node,
  handle,

  /// spritePaint is a Sprite element's frame being painted on -- see
  /// sprite_painting.dart.
  spritePaint,

  /// tilePaint is a Tile map being painted -- see tile_painting.dart.
  tilePaint,

  /// stageOrbit is a 3D stage's camera being swung round it, by a drag with
  /// Option held anywhere on the stage, or with none, the page locked.
  stageOrbit,

  /// stagePan is a 3D stage's camera being slid sideways and up, by a
  /// shifted or middle-button drag with the page locked.
  stagePan,

  /// gizmo is a part of the gizmo on an element standing on a stage being
  /// dragged: see stage_gizmo.dart.
  gizmo,

  /// parallaxPan is parallax scenery's camera being panned, by a drag with
  /// Option held on it: the scenery follows the pointer, as a map does.
  parallaxPan,

  /// chartLabel is a chart's title or description being moved or resized
  /// inside the chart: a part of an element rather than the element, as
  /// player is.
  chartLabel,

  /// tableColumn is the rule between two of a table's columns being dragged
  /// to make one wider and the other narrower.
  tableColumn,

  /// counterPart is one of a counter's freely placed pieces (a word, or one of
  /// its buttons) being moved inside the counter's own box.
  counterPart,

  /// imageFrame is a picture being moved about inside its own frame: neither
  /// the element nor its pixels move, only which part the frame shows. See
  /// ImageFraming.
  imageFrame,

  /// imageLayerMove, imageLayerSize and imageLayerTurn are a picture layer
  /// being moved, resized by one of its handles, or turned by its knob, in a
  /// picture whose layers are being edited. See image_layers.dart.
  imageLayerMove,
  imageLayerSize,
  imageLayerTurn,

  /// imageMask is a mark being made on a picture's mask: a brush stroke, a
  /// lasso being drawn round something, or a gradient being dragged out.
  imageMask,

  /// imageQuick is a quick-select stroke being drawn.
  imageQuick,

  /// imageBrush is a paint or retouching stroke being drawn.
  imageBrush,

  /// flow is a link being pulled out of a text box's overflow grip and
  /// dropped on another box, making a chain of boxes: it changes which box the
  /// words that do not fit run on into.
  flow,

  /// guide is one of the reader's own lines being moved, or a new one pulled
  /// out of a ruler. Not an element: it moves what the canvas is lined up
  /// against.
  guide,

  /// vectorPoint is a point of a drawing being edited, or one of its
  /// handles, being dragged. See vector_editing.dart.
  vectorPoint,

  /// vectorPoints is several picked points of a drawing dragged together,
  /// and vectorMarquee a box dragged across one to pick the points inside it.
  vectorPoints,
  vectorMarquee,

  /// vectorPen is the pen's point just put down, its handles being pulled
  /// out by the drag.
  vectorPen,

  /// vectorScale is picked points being scaled by the scale tool, and
  /// vectorTint the tint tool dragged across points, colouring each it meets.
  vectorScale,
  vectorTint,

  /// vectorCorner is a corner being rounded, the drag setting how far.
  vectorCorner,

  /// vectorPencil is a pencil stroke being drawn; vectorErase the pen's
  /// eraser going over lines.
  vectorPencil,

  /// vectorKnife is the knife's line being drawn through a drawing. See
  /// vector_cut.dart.
  vectorKnife,
  vectorErase,

  /// vectorRub is the eraser rubbing out what it goes over.
  vectorRub,

  /// vectorShapeDraw is a shape being dragged out with the shapes tool;
  /// vectorShapeFit the one picked being moved or resized by its box.
  vectorShapeDraw,
  vectorShapeFit,

  /// vectorItems is the shapes the select shapes tool has picked being
  /// moved, sized or turned by their box. See vector_items.dart.
  vectorItems,

  /// vectorItemsBox is a box being dragged across a drawing to pick the
  /// shapes it touches.
  vectorItemsBox,
}

class CanvasStage extends StatefulWidget {
  final CanvasController controller;

  /// onButtonLink is called when a button element whose action is a link is
  /// pressed in the editor: handed up, since leaving the app is not the
  /// canvas's decision.
  final void Function(String url)? onButtonLink;

  const CanvasStage({required this.controller, this.onButtonLink, super.key});

  @override
  State<CanvasStage> createState() => CanvasStageState();
}

/// CanvasStageState is public so the screen, holding a key to it, can ask
/// where in document coordinates a drop from the sidebar landed: only the
/// stage knows the transform.
class CanvasStageState extends State<CanvasStage>
    with SingleTickerProviderStateMixin {
  CanvasController get controller => widget.controller;
  CanvasDocument get document => controller.document;

  _DragMode _mode = _DragMode.none;

  /// _playerIndex is which player of the selected team is being dragged, in
  /// [_DragMode.player]. The team stays selected: a player is one row of its
  /// list, not an element, with no handles of its own.
  int _playerIndex = -1;

  /// _playerGrab is where in the dot the pointer took hold, so a player does
  /// not jump to centre itself under the cursor on the first pixel of a drag.
  Offset _playerGrab = Offset.zero;

  /// _pendingButton is a selected button that has been pressed but not yet
  /// released. It runs its action on release, and only if the pointer has not
  /// travelled far enough to have been a drag. See _onPointerDown.
  ButtonElement? _pendingButton;

  /// _pendingCounter is a live counter's own button that has been pressed and
  /// not yet released, and _pendingCounterAt which of them it is: as with a
  /// button element, a press that turns into a drag moves the counter instead.
  /// See _onPointerUp.
  CounterElement? _pendingCounter;
  int _pendingCounterAt = -1;

  /// _pendingAudio is a selected speaker pressed on one of its controls and
  /// not yet released, which control, and where (the volume bar needs to know
  /// how far along).
  AudioElement? _pendingAudio;

  /// _keyDown is an instrument's key held under the pointer.
  (AudioElement, int)? _keyDown;

  /// _pendingVideo is the same for a selected video's controls.
  VideoElement? _pendingVideo;
  VideoPart _pendingVideoPart = VideoPart.picture;
  Offset _pendingVideoAt = Offset.zero;
  AudioControl _pendingAudioPart = AudioControl.playPause;
  Offset _pendingAudioAt = Offset.zero;

  /// _pendingLegend is a chart whose key has been pressed, and
  /// _pendingLegendAt which series' entry: a press that turns into a drag
  /// moves the chart rather than switching a series off.
  ChartElement? _pendingLegend;
  int _pendingLegendAt = -1;

  /// _legendHold is the timer running while a key is held down, and
  /// _legendHoldDelay how long it has to be held. Held, a key becomes a thing
  /// to move: a press and a drag are already spoken for, and a key has no grip
  /// of its own.
  Timer? _legendHold;
  static const Duration _legendHoldDelay = Duration(milliseconds: 400);

  /// _settingCounter is the counter whose Set button is being typed into, and
  /// _settingAt which button that is.
  String? _settingCounter;
  int _settingAt = -1;

  /// _hoveredCounter is the counter whose button is under the pointer, and
  /// _hoveredCounterAt which one, so it can be drawn lit.
  String? _hoveredCounter;
  int _hoveredCounterAt = -1;

  /// _buttonClickSlop is how far the pointer may move and still count as a
  /// click rather than a drag. Most trackpad clicks move a pixel or two.
  static const double _buttonClickSlop = 4;

  /// _dragThreshold is how far a press has to travel before it is a drag, in
  /// screen pixels: a click arrives with a pixel or three of travel, and must
  /// not move what it selects. Everything that moves something waits for
  /// this, then measures from the press itself, so what is dragged stays
  /// where it was picked up.
  static const double _dragThreshold = 4;

  /// _travelled is whether the press in hand has passed that threshold.
  bool _travelled = false;

  /// _lastClickAt and _doubleClickWindow spot the second click of a pair,
  /// timed by hand: this stage handles raw pointers, and a double-tap
  /// recogniser would delay every single tap while it waited.
  DateTime _lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _doubleClickWindow = Duration(milliseconds: 400);

  /// _lastVectorClick is where the last press on a drawing being edited
  /// was, for the pen's double-click.
  Offset _lastVectorClick = Offset.infinite;

  /// _thicknessReach is how near, on screen, the line thickness tool's drag
  /// has to pass a point to take it in.
  static const double _thicknessReach = 24;

  /// _penPullMin is how far, on screen, the pen has to be dragged as a point
  /// goes down before it pulls a curve out of it.
  static const double _penPullMin = 8;

  /// _framing is the picture being repositioned inside its frame, if one is:
  /// the picture whose layers are open with the base picture picked and the
  /// move tool in hand. Opened by double-clicking a selected picture (as a
  /// text element opens for typing); a plain drag still moves the element.
  String? get _framing {
    var e = controller.editingImage;
    // With layers round it the base picture has a place of its own (see
    // ImageLayer.basePlace) and is moved and sized by that, so there is no
    // framing to show.
    if (e == null ||
        !e.hasImage ||
        e.layered ||
        controller.imageLayer != baseLayerId ||
        controller.imageTool != ImageTool.move) {
      return null;
    }
    return e.id;
  }

  /// _layersMoved are the other picked picture layers a move carries with
  /// the one held, as they were when it began.
  List<ImageLayer> _layersMoved = const [];

  /// _layerStart is the picture layer being dragged as it was when the drag
  /// started, and _layerHandle the handle held -- see boxHandles.
  ImageLayer? _layerStart;
  int _layerHandle = -1;

  /// _maskOn is the picture a mark is being made on, while one is.
  LayerPicture? _maskOn;

  /// _strokeAt turns a point on the canvas into one of the stroke being
  /// drawn (a fraction of the frame for paint, of the picture for
  /// retouching), while one is.
  Offset Function(Offset)? _strokeAt;

  /// _quickTrail is a quick-select stroke being drawn, in fractions of the
  /// picture, and _quickSubtract whether it takes away; the stroke is cut
  /// when it is let go.
  List<Offset> _quickTrail = const [];
  bool _quickSubtract = false;

  /// _guideIndex is which guide is being dragged, while one is.
  int _guideIndex = -1;

  /// _framingStart is the framing the drag started from, so the drag is
  /// applied to where the picture was taken hold of rather than accumulating
  /// rounding.
  ImageFraming _framingStart = const ImageFraming();

  /// _pressedAt is where the pointer went down, in stage coordinates.
  Offset _pressedAt = Offset.zero;

  /// _painting is the picture being retouched, while a brush stroke is under
  /// way. Held by id, since the element is replaced when the stroke lands.
  String? _painting;

  /// _liveImage and _liveCanvas are the stroke being drawn: the same points in
  /// the picture's coordinates, for storing, and in the canvas's, for showing.
  /// The stroke is written to the element only when the pointer comes up:
  /// each write changes the cache key and rebuilds the whole treated picture.
  final List<Offset> _liveImage = [];
  final List<Offset> _liveCanvas = [];

  /// _liveRadius is the brush's radius in canvas units, worked out once when
  /// the stroke starts so the preview does not have to ask again per point.
  double _liveRadius = 0;

  /// _preview is a picture of what the held stroke would do, and _previewOf the
  /// settings it was made for: rebuilt as they change, so the reader adjusts
  /// hardness or cling and watches the same stroke redraw.
  ui.Image? _preview;
  String? _previewOf;

  /// _previewDebounce waits for the settings to stop moving before running the
  /// brush again: each keystroke or pixel of a scrub would otherwise start a
  /// full pass over the picture and an image decode.
  Timer? _previewDebounce;

  /// _previewDelay covers the gap between keystrokes and is short enough to
  /// feel like a consequence of the change.
  static const Duration _previewDelay = Duration(milliseconds: 220);

  /// _editorRect is where the editor was opened, in document space, frozen as
  /// it opens: for text riding a line the box comes from where the letters
  /// are, which move on every keystroke.
  Rect? _editorRect;

  /// _editingCell is the table cell being typed into, or null: a record, since
  /// a cell has no identity and its table is whatever is selected.
  (String, int, int)? _editingCell;

  /// _editingText is the text element being typed into, or null: by id,
  /// because the element is replaced on every keystroke.
  String? _editingText;

  /// _editingItem is which of that element's extra pieces is being typed
  /// into, by its own id, or null for the element's own paragraph. A piece is
  /// typed where it is drawn, as all words on the canvas are. See TextItem.
  String? _editingItem;

  /// _nodeIndex is which point of the selected path is being dragged, and
  /// _nodeHandleOut which of its two handles when the drag is a handle. Like a
  /// player, a node is not an element: the path stays selected.
  int _nodeIndex = -1;

  bool _nodeHandleOut = false;

  StageHandle? _handle;

  /// _flowFrom is the text box a link is being dragged out of, and _flowAt
  /// where the pointer has got to. See TextFlowGrips.
  String? _flowFrom;
  Offset? _flowAt;

  /// _dragStart is where the gesture began, in document space, and
  /// _startBounds are the selected elements as they were then: kept, rather
  /// than applying each delta to the current state, so rounding does not
  /// accumulate.
  Offset _dragStart = Offset.zero;

  /// _orbiting is the stage whose camera an Option-drag is swinging round,
  /// with the camera as it was and where on the screen the drag began.
  String? _orbiting;
  StageCamera? _orbitFrom;
  ParallaxCamera? _panFrom;
  Offset _orbitAt = Offset.zero;
  Map<String, Rect> _startBounds = {};

  /// _startPosed is where each element was on screen when the gesture began.
  /// See _beginTransform.
  Map<String, Rect> _startPosed = {};

  /// _startVisual is the box the handles were on. See _beginTransform.
  Map<String, Rect> _startVisual = {};

  /// _startElements are the selected elements as they were when the drag
  /// began, for a resize that scales what is inside them.
  Map<String, CanvasElement> _startElements = {};
  Map<String, double> _startRotation = {};
  Offset _startPan = Offset.zero;
  Rect? _marquee;

  /// marqueeForTest is the box being dragged to pick with, if one is.
  @visibleForTesting
  Rect? get marqueeForTest => _marquee;

  /// _visible is the room on screen: what the stage was laid out into.
  Size _visible = Size.zero;

  /// _viewport is the box the canvas is drawn into: [_visible] while the page
  /// fits, and bigger (by as much as the page sticks out) once it is zoomed in
  /// past the window or fitted to a width taller than it; the difference is
  /// scrolled.
  ///
  /// Everything else in this file works in this box's coordinates, as do the
  /// pointer events (the Listener is inside the scroll views). The exceptions
  /// are [toDocumentPoint] and the getters for the tests, in widget
  /// coordinates.
  Size _viewport = Size.zero;

  /// _scroll and _scrollX scroll the page down and across, where it is
  /// bigger than the window.
  final ScrollController _scroll = ScrollController();
  final ScrollController _scrollX = ScrollController();

  /// _scrolled is how far the page is scrolled, down and across.
  Offset get _scrolled => Offset(_scrollX.hasClients ? _scrollX.offset : 0,
      _scroll.hasClients ? _scroll.offset : 0);

  /// _stageMargin is the gap kept around the canvas when it is showing whole,
  /// so the page reads as a sheet with room around it.
  static const double _stageMargin = 24;

  /// _overspillFraction is how much of the world outside the canvas is shown
  /// when CanvasController.showOverspill is on, as a fraction of the page:
  /// enough to hold something coming on or going off, while the page still
  /// dominates.
  static const double _overspillFraction = 0.12;

  final FocusNode _focus = FocusNode(debugLabel: "canvas stage");

  @override
  void initState() {
    super.initState();
    // The caret moved by the keys, not only by what is typed.
    _typing.addListener(() {
      if (mounted && !_filling && controller.vectorTyping >= 0) {
        setState(() {});
      }
    });
    // The pen's pressure and tilt, where the platform only passes them on
    // through the runner.
    TabletInput.instance.start();
    controller.addListener(_onChanged);
    controller.images.addListener(_onChanged);
    controller.keysHeld.addListener(_onChanged);
    // Scrolled by hand (a scroll bar, two fingers, the wheel), the view is
    // where it is scrolled to: see _followScroll.
    _scroll.addListener(_followScroll);
    _scrollX.addListener(_followScroll);
    // Counters that say they start running do (a clock); a stopwatch waits
    // to be started.
    controller.startCounters();
    // The green screen's shader, read once for the whole app. Until it has
    // landed a keyed video is drawn unkeyed, and this repaints when it does.
    VideoKey.ready.addListener(_onChanged);
    AdjustShader.ready.addListener(_onChanged);
    TextureShader.ready.addListener(_onChanged);
    SharpenShader.ready.addListener(_onChanged);
    unawaited(VideoKey.load());
    unawaited(AdjustShader.load());
    unawaited(TextureShader.load());
    unawaited(SharpenShader.load());
    unawaited(HealShader.load());
  }

  @override
  void didUpdateWidget(CanvasStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_onChanged);
      oldWidget.controller.images.removeListener(_onChanged);
      oldWidget.controller.keysHeld.removeListener(_onChanged);
      controller.addListener(_onChanged);
      controller.images.addListener(_onChanged);
      controller.keysHeld.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    if (_wheelRests?.isActive ?? false) controller.endInteraction();
    _wheelRests?.cancel();
    _betweenTicker?.dispose();
    _between.dispose();
    _typing.dispose();
    _typingFocus.dispose();
    _previewDebounce?.cancel();
    _legendHold?.cancel();
    if (_steerTimer?.isActive ?? false) {
      _steerTimer!.cancel();
      controller.endInteraction();
    }
    _backgrounds.dispose();
    _scroll.dispose();
    _scrollX.dispose();
    controller.removeListener(_onChanged);
    controller.keysHeld.removeListener(_onChanged);
    controller.images.removeListener(_onChanged);
    VideoKey.ready.removeListener(_onChanged);
    AdjustShader.ready.removeListener(_onChanged);
    TextureShader.ready.removeListener(_onChanged);
    SharpenShader.ready.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  /// _between is how far past its frame the playhead has got, kept by
  /// _betweenTicker on every screen refresh while a drift plays, so the
  /// stage redraws it smoothly rather than a whole frame at a time. See
  /// scene_renderer's betweenFrames.
  final ValueNotifier<double> _between = ValueNotifier(0);
  Ticker? _betweenTicker;

  /// _followPlayback starts the refresh-by-refresh redraw when a drift
  /// starts playing, and stops it when playing stops.
  void _followPlayback() {
    var want = controller.playing && controller.playsDrift;
    var ticker = _betweenTicker ??=
        createTicker((_) => _between.value = controller.betweenFrames);
    if (want && !ticker.isActive) {
      ticker.start();
    } else if (!want && ticker.isActive) {
      ticker.stop();
      _between.value = 0;
    }
  }

  void _onChanged() {
    // Reframing follows the selection by way of the controller, which closes
    // a picture's layers when it stops being the one thing selected.
    if (!mounted) return;
    _followPlayback();
    setState(() {});
  }

  // ------------------------------------------------------------------------
  // Coordinates
  // ------------------------------------------------------------------------

  /// _fitScale is the scale at which the whole canvas fills the area, with
  /// [_stageMargin] to spare. Worked out from the viewport on every build:
  /// it changes with the window and the sidebar, which the controller does
  /// not know of.
  double get _fitScale {
    var size = document.size.size;
    if (size.width <= 0 || size.height <= 0) return 1;
    // A spread is two pages across and one down, so only the width makes
    // room; halving the fitted scale would halve the height as well.
    var across = size.width * (_spreadShown ? 2 : 1);
    var byWidth = (_visible.width - _stageMargin * 2) / across;
    // Fit to width ignores the height: a 9:16 story fitted whole would be a
    // narrow strip down the middle of a wide window.
    var fit = controller.fit == CanvasFit.width
        ? byWidth
        : math.min(byWidth, (_visible.height - _stageMargin * 2) / size.height);
    // The overspill has to fit on screen too, so the page gives up the room
    // for it rather than the margin.
    if (controller.showOverspill) fit /= 1 + _overspillFraction * 2;
    return fit.isFinite && fit > 0 ? fit : 1;
  }

  /// _viewRect is everything that is drawn: the page, plus the overspill
  /// round it when that is showing. The stage clips to it and tests the
  /// pointer against it, so an element off the page is grabbable exactly
  /// when it can be seen.
  Rect get _viewRect {
    var page = _pageRect;
    // The neighbour's half of the spread, added on its own side. The edited
    // page keeps its frame and its origin, so nothing the pointer does has
    // to know of a second leaf.
    if (_spreadShown) {
      page = _facingOnLeft
          ? Rect.fromLTWH(page.left, page.top, page.width * 2, page.height)
          : Rect.fromLTWH(
              page.left - page.width, page.top, page.width * 2, page.height);
    }
    var shown = !controller.showOverspill
        ? page
        : Rect.fromCenter(
            center: page.center,
            width: page.width * (1 + _overspillFraction * 2),
            height: page.height * (1 + _overspillFraction * 2),
          );
    // A game's level, as far as it reaches: drawn, grabbable and scrolled
    // along while it is not being played.
    if (_level case var level?) {
      shown = shown.expandToInclude(
          Rect.fromPoints(_toStage(level.topLeft), _toStage(level.bottomRight)));
    }
    return shown;
  }

  /// _level is how far a game's scene reaches, in the document's units (a
  /// level wider or taller than the screen), so it can be scrolled along to be
  /// edited; null for one that fits on the page, for anything but a game, and
  /// while it is played, when the view is the game's.
  Rect? get _level {
    if (!document.game || controller.gaming || document.editingMaster) {
      return null;
    }
    // Asked several times a build: worked out once for each document,
    // frame and moment of what plays live.
    var key = (document, controller.frame, controller.liveMotion?.clock);
    if (_levelOf case (var k, var known)
        when identical(k.$1, key.$1) && k.$2 == key.$2 && k.$3 == key.$3) {
      return known;
    }
    var made = _levelNow();
    _levelOf = (key, made);
    return made;
  }

  ((CanvasDocument, int, double?), Rect?)? _levelOf;

  Rect? _levelNow() {
    var page = Offset.zero & document.size.size;
    var reach = page;
    var frame = controller.frame;
    for (var e in document.elements) {
      // Sounds are kept off the canvas, and a backdrop fills the page.
      if (e is AudioElement || e is BackgroundElement) continue;
      reach = reach.expandToInclude(e.movedBoundsAt(frame, document, live: controller.liveMotion));
    }
    return reach == page ? null : reach;
  }

  /// levelShown is whether a game's level reaching past the page is being
  /// shown round it, for the painter to mark the page out within it.
  bool get levelShown => _level != null;

  /// _contentSize is how much room the canvas and its margins need: the
  /// visible box whenever the canvas fits in it, wider or taller when zoomed
  /// in or fitted to the width, the excess scrolled.
  Size _contentSize(Size visible) {
    if (visible.width <= 0 || visible.height <= 0) return visible;
    var spill = controller.showOverspill ? 1 + _overspillFraction * 2 : 1.0;
    var page = document.size.size * _scale;
    var wide = page.width * spill * (_spreadShown ? 2 : 1) + _stageMargin * 2;
    var tall = page.height * spill + _stageMargin * 2;
    // A game's level, all of it in reach: the page stays in the middle, so
    // as much room each side as it reaches past the page on its far side.
    if (_level case var level?) {
      var doc = document.size.size;
      var across = math.max(-level.left, level.right - doc.width) * _scale;
      var down = math.max(-level.top, level.bottom - doc.height) * _scale;
      wide = math.max(wide, page.width + across * 2 + _stageMargin * 2);
      tall = math.max(tall, page.height + down * 2 + _stageMargin * 2);
    }
    // Zoomed, room to move it about in: as far as its edges reach the
    // window's, and half a window past them, so it can be lifted clear of
    // the timeline and mixer open over the stage. At the whole canvas it
    // stays in the middle.
    if ((controller.zoom - 1).abs() > 0.001) {
      wide = math.max(wide, visible.width * 2 - wide) + visible.width;
      tall = math.max(tall, visible.height * 2 - tall) + visible.height;
    }
    return Size(math.max(visible.width, wide), math.max(visible.height, tall));
  }

  /// _facingPage is the page drawn beside the one being worked on, or null
  /// where it stands alone: a set of scenes, facing pages switched off, a
  /// cover, the first leaf, or the master canvas (one page, which would
  /// otherwise look different depending on where it was opened from). See
  /// CanvasDocument.facingAt. The neighbour is only drawn: it cannot be
  /// selected, moved or typed into.
  int? get _facingPage =>
      document.editingMaster ? null : document.facingAt(document.at);

  /// _bookPreview is whether the document is being played as a book: facing
  /// pages, and the run rather than one canvas on the stage. Every leaf is
  /// then drawn in its own place in the spread, so the stage keeps one frame
  /// for the run and a transition between spreads has both to move.
  bool get _bookPreview => controller.previewAt != null && document.hasSpread;

  /// _spreadShown is whether room is given to the leaf beside this one, which
  /// is not whether it is drawn: fitted to the width there is no spread, but
  /// the neighbour is still drawn, since a picture across the gutter is part
  /// of this page.
  bool get _spreadShown =>
      (_facingPage != null || _bookPreview) &&
      controller.fit != CanvasFit.width;

  /// _facingOnLeft is whether the page being worked on is the left-hand leaf,
  /// so the neighbour is drawn to its right.
  bool get _facingOnLeft {
    if (_bookPreview) return document.spreadOf(document.at)?.$1 == document.at;
    if (document.editingMaster) return false;
    return document.facingIsLeft(document.at) ?? false;
  }

  /// _onFacingPage is whether a point on the stage is over the leaf drawn
  /// beside the one being edited: measured against the edited page's own
  /// frame, since the two share an edge.
  bool _onFacingPage(Offset stage) {
    if (!_spreadShown) return false;
    var page = _pageRect;
    if (stage.dy < page.top || stage.dy > page.bottom) return false;
    return _facingOnLeft ? stage.dx > page.right : stage.dx < page.left;
  }

  /// _pageRect is the page on screen: drawn at [_scale] and centred in the
  /// viewport, which grows past the window when the page does, the
  /// difference scrolled.
  Rect get _pageRect {
    var size = document.size.size * _scale;
    // The spread is what sits in the middle, the edited page taking its own
    // half, so the spread does not move across the window when the page
    // being worked on changes sides.
    var across = !_spreadShown
        ? 0.0
        : (_facingOnLeft ? -size.width / 2 : size.width / 2);
    return Rect.fromCenter(
      center: Offset(_viewport.width / 2 + across, _viewport.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  /// _scale is what one document unit measures on screen: the fitted size
  /// times the zoom. See CanvasController.zoom on why zoom is a multiple of
  /// the fit.
  double get _scale => _fitScale * controller.zoom;

  /// _tellControllerTheScale hands the fitted scale to the controller so the
  /// band can say what is on screen. After the frame: notifying during layout
  /// is "setState called during build" (see CanvasController.restoreFit).
  void _tellControllerTheScale() {
    var found = _fitScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.reportFitScale(found);
    });
  }

  /// _scaledSize is the document as drawn.
  Size get _scaledSize => document.size.size * _scale;

  /// _origin is where the document's top-left corner sits in stage space: the
  /// page's own.
  Offset get _origin => _pageRect.topLeft;

  /// _clampedPan is where the view is, as CanvasController.pan says it: how
  /// far the middle of the page is from the middle of the window, in screen
  /// pixels, as it is scrolled.
  Offset get _clampedPan {
    var page = _pageRect.center;
    var at = _scrolled + Offset(_visible.width / 2, _visible.height / 2);
    return page - at;
  }

  /// _scrollFor is how far to scroll, down and across, to put the view at
  /// [pan], within how far the page can be scrolled.
  Offset _scrollFor(Offset pan) {
    var page = _pageRect.center;
    var want = page - Offset(_visible.width / 2, _visible.height / 2) - pan;
    return Offset(
      want.dx
          .clamp(0.0, math.max(0.0, _viewport.width - _visible.width))
          .toDouble(),
      want.dy
          .clamp(0.0, math.max(0.0, _viewport.height - _visible.height))
          .toDouble(),
    );
  }

  /// _setPan moves the view to [pan], as near it as the page can be
  /// scrolled.
  void _setPan(Offset pan) {
    var to = _scrollFor(pan);
    _jumpTo(to);
    var page = _pageRect.center;
    var at = page - Offset(_visible.width / 2, _visible.height / 2) - to;
    controller.pan = Offset2(at.dx, at.dy);
  }

  /// _syncing is set while the scroll views are moved to match the view, so
  /// _followScroll does not take the move back as a scroll by hand.
  bool _syncing = false;

  void _jumpTo(Offset to) {
    _syncing = true;
    if (_scrollX.hasClients && (_scrollX.offset - to.dx).abs() > 0.5) {
      _scrollX.jumpTo(to.dx.clamp(0.0, _scrollX.position.maxScrollExtent));
    }
    if (_scroll.hasClients && (_scroll.offset - to.dy).abs() > 0.5) {
      _scroll.jumpTo(to.dy.clamp(0.0, _scroll.position.maxScrollExtent));
    }
    _syncing = false;
  }

  /// _followScroll keeps the view where the page has been scrolled to by
  /// hand, so the zoom buttons zoom about what is looked at.
  void _followScroll() {
    if (_syncing || !mounted) return;
    var pan = _clampedPan;
    controller.followPan(Offset2(pan.dx, pan.dy));
  }

  /// _syncScroll scrolls to where the view is, after the page is laid out
  /// at its size: zoomed by the buttons, by a pinch, or onto a character.
  void _syncScroll() {
    if (!mounted) return;
    _jumpTo(_scrollFor(Offset(controller.pan.dx, controller.pan.dy)));
  }

  Offset _toDocument(Offset stage) =>
      (stage - _origin) / (_scale == 0 ? 1 : _scale);

  Offset _toStage(Offset doc) => doc * _scale + _origin;

  /// toDocumentPoint converts a position in this widget's own coordinates to a
  /// point in the document, for a drop from the sidebar. The scroll offset is
  /// added on, since everything in here works in the scrolled content's
  /// coordinates.
  Offset toDocumentPoint(Offset local) => _toDocument(local + _scrolled);

  /// pageRect is the canvas's frame, in this widget's coordinates, for tests:
  /// the canvas is painted, not laid out, so there is no render box to
  /// measure.
  @visibleForTesting
  Rect get pageRect => _pageRect.shift(-_scrolled);

  /// contentRect is the document as drawn inside that frame.
  @visibleForTesting
  Rect get contentRect => (_origin & _scaledSize).shift(-_scrolled);

  /// spreadRect is the frame the page and the leaf beside it fill together,
  /// which sits in the middle of the window while facing pages show; the
  /// page's own frame where there is no leaf beside it.
  @visibleForTesting
  Rect get spreadRect => _viewRect.shift(-_scrolled);

  /// flowGrips is where a selected text box's overflow dots are and what they
  /// say, for the tests that drag one onto another box.
  @visibleForTesting
  TextFlowGrips? get textFlowGrips => _flowGrips();

  /// textFlowLines is the links being drawn, for the tests about when a chain
  /// is visible.
  @visibleForTesting
  List<FlowLine> get textFlowLines => _flowLines();

  /// gizmo is the gizmo on the selected element standing on a 3D stage, for
  /// the tests that take hold of its parts.
  @visibleForTesting
  StageGizmo? get gizmo => _gizmo();

  /// toStagePoint is where a point of the document is on screen, for the same
  /// tests.
  @visibleForTesting
  Offset toStagePoint(Offset doc) => _toStage(doc) - _scrolled;

  /// handleAt is where the selection's [handle] is on screen, for the tests
  /// that drag one: turned and slanted, it is not at the box's corner.
  @visibleForTesting
  Offset handleAt(StageHandle handle) {
    var bounds = _selectionBounds;
    return bounds == null ? Offset.zero : _handlePosition(handle, bounds);
  }

  /// _chosen is what is selected on the canvas. A sound on the timeline is
  /// selected from its channel and is not drawn, so it has no box.
  List<CanvasElement> get _chosen => [
        for (var e in controller.selectedElements)
          if (!isTimelineSound(e)) e,
      ];

  /// _selectionBounds is the axis-aligned box round everything selected, in
  /// document space. Rotation is ignored for several: handles cannot follow
  /// several rotations at once.
  Rect? get _selectionBounds {
    var elements = _chosen;
    if (elements.isEmpty) return null;
    // A team standing on a pitch has no box to show, move or size: the
    // pitch places it, and its players are what is picked up.
    if (elements.length == 1 &&
        elements.first is TeamElement &&
        (elements.first as TeamElement).linked) {
      return null;
    }
    // An element reused: each copy its own thing on the canvas, outlined
    // and picked alone -- the box round them all only with every one picked
    // in its Instances (Ken: the box was clutter, and in the way).
    // One copy picked: a box of its own, to size, turn and move it by
    // (Ken, 2026-11-08: "Individual instances should get a box").
    if (_oneCopy case (var e, var i)?) {
      return e.boundsWith(_copyPose(e, i));
    }
    if (elements.length == 1) {
      var e = elements.first;
      if (e.base.motion.instances case var set? when set.count > 1) {
        if (!controller.allCopiesChosen(e.id) &&
            controller.pickedCopiesOf(e.id).length < set.count) {
          return null;
        }
      }
    }
    // Where they are on this frame, not where they rest (see
    // CanvasElement.boundsAt), so the box moves with an animated element.
    var box = _visualBounds(elements.first);
    for (var e in elements.skip(1)) {
      box = box.expandToInclude(_visualBounds(e));
    }
    return box;
  }

  /// _oneCopy is the one copy picked of the one element selected, reused,
  /// as (the element, the copy's index): the one copy that has a box.
  (CanvasElement, int)? get _oneCopy {
    var elements = _chosen;
    if (elements.length != 1) return null;
    var e = elements.first;
    var set = e.base.motion.instances;
    if (set == null || set.count < 2) return null;
    var picked = controller.pickedCopiesOf(e.id);
    if (picked.length != 1) return null;
    var i = set.items.indexWhere((x) => x.id == picked.first);
    return i < 0 ? null : (e, i);
  }

  /// _copyPose is copy [i] of [e] as it is on this frame.
  Keyframe _copyPose(CanvasElement e, int i) =>
      poseWithMotion(e, controller.frame, controller.document,
          live: controller.liveMotion, instance: i);

  /// _boxIsNotTheShape marks the elements whose selection box is bigger than
  /// what the pointer can actually land on -- see _onPointerDown.
  bool _boxIsNotTheShape(CanvasElement e) =>
      e is LineElement ||
      e is PathElement ||
      (e is TextElement && e.curve != null);

  /// _visualBounds is where an element is drawn (see visualBoundsOf): a bowed
  /// line, a path and text riding a line are drawn outside their own
  /// rectangle.
  Rect _visualBounds(CanvasElement e) =>
      visualBoundsOf(e, document, controller.frame,
          live: controller.liveMotion);

  /// _selectionHasOwnGeometry is whether the handles and the rotate ring are
  /// worth showing. See hasOwnGeometry.
  bool get _selectionHasOwnGeometry {
    var elements = _chosen;
    if (elements.isEmpty) return false;
    return elements.every((e) => hasOwnGeometry(e, document, controller.frame));
  }

  /// _rotationOfSelection is the single selected element's rotation, or zero
  /// when several are chosen.
  double get _rotationOfSelection {
    if (_oneCopy case (var e, var i)?) {
      return (e.rotation + _copyPose(e, i).rotate) * math.pi / 180;
    }
    return _chosen.length == 1
        ? _chosen.first.movedRotationAt(controller.frame, controller.document,
                live: controller.liveMotion) *
            math.pi /
            180
        : 0;
  }

  /// _skewOfSelection is the single selected element's slant, in degrees,
  /// across and down, or nothing when several are chosen.
  Offset get _skewOfSelection => _chosen.length == 1
      ? Offset(_chosen.first.base.skewX, _chosen.first.base.skewY)
      : Offset.zero;

  /// _frameOfSelection is how the selection's box is laid on the page:
  /// turned and slanted, for one element; upright for several.
  BoxFrame get _frameOfSelection => BoxFrame(
      _rotationOfSelection * 180 / math.pi,
      _skewOfSelection.dx,
      _skewOfSelection.dy);

  // ------------------------------------------------------------------------
  // Hit testing
  // ------------------------------------------------------------------------

  /// _hitElement is the topmost element under a document-space point, walked
  /// from the front backwards.
  CanvasElement? _hitElement(Offset point) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var e = document.elements[i];
      if (!e.visible || e.locked) continue;
      if (_containsPoint(e, point)) return e;
    }
    return null;
  }

  /// _strokeReach is how far from a line the pointer may be and still be on
  /// it, in document units: half the stroke plus a few pixels of slack.
  double _strokeReach(double strokeWidth) =>
      math.max(strokeWidth / 2, 0) + strokeHitSlop / _scale;

  /// _nearPolyline is whether [point] is within [reach] of the polyline.
  bool _nearPolyline(List<Offset> points, Offset point, double reach) {
    for (var i = 1; i < points.length; i++) {
      var a = points[i - 1], b = points[i];
      var ab = b - a;
      var lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
      var t = lengthSquared == 0
          ? 0.0
          : (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      var closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
      if ((point - closest).distance <= reach) return true;
    }
    return false;
  }

  /// _containsPoint asks whether a point is inside an element, undoing its
  /// turn and slant first so it is hit where it is drawn.
  bool _containsPoint(CanvasElement e, Offset point) {
    // A camera by its frame's edge: inside it is what it shows, to be
    // picked as if it were not there.
    if (e is CameraElement) {
      var frame = e.movedBoundsAt(controller.frame, controller.document,
          live: controller.liveMotion);
      var reach = _strokeReach(2) + 4 / _scale;
      return frame.inflate(reach).contains(point) &&
          !frame.deflate(reach).contains(point);
    }
    // A team on a pitch is wherever the pitch puts its players, not in its
    // own box.
    if (e is TeamElement && e.linked) return _hitPlayer(e, point) != null;
    // Something on a stage is wherever the camera puts it: inside the four
    // corners it is seen at.
    if (e.base.spot != null) {
      if (stagedIn(document, e, controller.frame) case var at?) {
        return (Path()..addPolygon(at.quad, true)).contains(point);
      }
    }
    // A curve is caught by its stroke, not by its box: a bowed line or a
    // path bulges outside its box, and text riding a line has its words
    // wherever the line is.
    if (e is LineElement || e is PathElement) {
      var curve = curveOfElement(
          e is LineElement ? lineWithPose(e, controller.frame) : e);
      if (curve != null && curve.length >= 2) {
        var width =
            e is LineElement ? e.strokeWidth : (e as PathElement).strokeWidth;
        return _nearPolyline(curve, point, _strokeReach(width));
      }
    }
    if (e is TextElement) {
      var curve = curveUnderText(e, document, controller.frame);
      if (curve != null && curve.length >= 2) {
        // Generous: what is aimed at is a row of letters on the line.
        return _nearPolyline(
            curve, point, _strokeReach(e.textSpec.fontSize * 1.2));
      }
    }

    // Against where it is on this frame, as the selection box is.
    var box = e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    // Back into its own upright box: turned and slanted, it is hit where it
    // is drawn. See BoxFrame.
    var shape = e.movedFrameAt(controller.frame, controller.document,
        live: controller.liveMotion);
    var local = point;
    if (!shape.upright) local = box.center + shape.invert(point - box.center);
    if (!box.contains(local)) return false;

    // A circle is hit inside the circle, not in its box's corners.
    if (e is ShapeElement && e.shape == ShapeKind.circle) {
      var r = box.shortestSide / 2;
      return (local - box.center).distance <= r;
    }
    return true;
  }

  /// _onSelectionGrip is whether a press at [stage] ([doc] in document space)
  /// would take hold of something on the selection: a resize or rotate
  /// handle, a flow grip, or a selected path's points and handles.
  bool _onSelectionGrip(Offset stage, Offset doc) {
    if (controller.selection.isEmpty) return false;
    if (_hitHandle(stage) != null || _hitFlowGrip(stage) != null) return true;
    var path = _selectedPath();
    return path != null && _hitPathControl(path, doc) != null;
  }

  /// _hitHandle is which grip is under a stage-space point, if any.
  StageHandle? _hitHandle(Offset stage) => _nearestHandle(stage)?.$1;

  /// _nearestHandle is the closest grip within reach, and how far away it is.
  /// The closest rather than the first found: on anything small two handles'
  /// targets overlap. The distance comes back because the flow grips sit on
  /// the same outline and have to know whether they are the nearer thing.
  (StageHandle, double)? _nearestHandle(Offset stage) {
    // Nothing to grab on something whose size and angle are a line's.
    if (!_selectionHasOwnGeometry) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;
    var reach = handleSize / 2 + handleHitSlop;

    // Hidden helpers are unreachable helpers: see
    // CanvasController.showHelpers.
    if (!controller.showHelpers) return null;

    // The middle of an element is not a handle. On a short element (a text
    // box one line high) the top and bottom grips' targets would meet in the
    // middle, and every press on the words would resize instead of move.
    if (_insideCore(stage, bounds, reach)) return null;

    StageHandle? best;
    var away = double.infinity;
    for (var handle in StageHandle.values) {
      var at = _handlePosition(handle, bounds);
      // Clipped out of sight means clipped out of reach.
      if (!_viewRect.inflate(reach).contains(at)) continue;
      var d = (stage - at).distance;
      if (d <= reach && d < away) {
        best = handle;
        away = d;
      }
    }
    return best == null ? null : (best, away);
  }

  /// _insideCore is whether a stage point is far enough inside [bounds] that
  /// nothing on the outline can have meant it. Each direction gives up at most
  /// a third of the element to its grips, so there is always a middle left to
  /// press.
  bool _insideCore(Offset stage, Rect bounds, double reach) {
    var on = Offset(bounds.width, bounds.height) * _scale;
    if (on.dx <= 0 || on.dy <= 0) return false;
    var keepX = math.min(reach, on.dx / 3);
    var keepY = math.min(reach, on.dy / 3);

    // In the selection's own frame, so a rotated box keeps its middle too.
    var d = stage - _toStage(bounds.center);
    var local = _frameOfSelection.invert(d);
    return local.dx.abs() < on.dx / 2 - keepX &&
        local.dy.abs() < on.dy / 2 - keepY;
  }

  /// _selectedText is the one text element selected on its own, the only
  /// time the flow grips are shown.
  TextElement? _selectedText() {
    if (controller.selection.length != 1) return null;
    var element = document.elementById(controller.selection.first);
    return element is TextElement ? element : null;
  }

  /// _flowGrips is where a selected text box's two dots go, and what they
  /// have to say. Null when there is nothing to say it about.
  TextFlowGrips? _flowGrips() {
    if (!controller.showHelpers) return null;
    var e = _selectedText();
    if (e == null || e.curve != null) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;

    var inner = e.box.inner(e.bounds);
    var flow = flowFor(e, document, inner, drawnTextSpec(e, e.bounds),
        frame: controller.frame, images: controller.images);

    return TextFlowGrips(
      inAt: _gripPosition(bounds, top: true),
      outAt: _gripPosition(bounds, top: false),
      overflowing: flow.overflows,
      receiving: flow.receiving,
      linked: e.flowTo.isNotEmpty && document.elementById(e.flowTo) != null,
    );
  }

  /// _flowDragLine is the link being dragged, from the box the words leave to
  /// wherever the pointer is.
  FlowLine? _flowDragLine() {
    if (_mode != _DragMode.flow) return null;
    var at = _flowAt;
    var from = _flowFrom == null ? null : document.elementById(_flowFrom!);
    if (at == null || from == null) return null;
    return FlowLine(
        _toStage(_flowPointOf(from.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), top: false)),
        at);
  }

  /// _flowLines is every link between two text boxes worth drawing: either
  /// box selected, or every box being shown at once (see
  /// CanvasController.showAllBounds).
  List<FlowLine> _flowLines() {
    // Hidden joins leave the grips, which say there is a chain and whether
    // the words fit; it is the lines that cross the design.
    if (!controller.showHelpers || controller.hideJoins) return const [];
    var out = <FlowLine>[];

    for (var e in document.elements) {
      if (e is! TextElement || e.flowTo.isEmpty) continue;
      var into = document.elementById(e.flowTo);
      if (into == null || !e.visible || !into.visible) continue;

      // Not the one in hand: it is being drawn from the pointer instead.
      if (_mode == _DragMode.flow && e.id == _flowFrom) continue;

      var shown = controller.showAllBounds ||
          controller.selection.contains(e.id) ||
          controller.selection.contains(into.id);
      if (!shown) continue;

      var inner = e.box.inner(e.bounds);
      var flow = flowFor(e, document, inner, drawnTextSpec(e, e.bounds),
          frame: controller.frame);
      out.add(FlowLine(
        _toStage(_flowPointOf(e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), top: false)),
        _toStage(_flowPointOf(into.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), top: true)),
        overflowing: flow.overflows,
      ));
    }
    return out;
  }

  /// _flowPointOf is where a box's flow grip sits, in document space.
  Offset _flowPointOf(Rect bounds, {required bool top}) => top
      ? Offset(bounds.left, bounds.top + bounds.height / 4)
      : Offset(bounds.right, bounds.bottom - bounds.height / 4);

  /// _gripPosition puts a flow grip half way between two resize handles: the
  /// incoming dot between the top-left and the middle-left, the outgoing one
  /// between the middle-right and the bottom-right, so they do not crowd a
  /// corner.
  Offset _gripPosition(Rect bounds, {required bool top}) {
    var centre = _toStage(bounds.center);
    var half = Offset(bounds.width, bounds.height) * _scale / 2;
    var local =
        top ? Offset(-half.dx, -half.dy / 2) : Offset(half.dx, half.dy / 2);
    return centre + _frameOfSelection.apply(local);
  }

  /// _textPieceOwner is the text element with a piece under the pointer,
  /// where its own box is not. Any text element, not only the selected one: a
  /// piece pushed outside its box may be the only thing of it near the
  /// pointer, and must take a first click. Front to back, like the ordinary
  /// hit test.
  TextElement? _textPieceOwner(Offset doc) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var element = document.elements[i];
      if (element is! TextElement || element.locked || !element.visible) {
        continue;
      }
      if (_textItemAt(element, doc) != null) return element;
    }
    return null;
  }

  /// _looseTextPiece is a text element with a piece under the pointer that is
  /// drawn outside the element's own box. It beats the resize handles: a
  /// piece pushed out sits against the outline the handles answer near.
  /// Inside the box the outline means resizing (see _insideCore).
  TextElement? _looseTextPiece(Offset doc) {
    var owner = _textPieceOwner(doc);
    if (owner == null) return null;
    return owner.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion).contains(doc) ? null : owner;
  }

  /// _textItemAt is which of a text element's extra pieces a document point
  /// is on, or null for none: off the function that draws them (see
  /// textItemRects), so what is clicked is what is seen.
  TextItem? _textItemAt(TextElement e, Offset doc) {
    if (e.items.isEmpty) return null;
    var bounds = e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    var rects = textItemRects(e, bounds);
    // Backwards: the last one drawn is on top.
    for (var i = e.items.length - 1; i >= 0; i--) {
      // Hidden or locked in the Layers, it is not there to be pressed.
      if (e.items[i].hidden || e.items[i].locked) continue;
      if (!rects[i].isEmpty && rects[i].inflate(2).contains(doc)) {
        return e.items[i];
      }
    }
    return null;
  }

  /// _topmostOf is whichever of the two is drawn in front (later in the
  /// document's list), or either one where the other is null.
  CanvasElement? _topmostOf(CanvasElement? box, CanvasElement? piece) {
    if (box == null || piece == null) return box ?? piece;
    if (box.id == piece.id) return box;
    var elements = document.elements;
    return elements.indexWhere((e) => e.id == piece.id) >
            elements.indexWhere((e) => e.id == box.id)
        ? piece
        : box;
  }

  /// _hitFlowGrip is which flow grip is under the pointer, if either. The
  /// outgoing grip starts or moves a link; the incoming one picks up the link
  /// that arrives, to disconnect it.
  ///
  /// [beat] is how close the nearest resize handle is: a grip only answers
  /// when it is nearer. On a short box they sit almost on top of each other,
  /// and ties go to the handle.
  ({bool out})? _hitFlowGrip(Offset stage, {double beat = double.infinity}) {
    var grips = _flowGrips();
    if (grips == null) return null;
    var reach = flowGripSize / 2 + flowGripHitSlop;
    // On the same outline as the resize grips, so it keeps off the middle
    // too: see _insideCore.
    var bounds = _selectionBounds;
    if (bounds != null && _insideCore(stage, bounds, reach)) return null;
    var out = (stage - grips.outAt).distance;
    var into = (stage - grips.inAt).distance;
    if (out <= reach && out < beat && (!grips.receiving || out <= into)) {
      return (out: true);
    }
    if (grips.receiving && into <= reach && into < beat) return (out: false);
    return null;
  }

  /// _counterPart is which freely placed piece of a counter is being dragged:
  /// its id, and which piece (-2 the words in front, -3 the words after, 0
  /// upwards a button).
  String? _counterPart;
  int _counterPartAt = 0;

  /// _counterPartUnder is the freely placed piece a document point is on, if
  /// any. Only pieces let loose: a word on the number's line is part of it.
  int? _counterPartUnder(CounterElement e, Offset doc) {
    if (e.looseButtons) {
      var at = _counterButtonAt(e, doc);
      if (at >= 0) return at;
    }
    if (!e.loose) return null;
    var inner = e.box.inner(e.bounds);
    for (var (which, text, at) in [
      (-2, e.before, e.beforeAt),
      (-3, e.after, e.afterAt),
    ]) {
      if (text.isEmpty) continue;
      var centre = Offset(inner.center.dx + inner.width * at.dx,
          inner.center.dy + inner.height * at.dy);
      // A target the height of the words and a few ems wide, about what is
      // drawn.
      var box = Rect.fromCenter(
          center: centre,
          width: math.max(
              e.affixSpec.fontSize * text.length * 0.7, e.affixSpec.fontSize),
          height: e.affixSpec.fontSize * 1.4);
      if (box.contains(doc)) return which;
    }
    return null;
  }

  /// _applyCounterPart moves that piece to wherever the pointer is.
  void _applyCounterPart(Offset doc) {
    var id = _counterPart;
    var element = id == null ? null : document.elementById(id);
    if (element is! CounterElement) return;

    var inner = element.box.inner(element.bounds);
    if (inner.width <= 0 || inner.height <= 0) return;
    // Back to a fraction of the box from its middle, as a placement is
    // held, so the piece stays put when the counter is resized.
    var at = Offset(
      ((doc.dx - inner.center.dx) / inner.width).clamp(-1.0, 1.0),
      ((doc.dy - inner.center.dy) / inner.height).clamp(-1.0, 1.0),
    );

    controller.replaceElement(
        switch (_counterPartAt) {
          -2 => element.copyWith(beforeAt: at),
          -3 => element.copyWith(afterAt: at),
          _ => element.copyWith(buttonAt: [
              for (var i = 0; i < element.buttons.length; i++)
                i == _counterPartAt ? at : element.placedButton(i),
            ]),
        },
        transient: true);
  }

  /// _legendSeriesAt is which series' key entry a document point is on, or -1
  /// for none: off the painter, so the target is exactly what was drawn.
  int _legendSeriesAt(ChartElement e, Offset doc) {
    for (var (series, box) in chartLegendRects(e, e.bounds)) {
      if (box.contains(doc)) return series;
    }
    return -1;
  }

  /// _toggleSeries switches one of a chart's series off, or back on.
  void _toggleSeries(ChartElement e, int at) {
    var current = document.elementById(e.id);
    if (current is! ChartElement) return;
    if (at < 0 || at >= current.data.series.length) return;
    var series = [...current.data.series];
    series[at] = series[at].copyWith(hidden: !series[at].hidden);
    controller.beginInteraction();
    controller.replaceElement(
        current.copyWith(data: current.data.copyWith(series: series)));
    controller.endInteraction();
  }

  /// _holdLegend takes hold of a chart's key, so a held press moves the key
  /// rather than pressing one of its switches. The key keeps the place it is
  /// drawn in, and from then on is a placed label like the title, put back by
  /// the button in the Legend settings.
  void _holdLegend(ChartElement e) {
    _legendHold = null;
    var current = document.elementById(e.id);
    if (current is! ChartElement || current.locked) return;
    var bounds = current.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    if (bounds.width <= 0 || bounds.height <= 0) return;
    var block = chartLegendBlock(current, bounds);
    if (block.isEmpty) return;

    // What was pressed is not a switch any more.
    _pendingLegend = null;
    _pendingLegendAt = -1;

    if (!current.legend.hasPlace) {
      controller.replaceElement(
          current.copyWith(
            legend: current.legend.copyWith(
              x: (block.left - bounds.left) / bounds.width,
              y: (block.top - bounds.top) / bounds.height,
            ),
          ),
          transient: true);
    }
    _labelGrab = ChartLabelGrab(
        ChartLabelPart.legend, false, _toDocument(_pressedAt) - block.topLeft);
    setState(() => _mode = _DragMode.chartLabel);
  }

  /// _audioPartAt is which of a speaker's controls a document point is on, or
  /// null for none: the rectangles the painter drew (see audioParts).
  AudioControl? _audioPartAt(AudioElement e, Offset doc) {
    var parts = audioParts(e, e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    if (parts.volume case var v? when v.contains(doc)) {
      return AudioControl.volume;
    }
    if (parts.mute case var m? when m.contains(doc)) return AudioControl.mute;
    if (e.has(AudioControl.playPause) && parts.icon.contains(doc)) {
      return AudioControl.playPause;
    }
    return null;
  }

  /// _masterAudioAt is a speaker on the master under a document point, and
  /// which of its controls, while a page is the canvas in front of the reader.
  (AudioElement, AudioControl)? _masterAudioAt(Offset doc) {
    if (document.editingMaster) return null;
    var master = document.masterScene;
    if (master == null) return null;
    for (var e in master.elements.reversed) {
      if (e is! AudioElement || !e.visible) continue;
      var part = _audioPartAt(e, doc);
      if (part != null) return (e, part);
    }
    return null;
  }

  /// _videoPartAt is which part of a video a document point is on, from the
  /// rectangles the painter drew. A link answers anywhere on it.
  VideoPart? _videoPartAt(VideoElement e, Offset doc) =>
      videoPartAt(videoParts(e, e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion)), doc,
          clickable:
              e.isLink || (e.has(VideoControl.clickToggle) && !e.clip.timed));

  /// _masterVideoAt is a video on the master under a document point, while a
  /// page is in front of the reader. See _masterAudioAt.
  (VideoElement, VideoPart)? _masterVideoAt(Offset doc) {
    if (document.editingMaster) return null;
    var master = document.masterScene;
    if (master == null) return null;
    for (var e in master.elements.reversed) {
      if (e is! VideoElement || !e.visible) continue;
      var part = _videoPartAt(e, doc);
      if (part != null) return (e, part);
    }
    return null;
  }

  void _pressVideo(VideoElement e, VideoPart part, Offset doc) {
    var parts = videoParts(e, e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    var along = switch (part) {
      VideoPart.track => alongBar(parts.track!, doc.dx),
      VideoPart.volume => alongBar(parts.volume!, doc.dx),
      _ => 0.0,
    };
    var url = controller.pressVideo(e, part, along: along);
    // Leaving the app is asked about by whoever put the stage up, as for a
    // button's link.
    if (url != null && url.isNotEmpty) widget.onButtonLink?.call(url);
  }

  void _pressAudio(AudioElement e, AudioControl part, Offset doc) {
    double? volume;
    if (part == AudioControl.volume) {
      var bar = audioParts(e, e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion)).volume;
      if (bar != null) volume = volumeAt(bar, doc.dx);
    }
    controller.pressAudio(e, part, volume: volume);
  }

  /// _counterButtonAt is which of a counter's buttons a document point is in,
  /// or -1 for none.
  int _counterButtonAt(CounterElement e, Offset doc) {
    var rects = counterButtonRects(e, e.bounds);
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(doc)) return i;
    }
    return -1;
  }

  /// _pressCounter runs one of a counter's buttons. Set is handled here: the
  /// controller has no window, and the answer is typed on the button rather
  /// than in a dialog over the canvas.
  void _pressCounter(CounterElement e, int at) {
    if (at < 0 || at >= e.buttons.length) return;
    var button = e.buttons[at];
    if (controller.pressCounterButton(e, button)) return;
    setState(() {
      _settingCounter = e.id;
      _settingAt = at;
    });
  }

  /// _counterInputFor is the field that opens on a counter's Set button, at
  /// the button's size. Enter takes it; anything else that closes it leaves
  /// the counter alone.
  Widget? _counterInputFor() {
    var id = _settingCounter;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! CounterElement) return null;
    var rects = counterButtonRects(element, element.bounds);
    if (_settingAt < 0 || _settingAt >= rects.length) return null;

    var box = rects[_settingAt];
    var topLeft = _toStage(box.topLeft);
    void close() {
      if (mounted) {
        setState(() {
          _settingCounter = null;
          _settingAt = -1;
        });
      }
    }

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: box.width * _scale,
      height: box.height * _scale,
      child: CounterInput(
        key: ValueKey("set-$id"),
        value: controller.counterValue(element),
        decimals: element.decimals,
        onDone: (typed) {
          if (typed != null) controller.setCounterValue(element, typed);
          close();
        },
      ),
    );
  }

  /// _dropFlow finishes a link drag: onto another text box it points the
  /// words there; anywhere else it takes the link away, so a chain is taken
  /// apart by the gesture that made it.
  void _dropFlow(Offset stage) {
    var from = _flowFrom == null
        ? null
        : document.elementById(_flowFrom!) as TextElement?;
    if (from == null || controller.lockJoins) return;

    var doc = _toDocument(stage);
    TextElement? onto;
    for (var element in document.elements.reversed) {
      if (element is! TextElement || element.id == from.id) continue;
      if (element.locked || !element.visible) continue;
      if (_containsPoint(element, doc)) {
        onto = element;
        break;
      }
    }

    if (onto != null && wouldLoop(from, onto.id, document)) {
      // A ring of boxes has no first box to start reading from: refused, and
      // the link that was there is left alone.
      return;
    }

    controller.beginInteraction();
    controller.replaceElement(from.copyWith(flowTo: onto?.id ?? ""));
    controller.endInteraction();
  }

  /// _handlePosition is where a grip is drawn, in stage space.
  Offset _handlePosition(StageHandle handle, Rect bounds) {
    var centre = _toStage(bounds.center);
    var half = Offset(bounds.width, bounds.height) * _scale / 2;

    var local = switch (handle) {
      StageHandle.topLeft => Offset(-half.dx, -half.dy),
      StageHandle.topCenter => Offset(0, -half.dy),
      StageHandle.topRight => Offset(half.dx, -half.dy),
      StageHandle.centerLeft => Offset(-half.dx, 0),
      StageHandle.centerRight => Offset(half.dx, 0),
      StageHandle.bottomLeft => Offset(-half.dx, half.dy),
      StageHandle.bottomCenter => Offset(0, half.dy),
      StageHandle.bottomRight => Offset(half.dx, half.dy),
      StageHandle.rotate => Offset(0, -half.dy - rotateHandleGap),
    };
    // Where the box is drawn: turned and slanted. See BoxFrame.
    return centre + _frameOfSelection.apply(local);
  }

  // ------------------------------------------------------------------------
  // Gestures
  // ------------------------------------------------------------------------

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  /// _pressedCopy is the copy of [_pressedCopyOf] a press landed on, picked
  /// where the press is a click rather than a drag (Ken, 2026-11-08: copies
  /// are objects on the canvas).
  String? _pressedCopy, _pressedCopyOf;

  /// _copiesStart and _dragCopies are an element's copies as a drag of
  /// some of them began, and which are dragged.
  InstanceSet? _copiesStart;
  Set<String> _dragCopies = const {};

  void _onPointerDown(PointerDownEvent event) {
    _pointer = event;
    // Not while typing: an editor is a real text field over the canvas, with
    // its own pointers, and clicking off it moves the focus, which closes it
    // (see CanvasTextEditor._onFocus). A cell editor counts: the stage
    // taking the focus would close it before its own picture button's tap
    // finished.
    if (_editingText != null || _editingCell != null) return;
    _focus.requestFocus();
    // Looking through the camera, the page is drawn moved and a press would
    // land somewhere other than it looks: the press puts the page back, and
    // does nothing else. See CanvasController.cameraView.
    if (controller.cameraView) {
      controller.cameraView = false;
      return;
    }
    var stage = event.localPosition;
    _pressedAt = stage;
    _travelled = false;
    var doc = _toDocument(stage);
    _dragStart = doc;
    _pressedCopy = null;
    // Placing copies: each click puts one there (Escape stops).
    if (controller.placingCopies case var placing?
        when event.buttons == kPrimaryMouseButton) {
      controller.beginInteraction();
      controller.placeCopyAt(placing, doc);
      controller.endInteraction();
      _mode = _DragMode.none;
      return;
    }

    // A press on the facing page opens it. Before the pan check (panning is
    // a drag) and the hit test (an element of the edited page hanging over
    // the spine would take it). Except on a grip of what is selected: a
    // picture across the spread has handles on the other leaf.
    if (_facingPage case var beside?
        when _onFacingPage(stage) && !_onSelectionGrip(stage, doc)) {
      controller.goToScene(beside);
      _mode = _DragMode.none;
      return;
    }

    // The eyedropper: the colour under the press, and nothing else.
    if (controller.sampling) {
      _mode = _DragMode.none;
      _sampleAt(doc);
      return;
    }

    // The pen's buttons and its other end, with the pencil out, do what
    // they are set to, before the middle button's pan.
    if (_stylusPress(event, doc)) return;

    // The gizmo on an element standing on a 3D stage, before anything under
    // it: it is drawn on top.
    if (_pressGizmo(doc)) return;

    // The page locked on a stage: a press on the stage itself takes hold
    // of its camera rather than moving the page or sweeping a selection.
    if (_pressLockedStage(event, doc)) return;

    // The pan tool and the middle button pan (Space plays and stops). Not
    // while the page is locked; and the pan tool not on a 3D stage, where
    // the bar has the 3D tools instead.
    if (!controller.pageLocked &&
        ((controller.tool == CanvasTool.pan && !controller.onStage3d) ||
            event.buttons == kMiddleMouseButton)) {
      _mode = _DragMode.pan;
      _startPan = _clampedPan;
      _dragStart = stage;
      return;
    }

    // While a picture's layers are open, a press on it works on them; a
    // press anywhere else finishes the editing, as clicking off a text
    // editor closes it.
    if (controller.editingImage case var picture?) {
      if (_pressLayers(picture, doc)) return;
      controller.editImage(null);
    }

    // A guide, before anything on the canvas: it is a hairline drawn over
    // the design, so the reach is tight (see guideGrabSlop), but within it
    // the guide wins.
    if (_startGuideDrag(stage, doc)) return;

    // An anchor point shown and not locked, before the element it sits on:
    // it is the small thing drawn on top.
    if (_anchorUnder(stage) case var id?) {
      _anchorOf = id;
      _mode = _DragMode.anchor;
      controller.beginInteraction();
      return;
    }

    // A sprite being painted takes a press on it before anything else: a
    // brush on its pixels.
    if (controller.spritePaint case var session?) {
      if (session.sprite case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.spritePaint;
        unawaited(session.strokeStart(doc));
        return;
      }
    }
    // So does a map being painted: a brush on its cells.
    if (controller.tilePaint case var session?) {
      if (session.map case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.tilePaint;
        session.strokeStart(doc);
        return;
      }
    }

    // A drawing being edited takes the press first: its points and handles,
    // its shapes, and anywhere inside it. A press outside it finishes the
    // editing and goes on to do what it would have done.
    if (controller.editingVector case var vector?
        when _pressVector(vector, doc)) {
      return;
    }

    // Option held on a 3D stage takes hold of its camera: across goes round
    // the stage, down looks from higher. On a Background element showing
    // one, or, where the press hits nothing else, the background's own.
    if (HardwareKeyboard.instance.isAltPressed) {
      var hit = _hitElement(doc);
      var held = switch (hit) {
        StageElement s => s,
        BackgroundElement b when b.isStage => b.staged,
        null => controller.stageOf(backgroundStageId),
        _ => null,
      };
      // Parallax scenery is panned the same way.
      var scenery = switch (hit) {
        BackgroundElement b when b.isParallax => b.parallaxed,
        null => controller.parallaxOf(backgroundParallaxId),
        _ => null,
      };
      if (scenery case var p? when !p.locked) {
        _orbiting = p.id;
        _panFrom = p.cameraAt(controller.frame);
        _orbitAt = stage;
        _mode = _DragMode.parallaxPan;
        controller.beginInteraction();
        return;
      }
      if (held case var s? when !s.locked) {
        _orbiting = s.id;
        _orbitFrom = s.cameraAt(controller.frame);
        _orbitAt = stage;
        _mode = _DragMode.stageOrbit;
        controller.beginInteraction();
        return;
      }
    }

    // A selected path's points and handles are grabbed before anything
    // else, as a team's players are: they are drawn on top of the curve.
    var path = _selectedPath();
    if (path != null) {
      var grab = _hitPathControl(path, doc);
      if (grab != null) {
        var (index, isHandle, isOut) = grab;
        _nodeIndex = index;
        _nodeHandleOut = isOut;
        _mode = isHandle ? _DragMode.handle : _DragMode.node;
        controller.beginInteraction();
        return;
      }
    }

    // Inside the box of something already selected whose box is not its
    // shape (a curved line, a path, text on a line) takes hold of it.
    // Selecting one still needs the stroke, or a bowed line's empty box
    // would steal clicks meant for what is under it.
    if (!_shiftHeld && controller.selection.length == 1) {
      var chosen = document.elementById(controller.selection.first);
      if (chosen != null &&
          !chosen.locked &&
          chosen.visible &&
          _boxIsNotTheShape(chosen) &&
          _visualBounds(chosen).contains(doc) &&
          _hitElement(doc) == null) {
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // Outside the frame there is nothing to hit: clicking the margin clears
    // the selection.
    if (!_viewRect.contains(stage) && _hitHandle(stage) == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.none;
      return;
    }

    // Neither the flow grips nor the resize handles where the press is on a
    // piece of writing drawn outside its own box: see _looseTextPiece.
    if (_looseTextPiece(doc) == null) {
      // A flow grip, before the resize handles, but only where it is the
      // nearer: on a short box the grip lands on the middle handle.
      var nearest = _nearestHandle(stage);
      if (_hitFlowGrip(stage, beat: nearest?.$2 ?? double.infinity)
          case var grip?) {
        var selected = document.elementById(controller.selection.first);
        // A locked connector still shows (it is how a chain is read) but does
        // not answer the pointer.
        if (controller.lockJoins) return;
        // Dragging the incoming grip takes hold of the link that arrives here,
        // which belongs to the box in front. The loose end moves; where it is
        // dropped is what it means.
        var from = grip.out
            ? controller.selection.first
            : (selected is TextElement
                ? flowSourceOf(selected, document)?.id
                : null);
        if (from != null) {
          setState(() {
            _flowFrom = from;
            _flowAt = stage;
            _mode = _DragMode.flow;
          });
          return;
        }
      }

      var handle = nearest?.$1;
      if (handle != null) {
        // A side handle slants the element instead, with Command held or the
        // Skew switch on, one element at a time.
        var side = handle == StageHandle.topCenter ||
            handle == StageHandle.bottomCenter ||
            handle == StageHandle.centerLeft ||
            handle == StageHandle.centerRight;
        // The one copy's box sizes and turns that copy: its own values, as
        // its Instances card sets them. It has no slant of its own.
        if (_oneCopy case (var e, var i)?) {
          _beginCopyBox(e, i,
              handle == StageHandle.rotate
                  ? _DragMode.copyTurn
                  : _DragMode.copySize,
              handle);
          return;
        }
        var skewing = side &&
            _chosen.length == 1 &&
            (controller.skewHandles || HardwareKeyboard.instance.isMetaPressed);
        _beginTransform(
            handle == StageHandle.rotate
                ? _DragMode.rotate
                : skewing
                    ? _DragMode.skew
                    : _DragMode.resize,
            handle);
        return;
      }
    }

    // The retouching brush, before anything else: while it is on, a drag is
    // a stroke and nothing on the canvas moves.
    if (controller.retouch.on) {
      var picture = _selectedPicture();
      if (picture != null) {
        _painting = picture.id;
        _mode = _DragMode.none;
        controller.beginInteraction();
        _paintStrokeAt(doc, start: true);
        return;
      }
    }

    // A player of any team, before anything else on the canvas: a player
    // dragged outside his team's box, or standing in the other side's half,
    // would otherwise find no team or the wrong one. A dot is the smallest
    // and topmost thing and wins against every box.
    var hit = _hitAnyPlayer(doc);
    if (hit != null) {
      var (team, index) = hit;
      if (controller.selection.length != 1 ||
          controller.selection.first != team.id) {
        controller.selectOnly(team.id);
      }
      _mode = _DragMode.player;
      _playerIndex = index;
      // Held by where they stand rather than by the middle of their token,
      // which on a pitch seen at an angle is lifted off the ground.
      _playerGrab = doc -
          playerPlace(teamGround(document, team, controller.frame), team,
                  team.players[index], controller.frame)
              .ground;
      // Clicking a player is also how the timeline is pointed at them: a
      // player has no id and cannot be selected.
      controller.focusedPlayer = index;
      controller.beginInteraction();
      return;
    }

    // A placed label of the selected chart, before the chart itself: it sits
    // inside the chart's box, so the ordinary hit test would move the chart.
    var chart = controller.selected;
    if (chart is ChartElement && !chart.locked) {
      var grab = chartLabelGrabAt(
          chart, chart.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc, _docSlop);
      if (grab != null) {
        // A placed key is both the thing that moves and the row of switches:
        // armed here, decided on release by how far the pointer travelled.
        if (grab.part == ChartLabelPart.legend &&
            controller.selection.length == 1) {
          var at = _legendSeriesAt(chart, doc);
          if (at >= 0) {
            _pendingLegend = chart;
            _pendingLegendAt = at;
          }
        }
        _labelGrab = grab;
        _mode = _DragMode.chartLabel;
        controller.beginInteraction();
        return;
      }
    }

    // A column rule of the selected table, before the table itself, which
    // would otherwise be picked up.
    var table = controller.selected;
    if (table is TableElement && !table.locked) {
      var divider =
          tableColumnAt(table, table.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc, _docSlop);
      if (divider != null) {
        _columnGrab = divider;
        _mode = _DragMode.tableColumn;
        controller.beginInteraction();
        return;
      }
    }

    // A speaker on the master, pressed from a page. It cannot be selected
    // there (the master is edited on its own), so a press means pressing
    // it: background music with a mute switch sits on the master.
    if (_masterAudioAt(doc) case (var sound, var part)?) {
      _pressAudio(sound, part, doc);
      _mode = _DragMode.none;
      return;
    }
    if (_masterVideoAt(doc) case (var film, var part)?) {
      _pressVideo(film, part, doc);
      _mode = _DragMode.none;
      return;
    }

    // A piece of a text element counts as that element, wherever it is
    // drawn (a gap or a side can put it outside its box), and wins against
    // anything drawn under its element.
    var element = _topmostOf(_hitElement(doc), _textPieceOwner(doc));
    if (element == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.marquee;
      setState(() => _marquee = Rect.fromPoints(doc, doc));
      return;
    }

    // A selected button is tried by clicking it and moved by dragging it,
    // so the action waits for pointer-up, where the distance travelled is
    // known. See _onPointerUp.
    if (element is ButtonElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingButton = element;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A selected speaker's own controls, on the same terms as a button: a
    // press that stays put plays, mutes or sets the volume, and one that
    // travels moves it. And a selected video's: its play button, its bar,
    // or the picture itself.
    if (element is VideoElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _videoPartAt(element, doc);
      if (part != null) {
        _pendingVideo = element;
        _pendingVideoPart = part;
        _pendingVideoAt = doc;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A selected instrument's keys: down, the note sounds at once, and let
    // go, it stops. A press that travels lets the note go and moves the
    // keyboard instead. Further down the key is harder, as on a real one.
    if (element is AudioElement &&
        element.instrument != null &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var keys =
          keyboardLayout(element.instrument!, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
      if (keys.keyAt(doc) case (var key, var depth)?) {
        controller.noteOn(element, key, velocity: (50 + depth * 77).round());
        _keyDown = (element, key);
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    if (element is AudioElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _audioPartAt(element, doc);
      if (part != null) {
        _pendingAudio = element;
        _pendingAudioPart = part;
        _pendingAudioAt = doc;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A live counter's own buttons, on the same terms: only when it is the
    // thing selected and the press does not turn into a drag. A freely
    // placed piece is both (press it and it runs, drag it and it moves), so
    // the press is armed here and the mode is the one that moves the piece.
    if (element is CounterElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var part = _counterPartUnder(element, doc);
      var at = element.live ? _counterButtonAt(element, doc) : -1;
      if (part != null) {
        controller.beginInteraction();
        _counterPart = element.id;
        _counterPartAt = part;
        _dragStart = doc;
        if (at >= 0 && element.live) {
          _pendingCounter = element;
          _pendingCounterAt = at;
        }
        setState(() => _mode = _DragMode.counterPart);
        return;
      }
      if (at >= 0) {
        _pendingCounter = element;
        _pendingCounterAt = at;
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A chart's key entry switches that series off and on, on the same
    // terms: only while the chart is selected.
    if (element is ChartElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var at = _legendSeriesAt(element, doc);
      if (at >= 0) {
        _pendingLegend = element;
        _pendingLegendAt = at;
        // Held rather than tapped, the same press moves the key instead.
        _legendHold = Timer(_legendHoldDelay, () => _holdLegend(element));
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A second click on a selected drawing opens it for editing point by
    // point, as a second click opens text for typing.
    if (element is VectorElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < _doubleClickWindow) {
      _mode = _DragMode.none;
      // And the shape that was double-clicked picked, ready to be worked on.
      var at = doc;
      unawaited(startVectorEditing(context, controller, element).then((_) {
        var e = controller.editingVector;
        if (!mounted || e == null || e.id != element.id) return;
        var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
        var shape = shapeAt(e, at, reach);
        if (shape >= 0) controller.pickVectorShape(shape);
      }));
      return;
    }

    // A second click on a selected picture opens its layers, with the layer
    // under the click picked. With the base picture picked, dragging moves
    // the picture inside its box (see _framing).
    if (element is ImageElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < _doubleClickWindow) {
      controller.editImage(element.id, layer: layerAt(element, doc).id);
      _mode = _DragMode.none;
      return;
    }

    // A second click on a cell of a selected table opens it for typing.
    if (element is TableElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < _doubleClickWindow) {
      var at = tableCellAt(element, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc);
      if (at != null) {
        setState(() => _editingCell = (element.id, at.$1, at.$2));
        _mode = _DragMode.none;
        return;
      }
    }

    // A second click on a selected text element opens it for typing; the
    // first selects, so it is still moved by dragging. Not one whose words
    // come from a document or that is flowed into: neither owns its words,
    // and what was typed would be written over.
    if (element is TextElement &&
        !element.document.on &&
        flowSourceOf(element, document) == null &&
        !_shiftHeld &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < _doubleClickWindow) {
      setState(() {
        _editingText = element.id;
        // Whichever piece the second click landed on, or the element's own
        // words.
        _editingItem = _textItemAt(element, doc)?.id;
      });
      // The piece being typed into is the one picked in its Layers, so its
      // settings are the ones showing.
      controller.pickTextLayer(element.id, _editingItem);
      _mode = _DragMode.none;
      return;
    }
    _lastClickAt = clock.now();

    // A copy of an element reused: see _pressCopy.
    if (_pressCopy(element, doc)) return;

    if (_shiftHeld) {
      controller.toggleSelected(element.id);
    } else if (!controller.selection.contains(element.id)) {
      controller.selectOnly(element.id);
    }

    // A team with its frame locked, or standing on a pitch, is still
    // selectable but its box does not move. A drag that was going to take
    // hold of a player has been dealt with above.
    if (element is TeamElement && element.frameFixed) {
      _mode = _DragMode.none;
      return;
    }

    _beginTransform(_DragMode.move, null);
  }

  /// _pressCopy takes a press on [element], reused, at [doc] for the copy
  /// there (Ken, 2026-11-08). Alt drags out new copies of it (or of those
  /// picked, it among them); Shift picks it in or out; with copies picked,
  /// it is picked and dragged on its own -- otherwise the press goes on to
  /// the element, a drag moving them all and a click picking this one (see
  /// _onPointerUp). True where the press is dealt with.
  bool _pressCopy(CanvasElement element, Offset doc) {
    var set = element.base.motion.instances;
    if (set == null) return false;
    var i = element.instanceAt(doc, controller.frame, controller.document,
        live: controller.liveMotion);
    if (i == null) return false;
    var id = set.items[i].id;
    _pressedCopy = id;
    _pressedCopyOf = element.id;
    var picked = controller.pickedCopiesOf(element.id);
    if (HardwareKeyboard.instance.isAltPressed) {
      if (!controller.selection.contains(element.id)) {
        controller.selectOnly(element.id);
      }
      controller.beginInteraction();
      _dragCopies = controller.duplicateCopies(
          element.id, picked.contains(id) ? picked : {id}, Offset.zero);
      _copiesStart = controller.motionOf(element.id).instances;
      _pressedCopy = null;
      _mode = _DragMode.copies;
      return true;
    }
    if (_shiftHeld && controller.selection.contains(element.id)) {
      controller.pickCopy(element.id, id, toggle: true);
      _pressedCopy = null;
      _mode = _DragMode.none;
      return true;
    }
    if (picked.isNotEmpty) {
      if (!picked.contains(id)) {
        controller.pickCopy(element.id, id);
        picked = {id};
      }
      controller.beginInteraction();
      _dragCopies = picked;
      _copiesStart = set;
      _pressedCopy = null;
      _mode = _DragMode.copies;
      return true;
    }
    return false;
  }

  /// _copyPivot is what the one copy's box sizes and turns about, while a
  /// handle of it is held: its anchor, which stays where it is (see
  /// CanvasElement.boundsWith). _copySize and _copyTurn are its own Size and
  /// Turn as the drag began.
  Offset _copyPivot = Offset.zero;
  double _copySize = 1, _copyTurn = 0;

  void _beginCopyBox(
      CanvasElement e, int i, _DragMode mode, StageHandle? handle) {
    var set = e.base.motion.instances!;
    _mode = mode;
    _handle = handle;
    _copyPivot = e.anchorIn(e.boundsWith(_copyPose(e, i)));
    _copySize = set.sizeOf(i);
    _copyTurn = set.turnOf(i);
    controller.beginInteraction();
  }

  /// _applyCopyBox sizes or turns the one copy picked as its handle is
  /// dragged to [doc]. Sized evenly, by how much farther from its anchor the
  /// pointer is along the line it was pressed on (a copy has one Size);
  /// turned by the angle swept, to fifteen degrees with Shift.
  void _applyCopyBox(Offset doc) {
    var e = controller.selected;
    if (e == null) return;
    var from = _dragStart - _copyPivot, to = doc - _copyPivot;
    if (_mode == _DragMode.copyTurn) {
      var swept = (math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx)) *
          180 /
          math.pi;
      var turn = _copyTurn + swept;
      if (_shiftHeld) turn = (turn / 15).round() * 15;
      turn = (turn + 180) % 360 - 180;
      controller.setCopyOwn(e.id, CopyValue.turn.name, turn, transient: true);
      return;
    }
    var along = from.distanceSquared;
    if (along < 1e-6) return;
    var f = (to.dx * from.dx + to.dy * from.dy) / along;
    var size = (_copySize * f).clamp(CopyValue.size.min, CopyValue.size.max);
    controller.setCopyOwn(e.id, CopyValue.size.name, size, transient: true);
  }

  /// _moveCopies puts the copies being dragged [delta] from where they
  /// began, one way only with Shift.
  void _moveCopies(Offset delta) {
    var from = _copiesStart, of = controller.selected?.id;
    if (from == null || of == null) return;
    if (_shiftHeld) {
      delta = delta.dx.abs() >= delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    controller.setInstances(
        of,
        from.copyWith(items: [
          for (var x in from.items)
            _dragCopies.contains(x.id)
                ? x.copyWith(dx: x.dx + delta.dx, dy: x.dy + delta.dy)
                : x,
        ]),
        transient: true);
  }

  /// _selectedPath is the one selected element, when it is a path.
  PathElement? _selectedPath() {
    var selected = controller.selected;
    return selected is PathElement ? selected : null;
  }

  /// _hitPathControl finds the point or handle under [doc], as (index,
  /// isHandle, isOutHandle). Handles first, so a handle on top of its own
  /// point (an unbent node's) can still be pulled out.
  (int, bool, bool)? _hitPathControl(PathElement path, Offset doc) {
    // In document units, so the grab area is the same size on screen at any
    // zoom.
    var reach = (handleSize / 2 + handleHitSlop) / _scale;
    for (var i = 0; i < path.nodes.length; i++) {
      var node = path.nodes[i];
      if ((doc - path.outHandleOf(node)).distance <= reach &&
          (node.outDx != 0 || node.outDy != 0)) {
        return (i, true, true);
      }
      if ((doc - path.inHandleOf(node)).distance <= reach &&
          (node.inDx != 0 || node.inDy != 0)) {
        return (i, true, false);
      }
    }
    for (var i = 0; i < path.nodes.length; i++) {
      if ((doc - path.pointOf(path.nodes[i])).distance <= reach) {
        return (i, false, false);
      }
    }
    return null;
  }

  /// _vectorPart is which part of the picked point a drag has hold of.
  VectorPart _vectorPart = VectorPart.point;

  /// _vectorBefore and _vectorFrom are the drawing and the press a drag of
  /// several points started from, so the drag is applied to where they were.
  VectorElement? _vectorBefore;
  Offset _vectorFrom = Offset.zero;

  /// _vectorShapeUnder is the shape a box was started on, which a click (a
  /// box that never grew) picks.
  int _vectorShapeUnder = -1;

  /// _pressVector answers a press on a drawing being edited, returning
  /// whether it took the press.
  ///
  /// With the pen out, a press puts a point down. Otherwise: a point or
  /// handle is taken hold of (Shift adds or removes it; one of several picked
  /// drags them all); a second click on the picked point makes it a corner or
  /// smooth; a second click on the picked shape's outline puts a point in it;
  /// a press on a shape picks it and drags it whole; and a press on empty
  /// space drags a box to pick points. Outside the drawing the editing ends,
  /// and the press is left for whatever else wants it.
  bool _pressVector(VectorElement e, Offset doc) {
    var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
    var twice = clock.now().difference(_lastClickAt) < _doubleClickWindow;
    // A double-click here is two clicks on one spot.
    var sameSpot = (doc - _lastVectorClick).distance * _scale <= _penPullMin;
    _lastClickAt = clock.now();
    _lastVectorClick = doc;
    // The pen takes hold of points and handles as picking does, and the
    // next point it puts down joins on from the point it took.
    VectorHit? penHit;
    switch (controller.vectorTool) {
      case VectorTool.pen:
        // A double-click finishes the line, as Escape does, ready for the
        // next to start fresh.
        if (twice && sameSpot) {
          controller.finishPenShape();
          _mode = _DragMode.none;
          return true;
        }
        if (_penCloses(e, doc, reach)) return true;
        penHit = hitVector(e, doc, reach,
            shape: controller.vectorShape,
            picked: controller.vectorPick,
            picks: controller.vectorPicks);
        if (penHit == null) {
          if (anyPointAt(e, doc, reach) case var on?) {
            penHit = VectorHit(on, VectorPart.point);
          }
        }
        if (penHit == null) {
          _penPut(e, doc);
          return true;
        }
      case VectorTool.scale when _pressScale(e, doc, reach):
        return true;
      case VectorTool.boolean:
        _pressCombine(e, doc, reach);
        return true;
      case VectorTool.eraser:
        _pressEraser(e, doc, reach);
        return true;
      case VectorTool.selectShapes:
        _pressItems(e, doc, reach);
        return true;
      case VectorTool.align when controller.vectorAlignsShapes:
        _pressItems(e, doc, reach);
        return true;
      case VectorTool.text:
        // On text: type into it. Anywhere else: new text, starting there.
        var under = shapeAt(e, doc, reach);
        var shapes = e.shapes ?? const <VectorShape>[];
        if (under >= 0 && shapes[under].liveText != null) {
          controller.startVectorTyping(under);
          _typingFor = -2;
        } else {
          controller.newVectorText(VectorSpace(e).toDrawing(doc));
          _typingFor = -2;
        }
        _mode = _DragMode.none;
        return true;
      case VectorTool.knife:
        _knife = [doc];
        _mode = _DragMode.vectorKnife;
        return true;
      case VectorTool.shapes:
        _vectorBefore = e;
        _shapeFrom = doc;
        controller.beginInteraction();
        // On the shape just drawn or picked, or a handle of its box: moved or
        // resized, not another drawn.
        if (_shapeGrabbed(e, doc) case (var group, var box, var handle)?) {
          _shapeGroup = group;
          _shapeBox = box;
          _shapeHandle = handle;
          _mode = _DragMode.vectorShapeFit;
          return true;
        }
        _mode = _DragMode.vectorShapeDraw;
        return true;
      case VectorTool.pencil when controller.vectorQuickFill:
        _pressQuickFill(e, doc, reach);
        return true;
      case VectorTool.pencil:
        _pressPencil(e, doc);
        return true;
      case VectorTool.corner when _pressCorner(e, doc, reach):
        return true;
      case VectorTool.tint || VectorTool.shadow || VectorTool.highlight
          when _pressTint(e, doc):
        return true;
      default:
        // Otherwise as the select tool (a scale with nothing to scale, or a
        // tint off any point): a box, a shape picked, a click off.
        break;
    }
    var hit = penHit ??
        hitVector(e, doc, reach,
            shape: controller.vectorShape,
            picked: controller.vectorPick,
            picks: controller.vectorPicks);
    var pen = controller.vectorTool == VectorTool.pen;
    if (hit != null) {
      var point = hit.part == VectorPart.point;
      if (point && _shiftHeld) {
        controller.pickVectorPoint(hit.pick, toggle: true);
        if (pen) controller.penFrom(controller.vectorPick);
        _mode = _DragMode.none;
        return true;
      }
      if (twice && point && controller.vectorPick == hit.pick) {
        controller.replaceElement(withSmoothToggled(e, hit.pick));
        _mode = _DragMode.none;
        return true;
      }
      if (point &&
          controller.vectorPicks.length > 1 &&
          controller.vectorPicks.contains(hit.pick)) {
        _vectorBefore = e;
        _vectorFrom = doc;
        _mode = _DragMode.vectorPoints;
        controller.beginInteraction();
        return true;
      }
      if (point) controller.pickVectorPoint(hit.pick);
      if (pen) controller.penFrom(hit.pick);
      _vectorPart = hit.part;
      _mode = _DragMode.vectorPoint;
      controller.beginInteraction();
      return true;
    }
    // Inside the box round several picked points: they are dragged, all
    // together, by their middle as well as by any one of them.
    if (!twice && !_shiftHeld) {
      var box = picksBox(e, controller.vectorPicks);
      // As far out as the box is drawn: a handle's width round the points.
      if (box != null && box.inflate(e.handleSize / _scale).contains(doc)) {
        _vectorBefore = e;
        _vectorFrom = doc;
        _mode = _DragMode.vectorPoints;
        controller.beginInteraction();
        return true;
      }
    }
    // A double-click on a shape's line puts a point in it there; on its
    // fill, away from the line, it picks every point connected to the part
    // clicked. Both clicks on one spot.
    if (twice && sameSpot) {
      var shape = controller.vectorShape >= 0
          ? controller.vectorShape
          : shapeAt(e, doc, reach);
      var shapes = e.shapes ?? const <VectorShape>[];
      if (shape >= 0 && shape < shapes.length) {
        var space = VectorSpace(e);
        var onLine = math.max(
            shapes[shape].strokeWidth / 2 / space.unitsPer, reach * 0.5);
        var at = nearestSegment(e, shape, doc, onLine);
        if (at != null) {
          var (next, pick) = withPointAdded(e, shape, at.$1, at.$2, at.$3);
          controller.replaceElement(next);
          controller.pickVectorPoint(pick);
          _mode = _DragMode.none;
          return true;
        }
      }
      var under = shapeAt(e, doc, reach);
      if (under >= 0) {
        controller.pickVectorPoints(
            connectedPicks(e, under, VectorSpace(e).toDrawing(doc)));
        _mode = _DragMode.none;
        return true;
      }
    }
    // A shape cut into pieces: a press on a piece picks it -- every point
    // of it -- and a drag moves it alone. See vector_cut.dart.
    if (!twice && !_shiftHeld && controller.vectorTool == VectorTool.select) {
      var under = shapeAt(e, doc, reach);
      var shapes = e.shapes ?? const <VectorShape>[];
      if (under >= 0 && partsOf(shapes[under]).length > 1) {
        var space = VectorSpace(e);
        var shape = shapes[under];
        if (partAt(shape, space.toDrawing(doc), reach * space.unitsPer)
            case var part?) {
          controller.pickVectorPoints({
            for (var (p, run) in shape.paths.indexed)
              if (run.part == part)
                for (var n = 0; n < run.nodes.length; n++)
                  VectorPick(under, p, n),
          });
          _vectorBefore = e;
          _vectorFrom = doc;
          _mode = _DragMode.vectorPoints;
          controller.beginInteraction();
          return true;
        }
      }
    }
    // Anywhere else (on a shape, empty space, or off the drawing) starts a
    // box to pick points with: in edit mode a drag picks points. Let go
    // without moving, it is a click, which on a shape picks the shape. See
    // _onPointerUp.
    _vectorShapeUnder = shapeAt(e, doc, reach);
    // A box started off the drawing can sweep up its edge points; a click
    // off it that does not move finishes the editing. What is picked stays
    // picked until the box is let go.
    _vectorPressedOutside = !_visualBounds(e).contains(doc);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorMarquee;
    return true;
  }

  /// _vectorPressedOutside is whether the press a box started from was
  /// outside the drawing, so that, let go without moving, it finishes the
  /// editing.
  bool _vectorPressedOutside = false;

  /// _pointer is the pointer event being handled: what the pen says about
  /// pressure, tilt and its buttons, which the press and drag handlers
  /// are not otherwise given.
  PointerEvent? _pointer;

  /// _penSamples is the pencil stroke being drawn, reading by reading, and
  /// _penWidth its full width in the drawing's units.
  List<PenSample> _penSamples = [];
  double _penWidth = 1;
  double _eraseReach = 0;

  /// _penLean is which way, and how far, the pen leans (across and down,
  /// each -1 to 1), or null for a mouse, or a pen that does not say.
  Offset? _penLean() {
    var tablet = TabletInput.instance;
    if (tablet.fresh) return Offset(tablet.tiltX, tablet.tiltY);
    var ev = _pointer;
    if (ev == null ||
        (ev.kind != PointerDeviceKind.stylus &&
            ev.kind != PointerDeviceKind.invertedStylus)) {
      return null;
    }
    // Flutter's own: how far over, a quarter turn at most, and which way.
    var lean = (ev.tilt / (math.pi / 2)).clamp(0.0, 1.0);
    return Offset(math.sin(ev.orientation), -math.cos(ev.orientation)) * lean;
  }

  /// _penSample is the pen as [_pointer] last reported it, at [doc]: its
  /// pressure and tilt where the pen says (a mouse, or a platform that passes
  /// neither on, gives null, and the brush makes do with speed).
  PenSample _penSample(Offset doc) {
    var ev = _pointer;
    // On macOS the runner reads the pen for Flutter -- see TabletInput.
    var tablet = TabletInput.instance;
    if (tablet.fresh) {
      return PenSample(doc,
          pressure: tablet.pressure,
          tilt: tablet.tilt,
          time: ev?.timeStamp ?? Duration.zero);
    }
    var pen = ev != null &&
        (ev.kind == PointerDeviceKind.stylus ||
            ev.kind == PointerDeviceKind.invertedStylus);
    double? pressure;
    if (pen && ev.pressureMax > ev.pressureMin) {
      pressure =
          (ev.pressure - ev.pressureMin) / (ev.pressureMax - ev.pressureMin);
    }
    return PenSample(doc,
        pressure: pressure,
        tilt: pen ? ev.tilt : null,
        time: ev?.timeStamp ?? Duration.zero);
  }

  /// _pressEraser starts the eraser: rubbing out what it goes over (the
  /// lines, the fills, or both, as set) or, set to take out whole lines,
  /// every line and shape it touches. On the page only, as the pencil is.
  void _pressEraser(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    if (!_onPage(doc)) return;
    controller.beginInteraction();
    if (controller.vectorEraseWhole) {
      _eraseReach = math.max(reach, controller.vectorEraseSize / 2 / _scale);
      controller.replaceElement(withoutShapesAt(e, doc, _eraseReach),
          transient: true);
      _mode = _DragMode.vectorErase;
      return;
    }
    _startStroke(
        e,
        doc,
        VectorTint(
            points: const [],
            paint: const PaintSpec(Color(0xFF000000)),
            width:
                controller.vectorEraseSize / _scale * VectorSpace(e).unitsPer,
            soft: controller.vectorEraseSoft,
            line: controller.vectorEraseLine,
            fill: controller.vectorEraseFill,
            erase: true),
        rubOut: true);
    _mode = _DragMode.vectorRub;
  }

  /// _picksShapes is whether presses on the drawing pick whole shapes: the
  /// select shapes tool, or the align tool after it.
  bool get _picksShapes =>
      controller.vectorTool == VectorTool.selectShapes ||
      (controller.vectorTool == VectorTool.align &&
          controller.vectorAlignsShapes);

  /// _itemsBox is the box round the shapes picked when the drag began, in
  /// the drawing's units; _itemsHandle the handle held (see boxHandles), -1
  /// for the turning handle, or null for the whole, moved.
  Rect _itemsBox = Rect.zero;
  int? _itemsHandle;

  /// _pressItems is a press with the select shapes tool: on a handle of the
  /// box round what is picked, that handle; on a shape, it (with Shift, added
  /// or taken out) held to be moved; inside the box, everything picked, held;
  /// anywhere else, nothing picked.
  void _pressItems(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var space = VectorSpace(e);
    var items = controller.vectorItems;
    var box = itemsExtent(e, items);
    void hold(Rect box, int? handle) {
      _vectorBefore = e;
      _shapeFrom = doc;
      _itemsBox = box;
      _itemsHandle = handle;
      controller.beginInteraction();
      _mode = _DragMode.vectorItems;
    }

    if (box != null && !_shiftHeld) {
      var top = space.toCanvas(box.topCenter) * _scale;
      if ((doc * _scale - (top - const Offset(0, shapeTurnReach))).distance <=
          8) {
        return hold(box, -1);
      }
      for (var (i, h) in boxHandles(box).indexed) {
        if ((space.toCanvas(h) - doc).distance * _scale <= 7) {
          return hold(box, i);
        }
      }
    }
    var under = itemAt(e, doc, reach);
    if (under != null) {
      if (_shiftHeld) {
        controller.pickVectorItem(under, toggle: true);
        return;
      }
      if (!items.contains(under)) controller.pickVectorItem(under);
      var now = itemsExtent(e, controller.vectorItems);
      if (now != null) hold(now, null);
      return;
    }
    if (box != null && box.contains(space.toDrawing(doc)) && !_shiftHeld) {
      return hold(box, null);
    }
    // Empty space: a box dragged across it picks every shape it touches;
    // let go without moving, nothing picked.
    if (!_shiftHeld) controller.pickVectorItem(null);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorItemsBox;
  }

  /// _dragItems moves, sizes or turns what is picked to follow [doc]: by a
  /// handle, the opposite side staying put (Shift keeps a corner's
  /// proportions); by the turning handle, about the box's middle (Shift in
  /// steps of fifteen degrees); held inside, the whole of it.
  void _dragItems(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var space = VectorSpace(before);
    var at = space.toDrawing(doc);
    var from = space.toDrawing(_shapeFrom);
    var box = _itemsBox;
    var items = controller.vectorItems;
    VectorElement next;
    if (_itemsHandle == -1) {
      var c = box.center;
      var turn = math.atan2(at.dy - c.dy, at.dx - c.dx) -
          math.atan2(from.dy - c.dy, from.dx - c.dx);
      if (_shiftHeld) {
        const step = math.pi / 12;
        turn = (turn / step).round() * step;
      }
      next = withItemsTurned(before, items, c, turn);
    } else {
      var to = _itemsHandle == null
          ? box.shift(at - from)
          : boxResized(box, _itemsHandle!, at,
              even: _shiftHeld, least: space.unitsPer);
      next = withItemsFitted(before, items, box, to);
    }
    controller.replaceElement(next, transient: true);
  }

  /// _shapeFrom is where the shape being drawn was started, on the canvas.
  Offset _shapeFrom = Offset.zero;

  /// _shapeGroup, _shapeBox and _shapeHandle are the shape the shapes tool is
  /// moving or resizing: its group, its box when the drag began (in the
  /// drawing's units), and the handle held (see boxHandles), or null for the
  /// whole of it.
  int _shapeGroup = -1;
  Rect _shapeBox = Rect.zero;
  int? _shapeHandle;

  /// _shapeGrabbed is the shape picked (what the shapes tool last drew, or
  /// whatever was picked) where [doc] is on it or a handle of its box: its
  /// group, its box, and the handle, or null for inside it. Null where the
  /// press is elsewhere, and draws a new shape.
  (int, Rect, int?)? _shapeGrabbed(VectorElement e, Offset doc) {
    var picked = controller.vectorShapeMade;
    if (picked < 0) return null;
    var group = groupStarts(e).indexOf(groupOf(e, picked));
    var box = groupExtent(e, group);
    if (group < 0 || box == null) return null;
    var space = VectorSpace(e);
    for (var (i, h) in boxHandles(box).indexed) {
      if ((space.toCanvas(h) - doc).distance * _scale <= 7) {
        return (group, box, i);
      }
    }
    if (box.contains(space.toDrawing(doc))) return (group, box, null);
    return null;
  }

  /// _fitShape moves or resizes the shape held to follow [doc]: by its
  /// handle, the opposite side staying put (Shift keeps a corner's
  /// proportions), or, held inside, the whole of it.
  void _fitShape(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var space = VectorSpace(before);
    var at = space.toDrawing(doc);
    var box = _shapeBox;
    var next = _shapeHandle == null
        ? box.shift(at - space.toDrawing(_shapeFrom))
        : boxResized(box, _shapeHandle!, at,
            even: _shiftHeld, least: space.unitsPer);
    controller.replaceElement(withGroupFitted(before, _shapeGroup, box, next),
        transient: true);
  }

  /// _drawShape draws the shapes tool's shape from where the drag began to
  /// [doc]: in the box between them, or from one to the other for a line or
  /// an arrow. Shift keeps a box square and a line to steps of forty-five
  /// degrees; Alt draws out from the middle. [clicked] draws one of a good
  /// size round the click, for a click that never became a drag.
  void _drawShape(Offset doc, {bool clicked = false}) {
    var before = _vectorBefore;
    if (before == null) return;
    var kind = controller.vectorShapeKind;
    var shift = _shiftHeld, alt = HardwareKeyboard.instance.isAltPressed;
    var a = _shapeFrom, b = doc;
    if (clicked) {
      var half = 40 / _scale;
      a = _shapeFrom - Offset(half, kind.fromEnds ? 0 : half);
      b = _shapeFrom + Offset(half, kind.fromEnds ? 0 : half);
    } else if (kind.fromEnds) {
      var d = b - a;
      if (shift && d.distance > 0) {
        const step = math.pi / 4;
        var angle = (math.atan2(d.dy, d.dx) / step).round() * step;
        d = Offset(math.cos(angle), math.sin(angle)) * d.distance;
      }
      b = a + d;
      if (alt) a = a - d;
    } else {
      var d = b - a;
      if (kind.even || shift) {
        var m = math.max(d.dx.abs(), d.dy.abs());
        d = Offset(d.dx < 0 ? -m : m, d.dy < 0 ? -m : m);
      }
      b = a + d;
      if (alt) a = a - d;
    }
    var space = VectorSpace(before);
    var from = space.toDrawing(a), to = space.toDrawing(b);
    var box = Rect.fromPoints(from, to);
    var shape = shapeOf(kind, box,
        from: from,
        to: to,
        sides: controller.vectorShapeSides,
        inner: controller.vectorStarInner,
        corner: controller.vectorShapeCorner * math.min(box.width, box.height),
        fill: controller.vectorShapeFill,
        stroke: controller.vectorShapeLine,
        strokeWidth: controller.vectorShapeWidth / _scale * space.unitsPer);
    controller.replaceElement(
        before.copyWith(shapes: [...?before.shapes, shape]),
        transient: true);
  }

  /// _typing holds what is typed into a drawing's text, in a field the reader
  /// never sees: it takes the keys, caret moves, selections and input methods,
  /// and the letters appear on the drawing. _typingFor is the shape it was
  /// last filled from, so a different one starts it afresh.
  final TextEditingController _typing = TextEditingController();
  final FocusNode _typingFocus = FocusNode(debugLabel: "vectorTyping");
  int _typingFor = -1;
  bool _filling = false;

  /// _typedLayout is the text being typed, laid out, with the drawing and the
  /// shape, or null.
  (VectorElement, VectorTextLayout)? _typedLayout() {
    var e = controller.editingVector;
    var i = controller.vectorTyping;
    var shapes = e?.shapes;
    if (e == null || shapes == null || i < 0 || i >= shapes.length) {
      return null;
    }
    var s = shapes[i];
    var t = s.liveText;
    if (t == null) return null;
    var pick = FontFiles.instance.cached(t.family, t.weight, t.italic);
    if (pick == null) return null;
    return (e, layoutVectorText(t, s.textOrigin ?? t.origin, pick));
  }

  /// _caret is where the caret is drawn, top to bottom, on the page.
  (Offset, Offset)? _caret() {
    if (_typedLayout() case (var e, var laid)?) {
      var at =
          _typing.selection.baseOffset.clamp(0, laid.carets.length - 1).toInt();
      var p = laid.carets[at];
      var space = VectorSpace(e);
      return (
        space.toCanvas(p - Offset(0, laid.ascent)),
        space.toCanvas(p + Offset(0, laid.descent)),
      );
    }
    return null;
  }

  /// _typingField is the unseen field typed into, while text is.
  Widget? _typingField() {
    var i = controller.vectorTyping;
    if (i < 0) {
      _typingFor = -1;
      return null;
    }
    var e = controller.editingVector;
    var t = (e?.shapes != null && i < e!.shapes!.length)
        ? e.shapes![i].liveText
        : null;
    if (_typingFor != i) {
      _typingFor = i;
      var text = t?.text ?? "";
      // Filled while the stage is being built, which is the rebuild.
      _filling = true;
      _typing.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
      _filling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _typingFocus.requestFocus();
      });
    }
    var caret = _caret();
    var at = caret == null ? Offset.zero : _toStage(caret.$1);
    return Positioned(
      left: at.dx,
      top: at.dy,
      width: 2,
      height: 2,
      child: Opacity(
        opacity: 0,
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              controller.stopVectorTyping();
              _focus.requestFocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            key: const ValueKey("vectorTypingField"),
            controller: _typing,
            focusNode: _typingFocus,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            onChanged: (v) {
              var e = controller.editingVector;
              var i = controller.vectorTyping;
              var shape = e?.shapes != null && i >= 0 && i < e!.shapes!.length
                  ? e.shapes![i]
                  : null;
              var t = shape?.liveText;
              if (t != null) {
                controller.retypeVectorText(i, t.copyWith(text: v));
              }
            },
          ),
        ),
      ),
    );
  }

  /// _sampleAt takes the colour of the canvas at [doc] (everything on it, as
  /// drawn at this frame) for the eyedropper.
  Future<void> _sampleAt(Offset doc) async {
    var rec = ui.PictureRecorder();
    var canvas = Canvas(rec);
    canvas.translate(-doc.dx, -doc.dy);
    paintCanvasDocument(canvas, controller.document,
        frame: controller.frame, images: controller.images);
    var picture = rec.endRecording();
    var image = await picture.toImage(1, 1);
    var bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    picture.dispose();
    if (bytes == null || !mounted) return;
    controller.sampledColour(Color.fromARGB(bytes.getUint8(3),
        bytes.getUint8(0), bytes.getUint8(1), bytes.getUint8(2)));
  }

  /// _knife is the knife's line, on the page, while it is being drawn.
  List<Offset> _knife = const [];

  /// _finishKnife cuts what the knife's line went through (the shape picked,
  /// or every shape it crossed) as one change.
  void _finishKnife() {
    var line = _knife;
    setState(() => _knife = const []);
    var e = controller.editingVector;
    if (e == null || line.length < 2) return;
    var space = VectorSpace(e);
    var drawn = simplifiedKnife([for (var p in line) space.toDrawing(p)],
        0.5 / _scale * space.unitsPer);
    var gap = controller.vectorKnifeGap * space.unitsPer;
    var shapes = e.shapes ?? const <VectorShape>[];
    var only = controller.vectorShape;
    var next = <VectorShape>[];
    var cut = false;
    for (var (i, s) in shapes.indexed) {
      var pieces = only >= 0 && i != only ? null : cutShape(s, drawn, gap);
      cut |= pieces != null;
      next.add(pieces ?? s);
    }
    if (!cut) return;
    controller.replaceElement(e.copyWith(shapes: next));
    // The points have new numbers: nothing of them stays picked.
    controller.pickVectorShape(only);
  }

  /// _pressQuickFill fills the area the lines close round the click with the
  /// fill colour, or, on an earlier quick fill (a fill with no line of its
  /// own), recolours it. An area the lines leave open is said so, and nothing
  /// is filled.
  void _pressQuickFill(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var colour = controller.vectorPencilFill;
    var hit = shapeAt(e, doc, reach);
    if (hit >= 0) {
      var s = e.shapes![hit];
      if (s.fill != null && s.stroke == null) {
        controller.replaceElement(e.withShape(hit, s.copyWith(fill: colour)));
        return;
      }
    }
    var gap = controller.vectorFillGap / _scale * VectorSpace(e).unitsPer;
    var snack = SnackBarModel.of(context);
    quickFilled(e, doc, colour, gap: gap).then((next) {
      // Only onto the drawing it was worked out from: anything done to it in
      // the meantime wins.
      if (!mounted || !identical(controller.editingVector, e)) return;
      if (next == null) {
        snack.error("That area isn't closed: no fill");
        return;
      }
      controller.replaceElement(next);
    });
  }

  /// _onPage is whether [doc] is on the page, the only place the pencil
  /// draws: a hand resting round the page, or a pen run off its edge, puts
  /// nothing down.
  bool _onPage(Offset doc) =>
      (Offset.zero & controller.document.size.size).contains(doc);

  /// _penRuns is the pencil stroke being drawn, as the stretches of it on the
  /// page: one, unless the pen went off the edge and came back, when each
  /// stretch is a line of its own.
  List<List<PenSample>> _penRuns = [];

  /// _pressPencil starts a stroke of the pencil: a new line, on top.
  void _pressPencil(VectorElement e, Offset doc) {
    if (!_onPage(doc)) {
      _mode = _DragMode.none;
      return;
    }
    var space = VectorSpace(e);
    _vectorBefore = e;
    _penInto = controller.vectorSelectedShapes;
    _penWidth = controller.vectorBrush.size / _scale * space.unitsPer;
    _penSamples = [_penSample(doc)];
    _penRuns = [_penSamples];
    controller.beginInteraction();
    _drawPencil();
    _mode = _DragMode.vectorPencil;
  }

  /// _penInto is the shapes picked as the pencil went down: one filled
  /// shape, and what is drawn in its colour is added to it rather than
  /// drawn as a shape of its own.
  Set<int> _penInto = const {};

  /// _mergePencil adds what the pencil has just drawn to the one filled shape
  /// picked, where it touches it, as a blob brush adds to a shape.
  void _mergePencil() {
    var before = _vectorBefore, e = controller.editingVector;
    if (before == null || e == null || _penInto.length != 1) return;
    var was = before.shapes ?? const <VectorShape>[];
    var now = e.shapes ?? const <VectorShape>[];
    var base = _penInto.first;
    if (now.length <= was.length || base >= was.length) return;
    if (groupMembers(before, base).length != 1) return;
    var target = was[base];
    // Only in its own colour, as a blob brush merges: a line drawn in
    // another (an eye on a face) is a shape of its own.
    var fill = target.fill, ink = controller.vectorPencilColour;
    if (fill == null ||
        (fill.r - ink.r).abs() > 0.01 ||
        (fill.g - ink.g).abs() > 0.01 ||
        (fill.b - ink.b).abs() > 0.01) {
      return;
    }
    // What was drawn, as the area it covers: its line, as wide as it is
    // drawn, and its fill.
    Path area(VectorShape s) {
      var out = Path();
      if (s.fill != null)
        out = Path.combine(PathOperation.union, out, vectorShapePath(s));
      if (s.stroke != null)
        out = Path.combine(PathOperation.union, out, vectorLinePath(s));
      return out;
    }

    var added = now.sublist(was.length);
    if (added.isEmpty) return;
    var into = vectorShapePath(target);
    var stroke = added
        .map(area)
        .reduce((a, b) => Path.combine(PathOperation.union, a, b));
    // Not touching it: a shape of its own, as drawn.
    if (Path.combine(PathOperation.intersect, into, stroke)
        .getBounds()
        .isEmpty) {
      return;
    }
    var merged = Path.combine(PathOperation.union, into, stroke);
    var paths =
        vectorPathsOf(merged, tolerance: 0.35 * VectorSpace(before).unitsPer);
    if (paths.isEmpty) return;
    controller.replaceElement(
        before.copyWith(shapes: [
          for (var (i, s) in was.indexed)
            i == base ? s.copyWith(paths: paths) : s,
        ]),
        transient: true);
  }

  void _applyPencil(Offset doc) {
    if (!_onPage(doc)) {
      // Off the page: the stretch drawn so far ends, and the next reading back
      // on it starts another.
      _penSamples = [];
      return;
    }
    var last = _penSamples.lastOrNull;
    // A reading less than a pixel on is no new reading.
    if (last != null && (doc - last.at).distance * _scale < 1) return;
    if (_penSamples.isEmpty) _penRuns.add(_penSamples);
    _penSamples.add(_penSample(doc));
    _drawPencil();
  }

  void _drawPencil() {
    var before = _vectorBefore;
    if (before == null) return;
    // The stroke and, with symmetry on, its mirror images: each a line of
    // its own, drawn as it is.
    var drawn = [
      for (var run in _penRuns)
        for (var (samples, brush) in mirroredStrokes(
            before, run, controller.vectorBrush,
            across: controller.vectorMirrorAcross,
            down: controller.vectorMirrorDown))
          if (pencilShape(before, samples, brush, controller.vectorPencilColour,
                  _penWidth,
                  fillColour: controller.vectorPencilFill)
              case var shape?)
            shape,
    ];
    if (drawn.isEmpty) return;
    controller.replaceElement(
        before.copyWith(shapes: [...?before.shapes, ...drawn]),
        transient: true);
  }

  /// _modifierButton is which pen button a key held as the pen touches stands
  /// for (Shift the first, Option the second, Control the third), or null.
  /// Command is left alone for shortcuts.
  int? _modifierButton() {
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed) return null;
    if (keys.isShiftPressed) return 0;
    if (keys.isAltPressed) return 1;
    if (keys.isControlPressed) return 2;
    return null;
  }

  /// _tabletButton is which of the pen's three buttons (0, 1 or 2) the
  /// tablet's last reading says is held, or null for none, or no reading.
  int? _tabletButton() {
    var t = TabletInput.instance;
    if (!t.fresh) return null;
    for (var (i, bit) in const [(0, 2), (1, 4), (2, 8)]) {
      if (t.buttons & bit != 0) return i;
    }
    return null;
  }

  /// _stylusPress does what a button on the pen (or its other end) is set to,
  /// with the pencil out, answering whether it took the press. A tablet's
  /// driver sends the pen's buttons as mouse buttons (right, middle, back
  /// clicks) as the tablet's settings map them.
  bool _stylusPress(PointerDownEvent event, Offset doc) {
    var e = controller.editingVector;
    if (e == null || controller.vectorTool != VectorTool.pencil) return false;
    var b = event.buttons;
    var buttons = controller.stylusButtons;
    StylusAction? action;
    if (event.kind == PointerDeviceKind.invertedStylus ||
        (TabletInput.instance.eraser && TabletInput.instance.near)) {
      action = controller.stylusEraser;
    } else if (_tabletButton() case var i?) {
      // The pen's own buttons, as the tablet reported them, where it sent
      // them as a reading rather than as a click.
      action = buttons[i];
    } else if (b & kSecondaryButton != 0) {
      action = buttons[0];
    } else if (b & kMiddleMouseButton != 0) {
      action = buttons[1];
    } else if (b & (kBackMouseButton | kForwardMouseButton) != 0) {
      action = buttons[2];
    } else if (_modifierButton() case var i?) {
      // A key held as the pen touches stands in for a button: the way to
      // reach them on a pen display whose own buttons are taken (a MovinkPad's
      // open its sidebar of keys).
      action = buttons[i];
    }
    if (action == null || action == StylusAction.draw) return false;
    var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
    _mode = _DragMode.none;
    switch (action) {
      case StylusAction.draw:
        return false;
      case StylusAction.erase:
        _eraseReach = math.max(reach, controller.vectorBrush.size / 2 / _scale);
        controller.beginInteraction();
        controller.replaceElement(withoutShapesAt(e, doc, _eraseReach),
            transient: true);
        _mode = _DragMode.vectorErase;
      case StylusAction.pickColour:
        var hit = shapeAt(e, doc, reach);
        if (hit >= 0) {
          var s = e.shapes![hit];
          if ((s.stroke ?? s.fill) case var c?) {
            controller.vectorPencilColour = c.withValues(alpha: 1);
          }
        }
      case StylusAction.pan:
        _mode = _DragMode.pan;
        _startPan = _clampedPan;
        _dragStart = event.localPosition;
      case StylusAction.undo:
        controller.undo();
      case StylusAction.select:
        controller.vectorTool = VectorTool.select;
      case StylusAction.nothing:
        break;
    }
    return true;
  }

  /// _cornerFrom is where, on the canvas, the corner being shaped was: what a
  /// drag's distance is measured from.
  Offset _cornerFrom = Offset.zero;

  /// _pressCorner rounds (or cuts) the corner at the point pressed, as far
  /// back as the corner size says; the drag that follows sets how far. While
  /// the corner it made is still picked, a press on it (either of its two
  /// points, or where the corner was) goes on shaping that one. Off any point
  /// it takes no press, and the press picks as the select tool's would.
  bool _pressCorner(VectorElement e, Offset doc, double reach) {
    var on = anyPointAt(e, doc, reach);
    if (controller.vectorCornerPoint case var was?) {
      var at = VectorSpace(e).toCanvas(was);
      if ((on != null && controller.vectorPicks.contains(on)) ||
          (doc - at).distance <= reach * 2) {
        controller.beginInteraction();
        _cornerFrom = at;
        _mode = _DragMode.vectorCorner;
        return true;
      }
    }
    if (on == null) return false;
    _mode = _DragMode.none;
    // On a corner already rounded (made before, or a rounded box's), that
    // corner is taken up to be reshaped, not rounded again.
    if (controller.adoptCorner(on)) {
      if (controller.vectorCornerPoint case var was?) {
        controller.beginInteraction();
        _cornerFrom = VectorSpace(e).toCanvas(was);
        _mode = _DragMode.vectorCorner;
      }
      return true;
    }
    var node = vectorNodeAt(e, on);
    if (node == null) return true;
    controller.beginInteraction();
    if (!controller.roundCorner(on, transient: true)) {
      controller.endInteraction();
      return true;
    }
    _cornerFrom = VectorSpace(e).toCanvas(node.point);
    _mode = _DragMode.vectorCorner;
    return true;
  }

  void _applyCorner(Offset doc) {
    controller.sizeCorner(
        math.max(0.5, (doc - _cornerFrom).distance).roundToDouble(),
        transient: true);
  }

  /// _pressCombine is a click with the Boolean tool: on a shape it picks that
  /// shape for combining, or unpicks it (the whole of a shape already
  /// combined, never a part). On empty space it unpicks them all; off the
  /// drawing it finishes the editing.
  void _pressCombine(VectorElement e, Offset doc, double reach) {
    _mode = _DragMode.none;
    var hit = shapeAt(e, doc, reach);
    if (hit >= 0) {
      controller.toggleCombining(groupOf(e, hit));
    } else if (_visualBounds(e).contains(doc)) {
      controller.clearCombining();
    } else {
      controller.editVector(null);
    }
  }

  /// _penCloses closes the run the pen is drawing, where the press is on its
  /// first point, returning whether it did.
  bool _penCloses(VectorElement e, Offset doc, double reach) {
    var from = controller.vectorPenFrom;
    var shapes = e.shapes ?? const <VectorShape>[];
    if (from == null ||
        from.shape >= shapes.length ||
        from.path >= shapes[from.shape].paths.length) {
      return false;
    }
    var run = shapes[from.shape].paths[from.path];
    var first = VectorSpace(e).toCanvas(run.nodes.first.point);
    if (run.closed ||
        run.nodes.length < 3 ||
        from.node != run.nodes.length - 1 ||
        (first - doc).distance > reach) {
      return false;
    }
    controller.replaceElement(withPenClosed(e, from));
    controller.finishPenShape();
    _mode = _DragMode.none;
    return true;
  }

  /// _penPut puts the pen's next point down at [doc], joined on from the point
  /// it last put down or took hold of, or starting a shape with none. The drag
  /// that follows pulls its handles out; the press and the drag are one undo
  /// step.
  void _penPut(VectorElement e, Offset doc) {
    var from = controller.vectorPenFrom;
    var shapes = e.shapes ?? const <VectorShape>[];
    if (from != null && vectorNodeAt(e, from) == null) from = null;
    var picked = controller.vectorShape;
    // A new shape is drawn like the shape picked, or, with none, in the
    // colours set for new shapes. See ColourPanel.
    var view = e.viewBox;
    var like = from == null && picked >= 0 && picked < shapes.length
        ? shapes[picked]
        : VectorShape(
            paths: const [],
            stroke: controller.vectorShapeLine ?? const Color(0xFF000000),
            strokeWidth: math.max(1.0, math.min(view.width, view.height) / 100),
            cap: StrokeCap.round,
            join: StrokeJoin.round);
    controller.beginInteraction();
    _vectorFrom = doc;
    var (next, pick) = withPenPoint(e, from, doc, like: like);
    controller.replaceElement(next, transient: true);
    controller.penFrom(pick);
    controller.pickVectorPoint(pick);
    _mode = _DragMode.vectorPen;
  }

  /// _widths is the points the scale tool is thickening or thinning the line
  /// at, each with its width when the drag began, or empty when it is scaling
  /// the whole drawing.
  Map<VectorPick, double> _widths = {};
  double _scaleReach = 0;
  bool _sweeping = false;
  bool _scaleLetsGo = false;

  /// _pressScale starts the line thickness tool: the line made thicker or
  /// thinner at the points picked (or, with none picked, the points nearest
  /// the press) and at every point the drag goes on to pass near.
  bool _pressScale(VectorElement e, Offset doc, double reach) {
    // Near enough to take in is wider than a point's own handle: a drag
    // sweeps across a line's points as a brush would.
    var near = math.max(reach, _thicknessReach / _scale);
    var picks = controller.vectorPicks;
    var hit = anyPointAt(e, doc, reach);
    // Shift and a click on a point adds it to the points picked, or takes
    // it out, as picking does.
    if (hit != null && _shiftHeld) {
      controller.pickVectorPoint(hit, toggle: true);
      _mode = _DragMode.none;
      return true;
    }
    Set<VectorPick> those;
    if (hit != null) {
      // On a point: all those picked if it is one of them; otherwise it,
      // picked now.
      if (!picks.contains(hit)) controller.pickVectorPoint(hit);
      those = controller.vectorPicks;
    } else if (picks.isNotEmpty) {
      those = picks;
    } else {
      // Nothing picked: the point nearest the press, if one is near.
      var nearest = anyPointAt(e, doc, near);
      those = nearest == null ? const {} : {nearest};
    }
    // Only a drag with nothing picked sweeps up the points it passes; with
    // points picked, it is theirs alone.
    _sweeping = hit == null && picks.isEmpty;
    // A click off every point, with points picked, lets them go (back to
    // sweeping). See _onPointerUp.
    _scaleLetsGo = hit == null && picks.isNotEmpty;
    _widths = {
      for (var p in joinedTo(e, those))
        if (vectorNodeAt(e, p) case var n?) p: n.width,
    };
    _scaleReach = near;
    _vectorBefore = e;
    _vectorFrom = doc;
    _mode = _DragMode.vectorScale;
    controller.beginInteraction();
    return true;
  }

  /// _applyScale scales by how far the pointer has gone: right or up larger,
  /// left or down smaller, doubling or halving every hundred and fifty pixels
  /// on screen, whatever the zoom.
  void _applyScale(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var moved = (doc - _vectorFrom) * _scale;
    var factor = math.pow(2, (moved.dx - moved.dy) / 150).toDouble();
    // Passed near, a point joins in from the width it had, so a sweep across
    // a line takes in all it crosses.
    for (var over in _sweeping
        ? pointsNear(before, doc, _scaleReach)
        : const <VectorPick>{}) {
      if (_widths.containsKey(over)) continue;
      for (var p in joinedTo(before, {over})) {
        _widths[p] = vectorNodeAt(before, p)?.width ?? 1;
      }
    }
    if (_widths.isEmpty) return;
    controller.replaceElement(withWidths(before, _widths, factor),
        transient: true);
  }

  /// _pressTint starts a stroke of the tint brush (an eraser's, with Alt
  /// held) anywhere over the drawing. Off it, it takes no press.
  bool _pressTint(VectorElement e, Offset doc) {
    controller.beginInteraction();
    _mode = _DragMode.vectorTint;
    // Off the drawing nothing is painted until the brush is dragged onto
    // it; let go without moving, it is a click off the drawing. Never a box:
    // the brush picks nothing.
    if (!_visualBounds(e).contains(doc)) {
      _tintWaiting = doc;
      return true;
    }
    _tintWaiting = null;
    _startTint(e, doc);
    return true;
  }

  /// _tintWaiting is a tint press off the drawing, not yet a stroke.
  Offset? _tintWaiting;

  /// _shade is what the brush stroke being painted is: a tint (nought), a
  /// shadow (below), or a highlight (above). See VectorTool.shadow.
  int get _shade => switch (controller.vectorTool) {
        VectorTool.shadow => -1,
        VectorTool.highlight => 1,
        _ => 0,
      };

  void _startTint(VectorElement e, Offset doc) {
    var space = VectorSpace(e);
    // The brush is a size on screen; in the drawing's units it is that over
    // how large a drawing unit is on screen.
    var unit =
        (space.toDrawing(doc + const Offset(1, 0)) - space.toDrawing(doc))
            .distance;
    _startStroke(
        e,
        doc,
        VectorTint(
          points: const [],
          paint: controller.vectorTint,
          width: controller.vectorBrushSize / _scale * unit,
          // Shading drawn on is cel shading: a hard edge, unless softened.
          soft: _shade != 0
              ? controller.vectorBrushSoft * 0.5
              : controller.vectorBrushSoft,
          line: controller.vectorTintLine,
          fill: controller.vectorTintFill,
          erase: HardwareKeyboard.instance.isAltPressed,
        ));
  }

  void _applyTint(Offset doc) {
    var e = controller.editingVector;
    if (e == null) return;
    if (_tintWaiting case var from?) {
      _tintWaiting = null;
      _startTint(e, from);
    }
    _carryStroke(doc);
  }

  /// _stroke is the tint stroke or rub-out being painted, _strokeOn the shapes
  /// it has gone over so far, and _strokeRubs whether it is a rub-out. Laid,
  /// each time it grows, on the drawing as it was when it began; see
  /// shapesUnder and withStrokeOn.
  VectorTint? _stroke;
  Set<int> _strokeOn = {};
  bool _strokeRubs = false;

  void _startStroke(VectorElement e, Offset doc, VectorTint like,
      {bool rubOut = false}) {
    var at = VectorSpace(e).toDrawing(doc);
    _vectorBefore = e;
    _strokeRubs = rubOut;
    _stroke = VectorTint(
        points: [at],
        paint: like.paint,
        width: like.width,
        soft: like.soft,
        line: like.line,
        fill: like.fill,
        erase: like.erase);
    _strokeOn = _onPicked(shapesUnder(e, at, like.width / 2));
    controller.replaceElement(
        withStrokeOn(e, _strokeOn, _stroke!,
            rubOut: rubOut, shade: rubOut ? 0 : _shade),
        transient: true);
  }

  /// _onPicked is [under] (the shapes a brush goes over) kept to the shapes
  /// picked, where any are, so a tint stays inside what is selected.
  Set<int> _onPicked(Set<int> under) {
    var picked = controller.vectorSelectedShapes;
    return picked.isEmpty ? under : under.intersection(picked);
  }

  void _carryStroke(Offset doc) {
    var before = _vectorBefore, stroke = _stroke;
    if (before == null || stroke == null) return;
    var at = VectorSpace(before).toDrawing(doc);
    // A move of less than a tenth of the brush's width adds nothing.
    if ((at - stroke.points.last).distance < stroke.width / 10) return;
    _stroke = stroke.withPoint(at);
    _strokeOn = {
      ..._strokeOn,
      ..._onPicked(shapesUnder(before, at, stroke.width / 2))
    };
    controller.replaceElement(
        withStrokeOn(before, _strokeOn, _stroke!,
            rubOut: _strokeRubs, shade: _strokeRubs ? 0 : _shade),
        transient: true);
  }

  /// _brushAt is where the tint brush's ring is drawn: the pointer, while
  /// the tint tool is out over a drawing being edited. Null hides it.
  Offset? _brushAt;

  void _moveBrush(Offset stage) {
    var on = controller.editingVector != null &&
        (controller.vectorTool == VectorTool.tint ||
            controller.vectorTool == VectorTool.shadow ||
            controller.vectorTool == VectorTool.highlight ||
            controller.vectorTool == VectorTool.pencil ||
            controller.vectorTool == VectorTool.eraser);
    var at = on ? stage : null;
    if (at != _brushAt) setState(() => _brushAt = at);
  }

  /// _brushRing is the tint brush's outline under the pointer: how wide a
  /// stroke will be, before it is painted.
  Widget? _brushRing() {
    var at = _brushAt;
    var pencil = controller.vectorTool == VectorTool.pencil &&
        !controller.vectorQuickFill;
    if (controller.vectorTool == VectorTool.pencil && !pencil) return null;
    var eraser = controller.vectorTool == VectorTool.eraser;
    if (at == null ||
        controller.editingVector == null ||
        (controller.vectorTool != VectorTool.tint &&
            controller.vectorTool != VectorTool.shadow &&
            controller.vectorTool != VectorTool.highlight &&
            !pencil &&
            !eraser)) {
      return null;
    }
    var d = math.max(
        4.0,
        pencil
            ? controller.vectorBrush.size
            : eraser
                ? controller.vectorEraseSize
                : controller.vectorBrushSize);
    return Positioned(
      left: at.dx - d / 2,
      top: at.dy - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xCCFFFFFF), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x99000000), spreadRadius: 0.5),
            ],
          ),
        ),
      ),
    );
  }

  /// _applyVectorMove drags the picked point of the drawing being edited, or
  /// one of its handles. Alt moves a smooth point's handle on its own, making
  /// the point a corner, as on a path.
  void _applyVectorMove(Offset doc) {
    var e = controller.editingVector, pick = controller.vectorPick;
    if (e == null || pick == null) return;
    controller.replaceElement(
        movedVector(e, pick, _vectorPart, doc,
            breakHandles: HardwareKeyboard.instance.isAltPressed,
            drag: controller.vectorHandleDrag,
            snap: controller.vectorHandleSnap || _shiftHeld),
        transient: true);
  }

  /// _applyNodeMove drags a point or one of its handles.
  void _applyNodeMove(Offset doc, {required bool handle}) {
    var path = _selectedPath();
    if (path == null || _nodeIndex < 0 || _nodeIndex >= path.nodes.length) {
      return;
    }
    var w = path.width == 0 ? 1.0 : path.width;
    var h = path.height == 0 ? 1.0 : path.height;
    var fraction = Offset((doc.dx - path.x) / w, (doc.dy - path.y) / h);
    var node = path.nodes[_nodeIndex];

    // Alt breaks the handle pair, which is how a corner is made; most of a
    // run is smooth, so held down is the exception.
    var next = handle
        ? (HardwareKeyboard.instance.isAltPressed
            ? (_nodeHandleOut
                ? node.copyWith(
                    outDx: fraction.dx - node.x, outDy: fraction.dy - node.y)
                : node.copyWith(
                    inDx: fraction.dx - node.x, inDy: fraction.dy - node.y))
            : node.withMirroredHandle(out: _nodeHandleOut, to: fraction))
        : node.copyWith(x: fraction.dx, y: fraction.dy);

    controller.replaceElement(path.withNode(_nodeIndex, next), transient: true);
  }

  /// _selectedPicture is the one selected element, when it is a picture with
  /// something in it.
  ImageElement? _selectedPicture() {
    var selected = controller.selected;
    return selected is ImageElement && selected.hasImage ? selected : null;
  }

  /// _paintStrokeAt adds a point to the live copy of the stroke being painted
  /// (committing is [_commitStroke], on pointer up). The point is stored in
  /// the picture's coordinates, so a stroke stays where it was painted when
  /// the element is resized, refitted or recropped; converting is
  /// ImagePlacement's job, the same mapping the painter draws through.
  void _paintStrokeAt(Offset doc, {bool start = false}) {
    var id = _painting;
    if (id == null) return;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return;

    var image = controller.images.original(picture.assetId);
    if (image == null) return;

    var inner = picture.box.inner(picture.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    var size = Size(image.width.toDouble(), image.height.toDouble());
    var placement = placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
    var at = placement.toImage(doc, size);
    // Off the picture: the part of a stroke past the edge touches nothing,
    // but the stroke goes on.
    if (at == null) return;

    if (start) {
      // The brush is a fraction of the picture's shorter side; the preview is
      // drawn in canvas units, so it is converted once here.
      var shorter = math.min(size.width, size.height);
      var scale = placement.scaleToImage();
      _liveRadius = controller.brushSize * shorter / (scale == 0 ? 1 : scale);
    }

    setState(() {
      _liveImage.add(at);
      _liveCanvas.add(doc);
    });
  }

  /// _layerReach is how near, in document units, a press has to be to a
  /// layer's handle to take hold of it.
  double get _layerReach => (handleSize / 2 + handleHitSlop) / _scale;

  /// _layerKnob is where the knob that turns [space]'s layer is: above the
  /// middle of its top, out along the way it faces.
  Offset _layerKnob(LayerSpace space) {
    var corners = space.corners;
    var top = (corners[0] + corners[1]) / 2;
    var middle = (corners[0] + corners[2]) / 2;
    var up = top - middle;
    var length = up.distance;
    var away = length == 0 ? const Offset(0, -1) : up / length;
    return top + away * (shapeTurnReach / _scale);
  }

  /// _layerBoxes is what the painter draws over a picture whose layers are
  /// open. See StageLayers.
  StageLayers? _layerBoxes() {
    var e = controller.editingImage;
    if (e == null) return null;
    if (controller.warpLayer case var id?) return _warpView(e, id);
    var picked = controller.pickedLayer;
    // With a brush in hand, its ring and, cloning, where it copies from.
    if (controller.imageTool.paints && picked != null) {
      var tool = controller.imageTool;
      var hover = _toDocument(_hoverAt);
      if (!tool.retouches) {
        var inner = e.box.inner(e.bounds);
        return StageLayers(ring: (
          hover,
          controller.paintSize * math.min(inner.width, inner.height)
        ));
      }
      var on = controller.retouchesFrame
          ? LayerPicture.frame(e, picked)
          : _maskPicture(e);
      if (on == null) return const StageLayers();
      Offset? marker;
      if (tool == ImageTool.clone && controller.cloneFrom != null) {
        var offset = controller.cloneOffset;
        marker = offset == null
            ? on.fromPicture(controller.cloneFrom!)
            : on.fromPicture(on.toPicture(hover) + offset);
      }
      return StageLayers(ring: (
        hover,
        controller.paintSize * on.shortSide * on.canvasPerPixel
      ), marker: marker);
    }
    // With a mask tool in hand the boxes are in the way: the picture, its
    // mask as shown, and the brush's ring.
    if (controller.imageTool.masks && picked != null) {
      var on = _maskPicture(e);
      if (controller.maskBusy == null && _mode != _DragMode.imageQuick) {
        _quickTrail = const [];
      }
      var brushes = controller.imageTool == ImageTool.brush ||
          controller.imageTool == ImageTool.quick ||
          controller.imageTool == ImageTool.refine;
      // A lasso being drawn: its outline, from the mark being made.
      List<Offset>? lasso;
      if (_mode == _DragMode.imageMask &&
          controller.imageTool == ImageTool.lasso &&
          on != null) {
        var mask = picked.framed ? picked.mask : lookOf(e, picked.id)?.mask;
        var last = mask?.marks.lastOrNull;
        if (last != null && last.kind == MaskMarkKind.lasso) {
          lasso = [for (var f in last.points) on.fromPicture(f)];
        }
      }
      return StageLayers(
        lasso: lasso,
        masking: (
          element: e,
          layer: picked.id,
          view: controller.maskView,
        ),
        trail: on == null || _quickTrail.isEmpty
            ? null
            : (
                [for (var f in _quickTrail) on.fromPicture(f)],
                controller.maskBrushSize * on.shortSide * on.canvasPerPixel,
                _quickSubtract,
              ),
        ring: brushes && on != null
            ? (
                _toDocument(_hoverAt),
                controller.maskBrushSize * on.shortSide * on.canvasPerPixel
              )
            : null,
      );
    }
    var also = controller.imageLayers.skip(1).toSet();
    var others = [
      for (var l in e.stack)
        if (l.kind == LayerKind.picture &&
            l.visible &&
            l.id != picked?.id &&
            !also.contains(l.id))
          LayerSpace(e, l).corners
    ];
    var chosen = [
      for (var l in e.stack)
        if (l.kind == LayerKind.picture && l.visible && also.contains(l.id))
          LayerSpace(e, l).corners
    ];
    // The base picture has a place of its own once there are layers round
    // it (see ImageLayer.basePlace) and is handled as a picture layer is,
    // without the knob: it turns with the element.
    var handled = picked != null &&
        (picked.kind == LayerKind.picture || (picked.isBase && e.layered));
    if (!handled) {
      var inner = e.box.inner(e.bounds);
      var space = LayerSpace(e, ImageLayer.base);
      return StageLayers(
          others: others,
          chosen: chosen,
          picked: [
            inner.topLeft,
            inner.topRight,
            inner.bottomRight,
            inner.bottomLeft
          ].map(space.fromFrame).toList());
    }
    var space = LayerSpace(e, picked);
    // Locked, it is outlined but has nothing to take hold of.
    var held = controller.layerLocked(picked);
    return StageLayers(
      others: others,
      chosen: chosen,
      picked: space.corners,
      handles: held
          ? const []
          : [for (var h in boxHandles(space.rect)) space.fromLayer(h)],
      knob: picked.isBase || held ? null : _layerKnob(space),
    );
  }

  // ---- warp grid ------------------------------------------------------

  /// _warpSpace is how the warp grid of the layer [id] of [e] lies on the
  /// canvas: a fraction of the picture's box to a point on the canvas, and
  /// back, through the element's turn and slant, the layer's turn, and its
  /// mirror.
  (Offset Function(Offset), Offset Function(Offset)) _warpSpace(
      ImageElement e, String id) {
    var layer = e.layerById(id) ?? ImageLayer.base;
    var space = LayerSpace(e, layer);
    var r = space.rect;
    Offset mirror(Offset f) =>
        Offset(layer.flipX ? 1 - f.dx : f.dx, layer.flipY ? 1 - f.dy : f.dy);
    Offset toDoc(Offset f) {
      var m = mirror(f);
      return space
          .fromLayer(r.topLeft + Offset(m.dx * r.width, m.dy * r.height));
    }

    Offset toFrac(Offset doc) {
      var l = space.toLayer(doc) - r.topLeft;
      return mirror(Offset(
          l.dx / math.max(1e-9, r.width), l.dy / math.max(1e-9, r.height)));
    }

    return (toDoc, toFrac);
  }

  /// _warpPoints is the warp grid's points on the canvas.
  List<Offset> _warpPoints(ImageElement e, String id) {
    var (toDoc, _) = _warpSpace(e, id);
    return [for (var f in controller.warpOf(e, id).grid) toDoc(f)];
  }

  /// _warpBox is the box round the picked points, on the canvas, with its
  /// knob, for two or more picked.
  (Rect, Offset)? _warpBox(List<Offset> points) {
    var picks = controller.warpPicks;
    if (picks.length < 2) return null;
    var picked = [
      for (var k in picks)
        if (k < points.length) points[k]
    ];
    if (picked.length < 2) return null;
    var box = Rect.fromLTRB(
        picked.map((p) => p.dx).reduce(math.min),
        picked.map((p) => p.dy).reduce(math.min),
        picked.map((p) => p.dx).reduce(math.max),
        picked.map((p) => p.dy).reduce(math.max));
    // Room round points in a line, so the box has corners to hold.
    var least = 12 / _scale;
    if (box.width < least || box.height < least) {
      box = Rect.fromCenter(
          center: box.center,
          width: math.max(box.width, least),
          height: math.max(box.height, least));
    }
    return (box, box.topCenter - Offset(0, 24 / _scale));
  }

  /// _warpView is the warp grid as the stage draws it.
  StageLayers _warpView(ImageElement e, String id) {
    var warp = controller.warpOf(e, id);
    var (toDoc, _) = _warpSpace(e, id);
    var g = warp.grid;
    var points = [for (var f in g) toDoc(f)];
    const fine = 12;
    var lines = <List<Offset>>[
      for (var i = 0; i <= warp.rows; i++)
        [
          for (var k = 0; k <= warp.cols * fine; k++)
            toDoc(warp.sample(k / (warp.cols * fine), i / warp.rows, g))
        ],
      for (var j = 0; j <= warp.cols; j++)
        [
          for (var k = 0; k <= warp.rows * fine; k++)
            toDoc(warp.sample(j / warp.cols, k / (warp.rows * fine), g))
        ],
    ];
    var box = _warpBox(points);
    return StageLayers(
        warp: StageWarp(
            lines: lines,
            points: points,
            picks: controller.warpPicks,
            box: box == null
                ? null
                : [
                    box.$1.topLeft,
                    box.$1.topRight,
                    box.$1.bottomRight,
                    box.$1.bottomLeft
                  ],
            knob: box?.$2));
  }

  List<Offset> _warpStartPoints = const [];
  Offset _warpPivot = Offset.zero;
  Offset _warpGrab = Offset.zero;

  /// _pressWarp is a press while a warp grid is shown: on the box's knob
  /// or a corner, to turn or size the points picked; on a point, to pick it
  /// (Shift adds it or takes it away) and drag; inside the box, to drag the
  /// lot; anywhere else, a box dragged out to pick points with.
  bool _pressWarp(ImageElement e, String id, Offset doc) {
    var points = _warpPoints(e, id);
    var reach = 10 / _scale;
    var shift = _shiftHeld;
    void hold(_DragMode mode) {
      _mode = mode;
      _warpStartPoints = [...controller.warpOf(e, id).grid];
      _warpGrab = doc;
      controller.beginInteraction();
    }

    if (_warpBox(points) case (var box, var knob)) {
      if ((doc - knob).distance <= reach) {
        _warpPivot = box.center;
        hold(_DragMode.warpTurn);
        return true;
      }
      for (var c in [
        box.topLeft,
        box.topRight,
        box.bottomLeft,
        box.bottomRight
      ]) {
        if ((doc - c).distance <= reach) {
          _warpPivot = box.center;
          hold(_DragMode.warpScale);
          return true;
        }
      }
    }
    var nearest = -1;
    var best = reach;
    for (var (k, p) in points.indexed) {
      var d = (p - doc).distance;
      if (d <= best) {
        best = d;
        nearest = k;
      }
    }
    if (nearest >= 0) {
      var picks = {...controller.warpPicks};
      if (shift) {
        picks.contains(nearest) ? picks.remove(nearest) : picks.add(nearest);
        controller.warpPicks = picks;
        _mode = _DragMode.none;
        return true;
      }
      if (!picks.contains(nearest)) controller.warpPicks = {nearest};
      hold(_DragMode.warpMove);
      return true;
    }
    if (_warpBox(points) case (var box, _) when box.contains(doc)) {
      hold(_DragMode.warpMove);
      return true;
    }
    if (!shift) controller.warpPicks = const {};
    _mode = _DragMode.warpMarquee;
    _warpGrab = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    return true;
  }

  /// _dragWarp carries the picked points to [doc]: moved by the drag, sized
  /// about the middle of their box by how much further from it the pointer
  /// is, or turned about it.
  void _dragWarp(Offset doc) {
    var e = controller.editingImage, id = controller.warpLayer;
    if (e == null || id == null) return;
    if (_mode == _DragMode.warpMarquee) {
      setState(() => _marquee = Rect.fromPoints(_warpGrab, doc));
      return;
    }
    var (toDoc, toFrac) = _warpSpace(e, id);
    var start = [for (var f in _warpStartPoints) toDoc(f)];
    Offset carried(Offset p) {
      switch (_mode) {
        case _DragMode.warpMove:
          return p + (doc - _warpGrab);
        case _DragMode.warpScale:
          var from = (_warpGrab - _warpPivot).distance;
          var k = from < 1e-9 ? 1.0 : (doc - _warpPivot).distance / from;
          return _warpPivot + (p - _warpPivot) * k;
        case _DragMode.warpTurn:
          var a =
              (doc - _warpPivot).direction - (_warpGrab - _warpPivot).direction;
          if (_shiftHeld) a = (a / (math.pi / 12)).round() * (math.pi / 12);
          var d = p - _warpPivot;
          return _warpPivot +
              Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
                  d.dx * math.sin(a) + d.dy * math.cos(a));
        default:
          return p;
      }
    }

    var picks = controller.warpPicks;
    controller.changeWarp(
        (w) => w.withPoints([
              for (var (k, f) in _warpStartPoints.indexed)
                picks.contains(k) ? toFrac(carried(start[k])) : f
            ]),
        transient: true);
  }

  /// _finishWarpMarquee picks the points inside the box dragged out.
  void _finishWarpMarquee() {
    var box = _marquee;
    var e = controller.editingImage, id = controller.warpLayer;
    setState(() => _marquee = null);
    if (box == null || e == null || id == null) return;
    var picks = {...controller.warpPicks};
    for (var (k, p) in _warpPoints(e, id).indexed) {
      if (box.contains(p)) picks.add(k);
    }
    controller.warpPicks = picks;
  }

  /// _nudgeWarp moves the picked points by [by], in canvas units.
  bool _nudgeWarp(Offset by) {
    var e = controller.editingImage, id = controller.warpLayer;
    if (e == null || id == null || controller.warpPicks.isEmpty) return false;
    var (toDoc, toFrac) = _warpSpace(e, id);
    var picks = controller.warpPicks;
    controller.changeWarp((w) => w.withPoints([
          for (var (k, f) in w.grid.indexed)
            picks.contains(k) ? toFrac(toDoc(f) + by) : f
        ]));
    return true;
  }

  /// _pressLayers is a press at [doc] on [e] while its layers are open: the
  /// picked layer's knob or handles, then whichever picture layer is on top
  /// under the press, then the base picture. False when the press missed the
  /// picture altogether, which closes it.
  bool _pressLayers(ImageElement e, Offset doc) {
    if (controller.warpLayer case var id?) return _pressWarp(e, id, doc);
    var picked = controller.pickedLayer;
    // A locked layer is not drawn on, masked or moved here. The press is
    // still the picture's, so it stays open.
    if (picked != null &&
        controller.layerLocked(picked) &&
        (controller.imageTool.masks || controller.imageTool.paints)) {
      controller.noteForBrush(controller.imageSolo
          ? "Another layer is soloed: pick this one, or turn Solo off."
          : "This layer is locked: unlock it in the layers list to work on "
              "it.");
      _mode = _DragMode.none;
      return true;
    }
    if (controller.imageTool.masks) return _pressMask(e, doc);
    if (controller.imageTool.paints) return _pressBrush(e, doc);
    if (picked != null &&
        (picked.kind == LayerKind.picture || (picked.isBase && e.layered)) &&
        picked.visible &&
        !controller.layerLocked(picked)) {
      var space = LayerSpace(e, picked);
      if (!picked.isBase && (doc - _layerKnob(space)).distance <= _layerReach) {
        return _holdLayer(picked, _DragMode.imageLayerTurn, -1);
      }
      for (var (i, h) in boxHandles(space.rect).indexed) {
        if ((doc - space.fromLayer(h)).distance <= _layerReach) {
          return _holdLayer(picked, _DragMode.imageLayerSize, i);
        }
      }
    }
    var under = layerAt(e, doc, locked: controller.layerLocked);
    if (!under.isBase) {
      // Shift or Command picks it as well, or lets it go again; a press on
      // one already picked keeps the others, so they move together.
      if (_shiftHeld || HardwareKeyboard.instance.isMetaPressed) {
        controller.pickImageLayer(under.id, add: true);
        if (!controller.imageLayers.contains(under.id)) {
          _mode = _DragMode.none;
          return true;
        }
      } else if (!controller.imageLayers.contains(under.id)) {
        controller.pickImageLayer(under.id);
      }
      return _holdLayer(under, _DragMode.imageLayerMove, -1);
    }
    if (!_containsPoint(e, doc)) return false;
    // Locked, the base picture is not picked or moved: the press only keeps
    // the picture open.
    if (controller.layerLocked(under)) {
      _mode = _DragMode.none;
      return true;
    }
    controller.pickImageLayer(baseLayerId);
    // With layers round it, the base picture is moved about the frame as a
    // picture layer is, where it is pressed.
    if (e.layered) {
      var base = e.layerById(baseLayerId)!;
      if (LayerSpace(e, base).contains(doc)) {
        return _holdLayer(base, _DragMode.imageLayerMove, -1);
      }
      _mode = _DragMode.none;
      return true;
    }
    // The base picture always fills its frame, so moving it is moving it
    // about inside the frame, which only a picture filling the frame has
    // room to do. See ImageFraming.
    if (e.hasImage && e.fit == ImageFit.cover) {
      _framingStart = e.framing;
      _mode = _DragMode.imageFrame;
      controller.beginInteraction();
    } else {
      _mode = _DragMode.none;
    }
    return true;
  }

  /// _maskPicture is where the picked layer of [e] draws its picture, once
  /// the picture has loaded.
  LayerPicture? _maskPicture(ImageElement e) {
    var picked = controller.pickedLayer;
    if (picked != null && picked.framed) return LayerPicture.frame(e, picked);
    var look = lookOf(e, controller.imageLayer);
    if (look == null || !look.hasImage) return null;
    var image = controller.images.original(look.assetId);
    if (image == null) return null;
    return LayerPicture.of(e, controller.imageLayer,
        Size(image.width.toDouble(), image.height.toDouble()));
  }

  /// _pressMask is a press with a mask tool in hand: a click for a subject,
  /// or the start of a mark. Anywhere on the picture, or near enough to it
  /// that a stroke can start off its edge; further off, it misses.
  bool _pressMask(ImageElement e, Offset doc) {
    var on = _maskPicture(e);
    if (on == null) return _containsPoint(e, doc);
    var f = on.toPicture(doc);
    bool within(double v) => v >= 0 && v <= 1;
    var inside = within(f.dx) && within(f.dy);
    if (!inside && !_containsPoint(e, doc)) return false;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var hide = controller.maskHide != alt;
    // The tools that look at a picture's pixels have none to look at on an
    // adjustment, a texture, a colour or paint.
    if ((controller.pickedLayer?.framed ?? false) &&
        (controller.imageTool == ImageTool.subject ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine)) {
      _mode = _DragMode.none;
      controller.noteForBrush("${controller.imageTool.label} looks for a "
          "subject in a picture. On this layer, mask with the brush, the "
          "lasso or a gradient.");
      return true;
    }
    MaskMark mark;
    switch (controller.imageTool) {
      case ImageTool.subject:
        _mode = _DragMode.none;
        if (inside) {
          unawaited(controller.findSubject(
              at: f,
              how: _shiftHeld
                  ? MaskCombine.add
                  : alt
                      ? MaskCombine.subtract
                      : MaskCombine.replace));
        }
        return true;
      case ImageTool.quick || ImageTool.refine:
        _maskOn = on;
        _quickTrail = [f];
        _quickSubtract = alt;
        _mode = _DragMode.imageQuick;
        setState(() {});
        return true;
      case ImageTool.brush:
        var pressure = _penSample(doc).pressure;
        mark = MaskMark(
            kind: MaskMarkKind.brush,
            points: [f],
            pressure: pressure == null ? const [] : [pressure],
            radius: controller.maskBrushSize,
            hardness: controller.maskHardness,
            strength: controller.maskStrength,
            hide: hide);
      case ImageTool.lasso:
        mark = MaskMark(kind: MaskMarkKind.lasso, points: [f], hide: hide);
      case ImageTool.fade:
        mark = MaskMark(
            kind: MaskMarkKind.fade,
            points: [f, f],
            radial: controller.maskRadial,
            strength: controller.maskStrength,
            hide: hide);
      default:
        return false;
    }
    _maskOn = on;
    _mode = _DragMode.imageMask;
    controller.beginInteraction();
    controller.changeMask((m) => m.withMark(mark).copyWith(on: true),
        transient: true);
    return true;
  }

  /// _dragMask carries the mark being made to [doc].
  void _dragMask(Offset doc) {
    var on = _maskOn;
    if (on == null) return;
    var f = on.toPicture(doc);
    var pressure = _penSample(doc).pressure;
    controller.changeMask((m) {
      if (m.marks.isEmpty) return m;
      var last = m.marks.last;
      if (last.kind == MaskMarkKind.fade) {
        return m.withLastMark(last.copyWith(points: [last.points.first, f]));
      }
      // Not every pixel of the drag: a point every half a picture pixel or so
      // is all a stroke can show, and a stroke is kept in the document.
      var was = last.points.last;
      var gap = Offset(
          (f.dx - was.dx) * on.size.width, (f.dy - was.dy) * on.size.height);
      if (gap.distance < 0.75) return m;
      return m.withLastMark(last.copyWith(
          points: [...last.points, f],
          pressure: last.pressure.isEmpty || pressure == null
              ? last.pressure
              : [...last.pressure, pressure]));
    }, transient: true);
  }

  /// _frameFraction is [doc] as a fraction of [e]'s frame, across and down.
  Offset _frameFraction(ImageElement e, Offset doc) {
    var space = LayerSpace(e, ImageLayer.base);
    var p = space.toFrame(doc) - space.inner.topLeft;
    return Offset(p.dx / math.max(1e-9, space.inner.width),
        p.dy / math.max(1e-9, space.inner.height));
  }

  /// _pressBrush is a press with a paint or retouching brush in hand: the
  /// start of a stroke, or, with the clone tool and Option, the choosing of
  /// where to copy from.
  bool _pressBrush(ImageElement e, Offset doc) {
    var tool = controller.imageTool;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var pressure = _penSample(doc).pressure;
    if (!tool.retouches) {
      // Anywhere at all on a picture that does not clip: the frame grows to
      // take the paint in. One that clips paints only inside itself.
      if (e.clip && !_containsPoint(e, doc)) return false;
      controller.beginInteraction();
      // Paint goes on a paint layer: one is made over the layer picked, where
      // that is not one already, in the same step as the stroke.
      if (controller.pickedLayer?.kind != LayerKind.paint) {
        controller.addImageLayer(ImageLayer.painting());
      }
      var f = _frameFraction(controller.editingImage!, doc);
      var mark = StrokeMark(
          kind: tool == ImageTool.erase || alt
              ? StrokeKind.erase
              : StrokeKind.paint,
          points: [f],
          pressure: pressure == null ? const [] : [pressure],
          radius: controller.paintSize,
          hardness: controller.paintHardness,
          strength: controller.paintStrength,
          colour: controller.paintColour,
          tip: controller.paintTip,
          tilt: [if (_penLean() case var lean?) lean]);
      controller.changePaint((s) => [...s, mark], transient: true);
      _strokeAt = (doc) => _frameFraction(controller.editingImage!, doc);
      _mode = _DragMode.imageBrush;
      return true;
    }
    // Across the whole frame, the strokes are a paint layer's, in fractions
    // of the frame; on one picture, that picture's, in fractions of it.
    var whole = controller.retouchesFrame;
    var on = whole
        ? LayerPicture.frame(e, controller.pickedLayer ?? ImageLayer.base)
        : _maskPicture(e);
    if (on == null) return _containsPoint(e, doc);
    var f = on.toPicture(doc);
    bool within(double v) => v >= 0 && v <= 1;
    if (!(whole && !e.clip) &&
        !(within(f.dx) && within(f.dy)) &&
        !_containsPoint(e, doc)) {
      return false;
    }
    var source = Offset.zero;
    if (tool == ImageTool.clone) {
      _mode = _DragMode.none;
      if (alt) {
        controller.cloneFrom = f;
        return true;
      }
      var from = controller.cloneFrom;
      if (from == null) {
        controller.noteForBrush(
            "Option-click first, on what to copy from -- then paint where it "
            "is to go.");
        return true;
      }
      source = controller.cloneOffset ??= from - f;
    }
    // A heal takes its texture from beside where it starts: see healSource.
    if (tool == ImageTool.heal) {
      source = healSource(f, controller.paintSize, on.size);
    }
    var mark = StrokeMark(
        kind: switch (tool) {
          ImageTool.clone => StrokeKind.clone,
          ImageTool.heal => StrokeKind.heal,
          ImageTool.dodge =>
            controller.burning != alt ? StrokeKind.burn : StrokeKind.dodge,
          ImageTool.sharpen => StrokeKind.sharpen,
          ImageTool.smudge => StrokeKind.smudge,
          _ => StrokeKind.blur,
        },
        points: [f],
        pressure: pressure == null ? const [] : [pressure],
        radius: controller.paintSize,
        hardness: controller.paintHardness,
        strength: controller.paintStrength,
        source: source);
    controller.beginInteraction();
    if (whole) {
      // A layer of its own, at the top of the picture, in the same step as the
      // stroke, unless a paint layer is picked already. See
      // CanvasController.retouchLayerForFrame.
      controller.retouchLayerForFrame();
      controller.changePaint((s) => [...s, mark], transient: true);
    } else {
      controller.changeRetouch((s) => [...s, mark], transient: true);
    }
    // Across the whole frame, measured in the frame as it is at each step:
    // it grows as the stroke goes past it.
    _strokeAt = whole
        ? (doc) => _frameFraction(controller.editingImage!, doc)
        : on.toPicture;
    _mode = _DragMode.imageBrush;
    return true;
  }

  /// _dragBrush carries the stroke being drawn to [doc].
  void _dragBrush(Offset doc) {
    var at = _strokeAt;
    if (at == null) return;
    var f = at(doc);
    var pressure = _penSample(doc).pressure;
    var lean = _penLean();
    List<StrokeMark> grown(List<StrokeMark> strokes) {
      if (strokes.isEmpty) return strokes;
      var last = strokes.last;
      if ((f - last.points.last).distance < 0.0005) return strokes;
      return [
        ...strokes.sublist(0, strokes.length - 1),
        last.copyWith(
            points: [...last.points, f],
            pressure: last.pressure.isEmpty || pressure == null
                ? last.pressure
                : [...last.pressure, pressure],
            tilt: last.tilt.isEmpty || lean == null
                ? last.tilt
                : [...last.tilt, lean]),
      ];
    }

    if (controller.imageTool.retouches &&
        controller.pickedLayer?.kind != LayerKind.paint) {
      controller.changeRetouch(grown, transient: true);
    } else {
      controller.changePaint(grown, transient: true);
    }
  }

  bool _holdLayer(ImageLayer layer, _DragMode mode, int handle) {
    _layerStart = layer;
    // A move carries every picked picture layer with the one held.
    _layersMoved = mode == _DragMode.imageLayerMove
        ? [
            for (var l in controller.pickedLayers)
              if (l.kind == LayerKind.picture &&
                  l.id != layer.id &&
                  !controller.layerLocked(l))
                l
          ]
        : const [];
    _layerHandle = handle;
    _mode = mode;
    controller.beginInteraction();
    return true;
  }

  /// _dragLayer carries the picture layer held to where the pointer is.
  void _dragLayer(Offset doc) {
    var e = controller.editingImage, was = _layerStart;
    if (e == null || was == null) return;
    var start = e.withLayer(was.id, (_) => was);
    var space = LayerSpace(start, was);
    var carried = e;
    ImageLayer next;
    switch (_mode) {
      case _DragMode.imageLayerMove:
        // The travel in the frame's own unturned space, so a turned picture
        // still moves the way the pointer does.
        var travel = space.toFrame(doc) - space.toFrame(_dragStart);
        var rect = space.rect.shift(travel);
        next = was.placed(layerPlace(space.inner, rect), turn: was.turn);
        // And the others picked with it, the same distance.
        for (var other in _layersMoved) {
          var at = layerRect(space.inner, other.place).shift(travel);
          carried = carried.withLayer(
              other.id,
              (_) =>
                  other.placed(layerPlace(space.inner, at), turn: other.turn));
        }
      case _DragMode.imageLayerSize:
        // The corners keep the picture's proportions where it holds them (Keep
        // its proportions), and Shift does the other.
        var holds = (was.look ?? e).base.lockAspect;
        var even = _layerHandle < 4 && (holds ? !_shiftHeld : _shiftHeld);
        var rect = space.resized(doc, _layerHandle,
            (r, h, p) => boxResized(r, h, p, even: even, least: 4));
        next = was.placed(layerPlace(space.inner, rect), turn: was.turn);
      case _DragMode.imageLayerTurn:
        var turn = space.turnTo(doc);
        if (_shiftHeld) turn = (turn / 15).round() * 15.0;
        turn = ((turn + 180) % 360) - 180;
        next = was.placed(was.place, turn: turn);
      default:
        return;
    }
    controller.changeImage(carried.withLayer(was.id, (_) => next),
        transient: true);
  }

  /// _framedPicture is the element being reframed and the picture in it,
  /// when both are there to be had.
  (ImageElement, ui.Image)? _framedPicture() {
    var id = _framing;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! ImageElement) return null;
    var image = controller.images.original(element.assetId);
    return image == null ? null : (element, image);
  }

  /// _framingPlacement is where the picture is drawn right now, asked of the
  /// same code that draws it.
  ImagePlacement? _framingPlacement(ImageElement e, ui.Image image) {
    var inner = _framingRect(e);
    if (inner.width <= 0 || inner.height <= 0) return null;
    return placeImage(
        Size(image.width.toDouble(), image.height.toDouble()), inner, e.fit,
        crop: e.crop, framing: e.framing);
  }

  /// _framingRect is where the picture being reframed is drawn: its frame,
  /// or, with layers round it, its own place in the frame, which is no longer
  /// the whole once the frame has grown round a layer or a stroke.
  Rect _framingRect(ImageElement e) {
    var inner = e.box.inner(e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    if (!e.layered) return inner;
    var base =
        e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
    return layerRect(inner, base.place);
  }

  /// _framingView is what the painter draws over a picture being reframed:
  /// the whole of it, in the place the visible part is already in.
  StageFraming? _framingView() {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null || placement.src.width <= 0) return null;

      var base =
          e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
      return StageFraming(image, placement.whole, placement.wholeDst,
          _framingRect(e), e.movedRotationAt(controller.frame, controller.document,
            live: controller.liveMotion) * math.pi / 180,
          pivot: e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion).center,
          flipX: base.flipX,
          flipY: base.flipY);
    }
    return null;
  }

  /// _startGuideDrag takes hold of a guide, or pulls a new one out of a ruler,
  /// returning whether it did. A press inside a ruler always means a new
  /// guide; a press near a line means that line, unless the guides are locked
  /// or hidden.
  bool _startGuideDrag(Offset stage, Offset doc) {
    var guides = document.guides;
    if (!guides.showGuides) return false;

    // Out of a ruler: pulling down from the top gives a horizontal line,
    // out of the left a vertical one.
    var from = _rulerUnder(stage);
    if (from != null) {
      var axis = from == GuideAxis.vertical
          ? GuideAxis.vertical
          : GuideAxis.horizontal;
      var at = axis == GuideAxis.vertical ? doc.dx : doc.dy;
      controller.beginInteraction();
      var next = guides.withGuide(CanvasGuide(axis: axis, at: at));
      _guideIndex = next.guides.length - 1;
      _mode = _DragMode.guide;
      controller.apply(document.copyWith(guides: next), transient: true);
      return true;
    }

    if (guides.lockGuides) return false;
    var reach = guideGrabSlop / _scale;
    for (var (i, guide) in guides.guides.indexed) {
      var gap = guide.axis == GuideAxis.vertical
          ? (doc.dx - guide.at).abs()
          : (doc.dy - guide.at).abs();
      if (gap > reach) continue;
      _guideIndex = i;
      _mode = _DragMode.guide;
      controller.beginInteraction();
      return true;
    }
    return false;
  }

  /// _rulerUnder is which ruler the pointer is in, as the axis of the guide
  /// it would produce, or null. The strips come from the function that draws
  /// them, so what can be dragged out of is what is seen.
  GuideAxis? _rulerUnder(Offset stage) {
    if (!document.guides.showRulers) return null;
    var rulers = document.guides.rulers;
    if (!rulers.any) return null;
    // The strips are at the window's edges, the page scrolled under them.
    return rulerBandsFor(_pageRect.shift(-_scrolled), _visible, rulers)
        .axisAt(stage - _scrolled);
  }

  /// _applyGuide moves the guide being dragged to where the pointer is,
  /// snapped to the grid like anything else so it can sit exactly on a
  /// gridline.
  void _applyGuide(Offset doc) {
    var guides = document.guides;
    if (_guideIndex < 0 || _guideIndex >= guides.guides.length) return;
    var guide = guides.guides[_guideIndex];

    var at = guide.axis == GuideAxis.vertical ? doc.dx : doc.dy;
    if (!HardwareKeyboard.instance.isAltPressed) {
      var line = snapEdgeTo(
        at,
        guides,
        document.size.size,
        vertical: guide.axis == GuideAxis.vertical,
        within: guides.snapWithin / _scale,
      );
      if (line != null) at = line;
    }

    controller.apply(
        document.copyWith(guides: guides.movedGuide(_guideIndex, at)),
        transient: true);
  }

  /// _finishGuide drops the guide, or throws it away if it was dragged off
  /// the canvas, which is how a single guide is removed.
  void _finishGuide() {
    var guides = document.guides;
    if (_guideIndex < 0 || _guideIndex >= guides.guides.length) {
      _guideIndex = -1;
      return;
    }
    var guide = guides.guides[_guideIndex];
    var page = document.size.size;
    var off = guide.axis == GuideAxis.vertical
        ? guide.at < 0 || guide.at > page.width
        : guide.at < 0 || guide.at > page.height;

    if (off) {
      controller
          .apply(document.copyWith(guides: guides.withoutGuide(_guideIndex)));
    }
    _guideIndex = -1;
  }

  /// _applyFraming moves the picture inside its frame by however far the
  /// pointer has come since it went down. The travel is in canvas units and
  /// the framing in fractions of the slack, so it is converted through the
  /// placement, and the picture follows the pointer at any zoom. Dragging
  /// right moves the picture right: the window chooses pixels further left.
  void _applyFraming(Offset doc) {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null) return;
      // Canvas units per picture pixel, from what is drawn and where: the
      // window is the picture before the crop, and the drawn part after it.
      var perPixel = placement.src.width <= 0
          ? 0.0
          : placement.dst.width / placement.src.width;
      if (perPixel <= 0) return;
      var slack = placement.slack;

      // Undone by the element's own rotation, so a tilted picture moves the
      // way the pointer does.
      var travel = doc - _dragStart;
      var a = -e.movedRotationAt(controller.frame, controller.document,
            live: controller.liveMotion) * math.pi / 180;
      if (a != 0) {
        travel = Offset(travel.dx * math.cos(a) - travel.dy * math.sin(a),
            travel.dx * math.sin(a) + travel.dy * math.cos(a));
      }
      // And by its mirror: a picture flipped across moves the other way
      // inside its frame for the same drag.
      var base =
          e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
      travel = Offset(base.flipX ? -travel.dx : travel.dx,
          base.flipY ? -travel.dy : travel.dy);

      controller.replaceElement(
          e.copyWith(
              framing: e.framing.copyWith(
            x: slack.dx <= 0
                ? _framingStart.x
                : _framingStart.x - travel.dx / perPixel / slack.dx,
            y: slack.dy <= 0
                ? _framingStart.y
                : _framingStart.y - travel.dy / perPixel / slack.dy,
          )),
          transient: true);
    }
  }

  /// _previewPlacement is where the held stroke's preview goes on the canvas:
  /// over its picture, through the same placement the picture is drawn with.
  ImagePlacement? _previewPlacement() {
    var id = controller.pendingPicture;
    if (id == null || _preview == null) return null;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return null;
    var inner = picture.box.inner(picture.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    var size = Size(_preview!.width.toDouble(), _preview!.height.toDouble());
    return placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
  }

  /// _refreshPreview rebuilds the picture of what the held stroke would do,
  /// when the stroke or the settings behind it have changed, keyed on the
  /// settings rather than on every notification.
  void _refreshPreview() {
    var stroke = controller.pendingAsStroke();
    var id = controller.pendingPicture;
    if (stroke == null || id == null) {
      if (_preview != null || _previewOf != null) {
        setState(() {
          _preview = null;
          _previewOf = null;
        });
      }
      return;
    }

    var picture = document.elementById(id);
    if (picture is! ImageElement) return;
    var source = controller.images.original(picture.assetId);
    if (source == null) return;

    var key = "$id|${stroke.points.length}|${stroke.radius}|"
        "${stroke.hardness}|${stroke.snap}|${stroke.keep}|"
        "${stroke.fill}|${stroke.fillInside}";
    if (key == _previewOf) return;
    _previewOf = key;

    // After the settings have stopped moving. There is no telling a
    // keystroke from the last one except by waiting, so the stroke goes
    // through the same delay.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(_previewDelay, () {
      if (!mounted || _previewOf != key) return;
      // The preview colours itself by how hard the brush is at each pixel,
      // which is the thing being judged.
      strokePreview(source, stroke).then((image) {
        if (!mounted || _previewOf != key) return;
        setState(() => _preview = image);
      });
    });
  }

  /// _commitStroke writes the finished stroke onto the picture, as one change
  /// for the whole gesture: one pass over the pixels, one undo step.
  void _commitStroke() {
    var id = _painting;
    _painting = null;
    var points = [..._liveImage];
    setState(() {
      _liveImage.clear();
      _liveCanvas.clear();
    });

    var picture = id == null ? null : document.elementById(id);
    if (picture is! ImageElement || points.isEmpty) {
      controller.endInteraction();
      return;
    }

    // A marking brush teaches the learning method what is what; the other
    // two rub the picture out and put it back. Which it is is kept with the
    // stroke, since another brush may be picked before it is applied.
    var teaching = controller.retouch.teaches;

    // Held rather than applied, so the brush can be adjusted while the same
    // stroke redraws: see CanvasController.holdStroke.
    controller.holdStroke(picture.id, points,
        keeps: controller.retouch.keeps,
        teaches: teaching,
        fills: controller.retouch.fills);
    controller.endInteraction();
  }

  /// _selectedTeam is the one selected element, when it is a team.
  TeamElement? _selectedTeam() {
    var selected = controller.selected;
    return selected is TeamElement ? selected : null;
  }

  /// _hitAnyPlayer is the topmost player of any team under [doc], in reverse
  /// paint order. It ignores the teams' boxes: a player is placed as a
  /// fraction of one but not confined to it, and two teams on one pitch
  /// overlap.
  (TeamElement, int)? _hitAnyPlayer(Offset doc) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var element = document.elements[i];
      if (element is! TeamElement || element.locked || !element.visible) {
        continue;
      }
      var index = _hitPlayer(element, doc);
      if (index != null) return (element, index);
    }
    return null;
  }

  /// _hitPlayer is which of [team]'s players is under [doc], or null,
  /// searched back to front so the one drawn on top is picked. A locked
  /// player is not hittable, so a run can be dragged through a pinned back
  /// four.
  int? _hitPlayer(TeamElement team, Offset doc) {
    var rx = team.dotWidth / 2;
    var ry = team.dotHeight / 2;
    if (rx <= 0 || ry <= 0) return null;
    var ground = teamGround(document, team, controller.frame);

    for (var i = team.players.length - 1; i >= 0; i--) {
      var spot = team.players[i];
      if (spot.locked || spot.hidden) continue;
      // Where they are on this frame, not where they rest, and on a pitch,
      // where the pitch has put them, at the size it has made them.
      var at = playerPlace(ground, team, spot, controller.frame);
      if (!at.shown) continue;
      var d = doc - at.centre;
      // The ball by its own size, which is smaller than a player's.
      var own = spot.ball ? team.radiusOf(spot) : null;
      var sx = (own ?? rx) * at.size, sy = (own ?? ry) * at.size;
      // Against the ellipse rather than a square, so the gaps between dots in
      // a tight back four stay gaps.
      if ((d.dx * d.dx) / (sx * sx) + (d.dy * d.dy) / (sy * sy) <= 1) return i;
    }
    return null;
  }

  /// _applyPlayerMove drags one player of the selected team, written back as
  /// the fraction of the team's box it is stored as, so it stays put when the
  /// team is moved or resized.
  void _applyPlayerMove(Offset doc) {
    var team = _selectedTeam();
    if (team == null ||
        _playerIndex < 0 ||
        _playerIndex >= team.players.length) {
      return;
    }
    var spot = team.players[_playerIndex];
    var at = doc - _playerGrab;

    // On a pitch, the pointer is carried back onto the field and the player
    // kept in its metres, so wherever the pitch goes, they go.
    var ground = teamGround(document, team, controller.frame);
    if (ground != null) {
      var field = ground.field(at);
      if (field == null) return;
      var animatingOnPitch = controller.document.isAnimated &&
          (controller.autoKeyframe || (spot.track?.isEmpty == false));
      if (animatingOnPitch) {
        var rest = teamFieldPoint(team, spot, ground.place);
        var ref = ground.place.reference;
        var track =
            (spot.track ?? ElementTrack.empty).seededFor(controller.frame);
        var pose = track.at(controller.frame);
        controller.replaceElement(
          team.withPlayer(
            _playerIndex,
            spot.copyWith(
              track: track.withKey(pose.copyWith(
                frame: controller.frame,
                dx: (field.dx - rest.dx) * ref,
                dy: -(field.dy - rest.dy) * ref,
              )),
            ),
          ),
          transient: true,
        );
        return;
      }
      var (dx, dy) = spotFromField(team, field, ground.place);
      controller.replaceElement(
        team.withPlayer(_playerIndex, spot.copyWith(dx: dx, dy: dy)),
        transient: true,
      );
      return;
    }

    // A player animates like anything else: while the document is animated
    // and either auto-keyframe is on or this player already moves, the drag
    // writes a keyframe on the player's track rather than changing where
    // they line up.
    var animating = controller.document.isAnimated &&
        (controller.autoKeyframe || (spot.track?.isEmpty == false));

    if (animating) {
      var rest = team.centreOf(spot);
      // Seeded at the start, so a drag at frame 12 is a run from where he was
      // rather than a move for the whole document. See ElementTrack.seededFor.
      var track =
          (spot.track ?? ElementTrack.empty).seededFor(controller.frame);
      var pose = track.at(controller.frame);
      controller.replaceElement(
        team.withPlayer(
          _playerIndex,
          spot.copyWith(
            track: track.withKey(pose.copyWith(
              frame: controller.frame,
              dx: at.dx - rest.dx,
              dy: at.dy - rest.dy,
            )),
          ),
        ),
        transient: true,
      );
      return;
    }

    var w = team.width == 0 ? 1.0 : team.width;
    var h = team.height == 0 ? 1.0 : team.height;
    controller.replaceElement(
      team.withPlayer(
        _playerIndex,
        spot.copyWith(dx: (at.dx - team.x) / w, dy: (at.dy - team.y) / h),
      ),
      transient: true,
    );
  }

  void _beginTransform(_DragMode mode, StageHandle? handle) {
    _mode = mode;
    _handle = handle;
    _startBounds = {
      for (var e in controller.selectedElements) e.id: e.bounds,
    };
    // And the elements as they were, for the resize that scales what is
    // inside them: the factor is measured from the start of the drag, so it
    // is applied to the element as it was then.
    _startElements = {
      for (var e in controller.selectedElements) e.id: e,
    };
    // Where each element is on this frame, which is what a move works from.
    // Kept apart from the resting bounds, which a resize works from: a
    // resize writes the base size, and a posed size would bake a scale into
    // the element. A move from the resting bounds would throw away whatever
    // pose the frame already had.
    _startPosed = {
      for (var e in controller.selectedElements)
        e.id: e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion),
    };
    // The box the handles are on, which for a line or a path is bigger than
    // the element's own (see _visualBounds). A resize is expressed against
    // this and applied to the real rectangle in the same proportion.
    _startVisual = {
      for (var e in controller.selectedElements) e.id: _visualBounds(e),
    };
    _startRotation = {
      for (var e in controller.selectedElements) e.id: e.rotation,
    };
    controller.beginInteraction();
  }

  /// _selectedChartLabels is what the painter outlines. Empty unless one
  /// chart is selected and has a placed label.
  List<Rect> _selectedChartLabels() {
    var element = controller.selected;
    if (element is! ChartElement || !controller.showHelpers) return const [];
    return chartLabelPlaces(element, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion))
        .values
        .where((r) => !r.isEmpty)
        .toList();
  }

  /// _selectedTableColumns is what the painter puts grips on: each inner
  /// column rule of the selected table, as an x and the top and bottom of the
  /// table.
  List<(double, double, double)> _selectedTableColumns() {
    var element = controller.selected;
    if (element is! TableElement || element.locked || !controller.showHelpers) {
      return const [];
    }
    var bounds = element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    return [
      for (var x in tableColumnDividers(element, bounds))
        (x, bounds.top, bounds.bottom),
    ];
  }

  /// _docSlop is the pointer's reach in document units: the allowance is in
  /// screen pixels (how still a hand is), so it is divided by the zoom.
  double get _docSlop => handleHitSlop / _scale;

  /// _applyPart writes a part-drag onto the selected element (see
  /// stage_parts.dart, which works out the new element). Transient: the drag
  /// is one undo step, closed when the pointer lifts.
  void _applyPart(Offset doc, {required bool chartLabel}) {
    var element = controller.selected;
    if (element == null) return;
    var bounds = element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    CanvasElement? next;
    if (chartLabel) {
      var grab = _labelGrab;
      if (grab == null || element is! ChartElement) return;
      next = chartLabelDragged(element, bounds, grab, doc);
    } else {
      var at = _columnGrab;
      if (at == null || element is! TableElement) return;
      next = tableColumnDragged(element, bounds, at, doc);
    }
    if (next != null) controller.replaceElement(next, transient: true);
  }

  /// _labelGrab is the chart label being dragged, while one is.
  ChartLabelGrab? _labelGrab;

  /// _columnGrab is which of a table's dividers is being dragged: the index of
  /// the column to its left.
  int? _columnGrab;

  void _onPointerMove(PointerMoveEvent event) {
    _pointer = event;
    // Held down as well as hovering: a brush's ring is drawn where the
    // pointer last was, and must follow it through a stroke.
    _hoverAt = event.localPosition;
    if (_brushAt != null) _moveBrush(event.localPosition);
    // A key held that travels is a drag of the keyboard: the note goes.
    if (_keyDown case (var e, var key)?
        when (event.localPosition - _pressedAt).distance > _buttonClickSlop) {
      controller.noteOff(e, key);
      _keyDown = null;
    }
    // A press that travels is a drag of the chart, not a hold of its key.
    if (_legendHold != null &&
        (event.localPosition - _pressedAt).distance > _buttonClickSlop) {
      _legendHold?.cancel();
      _legendHold = null;
    }
    if (_painting != null) {
      _paintStrokeAt(_toDocument(event.localPosition));
      return;
    }
    if (_mode == _DragMode.none) {
      _updateHover(event.localPosition);
      return;
    }

    if (_mode == _DragMode.pan) {
      var delta = event.localPosition - _dragStart;
      _setPan(Offset(_startPan.dx + delta.dx, _startPan.dy + delta.dy));
      return;
    }

    // A link being pulled out of a text box's overflow grip: nothing moves,
    // the line follows the pointer.
    if (_mode == _DragMode.flow) {
      setState(() => _flowAt = event.localPosition);
      return;
    }

    // Nothing moves until the press has travelled far enough to be a drag,
    // except the marquee, drawn from the press itself.
    if (!_travelled && _mode != _DragMode.marquee) {
      if ((event.localPosition - _pressedAt).distance <= _dragThreshold) {
        return;
      }
      _travelled = true;
      // From here on the drag is measured from the press, so what is dragged
      // sits under the pointer where it was picked up.
    }

    var doc = _toDocument(event.localPosition);
    var delta = doc - _dragStart;

    switch (_mode) {
      case _DragMode.copies:
        _moveCopies(delta);
      case _DragMode.copySize || _DragMode.copyTurn:
        _applyCopyBox(doc);
      case _DragMode.move:
        _applyMove(delta);
      case _DragMode.resize:
        _applyResize(delta);
      case _DragMode.skew:
        _applySkew(delta);
      case _DragMode.warpMove ||
            _DragMode.warpScale ||
            _DragMode.warpTurn ||
            _DragMode.warpMarquee:
        _dragWarp(doc);
      case _DragMode.rotate:
        _applyRotate(doc);
      case _DragMode.anchor:
        if (document.elementById(_anchorOf ?? "") case var e?) {
          controller.replaceElement(e.withAnchorAt(doc, controller.frame),
              transient: true);
        }
      case _DragMode.marquee:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.player:
        _applyPlayerMove(doc);
      case _DragMode.stageOrbit:
        if (controller.stageOf(_orbiting ?? "") case var s?) {
          var from = _orbitFrom ?? s.cameraAt(controller.frame);
          var d = event.localPosition - _orbitAt;
          var yaw = from.yaw + d.dx * CanvasOrbitPad.degreesPerPixel * 0.5;
          var pitch = (from.pitch + d.dy * CanvasOrbitPad.degreesPerPixel * 0.5)
              .clamp(-10.0, 89.0);
          controller.putStage(
              controller.stageFilmed(
                  s, from.copyWith(yaw: (yaw * 10).round() / 10, pitch: pitch)),
              transient: true);
        }
      case _DragMode.stagePan:
        if (controller.stageOf(_orbiting ?? "") case var s?) {
          var from = _orbitFrom ?? s.cameraAt(controller.frame);
          var d = (event.localPosition - _orbitAt) / (_scale == 0 ? 1 : _scale);
          controller.putStage(
              controller.stageFilmed(s, StageView(s.bounds, from).panned(d)),
              transient: true);
        }
      case _DragMode.gizmo:
        if (_gizmoDrag case (var g, var part, var from, var id)?) {
          if (document.elementById(id) case var e?) {
            var guides = document.guides;
            var snap =
                guides.stageSnap && !HardwareKeyboard.instance.isAltPressed;
            var spot = g.dragged(part, from, doc,
                pageScale: _scale,
                step: snap ? guides.stageStep : 0,
                turn: snap ? guides.stageTurn : 0);
            controller.replaceElement(controller.spotted(e, spot),
                transient: true);
          }
        }
      case _DragMode.parallaxPan:
        if ((controller.parallaxOf(_orbiting ?? ""), _panFrom)
            case (var p?, var from?)) {
          // Against the drag, in design units: dragging the scenery left
          // moves the camera right.
          var d = (event.localPosition - _orbitAt) / (_scale == 0 ? 1 : _scale);
          controller.putBackdrop(
              controller.parallaxFilmed(
                  p,
                  from.copyWith(
                      x: (from.x - d.dx).roundToDouble(),
                      y: (from.y - d.dy).roundToDouble())),
              transient: true);
        }
      case _DragMode.spritePaint:
        if (controller.spritePaint case var session?)
          unawaited(session.strokeTo(doc));
      case _DragMode.tilePaint:
        controller.tilePaint?.strokeTo(doc);
      case _DragMode.vectorPoint:
        _applyVectorMove(doc);
      case _DragMode.vectorPoints:
        var before = _vectorBefore;
        if (before != null) {
          var space = VectorSpace(before);
          var by = space.toDrawing(doc) - space.toDrawing(_vectorFrom);
          controller.replaceElement(
              withPointsMoved(before, controller.vectorPicks, by),
              transient: true);
        }
      case _DragMode.vectorMarquee:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.vectorScale:
        _applyScale(doc);
      case _DragMode.vectorTint:
        _applyTint(doc);
      case _DragMode.vectorCorner:
        _applyCorner(doc);
      case _DragMode.vectorPencil:
        _applyPencil(doc);
      case _DragMode.vectorKnife:
        // A point a couple of pixels on from the last, no closer.
        if ((doc - _knife.last).distance * _scale >= 2) {
          setState(() => _knife = [..._knife, doc]);
        }
      case _DragMode.vectorShapeDraw:
        _drawShape(doc);
      case _DragMode.vectorShapeFit:
        _fitShape(doc);
      case _DragMode.vectorItems:
        _dragItems(doc);
      case _DragMode.vectorItemsBox:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.vectorRub:
        if (_onPage(doc)) _carryStroke(doc);
      case _DragMode.vectorErase:
        if (controller.editingVector case var e?) {
          var next = withoutShapesAt(e, doc, _eraseReach);
          if (!identical(next, e)) {
            controller.replaceElement(next, transient: true);
          }
        }
      case _DragMode.vectorPen:
        var e = controller.editingVector, pick = controller.vectorPick;
        if (e != null && pick != null) {
          // A hand that shifts a little as it clicks puts a corner down: handles
          // a few pixels long would round it off.
          var pulled = (doc - _vectorFrom).distance * _scale >= _penPullMin;
          controller.replaceElement(
              withPenHandles(e, pick, pulled ? doc : _vectorFrom),
              transient: true);
        }
      case _DragMode.node:
        _applyNodeMove(doc, handle: false);
      case _DragMode.handle:
        _applyNodeMove(doc, handle: true);
      case _DragMode.chartLabel:
        _applyPart(doc, chartLabel: true);
      case _DragMode.tableColumn:
        _applyPart(doc, chartLabel: false);
      case _DragMode.counterPart:
        _applyCounterPart(doc);
      case _DragMode.imageFrame:
        _applyFraming(doc);
      case _DragMode.imageLayerMove ||
            _DragMode.imageLayerSize ||
            _DragMode.imageLayerTurn:
        _dragLayer(doc);
      case _DragMode.imageMask:
        _dragMask(doc);
      case _DragMode.imageBrush:
        _dragBrush(doc);
      case _DragMode.imageQuick:
        if (_maskOn case var on?) {
          setState(() => _quickTrail = [..._quickTrail, on.toPicture(doc)]);
        }
      case _DragMode.guide:
        _applyGuide(doc);
      default:
        break;
    }
  }

  /// _snappedTo is the lines the drag is caught on, drawn so a snap is seen
  /// rather than felt as a jump.
  SnapResult? _snappedTo;

  /// _otherBounds is where everything not being dragged sits, for the drag to
  /// line up against: the elements themselves, not only the guides. Locked
  /// elements count.
  List<Rect> _otherBounds() {
    if (!document.guides.snapTo.objects) return const [];
    var moving = _startPosed.keys.toSet();
    return [
      for (var element in document.elements)
        if (!moving.contains(element.base.id) && element.base.visible)
          element.bounds,
    ];
  }

  /// _startBoxOfSelection is where everything being dragged was when the drag
  /// began, as one rectangle.
  Rect? _startBoxOfSelection() {
    Rect? box;
    for (var entry in _startPosed.entries) {
      box = box == null ? entry.value : box.expandToInclude(entry.value);
    }
    return box;
  }

  void _applyMove(Offset delta) {
    // Shift constrains to one axis.
    if (_shiftHeld) {
      delta = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    // Snapped once, against the whole selection's box, so things moved
    // together stay together. Alt held turns it off for the drag.
    var box = _startBoxOfSelection();
    // Not on a 3D stage, where the page's lines mean nothing: what stands
    // there snaps to the 3D steps across its floor (see
    // CanvasController.movedTo).
    var onStage = _startPosed.keys
        .any((id) => document.elementById(id)?.base.spot != null);
    if (box != null && !onStage && !HardwareKeyboard.instance.isAltPressed) {
      var snapped = snapTopLeft(
        box.topLeft + delta,
        box.size,
        document.guides,
        document.size.size,
        within: document.guides.snapWithin / _scale,
        others: _otherBounds(),
      );
      delta = snapped.at - box.topLeft;
      _snappedTo = snapped;
    } else {
      _snappedTo = null;
    }

    var next = document;
    for (var entry in _startPosed.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // Through the controller rather than straight onto the base: an element
      // being animated is posed rather than moved. See
      // CanvasController.posesRatherThanMoves.
      next = next.withElement(
          controller.movedTo(element, entry.value.topLeft + delta));
    }
    controller.apply(next, transient: true);
  }

  /// _applyLineEnd drags one end of a single straight line, if that is what
  /// [handle] is on, and says whether it was. A line is its two ends, not a
  /// box (a box is at least eight pixels deep, so a line could never be
  /// level). The end swings onto the nearest level, upright or diagonal
  /// within a few degrees of one, always with Shift; Alt lets it go anywhere.
  bool _applyLineEnd(StageHandle handle, Offset delta) {
    if (_startVisual.length != 1 || !_frameOfSelection.upright) return false;
    // The line as it was when the drag began: every frame of the drag works
    // from it, since crossing one end past the other swaps the ends and
    // their arrows.
    var line = _startElements[_startVisual.keys.first];
    if (line is! LineElement || line.curvature != 0 || line.locked) {
      return false;
    }
    var was = line.bounds;
    var start = line.flipped ? was.bottomLeft : was.topLeft;
    var end = line.flipped ? was.topRight : was.bottomRight;
    // Which end the handle is on: the corner of the visual box nearest it.
    var box = _startVisual.values.first;
    var corner = switch (handle) {
      StageHandle.topLeft => box.topLeft,
      StageHandle.topRight => box.topRight,
      StageHandle.bottomLeft => box.bottomLeft,
      StageHandle.bottomRight => box.bottomRight,
      _ => null,
    };
    if (corner == null) return false;
    var movesStart = (corner - start).distance < (corner - end).distance;
    var fixed = movesStart ? end : start;
    var moving = (movesStart ? start : end) + delta;
    if (!HardwareKeyboard.instance.isAltPressed) {
      moving = snapLineAngle(fixed, moving, always: _shiftHeld);
    }
    var next = movesStart
        ? line.withEnds(moving, fixed)
        : line.withEnds(fixed, moving);
    controller.apply(document.withElement(next), transient: true);
    return true;
  }

  /// _applySkew slants the one selected element by a side handle dragged
  /// [delta]: the top or bottom handle across, the left or right up and
  /// down. The side held moves with the pointer and the opposite stays put,
  /// so the element is slanted about its middle and moved by half as much.
  void _applySkew(Offset delta) {
    var handle = _handle;
    if (handle == null || _startElements.length != 1) return;
    var start = _startElements.values.first;
    if (start.locked) return;
    var box = start.bounds;
    // The drag in the element's own turned frame, but not its slanted one:
    // the slant is what is being changed.
    var a = -start.rotation * math.pi / 180;
    var d = Offset(delta.dx * math.cos(a) - delta.dy * math.sin(a),
        delta.dx * math.sin(a) + delta.dy * math.cos(a));
    double tanOf(double deg) => math.tan(deg * math.pi / 180);
    double degOf(double t) =>
        (math.atan(t) * 180 / math.pi).clamp(-maxSkew, maxSkew);
    var skewX = start.base.skewX, skewY = start.base.skewY;
    Offset shift;
    switch (handle) {
      case StageHandle.topCenter || StageHandle.bottomCenter:
        if (box.height <= 0) return;
        var sign = handle == StageHandle.topCenter ? -1 : 1;
        skewX = degOf(tanOf(skewX) + sign * d.dx / box.height);
        shift = Offset(d.dx / 2, 0);
      case StageHandle.centerLeft || StageHandle.centerRight:
        if (box.width <= 0) return;
        var sign = handle == StageHandle.centerLeft ? -1 : 1;
        skewY = degOf(tanOf(skewY) + sign * d.dy / box.width);
        shift = Offset(0, d.dy / 2);
      default:
        return;
    }
    // The half-move back onto the page, turned as the element is.
    var r = start.rotation * math.pi / 180;
    var page = Offset(shift.dx * math.cos(r) - shift.dy * math.sin(r),
        shift.dx * math.sin(r) + shift.dy * math.cos(r));
    controller.replaceElement(
        start.withBase(
            skewX: skewX,
            skewY: skewY,
            x: start.x + page.dx,
            y: start.y + page.dy),
        transient: true);
  }

  void _applyResize(Offset delta) {
    var handle = _handle;
    if (handle == null) return;
    if (_applyLineEnd(handle, delta)) return;

    // The edge being dragged lands on the lines a move lands on: only for an
    // upright box, and Alt turns it off, as for a move.
    if (_frameOfSelection.upright && !HardwareKeyboard.instance.isAltPressed) {
      delta = _snapResize(handle, delta);
    } else {
      _snappedTo = null;
    }

    // The drag is rotated into the element's own frame, so pulling the right
    // edge of a tilted element makes it wider rather than moving it sideways.
    delta = _frameOfSelection.invert(delta);

    // One box for the whole drag, every element mapped through it, so
    // things resized together keep their sizes and gaps in proportion.
    Rect? group;
    for (var box in _startVisual.values) {
      group = group == null ? box : group.expandToInclude(box);
    }
    if (group == null) return;
    var several = _startVisual.length > 1;

    var left = group.left + (handle.movesLeft ? delta.dx : 0);
    var right = group.right + (handle.movesRight ? delta.dx : 0);
    var top = group.top + (handle.movesTop ? delta.dy : 0);
    var bottom = group.bottom + (handle.movesBottom ? delta.dy : 0);

    // Shift keeps the proportions, by whichever axis moved further. A
    // picture asks for that without the key, and Shift lets it go (see
    // CanvasElement.keepsAspect). Several things at once are held by
    // default: a group pulled out of shape pulls every gap out of shape.
    var first = document.elementById(_startVisual.keys.first);
    var keep = several
        ? !_shiftHeld
        : ((first?.keepsAspect ?? false) ? !_shiftHeld : _shiftHeld);
    if (keep && group.height > 0) {
      var aspect = group.width / group.height;
      if ((right - left).abs() > (bottom - top).abs() * aspect) {
        var height = (right - left).abs() / aspect;
        handle.movesTop ? top = bottom - height : bottom = top + height;
      } else {
        var width = (bottom - top).abs() * aspect;
        handle.movesLeft ? left = right - width : right = left + width;
      }
    }

    // Minimums rather than a selection dragged inside out: a negative width
    // draws nothing and cannot be grabbed again.
    const minimum = 8.0;
    if (right - left < minimum) {
      handle.movesLeft ? left = right - minimum : right = left + minimum;
    }
    if (bottom - top < minimum) {
      handle.movesTop ? top = bottom - minimum : bottom = top + minimum;
    }

    var sx = group.width == 0 ? 1.0 : (right - left) / group.width;
    var sy = group.height == 0 ? 1.0 : (bottom - top) / group.height;

    var next = document;
    for (var entry in _startVisual.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // Against the box the handles are on, which for a line or a path is
      // larger than the element's own rectangle.
      var start = entry.value;
      var real = _startBounds[entry.key] ?? start;

      // Holding the proportions holds them of everything inside (the type,
      // the spacing, the room inside a chip). From the element as it was when
      // the drag began: see _startElements.
      var from = _startElements[entry.key] ?? element;
      element = keep ? from.scaledBy(sx) : element;
      next = next.withElement(element.withBase(
        x: left + (real.left - group.left) * sx,
        y: top + (real.top - group.top) * sy,
        width: math.max(1, real.width * sx),
        height: math.max(1, real.height * sy),
        // What the design inside the box has been scaled by, written down
        // where the shape switch reads it (see ElementBase.typeScale), so going
        // to another shape does not undo the drag by the wrong amount.
        typeScale: keep ? from.base.typeScale * sx : null,
      ));
    }
    controller.apply(next, transient: true);
  }

  /// _snapResize moves the dragged edge onto a line and leaves the opposite
  /// edge alone: a resize moves one side, so it snaps that side only, against
  /// the union of what is being resized.
  Offset _snapResize(StageHandle handle, Offset delta) {
    Rect? box;
    for (var start in _startVisual.values) {
      box = box == null ? start : box.expandToInclude(start);
    }
    if (box == null) {
      _snappedTo = null;
      return delta;
    }

    var guides = document.guides;
    var within = guides.snapWithin / _scale;
    var canvas = document.size.size;
    var others = _otherBounds();
    var dx = delta.dx;
    var dy = delta.dy;
    double? onVertical;
    double? onHorizontal;

    if (handle.movesLeft || handle.movesRight) {
      var at = (handle.movesLeft ? box.left : box.right) + dx;
      var line = snapEdgeTo(at, guides, canvas,
          vertical: true, within: within, others: others);
      if (line != null) {
        dx += line - at;
        onVertical = line;
      }
    }
    if (handle.movesTop || handle.movesBottom) {
      var at = (handle.movesTop ? box.top : box.bottom) + dy;
      var line = snapEdgeTo(at, guides, canvas,
          vertical: false, within: within, others: others);
      if (line != null) {
        dy += line - at;
        onHorizontal = line;
      }
    }

    _snappedTo = onVertical == null && onHorizontal == null
        ? null
        : SnapResult(box.topLeft,
            onVertical: onVertical, onHorizontal: onHorizontal);
    return Offset(dx, dy);
  }

  /// _anchorOf is the element whose anchor is being dragged.
  String? _anchorOf;

  /// _anchorsShown is every selected element's anchor that is shown: where
  /// it is on the page now, and whether it is locked.
  List<({Offset at, bool locked})> _anchorsShown() => [
        for (var id in controller.selection)
          if (controller.anchorShown(id))
            if (document.elementById(id) case var e?)
              (at: e.anchorAt(controller.frame), locked: e.base.anchorLocked),
      ];

  /// _anchorUnder is the element whose anchor (shown, and not locked) is
  /// under [stage], or null.
  String? _anchorUnder(Offset stage) {
    for (var id in controller.selection) {
      if (!controller.anchorShown(id)) continue;
      var e = document.elementById(id);
      if (e == null || e.base.anchorLocked || e.locked) continue;
      if ((_toStage(e.anchorAt(controller.frame)) - stage).distance <= 10) {
        return id;
      }
    }
    return null;
  }

  void _applyRotate(Offset doc) {
    var bounds = _selectionBounds;
    if (bounds == null) return;
    var centre = bounds.center;
    // One element turns about its anchor, which stays where it is.
    if (controller.selection.length == 1) {
      var one = document.elementById(controller.selection.first);
      if (one != null && !one.anchorCentred) {
        centre =
            one.turnedAboutCentre(one.anchorIn(one.bounds), one.bounds.center);
      }
    }

    var from = math.atan2(_dragStart.dy - centre.dy, _dragStart.dx - centre.dx);
    var to = math.atan2(doc.dy - centre.dy, doc.dx - centre.dx);
    var degrees = (to - from) * 180 / math.pi;

    var next = document;
    for (var entry in _startRotation.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      var rotation = entry.value + degrees;
      // Shift snaps to fifteen degrees.
      if (_shiftHeld) rotation = (rotation / 15).round() * 15;
      next = next.withElement(element.turnedTo(rotation));
    }
    controller.apply(next, transient: true);
  }

  void _onPointerUp(PointerEvent event) {
    // Let go before it was held long enough, so it was a press after all.
    _legendHold?.cancel();
    _legendHold = null;
    if (_painting != null) {
      _commitStroke();
      return;
    }
    _playerIndex = -1;

    // A press on an already-selected button that never became a drag is a
    // click, and a click runs it. Measured in stage pixels, so the tolerance
    // is the same at any zoom.
    var counter = _pendingCounter;
    var counterAt = _pendingCounterAt;
    _pendingCounter = null;
    _pendingCounterAt = -1;
    if (_counterPart != null) {
      _counterPart = null;
      controller.endInteraction();
      _mode = _DragMode.none;
    }
    if (counter != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressCounter(counter, counterAt);
      return;
    }

    var legend = _pendingLegend;
    var legendAt = _pendingLegendAt;
    _pendingLegend = null;
    _pendingLegendAt = -1;
    if (legend != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _toggleSeries(legend, legendAt);
      return;
    }

    var film = _pendingVideo;
    _pendingVideo = null;
    if (film != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressVideo(film, _pendingVideoPart, _pendingVideoAt);
      return;
    }

    if (_keyDown case (var e, var key)?) {
      _keyDown = null;
      controller.noteOff(e, key);
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      return;
    }

    var sound = _pendingAudio;
    _pendingAudio = null;
    if (sound != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      _pressAudio(sound, _pendingAudioPart, _pendingAudioAt);
      return;
    }

    var button = _pendingButton;
    _pendingButton = null;
    if (button != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      var url = controller.runButtonAction(button.action);
      if (url != null && url.isNotEmpty) widget.onButtonLink?.call(url);
      return;
    }

    if (_mode == _DragMode.flow) {
      _dropFlow(event.localPosition);
      setState(() {
        _flowFrom = null;
        _flowAt = null;
        _mode = _DragMode.none;
      });
      return;
    }

    if (_mode == _DragMode.vectorMarquee) {
      var box = _marquee, e = controller.editingVector;
      if (box != null && e != null && box.width > 2 && box.height > 2) {
        var inside = picksIn(e, box);
        controller.pickVectorPoints(
            _shiftHeld ? {...controller.vectorPicks, ...inside} : inside);
      } else if (_vectorShapeUnder >= 0 && !_travelled) {
        // A click on a shape picks it.
        controller.pickVectorShape(_vectorShapeUnder);
      } else if (!_vectorPressedOutside && !_shiftHeld) {
        // A click on the drawing's empty space lets go of what was picked.
        controller.pickVectorShape(-1);
      } else if (_vectorPressedOutside && !_travelled) {
        // A click off the drawing: the editing is finished, and the click does
        // what it would have.
        controller.editVector(null);
        var hit = _hitElement(_dragStart);
        if (hit == null) {
          controller.clearSelection();
        } else if (hit.id != controller.selected?.id) {
          controller.selectOnly(hit.id);
        }
      }
      _vectorPressedOutside = false;
      _vectorShapeUnder = -1;
      setState(() => _marquee = null);
    }
    if (_mode == _DragMode.vectorPoints ||
        _mode == _DragMode.vectorPen ||
        _mode == _DragMode.vectorScale ||
        _mode == _DragMode.vectorTint ||
        _mode == _DragMode.vectorCorner ||
        _mode == _DragMode.vectorPencil ||
        _mode == _DragMode.vectorErase ||
        _mode == _DragMode.vectorRub ||
        _mode == _DragMode.vectorShapeDraw ||
        _mode == _DragMode.vectorShapeFit ||
        _mode == _DragMode.vectorItems) {
      if (_mode == _DragMode.vectorShapeDraw) {
        // A click, not a drag: a shape of a good size, centred on it.
        if (!_travelled) _drawShape(_shapeFrom, clicked: true);
        if (_vectorBefore?.shapes case var was?) {
          controller.vectorShapeMade = was.length;
          controller.pickVectorShape(was.length);
        }
      }
      if (_mode == _DragMode.vectorPencil) _mergePencil();
      _penInto = const {};
      _stroke = null;
      _strokeOn = {};
      if (_mode == _DragMode.vectorScale && _scaleLetsGo && !_travelled) {
        controller.pickVectorPoints(const {});
      }
      _scaleLetsGo = false;
      _penSamples = [];
      _penRuns = [];
      _vectorBefore = null;
      _widths = {};
      controller.endInteraction();
      if (_tintWaiting != null) {
        _tintWaiting = null;
        controller.editVector(null);
      }
    }
    if (_mode == _DragMode.warpMarquee) _finishWarpMarquee();
    if (_mode == _DragMode.marquee) {
      var box = _marquee;
      if (box != null && box.width > 3 && box.height > 3) {
        for (var e in document.elements) {
          if (!e.locked && e.visible && box.overlaps(e.bounds)) {
            controller.toggleSelected(e.id);
          }
        }
      }
      setState(() => _marquee = null);
    }
    if (_mode == _DragMode.node || _mode == _DragMode.handle) {
      // Re-baked once, at the end of the drag rather than on every pixel: a
      // route is dozens of keyframes.
      var path = _selectedPath();
      if (path != null) controller.applyPathFollow(path);
      controller.endInteraction();
      _nodeIndex = -1;
    }
    // Every mode that opened an interaction closes it here: beginInteraction
    // only takes the document if none is held, so one left open would merge
    // into the next gesture's undo step.
    if (_mode == _DragMode.guide) _finishGuide();
    if (_mode == _DragMode.spritePaint) {
      if (controller.spritePaint case var session?)
        unawaited(session.strokeEnd());
    }
    if (_mode == _DragMode.tilePaint) controller.tilePaint?.strokeEnd();
    if (_mode == _DragMode.vectorKnife) _finishKnife();
    if (_mode == _DragMode.vectorItemsBox) {
      var box = _marquee;
      var e = controller.editingVector;
      if (box != null && e != null && _travelled) {
        controller.pickVectorItems(itemsIn(e, box), add: _shiftHeld);
      }
      setState(() => _marquee = null);
    }
    // A click on a copy, not a drag: that copy picked.
    if (_mode == _DragMode.move && !_travelled) {
      if ((_pressedCopy, _pressedCopyOf) case (var id?, var of?)) {
        controller.pickCopy(of, id);
      }
    }
    _pressedCopy = null;
    if (_mode == _DragMode.copies ||
        _mode == _DragMode.copySize ||
        _mode == _DragMode.copyTurn ||
        _mode == _DragMode.move ||
        _mode == _DragMode.anchor ||
        _mode == _DragMode.resize ||
        _mode == _DragMode.skew ||
        _mode == _DragMode.warpMove ||
        _mode == _DragMode.warpScale ||
        _mode == _DragMode.warpTurn ||
        _mode == _DragMode.rotate ||
        _mode == _DragMode.chartLabel ||
        _mode == _DragMode.stageOrbit ||
        _mode == _DragMode.stagePan ||
        _mode == _DragMode.gizmo ||
        _mode == _DragMode.parallaxPan ||
        _mode == _DragMode.tableColumn ||
        _mode == _DragMode.imageFrame ||
        _mode == _DragMode.imageLayerMove ||
        _mode == _DragMode.imageLayerSize ||
        _mode == _DragMode.imageLayerTurn ||
        _mode == _DragMode.imageMask ||
        _mode == _DragMode.imageBrush ||
        _mode == _DragMode.vectorPoint ||
        _mode == _DragMode.player ||
        _mode == _DragMode.guide) {
      controller.endInteraction();
    }
    if (_mode == _DragMode.imageQuick && _quickTrail.isNotEmpty) {
      unawaited(controller.imageTool == ImageTool.refine
          ? controller.refineEdge(_quickTrail)
          : controller.quickSelect(_quickTrail, subtract: _quickSubtract));
      // Left on the canvas until the cut lands, so the stroke does not
      // vanish for the moment it takes.
    }
    // A press on the stage with the page locked that never moved is a click
    // on nothing: it lets go of what was selected.
    if (_lockedPress && !_travelled) controller.clearSelection();
    _lockedPress = false;
    if (_gizmoDrag != null) setState(() => _gizmoDrag = null);
    _mode = _DragMode.none;
    _handle = null;
    _maskOn = null;
    _strokeAt = null;
    // The lines only mean anything while something is being dragged.
    if (_snappedTo != null) setState(() => _snappedTo = null);
  }

  /// _backgrounds is the generated background, rasterised once and kept while
  /// the design and the size hold still. One cache for every canvas on screen:
  /// it holds a few rasters, so the facing leaf and the pages leaving and
  /// arriving keep theirs. See ProceduralCache.
  final ProceduralCache _backgrounds = ProceduralCache();

  /// _hoverAt is where the pointer last was, in stage coordinates, so the
  /// cursor can say what is under it (a ruler, in particular).
  Offset _hoverAt = Offset.zero;

  /// _updateHover keeps the renderer told which button is under the pointer.
  void _updateHover(Offset stage) {
    _hoverAt = stage;
    // For a Look at that faces the pointer.
    controller.stagePointer = _toDocument(stage);
    // The tile to be laid follows the pointer over a map being painted.
    controller.tilePaint?.hoverAt(_toDocument(stage));
    // The brush's ring follows the pointer.
    if (controller.editingImage != null &&
        (controller.imageTool == ImageTool.brush ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine ||
            controller.imageTool.paints)) {
      setState(() {});
    }
    var doc = _toDocument(stage);
    // The gizmo's part under the pointer, lit.
    var hot = _gizmo()?.hit(doc, _gizmoReach);
    if (hot != _gizmoHot) setState(() => _gizmoHot = hot);
    var element = _hitElement(doc);
    var id = element is ButtonElement ? element.id : null;

    // And which of a live counter's own buttons, lit as a button element
    // is.
    String? counter;
    var at = -1;
    if (element is CounterElement && element.live) {
      at = _counterButtonAt(element, doc);
      if (at >= 0) counter = element.id;
    }

    // Whether a click here would do something rather than select or move
    // (the tests _onPointerDown makes), so the pointer can say so.
    var selected = element != null &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id;
    var pressable = counter != null ||
        (selected &&
            (element is ButtonElement ||
                (element is VideoElement &&
                    _videoPartAt(element, doc) != null) ||
                (element is AudioElement &&
                    _audioPartAt(element, doc) != null)));

    if (id != controller.hoveredButton ||
        counter != _hoveredCounter ||
        at != _hoveredCounterAt ||
        pressable != _hoverPressable) {
      controller.hoveredButton = id;
      setState(() {
        _hoveredCounter = counter;
        _hoveredCounterAt = at;
        _hoverPressable = pressable;
      });
    }
  }

  /// _hoverPressable is whether the pointer is over something a click would
  /// press: a selected button, a selected speaker's or video's controls, or a
  /// live counter's buttons.
  bool _hoverPressable = false;

  // ---------------------------------------------------------- 3D stage

  /// _gizmoDrag is the gizmo being dragged: as it was when the drag began,
  /// the part held, the page point it was taken hold of at, and the
  /// element's id.
  (StageGizmo, GizmoPart, Offset, String)? _gizmoDrag;

  /// _gizmoHot is the gizmo's part under the pointer, lit.
  GizmoPart? _gizmoHot;

  /// _lockedPress is whether the press under way took hold of the stage's
  /// camera because the page is locked.
  bool _lockedPress = false;

  /// _gizmoReach is how near a part, in page units, the pointer has to be
  /// to take hold of it.
  double get _gizmoReach => 9 / (_scale == 0 ? 1 : _scale);

  /// _gizmo is the gizmo on the one element selected, where it stands on a
  /// stage and the handles are shown, or null.
  StageGizmo? _gizmo() {
    if (!controller.showHelpers || controller.playing || controller.gaming) {
      return null;
    }
    if (controller.selection.length != 1) return null;
    var e = document.elementById(controller.selection.first);
    if (e == null || e.locked || e.base.spot == null) return null;
    var at = stagedIn(document, e, controller.frame);
    if (at == null) return null;
    return StageGizmo.of(e, at, controller.stageTool, _scale);
  }

  /// _pressGizmo takes hold of the part of the gizmo under [doc], if any.
  bool _pressGizmo(Offset doc) {
    var g = _gizmo();
    if (g == null) return false;
    var part = g.hit(doc, _gizmoReach);
    if (part == null) return false;
    _gizmoDrag = (g, part, doc, controller.selection.first);
    _mode = _DragMode.gizmo;
    controller.beginInteraction();
    setState(() => _gizmoHot = part);
    return true;
  }

  /// _pressLockedStage takes hold of the stage's camera, with the page locked,
  /// for a press on the stage itself (not on anything standing on it) or the
  /// middle button anywhere: a drag orbits; shifted, or the middle button, it
  /// pans.
  bool _pressLockedStage(PointerDownEvent event, Offset doc) {
    if (!controller.pageLocked) return false;
    var s = controller.steeredStage;
    if (s == null || s.locked) return false;
    var middle = event.buttons == kMiddleMouseButton;
    if (!middle) {
      var hit = _hitElement(doc);
      var onStage = hit == null ||
          hit is StageElement ||
          (hit is BackgroundElement && hit.isStage);
      if (!onStage) return false;
    }
    _orbiting = s.id;
    _orbitFrom = s.cameraAt(controller.frame);
    _orbitAt = event.localPosition;
    _mode = middle || HardwareKeyboard.instance.isShiftPressed
        ? _DragMode.stagePan
        : _DragMode.stageOrbit;
    _lockedPress = true;
    controller.beginInteraction();
    return true;
  }

  /// _steerTimer ends a run of scrolls and pinches steering the camera
  /// as one undo step, once they stop.
  Timer? _steerTimer;

  /// _steering opens the undo step a run of camera steering makes, or
  /// keeps it open.
  void _steering() {
    if (_steerTimer == null) controller.beginInteraction();
    _steerTimer?.cancel();
    _steerTimer = Timer(const Duration(milliseconds: 350), () {
      _steerTimer = null;
      controller.endInteraction();
    });
  }

  /// _steerByScroll is the wheel and two fingers with the page locked on a
  /// stage: they orbit its camera, shifted they pan it, and with Command or
  /// Control (a pinch, to the wheel) they zoom it.
  void _steerByScroll(PointerScrollEvent event) {
    if (!controller.onStage3d) return;
    var keys = HardwareKeyboard.instance;
    var d = event.scrollDelta;
    _steering();
    if (keys.isControlPressed || keys.isMetaPressed) {
      controller.dollyBy(math.exp(d.dy * 0.01), transient: true);
    } else if (keys.isShiftPressed) {
      controller.panCameraBy(-d / (_scale == 0 ? 1 : _scale),
          transient: true);
    } else {
      controller.orbitBy(-d.dx * 0.4, -d.dy * 0.4, transient: true);
    }
  }

  /// _scrollPhysics holds a page that scrolls still while it is locked.
  ScrollPhysics? get _scrollPhysics =>
      controller.pageLocked ? const NeverScrollableScrollPhysics() : null;

  /// _pinchScale is the last scale of a pinch steering the camera.
  double _pinchScale = 1;

  /// _wheelRests closes a run of wheel turns as one change.
  Timer? _wheelRests;

  void _onScroll(PointerScrollEvent event) {
    // While reframing, the wheel is the picture's zoom rather than the
    // view's: drag to choose what is in shot, scroll to choose how much.
    if (_framing != null) {
      var framed = document.elementById(_framing!);
      if (framed is ImageElement) {
        // A run of wheel turns is one change, closed once the wheel rests.
        controller.beginInteraction();
        controller.replaceElement(
            framed.copyWith(
                framing: framed.framing.copyWith(
                    zoom: framed.framing.zoom *
                        (event.scrollDelta.dy > 0 ? 0.94 : 1.06))),
            transient: true);
        _wheelRests?.cancel();
        _wheelRests = Timer(
            const Duration(milliseconds: 400), controller.endInteraction);
        return;
      }
    }

    // About the pointer rather than the middle, so the corner scrolled in on
    // stays where it is.
    _zoomAbout(event.localPosition,
        controller.zoom * (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
  }

  /// _zoomAbout zooms to [zoom], keeping the point of the page under
  /// [stage] where it is on screen.
  void _zoomAbout(Offset stage, double zoom,
      {Offset? doc, Offset? pan, double? scale}) {
    var under = doc ?? _toDocument(stage);
    var was = pan ?? _clampedPan;
    var before = scale ?? _scale;
    controller.zoom = zoom;
    var after = _fitScale * controller.zoom;
    var middle = Offset(document.size.width / 2, document.size.height / 2);
    var next = was + (under - middle) * (before - after);
    controller.pan = Offset2(next.dx, next.dy);
  }

  /// _pinch is a pinch on the trackpad under way: the zoom, the view, the
  /// scale and the point of the page under the fingers it started from.
  ({double zoom, Offset pan, double scale, Offset doc})? _pinch;

  void _onPinchStart(PointerPanZoomStartEvent e) {
    // Locked, the page does not zoom: on a stage the fingers steer its
    // camera instead (see _onPinchUpdate).
    if (controller.pageLocked) {
      _pinchScale = 1;
      return;
    }
    _pinch = (
      zoom: controller.zoom,
      pan: _clampedPan,
      scale: _scale,
      doc: _toDocument(e.localPosition),
    );
  }

  /// _onPinchUpdate zooms as the fingers spread or close, about where they
  /// are. A two-finger slide alone is the scroll views' to scroll.
  void _onPinchUpdate(PointerPanZoomUpdateEvent e) {
    if (controller.pageLocked) {
      if (!controller.onStage3d) return;
      _steering();
      var spread = e.scale / (_pinchScale == 0 ? 1 : _pinchScale);
      _pinchScale = e.scale;
      if ((spread - 1).abs() > 0.002) {
        controller.dollyBy(1 / spread, transient: true);
      } else if (HardwareKeyboard.instance.isShiftPressed) {
        controller.panCameraBy(e.panDelta / (_scale == 0 ? 1 : _scale),
            transient: true);
      } else {
        controller.orbitBy(e.panDelta.dx * 0.4, e.panDelta.dy * 0.4,
            transient: true);
      }
      return;
    }
    var p = _pinch;
    if (p == null || (e.scale - 1).abs() < 0.01) return;
    _zoomAbout(e.localPosition, p.zoom * e.scale,
        doc: p.doc, pan: p.pan, scale: p.scale);
  }

  void _onPinchEnd(PointerPanZoomEndEvent e) => _pinch = null;

  // ------------------------------------------------------------------------

  /// _onKey is the canvas's keyboard. The arrows move what is chosen, and
  /// walk the frames when nothing is; Alt swaps the two. Space plays and
  /// stops; the pan tool pans (see CanvasTool).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A game playing has the keys: Space jumps and the arrows run, rather
    // than playing the timeline or walking its frames. See gameKey.
    if (controller.gaming) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never while somebody is typing: see isTypingInAField.
    if (isTypingInAField()) return KeyEventResult.ignored;
    var keys = HardwareKeyboard.instance;
    // Arrows move what is chosen, and walk the frames when nothing is; Alt
    // asks for the other.
    var nudging = controller.selection.isNotEmpty != keys.isAltPressed;
    var step = keys.isShiftPressed ? 10.0 : 1.0;

    // Cmd on a Mac, Control everywhere else; either, so a Mac with a PC
    // keyboard works too.
    var command = keys.isMetaPressed || keys.isControlPressed;
    if (command) {
      // While a drawing is edited, its points are what is copied, cut, pasted
      // and picked all, not the elements.
      if (controller.editingVector != null) {
        var done = switch (event.logicalKey) {
          LogicalKeyboardKey.keyA => controller.pickAllVectorPoints(),
          LogicalKeyboardKey.keyC => controller.copyVectorPoints(),
          LogicalKeyboardKey.keyX => controller.cutVectorPoints(),
          LogicalKeyboardKey.keyV => controller.pasteVectorPoints(),
          _ => false,
        };
        if (done) return KeyEventResult.handled;
        // A copy or paste with no points: nothing, rather than the whole
        // drawing copied while its points are being edited.
        if (const [
          LogicalKeyboardKey.keyA,
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyV,
        ].contains(event.logicalKey)) {
          return KeyEventResult.handled;
        }
      }
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyC:
          controller.copySelected();
        case LogicalKeyboardKey.keyX:
          controller.cutSelected();
        case LogicalKeyboardKey.keyV:
          controller.paste();
        case LogicalKeyboardKey.keyD:
          controller.duplicateSelected();
        case LogicalKeyboardKey.keyA:
          controller.selectAll();
        case LogicalKeyboardKey.keyZ:
          keys.isShiftPressed ? controller.redo() : controller.undo();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }

    // A warp grid's picked points, while it is shown, before anything else
    // the arrows do.
    var arrow = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (arrow != null && _nudgeWarp(arrow)) return KeyEventResult.handled;

    // The page's and the stage's own letters, while no picture or drawing is
    // being edited (they have letters of their own). L locks the page,
    // Shift-S snaps; on a 3D stage G, R and S are the 3D tools, F frames what
    // is selected and Home puts the camera back.
    var plain = controller.editingImage == null &&
        controller.editingVector == null &&
        !keys.isAltPressed;
    var three = plain && controller.onStage3d;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyL when plain:
        controller.pageLocked = !controller.pageLocked;
      case LogicalKeyboardKey.keyS when plain && keys.isShiftPressed:
        controller.canvasSnap = !controller.canvasSnap;
      case LogicalKeyboardKey.keyG when three:
        controller.stageTool = StageTool.move;
      case LogicalKeyboardKey.keyR when three:
        controller.stageTool = StageTool.rotate;
      case LogicalKeyboardKey.keyS when three:
        controller.stageTool = StageTool.scale;
      case LogicalKeyboardKey.keyF when three:
        controller.frameSelected();
      case LogicalKeyboardKey.home when three:
        controller.resetCamera();
      case LogicalKeyboardKey.space:
        controller.togglePlay();
      case LogicalKeyboardKey.arrowLeft:
        nudging ? controller.nudgeSelected(-step, 0) : controller.stepFrame(-1);
      case LogicalKeyboardKey.arrowRight:
        nudging ? controller.nudgeSelected(step, 0) : controller.stepFrame(1);
      case LogicalKeyboardKey.arrowUp:
        nudging
            ? controller.nudgeSelected(0, -step)
            : controller.stepFrame(-10);
      case LogicalKeyboardKey.arrowDown:
        nudging ? controller.nudgeSelected(0, step) : controller.stepFrame(10);
      // A picture's layers open with a layer picked: the layer goes, not the
      // picture.
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
          when controller.editingImage != null &&
              controller.imageLayer != baseLayerId:
        controller.removeImageLayer(controller.imageLayer);
      // Copies picked: those copies go, not the element.
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
          when controller.selected != null &&
              controller.copiesPicked(controller.selected!.id):
        var id = controller.selected!.id;
        controller.beginInteraction();
        controller.removeCopies(id, controller.pickedCopiesOf(id));
        controller.endInteraction();
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        controller.deleteSelected();
      // Return finishes the shape the pen is drawing, left open.
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when controller.vectorPenShape >= 0:
        controller.finishPenShape();
      // The drawing's tools, while it is edited: V picks points, P the pen,
      // S scales, I tints. A tool's key again goes back to picking.
      case LogicalKeyboardKey.keyV when controller.editingImage != null:
        controller.imageTool = ImageTool.move;
      // A picture's mask tools, while its layers are open.
      case LogicalKeyboardKey.keyW when controller.editingImage != null:
        controller.imageTool = ImageTool.subject;
      case LogicalKeyboardKey.keyC when controller.editingImage != null:
        controller.imageTool = ImageTool.crop;
      case LogicalKeyboardKey.keyK when controller.editingImage != null:
        controller.imageTool = ImageTool.edge;
      case LogicalKeyboardKey.keyB when controller.editingImage != null:
        controller.imageTool = ImageTool.brush;
      case LogicalKeyboardKey.keyQ when controller.editingImage != null:
        controller.imageTool = ImageTool.quick;
      case LogicalKeyboardKey.keyR when controller.editingImage != null:
        controller.imageTool = ImageTool.refine;
      case LogicalKeyboardKey.keyP when controller.editingImage != null:
        controller.imageTool = ImageTool.paint;
      case LogicalKeyboardKey.keyE when controller.editingImage != null:
        controller.imageTool = ImageTool.erase;
      case LogicalKeyboardKey.keyS when controller.editingImage != null:
        controller.imageTool = ImageTool.clone;
      case LogicalKeyboardKey.keyJ when controller.editingImage != null:
        controller.imageTool = ImageTool.heal;
      case LogicalKeyboardKey.keyO when controller.editingImage != null:
        controller.imageTool = ImageTool.dodge;
      case LogicalKeyboardKey.keyU when controller.editingImage != null:
        controller.imageTool = ImageTool.soften;
      case LogicalKeyboardKey.keyY when controller.editingImage != null:
        controller.imageTool = ImageTool.sharpen;
      case LogicalKeyboardKey.keyM when controller.editingImage != null:
        controller.imageTool = ImageTool.smudge;
      case LogicalKeyboardKey.keyL when controller.editingImage != null:
        controller.imageTool = ImageTool.lasso;
      case LogicalKeyboardKey.keyG when controller.editingImage != null:
        controller.imageTool = ImageTool.fade;
      // X turns the mask tools over, as it swaps the colours everywhere.
      case LogicalKeyboardKey.keyX when controller.editingImage != null:
        controller.maskHide = !controller.maskHide;
      // The brackets size the brush, as in every painting program.
      case LogicalKeyboardKey.bracketLeft when controller.editingImage != null:
        if (controller.imageTool.paints) {
          controller.paintSize = controller.paintSize / 1.2;
        } else {
          controller.maskBrushSize = controller.maskBrushSize / 1.2;
        }
      case LogicalKeyboardKey.bracketRight when controller.editingImage != null:
        if (controller.imageTool.paints) {
          controller.paintSize = controller.paintSize * 1.2;
        } else {
          controller.maskBrushSize = controller.maskBrushSize * 1.2;
        }
      case LogicalKeyboardKey.keyV when controller.editingVector != null:
        controller.vectorTool = VectorTool.select;
      case LogicalKeyboardKey.keyG when controller.editingVector != null:
        controller.vectorTool = VectorTool.selectShapes;
      case LogicalKeyboardKey.keyP when controller.editingVector != null:
        controller.vectorTool =
            controller.vectorPen ? VectorTool.select : VectorTool.pen;
      case LogicalKeyboardKey.keyS when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.scale
            ? VectorTool.select
            : VectorTool.scale;
      case LogicalKeyboardKey.keyT when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.text
            ? VectorTool.select
            : VectorTool.text;
      case LogicalKeyboardKey.keyK when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.knife
            ? VectorTool.select
            : VectorTool.knife;
      case LogicalKeyboardKey.keyR when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.shapes
            ? VectorTool.select
            : VectorTool.shapes;
      case LogicalKeyboardKey.keyE when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.eraser
            ? VectorTool.select
            : VectorTool.eraser;
      case LogicalKeyboardKey.keyN when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.pencil
            ? VectorTool.select
            : VectorTool.pencil;
      case LogicalKeyboardKey.keyA when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.align
            ? VectorTool.select
            : VectorTool.align;
      case LogicalKeyboardKey.keyC when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.corner
            ? VectorTool.select
            : VectorTool.corner;
      case LogicalKeyboardKey.keyB when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.boolean
            ? VectorTool.select
            : VectorTool.boolean;
      case LogicalKeyboardKey.keyI when controller.editingVector != null:
        controller.vectorTool = controller.vectorTool == VectorTool.tint
            ? VectorTool.select
            : VectorTool.tint;
      case LogicalKeyboardKey.escape:
        // One thing at a time: a warp grid's picked points are let go first,
        // then the grid, then the picture's frame, and only then the selection.
        if (controller.warpLayer != null && controller.warpPicks.isNotEmpty) {
          controller.warpPicks = const {};
        } else if (controller.warpLayer != null) {
          controller.editWarp("", "", on: false);
        } else
        // A clone's point is let go before the picture is.
        if (controller.editingImage != null &&
            controller.imageTool == ImageTool.clone &&
            controller.cloneFrom != null) {
          controller.cloneFrom = null;
        } else if (controller.editingImage != null &&
            controller.imageTool != ImageTool.move) {
          // Then the tool is put down, and only then the picture.
          controller.imageTool = ImageTool.move;
        } else if (controller.editingImage != null) {
          controller.editImage(null);
        } else if (controller.vectorEditing != null) {
          // Out of a drawing a step at a time: the shape the pen is drawing,
          // then the pen, then the points picked, then the editing.
          if (controller.vectorPenShape >= 0) {
            controller.finishPenShape();
          } else if (controller.vectorTool != VectorTool.select) {
            controller.vectorTool = VectorTool.select;
          } else if (controller.vectorPicks.isNotEmpty) {
            controller.pickVectorPoint(null);
          } else {
            controller.editVector(null);
          }
        } else if (controller.placingCopies != null) {
          // Placing copies stops before anything is let go.
          controller.placingCopies = null;
        } else if (controller.selected case var e?
            when controller.copiesPicked(e.id)) {
          // Copies picked: back to all of them, then the element -- each
          // still its own on the canvas, no box round them all.
          controller.pickCopies(e.id, const {});
        } else {
          controller.clearSelection();
        }
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // Cheap unless the stroke or its settings have changed: see
    // _refreshPreview.
    _refreshPreview();
    return _buildStage();
  }

  Widget _buildStage() => LayoutBuilder(
        builder: (context, constraints) {
          _visible = Size(constraints.maxWidth, constraints.maxHeight);
          var content = _contentSize(_visible);
          _viewport = content;
          // Scrolled to where the view is, once laid out at this size.
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncScroll());
          // How much the canvas had to shrink to fit, half of what the percentage
          // on the band means.
          _tellControllerTheScale();

          Widget painter = SizedBox(
            width: content.width,
            height: content.height,
            // Not clipped: the text editor sits in here and a long caption grows
            // past the box it opened in.
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                // A pointer the system takes away ends what it was doing
                // as letting go would, rather than leaving it open.
                onPointerCancel: _onPointerUp,
                onPointerHover: (e) {
                  _updateHover(e.localPosition);
                  _moveBrush(e.localPosition);
                },
                onPointerSignal: _onPointerSignal,
                onPointerPanZoomStart: _onPinchStart,
                onPointerPanZoomUpdate: _onPinchUpdate,
                onPointerPanZoomEnd: _onPinchEnd,
                child: MouseRegion(
                  cursor: _cursor(),
                  onExit: (_) => controller.stagePointer = null,
                  // Clipped to the stage's own box as well as the frame inside it: a
                  // CustomPainter may draw outside its bounds, and a zoomed canvas would
                  // paint over the sidebar, the band and the timeline.
                  child: ClipRect(
                    child: CustomPaint(
                      painter: StagePainter(
                        between: _between,
                        // A tile tried on as the pointer passes is a glimpse too: drawn as a
                        // gesture is, then properly when it is picked or let go of.
                        drafting: controller.interacting || controller.trying,
                        backgrounds: _backgrounds,
                        page: _pageRect,
                        view: _viewRect,
                        levelShown: levelShown,
                        facing: _facingPage,
                        facingFrame: _facingPage == null
                            ? 0
                            : controller.frameOn(_facingPage!),
                        facingOnLeft: _facingOnLeft,
                        facingShown: _spreadShown,
                        // Played as a game: the canvas as the game has it.
                        document: controller.gameView ?? controller.spoken(document),
                        frame: controller.frame,
                        previewAt: controller.previewAt,
                        previewing: controller.previewing,
                        anchors: _anchorsShown(),
                        scale: _scale,
                        origin: _origin,
                        images: controller.images,
                        hoveredButton: controller.hoveredButton,
                        counterValue: controller.counterValue,
                        liveMotion: controller.liveMotion,
                        motionTick: controller.motionTick,
                        // Played or looked through: a 3D stage through its
                        // Camera.
                        directed: (controller.playing || controller.cameraView) &&
                            !document.editingMaster,
                        counterPressed: (e) =>
                            e.id == _hoveredCounter ? _hoveredCounterAt : -1,
                        counterRunning: controller.counterRunning,
                        counterTick: controller.counterTicks,
                        audioState: controller.audioState,
                        videoShow: controller.videoShow,
                        audioRevision: controller.audioRevision,
                        selection: {for (var e in _chosen) e.id},
                        // Its trail and onion skin while the Chain is
                        // open on its motion.
                        trail: controller.motionTrail &&
                            controller.chainShowsMotion,
                        gameChange: controller.gameChange,
                        pickedCopies: controller.selected == null
                            ? const {}
                            : controller.pickedCopiesOf(controller.selected!.id),
                        showHelpers: controller.showHelpers,
                        // The scene's slow move, while it plays (see SceneCamera). Still while
                        // editing, so a press lands where the page looks to be.
                        camera: (controller.playing || controller.cameraView) &&
                                !document.editingMaster
                            // Its Camera, which takes over, or its slow
                            // move: see sceneFraming.
                            ? sceneFraming(document, controller.frame,
                                live: controller.liveMotion)
                            : null,
                        selectedPath: _selectedPath(),
                        // Over a page that scrolls, the rulers are drawn in a
                        // layer that does not.
                        rulersApart: _viewport.width > _visible.width + 0.5 ||
                            _viewport.height > _visible.height + 0.5,
                        spritePaintTick: controller.spritePaint?.tick ?? -1,
                        tilePaintTick: controller.tilePaint?.tick ?? -1,
                        editingLayers: _layerBoxes(),
                        editingVector: switch (controller.editingVector) {
                          var v? => (
                              element: v,
                              shape: controller.vectorShape,
                              pick: controller.vectorPick,
                              picks: controller.vectorPicks,
                              // The tint brush picks nothing, so the points and the box round them
                              // are put away (and the pencil's, unless it is set to show them); and
                              // while the line's thickness is dragged, the line is watched.
                              bare: _mode == _DragMode.vectorScale ||
                                  controller.vectorTool == VectorTool.shapes ||
                                  // Shapes picked whole: their box, not
                                  // their points.
                                  _picksShapes ||
                                  // Typing: the letters, not their points.
                                  controller.vectorTool == VectorTool.text ||
                                  controller.vectorTool == VectorTool.tint ||
                                  controller.vectorTool == VectorTool.shadow ||
                                  controller.vectorTool ==
                                      VectorTool.highlight ||
                                  controller.vectorTool == VectorTool.eraser ||
                                  (controller.vectorTool == VectorTool.pencil &&
                                      !controller.vectorPencilPoints),
                              // The shapes tool's box round the shape picked.
                              turnable: _picksShapes,
                              shapeBox: _picksShapes
                                  ? itemsExtent(v, controller.vectorItems)
                                  : controller.vectorTool ==
                                              VectorTool.shapes &&
                                          controller.vectorShapeMade >= 0
                                      ? groupExtent(
                                          v,
                                          groupStarts(v).indexOf(groupOf(
                                              v, controller.vectorShapeMade)))
                                      : null,
                              // The pencil's mirror lines, while it is out.
                              mirror: controller.vectorTool == VectorTool.pencil
                                  ? (
                                      across: controller.vectorMirrorAcross,
                                      down: controller.vectorMirrorDown
                                    )
                                  : null,
                              combining:
                                  controller.vectorTool == VectorTool.boolean
                                      ? controller.vectorCombining
                                      : null,
                              // While a box is dragged across it, every point
                              // is shown, and those in the box lit.
                              boxing: _mode == _DragMode.vectorMarquee &&
                                  _marquee != null,
                              boxed: _mode == _DragMode.vectorMarquee &&
                                      _marquee != null
                                  ? picksIn(v, _marquee!)
                                  : const <VectorPick>{},
                            ),
                          null => null,
                        },
                        chartLabels: _selectedChartLabels(),
                        tableColumns: _selectedTableColumns(),
                        editingText: _editingText,
                        editingItem: _editingItem,
                        preview: _preview,
                        previewOn: _previewPlacement(),
                        liveStroke: _liveCanvas,
                        knife: _knife,
                        caret: _caret(),
                        liveStrokeRadius: _liveRadius,
                        liveStrokeKeeps: controller.retouch.keeps,
                        selectionBounds: _selectionBounds,
                        framing: _framingView(),
                        guides: document.guides,
                        snapped: _snappedTo,
                        showHandles: _selectionHasOwnGeometry,
                        selectionRotation: _rotationOfSelection,
                        touchAreas: _touchAreas(),
                        selectionSkew: _skewOfSelection,
                        handleFor: _handlePosition,
                        flowGrips: _flowGrips(),
                        flowLines: _flowLines(),
                        showAllBounds: controller.showAllBounds,
                        flowDrag: _flowDragLine(),
                        marquee: _marquee,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              )),
              // The gizmo on an element standing on a 3D stage.
              if (_gizmo() case var g?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: StageGizmoPainter(g,
                          hot: _gizmoDrag?.$2 ?? _gizmoHot,
                          scale: _scale,
                          origin: _origin),
                    ),
                  ),
                ),
              if (_editorFor() case var editor?) editor,
              if (_typingField() case var typing?) typing,
              if (_brushRing() case var ring?) ring,
              if (_cellEditorFor() case var cell?) cell,
              if (_counterInputFor() case var setting?) setting,
            ]),
          );

          // Only scrollable when there is something to scroll: a scroll view that
          // never scrolls still claims the wheel, which is how the pan tool zooms.
          // The bar that runs down is the inner view's, drawn at the window's
          // edge.
          var down = content.height > _visible.height + 0.5;
          var across = content.width > _visible.width + 0.5;
          if (down && across) {
            painter = Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              notificationPredicate: (n) => n.depth == 1,
              child: Scrollbar(
                controller: _scrollX,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollX,
                  scrollDirection: Axis.horizontal,
                  physics: _scrollPhysics,
                  child: SizedBox(
                    width: content.width,
                    height: _visible.height,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      physics: _scrollPhysics,
                      child: painter,
                    ),
                  ),
                ),
              ),
            );
          } else if (down) {
            painter = Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                physics: _scrollPhysics,
                child: painter,
              ),
            );
          } else if (across) {
            painter = Scrollbar(
              controller: _scrollX,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollX,
                scrollDirection: Axis.horizontal,
                physics: _scrollPhysics,
                child: painter,
              ),
            );
          }
          // A drag on the page (a finger's, a pen's, a mouse's) is the canvas's:
          // drawing, moving, picking. The page is scrolled by its bars, the wheel
          // and two fingers on a trackpad.
          if (down || across) {
            painter = ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(dragDevices: {PointerDeviceKind.trackpad}),
              child: painter,
            );
          }
          // Over a page that scrolls, the rulers in a layer that does not.
          if ((down || across) &&
              document.guides.showRulers &&
              document.guides.rulers.any) {
            painter = Stack(children: [
              Positioned.fill(child: painter),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_scroll, _scrollX]),
                    builder: (context, _) => CustomPaint(
                      painter: _RulerLayer(
                          guides: document.guides,
                          sheet: document.size.size,
                          scale: _scale,
                          origin: _origin - _scrolled,
                          page: _pageRect.shift(-_scrolled)),
                    ),
                  ),
                ),
              ),
            ]);
          }

          // The 3D view controls, at the right of a scene showing a stage, over
          // the page and still however it scrolls. Not while it plays. Always in
          // a Stack, so the page under them is not rebuilt as they come and go.
          painter = Stack(children: [
            Positioned.fill(child: painter),
            if (controller.onStage3d &&
                controller.stageNav != StageNav.none &&
                !controller.playing &&
                !controller.gaming)
              Positioned(
                right: 10,
                top: 10,
                child: StageNavControls(controller: controller),
              ),
          ]);

          return Focus(focusNode: _focus, onKeyEvent: _onKey, child: painter);
        },
      );

  /// _touchAreas are what a game touches of each element played, while the
  /// Game tab is open and the game is not being played.
  List<Rect> _touchAreas() {
    if (!controller.gameTabOpen || controller.gaming || !document.game) {
      return const [];
    }
    var frame = controller.frame;
    return [
      for (var e in document.elements)
        if (e.visible && e.base.play.as != PlayAs.none)
          gameTouchArea(e, e.movedBoundsAt(frame, document, live: controller.liveMotion)),
    ];
  }

  /// _cellEditorFor is the overlay for a cell being typed into: see
  /// CanvasCellEditor.
  Widget? _cellEditorFor() {
    var editing = _editingCell;
    if (editing == null) return null;
    var (id, row, col) = editing;
    var element = document.elementById(id);
    if (element is! TableElement) return null;

    var box =
        tableCellRect(element, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), row, col);
    var topLeft = _toStage(box.topLeft);
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: math.max(40, box.width * _scale),
      height: math.max(20, box.height * _scale),
      child: CanvasCellEditor(
        key: ValueKey("cell-$id-$row-$col"),
        value: element.cell(row, col),
        fontSize: math.max(9, element.cellSpec.fontSize * _scale),
        onChanged: (text) {
          controller.beginInteraction();
          controller.replaceElement(tableWithCell(element, row, col, text),
              transient: true);
        },
        onDone: () {
          controller.endInteraction();
          if (mounted) setState(() => _editingCell = null);
        },
        onPickPicture: () async {
          var asset = await pickCanvasImage(context);
          if (asset == null || !mounted) return;
          controller.beginInteraction();
          controller.replaceElement(tableWithCell(
              element, row, col, "${TableElement.pictureCell}$asset"));
          controller.endInteraction();
          setState(() => _editingCell = null);
        },
      ),
    );
  }

  /// _editorFor is the text editor overlay, when one is open: built here
  /// because it sits in the painting's coordinates, which only the stage
  /// knows.
  Widget? _editorFor() {
    var id = _editingText;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! TextElement) return null;

    // One of the element's own pieces, where the second click landed on
    // one, held open by its id: the element and its list are rebuilt on
    // every keystroke.
    var itemId = _editingItem;
    var at = itemId == null
        ? -1
        : element.items.indexWhere((item) => item.id == itemId);
    var item = at < 0 ? null : element.items[at];

    var box = _editorRect ??=
        item == null ? _editorBoxFor(element) : _itemEditorBoxFor(element, at);
    var topLeft = _toStage(box.topLeft);
    return CanvasTextEditor(
      key: ValueKey("edit-$id-${item?.id ?? ""}"),
      element: element,
      item: item,
      rect: Rect.fromLTWH(
          topLeft.dx, topLeft.dy, box.width * _scale, box.height * _scale),
      scale: _scale,
      onChanged: (text) {
        controller.beginInteraction();
        controller.replaceElement(
            item == null
                ? element.copyWith(text: text)
                : element.copyWith(items: [
                    for (var (i, it) in element.items.indexed)
                      i == at ? it.copyWith(text: text) : it,
                  ]),
            transient: true);
      },
      onDone: () {
        controller.endInteraction();
        if (mounted) {
          setState(() {
            _editingText = null;
            _editingItem = null;
            _editorRect = null;
          });
        }
      },
    );
  }

  /// _itemEditorBoxFor is the rectangle an item's editor opens in: where the
  /// piece is drawn, with room to type into.
  Rect _itemEditorBoxFor(TextElement element, int at) {
    var bounds = element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    var rect = textItemRects(element, bounds)[at];
    var item = element.items[at];
    var inner = element.box.inner(bounds);
    if (rect.isEmpty) rect = Rect.fromLTWH(inner.left, inner.top, 0, 0);

    return _grownForTyping(rect, item.slot.across, inner,
        item.spec.fontSize * item.spec.lineHeight);
  }

  /// _grownForTyping is a block's rectangle with room to write in, grown from
  /// the edge its slot holds it to, so the words stay put.
  Rect _grownForTyping(
      Rect rect, TextAlignSpec across, Rect inner, double line) {
    var width = math.max(rect.width, math.max(line * 6, inner.width * 0.4));
    width = math.min(width, inner.width);
    var height = math.max(rect.height, line * 1.4);
    var left = switch (across) {
      TextAlignSpec.right => rect.right - width,
      TextAlignSpec.center => rect.center.dx - width / 2,
      _ => rect.left,
    };
    return Rect.fromLTWH(left, rect.top, width, height);
  }

  /// _editorBoxFor is the rectangle the editor opens in: over the words,
  /// wherever they are (text riding a line is not in its own rectangle), but
  /// not tight round them. A minimum leaves room to type, grown about its
  /// centre so what is there stays put.
  Rect _editorBoxFor(TextElement element) {
    var box = _visualBounds(element);
    // The element's own words in a slot are a block in the box, so the
    // editor opens over the block, not the whole box. See TextElement.slot.
    if (bodyIsBlock(element)) {
      var bounds = element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
      var rect = textBodyRect(element, bounds);
      if (rect != null) {
        return _grownForTyping(
            rect,
            element.slot!.across,
            element.box.inner(bounds),
            element.textSpec.fontSize * element.textSpec.lineHeight);
      }
    }
    if (element.curve == null) return box;

    var line = element.textSpec.fontSize * element.textSpec.lineHeight;
    var wanted = Size(
      math.max(box.width, math.max(line * 8, document.size.width * 0.3)),
      // Room for a few lines, so a caption that runs on has somewhere to go.
      math.max(box.height, line * 3),
    );
    return Rect.fromCenter(
      center: box.center,
      width: wanted.width,
      height: wanted.height,
    );
  }

  /// _onPointerSignal decides whether the wheel belongs to this stage or to
  /// the scroll view round it. The pan tool claims it through the resolver,
  /// so zooming wins; the select tool does not, so a tall fit-width canvas
  /// scrolls with the wheel.
  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    // Locked, the wheel is claimed before the scroll views see it: on a
    // stage it steers the camera, on a page it does nothing.
    if (controller.pageLocked) {
      GestureBinding.instance.pointerSignalResolver.register(
          signal, (event) => _steerByScroll(event as PointerScrollEvent));
      return;
    }
    if (controller.tool != CanvasTool.pan || controller.onStage3d) return;
    GestureBinding.instance.pointerSignalResolver
        .register(signal, (event) => _onScroll(event as PointerScrollEvent));
  }

  MouseCursor _cursor() {
    // Placing copies: a click puts one down.
    if (controller.placingCopies != null) return SystemMouseCursors.copy;
    if (controller.retouch.on && _selectedPicture() != null) {
      return SystemMouseCursors.precise;
    }
    if (controller.editingImage != null &&
        (controller.imageTool.masks || controller.imageTool.paints)) {
      return SystemMouseCursors.precise;
    }
    if (_mode == _DragMode.pan) return SystemMouseCursors.grabbing;
    if (_mode == _DragMode.stageOrbit || _mode == _DragMode.stagePan) {
      return SystemMouseCursors.grabbing;
    }
    if (_mode == _DragMode.gizmo) return SystemMouseCursors.grabbing;
    if (_gizmoHot != null) return SystemMouseCursors.grab;
    if (controller.tool == CanvasTool.pan && !controller.onStage3d) {
      return SystemMouseCursors.grab;
    }
    // Drawing with the pencil, the pointer is the brush's ring and nothing
    // more.
    if (controller.editingVector != null &&
        controller.vectorTool == VectorTool.eraser) {
      return SystemMouseCursors.none;
    }
    if (controller.sampling) return SystemMouseCursors.precise;
    if (controller.editingVector != null &&
        controller.vectorTool == VectorTool.knife) {
      return SystemMouseCursors.precise;
    }
    if (controller.editingVector != null &&
        controller.vectorTool == VectorTool.pencil) {
      // Filling, it is a point to click on; drawing, the brush's ring.
      return controller.vectorQuickFill
          ? SystemMouseCursors.precise
          : SystemMouseCursors.none;
    }
    if (_mode == _DragMode.rotate) return SystemMouseCursors.grabbing;
    if (_mode == _DragMode.move) return SystemMouseCursors.move;
    // A ruler is a place to pull a guide out of, so it says so on approach.
    if (_mode == _DragMode.guide) return SystemMouseCursors.grabbing;
    if (_rulerUnder(_hoverAt) case var axis?) {
      return axis == GuideAxis.vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown;
    }
    // A picture being reframed is grabbable everywhere inside it, and
    // saying so tells the reader they are in a mode.
    if (_framing != null) {
      return _mode == _DragMode.imageFrame
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab;
    }
    if (_mode == _DragMode.none && _hoverPressable) {
      return SystemMouseCursors.click;
    }
    return SystemMouseCursors.basic;
  }
}

/// _RulerLayer draws the stage's rulers over a page that scrolls, at the
/// edges of the window: see paintStageRulers.
class _RulerLayer extends CustomPainter {
  final CanvasGuides guides;
  final Size sheet;
  final double scale;
  final Offset origin;
  final Rect page;
  const _RulerLayer(
      {required this.guides,
      required this.sheet,
      required this.scale,
      required this.origin,
      required this.page});

  @override
  void paint(Canvas canvas, Size size) =>
      paintStageRulers(canvas, size, guides, sheet, scale, origin, page);

  @override
  bool shouldRepaint(_RulerLayer old) =>
      old.guides != guides ||
      old.sheet != sheet ||
      old.scale != scale ||
      old.origin != origin ||
      old.page != page;
}
