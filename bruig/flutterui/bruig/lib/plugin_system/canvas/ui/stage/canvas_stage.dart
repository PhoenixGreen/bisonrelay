import 'dart:typed_data';
import 'package:bruig/plugin_system/canvas/model/layout_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/layout_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/render/code_task_painter.dart';
import 'package:bruig/plugin_system/canvas/render/play_task_painter.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
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
import 'package:bruig/plugin_system/canvas/ui/stage/stage_hit_test.dart';
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
import 'package:bruig/plugin_system/canvas/ui/stage/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/render/counter_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/stage/stage_keys.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

part 'stage_coordinates.dart';
part 'stage_hit_testing.dart';
part 'stage_press.dart';
part 'stage_vector_tools.dart';
part 'stage_picture_tools.dart';
part 'stage_framing.dart';
part 'stage_drag.dart';
part 'stage_release.dart';
part 'stage_3d_view.dart';
part 'stage_text_pieces.dart';
part 'stage_layouts.dart';

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

  /// pieceMove, pieceSize and pieceTurn move, size or turn a text element's
  /// picture piece by its own box. See stage_text_pieces.dart.
  pieceMove,
  pieceSize,
  pieceTurn,

  /// layoutCut and layoutTrack drag a Layout's cut or grid line, and
  /// layoutCutTurn and -Gutter a cut's tilt and gutter by its knobs;
  /// layoutCellMove, -Size and -Turn a picked Free cell. See
  /// stage_layouts.dart.
  layoutCut,
  layoutCutTurn,
  layoutCutGutter,
  layoutTrack,
  layoutCellMove,
  layoutCellSize,
  layoutCellTurn,

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
  // The parts (stage_*.dart) are extensions, and call setState:
  // overridden so the call is this class's own, not State's protected one.
  @override
  void setState(VoidCallback fn) => super.setState(fn);

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

  /// _gesturePointer is the pointer whose press began the gesture under way,
  /// or null. Another pointer's press, drag and release are ignored until it
  /// is up or cancelled: a second finger would otherwise take the gesture
  /// over and leave the first one's undo step open.
  int? _gesturePointer;

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

  /// _editingClick is where the click that opened the editor landed,
  /// globally, so the caret goes there. See CanvasTextEditor.clickAt.
  Offset? _editingClick;

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
    _forgetGoneEdits();
    setState(() {});
  }

  /// _forgetGoneEdits ends an edit in place whose element has gone, deleted
  /// or with another canvas loaded. Its editor is not built without the
  /// element, so never says it is done: the stage would go on ignoring
  /// presses, and the undo step the typing opened would take in the next
  /// change.
  void _forgetGoneEdits() {
    if (_editingText case var id?
        when document.elementById(id) is! TextElement) {
      _forgetTextEdit();
      controller.endInteraction();
    }
    if (_editingCell case (var id, _, _)?
        when document.elementById(id) is! TableElement) {
      _editingCell = null;
      controller.endInteraction();
    }
    if (_settingCounter case var id?
        when document.elementById(id) is! CounterElement) {
      _settingCounter = null;
      _settingAt = -1;
    }
  }

  // ---- stage_coordinates.dart ---------------------------------------------

  ((CanvasDocument, int, double?), Rect?)? _levelOf;

  /// _syncing is set while the scroll views follow the view, so
  /// _followScroll does not take it for a scroll by hand.
  bool _syncing = false;

  /// _followScroll keeps the view where the page was scrolled by hand, so
  /// the zoom buttons zoom about what is looked at.
  void _followScroll() {
    if (_syncing || !mounted) return;
    var pan = _clampedPan;
    controller.followPan(Offset2(pan.dx, pan.dy));
  }

  // ---- stage_hit_testing.dart ---------------------------------------------

  /// _counterPart is the counter whose loose piece is dragged, and
  /// _counterPartAt which: -2 the words before, -3 after, 0 and up a button.
  String? _counterPart;
  int _counterPartAt = 0;

  /// _liveTapPending is a press that opened a preview live, replayed into
  /// the app on release (_replayTap).
  bool _liveTapPending = false;
  int _replayPointer = 0x7FFF0000;

  // ---- stage_press.dart ---------------------------------------------------

  /// _pressedCopy is the copy of [_pressedCopyOf] a press landed on, picked
  /// if the press is a click.
  String? _pressedCopy, _pressedCopyOf;

  /// _copiesStart and _dragCopies are the copies at the drag's start, and
  /// which are dragged.
  InstanceSet? _copiesStart;
  Set<String> _dragCopies = const {};

  /// _copyPivot is the one copy's anchor, which its box sizes and turns
  /// about and which stays put (see CanvasElement.boundsWith). _copySize and
  /// _copyTurn are its own Size and Turn at the drag's start.
  Offset _copyPivot = Offset.zero;
  double _copySize = 1, _copyTurn = 0;

  /// _pieceStart is the picture piece as it was when its box was pressed,
  /// which a drag of it measures from. See stage_text_pieces.dart.
  TextItem? _pieceStart;

  /// _pieceMiddle is that piece's middle on the page at the press: what it
  /// is sized and turned about.
  Offset _pieceMiddle = Offset.zero;

  /// _layoutStart is a Layout as it was when one of its lines or cells was
  /// pressed, and _layoutCut, _layoutTrack and _layoutMiddle what was
  /// pressed (stage_layouts.dart).
  LayoutElement? _layoutStart;
  LayoutCutLine? _layoutCut;
  LayoutTrackLine? _layoutTrack;
  Offset _layoutMiddle = Offset.zero;

  // ---- stage_vector_tools.dart --------------------------------------------

  VectorPart _vectorPart = VectorPart.point;

  /// _vectorBefore and _vectorFrom are the drawing and press a drag began at.
  VectorElement? _vectorBefore;
  Offset _vectorFrom = Offset.zero;

  /// _vectorShapeUnder is the shape a box began on, picked by a click.
  int _vectorShapeUnder = -1;

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

  /// _itemsBox is the box round the picked shapes at the drag's start, in
  /// drawing units; _itemsHandle the handle held (see boxHandles), -1 for the
  /// turning handle, or null to move the whole.
  Rect _itemsBox = Rect.zero;
  int? _itemsHandle;

  Offset _shapeFrom = Offset.zero;

  /// _shapeGroup, _shapeBox and _shapeHandle are the shape the shapes tool
  /// moves or resizes: its group, its box at the drag's start (drawing
  /// units), and the handle held (see boxHandles), or null for the whole.
  int _shapeGroup = -1;
  Rect _shapeBox = Rect.zero;
  int? _shapeHandle;

  /// _typing holds a drawing's text being typed, in an unseen field that
  /// takes keys, caret moves, selections and input methods; the letters
  /// appear on the drawing. _typingFor is the shape it was last filled from,
  /// so another one refills it.
  final TextEditingController _typing = TextEditingController();
  final FocusNode _typingFocus = FocusNode(debugLabel: "vectorTyping");
  int _typingFor = -1;
  bool _filling = false;

  List<Offset> _knife = const [];

  /// _penRuns is the pencil stroke's stretches on the page, each its own
  /// line.
  List<List<PenSample>> _penRuns = [];

  /// _penInto is the shapes picked as the pencil went down: if one filled
  /// shape, strokes in its colour are added to it (see _mergePencil).
  Set<int> _penInto = const {};

  /// _cornerFrom is the shaped corner's place, a drag's distance's origin.
  Offset _cornerFrom = Offset.zero;

  /// _widths is the points the thickness tool changes, with their widths at
  /// the start; empty when scaling the whole drawing.
  Map<VectorPick, double> _widths = {};
  double _scaleReach = 0;
  bool _sweeping = false;
  bool _scaleLetsGo = false;

  /// _tintWaiting is a tint press off the drawing, not yet a stroke.
  Offset? _tintWaiting;

  /// _stroke is the tint stroke or rub-out being painted, _strokeOn the
  /// shapes it has crossed, and _strokeRubs whether it rubs out. Each growth
  /// is laid on the drawing as it was at the start; see withStrokeOn.
  VectorTint? _stroke;
  Set<int> _strokeOn = {};
  bool _strokeRubs = false;

  /// _brushAt is where the brush ring is drawn; null hides it.
  Offset? _brushAt;

  // ---- stage_picture_tools.dart -------------------------------------------

  // ---- warp grid ------------------------------------------------------

  List<Offset> _warpStartPoints = const [];
  Offset _warpPivot = Offset.zero;
  Offset _warpGrab = Offset.zero;

  // ---- stage_drag.dart ----------------------------------------------------

  /// _selectedTableColumns are the selected table's inner column rules, as
  /// (x, top, bottom), for grips.
  List<(double, double, double)> _selectedTableColumns() {
    var element = controller.selected;
    if (element is! TableElement || element.locked || !controller.showHelpers) {
      return const [];
    }
    var bounds = _hit.posed(element);
    return [
      for (var x in tableColumnDividers(element, bounds))
        (x, bounds.top, bounds.bottom),
    ];
  }

  ChartLabelGrab? _labelGrab;

  /// _columnGrab is the dragged divider: the index of the column to its left.
  int? _columnGrab;

  /// _snappedTo is the lines the drag is caught on, drawn so a snap is seen
  /// rather than felt as a jump.
  SnapResult? _snappedTo;

  String? _anchorOf;

  /// _anchorsShown is each selected element's shown anchor and whether it
  /// is locked.
  List<({Offset at, bool locked})> _anchorsShown() => [
        for (var id in controller.selection)
          if (controller.anchorShown(id))
            if (document.elementById(id) case var e?)
              (at: e.anchorAt(controller.frame), locked: e.base.anchorLocked),
      ];

  // ---- stage_release.dart -------------------------------------------------

  /// _backgrounds caches generated backgrounds, rasterised once while the
  /// design and size hold still. Shared by every canvas on screen, with room
  /// for a few, so the facing leaf and pages in transition keep theirs. See
  /// ProceduralCache.
  final ProceduralCache _backgrounds = ProceduralCache();

  /// _hoverAt is the pointer's last stage position, for the cursor.
  Offset _hoverAt = Offset.zero;

  /// _hoverRuler is the ruler the hover was last over, kept so the stage
  /// rebuilds for the cursor only when that changes, not on every move.
  GuideAxis? _hoverRuler;

  /// _hoverPressable is whether a click here would press a selected button,
  /// speaker or video control, or a live counter's button.
  bool _hoverPressable = false;

  // ---- stage_3d_view.dart -------------------------------------------------

  /// _gizmoDrag is the gizmo at the drag's start, the part held, the page
  /// point taken, and the element's id.
  (StageGizmo, GizmoPart, Offset, String)? _gizmoDrag;

  GizmoPart? _gizmoHot;

  /// _lockedPress is whether this press took the camera of a locked page.
  bool _lockedPress = false;

  /// _steerTimer closes a run of camera steering as one undo step.
  Timer? _steerTimer;

  double _pinchScale = 1;

  /// _wheelRests closes a run of wheel turns as one change.
  Timer? _wheelRests;

  /// _pinch is the zoom, view, scale and page point a pinch began from.
  ({double zoom, Offset pan, double scale, Offset doc})? _pinch;

  // ------------------------------------------------------------------------

  /// _onKey is the canvas's keyboard: the lines of canvasShortcuts heard
  /// while the canvas has it, then the page's (stage_keys.dart).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) =>
      canvasKey(controller, event, reach: ShortcutReach.canvas);

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
                // One pointer at a time: see _gesturePointer.
                onPointerDown: (e) {
                  if (_gesturePointer != null) return;
                  _gesturePointer = e.pointer;
                  _onPointerDown(e);
                },
                onPointerMove: (e) {
                  if (e.pointer == _gesturePointer) _onPointerMove(e);
                },
                onPointerUp: (e) {
                  if (e.pointer != _gesturePointer) return;
                  _gesturePointer = null;
                  _onPointerUp(e);
                },
                // A cancelled pointer ends its gesture without its click.
                onPointerCancel: (e) {
                  if (e.pointer != _gesturePointer) return;
                  _gesturePointer = null;
                  _onPointerUp(e, cancelled: true);
                },
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
                        layoutMarks: _layoutMarks(),
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
    var hit = _hit;
    return [
      for (var e in document.elements)
        if (e.visible && e.base.play.as != PlayAs.none)
          gameTouchArea(e, hit.posed(e)),
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
        tableCellRect(element, _hit.posed(element), row, col);
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
    var shows = editorDrawsWords(element, item);

    // Where the words are laid out, worked out again on every keystroke as
    // the painter does, so the field stays on them -- except text on a line,
    // whose box is frozen where it opened (the letters move as they come).
    var bounds = _hit.posed(element);
    var box = element.curve != null
        ? (_editorRect ??= _editorBoxFor(element))
        : item != null
            ? _wordsBlockFor(element, bounds, item: item, at: at)
            : bodyIsBlock(element)
                ? _wordsBlockFor(element, bounds)
                : bounds;
    var topLeft = _toStage(box.topLeft);
    return CanvasTextEditor(
      key: ValueKey("edit-$id-${item?.id ?? ""}"),
      element: element,
      item: item,
      rect: Rect.fromLTWH(
          topLeft.dx, topLeft.dy, box.width * _scale, box.height * _scale),
      pivot: _toStage(bounds.center),
      scale: _scale,
      showWords: shows,
      clickAt: _editingClick,
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
        if (mounted) setState(_forgetTextEdit);
      },
    );
  }

  /// _forgetTextEdit lets go of the text being typed into.
  void _forgetTextEdit() {
    _editingText = null;
    _editingItem = null;
    _editingClick = null;
    _editorRect = null;
  }

  /// _wordsBlockFor is where a block of words is laid out -- piece [item]
  /// (at [at] in the list), or the element's own words given a slot -- as
  /// wide as the painter lets them grow: the box's inner width less the
  /// piece's own padding, held to the edge its slot holds it to.
  Rect _wordsBlockFor(TextElement element, Rect bounds,
      {TextItem? item, int at = -1}) {
    var inner = element.box.inner(bounds);
    var slot = item?.slot ?? element.slot ?? TextSlot.topLeft;
    var rect = item != null
        ? textItemRects(element, bounds)[at]
        : (textBodyRect(element, bounds) ?? inner);
    var pad = item?.box.pad.insets ?? EdgeInsets.zero;
    if (rect == Rect.zero) {
      // Nothing laid out at all: the slot's corner of the box.
      rect = Rect.fromLTWH(
          switch (slot.across) {
            TextAlignSpec.right => inner.right,
            TextAlignSpec.center => inner.center.dx,
            _ => inner.left,
          },
          inner.top,
          0,
          0);
    }
    var words = pad.deflateRect(rect);
    var spec = item?.spec ?? drawnTextSpec(element, bounds);
    var room = math.max(1.0, inner.width - pad.left - pad.right);
    var left = switch (slot.across) {
      TextAlignSpec.right => words.right - room,
      TextAlignSpec.center => words.center.dx - room / 2,
      _ => words.left,
    };
    return Rect.fromLTWH(left, words.top, room,
        math.max(words.height, spec.fontSize * spec.lineHeight));
  }

  /// _editorBoxFor is where the editor opens over text on a line: over the
  /// words wherever they are (outside its rectangle), not tight round them,
  /// with a minimum to type in, grown about its centre so the text stays put.
  Rect _editorBoxFor(TextElement element) {
    var box = _visualBounds(element);
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
