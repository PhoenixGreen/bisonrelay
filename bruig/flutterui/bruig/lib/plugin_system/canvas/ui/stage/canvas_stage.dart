import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_painter.dart';
import 'package:bruig/plugin_system/canvas/render/code_run_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/code/code_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/code/code_live_preview.dart';
import 'package:bruig/plugin_system/canvas/model/elements/metronome_element.dart';
import 'package:bruig/plugin_system/canvas/render/metronome_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/synth_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:clock/clock.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/ui/stage/orbit_pad.dart';
import 'package:bruig/plugin_system/canvas/model/elements/camera_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/background_element.dart';
import 'package:bruig/plugin_system/canvas/render/motion_document.dart';
import 'package:bruig/plugin_system/canvas/render/instrument_painter.dart';
import 'package:bruig/plugin_system/canvas/render/score_sheet.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_camera.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_gizmo.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_nav_controls.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_note.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/marker_panel.dart'
    show replaceMarker;
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_snap.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
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
import 'package:bruig/plugin_system/canvas/ui/stage/quick_fill.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/tablet_input.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_editing.dart';
import 'package:bruig/plugin_system/canvas/render/adjust_painter.dart';
import 'package:bruig/plugin_system/canvas/render/layer_effects.dart';
import 'package:bruig/plugin_system/canvas/render/brush_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/image_masking.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_mask.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_strokes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_layers.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_items.dart';
import 'package:bruig/plugin_system/canvas/ui/drawing/vector_shapes.dart';
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
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart'
    show MotionEditing;
import 'package:bruig/plugin_system/canvas/ui/game/canvas_game.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

// canvas_stage.dart is the canvas you can touch: the document drawn through
// the export's scene_renderer.dart, with handles over it and every gesture
// that moves something. stage_painter.dart draws; stage_parts.dart answers
// drags on a piece inside an element; stage_geometry.dart holds shared sizes.
// Pointer positions go from stage (screen) space to document space once, at
// the top of each handler; handles stay in stage space, one size at any zoom.

/// _DragMode is what the pointer is currently doing.
enum _DragMode {
  none,

  /// synthKnob is a synth module's knob turned by a drag up or down, and
  /// synthCable a cable carried from a jack. See _pressSynth.
  synthKnob,
  synthCable,

  /// synthScreen is a digital envelope's or filter's screen dragged on.
  synthScreen,

  /// codeDivider is a Code panel's pane divider dragged; codeTab one of its
  /// tabs carried. See _pressCode.
  codeDivider,
  codeTab,

  /// codeScrub is a Code panel's playbar track dragged along.
  codeScrub,

  /// copies is copies of an element dragged on their own: those picked, or
  /// made by an Alt-drag. See _moveCopies.
  copies,

  /// skew is a side handle dragged to slant the element. See _applySkew.
  skew,

  /// copySize and copyTurn size or turn the one copy picked (see _oneCopy)
  /// by its own handles. See _applyCopyBox.
  copySize,
  copyTurn,

  /// warpMove, warpScale and warpTurn move, size or turn a warp grid's
  /// picked points; warpMarquee picks points with a box.
  warpMove,
  warpScale,
  warpTurn,
  warpMarquee,

  /// anchor is an element's anchor point dragged. See ElementBase.anchorX.
  anchor,
  move,
  resize,
  rotate,
  marquee,
  pan,
  player,
  node,
  handle,

  /// spritePaint is a Sprite's frame being painted: see sprite_painting.dart.
  spritePaint,

  /// tilePaint is a Tile map being painted -- see tile_painting.dart.
  tilePaint,

  /// stageOrbit is a 3D stage's camera being swung round it, by a drag with
  /// Option held anywhere on the stage, or with none, the page locked.
  stageOrbit,

  /// stagePan is a 3D stage's camera being slid sideways and up, by a
  /// shifted or middle-button drag with the page locked.
  stagePan,

  /// gizmo is a part of the stage gizmo dragged: see stage_gizmo.dart.
  gizmo,

  /// parallaxPan is parallax scenery panned by an Option-drag on it.
  parallaxPan,

  /// chartLabel is a chart's title or description moved or resized.
  chartLabel,

  /// tableColumn is the rule between two table columns dragged.
  tableColumn,

  /// counterPart is one of a counter's freely placed pieces moved inside it.
  counterPart,

  /// imageFrame is a picture moved inside its frame: only which part the
  /// frame shows changes. See ImageFraming.
  imageFrame,

  /// imageLayerMove, imageLayerSize and imageLayerTurn move, resize or turn a
  /// picture layer while its layers are edited. See image_layers.dart.
  imageLayerMove,
  imageLayerSize,
  imageLayerTurn,

  /// imageMask is a mask mark: a brush stroke, a lasso or a gradient.
  imageMask,

  /// imageQuick is a quick-select stroke being drawn.
  imageQuick,

  /// imageBrush is a paint or retouching stroke being drawn.
  imageBrush,

  /// flow is a link pulled from a text box's overflow grip to another box.
  flow,

  /// guide is a guide line moved, or a new one pulled from a ruler.
  guide,

  /// vectorPoint is a drawing's point or handle dragged.
  vectorPoint,

  /// vectorPoints is several picked points dragged together; vectorMarquee a
  /// box dragged to pick points.
  vectorPoints,
  vectorMarquee,

  /// vectorPen is the pen's new point, its handles pulled out by the drag.
  vectorPen,

  /// vectorScale is picked points scaled; vectorTint the tint tool colouring
  /// each point it meets.
  vectorScale,
  vectorTint,

  /// vectorCorner is a corner being rounded, the drag setting how far.
  vectorCorner,

  /// vectorPencil is a pencil stroke; vectorErase the pen's eraser.
  vectorPencil,

  /// vectorKnife is the knife's line through a drawing. See vector_cut.dart.
  vectorKnife,
  vectorErase,

  /// vectorRub is the eraser rubbing out what it goes over.
  vectorRub,

  /// vectorShapeDraw is a shape dragged out with the shapes tool;
  /// vectorShapeFit the picked one moved or resized by its box.
  vectorShapeDraw,
  vectorShapeFit,

  /// vectorItems is the picked shapes moved, sized or turned by their box.
  vectorItems,

  /// vectorItemsBox is a box dragged to pick the shapes it touches.
  vectorItemsBox,
}

class CanvasStage extends StatefulWidget {
  final CanvasController controller;

  /// onButtonLink is called when a link button is pressed in the editor:
  /// leaving the app is not the canvas's decision.
  final void Function(String url)? onButtonLink;

  const CanvasStage({required this.controller, this.onButtonLink, super.key});

  @override
  State<CanvasStage> createState() => CanvasStageState();
}

/// CanvasStageState is public so the screen can ask, through a key, where in
/// document space a sidebar drop landed: only the stage knows the transform.
class CanvasStageState extends State<CanvasStage>
    with SingleTickerProviderStateMixin {
  CanvasController get controller => widget.controller;
  CanvasDocument get document => controller.document;

  _DragMode _mode = _DragMode.none;

  /// _playerIndex is which player of the selected team is dragged. The team
  /// stays selected: a player is a row of its list, not an element.
  int _playerIndex = -1;

  /// _playerGrab is where in the dot the pointer took hold, so a player does
  /// not jump to centre under the cursor.
  Offset _playerGrab = Offset.zero;

  /// _pendingButton is a selected button pressed: it runs on release, unless
  /// the press became a drag.
  ButtonElement? _pendingButton;

  /// _noteWas is the marker whose canvas label is dragged (sized by its grip
  /// if [_noteSizing]), as it was at the press; _noteFrom where it began.
  TimelineAction? _noteWas;
  bool _noteSizing = false;
  Offset _noteFrom = Offset.zero;

  /// _pendingCounter and _pendingCounterAt are a live counter's button
  /// pressed: a press that becomes a drag moves the counter instead.
  CounterElement? _pendingCounter;
  int _pendingCounterAt = -1;

  /// _pendingCodeEdit is a Code pane pressed: released in place, it opens.
  (String, int)? _pendingCodeEdit;

  /// _pendingAudio is a selected speaker pressed on a control: which, and
  /// where (the volume bar needs how far along).
  AudioElement? _pendingAudio;

  /// _keyDown is an instrument's key held under the pointer.
  (AudioElement, int)? _keyDown;

  /// _synthKey is a synth keyboard key held; _synthKnob a knob turned (its
  /// module, knob, start value and press point); _synthCable a cable carried
  /// (from which jack, the cable it was lifted from if any, and where it is).
  (SynthModuleElement, int)? _synthKey;
  (String, SynthKnob, double, Offset)? _synthKnob;

  /// _synthScreen is a digital module's screen dragged: its module and what
  /// was taken (see synthScreenGrab).
  (String, String)? _synthScreen;

  /// _codeDivider is a Code panel's pane divider dragged (panel id, line).
  /// _codeTab is a tab pressed (panel, pane, file); _codeTabAt where it has
  /// been carried on the page.
  (String, CodeDividerBox)? _codeDivider;
  ({String id, int pane, String file})? _codeTab;
  Offset? _codeTabAt;

  /// _codeScrub is the Code panel whose playbar track is being dragged.
  String? _codeScrub;

  /// _codeOver is the Code pane under the pointer, which the wheel and two
  /// fingers scroll instead of the page; _codePinch one a slide began over.
  (String, int)? _codeOver;
  (String, int)? _codePinch;

  /// _inLive is a press that began on a live preview, left to the preview.
  bool _inLive = false;

  /// _codeEditBegun is whether the code editor has begun its undo step.
  bool _codeEditBegun = false;
  ({
    SynthModuleElement from,
    String port,
    bool out,
    (SynthModuleElement, String)? lifted,
    Offset at,
  })? _synthCable;

  /// _pendingSheet is a selected score sheet pressed: let go in place, the
  /// playhead goes to the note there (see sheetPressed).
  SheetElement? _pendingSheet;
  Offset _pendingSheetAt = Offset.zero;

  /// _pendingVideo is the same for a selected video's controls.
  VideoElement? _pendingVideo;
  VideoPart _pendingVideoPart = VideoPart.picture;
  Offset _pendingVideoAt = Offset.zero;
  AudioControl _pendingAudioPart = AudioControl.playPause;
  Offset _pendingAudioAt = Offset.zero;

  /// _pendingLegend is a chart whose key was pressed, and _pendingLegendAt
  /// which entry: a press that becomes a drag moves the chart instead.
  ChartElement? _pendingLegend;
  int _pendingLegendAt = -1;

  /// _legendHold times a key held down for _legendHoldDelay, after which it
  /// can be moved: press and drag are taken, and a key has no grip.
  Timer? _legendHold;
  static const Duration _legendHoldDelay = Duration(milliseconds: 400);

  /// _settingCounter and _settingAt are the counter Set button typed into.
  String? _settingCounter;
  int _settingAt = -1;

  /// _hoveredCounter and _hoveredCounterAt are the counter button hovered.
  String? _hoveredCounter;
  int _hoveredCounterAt = -1;

  /// _buttonClickSlop is how far a click may move and not be a drag.
  static const double _buttonClickSlop = 4;

  /// _dragThreshold is how far, in screen pixels, a press travels before it
  /// is a drag, so a click does not move what it selects. Drags then measure
  /// from the press itself, so what is dragged stays where it was picked up.
  static const double _dragThreshold = 4;

  /// _travelled is whether the press in hand has passed that threshold.
  bool _travelled = false;

  /// _lastClickAt and _doubleClickWindow spot a double click by hand: a
  /// double-tap recogniser would delay every single tap.
  DateTime _lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _doubleClickWindow = Duration(milliseconds: 400);

  /// _lastVectorClick is the last press on a drawing, for its double-click.
  Offset _lastVectorClick = Offset.infinite;

  /// _thicknessReach is how near, on screen, the thickness tool's drag must
  /// pass a point to take it in.
  static const double _thicknessReach = 24;

  /// _penPullMin is how far, on screen, the pen must be dragged as a point
  /// goes down to pull a curve out of it.
  static const double _penPullMin = 8;

  /// _framing is the picture being moved inside its frame, if one is: layers
  /// open with the base picture picked and the move tool in hand. Opened by
  /// double-clicking a selected picture; a plain drag moves the element.
  String? get _framing {
    var e = controller.editingImage;
    // Layered, the base picture has a place of its own (see
    // ImageLayer.basePlace), so there is no framing.
    if (e == null ||
        !e.hasImage ||
        e.layered ||
        controller.imageLayer != baseLayerId ||
        controller.imageTool != ImageTool.move) {
      return null;
    }
    return e.id;
  }

  /// _layersMoved are the other picked layers a move carries, as they began.
  List<ImageLayer> _layersMoved = const [];

  /// _layerStart is the dragged picture layer as it was at the start, and
  /// _layerHandle the handle held (see boxHandles).
  ImageLayer? _layerStart;
  int _layerHandle = -1;

  /// _maskOn is the picture a mark is being made on, while one is.
  LayerPicture? _maskOn;

  /// _strokeAt turns a canvas point into one of the stroke being drawn (a
  /// fraction of the frame for paint, of the picture for retouching).
  Offset Function(Offset)? _strokeAt;

  /// _quickTrail is a quick-select stroke in fractions of the picture, and
  /// _quickSubtract whether it takes away; it is cut when let go.
  List<Offset> _quickTrail = const [];
  bool _quickSubtract = false;

  int _guideIndex = -1;

  /// _framingStart is the framing at the drag's start: no rounding builds up.
  ImageFraming _framingStart = const ImageFraming();

  /// _pressedAt is where the pointer went down, in stage coordinates.
  Offset _pressedAt = Offset.zero;

  /// _painting is the picture being retouched during a brush stroke, by id,
  /// since the element is replaced when the stroke lands.
  String? _painting;

  /// _liveImage and _liveCanvas are the stroke being drawn, in the picture's
  /// coordinates for storing and the canvas's for showing. It is written to
  /// the element only on pointer up: each write rebuilds the treated picture.
  final List<Offset> _liveImage = [];
  final List<Offset> _liveCanvas = [];

  /// _liveRadius is the brush radius in canvas units, set once per stroke.
  double _liveRadius = 0;

  /// _preview is a picture of what the held stroke would do, and _previewOf
  /// the settings it was made for: rebuilt as they change, so adjusting
  /// hardness or cling redraws the same stroke.
  ui.Image? _preview;
  String? _previewOf;

  /// _previewDebounce waits for the settings to settle: otherwise each
  /// keystroke or scrub pixel starts a full pass and an image decode.
  Timer? _previewDebounce;

  /// _previewDelay spans the gap between keystrokes yet still feels prompt.
  static const Duration _previewDelay = Duration(milliseconds: 220);

  /// _editorRect is where the editor opened, in document space, frozen: for
  /// text on a line the box follows the letters, which move as you type.
  Rect? _editorRect;

  /// _editingCell is the table cell typed into, or null: a record, since a
  /// cell has no identity and its table is the selection.
  (String, int, int)? _editingCell;

  /// _editingText is the text element typed into, or null: by id, since the
  /// element is replaced on every keystroke.
  String? _editingText;

  /// _editingItem is the id of the element's extra piece typed into, or null
  /// for its own paragraph. See TextItem.
  String? _editingItem;

  /// _nodeIndex is the selected path's point being dragged, and
  /// _nodeHandleOut which handle, when a handle is. The path stays selected.
  int _nodeIndex = -1;

  bool _nodeHandleOut = false;

  StageHandle? _handle;

  /// _flowFrom is the box a link is dragged from; _flowAt the pointer.
  String? _flowFrom;
  Offset? _flowAt;

  /// _dragStart is where the gesture began, in document space, and
  /// _startBounds the selection then: kept so rounding does not accumulate.
  Offset _dragStart = Offset.zero;

  /// _orbiting is the stage an Option-drag is orbiting, with the camera as
  /// it was and where the drag began.
  String? _orbiting;
  StageCamera? _orbitFrom;
  ParallaxCamera? _panFrom;
  Offset _orbitAt = Offset.zero;
  Map<String, Rect> _startBounds = {};

  /// _startPosed is each element's place at the start: see _beginTransform.
  Map<String, Rect> _startPosed = {};

  /// _startVisual is the box the handles were on. See _beginTransform.
  Map<String, Rect> _startVisual = {};

  /// _startElements are the selection at the start, for a scaling resize.
  Map<String, CanvasElement> _startElements = {};
  Map<String, double> _startRotation = {};
  Offset _startPan = Offset.zero;
  Rect? _marquee;

  @visibleForTesting
  Rect? get marqueeForTest => _marquee;

  /// _visible is the room on screen the stage was laid out into.
  Size _visible = Size.zero;

  /// _viewport is the box the canvas is drawn into: [_visible] while the page
  /// fits, bigger when zoomed past the window or fitted to a width taller
  /// than it; the difference is scrolled.
  ///
  /// This file and the pointer events (the Listener is inside the scroll
  /// views) work in its coordinates, except [toDocumentPoint] and the test
  /// getters, which use widget coordinates.
  Size _viewport = Size.zero;

  /// _scroll and _scrollX scroll the page down and across.
  final ScrollController _scroll = ScrollController();
  final ScrollController _scrollX = ScrollController();

  Offset get _scrolled => Offset(_scrollX.hasClients ? _scrollX.offset : 0,
      _scroll.hasClients ? _scroll.offset : 0);

  /// _stageMargin is the gap kept round the whole canvas.
  static const double _stageMargin = 24;

  /// _overspillFraction is how much world beyond the page shows when
  /// CanvasController.showOverspill is on, as a fraction of the page.
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
    // Pen pressure and tilt, which some platforms pass only via the runner.
    TabletInput.instance.start();
    controller.addListener(_onChanged);
    controller.images.addListener(_onChanged);
    controller.keysHeld.addListener(_onChanged);
    _scroll.addListener(_followScroll);
    _scrollX.addListener(_followScroll);
    // Counters set to start running do; a stopwatch waits.
    controller.startCounters();
    // Shaders loaded once for the app. Until the key shader lands a keyed
    // video is drawn unkeyed; this repaints when it does.
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

  /// _between is how far past its frame the playhead is, updated each screen
  /// refresh while a drift plays. See scene_renderer's betweenFrames.
  final ValueNotifier<double> _between = ValueNotifier(0);
  Ticker? _betweenTicker;

  /// _followPlayback runs _betweenTicker while a drift plays.
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
    // The controller closes a picture's layers when the selection moves off it.
    if (!mounted) return;
    _followPlayback();
    setState(() {});
  }

  // ------------------------------------------------------------------------
  // Coordinates
  // ------------------------------------------------------------------------

  /// _fitScale is the scale at which the whole canvas fits, with
  /// [_stageMargin] to spare. Worked out on every build: it changes with the
  /// window and sidebar, which the controller does not know.
  double get _fitScale {
    var size = document.size.size;
    if (size.width <= 0 || size.height <= 0) return 1;
    // A spread is two pages across: only the width makes room.
    var across = size.width * (_spreadShown ? 2 : 1);
    var byWidth = (_visible.width - _stageMargin * 2) / across;
    // Fit to width ignores the height: a 9:16 story would be a narrow strip.
    var fit = controller.fit == CanvasFit.width
        ? byWidth
        : math.min(byWidth, (_visible.height - _stageMargin * 2) / size.height);
    // The page gives up room for the overspill, not the margin.
    if (controller.showOverspill) fit /= 1 + _overspillFraction * 2;
    return fit.isFinite && fit > 0 ? fit : 1;
  }

  /// _viewRect is everything drawn: the page, plus overspill when showing.
  /// Clipped and hit-tested against, so off-page elements are grabbable
  /// exactly when seen.
  Rect get _viewRect {
    var page = _pageRect;
    // The neighbour's half of the spread, on its own side. The edited page
    // keeps its frame and origin, so the pointer code knows of one leaf.
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
    // A game's level, drawn, grabbable and scrollable while not played.
    if (_level case var level?) {
      shown = shown.expandToInclude(
          Rect.fromPoints(_toStage(level.topLeft), _toStage(level.bottomRight)));
    }
    return shown;
  }

  /// _level is a game scene's reach past the page, in document units, so it
  /// can be scrolled to; null if it fits, for a non-game, and during play.
  Rect? get _level {
    if (!document.game || controller.gaming || document.editingMaster) {
      return null;
    }
    // Asked several times a build: cached per document, frame and live clock.
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

  /// levelShown is whether a game's level reaches past the page.
  bool get levelShown => _level != null;

  /// _contentSize is the room the canvas and margins need, the excess over
  /// the visible box scrolled.
  Size _contentSize(Size visible) {
    if (visible.width <= 0 || visible.height <= 0) return visible;
    var spill = controller.showOverspill ? 1 + _overspillFraction * 2 : 1.0;
    var page = document.size.size * _scale;
    var wide = page.width * spill * (_spreadShown ? 2 : 1) + _stageMargin * 2;
    var tall = page.height * spill + _stageMargin * 2;
    // A game's level: the page stays centred, so each side gets as much room
    // as the level reaches past the far side.
    if (_level case var level?) {
      var doc = document.size.size;
      var across = math.max(-level.left, level.right - doc.width) * _scale;
      var down = math.max(-level.top, level.bottom - doc.height) * _scale;
      wide = math.max(wide, page.width + across * 2 + _stageMargin * 2);
      tall = math.max(tall, page.height + down * 2 + _stageMargin * 2);
    }
    // Zoomed, room to move it about: half a window past its edges, so it can
    // be lifted clear of the timeline and mixer. Unzoomed it stays centred.
    if ((controller.zoom - 1).abs() > 0.001) {
      wide = math.max(wide, visible.width * 2 - wide) + visible.width;
      tall = math.max(tall, visible.height * 2 - tall) + visible.height;
    }
    return Size(math.max(visible.width, wide), math.max(visible.height, tall));
  }

  /// _facingPage is the page drawn beside the edited one, or null when it
  /// stands alone (scenes, facing pages off, a cover, the first leaf, or the
  /// master, which would otherwise look different by where it was opened
  /// from). See CanvasDocument.facingAt. The neighbour is only drawn.
  int? get _facingPage =>
      document.editingMaster ? null : document.facingAt(document.at);

  /// _bookPreview is whether the document plays as a book: every leaf drawn
  /// in its spread place, so a transition between spreads moves both.
  bool get _bookPreview => controller.previewAt != null && document.hasSpread;

  /// _spreadShown is whether room is given to the facing leaf. Fitted to
  /// width there is none, but the neighbour is still drawn, since a picture
  /// across the gutter is part of this page.
  bool get _spreadShown =>
      (_facingPage != null || _bookPreview) &&
      controller.fit != CanvasFit.width;

  /// _facingOnLeft is whether the edited page is the left leaf.
  bool get _facingOnLeft {
    if (_bookPreview) return document.spreadOf(document.at)?.$1 == document.at;
    if (document.editingMaster) return false;
    return document.facingIsLeft(document.at) ?? false;
  }

  /// _onFacingPage is whether a stage point is over the facing leaf.
  bool _onFacingPage(Offset stage) {
    if (!_spreadShown) return false;
    var page = _pageRect;
    if (stage.dy < page.top || stage.dy > page.bottom) return false;
    return _facingOnLeft ? stage.dx > page.right : stage.dx < page.left;
  }

  /// _pageRect is the page on screen at [_scale], centred in the viewport.
  Rect get _pageRect {
    var size = document.size.size * _scale;
    // The spread is centred, the edited page taking its half, so it does not
    // shift when the edited page changes sides.
    var across = !_spreadShown
        ? 0.0
        : (_facingOnLeft ? -size.width / 2 : size.width / 2);
    return Rect.fromCenter(
      center: Offset(_viewport.width / 2 + across, _viewport.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  /// _scale is one document unit on screen: the fit times the zoom.
  double get _scale => _fitScale * controller.zoom;

  /// _tellControllerTheScale reports the fitted scale to the controller after
  /// the frame: notifying during layout is "setState called during build".
  void _tellControllerTheScale() {
    var found = _fitScale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.reportFitScale(found);
    });
  }

  Size get _scaledSize => document.size.size * _scale;

  /// _origin is the document's top-left in stage space: the page's own.
  Offset get _origin => _pageRect.topLeft;

  /// _clampedPan is the view as CanvasController.pan holds it: the page's
  /// middle from the window's, in screen pixels.
  Offset get _clampedPan {
    var page = _pageRect.center;
    var at = _scrolled + Offset(_visible.width / 2, _visible.height / 2);
    return page - at;
  }

  /// _scrollFor is the scroll that puts the view at [pan], within range.
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

  /// _setPan moves the view as near [pan] as the page can be scrolled.
  void _setPan(Offset pan) {
    var to = _scrollFor(pan);
    _jumpTo(to);
    var page = _pageRect.center;
    var at = page - Offset(_visible.width / 2, _visible.height / 2) - to;
    controller.pan = Offset2(at.dx, at.dy);
  }

  /// _syncing is set while the scroll views follow the view, so
  /// _followScroll does not take it for a scroll by hand.
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

  /// _followScroll keeps the view where the page was scrolled by hand, so
  /// the zoom buttons zoom about what is looked at.
  void _followScroll() {
    if (_syncing || !mounted) return;
    var pan = _clampedPan;
    controller.followPan(Offset2(pan.dx, pan.dy));
  }

  /// _syncScroll scrolls to the view once the page is laid out at its size.
  void _syncScroll() {
    if (!mounted) return;
    _jumpTo(_scrollFor(Offset(controller.pan.dx, controller.pan.dy)));
  }

  Offset _toDocument(Offset stage) =>
      (stage - _origin) / (_scale == 0 ? 1 : _scale);

  Offset _toStage(Offset doc) => doc * _scale + _origin;

  /// toDocumentPoint is a widget point in document space, for sidebar drops.
  Offset toDocumentPoint(Offset local) => _toDocument(local + _scrolled);

  /// pageRect is the canvas's frame in widget coordinates, for tests: the
  /// canvas is painted, so there is no render box to measure.
  @visibleForTesting
  Rect get pageRect => _pageRect.shift(-_scrolled);

  @visibleForTesting
  Rect get contentRect => (_origin & _scaledSize).shift(-_scrolled);

  /// spreadRect is the page and facing leaf's frame together, for tests.
  @visibleForTesting
  Rect get spreadRect => _viewRect.shift(-_scrolled);

  /// textFlowGrips is a selected text box's overflow dots, for tests.
  @visibleForTesting
  TextFlowGrips? get textFlowGrips => _flowGrips();

  /// textFlowLines is the chain links drawn, for tests.
  @visibleForTesting
  List<FlowLine> get textFlowLines => _flowLines();

  /// gizmo is the gizmo on the selected staged element, for tests.
  @visibleForTesting
  StageGizmo? get gizmo => _gizmo();

  /// toStagePoint is a document point on screen, for tests.
  @visibleForTesting
  Offset toStagePoint(Offset doc) => _toStage(doc) - _scrolled;

  /// handleAt is [handle] on screen, for tests: turned or slanted, it is off
  /// the box's corner.
  @visibleForTesting
  Offset handleAt(StageHandle handle) {
    var bounds = _selectionBounds;
    return bounds == null ? Offset.zero : _handlePosition(handle, bounds);
  }

  /// _chosen is the selection on the canvas: a timeline sound is selected
  /// from its channel and has no box.
  List<CanvasElement> get _chosen => [
        for (var e in controller.selectedElements)
          if (!isTimelineSound(e)) e,
      ];

  /// _selectionBounds is the axis-aligned box round the selection, in
  /// document space; rotation is ignored for several.
  Rect? get _selectionBounds {
    var elements = _chosen;
    if (elements.isEmpty) return null;
    // A team on a pitch has no box: the pitch places it.
    if (elements.length == 1 &&
        elements.first is TeamElement &&
        (elements.first as TeamElement).linked) {
      return null;
    }
    // A reused element's copies are each outlined and picked alone; a box
    // round them all shows only with every copy picked, as it would be
    // clutter. One copy picked gets its own box to size, turn and move.
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
    // Where they are on this frame, so the box follows an animated element.
    var box = _visualBounds(elements.first);
    for (var e in elements.skip(1)) {
      box = box.expandToInclude(_visualBounds(e));
    }
    return box;
  }

  /// _oneCopy is (element, index) when one copy of the one selected reused
  /// element is picked: the one copy that has a box.
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

  Keyframe _copyPose(CanvasElement e, int i) =>
      poseWithMotion(e, controller.frame, controller.document,
          live: controller.liveMotion, instance: i);

  /// _boxIsNotTheShape marks elements whose selection box is bigger than what
  /// the pointer can land on: see _onPointerDown.
  bool _boxIsNotTheShape(CanvasElement e) =>
      e is LineElement ||
      e is PathElement ||
      (e is TextElement && e.curve != null);

  /// _visualBounds is where an element is drawn: outside its rectangle for a
  /// bowed line, a path or text on a line. See visualBoundsOf.
  Rect _visualBounds(CanvasElement e) =>
      visualBoundsOf(e, document, controller.frame,
          live: controller.liveMotion);

  /// _selectionHasOwnGeometry is whether handles are worth showing. See
  /// hasOwnGeometry.
  bool get _selectionHasOwnGeometry {
    var elements = _chosen;
    if (elements.isEmpty) return false;
    return elements.every((e) => hasOwnGeometry(e, document, controller.frame));
  }

  /// _rotationOfSelection is the lone selection's rotation in radians, or 0.
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

  /// _skewOfSelection is the lone selection's slant in degrees, or zero.
  Offset get _skewOfSelection => _chosen.length == 1
      ? Offset(_chosen.first.base.skewX, _chosen.first.base.skewY)
      : Offset.zero;

  /// _frameOfSelection is the selection box's turn and slant on the page.
  BoxFrame get _frameOfSelection => BoxFrame(
      _rotationOfSelection * 180 / math.pi,
      _skewOfSelection.dx,
      _skewOfSelection.dy);

  // ------------------------------------------------------------------------
  // Hit testing
  // ------------------------------------------------------------------------

  /// _hitElement is the topmost element under a document point.
  CanvasElement? _hitElement(Offset point) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var e = document.elements[i];
      if (!e.visible || e.locked) continue;
      if (_containsPoint(e, point)) return e;
    }
    return null;
  }

  /// _selectedAt is the topmost selected element under [point], which a
  /// press takes before anything drawn over it.
  CanvasElement? _selectedAt(Offset point) {
    var picked = controller.selection;
    if (picked.isEmpty) return null;
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var e = document.elements[i];
      if (!picked.contains(e.id) || e.locked) continue;
      if (_containsPoint(e, point)) return e;
    }
    return null;
  }

  /// _strokeReach is how near a line, in document units, counts as on it.
  double _strokeReach(double strokeWidth) =>
      math.max(strokeWidth / 2, 0) + strokeHitSlop / _scale;

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

  /// _containsPoint is whether [point] is inside [e] as drawn, turn and slant
  /// undone.
  bool _containsPoint(CanvasElement e, Offset point) {
    // A camera is hit by its frame's edge: what it shows inside is picked as
    // if it were not there.
    if (e is CameraElement) {
      var frame = e.movedBoundsAt(controller.frame, controller.document,
          live: controller.liveMotion);
      var reach = _strokeReach(2) + 4 / _scale;
      if (frame.inflate(reach).contains(point) &&
          !frame.deflate(reach).contains(point)) {
        return true;
      }
      // Its name tab and corner brackets too: an edge on the page's edge is
      // hard to pick.
      if (cameraTab(e, frame, _scale).contains(point)) return true;
      var corner = math.min(22 / _scale, frame.shortestSide / 4);
      for (var c in [
        frame.topLeft,
        frame.topRight,
        frame.bottomLeft,
        frame.bottomRight,
      ]) {
        var inside = Rect.fromCenter(
            center: Offset(c.dx + (c.dx == frame.left ? 1 : -1) * corner / 2,
                c.dy + (c.dy == frame.top ? 1 : -1) * corner / 2),
            width: corner,
            height: corner);
        if (inside.contains(point)) return true;
      }
      return false;
    }
    // A team on a pitch is wherever the pitch puts its players.
    if (e is TeamElement && e.linked) return _hitPlayer(e, point) != null;
    // Something on a stage is inside the four corners the camera sees.
    if (e.base.spot != null) {
      if (stagedIn(document, e, controller.frame) case var at?) {
        return (Path()..addPolygon(at.quad, true)).contains(point);
      }
    }
    // A curve is hit by its stroke, not its box: a bowed line or path bulges
    // out of its box, and text on a line is wherever the line is.
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
        // Generous: the target is a row of letters on the line.
        return _nearPolyline(
            curve, point, _strokeReach(e.textSpec.fontSize * 1.2));
      }
    }

    var box = e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    var shape = e.movedFrameAt(controller.frame, controller.document,
        live: controller.liveMotion);
    var local = point;
    if (!shape.upright) local = box.center + shape.invert(point - box.center);
    if (!box.contains(local)) return false;

    if (e is ShapeElement && e.shape == ShapeKind.circle) {
      var r = box.shortestSide / 2;
      return (local - box.center).distance <= r;
    }
    return true;
  }

  /// _onSelectionGrip is whether a press takes hold of the selection: a
  /// handle, a flow grip, or a path's points.
  bool _onSelectionGrip(Offset stage, Offset doc) {
    if (controller.selection.isEmpty) return false;
    if (_hitHandle(stage) != null || _hitFlowGrip(stage) != null) return true;
    var path = _selectedPath();
    return path != null && _hitPathControl(path, doc) != null;
  }

  StageHandle? _hitHandle(Offset stage) => _nearestHandle(stage)?.$1;

  /// _nearestHandle is the closest grip in reach and its distance: closest,
  /// since on a small element handle targets overlap; the distance lets the
  /// flow grips on the same outline tell whether they are nearer.
  (StageHandle, double)? _nearestHandle(Offset stage) {
    if (!_selectionHasOwnGeometry) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;
    var reach = handleSize / 2 + handleHitSlop;

    // Hidden helpers cannot be grabbed: see CanvasController.showHelpers.
    if (!controller.showHelpers) return null;

    // The middle is not a handle: on a one-line text box the top and bottom
    // targets would meet, and every press would resize instead of move.
    if (_insideCore(stage, bounds, reach)) return null;

    StageHandle? best;
    var away = double.infinity;
    for (var handle in StageHandle.values) {
      var at = _handlePosition(handle, bounds);
      // Clipped out of sight is out of reach.
      if (!_viewRect.inflate(reach).contains(at)) continue;
      var d = (stage - at).distance;
      if (d <= reach && d < away) {
        best = handle;
        away = d;
      }
    }
    return best == null ? null : (best, away);
  }

  /// _insideCore is whether a stage point is deep enough inside [bounds] that
  /// no grip can have meant it. Each direction gives at most a third to its
  /// grips, so a middle is always left to press.
  bool _insideCore(Offset stage, Rect bounds, double reach) {
    var on = Offset(bounds.width, bounds.height) * _scale;
    if (on.dx <= 0 || on.dy <= 0) return false;
    var keepX = math.min(reach, on.dx / 3);
    var keepY = math.min(reach, on.dy / 3);

    // In the selection's own frame, so a rotated box keeps its middle.
    var d = stage - _toStage(bounds.center);
    var local = _frameOfSelection.invert(d);
    return local.dx.abs() < on.dx / 2 - keepX &&
        local.dy.abs() < on.dy / 2 - keepY;
  }

  /// _selectedText is the lone selected text element, which shows flow grips.
  TextElement? _selectedText() {
    if (controller.selection.length != 1) return null;
    var element = document.elementById(controller.selection.first);
    return element is TextElement ? element : null;
  }

  /// _flowGrips is a selected text box's two dots and what they say, or null.
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

  /// _flowDragLine is the link being dragged, from its box to the pointer.
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

  /// _flowLines is every text link worth drawing: either box selected, or
  /// all boxes shown (see CanvasController.showAllBounds).
  List<FlowLine> _flowLines() {
    // Hidden joins hide only the lines that cross the design; the grips
    // still say there is a chain and whether the words fit.
    if (!controller.showHelpers || controller.hideJoins) return const [];
    var out = <FlowLine>[];

    for (var e in document.elements) {
      if (e is! TextElement || e.flowTo.isEmpty) continue;
      var into = document.elementById(e.flowTo);
      if (into == null || !e.visible || !into.visible) continue;

      // Not the one in hand: that is drawn from the pointer.
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

  Offset _flowPointOf(Rect bounds, {required bool top}) => top
      ? Offset(bounds.left, bounds.top + bounds.height / 4)
      : Offset(bounds.right, bounds.bottom - bounds.height / 4);

  /// _gripPosition puts a flow grip between two resize handles, in at upper
  /// left and out at lower right, clear of the corners.
  Offset _gripPosition(Rect bounds, {required bool top}) {
    var centre = _toStage(bounds.center);
    var half = Offset(bounds.width, bounds.height) * _scale / 2;
    var local =
        top ? Offset(-half.dx, -half.dy / 2) : Offset(half.dx, half.dy / 2);
    return centre + _frameOfSelection.apply(local);
  }

  /// _textPieceOwner is the frontmost text element with a piece under the
  /// pointer outside its box. Any one, not only the selected: a piece pushed
  /// outside its box may be all of it near the pointer, and must take a
  /// first click.
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

  /// _looseTextPiece is a text element with a piece under the pointer drawn
  /// outside its box. It beats the resize handles, whose outline a piece
  /// pushed out sits against; inside the box they win (see _insideCore).
  TextElement? _looseTextPiece(Offset doc) {
    var owner = _textPieceOwner(doc);
    if (owner == null) return null;
    return owner.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion).contains(doc) ? null : owner;
  }

  /// _textItemAt is [e]'s extra piece at a document point, or null, from
  /// what draws them (see textItemRects).
  TextItem? _textItemAt(TextElement e, Offset doc) {
    if (e.items.isEmpty) return null;
    var bounds = e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    var rects = textItemRects(e, bounds);
    // Backwards: the last drawn is on top.
    for (var i = e.items.length - 1; i >= 0; i--) {
      // Hidden or locked in the Layers, it cannot be pressed.
      if (e.items[i].hidden || e.items[i].locked) continue;
      if (!rects[i].isEmpty && rects[i].inflate(2).contains(doc)) {
        return e.items[i];
      }
    }
    return null;
  }

  /// _topmostOf is whichever of the two is drawn in front, or the non-null one.
  CanvasElement? _topmostOf(CanvasElement? box, CanvasElement? piece) {
    if (box == null || piece == null) return box ?? piece;
    if (box.id == piece.id) return box;
    var elements = document.elements;
    return elements.indexWhere((e) => e.id == piece.id) >
            elements.indexWhere((e) => e.id == box.id)
        ? piece
        : box;
  }

  /// _hitFlowGrip is the flow grip under the pointer, if any: the outgoing
  /// grip starts or moves a link, the incoming one picks up the arriving
  /// link to disconnect it.
  ///
  /// [beat] is how close the nearest resize handle is: a grip answers only
  /// when nearer, since on a short box they nearly overlap; ties go to the
  /// handle.
  ({bool out})? _hitFlowGrip(Offset stage, {double beat = double.infinity}) {
    var grips = _flowGrips();
    if (grips == null) return null;
    var reach = flowGripSize / 2 + flowGripHitSlop;
    // On the resize grips' outline, so it keeps off the middle too.
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

  /// _counterPart is the counter whose loose piece is dragged, and
  /// _counterPartAt which: -2 the words before, -3 after, 0 and up a button.
  String? _counterPart;
  int _counterPartAt = 0;

  /// _counterPartUnder is the loose piece at a document point, if any.
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
      var box = Rect.fromCenter(
          center: centre,
          width: math.max(
              e.affixSpec.fontSize * text.length * 0.7, e.affixSpec.fontSize),
          height: e.affixSpec.fontSize * 1.4);
      if (box.contains(doc)) return which;
    }
    return null;
  }

  /// _pressSynth answers a press on synth module [e]'s controls: a key
  /// sounds, a knob turns with a vertical drag (double-click: back to the
  /// teacher's start), an option is chosen, ↺ and the look switch act, and a
  /// jack starts a cable (from a used input, that cable is lifted). A locked
  /// module's knobs, options and ↺ do not change. False on the panel itself.
  bool _pressSynth(SynthModuleElement e, Offset doc) {
    var part = synthPartAt(e, doc);
    if (part == null) return false;
    if (controller.selection.length != 1 ||
        controller.selection.first != e.id) {
      controller.selectOnly(e.id);
    }
    _mode = _DragMode.none;
    switch (part.kind) {
      case SynthPartKind.key:
        controller.synthKeyDown(e, part.index);
        _synthKey = (e, part.index);
      case SynthPartKind.knob:
        if (e.fixed) break;
        var knob = synthKnobs[e.module]![part.index];
        var twice = clock.now().difference(_lastClickAt) < _doubleClickWindow;
        _lastClickAt =
            twice ? DateTime.fromMillisecondsSinceEpoch(0) : clock.now();
        if (twice) {
          controller.setSynth(e.withValue(knob.key, e.startValue(knob.key)));
          break;
        }
        controller.beginInteraction();
        _synthKnob = (e.id, knob, knob.turn(e.value(knob.key)), doc);
        setState(() => _mode = _DragMode.synthKnob);
      case SynthPartKind.screen:
        if (e.fixed) break;
        controller.beginInteraction();
        _synthScreen = (e.id, part.port);
        setState(() => _mode = _DragMode.synthScreen);
      case SynthPartKind.option:
        if (e.fixed) break;
        var name = synthChoiceOf(e.module)!;
        controller
            .setSynth(e.withChoice(name, synthChoices[name]![part.index]));
      case SynthPartKind.reset:
        if (!e.fixed) controller.resetSynth(e);
      case SynthPartKind.big:
        controller.bigSynth(e, !e.big);
      case SynthPartKind.look:
        controller.setSynth(e.copyWith(
            look: e.look == SynthLook.analogue
                ? SynthLook.digital
                : SynthLook.analogue));
      case SynthPartKind.jack:
        controller.beginInteraction();
        var plug = part.out ? null : e.inputs[part.port];
        var source = plug == null ? null : document.elementById(plug.module);
        _synthCable = source is SynthModuleElement
            ? (
                from: source,
                port: plug!.port,
                out: true,
                lifted: (e, part.port),
                at: doc
              )
            : (from: e, port: part.port, out: part.out, lifted: null, at: doc);
        setState(() => _mode = _DragMode.synthCable);
    }
    return true;
  }

  /// _pressCode answers a press on Code panel [e]: a tab shown, or carried
  /// to move it; its cross closing it; a listed file opened in the pane last
  /// pressed; a pane divider dragged; a press on the code queued to open it
  /// for typing. False on the panel itself, to pick and move it.
  bool _pressCode(CodeElement e, Offset doc) {
    var hit = codeHitAt(e, doc);
    if (hit == null) return false;
    var picked =
        controller.selection.length == 1 && controller.selection.first == e.id;
    void pick() {
      if (!picked) controller.selectOnly(e.id);
    }

    switch (hit) {
      // Its playbar works picked or not; the track is dragged to scrub.
      case CodePlayHit(part: CodePlayPart.play):
        controller.playCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.full):
        controller.toggleCodeFull(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.restart):
        controller.restartCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(part: CodePlayPart.reset):
        controller.resetCode(e);
        _mode = _DragMode.none;
        return true;
      case CodePlayHit(:var at):
        controller.seekCode(at);
        _codeScrub = e.id;
        setState(() => _mode = _DragMode.codeScrub);
        return true;
      case CodeDividerHit(:var divider):
        pick();
        controller.beginInteraction();
        _codeDivider = (e.id, divider);
        setState(() => _mode = _DragMode.codeDivider);
        return true;
      case CodeTabHit(:var pane, :var file, close: true):
        pick();
        controller.closeCodeTab(e, pane, file);
        _mode = _DragMode.none;
        return true;
      case CodeTabHit(:var pane, :var file):
        pick();
        _codeTab = (id: e.id, pane: pane, file: file);
        _codeTabAt = null;
        setState(() => _mode = _DragMode.codeTab);
        return true;
      case CodeFileHit(:var file):
        pick();
        controller.openCodeFile(e, file);
        _mode = _DragMode.none;
        return true;
      case CodePaneHit(:var pane, :var inTabs):
        controller.pressCodePane(e, pane);
        // One click on the code opens it for typing; a press that becomes a
        // drag moves the panel instead. See _onPointerUp.
        if (!inTabs && !_shiftHeld) _pendingCodeEdit = (e.id, pane);
        return false;
    }
  }

  /// _pressCodeRun answers a Run panel's Run button, and opens a picked
  /// panel's preview live.
  bool _pressCodeRun(CodeRunElement e, Offset doc) {
    var code = document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    var boxes = codeRunBoxes(e, e.bounds, runner: runner);
    var picked =
        controller.selection.length == 1 && controller.selection.first == e.id;
    if (picked &&
        !_shiftHeld &&
        (boxes.preview?.contains(doc) ?? false) &&
        e.result != null &&
        (runner == CodeRunner.web || runner == CodeRunner.flutter)) {
      controller.liveCode(e);
      // The opening press is replayed into the app once it is there.
      if (runner == CodeRunner.flutter) _liveTapPending = true;
      _mode = _DragMode.none;
      return true;
    }
    if (!boxes.runButton.contains(doc)) {
      return false;
    }
    if (controller.selection.length != 1 ||
        controller.selection.first != e.id) {
      controller.selectOnly(e.id);
    }
    // Run, then open live, so the next press goes to the app.
    controller.runCode(e).then((_) {
      if (!mounted || controller.codeLive != null) return;
      var now = document.elementById(e.id);
      if (now is CodeRunElement &&
          now.result?.preview.isNotEmpty == true &&
          controller.selection.length == 1 &&
          controller.selection.first == e.id &&
          (runner == CodeRunner.web || runner == CodeRunner.flutter)) {
        controller.liveCode(now);
      }
    });
    _mode = _DragMode.none;
    return true;
  }

  /// _liveTapPending is a press that opened a preview live, replayed into
  /// the app on release (_replayTap).
  bool _liveTapPending = false;
  int _replayPointer = 0x7FFF0000;

  /// _replayTap presses the live app at [global] once built, as a touch: a
  /// mouse's would need its pointer added first.
  void _replayTap(Offset global) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || controller.codeLive == null) return;
      var id = ++_replayPointer;
      GestureBinding.instance.handlePointerEvent(PointerDownEvent(
          pointer: id, position: global, kind: PointerDeviceKind.touch));
      GestureBinding.instance.handlePointerEvent(PointerUpEvent(
          pointer: id, position: global, kind: PointerDeviceKind.touch));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// _releaseCode ends a press on a Code panel: a divider let go, or a tab
  /// shown, or moved where it was carried.
  bool _releaseCode(Offset doc) {
    if (_codeScrub != null) {
      _codeScrub = null;
      setState(() => _mode = _DragMode.none);
      return true;
    }
    if (_codeDivider != null) {
      _codeDivider = null;
      controller.endInteraction();
      setState(() => _mode = _DragMode.none);
      return true;
    }
    var tab = _codeTab;
    if (tab == null) return false;
    var carried = _codeTabAt != null;
    setState(() {
      _codeTab = null;
      _codeTabAt = null;
      _mode = _DragMode.none;
    });
    var e = document.elementById(tab.id);
    if (e is! CodeElement) return true;
    if (!carried) {
      controller.showCodeTab(e, tab.pane, tab.file);
      return true;
    }
    if (codeTabDrop(e, doc) case (var to, var index)?) {
      controller.moveCodeTab(e, tab.file, tab.pane, to, index);
    }
    return true;
  }

  /// _codeTabCarried is a carried tab's name at the pointer and a drop mark.
  List<Widget> _codeTabCarried() {
    var tab = _codeTab, at = _codeTabAt;
    if (tab == null || at == null) return const [];
    var e = document.elementById(tab.id);
    if (e is! CodeElement) return const [];
    var f = e.file(tab.file);
    if (f == null) return const [];
    var theme = Theme.of(context);
    var out = <Widget>[];
    if (codeTabDrop(e, at) case (var pane, var index)?) {
      var b = codeBoxes(e, e.bounds).panes[pane];
      var x = b.tabs.isEmpty
          ? b.tabRow.left + e.fontSize * 0.3
          : index < b.tabs.length
              ? b.tabs[index].rect.left
              : b.tabs.last.rect.right;
      var top = _toStage(Offset(x, b.tabRow.top + e.fontSize * 0.3));
      out.add(Positioned(
          left: top.dx - 2,
          top: top.dy,
          width: 4,
          height: (b.tabRow.height - e.fontSize * 0.6) * _scale,
          child: IgnorePointer(
              child: ColoredBox(color: theme.colorScheme.primary))));
    }
    var p = _toStage(at);
    out.add(Positioned(
        left: p.dx + 12,
        top: p.dy + 10,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, color: f.colour),
              const SizedBox(width: 6),
              Text(f.name, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
        )));
    return out;
  }

  /// _codeEditorFor is the code editor over the pane being edited, if open.
  Widget? _codeEditorFor() {
    var (id, pane) = controller.codeEditing ?? ("", -1);
    if (pane < 0) return null;
    var e = document.elementById(id);
    if (e is! CodeElement) return null;
    var file = controller.codeShownFile(e, pane);
    var rect = codeEditorRect(e, pane);
    if (file == null || rect == null) return null;
    var tl = _toStage(rect.topLeft);
    return CodePaneEditor(
      key: ValueKey("codeEditing-$id-$pane-$file"),
      element: e,
      file: file,
      rect: Rect.fromLTWH(tl.dx, tl.dy, rect.width * _scale, rect.height * _scale),
      scale: _scale,
      onChanged: (text) {
        var now = document.elementById(id);
        if (now is! CodeElement) return;
        if (!_codeEditBegun) {
          _codeEditBegun = true;
          controller.beginInteraction();
        }
        controller.replaceElement(now.typedInto(file, text), transient: true);
      },
      onDone: () {
        if (_codeEditBegun) {
          _codeEditBegun = false;
          controller.endInteraction();
        }
        if (controller.codeEditing != null) {
          var now = document.elementById(id);
          if (now is CodeElement) controller.editCodePane(now, -1);
        }
        _focus.requestFocus();
      },
    );
  }

  /// _codeLiveRect is the open live preview on the stage, if any.
  Rect? _codeLiveRect() {
    var e = document.elementById(controller.codeLive ?? "");
    if (e is! CodeRunElement) return null;
    var code = document.elementById(e.code);
    var runner = runnerOf(e, code is CodeElement ? code : null);
    var preview = codeRunBoxes(e, e.bounds, runner: runner).preview;
    if (preview == null) return null;
    var tl = _toStage(preview.topLeft);
    return Rect.fromLTWH(
        tl.dx, tl.dy, preview.width * _scale, preview.height * _scale);
  }

  Widget? _codeLiveFor() {
    var id = controller.codeLive;
    if (id == null) return null;
    var e = document.elementById(id);
    if (e is! CodeRunElement) return null;
    var code = document.elementById(e.code);
    if (code is! CodeElement) return null;
    var entry = entryFile(e, code);
    var runner = runnerOf(e, code);
    var preview = codeRunBoxes(e, e.bounds, runner: runner).preview;
    if (entry == null || preview == null) return null;
    var tl = _toStage(preview.topLeft);
    return CodeLivePreview(
      key: ValueKey("codeLive-$id"),
      runner: runner,
      code: code,
      entry: entry,
      rect: Rect.fromLTWH(
          tl.dx, tl.dy, preview.width * _scale, preview.height * _scale),
      appSize: e.appSize(preview.size),
      onLog: controller.liveCodeLog,
      onSnap: (snap) => controller.codeLiveSnap = snap,
    );
  }

  /// _hoverCode notes the code pane under the pointer, which then scrolls
  /// instead of the page.
  void _hoverCode(Offset stage) {
    var over = _codePaneAt(stage);
    if (over != _codeOver) setState(() => _codeOver = over);
  }

  (String, int)? _codePaneAt(Offset stage) {
    var doc = _toDocument(stage);
    var e = _hitElement(doc);
    if (e is CodeElement && controller.codeEditing == null) {
      if (codeHitAt(e, doc) case CodePaneHit(:var pane, inTabs: false)) {
        return (e.id, pane);
      }
    }
    return null;
  }

  /// _scrollCodeBy scrolls pane [at] by [by] stage pixels, down positive.
  void _scrollCodeBy((String, int) at, double by) {
    var e = document.elementById(at.$1);
    if (e is! CodeElement) return;
    controller.scrollCode(e, at.$2, by / (_scale == 0 ? 1 : _scale));
  }

  void _pressMetronome(MetronomeElement e, MetronomePart part) {
    if (controller.selection.length != 1 ||
        controller.selection.first != e.id) {
      controller.selectOnly(e.id);
    }
    switch (part) {
      case MetronomePart.play:
        controller.toggleMetronome(e);
      case MetronomePart.slower:
        controller.metronomeStep(e, _shiftHeld ? -1.0 : -4.0);
      case MetronomePart.faster:
        controller.metronomeStep(e, _shiftHeld ? 1.0 : 4.0);
      case MetronomePart.tap:
        controller.tapMetronome(e);
      case MetronomePart.beats:
        controller.cycleMetronomeBeats(e);
    }
  }

  /// _pressSynthTask answers a task card's Hear and Check buttons.
  void _pressSynthTask(SynthTaskElement card, SynthTaskButton b) {
    if (controller.selection.length != 1 ||
        controller.selection.first != card.id) {
      controller.selectOnly(card.id);
    }
    switch (b) {
      case SynthTaskButton.hear:
        controller.hearSynthTarget(card);
      case SynthTaskButton.check:
        if (card.checks.isEmpty) return;
        var (met, of) = controller.checkSynthTask(card);
        var snack = SnackBarModel.of(context);
        if (met == of) {
          snack.success("That's it: ${card.title.toLowerCase()}.");
        } else {
          snack.error("Not yet: ${of - met} of $of still to do. See the list.");
        }
    }
  }

  /// _turnSynthKnob turns the dragged knob a whole turn per 150 pixels up,
  /// four times finer with Shift.
  void _turnSynthKnob(Offset doc) {
    var (id, knob, from, start) = _synthKnob ?? (null, null, 0.0, Offset.zero);
    var e = id == null ? null : document.elementById(id);
    if (e is! SynthModuleElement || knob == null) return;
    var travel = (start.dy - doc.dy) * _scale / (_shiftHeld ? 600 : 150);
    controller.setSynth(e.withValue(knob.key, knob.at(from + travel)),
        transient: true);
  }

  /// _releaseSynth ends a press on a synth module: the key released, the
  /// knob's turn one undo step, the cable plugged into the jack it is dropped
  /// on, or, lifted and dropped on nothing, removed. True if there was one.
  bool _releaseSynth(Offset doc) {
    if (_synthKey case (var e, var key)?) {
      _synthKey = null;
      controller.synthKeyUp(e, key);
      return true;
    }
    if (_synthKnob != null || _synthScreen != null) {
      _synthKnob = null;
      _synthScreen = null;
      controller.endInteraction();
      setState(() => _mode = _DragMode.none);
      return true;
    }
    var cable = _synthCable;
    if (cable == null) return false;
    _synthCable = null;
    var onto = synthJackUnder(document.elements, doc);
    var plugged = false;
    if (onto case (var into, var port, var out)? when out != cable.out) {
      var (src, srcPort) = cable.out ? (cable.from, cable.port) : (into, port);
      var (dst, dstPort) = cable.out ? (into, port) : (cable.from, cable.port);
      if (cable.lifted case (var was, var input)?
          when was.id != dst.id || input != dstPort) {
        controller.unplugSynth(
            document.elementById(was.id) as SynthModuleElement, input);
      }
      plugged = controller.plugSynth(src, srcPort,
          document.elementById(dst.id) as SynthModuleElement, dstPort);
      if (!plugged) {
        var a = (cable.out ? cable.from : into)
            .module
            .output(cable.out ? cable.port : port);
        var b = dst.module.input(dstPort);
        SnackBarModel.of(context).error(a == null || b == null
            ? "Patch from an output to an input."
            : "That doesn't fit: a ${a.signal.name} jack goes to a "
                "${a.signal.name} jack.");
      }
    } else if (cable.lifted case (var was, var input)?) {
      controller.unplugSynth(
          document.elementById(was.id) as SynthModuleElement, input);
    }
    controller.endInteraction();
    setState(() => _mode = _DragMode.none);
    return true;
  }

  /// _applyCounterPart moves the dragged counter piece to the pointer.
  void _applyCounterPart(Offset doc) {
    var id = _counterPart;
    var element = id == null ? null : document.elementById(id);
    if (element is! CounterElement) return;

    var inner = element.box.inner(element.bounds);
    if (inner.width <= 0 || inner.height <= 0) return;
    // A fraction of the box from its middle, so it stays put on resize.
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

  /// _legendSeriesAt is the series whose key entry is at a document point,
  /// from the painter, or -1.
  int _legendSeriesAt(ChartElement e, Offset doc) {
    for (var (series, box) in chartLegendRects(e, e.bounds)) {
      if (box.contains(doc)) return series;
    }
    return -1;
  }

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

  /// _holdLegend takes hold of a chart's key after a held press, to move it
  /// rather than press a switch. The key keeps its drawn place and becomes a
  /// placed label like the title, reset from the Legend settings.
  void _holdLegend(ChartElement e) {
    _legendHold = null;
    var current = document.elementById(e.id);
    if (current is! ChartElement || current.locked) return;
    var bounds = current.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion);
    if (bounds.width <= 0 || bounds.height <= 0) return;
    var block = chartLegendBlock(current, bounds);
    if (block.isEmpty) return;

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

  /// _audioPartAt is the speaker control at a document point, or null (see
  /// audioParts).
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

  /// _masterAudioAt is a master speaker and control under a document point.
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

  /// _videoPartAt is the video part at a document point. A link answers
  /// anywhere on it.
  VideoPart? _videoPartAt(VideoElement e, Offset doc) =>
      videoPartAt(videoParts(e, e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion)), doc,
          clickable:
              e.isLink || (e.has(VideoControl.clickToggle) && !e.clip.timed));

  /// _masterVideoAt is a master video under a document point.
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
    // Leaving the app is for whoever put the stage up, as a button's link is.
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

  /// _counterButtonAt is the counter button at a document point, or -1.
  int _counterButtonAt(CounterElement e, Offset doc) {
    var rects = counterButtonRects(e, e.bounds);
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].contains(doc)) return i;
    }
    return -1;
  }

  /// _pressCounter runs a counter's button. Set is typed on the button here,
  /// as the controller has no window.
  void _pressCounter(CounterElement e, int at) {
    if (at < 0 || at >= e.buttons.length) return;
    var button = e.buttons[at];
    if (controller.pressCounterButton(e, button)) return;
    setState(() {
      _settingCounter = e.id;
      _settingAt = at;
    });
  }

  /// _counterInputFor is the field on a counter's Set button: Enter takes
  /// it; closing it otherwise changes nothing.
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

  /// _dropFlow finishes a link drag: onto another text box it links there;
  /// elsewhere it unlinks, so the gesture that made a chain undoes it.
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
      // A ring of boxes has no first box to read from: refused.
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
    return centre + _frameOfSelection.apply(local);
  }

  // ------------------------------------------------------------------------
  // Gestures
  // ------------------------------------------------------------------------

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  /// _pressedCopy is the copy of [_pressedCopyOf] a press landed on, picked
  /// if the press is a click.
  String? _pressedCopy, _pressedCopyOf;

  /// _copiesStart and _dragCopies are the copies at the drag's start, and
  /// which are dragged.
  InstanceSet? _copiesStart;
  Set<String> _dragCopies = const {};

  void _onPointerDown(PointerDownEvent event) {
    _pointer = event;
    // Not while typing: an editor is a real text field with its own
    // pointers, and clicking off it moves focus, which closes it (see
    // CanvasTextEditor._onFocus). Taking focus would also close a cell editor
    // before its own picture button's tap finished.
    if (_editingText != null ||
        _editingCell != null ||
        controller.codeEditing != null) {
      return;
    }
    // A press off a live preview shuts it. One on it belongs to the preview:
    // shutting it would pull the page from under the click.
    if (controller.codeLive != null) {
      if (_codeLiveRect()?.contains(event.localPosition) ?? false) {
        _inLive = true;
        return;
      }
      controller.endLiveCode();
    }
    _focus.requestFocus();
    // Through the camera the page is drawn moved, so a press would land
    // elsewhere than it looks: it only puts the page back. See
    // CanvasController.cameraView.
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
    if (controller.placingCopies case var placing?
        when event.buttons == kPrimaryMouseButton) {
      controller.beginInteraction();
      controller.placeCopyAt(placing, doc);
      controller.endInteraction();
      _mode = _DragMode.none;
      return;
    }

    // A press on the facing page opens it, before the pan check (panning is
    // a drag) and the hit test (an element hanging over the spine would take
    // it), unless it is on a grip: a picture across the spread has handles on
    // the other leaf.
    if (_facingPage case var beside?
        when _onFacingPage(stage) && !_onSelectionGrip(stage, doc)) {
      controller.goToScene(beside);
      _mode = _DragMode.none;
      return;
    }

    // A held marker's canvas label: dragged to move, or sized by its grip.
    // Not in a game, where the page is the player's.
    if (_pressMarkerNote(doc)) return;

    if (controller.sampling) {
      _mode = _DragMode.none;
      _sampleAt(doc);
      return;
    }

    // The pen's buttons and eraser end, with the pencil out, before the
    // middle button's pan.
    if (_stylusPress(event, doc)) return;

    // The stage gizmo, drawn on top, before anything under it.
    if (_pressGizmo(doc)) return;

    // With the page locked, a press on a stage takes its camera.
    if (_pressLockedStage(event, doc)) return;

    // The pan tool and middle button pan (Space plays). Not with the page
    // locked, and not the pan tool on a 3D stage, which has its own tools.
    if (!controller.pageLocked &&
        ((controller.tool == CanvasTool.pan && !controller.onStage3d) ||
            event.buttons == kMiddleMouseButton)) {
      _mode = _DragMode.pan;
      _startPan = _clampedPan;
      _dragStart = stage;
      return;
    }

    // With a picture's layers open, a press on it works on them; elsewhere
    // it finishes editing.
    if (controller.editingImage case var picture?) {
      if (_pressLayers(picture, doc)) return;
      controller.editImage(null);
    }

    // A guide before anything on the canvas: it is a hairline, so its reach
    // is tight (see guideGrabSlop), but within it the guide wins.
    if (_startGuideDrag(stage, doc)) return;

    // An anchor point shown and unlocked, before the element it sits on.
    if (_anchorUnder(stage) case var id?) {
      _anchorOf = id;
      _mode = _DragMode.anchor;
      controller.beginInteraction();
      return;
    }

    // A sprite or tile map being painted takes a press on it first.
    if (controller.spritePaint case var session?) {
      if (session.sprite case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.spritePaint;
        unawaited(session.strokeStart(doc));
        return;
      }
    }
    if (controller.tilePaint case var session?) {
      if (session.map case var e? when !e.locked && e.bounds.contains(doc)) {
        _mode = _DragMode.tilePaint;
        session.strokeStart(doc);
        return;
      }
    }

    // A drawing being edited takes the press first; outside it, editing
    // ends and the press goes on.
    if (controller.editingVector case var vector?
        when _pressVector(vector, doc)) {
      return;
    }

    // Option on a 3D stage takes its camera: across orbits, down looks from
    // higher. On a Background element showing one, or, hitting nothing else,
    // the background's own.
    if (HardwareKeyboard.instance.isAltPressed) {
      var hit = _hitElement(doc);
      var held = switch (hit) {
        StageElement s => s,
        BackgroundElement b when b.isStage => b.staged,
        null => controller.stageOf(backgroundStageId),
        _ => null,
      };
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

    // A selected path's points and handles first: they are over the curve.
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

    // Inside the box of a selected element whose box is not its shape (a
    // curved line, a path, text on a line) takes hold of it. Selecting one
    // still needs the stroke, or a bowed line's empty box would steal clicks.
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

    // Outside the frame there is nothing to hit: a click clears the selection.
    if (!_viewRect.contains(stage) && _hitHandle(stage) == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.none;
      return;
    }

    // No flow grips or resize handles when the press is on a piece of text
    // drawn outside its box: see _looseTextPiece.
    if (_looseTextPiece(doc) == null) {
      // A flow grip before the resize handles, if nearer: on a short box the
      // grip lands on the middle handle.
      var nearest = _nearestHandle(stage);
      if (_hitFlowGrip(stage, beat: nearest?.$2 ?? double.infinity)
          case var grip?) {
        var selected = document.elementById(controller.selection.first);
        // A locked connector shows, as a chain is read by it, but ignores
        // the pointer.
        if (controller.lockJoins) return;
        // The incoming grip takes the arriving link, which belongs to the
        // box in front; where its loose end drops says what it means.
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
        // A side handle slants instead with Command or the Skew switch on.
        var side = handle == StageHandle.topCenter ||
            handle == StageHandle.bottomCenter ||
            handle == StageHandle.centerLeft ||
            handle == StageHandle.centerRight;
        // The one copy's box sizes and turns that copy by its own values. A
        // copy has no slant.
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

    // The retouching brush first: while on, a drag is a stroke.
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

    // A player of any team, before anything else: one dragged out of his
    // team's box, or in the other half, would find no team or the wrong one.
    // A dot is the smallest, topmost thing and beats every box.
    var hit = _hitAnyPlayer(doc);
    if (hit != null) {
      var (team, index) = hit;
      if (controller.selection.length != 1 ||
          controller.selection.first != team.id) {
        controller.selectOnly(team.id);
      }
      _mode = _DragMode.player;
      _playerIndex = index;
      // Held by where they stand, not their token's middle, which on a pitch
      // seen at an angle is off the ground.
      _playerGrab = doc -
          playerPlace(teamGround(document, team, controller.frame), team,
                  team.players[index], controller.frame)
              .ground;
      // Clicking a player points the timeline at them: they have no id.
      controller.focusedPlayer = index;
      controller.beginInteraction();
      return;
    }

    // A selected chart's placed label, before the chart whose box holds it.
    var chart = controller.selected;
    if (chart is ChartElement && !chart.locked) {
      var grab = chartLabelGrabAt(
          chart, chart.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion), doc, _docSlop);
      if (grab != null) {
        // A placed key both moves and holds switches: decided on release by
        // how far the pointer went.
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

    // A selected table's column rule, before the table.
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

    // The selection comes first: pressed anywhere on it, it is what moves,
    // whatever is drawn over it, so a drag after picking in Layers moves
    // what was picked. With nothing selected under the pointer, the topmost
    // thing wins.
    var held = _selectedAt(doc);

    // A master speaker pressed from a page. It cannot be selected there (the
    // master is edited on its own), so a press presses it: background music
    // with a mute switch lives on the master.
    if (held == null) {
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
    }

    // A text element's piece counts as that element wherever it is drawn
    // (gaps or sides can put it outside its box), and beats what is under it.
    var element =
        held ?? _topmostOf(_hitElement(doc), _textPieceOwner(doc));
    if (element == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.marquee;
      setState(() => _marquee = Rect.fromPoints(doc, doc));
      return;
    }

    // A synth module's controls answer a press picked or not, as a rack's
    // do; its panel picks and moves it.
    if (element is SynthModuleElement && _pressSynth(element, doc)) return;
    if (element is MetronomeElement) {
      if (metronomePartAt(element, doc) case var part?) {
        _pressMetronome(element, part);
        _mode = _DragMode.none;
        return;
      }
    }
    // A Code panel's tabs, files and pane dividers, and a Run panel's Run
    // button, answer a press picked or not.
    if (element is CodeElement && _pressCode(element, doc)) return;
    if (element is CodeRunElement && _pressCodeRun(element, doc)) return;
    if (element is CodeTaskElement && codeTaskButtonAt(element, doc)) {
      if (controller.selection.length != 1 ||
          controller.selection.first != element.id) {
        controller.selectOnly(element.id);
      }
      controller.checkCodeTask(element);
      _mode = _DragMode.none;
      return;
    }
    if (element is SynthTaskElement) {
      if (synthTaskButtonAt(element, doc) case var b?) {
        _pressSynthTask(element, b);
        _mode = _DragMode.none;
        return;
      }
    }

    // A selected button is tried by a click and moved by a drag, so its
    // action waits for pointer-up, when the travel is known. See
    // _onPointerUp.
    if (element is ButtonElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingButton = element;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A selected speaker's or video's controls, on the same terms: a press
    // that stays put plays, mutes, sets the volume or seeks; one that
    // travels moves it.
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

    // A selected sheet with a score: a press that stays put moves the
    // playhead to the note there; one that travels moves the sheet. Its
    // playbar takes a press picked or not.
    var onBar = element is SheetElement &&
        (sheetBarRect(
                    element,
                    element.movedBoundsAt(controller.frame, controller.document,
                        live: controller.liveMotion))
                ?.contains(doc) ??
            false);
    if (onBar &&
        (controller.selection.length != 1 ||
            controller.selection.first != element.id)) {
      controller.selectOnly(element.id);
    }
    if (element is SheetElement &&
        element.score.isNotEmpty &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingSheet = element;
      _pendingSheetAt = doc;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A selected instrument's keys sound on press and stop on release; a
    // press that travels releases the note and moves the keyboard. Further
    // down the key is harder, as on a real one.
    if (element is AudioElement &&
        element.instrument != null &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var keys =
          keyboardLayout(element.instrument!, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
      if (keys.keyAt(doc) case (var key, var depth)?) {
        controller.noteOn(element, key,
            velocity: (50 + depth * 77).round(),
            place: neckPlaceAt(keys, element.instrument!, doc));
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

    // A live counter's buttons, on the same terms: only when selected and the
    // press does not become a drag. A loose piece is both, so the press is
    // armed here and the mode moves the piece.
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

    // A chart's key entry switches its series, on the same terms.
    if (element is ChartElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      var at = _legendSeriesAt(element, doc);
      if (at >= 0) {
        _pendingLegend = element;
        _pendingLegendAt = at;
        // Held rather than tapped, the press moves the key instead.
        _legendHold = Timer(_legendHoldDelay, () => _holdLegend(element));
        _beginTransform(_DragMode.move, null);
        return;
      }
    }

    // A second click on a selected drawing opens it for editing.
    if (element is VectorElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        clock.now().difference(_lastClickAt) < _doubleClickWindow) {
      _mode = _DragMode.none;
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

    // A second click on a selected picture opens its layers, the one under
    // the click picked. With the base picked, a drag moves the picture
    // inside its box (see _framing).
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

    // A second click on a selected table's cell opens it for typing.
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
    // first only selects, so it can still be dragged. Not one whose words
    // come from a document or a flow: it does not own them, and typing would
    // be overwritten.
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
        _editingItem = _textItemAt(element, doc)?.id;
      });
      // Pick the typed piece in Layers, so its settings show.
      controller.pickTextLayer(element.id, _editingItem);
      _mode = _DragMode.none;
      return;
    }
    _lastClickAt = clock.now();

    if (_pressCopy(element, doc)) return;

    if (_shiftHeld) {
      controller.toggleSelected(element.id);
    } else if (!controller.selection.contains(element.id)) {
      controller.selectOnly(element.id);
    }

    // A team with its frame locked, or on a pitch, is selectable but its box
    // does not move. A player drag was dealt with above.
    if (element is TeamElement && element.frameFixed) {
      _mode = _DragMode.none;
      return;
    }

    _beginTransform(_DragMode.move, null);
  }

  /// _pressCopy takes a press on reused [element] at [doc] for the copy
  /// there. Alt drags out new copies of it (or of those picked); Shift picks
  /// it in or out; with copies picked, it is picked and dragged alone.
  /// Otherwise the press goes on to the element: a drag moves them all, a
  /// click picks this one (see _onPointerUp). True if handled.
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

  /// _copyPivot is the one copy's anchor, which its box sizes and turns
  /// about and which stays put (see CanvasElement.boundsWith). _copySize and
  /// _copyTurn are its own Size and Turn at the drag's start.
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

  /// _applyCopyBox sizes or turns the one picked copy as its handle is
  /// dragged to [doc]: sized evenly (a copy has one Size) by how much farther
  /// from its anchor the pointer is along the line pressed on; turned by the
  /// angle swept, in 15-degree steps with Shift.
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

  /// _moveCopies puts the dragged copies [delta] from their start, along one
  /// axis with Shift.
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

  PathElement? _selectedPath() {
    var selected = controller.selected;
    return selected is PathElement ? selected : null;
  }

  /// _hitPathControl is the point or handle under [doc], as (index, isHandle,
  /// isOutHandle). Handles first, so one on top of an unbent node's point
  /// can still be pulled out.
  (int, bool, bool)? _hitPathControl(PathElement path, Offset doc) {
    // In document units, so the grab area is one size on screen at any zoom.
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

  VectorPart _vectorPart = VectorPart.point;

  /// _vectorBefore and _vectorFrom are the drawing and press a drag began at.
  VectorElement? _vectorBefore;
  Offset _vectorFrom = Offset.zero;

  /// _vectorShapeUnder is the shape a box began on, picked by a click.
  int _vectorShapeUnder = -1;

  /// _pressVector answers a press on a drawing being edited, and says
  /// whether it took it.
  ///
  /// With the pen out, a press puts a point down. Otherwise a point or handle
  /// is taken (Shift toggles it; one of several picked drags them all); a
  /// second click on the picked point toggles corner/smooth; a double-click
  /// on a line adds a point; a press on a shape picks and drags it; and empty
  /// space drags a box to pick points. Outside the drawing, editing ends and
  /// the press goes on.
  bool _pressVector(VectorElement e, Offset doc) {
    var reach = (e.handleSize / 2 + handleHitSlop) / _scale;
    var twice = clock.now().difference(_lastClickAt) < _doubleClickWindow;
    // A double-click here is two clicks on one spot.
    var sameSpot = (doc - _lastVectorClick).distance * _scale <= _penPullMin;
    _lastClickAt = clock.now();
    _lastVectorClick = doc;
    // The pen takes hold of points and handles as picking does, and its next
    // point joins on from the one it took.
    VectorHit? penHit;
    switch (controller.vectorTool) {
      case VectorTool.pen:
        // A double-click finishes the line, as Escape does.
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
        // On the shape just drawn or picked, or its box's handle: moved or
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
        // Otherwise as the select tool (a scale with nothing to scale, a tint
        // off any point): a box, a shape picked, a click off.
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
    // Inside the box round several picked points drags them all, by their
    // middle as well as any one of them.
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
    // A double-click on a shape's line adds a point there; on its fill, it
    // picks every point connected to the part clicked. Both clicks on one
    // spot.
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
    // A shape cut into pieces: a press picks a piece's points, and a drag
    // moves it alone. See vector_cut.dart.
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
    // Anywhere else starts a box to pick points; released without moving it
    // is a click, which on a shape picks the shape. See _onPointerUp.
    _vectorShapeUnder = shapeAt(e, doc, reach);
    // A box from off the drawing can sweep up its edge points; a still click
    // off it finishes editing. The picks stay until the box is let go.
    _vectorPressedOutside = !_visualBounds(e).contains(doc);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorMarquee;
    return true;
  }

  /// _vectorPressedOutside is whether a box began off the drawing.
  bool _vectorPressedOutside = false;

  /// _pointer is the event being handled: the pen's pressure, tilt and
  /// buttons, which the handlers are not otherwise given.
  PointerEvent? _pointer;

  /// _penSamples is the pencil stroke's readings, _penWidth its full width
  /// in drawing units.
  List<PenSample> _penSamples = [];
  double _penWidth = 1;
  double _eraseReach = 0;

  /// _penLean is the pen's lean across and down, each -1 to 1, or null for a
  /// mouse or a pen that does not say.
  Offset? _penLean() {
    var tablet = TabletInput.instance;
    if (tablet.fresh) return Offset(tablet.tiltX, tablet.tiltY);
    var ev = _pointer;
    if (ev == null ||
        (ev.kind != PointerDeviceKind.stylus &&
            ev.kind != PointerDeviceKind.invertedStylus)) {
      return null;
    }
    // Flutter's tilt: how far over (a quarter turn at most), and which way.
    var lean = (ev.tilt / (math.pi / 2)).clamp(0.0, 1.0);
    return Offset(math.sin(ev.orientation), -math.cos(ev.orientation)) * lean;
  }

  /// _penSample is the pen as [_pointer] last reported it, at [doc]: pressure
  /// and tilt are null for a mouse or a platform that gives neither, and the
  /// brush then makes do with speed.
  PenSample _penSample(Offset doc) {
    var ev = _pointer;
    // On macOS the runner reads the pen: see TabletInput.
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

  /// _pressEraser starts the eraser: rubbing out lines, fills or both as
  /// set, or, set to whole lines, removing each line and shape it touches.
  /// On the page only, as the pencil is.
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

  /// _picksShapes is whether presses pick whole shapes: the select shapes
  /// tool, or align after it.
  bool get _picksShapes =>
      controller.vectorTool == VectorTool.selectShapes ||
      (controller.vectorTool == VectorTool.align &&
          controller.vectorAlignsShapes);

  /// _itemsBox is the box round the picked shapes at the drag's start, in
  /// drawing units; _itemsHandle the handle held (see boxHandles), -1 for the
  /// turning handle, or null to move the whole.
  Rect _itemsBox = Rect.zero;
  int? _itemsHandle;

  /// _pressItems is a press with the select shapes tool: a handle of the
  /// picked box takes that handle; a shape is held to move (Shift toggles
  /// it); inside the box, everything picked is held; elsewhere, nothing.
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
    // Empty space: a box picks every shape it touches.
    if (!_shiftHeld) controller.pickVectorItem(null);
    _dragStart = doc;
    setState(() => _marquee = Rect.fromPoints(doc, doc));
    _mode = _DragMode.vectorItemsBox;
  }

  /// _dragItems moves, sizes or turns the picked shapes to follow [doc]: a
  /// handle keeps its opposite side put (Shift keeps a corner's proportions);
  /// the turning handle turns about the middle (Shift in 15-degree steps);
  /// held inside moves the whole.
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

  Offset _shapeFrom = Offset.zero;

  /// _shapeGroup, _shapeBox and _shapeHandle are the shape the shapes tool
  /// moves or resizes: its group, its box at the drag's start (drawing
  /// units), and the handle held (see boxHandles), or null for the whole.
  int _shapeGroup = -1;
  Rect _shapeBox = Rect.zero;
  int? _shapeHandle;

  /// _shapeGrabbed is (group, box, handle) when [doc] is on the picked shape
  /// (the shapes tool's last, or whatever was picked) or a handle of its box;
  /// handle is null inside it. Null elsewhere, which draws a new shape.
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

  /// _fitShape moves or resizes the held shape to follow [doc]: a handle
  /// keeps its opposite side put (Shift keeps a corner's proportions); held
  /// inside moves the whole.
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

  /// _drawShape draws the shapes tool's shape from the drag's start to [doc]:
  /// in the box between, or end to end for a line or arrow. Shift keeps a box
  /// square and a line to 45-degree steps; Alt draws from the middle.
  /// [clicked] draws one of a good size round a click that never dragged.
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

  /// _typing holds a drawing's text being typed, in an unseen field that
  /// takes keys, caret moves, selections and input methods; the letters
  /// appear on the drawing. _typingFor is the shape it was last filled from,
  /// so another one refills it.
  final TextEditingController _typing = TextEditingController();
  final FocusNode _typingFocus = FocusNode(debugLabel: "vectorTyping");
  int _typingFor = -1;
  bool _filling = false;

  /// _typedLayout is the text being typed, laid out, with its drawing.
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

  /// _caret is the caret's top and bottom on the page.
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
      // Filled during the build, so _filling keeps its listener from
      // asking for another.
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

  /// _sampleAt takes the colour at [doc], as drawn at this frame, for the
  /// eyedropper.
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

  List<Offset> _knife = const [];

  /// _finishKnife cuts the picked shape, or every shape the knife crossed.
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
    // The points are renumbered: none stays picked.
    controller.pickVectorShape(only);
  }

  /// _pressQuickFill fills the area the lines close round the click, or
  /// recolours an earlier quick fill (a fill with no line). An open area is
  /// reported and left unfilled.
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
      // Only onto the drawing it was worked out from: later edits win.
      if (!mounted || !identical(controller.editingVector, e)) return;
      if (next == null) {
        snack.error("That area isn't closed: no fill");
        return;
      }
      controller.replaceElement(next);
    });
  }

  /// _onPage is whether [doc] is on the page, the only place the pencil
  /// draws: a resting hand or a pen run off the edge puts nothing down.
  bool _onPage(Offset doc) =>
      (Offset.zero & controller.document.size.size).contains(doc);

  /// _penRuns is the pencil stroke's stretches on the page, each its own
  /// line.
  List<List<PenSample>> _penRuns = [];

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

  /// _penInto is the shapes picked as the pencil went down: if one filled
  /// shape, strokes in its colour are added to it (see _mergePencil).
  Set<int> _penInto = const {};

  /// _mergePencil adds the pencil's new stroke to the one picked filled shape
  /// where it touches it, as a blob brush does.
  void _mergePencil() {
    var before = _vectorBefore, e = controller.editingVector;
    if (before == null || e == null || _penInto.length != 1) return;
    var was = before.shapes ?? const <VectorShape>[];
    var now = e.shapes ?? const <VectorShape>[];
    var base = _penInto.first;
    if (now.length <= was.length || base >= was.length) return;
    if (groupMembers(before, base).length != 1) return;
    var target = was[base];
    // Only in its own colour: a line in another (an eye on a face) is a
    // shape of its own.
    var fill = target.fill, ink = controller.vectorPencilColour;
    if (fill == null ||
        (fill.r - ink.r).abs() > 0.01 ||
        (fill.g - ink.g).abs() > 0.01 ||
        (fill.b - ink.b).abs() > 0.01) {
      return;
    }
    Path area(VectorShape s) {
      var out = Path();
      if (s.fill != null) {
        out = Path.combine(PathOperation.union, out, vectorShapePath(s));
      }
      if (s.stroke != null) {
        out = Path.combine(PathOperation.union, out, vectorLinePath(s));
      }
      return out;
    }

    var added = now.sublist(was.length);
    if (added.isEmpty) return;
    var into = vectorShapePath(target);
    var stroke = added
        .map(area)
        .reduce((a, b) => Path.combine(PathOperation.union, a, b));
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
      // Off the page the stretch ends; back on, another starts.
      _penSamples = [];
      return;
    }
    var last = _penSamples.lastOrNull;
    if (last != null && (doc - last.at).distance * _scale < 1) return;
    if (_penSamples.isEmpty) _penRuns.add(_penSamples);
    _penSamples.add(_penSample(doc));
    _drawPencil();
  }

  void _drawPencil() {
    var before = _vectorBefore;
    if (before == null) return;
    // The stroke and its mirror images, each its own line.
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

  /// _modifierButton is the pen button a key held as the pen touches stands
  /// for (Shift first, Option second, Control third), or null. Command is
  /// left for shortcuts.
  int? _modifierButton() {
    var keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed) return null;
    if (keys.isShiftPressed) return 0;
    if (keys.isAltPressed) return 1;
    if (keys.isControlPressed) return 2;
    return null;
  }

  /// _tabletButton is the pen button (0 to 2) the tablet says is held.
  int? _tabletButton() {
    var t = TabletInput.instance;
    if (!t.fresh) return null;
    for (var (i, bit) in const [(0, 2), (1, 4), (2, 8)]) {
      if (t.buttons & bit != 0) return i;
    }
    return null;
  }

  /// _stylusPress does what a pen button (or its other end) is set to, with
  /// the pencil out, and says whether it took the press. Tablet drivers send
  /// pen buttons as mouse buttons (right, middle, back) as mapped in their
  /// settings.
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
      action = buttons[i];
    } else if (b & kSecondaryButton != 0) {
      action = buttons[0];
    } else if (b & kMiddleMouseButton != 0) {
      action = buttons[1];
    } else if (b & (kBackMouseButton | kForwardMouseButton) != 0) {
      action = buttons[2];
    } else if (_modifierButton() case var i?) {
      // A key held as the pen touches stands in for a button, for pen
      // displays whose own buttons are taken (a MovinkPad's open its key
      // sidebar).
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

  /// _cornerFrom is the shaped corner's place, a drag's distance's origin.
  Offset _cornerFrom = Offset.zero;

  /// _pressCorner rounds (or cuts) the corner at the pressed point by the
  /// corner size; the following drag sets how far. While the corner made is
  /// still picked, a press on it (either point, or where the corner was)
  /// goes on shaping it. Off any point it declines, and the press picks as
  /// the select tool would.
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
    // A corner already rounded (earlier, or a rounded box's) is taken up to
    // reshape, not rounded again.
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

  /// _pressCombine is a Boolean-tool click: on a shape it toggles that shape
  /// for combining (a combined shape whole, never a part); on empty space it
  /// unpicks all; off the drawing it finishes editing.
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

  /// _penCloses closes the pen's run on a press at its first point.
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

  /// _penPut puts the pen's next point at [doc], joined from the point last
  /// put or taken, or starting a shape. The following drag pulls out its
  /// handles; press and drag are one undo step.
  void _penPut(VectorElement e, Offset doc) {
    var from = controller.vectorPenFrom;
    var shapes = e.shapes ?? const <VectorShape>[];
    if (from != null && vectorNodeAt(e, from) == null) from = null;
    var picked = controller.vectorShape;
    // A new shape copies the picked shape, or the colours set for new shapes.
    // See ColourPanel.
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

  /// _widths is the points the thickness tool changes, with their widths at
  /// the start; empty when scaling the whole drawing.
  Map<VectorPick, double> _widths = {};
  double _scaleReach = 0;
  bool _sweeping = false;
  bool _scaleLetsGo = false;

  /// _pressScale starts the line thickness tool on the picked points (or,
  /// with none, the point nearest the press) and every point the drag passes
  /// near.
  bool _pressScale(VectorElement e, Offset doc, double reach) {
    // The reach is wider than a point's handle: a drag sweeps across a
    // line's points as a brush would.
    var near = math.max(reach, _thicknessReach / _scale);
    var picks = controller.vectorPicks;
    var hit = anyPointAt(e, doc, reach);
    if (hit != null && _shiftHeld) {
      controller.pickVectorPoint(hit, toggle: true);
      _mode = _DragMode.none;
      return true;
    }
    Set<VectorPick> those;
    if (hit != null) {
      if (!picks.contains(hit)) controller.pickVectorPoint(hit);
      those = controller.vectorPicks;
    } else if (picks.isNotEmpty) {
      those = picks;
    } else {
      var nearest = anyPointAt(e, doc, near);
      those = nearest == null ? const {} : {nearest};
    }
    // Only a drag with nothing picked sweeps up the points it passes.
    _sweeping = hit == null && picks.isEmpty;
    // A click off every point unpicks them. See _onPointerUp.
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

  /// _applyScale scales by the pointer's travel: right or up larger, left or
  /// down smaller, doubling or halving every 150 screen pixels at any zoom.
  void _applyScale(Offset doc) {
    var before = _vectorBefore;
    if (before == null) return;
    var moved = (doc - _vectorFrom) * _scale;
    var factor = math.pow(2, (moved.dx - moved.dy) / 150).toDouble();
    // A point passed near joins in from its own width.
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

  /// _pressTint starts a tint stroke (an eraser's, with Alt).
  bool _pressTint(VectorElement e, Offset doc) {
    controller.beginInteraction();
    _mode = _DragMode.vectorTint;
    // Off the drawing nothing paints until the brush reaches it; a still
    // release is a click off it. The brush never picks.
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

  /// _shade is the stroke's kind: a tint (0), a shadow (-1) or a highlight
  /// (1). See VectorTool.shadow.
  int get _shade => switch (controller.vectorTool) {
        VectorTool.shadow => -1,
        VectorTool.highlight => 1,
        _ => 0,
      };

  void _startTint(VectorElement e, Offset doc) {
    var space = VectorSpace(e);
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
          // Drawn-on shading is cel shading: hard-edged unless softened.
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

  /// _stroke is the tint stroke or rub-out being painted, _strokeOn the
  /// shapes it has crossed, and _strokeRubs whether it rubs out. Each growth
  /// is laid on the drawing as it was at the start; see withStrokeOn.
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

  /// _onPicked keeps [under] to the picked shapes, if any.
  Set<int> _onPicked(Set<int> under) {
    var picked = controller.vectorSelectedShapes;
    return picked.isEmpty ? under : under.intersection(picked);
  }

  void _carryStroke(Offset doc) {
    var before = _vectorBefore, stroke = _stroke;
    if (before == null || stroke == null) return;
    var at = VectorSpace(before).toDrawing(doc);
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

  /// _brushAt is where the brush ring is drawn; null hides it.
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

  /// _brushRing is the brush outline under the pointer, a stroke's width.
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

  /// _applyVectorMove drags the picked point, or one of its handles. Alt
  /// moves a smooth point's handle alone, making it a corner.
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

  void _applyNodeMove(Offset doc, {required bool handle}) {
    var path = _selectedPath();
    if (path == null || _nodeIndex < 0 || _nodeIndex >= path.nodes.length) {
      return;
    }
    var w = path.width == 0 ? 1.0 : path.width;
    var h = path.height == 0 ? 1.0 : path.height;
    var fraction = Offset((doc.dx - path.x) / w, (doc.dy - path.y) / h);
    var node = path.nodes[_nodeIndex];

    // Alt breaks the handle pair, making a corner.
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

  /// _selectedPicture is the one selected element if it is a picture with
  /// something in it.
  ImageElement? _selectedPicture() {
    var selected = controller.selected;
    return selected is ImageElement && selected.hasImage ? selected : null;
  }

  /// _paintStrokeAt adds a point to the live stroke ([_commitStroke] commits
  /// it on pointer up). Points are stored in picture coordinates, so the
  /// stroke stays put when the element is resized, refitted or recropped;
  /// ImagePlacement converts, as the painter does.
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
    // Off the picture the stroke touches nothing but goes on.
    if (at == null) return;

    if (start) {
      // The brush is a fraction of the picture's shorter side, converted once
      // to canvas units for the preview.
      var shorter = math.min(size.width, size.height);
      var scale = placement.scaleToImage();
      _liveRadius = controller.brushSize * shorter / (scale == 0 ? 1 : scale);
    }

    setState(() {
      _liveImage.add(at);
      _liveCanvas.add(doc);
    });
  }

  /// _layerReach is how near a layer handle, in document units, a press is.
  double get _layerReach => (handleSize / 2 + handleHitSlop) / _scale;

  /// _layerKnob is [space]'s turning knob, above the middle of its top.
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
    // A brush in hand: its ring and, cloning, where it copies from.
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
    // A mask tool in hand: no boxes, just the picture, its mask and the ring.
    if (controller.imageTool.masks && picked != null) {
      var on = _maskPicture(e);
      if (controller.maskBusy == null && _mode != _DragMode.imageQuick) {
        _quickTrail = const [];
      }
      var brushes = controller.imageTool == ImageTool.brush ||
          controller.imageTool == ImageTool.quick ||
          controller.imageTool == ImageTool.refine;
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
    // Layered, the base picture has its own place (see ImageLayer.basePlace)
    // and is handled as a picture layer, without the knob: it turns with the
    // element.
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

  /// _warpSpace maps the warp grid of layer [id] of [e] between fractions of
  /// the picture's box and canvas points, and back, through the element's
  /// turn and slant and the layer's turn and mirror.
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

  List<Offset> _warpPoints(ImageElement e, String id) {
    var (toDoc, _) = _warpSpace(e, id);
    return [for (var f in controller.warpOf(e, id).grid) toDoc(f)];
  }

  /// _warpBox is the box and knob round two or more picked warp points.
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

  /// _pressWarp is a press on a shown warp grid: the box's knob or a corner
  /// turns or sizes the picked points; a point is picked (Shift toggles) and
  /// dragged; inside the box drags them all; elsewhere a box picks points.
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

  /// _dragWarp carries the picked points to [doc]: moved, sized about their
  /// box's middle by the pointer's change in distance, or turned about it.
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

  /// _pressLayers is a press at [doc] on [e] with its layers open: the picked
  /// layer's knob or handles, then the topmost picture layer under it, then
  /// the base picture. False if it missed the picture, which closes it.
  bool _pressLayers(ImageElement e, Offset doc) {
    if (controller.warpLayer case var id?) return _pressWarp(e, id, doc);
    var picked = controller.pickedLayer;
    // A locked layer is not drawn on, masked or moved. The press is still the
    // picture's, so it stays open.
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
      // Shift or Command toggles it into the picks; a press on one already
      // picked keeps the others, so they move together.
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
    // A locked base picture is not picked or moved; the press only keeps the
    // picture open.
    if (controller.layerLocked(under)) {
      _mode = _DragMode.none;
      return true;
    }
    controller.pickImageLayer(baseLayerId);
    // Layered, the base picture moves about the frame like a picture layer.
    if (e.layered) {
      var base = e.layerById(baseLayerId)!;
      if (LayerSpace(e, base).contains(doc)) {
        return _holdLayer(base, _DragMode.imageLayerMove, -1);
      }
      _mode = _DragMode.none;
      return true;
    }
    // Otherwise the base picture fills its frame, so moving it shifts it
    // inside the frame, which only a cover-fitted picture has room to do. See
    // ImageFraming.
    if (e.hasImage && e.fit == ImageFit.cover) {
      _framingStart = e.framing;
      _mode = _DragMode.imageFrame;
      controller.beginInteraction();
    } else {
      _mode = _DragMode.none;
    }
    return true;
  }

  /// _maskPicture is where the picked layer draws its picture, once loaded.
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

  /// _pressMask is a press with a mask tool: a click for a subject, or a
  /// mark's start. On the picture, or near enough for a stroke to start off
  /// its edge; further off it misses.
  bool _pressMask(ImageElement e, Offset doc) {
    var on = _maskPicture(e);
    if (on == null) return _containsPoint(e, doc);
    var f = on.toPicture(doc);
    bool within(double v) => v >= 0 && v <= 1;
    var inside = within(f.dx) && within(f.dy);
    if (!inside && !_containsPoint(e, doc)) return false;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var hide = controller.maskHide != alt;
    // Pixel-reading tools have no pixels on an adjustment, a texture, a
    // colour or paint.
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
      // A point every half picture pixel or so is all a stroke can show, and
      // strokes are kept in the document.
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

  Offset _frameFraction(ImageElement e, Offset doc) {
    var space = LayerSpace(e, ImageLayer.base);
    var p = space.toFrame(doc) - space.inner.topLeft;
    return Offset(p.dx / math.max(1e-9, space.inner.width),
        p.dy / math.max(1e-9, space.inner.height));
  }

  /// _pressBrush starts a paint or retouch stroke, or, cloning with Option,
  /// sets where to copy from.
  bool _pressBrush(ImageElement e, Offset doc) {
    var tool = controller.imageTool;
    var alt = HardwareKeyboard.instance.isAltPressed;
    var pressure = _penSample(doc).pressure;
    if (!tool.retouches) {
      // Anywhere on a picture that does not clip: the frame grows to take
      // the paint. One that clips paints only inside itself.
      if (e.clip && !_containsPoint(e, doc)) return false;
      controller.beginInteraction();
      // Paint goes on a paint layer: one is made over the picked layer if it
      // is not one, in the same step as the stroke.
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
    // Across the whole frame, strokes belong to a paint layer, in fractions
    // of the frame; on one picture, to it, in fractions of it.
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
      // Its own layer at the top of the picture, in the same step as the
      // stroke, unless a paint layer is picked. See
      // CanvasController.retouchLayerForFrame.
      controller.retouchLayerForFrame();
      controller.changePaint((s) => [...s, mark], transient: true);
    } else {
      controller.changeRetouch((s) => [...s, mark], transient: true);
    }
    // Across the whole frame, measured in the frame at each step: it grows
    // as the stroke passes its edge.
    _strokeAt = whole
        ? (doc) => _frameFraction(controller.editingImage!, doc)
        : on.toPicture;
    _mode = _DragMode.imageBrush;
    return true;
  }

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

  void _dragLayer(Offset doc) {
    var e = controller.editingImage, was = _layerStart;
    if (e == null || was == null) return;
    var start = e.withLayer(was.id, (_) => was);
    var space = LayerSpace(start, was);
    var carried = e;
    ImageLayer next;
    switch (_mode) {
      case _DragMode.imageLayerMove:
        // The travel in the frame's unturned space, so a turned picture moves
        // the way the pointer does.
        var travel = space.toFrame(doc) - space.toFrame(_dragStart);
        var rect = space.rect.shift(travel);
        next = was.placed(layerPlace(space.inner, rect), turn: was.turn);
        for (var other in _layersMoved) {
          var at = layerRect(space.inner, other.place).shift(travel);
          carried = carried.withLayer(
              other.id,
              (_) =>
                  other.placed(layerPlace(space.inner, at), turn: other.turn));
        }
      case _DragMode.imageLayerSize:
        // Corners keep proportions if the picture holds them (Keep its
        // proportions); Shift does the opposite.
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

  /// _framedPicture is the element being reframed and its picture.
  (ImageElement, ui.Image)? _framedPicture() {
    var id = _framing;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! ImageElement) return null;
    var image = controller.images.original(element.assetId);
    return image == null ? null : (element, image);
  }

  /// _framingPlacement is where the picture is drawn, from what draws it.
  ImagePlacement? _framingPlacement(ImageElement e, ui.Image image) {
    var inner = _framingRect(e);
    if (inner.width <= 0 || inner.height <= 0) return null;
    return placeImage(
        Size(image.width.toDouble(), image.height.toDouble()), inner, e.fit,
        crop: e.crop, framing: e.framing);
  }

  /// _framingRect is where the reframed picture is drawn: its frame, or,
  /// layered, its own place in the frame, which is less than the whole once
  /// the frame grows round a layer or stroke.
  Rect _framingRect(ImageElement e) {
    var inner = e.box.inner(e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion));
    if (!e.layered) return inner;
    var base =
        e.stack.firstWhere((l) => l.isBase, orElse: () => ImageLayer.base);
    return layerRect(inner, base.place);
  }

  /// _framingView is the whole reframed picture, placed where its visible
  /// part is, for the painter.
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

  /// _startGuideDrag takes a guide, or pulls a new one out of a ruler, and
  /// says whether it did. A press in a ruler always means a new guide; near a
  /// line, that line, unless guides are locked or hidden.
  bool _startGuideDrag(Offset stage, Offset doc) {
    var guides = document.guides;
    if (!guides.showGuides) return false;

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

  /// _rulerUnder is the ruler under the pointer, as the axis of the guide it
  /// makes, or null. The strips come from what draws them, so what can be
  /// dragged from is what is seen.
  GuideAxis? _rulerUnder(Offset stage) {
    if (!document.guides.showRulers) return null;
    var rulers = document.guides.rulers;
    if (!rulers.any) return null;
    // The strips are at the window's edges, the page scrolled under them.
    return rulerBandsFor(_pageRect.shift(-_scrolled), _visible, rulers)
        .axisAt(stage - _scrolled);
  }

  /// _applyGuide moves the dragged guide, snapped so it can sit on a
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

  /// _finishGuide drops the guide, or removes it if dragged off the canvas.
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

  /// _applyFraming moves the picture inside its frame by the pointer's travel
  /// since the press. Travel is in canvas units and framing in fractions of
  /// the slack, so it converts through the placement and follows the pointer
  /// at any zoom. Dragging right moves the picture right.
  void _applyFraming(Offset doc) {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null) return;
      // Canvas units per picture pixel.
      var perPixel = placement.src.width <= 0
          ? 0.0
          : placement.dst.width / placement.src.width;
      if (perPixel <= 0) return;
      var slack = placement.slack;

      // Undo the element's rotation and mirror, so the picture moves with
      // the pointer.
      var travel = doc - _dragStart;
      var a = -e.movedRotationAt(controller.frame, controller.document,
            live: controller.liveMotion) * math.pi / 180;
      if (a != 0) {
        travel = Offset(travel.dx * math.cos(a) - travel.dy * math.sin(a),
            travel.dx * math.sin(a) + travel.dy * math.cos(a));
      }
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

  /// _previewPlacement is where the held stroke's preview is drawn.
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

  /// _refreshPreview rebuilds the held stroke's preview when the stroke or
  /// its settings change, keyed on the settings rather than every notify.
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

    // Once the settings stop moving. A last keystroke is only told by
    // waiting, so the stroke goes through the same delay.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(_previewDelay, () {
      if (!mounted || _previewOf != key) return;
      // Coloured by the brush's hardness at each pixel, which is judged.
      strokePreview(source, stroke).then((image) {
        if (!mounted || _previewOf != key) return;
        setState(() => _preview = image);
      });
    });
  }

  /// _commitStroke writes the finished stroke onto the picture as one change
  /// for the gesture: one pass over the pixels, one undo step.
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

    // A marking brush teaches the learning method; the other two rub out and
    // restore. Which is kept with the stroke, since another brush may be
    // picked before it is applied.
    var teaching = controller.retouch.teaches;

    // Held, not applied, so the brush can be adjusted while the same stroke
    // redraws: see CanvasController.holdStroke.
    controller.holdStroke(picture.id, points,
        keeps: controller.retouch.keeps,
        teaches: teaching,
        fills: controller.retouch.fills);
    controller.endInteraction();
  }

  TeamElement? _selectedTeam() {
    var selected = controller.selected;
    return selected is TeamElement ? selected : null;
  }

  /// _hitAnyPlayer is the topmost player of any team under [doc]. Team boxes
  /// are ignored: a player is placed as a fraction of one but not confined
  /// to it, and two teams on one pitch overlap.
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

  /// _hitPlayer is the topmost of [team]'s players under [doc], or null. A
  /// locked player cannot be hit, so a run can be dragged through a pinned
  /// back four.
  int? _hitPlayer(TeamElement team, Offset doc) {
    var rx = team.dotWidth / 2;
    var ry = team.dotHeight / 2;
    if (rx <= 0 || ry <= 0) return null;
    var ground = teamGround(document, team, controller.frame);

    for (var i = team.players.length - 1; i >= 0; i--) {
      var spot = team.players[i];
      if (spot.locked || spot.hidden) continue;
      // Where the pitch draws them on this frame.
      var at = playerPlace(ground, team, spot, controller.frame);
      if (!at.shown) continue;
      var d = doc - at.centre;
      var own = spot.ball ? team.radiusOf(spot) : null;
      var sx = (own ?? rx) * at.size, sy = (own ?? ry) * at.size;
      // Tested against the ellipse, so gaps between dots in a tight back four
      // stay gaps.
      if ((d.dx * d.dx) / (sx * sx) + (d.dy * d.dy) / (sy * sy) <= 1) return i;
    }
    return null;
  }

  /// _applyPlayerMove drags a player of the selected team, stored as a
  /// fraction of the team's box so it stays put when the team moves or
  /// resizes.
  void _applyPlayerMove(Offset doc) {
    var team = _selectedTeam();
    if (team == null ||
        _playerIndex < 0 ||
        _playerIndex >= team.players.length) {
      return;
    }
    var spot = team.players[_playerIndex];
    var at = doc - _playerGrab;

    // On a pitch the pointer is carried onto the field and the player kept
    // in its metres, so the player goes wherever the pitch goes.
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

    // A player animates like anything else: with the document animated and
    // auto-keyframe on or the player already moving, the drag writes a
    // keyframe on their track rather than their lined-up place.
    var animating = controller.document.isAnimated &&
        (controller.autoKeyframe || (spot.track?.isEmpty == false));

    if (animating) {
      var rest = team.centreOf(spot);
      // Seeded at the start, so a drag at frame 12 is a run from where he
      // was, not a move for the whole document. See ElementTrack.seededFor.
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
    // And the elements themselves, for a resize that scales what is inside:
    // its factor is measured from the drag's start.
    _startElements = {
      for (var e in controller.selectedElements) e.id: e,
    };
    // Where each element is on this frame, which a move works from. A resize
    // works from the resting bounds instead: it writes the base size, and a
    // posed size would bake a scale in. A move from the resting bounds would
    // lose the frame's pose.
    _startPosed = {
      for (var e in controller.selectedElements)
        e.id: e.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion),
    };
    // The box the handles are on, bigger than the element's own for a line
    // or path (see _visualBounds). A resize is measured against it and
    // applied to the real rectangle in proportion.
    _startVisual = {
      for (var e in controller.selectedElements) e.id: _visualBounds(e),
    };
    _startRotation = {
      for (var e in controller.selectedElements) e.id: e.rotation,
    };
    controller.beginInteraction();
  }

  /// _selectedChartLabels are the lone selected chart's placed labels.
  List<Rect> _selectedChartLabels() {
    var element = controller.selected;
    if (element is! ChartElement || !controller.showHelpers) return const [];
    return chartLabelPlaces(element, element.movedBoundsAt(controller.frame, controller.document,
            live: controller.liveMotion))
        .values
        .where((r) => !r.isEmpty)
        .toList();
  }

  /// _selectedTableColumns are the selected table's inner column rules, as
  /// (x, top, bottom), for grips.
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

  /// _docSlop is the pointer's reach in document units: the slop is in
  /// screen pixels (how still a hand is), so divided by the zoom.
  double get _docSlop => handleHitSlop / _scale;

  /// _applyPart writes a part-drag onto the selected element (stage_parts.dart
  /// works out the new element). Transient: the drag is one undo step.
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

  ChartLabelGrab? _labelGrab;

  /// _columnGrab is the dragged divider: the index of the column to its left.
  int? _columnGrab;

  /// _pressMarkerNote takes a press on the held marker's canvas label.
  bool _pressMarkerNote(Offset doc) {
    var note = controller.holdingMarker;
    if (note == null || controller.gaming) return false;
    var laid = markerNoteLayout(controller.document.size.size, note);
    var sizing = laid.corner.contains(doc);
    if (!sizing && !laid.box.contains(doc)) return false;
    controller.beginInteraction();
    _noteWas = note;
    _noteSizing = sizing;
    _noteFrom = doc;
    _mode = _DragMode.none;
    return true;
  }

  /// _dragMarkerNote moves the held marker's label, or sizes it by the
  /// pointer's distance from its middle.
  void _dragMarkerNote(Offset doc) {
    var was = _noteWas!;
    var page = controller.document.size.size;
    TimelineAction next;
    if (_noteSizing) {
      var centre =
          Offset(was.noteAt.dx * page.width, was.noteAt.dy * page.height);
      var from = (_noteFrom - centre).distance;
      var ratio = from < 1 ? 1.0 : (doc - centre).distance / from;
      next = was.copyWith(
          noteSize: (was.noteSize * ratio).clamp(0.3, 6.0).toDouble());
    } else {
      var by = doc - _noteFrom;
      next = was.copyWith(
          noteAt: Offset((was.noteAt.dx + by.dx / page.width).clamp(0.0, 1.0),
              (was.noteAt.dy + by.dy / page.height).clamp(0.0, 1.0)));
    }
    replaceMarker(controller, next, transient: true);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_inLive) return;
    _pointer = event;
    if (_noteWas != null) {
      _dragMarkerNote(_toDocument(event.localPosition));
      return;
    }
    // Pressed as well as hovering: the brush ring must follow a stroke.
    _hoverAt = event.localPosition;
    if (_brushAt != null) _moveBrush(event.localPosition);
    if (_keyDown case (var e, var key)?
        when (event.localPosition - _pressedAt).distance > _buttonClickSlop) {
      controller.noteOff(e, key);
      _keyDown = null;
    }
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

    if (_mode == _DragMode.flow) {
      setState(() => _flowAt = event.localPosition);
      return;
    }

    // Nothing moves until the press travels far enough to be a drag, except
    // the marquee, drawn from the press itself.
    if (!_travelled && _mode != _DragMode.marquee) {
      if ((event.localPosition - _pressedAt).distance <= _dragThreshold) {
        return;
      }
      _travelled = true;
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
        if (controller.spritePaint case var session?) {
          unawaited(session.strokeTo(doc));
        }
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
          // A hand that shifts a little as it clicks puts a corner down:
          // handles a few pixels long would round it off.
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
      case _DragMode.synthKnob:
        _turnSynthKnob(doc);
      case _DragMode.codeScrub:
        if (document.elementById(_codeScrub ?? "") case CodeElement e) {
          controller.seekCode(codeTrackSeconds(e, doc));
        }
      case _DragMode.codeDivider:
        if (_codeDivider case (var id, var d)?) {
          if (document.elementById(id) case CodeElement e) {
            controller.replaceElement(codeDividerDragged(e, d, doc),
                transient: true);
          }
        }
      case _DragMode.codeTab:
        if (_codeTabAt != null ||
            (_toStage(doc) - _pressedAt).distance > _buttonClickSlop) {
          setState(() => _codeTabAt = doc);
        }
      case _DragMode.synthScreen:
        if (_synthScreen case (var id, var grab)?) {
          if (document.elementById(id) case SynthModuleElement e) {
            controller.setSynth(
                synthScreenDragged(e, grab, synthPanelPoint(e, doc)),
                transient: true);
          }
        }
      case _DragMode.synthCable:
        if (_synthCable case var c?) {
          setState(() => _synthCable = (
                from: c.from,
                port: c.port,
                out: c.out,
                lifted: c.lifted,
                at: doc
              ));
        }
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

  /// _otherBounds is everything not dragged, locked included, to snap to.
  List<Rect> _otherBounds() {
    if (!document.guides.snapTo.objects) return const [];
    var moving = _startPosed.keys.toSet();
    return [
      for (var element in document.elements)
        if (!moving.contains(element.base.id) && element.base.visible)
          element.bounds,
    ];
  }

  Rect? _startBoxOfSelection() {
    Rect? box;
    for (var entry in _startPosed.entries) {
      box = box == null ? entry.value : box.expandToInclude(entry.value);
    }
    return box;
  }

  void _applyMove(Offset delta) {
    if (_shiftHeld) {
      delta = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    // Snapped once, against the whole selection's box, so things moved
    // together stay together. Alt turns it off.
    var box = _startBoxOfSelection();
    // Not on a 3D stage, where page lines mean nothing: staged elements snap
    // to the floor's 3D steps (see CanvasController.movedTo).
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
      // A camera moves by where it looks, from its start: its frame is not
      // its box (see cameraFraming).
      if (_startElements[entry.key] case CameraElement start) {
        next = next.withElement(controller.cameraShifted(start, delta));
        continue;
      }
      // Through the controller, so an animated element is posed rather than
      // moved. See CanvasController.posesRatherThanMoves.
      next = next.withElement(
          controller.movedTo(element, entry.value.topLeft + delta));
    }
    controller.apply(next, transient: true);
  }

  /// _applyLineEnd drags one end of a single straight line, if [handle] is
  /// on one, and says whether it did. A line is its two ends, not a box (a
  /// box is at least eight pixels deep, so a line could never be level). The
  /// end snaps to level, upright or diagonal within a few degrees, always
  /// with Shift; Alt frees it.
  bool _applyLineEnd(StageHandle handle, Offset delta) {
    if (_startVisual.length != 1 || !_frameOfSelection.upright) return false;
    // The line at the drag's start: every step works from it, since crossing
    // one end past the other swaps the ends and their arrows.
    var line = _startElements[_startVisual.keys.first];
    if (line is! LineElement || line.curvature != 0 || line.locked) {
      return false;
    }
    var was = line.bounds;
    var start = line.flipped ? was.bottomLeft : was.topLeft;
    var end = line.flipped ? was.topRight : was.bottomRight;
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

  /// _applyCameraZoom zooms the one selected camera by a handle dragged
  /// [delta], and says whether it did: out shows more, in less, about the
  /// frame's middle, which keeps the page's shape.
  bool _applyCameraZoom(StageHandle handle, Offset delta) {
    if (_startElements.length != 1) return false;
    var start = _startElements.values.first;
    if (start is! CameraElement || start.locked) return false;
    var frame = _startPosed[start.id];
    if (frame == null) return false;
    var mid = frame.center;
    double? ratio(double edge, double centre, double by) {
      var was = edge - centre;
      if (was.abs() < 1e-6) return null;
      return (was + by) / was;
    }

    var rx = handle.movesLeft
        ? ratio(frame.left, mid.dx, delta.dx)
        : handle.movesRight
            ? ratio(frame.right, mid.dx, delta.dx)
            : null;
    var ry = handle.movesTop
        ? ratio(frame.top, mid.dy, delta.dy)
        : handle.movesBottom
            ? ratio(frame.bottom, mid.dy, delta.dy)
            : null;
    var grow = math.max(rx ?? 0, ry ?? 0);
    if (grow <= 0) grow = 0.05;
    controller.apply(
        document.withElement(controller.cameraZoomed(start, 1 / grow)),
        transient: true);
    return true;
  }

  /// _applySkew slants the one selected element by a side handle dragged
  /// [delta]: top or bottom across, left or right up and down. The held side
  /// follows the pointer and the opposite stays put, so the element slants
  /// about its middle and moves by half as much.
  void _applySkew(Offset delta) {
    var handle = _handle;
    if (handle == null || _startElements.length != 1) return;
    var start = _startElements.values.first;
    if (start.locked) return;
    var box = start.bounds;
    // The drag in the element's turned frame but not its slanted one: the
    // slant is what changes.
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
    if (_applyCameraZoom(handle, delta)) return;

    // The dragged edge lands on the lines a move does: upright boxes only,
    // and Alt turns it off.
    if (_frameOfSelection.upright && !HardwareKeyboard.instance.isAltPressed) {
      delta = _snapResize(handle, delta);
    } else {
      _snappedTo = null;
    }

    // Into the element's own frame, so pulling a tilted element's right edge
    // widens it rather than moving it sideways.
    delta = _frameOfSelection.invert(delta);

    // One box for the whole drag, so things resized together keep their sizes
    // and gaps in proportion.
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

    // Shift keeps proportions, by whichever axis moved further. A picture
    // keeps them without the key, Shift freeing it (see
    // CanvasElement.keepsAspect), as does a group: pulled out of shape, every
    // gap would be.
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

    // A minimum size, not a selection turned inside out: a negative width
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
      var start = entry.value;
      var real = _startBounds[entry.key] ?? start;

      // Keeping proportions scales everything inside (type, spacing, a chip's
      // padding), from the element at the drag's start.
      var from = _startElements[entry.key] ?? element;
      element = keep ? from.scaledBy(sx) : element;
      next = next.withElement(element.withBase(
        x: left + (real.left - group.left) * sx,
        y: top + (real.top - group.top) * sy,
        width: math.max(1, real.width * sx),
        height: math.max(1, real.height * sy),
        // The scale applied inside the box, kept where the shape switch reads
        // it (see ElementBase.typeScale), so a shape change does not undo the
        // drag by the wrong amount.
        typeScale: keep ? from.base.typeScale * sx : null,
      ));
    }
    controller.apply(next, transient: true);
  }

  /// _snapResize snaps the dragged edge alone onto a line, against the union
  /// of what is resized.
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

  String? _anchorOf;

  /// _anchorsShown is each selected element's shown anchor and whether it
  /// is locked.
  List<({Offset at, bool locked})> _anchorsShown() => [
        for (var id in controller.selection)
          if (controller.anchorShown(id))
            if (document.elementById(id) case var e?)
              (at: e.anchorAt(controller.frame), locked: e.base.anchorLocked),
      ];

  /// _anchorUnder is the element whose shown, unlocked anchor is at [stage].
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
    // One element turns about its anchor, which stays put.
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
      if (_shiftHeld) rotation = (rotation / 15).round() * 15;
      next = next.withElement(element.turnedTo(rotation));
    }
    controller.apply(next, transient: true);
  }

  void _onPointerUp(PointerEvent event) {
    if (_liveTapPending) {
      _liveTapPending = false;
      _replayTap(event.position);
      return;
    }
    if (_inLive) {
      _inLive = false;
      return;
    }
    if (_noteWas != null) {
      _noteWas = null;
      controller.endInteraction();
      return;
    }
    if (_releaseSynth(_toDocument(event.localPosition))) return;
    if (_releaseCode(_toDocument(event.localPosition))) return;
    var codeEdit = _pendingCodeEdit;
    _pendingCodeEdit = null;
    if (document.elementById(codeEdit?.$1 ?? "") case CodeElement e
        when codeEdit != null &&
            (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      if (controller.playing) controller.pause();
      _codeEditBegun = false;
      controller.editCodePane(e, codeEdit.$2);
      return;
    }
    _legendHold?.cancel();
    _legendHold = null;
    if (_painting != null) {
      _commitStroke();
      return;
    }
    _playerIndex = -1;

    // A press on a selected button that never became a drag is a click,
    // which runs it. Measured in stage pixels, so it holds at any zoom.
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

    var sheet = _pendingSheet;
    _pendingSheet = null;
    if (sheet != null &&
        (event.localPosition - _pressedAt).distance <= _buttonClickSlop) {
      controller.endInteraction();
      _mode = _DragMode.none;
      _handle = null;
      controller.sheetPressed(
          sheet,
          sheet.movedBoundsAt(controller.frame, controller.document,
              live: controller.liveMotion),
          _pendingSheetAt);
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
        controller.pickVectorShape(_vectorShapeUnder);
      } else if (!_vectorPressedOutside && !_shiftHeld) {
        // A click on empty space unpicks.
        controller.pickVectorShape(-1);
      } else if (_vectorPressedOutside && !_travelled) {
        // A click off the drawing finishes editing, and does what it would
        // have.
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
      // Re-baked once at the end, not every pixel: a route is dozens of
      // keyframes.
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
      if (controller.spritePaint case var session?) {
        unawaited(session.strokeEnd());
      }
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
      // Left on the canvas until the cut lands, so the stroke does not vanish
      // meanwhile.
    }
    // A still press on the stage with the page locked is a click on nothing:
    // it clears the selection.
    if (_lockedPress && !_travelled) controller.clearSelection();
    _lockedPress = false;
    if (_gizmoDrag != null) setState(() => _gizmoDrag = null);
    _mode = _DragMode.none;
    _handle = null;
    _maskOn = null;
    _strokeAt = null;
    if (_snappedTo != null) setState(() => _snappedTo = null);
  }

  /// _backgrounds caches generated backgrounds, rasterised once while the
  /// design and size hold still. Shared by every canvas on screen, with room
  /// for a few, so the facing leaf and pages in transition keep theirs. See
  /// ProceduralCache.
  final ProceduralCache _backgrounds = ProceduralCache();

  /// _hoverAt is the pointer's last stage position, for the cursor.
  Offset _hoverAt = Offset.zero;

  /// _updateHover keeps the renderer told what is under the pointer.
  void _updateHover(Offset stage) {
    _hoverAt = stage;
    _hoverCode(stage);
    // For a Look at that faces the pointer.
    controller.stagePointer = _toDocument(stage);
    controller.tilePaint?.hoverAt(_toDocument(stage));
    if (controller.editingImage != null &&
        (controller.imageTool == ImageTool.brush ||
            controller.imageTool == ImageTool.quick ||
            controller.imageTool == ImageTool.refine ||
            controller.imageTool.paints)) {
      setState(() {});
    }
    var doc = _toDocument(stage);
    var hot = _gizmo()?.hit(doc, _gizmoReach);
    if (hot != _gizmoHot) setState(() => _gizmoHot = hot);
    var element = _hitElement(doc);
    var id = element is ButtonElement ? element.id : null;

    String? counter;
    var at = -1;
    if (element is CounterElement && element.live) {
      at = _counterButtonAt(element, doc);
      if (at >= 0) counter = element.id;
    }

    // Whether a click here presses something, for the cursor.
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

  /// _hoverPressable is whether a click here would press a selected button,
  /// speaker or video control, or a live counter's button.
  bool _hoverPressable = false;

  // ---------------------------------------------------------- 3D stage

  /// _gizmoDrag is the gizmo at the drag's start, the part held, the page
  /// point taken, and the element's id.
  (StageGizmo, GizmoPart, Offset, String)? _gizmoDrag;

  GizmoPart? _gizmoHot;

  /// _lockedPress is whether this press took the camera of a locked page.
  bool _lockedPress = false;

  /// _gizmoReach is how near a part, in page units, the pointer must be.
  double get _gizmoReach => 9 / (_scale == 0 ? 1 : _scale);

  /// _gizmo is the gizmo on the lone selected staged element, or null.
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

  /// _pressLockedStage takes the stage's camera, with the page locked, for a
  /// press on the stage itself (not on anything standing on it) or the
  /// middle button anywhere: a drag orbits; shifted, or middle, it pans.
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

  /// _steerTimer closes a run of camera steering as one undo step.
  Timer? _steerTimer;

  void _steering() {
    if (_steerTimer == null) controller.beginInteraction();
    _steerTimer?.cancel();
    _steerTimer = Timer(const Duration(milliseconds: 350), () {
      _steerTimer = null;
      controller.endInteraction();
    });
  }

  /// _steerByScroll is the wheel or two fingers with the page locked on a
  /// stage: orbit, Shift to pan, Command or Control (a pinch, to the wheel)
  /// to zoom.
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

  /// _scrollPhysics holds the page still while locked or over code.
  ScrollPhysics? get _scrollPhysics =>
      controller.pageLocked || _codeOver != null
          ? const NeverScrollableScrollPhysics()
          : null;

  double _pinchScale = 1;

  /// _wheelRests closes a run of wheel turns as one change.
  Timer? _wheelRests;

  void _onScroll(PointerScrollEvent event) {
    // While reframing, the wheel zooms the picture, not the view: drag to
    // choose what is in shot, scroll to choose how much.
    if (_framing != null) {
      var framed = document.elementById(_framing!);
      if (framed is ImageElement) {
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

    // About the pointer, so the corner scrolled in on stays put.
    _zoomAbout(event.localPosition,
        controller.zoom * (event.scrollDelta.dy > 0 ? 0.9 : 1.1));
  }

  /// _zoomAbout zooms to [zoom], keeping the page point under [stage] put.
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

  /// _pinch is the zoom, view, scale and page point a pinch began from.
  ({double zoom, Offset pan, double scale, Offset doc})? _pinch;

  void _onPinchStart(PointerPanZoomStartEvent e) {
    _codePinch = _codePaneAt(e.localPosition);
    // Locked, the page does not zoom: on a stage the fingers steer the camera
    // instead (see _onPinchUpdate).
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
  /// are. A two-finger slide alone is the scroll views' to handle.
  void _onPinchUpdate(PointerPanZoomUpdateEvent e) {
    if (_codePinch case var at? when (e.scale - 1).abs() < 0.01) {
      _scrollCodeBy(at, -e.panDelta.dy);
      return;
    }
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

  void _onPinchEnd(PointerPanZoomEndEvent e) {
    _pinch = null;
    _codePinch = null;
  }

  // ------------------------------------------------------------------------

  /// _onKey is the canvas's keyboard. Arrows move the selection, or walk the
  /// frames with none; Alt swaps the two. Space plays and stops.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // A running game has the keys. See gameKey.
    if (controller.gaming) return KeyEventResult.handled;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (isTypingInAField()) return KeyEventResult.ignored;
    var keys = HardwareKeyboard.instance;
    var nudging = controller.selection.isNotEmpty != keys.isAltPressed;
    var step = keys.isShiftPressed ? 10.0 : 1.0;

    // Cmd or Control, so a Mac with a PC keyboard works too.
    var command = keys.isMetaPressed || keys.isControlPressed;
    if (command) {
      // While a drawing is edited, these act on its points, not elements.
      if (controller.editingVector != null) {
        var done = switch (event.logicalKey) {
          LogicalKeyboardKey.keyA => controller.pickAllVectorPoints(),
          LogicalKeyboardKey.keyC => controller.copyVectorPoints(),
          LogicalKeyboardKey.keyX => controller.cutVectorPoints(),
          LogicalKeyboardKey.keyV => controller.pasteVectorPoints(),
          _ => false,
        };
        if (done) return KeyEventResult.handled;
        // With no points to act on: nothing, not the whole drawing.
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

    var arrow = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (arrow != null && _nudgeWarp(arrow)) return KeyEventResult.handled;

    // Page and stage letters, unless a picture or drawing is edited (they
    // have their own): L locks the page, Shift-S snaps; on a 3D stage G, R
    // and S are the 3D tools, F frames the selection, Home resets the camera.
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
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace
          when controller.editingImage != null &&
              controller.imageLayer != baseLayerId:
        controller.removeImageLayer(controller.imageLayer);
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
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter
          when controller.vectorPenShape >= 0:
        controller.finishPenShape();
      // A picture's tools, while its layers are open.
      case LogicalKeyboardKey.keyV when controller.editingImage != null:
        controller.imageTool = ImageTool.move;
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
      // X inverts the mask tools, as it swaps colours elsewhere.
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
      // A drawing's tools, while it is edited; a tool's key again goes back
      // to picking.
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
        // One thing at a time: a warp grid's picked points, then the grid,
        // then the picture's frame, then the selection.
        if (controller.warpLayer != null && controller.warpPicks.isNotEmpty) {
          controller.warpPicks = const {};
        } else if (controller.warpLayer != null) {
          controller.editWarp("", "", on: false);
        } else
        if (controller.editingImage != null &&
            controller.imageTool == ImageTool.clone &&
            controller.cloneFrom != null) {
          controller.cloneFrom = null;
        } else if (controller.editingImage != null &&
            controller.imageTool != ImageTool.move) {
          controller.imageTool = ImageTool.move;
        } else if (controller.editingImage != null) {
          controller.editImage(null);
        } else if (controller.vectorEditing != null) {
          // Out of a drawing a step at a time: the pen's shape, the pen, the
          // picked points, then the editing.
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
          controller.placingCopies = null;
        } else if (controller.selected case var e?
            when controller.copiesPicked(e.id)) {
          // Copies picked: back to all of them, then the element.
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
    // Cheap unless the stroke or its settings changed: see _refreshPreview.
    _refreshPreview();
    return _buildStage();
  }

  Widget _buildStage() => LayoutBuilder(
        builder: (context, constraints) {
          _visible = Size(constraints.maxWidth, constraints.maxHeight);
          var content = _contentSize(_visible);
          _viewport = content;
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncScroll());
          // How much the canvas shrank to fit, for the band's percentage.
          _tellControllerTheScale();

          Widget painter = SizedBox(
            width: content.width,
            height: content.height,
            // Not clipped: a long caption in the text editor grows past it.
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                // A cancelled pointer ends its gesture as a release would.
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
                  onExit: (_) {
                    controller.stagePointer = null;
                    if (_codeOver != null) setState(() => _codeOver = null);
                  },
                  // Clipped to the stage's box too: a CustomPainter may draw
                  // outside its bounds, and a zoomed canvas would paint over
                  // the sidebar, band and timeline.
                  child: ClipRect(
                    child: CustomPaint(
                      painter: StagePainter(
                        between: _between,
                        // A tile tried on under the pointer is drawn as a
                        // gesture is, then properly once picked or left.
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
                        // A game's own view; playing, without guide paths.
                        document: controller.gaming || controller.playing
                            ? withoutGuides(controller.gameView ??
                                controller.spoken(document))
                            : controller.spoken(document),
                        frame: controller.frame,
                        previewAt: controller.previewAt,
                        previewing: controller.previewing,
                        markerNote: controller.holdingMarker,
                        markerNoteGrip: !controller.gaming,
                        anchors: _anchorsShown(),
                        scale: _scale,
                        origin: _origin,
                        images: controller.images,
                        hoveredButton: controller.hoveredButton,
                        counterValue: controller.counterValue,
                        liveMotion: controller.liveMotion,
                        motionTick: controller.motionTick,
                        directed: (controller.playing || controller.cameraView) &&
                            !document.editingMaster,
                        counterPressed: (e) =>
                            e.id == _hoveredCounter ? _hoveredCounterAt : -1,
                        counterRunning: controller.counterRunning,
                        counterTick: controller.counterTicks,
                        audioState: controller.audioState,
                        videoShow: controller.videoShow,
                        audioRevision: controller.audioRevision,
                        keysTick: controller.keysHeld.value,
                        selection: {for (var e in _chosen) e.id},
                        // Trail and onion skin while the Chain shows motion.
                        trail: controller.motionTrail &&
                            controller.chainShowsMotion,
                        gameChange: controller.gameChange,
                        pickedCopies: controller.selected == null
                            ? const {}
                            : controller.pickedCopiesOf(controller.selected!.id),
                        showHelpers: controller.showHelpers,
                        // The scene's slow move while it plays (see
                        // SceneCamera); still while editing, so a press lands
                        // where the page looks to be. A game frames the page
                        // its own way, following the player.
                        camera: controller.gaming
                            ? controller.gameFraming
                            : (controller.playing || controller.cameraView) &&
                                !document.editingMaster
                            // Its Camera, or its slow move: see sceneFraming.
                            ? sceneFraming(document, controller.frame,
                                live: controller.liveMotion)
                            : null,
                        selectedPath: _selectedPath(),
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
                              // Points and their box are put away for tools
                              // that pick nothing (and the pencil, unless set
                              // to show them), and while a line's thickness
                              // is dragged, so the line can be watched.
                              bare: _mode == _DragMode.vectorScale ||
                                  controller.vectorTool == VectorTool.shapes ||
                                  _picksShapes ||
                                  controller.vectorTool == VectorTool.text ||
                                  controller.vectorTool == VectorTool.tint ||
                                  controller.vectorTool == VectorTool.shadow ||
                                  controller.vectorTool ==
                                      VectorTool.highlight ||
                                  controller.vectorTool == VectorTool.eraser ||
                                  (controller.vectorTool == VectorTool.pencil &&
                                      !controller.vectorPencilPoints),
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
                              // While a box is dragged, all points show.
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
              if (_synthCable case var c?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CarriedCable(
                          synthJackAt(c.from, c.port, out: c.out),
                          c.at,
                          synthSignalColour((c.out
                                  ? c.from.module.output(c.port)
                                  : c.from.module.input(c.port))!
                              .signal),
                          synthScaleOf(c.from),
                          _scale,
                          _origin),
                    ),
                  ),
                ),
              if (_editorFor() case var editor?) editor,
              if (_codeEditorFor() case var code?) code,
              if (_codeLiveFor() case var live?) live,
              ..._codeTabCarried(),
              if (_typingField() case var typing?) typing,
              if (_brushRing() case var ring?) ring,
              if (_cellEditorFor() case var cell?) cell,
              if (_counterInputFor() case var setting?) setting,
            ]),
          );

          // Scrollable only when there is something to scroll: a scroll view
          // that never scrolls still claims the wheel, which the pan tool
          // zooms with. The vertical bar is the inner view's, drawn at the
          // window's edge.
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
          // A drag on the page (finger, pen or mouse) is the canvas's; the
          // page scrolls by its bars, the wheel and two trackpad fingers.
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

          // The 3D view controls, top right of a scene with a stage, fixed
          // over the scrolling page, hidden while playing. Always in a Stack,
          // so the page is not rebuilt as they come and go.
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

  /// _touchAreas are what a game touches of each played element, shown with
  /// the Game tab open.
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

  /// _cellEditorFor is the overlay for the cell being typed into.
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

  /// _editorFor is the text editor overlay, if open: built here because it
  /// sits in the painting's coordinates, which only the stage knows.
  Widget? _editorFor() {
    var id = _editingText;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! TextElement) return null;

    // The piece the second click landed on, if any, held by id: the element
    // and its list are rebuilt on every keystroke.
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

  /// _itemEditorBoxFor is where an item's editor opens, with room to type.
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

  /// _grownForTyping grows a block for typing from the edge its slot holds,
  /// so the words stay put.
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

  /// _editorBoxFor is where the editor opens: over the words wherever they
  /// are (text on a line is outside its rectangle), not tight round them,
  /// with a minimum to type in, grown about its centre so the text stays put.
  Rect _editorBoxFor(TextElement element) {
    var box = _visualBounds(element);
    // Words in a slot are a block, so the editor opens over it.
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

  /// _onPointerSignal decides whether the wheel belongs to this stage or the
  /// scroll view round it. The pan tool claims it through the resolver, so
  /// zooming wins; the select tool does not, so a tall fit-width canvas
  /// scrolls.
  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    if (_codeOver case var at?) {
      GestureBinding.instance.pointerSignalResolver.register(
          signal,
          (event) =>
              _scrollCodeBy(at, (event as PointerScrollEvent).scrollDelta.dy));
      return;
    }
    // Locked, the wheel is claimed before the scroll views: on a stage it
    // steers the camera, on a page it does nothing.
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
    // With the eraser, the pointer is the brush's ring and nothing more.
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
      return controller.vectorQuickFill
          ? SystemMouseCursors.precise
          : SystemMouseCursors.none;
    }
    if (_mode == _DragMode.rotate) return SystemMouseCursors.grabbing;
    if (_mode == _DragMode.move) return SystemMouseCursors.move;
    if (_mode == _DragMode.guide) return SystemMouseCursors.grabbing;
    if (_rulerUnder(_hoverAt) case var axis?) {
      return axis == GuideAxis.vertical
          ? SystemMouseCursors.resizeLeftRight
          : SystemMouseCursors.resizeUpDown;
    }
    // A picture being reframed is grabbable anywhere inside it.
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

/// _RulerLayer draws the rulers over a scrolling page, at the window's
/// edges: see paintStageRulers.
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

/// _CarriedCable is a synth cable carried from a jack to the pointer, dashed.
class _CarriedCable extends CustomPainter {
  final Offset? jack;
  final Offset at;
  final Color colour;
  final double panelScale, scale;
  final Offset origin;
  const _CarriedCable(this.jack, this.at, this.colour, this.panelScale,
      this.scale, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    var from = jack;
    if (from == null) return;
    paintSynthCable(canvas, from * scale + origin, at * scale + origin, colour,
        panelScale * scale,
        dashed: true);
  }

  @override
  bool shouldRepaint(_CarriedCable old) =>
      old.jack != jack ||
      old.at != at ||
      old.scale != scale ||
      old.origin != origin;
}
