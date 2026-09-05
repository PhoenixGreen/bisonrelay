import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/button_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/image_placement.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_text_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_parts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_stage.dart is the canvas you can touch: the document drawn, with
// selection handles over it and every gesture that moves something.
//
// It draws through the same scene_renderer.dart the export uses, under one
// transform -- so what is on screen is the document at the chosen zoom, and
// nothing here has an opinion about how any element looks. What it owns is
// entirely the other half: which element is under the pointer, what dragging a
// handle means, and where the handles go.
//
// Three pieces of that live next door, because each is read on its own and
// none of them needs the widget: stage_painter.dart draws everything, given
// values this file has already decided; stage_parts.dart answers the drags
// that move a piece *inside* an element -- a chart's title, a table's column
// rules; stage_geometry.dart is the sizes both halves have to agree on.
//
// The one idea worth stating plainly is the two coordinate spaces. *Document
// space* is where elements live and never changes with the view. *Stage space*
// is pixels on screen. Everything the pointer says arrives in stage space and
// is converted immediately, once, at the top of each gesture handler; nothing
// below that line has to think about zoom. Handles are the exception and are
// deliberately drawn and hit-tested in stage space, because a handle must stay
// the same size on screen at every zoom or it becomes unusable at both ends.

/// _DragMode is what the pointer is currently doing.
enum _DragMode {
  none,
  move,
  resize,
  rotate,
  marquee,
  pan,
  player,
  node,
  handle,

  /// chartLabel is a chart's title or description being moved or resized
  /// inside the chart. Its own mode because it moves a *part* of an element
  /// rather than the element, the same way player does.
  chartLabel,

  /// tableColumn is the rule between two of a table's columns being dragged
  /// to make one wider and the other narrower.
  tableColumn,

  /// imageFrame is a picture being moved about inside its own frame, which
  /// moves neither the element nor the picture's pixels -- only which part of
  /// them the frame is showing. See ImageFraming.
  imageFrame,
}

class CanvasStage extends StatefulWidget {
  final CanvasController controller;

  /// onButtonLink is called when a button element whose action is a link is
  /// pressed in the editor. Handed up rather than opened here, because leaving
  /// the app is not a decision a canvas widget should make on its own.
  final void Function(String url)? onButtonLink;

  const CanvasStage({required this.controller, this.onButtonLink, super.key});

  @override
  State<CanvasStage> createState() => CanvasStageState();
}

/// CanvasStageState is public for one reason: dropping an element onto the
/// canvas from the sidebar needs to know where, in document coordinates, the
/// pointer let go. Only the stage knows the transform, so the screen holds a
/// key to it and asks. Everything else here is private.
class CanvasStageState extends State<CanvasStage> {
  CanvasController get controller => widget.controller;
  CanvasDocument get document => controller.document;

  _DragMode _mode = _DragMode.none;

  /// _playerIndex is which player of the selected team is being dragged, in
  /// [_DragMode.player].
  ///
  /// A team is one element holding eleven dots, so dragging a single player is
  /// not selecting anything -- the team stays selected throughout, and what
  /// moves is one row of its list. That is deliberately not a second selection
  /// model: a player is not an element, has no handles and cannot be
  /// keyframed on its own.
  int _playerIndex = -1;

  /// _playerGrab is where in the dot the pointer took hold, so a player does
  /// not jump to centre itself under the cursor on the first pixel of a drag.
  Offset _playerGrab = Offset.zero;

  /// _pendingButton is a selected button that has been pressed but not yet
  /// released. It runs its action on release, and only if the pointer has not
  /// travelled far enough to have been a drag. See _onPointerDown.
  ButtonElement? _pendingButton;

  /// _buttonClickSlop is how far the pointer may move and still count as a
  /// click rather than a drag. Most trackpad clicks move a pixel or two.
  static const double _buttonClickSlop = 4;

  /// _lastClickAt and _doubleClickWindow spot the second click of a pair.
  ///
  /// Timed by hand rather than through a GestureDetector's onDoubleTap,
  /// because this stage handles raw pointers -- a gesture recogniser here
  /// would have to arbitrate with the drag, and a double tap recogniser delays
  /// every single tap by its own timeout while it waits to see if a second one
  /// is coming. Selecting something must not wait.
  DateTime _lastClickAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _doubleClickWindow = Duration(milliseconds: 400);

  /// _framing is the picture being repositioned inside its frame, if one is.
  ///
  /// A mode rather than a tool, entered by double-clicking a picture that is
  /// already selected -- the same second click that opens a text element for
  /// typing and a table's cell for editing. Dragging inside a picture has to
  /// go on moving the picture *element*, which is what it does nine times out
  /// of ten; asking for the other thing is a second click.
  String? _framing;

  /// _framingStart is the framing the drag started from, so that a drag is
  /// applied to where the picture was when it was taken hold of rather than
  /// accumulating rounding as it goes.
  ImageFraming _framingStart = const ImageFraming();

  /// _pressedAt is where the pointer went down, in stage coordinates.
  Offset _pressedAt = Offset.zero;

  /// _painting is the picture being retouched, while a brush stroke is under
  /// way. Held by id, since the element is replaced when the stroke lands.
  String? _painting;

  /// _liveImage and _liveCanvas are the stroke being drawn: the same points in
  /// the picture's coordinates, for storing, and in the canvas's, for showing.
  ///
  /// The stroke is not written to the element until the pointer comes up.
  /// Writing each point as it arrived changed the removal on every one, which
  /// changes the cache key, which sets the store rebuilding the whole treated
  /// picture -- a full pass over every pixel, dozens of times a second, while
  /// somebody is trying to draw a line. The line now appears immediately and
  /// the work happens once, when the stroke is finished.
  final List<Offset> _liveImage = [];
  final List<Offset> _liveCanvas = [];

  /// _liveRadius is the brush's radius in canvas units, worked out once when
  /// the stroke starts so the preview does not have to ask again per point.
  double _liveRadius = 0;

  /// _preview is a picture of what the held stroke would do, and _previewOf is
  /// the settings it was made for.
  ///
  /// Rebuilt whenever the stroke or the brush's settings change, which is the
  /// point of holding a stroke at all: the reader adjusts hardness or cling
  /// and watches the same stroke redraw itself.
  ui.Image? _preview;
  String? _previewOf;

  /// _previewDebounce waits for the settings to stop moving before running the
  /// brush again.
  ///
  /// Running it per change is what made typing and dragging a setting feel
  /// like wading: every keystroke and every pixel of a scrub is a new value,
  /// and each one started a full pass over the picture and an image decode.
  /// A number is entered *then* applied -- which is also how anybody expects a
  /// text field to behave.
  Timer? _previewDebounce;

  /// _previewDelay is long enough to cover the gap between keystrokes and
  /// short enough that the result feels like a consequence of the change
  /// rather than a separate event.
  static const Duration _previewDelay = Duration(milliseconds: 220);

  /// _editorRect is where the editor was opened, in document space.
  ///
  /// Frozen at the moment it opens rather than followed live. For text riding
  /// a line the box comes from where the letters are, and the letters move on
  /// every keystroke -- so a live box jumped about under the caret while it
  /// was being typed into.
  Rect? _editorRect;

  /// _editingCell is the table cell being typed into, or null.
  ///
  /// A record rather than an id: a cell has no identity of its own, and the
  /// table it belongs to is whatever is selected -- the same reasoning as the
  /// focused player of a team.
  (String, int, int)? _editingCell;

  /// _editingText is the text element being typed into, or null.
  ///
  /// Held by id rather than by element, because the element is replaced on
  /// every keystroke and a held copy would be one character behind.
  String? _editingText;

  /// _nodeIndex is which point of the selected path is being dragged, and
  /// _nodeHandleOut says which of its two handles when the drag is a handle.
  ///
  /// Like a player, a path node is not an element: the path stays selected
  /// throughout, and what moves is one entry in its list.
  int _nodeIndex = -1;
  bool _nodeHandleOut = false;

  StageHandle? _handle;

  /// _dragStart is where the gesture began, in document space, and
  /// _startBounds are the selected elements as they were then.
  ///
  /// The originals are kept rather than applying each delta to the current
  /// state, because accumulating deltas accumulates rounding -- an element
  /// dragged in a circle back to where it started would end up a pixel or two
  /// off, every time.
  Offset _dragStart = Offset.zero;
  Map<String, Rect> _startBounds = {};

  /// _startPosed is where each element was on screen when the gesture began.
  /// See _beginTransform.
  Map<String, Rect> _startPosed = {};

  /// _startVisual is the box the handles were on. See _beginTransform.
  Map<String, Rect> _startVisual = {};
  Map<String, double> _startRotation = {};
  Offset _startPan = Offset.zero;
  Rect? _marquee;

  /// _visible is the room on screen: what the stage was laid out into.
  Size _visible = Size.zero;

  /// _viewport is the box the canvas is drawn into, which is [_visible] except
  /// in [CanvasFit.width], where the canvas can be taller than the window and
  /// the difference is scrolled.
  ///
  /// Everything else in this file works in this box's coordinates, and so do
  /// the pointer events -- the Listener is inside the scroll view, so what it
  /// reports is already scrolled. The one exception is [toDocumentPoint],
  /// which is called from outside with widget coordinates; see there.
  Size _viewport = Size.zero;

  /// _scroll drives the vertical scroll in [CanvasFit.width].
  final ScrollController _scroll = ScrollController();

  /// _stageMargin is the gap kept around the canvas when it is showing whole,
  /// so the page reads as a sheet with room around it rather than as a region
  /// butted against the sidebar.
  static const double _stageMargin = 24;

  /// _overspillFraction is how much of the world outside the canvas is shown
  /// when CanvasController.showOverspill is on, as a fraction of the page.
  ///
  /// Twelve per cent each way. Enough to hold something that is about to come
  /// on or has just gone off -- which is all it is for -- and little enough
  /// that the page still dominates: turning it on shrinks the design by about
  /// a fifth, and any more than this and the thing being worked on is a small
  /// rectangle in the middle of a large grey one.
  static const double _overspillFraction = 0.12;

  final FocusNode _focus = FocusNode(debugLabel: "canvas stage");

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChanged);
    controller.images.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(CanvasStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_onChanged);
      oldWidget.controller.images.removeListener(_onChanged);
      controller.addListener(_onChanged);
      controller.images.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _scroll.dispose();
    controller.removeListener(_onChanged);
    controller.images.removeListener(_onChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    // Reframing follows the selection. Selecting something else -- from the
    // layers list, from a keyboard shortcut, by undoing back past the picture
    // -- has to leave the mode, or the ghost of a picture nobody is looking at
    // any more stays on the canvas over whatever is selected now.
    if (_framing != null &&
        (controller.selection.length != 1 ||
            controller.selection.first != _framing)) {
      _framing = null;
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------------
  // Coordinates
  // ------------------------------------------------------------------------

  /// _fitScale is the scale at which the whole canvas fills the area, with
  /// [_stageMargin] to spare.
  ///
  /// Recomputed from the viewport on every build rather than stored on the
  /// controller. It is a fact about how much room there is, which changes when
  /// the window is resized or the sidebar is collapsed, and the controller has
  /// no business knowing either.
  double get _fitScale {
    var size = document.size.size;
    if (size.width <= 0 || size.height <= 0) return 1;
    var byWidth = (_visible.width - _stageMargin * 2) / size.width;
    // Fit to width ignores the height entirely, which is the whole point: a
    // 9:16 story fitted whole is a narrow strip down the middle of a wide
    // window with most of the screen empty either side of it.
    var fit = controller.fit == CanvasFit.width
        ? byWidth
        : math.min(byWidth, (_visible.height - _stageMargin * 2) / size.height);
    // The overspill has to fit on screen too, so the page gives up the room
    // for it rather than the margin being eaten into.
    if (controller.showOverspill) fit /= 1 + _overspillFraction * 2;
    return fit.isFinite && fit > 0 ? fit : 1;
  }

  /// _viewRect is everything that is drawn: the page, plus the overspill
  /// around it when that is showing.
  ///
  /// This is what the stage clips to and what the pointer is tested against,
  /// so an element sitting off the page is visible and grabbable exactly when
  /// the reader has asked to see out there.
  Rect get _viewRect {
    var page = _pageRect;
    if (!controller.showOverspill) return page;
    return Rect.fromCenter(
      center: page.center,
      width: page.width * (1 + _overspillFraction * 2),
      height: page.height * (1 + _overspillFraction * 2),
    );
  }

  /// _contentSize is how much room the canvas and its margins need.
  ///
  /// The same as the visible box whenever the canvas fits in it. In fit-width
  /// it can be taller, and the excess is what scrolls.
  Size _contentSize(Size visible) {
    if (visible.width <= 0 || visible.height <= 0) return visible;
    var wanted = document.size.size.height *
            _fitScale *
            (controller.showOverspill ? 1 + _overspillFraction * 2 : 1) +
        _stageMargin * 2;
    return Size(visible.width, math.max(visible.height, wanted));
  }

  /// _pageRect is the canvas's frame on screen, and it does not move.
  ///
  /// This is the whole shape of the view. The frame is always the fitted size,
  /// centred, whatever the zoom -- so the edge of the canvas is always visible
  /// and zooming happens *inside* it, like moving a magnifier over a page
  /// rather than making the page bigger. Zooming used to enlarge the frame
  /// itself, which meant the borders went off screen and there was nothing
  /// left to tell you where the canvas ended.
  Rect get _pageRect {
    var size = document.size.size * _fitScale;
    return Rect.fromCenter(
      center: Offset(_viewport.width / 2, _viewport.height / 2),
      width: size.width,
      height: size.height,
    );
  }

  /// _scale is what one document unit measures on screen: the fitted size,
  /// times however far the reader has zoomed in from it. See
  /// CanvasController.zoom on why zoom is a multiple of the fit rather than of
  /// the document's own pixels.
  double get _scale => _fitScale * controller.zoom;

  /// _scaledSize is the document as drawn, which at any zoom above 1 is larger
  /// than the frame it is being drawn inside.
  Size get _scaledSize => document.size.size * _scale;

  /// _origin is where the document's top-left corner sits in stage space.
  Offset get _origin {
    var size = _scaledSize;
    var pan = _clampedPan;
    var page = _pageRect;
    return Offset(
      page.center.dx - size.width / 2 + pan.dx,
      page.center.dy - size.height / 2 + pan.dy,
    );
  }

  /// _clampPan keeps the frame full.
  ///
  /// The pan is bounded by exactly how much the zoomed document overhangs the
  /// frame, so the far edge can be brought to the edge of the frame and no
  /// further. At zoom 1 the overhang is nothing and the pan is pinned to zero,
  /// which is what makes the whole canvas sit exactly in its border with no
  /// way to knock it out of alignment.
  ///
  /// Without this it was possible to drag a zoomed canvas entirely out of the
  /// frame and be left looking at an empty rectangle.
  Offset _clampPan(Offset pan) {
    var size = _scaledSize;
    var page = _pageRect;
    var slackX = math.max(0.0, (size.width - page.width) / 2);
    var slackY = math.max(0.0, (size.height - page.height) / 2);
    return Offset(
      pan.dx.clamp(-slackX, slackX),
      pan.dy.clamp(-slackY, slackY),
    );
  }

  Offset get _clampedPan =>
      _clampPan(Offset(controller.pan.dx, controller.pan.dy));

  void _setPan(Offset pan) {
    var clamped = _clampPan(pan);
    controller.pan = Offset2(clamped.dx, clamped.dy);
  }

  Offset _toDocument(Offset stage) =>
      (stage - _origin) / (_scale == 0 ? 1 : _scale);

  Offset _toStage(Offset doc) => doc * _scale + _origin;

  /// toDocumentPoint converts a position in this widget's own coordinates to a
  /// point in the document, for a drop from the sidebar.
  ///
  /// The scroll offset is added on, because the caller measures against the
  /// whole widget while everything in here works in the scrolled content's
  /// coordinates. Without it, an element dropped on a scrolled fit-width canvas
  /// lands as far up the page as the view had been scrolled down.
  Offset toDocumentPoint(Offset local) =>
      _toDocument(local + Offset(0, _scroll.hasClients ? _scroll.offset : 0));

  /// pageRect is the canvas's frame, in this widget's coordinates.
  ///
  /// Exposed for tests, which is the only way to ask the questions that matter
  /// about the view: is the whole frame on screen, does it stay put when the
  /// zoom changes, and can a zoomed canvas be dragged out of it. All of them
  /// are invisible to a widget test otherwise -- the canvas is painted, not
  /// laid out, so there is no render box to measure.
  @visibleForTesting
  Rect get pageRect => _pageRect;

  /// contentRect is the document as drawn inside that frame.
  @visibleForTesting
  Rect get contentRect => _origin & _scaledSize;

  /// viewportSize is the room the stage has, for the same tests.
  @visibleForTesting
  Size get viewportSize => _viewport;

  /// _selectionBounds is the axis-aligned box around everything selected, in
  /// document space.
  ///
  /// Rotation is deliberately ignored for a multiple selection: handles that
  /// tried to follow several different rotations at once would have no
  /// meaningful orientation, and the box is only being used to say "this much
  /// is chosen".
  Rect? get _selectionBounds {
    var elements = controller.selectedElements;
    if (elements.isEmpty) return null;
    // Where they are on this frame, not where they rest -- see
    // CanvasElement.boundsAt. Using the resting bounds left the blue rectangle
    // standing still while the element inside it animated away, which reads as
    // the *contents* being animated rather than the element.
    var box = _visualBounds(elements.first);
    for (var e in elements.skip(1)) {
      box = box.expandToInclude(_visualBounds(e));
    }
    return box;
  }

  /// _boxIsNotTheShape marks the elements whose selection box is bigger than
  /// what the pointer can actually land on -- see _onPointerDown.
  bool _boxIsNotTheShape(CanvasElement e) =>
      e is LineElement ||
      e is PathElement ||
      (e is TextElement && e.curve != null);

  /// _visualBounds is where an element is actually drawn -- see
  /// visualBoundsOf. A bowed line, a path and text riding a line are all drawn
  /// somewhere other than their own rectangle, and a selection box on the
  /// rectangle is a box around empty canvas.
  Rect _visualBounds(CanvasElement e) =>
      visualBoundsOf(e, document, controller.frame);

  /// _selectionHasOwnGeometry is whether the handles and the rotate ring are
  /// worth showing. See hasOwnGeometry.
  bool get _selectionHasOwnGeometry {
    var elements = controller.selectedElements;
    if (elements.isEmpty) return false;
    return elements.every((e) => hasOwnGeometry(e, document, controller.frame));
  }

  /// _rotationOfSelection is the single selected element's rotation, or zero
  /// when several are chosen.
  double get _rotationOfSelection => controller.selectedElements.length == 1
      ? controller.selectedElements.first.rotationAt(controller.frame) *
          math.pi /
          180
      : 0;

  // ------------------------------------------------------------------------
  // Hit testing
  // ------------------------------------------------------------------------

  /// _hitElement is the topmost element under a document-space point.
  ///
  /// Walked from the front backwards, because the last element in paint order
  /// is the one on top and is the one a click should find.
  CanvasElement? _hitElement(Offset point) {
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var e = document.elements[i];
      if (!e.visible || e.locked) continue;
      if (_containsPoint(e, point)) return e;
    }
    return null;
  }

  /// _containsPoint asks whether a point is inside an element, undoing the
  /// element's rotation first so a rotated element is hit where it looks
  /// rather than where its unrotated box was.
  /// _strokeReach is how far from a line the pointer may be and still be on
  /// it, in document units. Half the stroke plus a few pixels of slack, so a
  /// hairline is still catchable without a steady hand.
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

  bool _containsPoint(CanvasElement e, Offset point) {
    // A curve is caught by its stroke, not by its box.
    //
    // A bowed line or a path with its handles pulled out bulges *outside* its
    // own bounding box, so the visible stroke was not clickable at all while
    // an empty corner of the box was. Text riding a line is the same problem
    // twice over: its box is wherever it was dropped, and the words are
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
        // Generous, because what is being aimed at is a row of letters sitting
        // on the line rather than the line itself.
        return _nearPolyline(
            curve, point, _strokeReach(e.textSpec.fontSize * 1.2));
      }
    }

    // Against where it is on this frame, for the same reason the selection box
    // is: an animated element clicked at frame 20 has to be hit where it is
    // drawn, not where it started.
    var box = e.boundsAt(controller.frame);
    var rotation = e.rotationAt(controller.frame);
    var local = point;
    if (rotation != 0) {
      var c = box.center;
      var d = point - c;
      var a = -rotation * math.pi / 180;
      local = c +
          Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
              d.dx * math.sin(a) + d.dy * math.cos(a));
    }
    if (!box.contains(local)) return false;

    // A line is a stroke, not a rectangle: a diagonal line's bounding box is
    // mostly empty, and clicking that empty space to select the line behind it
    // is the reported "I can't click the thing under my arrow".
    if (e is ShapeElement && e.shape == ShapeKind.circle) {
      var r = box.shortestSide / 2;
      return (local - box.center).distance <= r;
    }
    return true;
  }

  /// _hitHandle is which grip is under a stage-space point, if any.
  StageHandle? _hitHandle(Offset stage) {
    // Nothing to grab on something whose size and angle are a line's.
    if (!_selectionHasOwnGeometry) return null;
    var bounds = _selectionBounds;
    if (bounds == null) return null;
    var reach = handleSize / 2 + handleHitSlop;

    // Hidden helpers are unreachable helpers -- see
    // CanvasController.showHelpers.
    if (!controller.showHelpers) return null;

    for (var handle in StageHandle.values) {
      var at = _handlePosition(handle, bounds);
      // Clipped out of sight means clipped out of reach. A handle that can be
      // grabbed where nothing is drawn is a click that appears to do nothing
      // and then moves something.
      if (!_viewRect.inflate(reach).contains(at)) continue;
      if ((stage - at).distance <= reach) return handle;
    }
    return null;
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

    var a = _rotationOfSelection;
    if (a == 0) return centre + local;
    return centre +
        Offset(local.dx * math.cos(a) - local.dy * math.sin(a),
            local.dx * math.sin(a) + local.dy * math.cos(a));
  }

  // ------------------------------------------------------------------------
  // Gestures
  // ------------------------------------------------------------------------

  bool get _shiftHeld => HardwareKeyboard.instance.isShiftPressed;

  void _onPointerDown(PointerDownEvent event) {
    // Not while typing: an editor is a real text field sitting over the
    // canvas, and it deals with its own pointers. Clicking off it moves the
    // focus, which is what closes it -- see CanvasTextEditor._onFocus.
    //
    // A cell editor counts. Without it here, pressing anything inside one --
    // its own picture button included -- ran the stage's hit test and asked
    // for the canvas's focus, which took the focus off the field, which closed
    // the editor, which took the button with it before its tap had finished.
    if (_editingText != null || _editingCell != null) return;
    _focus.requestFocus();
    var stage = event.localPosition;
    _pressedAt = stage;
    var doc = _toDocument(stage);
    _dragStart = doc;

    // The pan tool and the middle button pan. Space used to as well, and no
    // longer does: it plays and stops now, which is worth more on a page for
    // building animations, and the pan tool is the discoverable version of
    // what space-drag was for.
    if (controller.tool == CanvasTool.pan ||
        event.buttons == kMiddleMouseButton) {
      _mode = _DragMode.pan;
      _startPan = _clampedPan;
      _dragStart = stage;
      return;
    }

    // While a picture is being reframed, a press inside it drags the picture
    // rather than the element. A press anywhere else is how the reframing is
    // finished -- the same way clicking off a text editor closes it.
    if (_framing != null) {
      var framed = document.elementById(_framing!);
      if (framed is ImageElement && _containsPoint(framed, doc)) {
        _framingStart = framed.framing;
        _mode = _DragMode.imageFrame;
        controller.beginInteraction();
        return;
      }
      setState(() => _framing = null);
    }

    // A selected path's points and handles are grabbed before anything
    // else, exactly as a team's players are: they are drawn on top of the
    // curve and are the thing being aimed at.
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

    // Inside the box of something already selected whose box is not its shape
    // -- a curved line, a path, text on a line -- takes hold of it.
    //
    // Two rules rather than one, deliberately. *Selecting* one of these still
    // needs the stroke, or a bowed line's large empty box would steal every
    // click meant for whatever is underneath it. Once it is selected the box
    // is yours, which is what makes it draggable from anywhere inside rather
    // than only from the few pixels of the line itself.
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

    // Outside the frame there is nothing to hit. Clicking the margin clears
    // the selection, which is the only thing it could sensibly mean.
    if (!_viewRect.contains(stage) && _hitHandle(stage) == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.none;
      return;
    }

    var handle = _hitHandle(stage);
    if (handle != null) {
      _beginTransform(
          handle == StageHandle.rotate ? _DragMode.rotate : _DragMode.resize,
          handle);
      return;
    }

    // The retouching brush, before anything else -- while it is on, a drag is
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

    // A player, before anything else on the canvas -- and a player of *any*
    // team, not just the selected one.
    //
    // It used to be the selected team's only, and that failed in the two ways
    // a pitch is actually used. A player dragged outside his own team's box is
    // not inside those bounds any more, so the ordinary element hit test never
    // returned his team and there was nothing to look inside. And with two
    // sides on one pitch the boxes overlap, so clicking a home player standing
    // in the away half found the away team's box first and picked that up
    // instead. A dot is the smallest and topmost thing on the canvas; it
    // should win against every box, including its own.
    var hit = _hitAnyPlayer(doc);
    if (hit != null) {
      var (team, index) = hit;
      if (controller.selection.length != 1 ||
          controller.selection.first != team.id) {
        controller.selectOnly(team.id);
      }
      _mode = _DragMode.player;
      _playerIndex = index;
      _playerGrab = doc - team.centreAt(team.players[index], controller.frame);
      // Clicking a player is also how the timeline is pointed at them: a
      // player has no id and cannot be selected, so this is the only thing
      // that says whose keyframes the controls are about.
      controller.focusedPlayer = index;
      controller.beginInteraction();
      return;
    }

    // A placed label of the selected chart, before the chart itself. It sits
    // inside the chart's own box, so the ordinary hit test would pick the
    // chart up and move the whole thing -- which is what happened before
    // there was anywhere else for the press to go.
    var chart = controller.selected;
    if (chart is ChartElement && !chart.locked) {
      var grab = chartLabelGrabAt(
          chart, chart.boundsAt(controller.frame), doc, _docSlop);
      if (grab != null) {
        _labelGrab = grab;
        _mode = _DragMode.chartLabel;
        controller.beginInteraction();
        return;
      }
    }

    // A column rule of the selected table, before the table itself -- the
    // rule is inside the table's own box, so the ordinary hit test would pick
    // the table up and move the whole thing.
    var table = controller.selected;
    if (table is TableElement && !table.locked) {
      var divider =
          tableColumnAt(table, table.boundsAt(controller.frame), doc, _docSlop);
      if (divider != null) {
        _columnGrab = divider;
        _mode = _DragMode.tableColumn;
        controller.beginInteraction();
        return;
      }
    }

    var element = _hitElement(doc);
    if (element == null) {
      if (!_shiftHeld) controller.clearSelection();
      _mode = _DragMode.marquee;
      setState(() => _marquee = Rect.fromPoints(doc, doc));
      return;
    }

    // A selected button is *tried* by clicking it and *moved* by dragging it.
    //
    // It used to run its action on pointer-down, which meant a button could
    // never be moved again once it was selected: the press that would have
    // started the drag fired the action instead, and the button stayed where
    // it was. So the decision is deferred to pointer-up, where the distance
    // travelled is known -- see _onPointerUp.
    if (element is ButtonElement &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id) {
      _pendingButton = element;
      _beginTransform(_DragMode.move, null);
      return;
    }

    // A second click on a picture that is already selected reframes it:
    // dragging then moves the picture inside its box instead of moving the
    // box. Only for a picture that fills its box -- see ImageFraming -- and
    // one that does not is switched to, because "fit inside" shows the whole
    // picture and there would be nothing to move.
    if (element is ImageElement &&
        element.hasImage &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        DateTime.now().difference(_lastClickAt) < _doubleClickWindow) {
      if (element.fit != ImageFit.cover) {
        controller.replaceElement(element.copyWith(fit: ImageFit.cover));
      }
      setState(() => _framing = element.id);
      _mode = _DragMode.none;
      return;
    }

    // A second click on a cell of a table that is already selected opens that
    // cell for typing, which is the same gesture the text element has and the
    // same one that renames a file.
    if (element is TableElement &&
        !_shiftHeld &&
        !element.locked &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        DateTime.now().difference(_lastClickAt) < _doubleClickWindow) {
      var at = tableCellAt(element, element.boundsAt(controller.frame), doc);
      if (at != null) {
        setState(() => _editingCell = (element.id, at.$1, at.$2));
        _mode = _DragMode.none;
        return;
      }
    }

    // A second click on a text element that is already selected opens it for
    // typing -- the same gesture that renames a file everywhere else. The
    // first click selects, so a text element is still moved by dragging it.
    if (element is TextElement &&
        !_shiftHeld &&
        controller.selection.length == 1 &&
        controller.selection.first == element.id &&
        _pressedAt != Offset.zero &&
        DateTime.now().difference(_lastClickAt) < _doubleClickWindow) {
      setState(() => _editingText = element.id);
      _mode = _DragMode.none;
      return;
    }
    _lastClickAt = DateTime.now();

    if (_shiftHeld) {
      controller.toggleSelected(element.id);
    } else if (!controller.selection.contains(element.id)) {
      controller.selectOnly(element.id);
    }

    // A team with its frame locked is still selectable -- its settings and its
    // squad list are wanted -- but the box itself does not move. Any drag that
    // was going to take hold of a player has already been dealt with above, so
    // reaching here means the pointer was on the pitch rather than on a dot.
    if (element is TeamElement && element.frameLocked) {
      _mode = _DragMode.none;
      return;
    }

    _beginTransform(_DragMode.move, null);
  }

  /// _selectedPath is the one selected element, when it is a path.
  PathElement? _selectedPath() {
    var selected = controller.selected;
    return selected is PathElement ? selected : null;
  }

  /// _hitPathControl finds the point or handle under [doc], as
  /// (index, isHandle, isOutHandle).
  ///
  /// Handles are tested before points so that a handle sitting on top of its
  /// own point -- which is where an unbent node's handles are -- can still be
  /// pulled out to make a curve.
  (int, bool, bool)? _hitPathControl(PathElement path, Offset doc) {
    // In document units, so the grab area is the same size on screen however
    // far the canvas is zoomed -- what is being allowed for is a pointer, not
    // a distance on the page.
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

    // Alt breaks the handle pair, which is how a corner is made. Held down is
    // the exception rather than the rule, because most of a run is smooth and
    // a curve that kinked every time a handle moved would be unusable.
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

  /// _paintStrokeAt adds a point to the stroke being painted.
  ///
  /// The point is stored in the *picture's* coordinates rather than the
  /// canvas's, so a stroke stays on the shoulder it was painted on when the
  /// element is resized, refitted or recropped afterwards. Converting is
  /// ImagePlacement's job, and it is the same mapping the painter draws
  /// through -- worked out separately the brush would touch pixels other than
  /// the ones under the pointer, and it would look like a wobbly brush rather
  /// than like two functions disagreeing.
  /// _paintStrokeAt adds a point to the stroke being drawn.
  ///
  /// Only to the live copy. Committing is [_commitStroke], on pointer up.
  void _paintStrokeAt(Offset doc, {bool start = false}) {
    var id = _painting;
    if (id == null) return;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return;

    var image = controller.images.original(picture.assetId);
    if (image == null) return;

    var inner = picture.boundsAt(controller.frame).deflate(picture.box.padding);
    var size = Size(image.width.toDouble(), image.height.toDouble());
    var placement = placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
    var at = placement.toImage(doc, size);
    // Off the picture: the part of a stroke that runs past the edge has
    // nothing to touch, which is not a reason to end the stroke.
    if (at == null) return;

    if (start) {
      // The brush is a fraction of the picture's shorter side, and the preview
      // has to be drawn in canvas units -- so it is converted once here rather
      // than per point.
      var shorter = math.min(size.width, size.height);
      var scale = placement.scaleToImage();
      _liveRadius = controller.brushSize * shorter / (scale == 0 ? 1 : scale);
    }

    setState(() {
      _liveImage.add(at);
      _liveCanvas.add(doc);
    });
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
    var inner = e.boundsAt(controller.frame).deflate(e.box.padding);
    if (inner.width <= 0 || inner.height <= 0) return null;
    return placeImage(
        Size(image.width.toDouble(), image.height.toDouble()), inner, e.fit,
        crop: e.crop, framing: e.framing);
  }

  /// _framingView is what the painter draws over a picture being reframed:
  /// the whole of it, in the place the visible part is already in.
  StageFraming? _framingView() {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null || placement.src.width <= 0) return null;

      // Doc units per picture pixel, which is the same in both directions --
      // a cover never distorts -- so one number scales the whole ghost.
      var perPixel = placement.dst.width / placement.src.width;
      var whole = placement.whole;
      var dst = Rect.fromLTWH(
        placement.dst.left - (placement.src.left - whole.left) * perPixel,
        placement.dst.top - (placement.src.top - whole.top) * perPixel,
        whole.width * perPixel,
        whole.height * perPixel,
      );
      return StageFraming(
          image,
          whole,
          dst,
          e.boundsAt(controller.frame).deflate(e.box.padding),
          e.rotationAt(controller.frame) * math.pi / 180);
    }
    return null;
  }

  /// _applyFraming moves the picture inside its frame by however far the
  /// pointer has come since it went down.
  ///
  /// The pointer's travel is in canvas units and the framing is in fractions
  /// of the slack, so it is converted through the placement rather than
  /// through a guess: a picture with very little spare moves a long way for a
  /// short drag, and one with a lot of spare barely moves, which is what makes
  /// the picture appear to follow the pointer at any zoom.
  ///
  /// The sign is the way round it looks. Dragging right moves the *picture*
  /// right, which means the window is choosing pixels further to its left.
  void _applyFraming(Offset doc) {
    if (_framedPicture() case (var e, var image)) {
      var placement = _framingPlacement(e, image);
      if (placement == null) return;
      var perPixel = placement.dst.width / placement.src.width;
      if (perPixel <= 0) return;
      var slack = placement.slack;

      // Undone by the element's own rotation, so a tilted picture moves the
      // way the pointer does rather than along its own diagonal.
      var travel = doc - _dragStart;
      var a = -e.rotationAt(controller.frame) * math.pi / 180;
      if (a != 0) {
        travel = Offset(travel.dx * math.cos(a) - travel.dy * math.sin(a),
            travel.dx * math.sin(a) + travel.dy * math.cos(a));
      }

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
  /// exactly over the picture it belongs to, through the same placement the
  /// picture itself is drawn with.
  ImagePlacement? _previewPlacement() {
    var id = controller.pendingPicture;
    if (id == null || _preview == null) return null;
    var picture = document.elementById(id);
    if (picture is! ImageElement) return null;
    var inner = picture.boundsAt(controller.frame).deflate(picture.box.padding);
    var size = Size(_preview!.width.toDouble(), _preview!.height.toDouble());
    return placeImage(size, inner, picture.fit,
        crop: picture.crop, framing: picture.framing);
  }

  /// _refreshPreview rebuilds the picture of what the held stroke would do,
  /// when the stroke or the settings behind it have changed.
  ///
  /// Keyed on the settings rather than rebuilt on every notification: the
  /// controller notifies for everything from the playhead moving to a
  /// selection changing, and running the brush over a photograph for each of
  /// those would be worse than the problem this replaced.
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

    // After the settings have stopped moving. The stroke itself is not worth
    // waiting for -- it is drawn already and the reader is looking at it -- but
    // there is no telling a keystroke from the last keystroke except by
    // waiting, so both go through the same delay.
    _previewDebounce?.cancel();
    _previewDebounce = Timer(_previewDelay, () {
      if (!mounted || _previewOf != key) return;
      // No colour to pass any more: the preview colours itself by how hard
      // the brush is at each pixel, which is the thing being judged.
      strokePreview(source, stroke).then((image) {
        if (!mounted || _previewOf != key) return;
        setState(() => _preview = image);
      });
    });
  }

  /// _commitStroke writes the finished stroke onto the picture.
  ///
  /// One change to the document for the whole gesture, so the store does its
  /// pass over the pixels once and undo has one step to take back.
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

    // A marking brush teaches the learning method what is what; the other two
    // rub the picture out and put it back. Which of the two this is has to be
    // remembered with the stroke, since the reader may pick up a different
    // brush before applying it.
    var teaching = controller.retouch.teaches;

    // Held rather than applied. The reader can now adjust the brush and watch
    // this same stroke redraw before deciding -- see
    // CanvasController.holdStroke.
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

  /// _hitAnyPlayer is the topmost player of any team under [doc].
  ///
  /// Walks the elements in reverse paint order so the team drawn last wins,
  /// which is the same rule every other hit test on this canvas follows. It
  /// deliberately ignores the teams' boxes: a player is placed as a fraction
  /// of one but is not confined to it, and two teams on one pitch have
  /// overlapping boxes anyway.
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

  /// _hitPlayer is which of [team]'s players is under [doc], or null.
  ///
  /// Searched back to front, so the player drawn on top is the one picked up
  /// -- which is the same rule the element hit test uses, and the reason Bring
  /// forward is worth having on a crowded midfield.
  ///
  /// A locked player is not hittable. That is what locking is for: pinning the
  /// back four so a run can be dragged through them without knocking one out
  /// of position.
  int? _hitPlayer(TeamElement team, Offset doc) {
    var rx = team.dotWidth / 2;
    var ry = team.dotHeight / 2;
    if (rx <= 0 || ry <= 0) return null;

    for (var i = team.players.length - 1; i >= 0; i--) {
      var spot = team.players[i];
      if (spot.locked || spot.hidden) continue;
      // Where they are on this frame, not where they rest: on frame 20 of a
      // run, the dot the pointer is over is the one that has moved.
      var d = doc - team.centreAt(spot, controller.frame);
      // Against the ellipse rather than a square, so the gaps between dots in
      // a tight back four stay gaps.
      if ((d.dx * d.dx) / (rx * rx) + (d.dy * d.dy) / (ry * ry) <= 1) return i;
    }
    return null;
  }

  /// _applyPlayerMove drags one player of the selected team.
  ///
  /// The position is written back as the fraction of the team's box that it is
  /// stored as, which is what keeps a player where they were put when the team
  /// is later moved or resized.
  void _applyPlayerMove(Offset doc) {
    var team = _selectedTeam();
    if (team == null ||
        _playerIndex < 0 ||
        _playerIndex >= team.players.length) {
      return;
    }
    var spot = team.players[_playerIndex];
    var at = doc - _playerGrab;

    // A player animates like anything else: while the document is animated
    // and either auto-keyframe is on or this player already moves, the drag
    // writes a keyframe rather than changing where they line up. That is what
    // makes a tactics diagram possible at all -- the winger's run is one
    // player's keyframes, not the team's.
    var animating = controller.document.isAnimated &&
        (controller.autoKeyframe || (spot.track?.isEmpty == false));

    if (animating) {
      var rest = team.centreOf(spot);
      // Seeded at the start, so a drag at frame 12 reads as a run from where
      // he was rather than as having moved him for the whole document. See
      // ElementTrack.seededFor.
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
    // Where each element *is* on this frame, which is what a move works from.
    //
    // Kept apart from the resting bounds above, which is what a resize works
    // from: resizing writes the base width and height, and feeding it a posed
    // size would bake a scale keyframe into the element itself.
    //
    // Using the resting bounds for the move was the third-keyframe jump.
    // movedTo turns a target position into a pose offset by subtracting the
    // resting position, so a drag that started from the resting top-left
    // produced a pose of exactly the drag delta -- throwing away whatever
    // pose the frame already had. On the first two keyframes that pose was
    // usually zero and nothing was visibly wrong; on the third it was not, and
    // the element leapt out from under the pointer the instant it moved.
    _startPosed = {
      for (var e in controller.selectedElements)
        e.id: e.boundsAt(controller.frame),
    };
    // The box the handles are on, which for a line or a path is bigger than
    // the element's own -- see _visualBounds. A resize is expressed against
    // this and then applied to the real rectangle in the same proportion, so
    // dragging a corner does what it looks like it does.
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
    return chartLabelPlaces(element, element.boundsAt(controller.frame))
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
    var bounds = element.boundsAt(controller.frame);
    return [
      for (var x in tableColumnDividers(element, bounds))
        (x, bounds.top, bounds.bottom),
    ];
  }

  /// _labelGrab is the chart label being dragged, while one is.
  /// _docSlop is the pointer's reach in document units.
  ///
  /// The allowance is a number of screen pixels -- how still a hand is, not
  /// how big the document is -- so it has to be divided by the zoom before it
  /// can be compared with anything in document space. Zoomed in, a grip that
  /// kept its document size would swallow half the table.
  double get _docSlop => handleHitSlop / _scale;

  /// _applyPart writes a part-drag onto the selected element -- see
  /// stage_parts.dart, which works out what the new element is. Both kinds
  /// are transient: the drag is one undo step, closed when the pointer lifts.
  void _applyPart(Offset doc, {required bool chartLabel}) {
    var element = controller.selected;
    if (element == null) return;
    var bounds = element.boundsAt(controller.frame);
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

  /// _columnGrab is which of a table's dividers is being dragged: the index of
  /// the column to its left.
  int? _columnGrab;

  void _onPointerMove(PointerMoveEvent event) {
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

    var doc = _toDocument(event.localPosition);
    var delta = doc - _dragStart;

    switch (_mode) {
      case _DragMode.move:
        _applyMove(delta);
      case _DragMode.resize:
        _applyResize(delta);
      case _DragMode.rotate:
        _applyRotate(doc);
      case _DragMode.marquee:
        setState(() => _marquee = Rect.fromPoints(_dragStart, doc));
      case _DragMode.player:
        _applyPlayerMove(doc);
      case _DragMode.node:
        _applyNodeMove(doc, handle: false);
      case _DragMode.handle:
        _applyNodeMove(doc, handle: true);
      case _DragMode.chartLabel:
        _applyPart(doc, chartLabel: true);
      case _DragMode.tableColumn:
        _applyPart(doc, chartLabel: false);
      case _DragMode.imageFrame:
        _applyFraming(doc);
      default:
        break;
    }
  }

  void _applyMove(Offset delta) {
    // Shift constrains to one axis, which is how every editor behaves and is
    // the only way to move something along a line without a grid.
    if (_shiftHeld) {
      delta = delta.dx.abs() > delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
    }
    var next = document;
    for (var entry in _startPosed.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // Through the controller rather than straight onto the base, because an
      // element that is being animated is being posed rather than relocated --
      // see CanvasController.posesRatherThanMoves, which is the whole reason
      // dragging an animated element used to appear to do nothing.
      next = next.withElement(
          controller.movedTo(element, entry.value.topLeft + delta));
    }
    controller.apply(next, transient: true);
  }

  void _applyResize(Offset delta) {
    var handle = _handle;
    if (handle == null) return;

    // The drag is rotated into the element's own frame, so pulling the right
    // edge of a tilted element makes it wider rather than moving it sideways.
    var a = -_rotationOfSelection;
    if (a != 0) {
      delta = Offset(delta.dx * math.cos(a) - delta.dy * math.sin(a),
          delta.dx * math.sin(a) + delta.dy * math.cos(a));
    }

    var next = document;
    for (var entry in _startVisual.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      // Against the box the handles are actually on. For a line or a path that
      // is larger than the element's own rectangle, and dragging a corner of a
      // box while a different rectangle resized underneath is what made a
      // curved line feel like it was fighting the pointer.
      var start = entry.value;

      var left = start.left + (handle.movesLeft ? delta.dx : 0);
      var right = start.right + (handle.movesRight ? delta.dx : 0);
      var top = start.top + (handle.movesTop ? delta.dy : 0);
      var bottom = start.bottom + (handle.movesBottom ? delta.dy : 0);

      // Shift keeps the proportions, driven by whichever axis moved further so
      // that a corner drag feels like one gesture rather than two. A picture
      // asks for the same thing without the key being held, and then Shift is
      // how it is let go of -- see CanvasElement.keepsAspect.
      var keep = element.keepsAspect ? !_shiftHeld : _shiftHeld;
      if (keep && start.height > 0) {
        var aspect = start.width / start.height;
        if ((right - left).abs() > (bottom - top).abs() * aspect) {
          var height = (right - left).abs() / aspect;
          handle.movesTop ? top = bottom - height : bottom = top + height;
        } else {
          var width = (bottom - top).abs() * aspect;
          handle.movesLeft ? left = right - width : right = left + width;
        }
      }

      // Minimums rather than allowing an element to be dragged inside out.
      // A negative width is a rectangle that draws nothing and cannot be
      // grabbed again, which is a way to lose an element with no way back.
      const minimum = 8.0;
      if (right - left < minimum) {
        handle.movesLeft ? left = right - minimum : right = left + minimum;
      }
      if (bottom - top < minimum) {
        handle.movesTop ? top = bottom - minimum : bottom = top + minimum;
      }

      // The handle box has been resized; the element's own rectangle follows
      // it in the same proportion. For everything except a line, a path and
      // curved text the two boxes are identical and this is the identity.
      var real = _startBounds[entry.key] ?? start;
      var sx = start.width == 0 ? 1.0 : (right - left) / start.width;
      var sy = start.height == 0 ? 1.0 : (bottom - top) / start.height;
      next = next.withElement(element.withBase(
        x: left + (real.left - start.left) * sx,
        y: top + (real.top - start.top) * sy,
        width: math.max(1, real.width * sx),
        height: math.max(1, real.height * sy),
      ));
    }
    controller.apply(next, transient: true);
  }

  void _applyRotate(Offset doc) {
    var bounds = _selectionBounds;
    if (bounds == null) return;
    var centre = bounds.center;

    var from = math.atan2(_dragStart.dy - centre.dy, _dragStart.dx - centre.dx);
    var to = math.atan2(doc.dy - centre.dy, doc.dx - centre.dx);
    var degrees = (to - from) * 180 / math.pi;

    var next = document;
    for (var entry in _startRotation.entries) {
      var element = next.elementById(entry.key);
      if (element == null || element.locked) continue;
      var rotation = entry.value + degrees;
      // Shift snaps to fifteen degrees, which covers every angle anybody
      // actually wants and makes "put it back to straight" reachable.
      if (_shiftHeld) rotation = (rotation / 15).round() * 15;
      next = next.withElement(element.withBase(rotation: rotation));
    }
    controller.apply(next, transient: true);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_painting != null) {
      _commitStroke();
      return;
    }
    _playerIndex = -1;

    // A press on an already-selected button that never became a drag is a
    // click, and a click runs it. Measured in stage pixels rather than
    // document units so the tolerance is the same however far in the canvas
    // is zoomed -- what is being allowed for is an unsteady hand, not a
    // distance on the page.
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
      // Re-baked once, at the end of the drag rather than on every pixel of
      // it: a route is dozens of keyframes and rewriting them all sixty times
      // a second would make dragging a point crawl.
      var path = _selectedPath();
      if (path != null) controller.applyPathFollow(path);
      controller.endInteraction();
      _nodeIndex = -1;
    }
    // Every mode that opened one closes it here.
    //
    // The list used to be the three that move the whole element, and the part
    // drags below it opened an interaction that nothing closed. Because
    // beginInteraction only takes the document if there is not one held
    // already, that did not lose the undo step -- it merged it into whatever
    // gesture came next, so undoing after nudging a chart's title also undid
    // the move that followed it.
    if (_mode == _DragMode.move ||
        _mode == _DragMode.resize ||
        _mode == _DragMode.rotate ||
        _mode == _DragMode.chartLabel ||
        _mode == _DragMode.tableColumn ||
        _mode == _DragMode.imageFrame) {
      controller.endInteraction();
    }
    _mode = _DragMode.none;
    _handle = null;
  }

  /// _updateHover keeps the renderer told which button is under the pointer.
  void _updateHover(Offset stage) {
    var element = _hitElement(_toDocument(stage));
    var id = element is ButtonElement ? element.id : null;
    if (id != controller.hoveredButton) {
      controller.hoveredButton = id;
      setState(() {});
    }
  }

  void _onScroll(PointerScrollEvent event) {
    // While reframing, the wheel is the picture's zoom rather than the view's.
    // It is the other half of the gesture -- drag to choose what is in shot,
    // scroll to choose how much of it -- and the view's zoom is still there on
    // the toolbar and under the pan tool.
    if (_framing != null) {
      var framed = document.elementById(_framing!);
      if (framed is ImageElement) {
        controller.replaceElement(
            framed.copyWith(
                framing: framed.framing.copyWith(
                    zoom: framed.framing.zoom *
                        (event.scrollDelta.dy > 0 ? 0.94 : 1.06))),
            transient: true);
        return;
      }
    }

    // Zoom about the pointer rather than about the middle, so scrolling in on
    // a corner of the pitch keeps that corner where it is instead of sending
    // it off screen.
    var before = _toDocument(event.localPosition);
    controller.zoomBy(event.scrollDelta.dy > 0 ? 0.9 : 1.1);
    var after = _toDocument(event.localPosition);
    var shift = (after - before) * _scale;
    _setPan(Offset(controller.pan.dx + shift.dx, controller.pan.dy + shift.dy));
  }

  // ------------------------------------------------------------------------

  /// _onKey is the canvas's keyboard.
  ///
  /// The arrows scrub rather than nudge, and that is a deliberate swap. This
  /// is a page for building animations, where stepping a frame at a time is
  /// the thing done constantly and moving something by a pixel is the thing
  /// done occasionally -- so the unmodified key is the frequent one. Nudging
  /// moves to Alt, in all four directions rather than only the two the arrows
  /// gave up, because a nudge that worked one way with a modifier and another
  /// way without would be worse than either.
  ///
  /// Space plays and stops. It used to hold the view for panning, which the
  /// pan tool now does visibly and discoverably -- see CanvasTool.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // Never while somebody is typing. See isTypingInAField: this handler runs
    // before the app's text-editing shortcuts do, so without this the arrow
    // keys scrubbed instead of moving the caret and the space bar started
    // playback instead of typing a space.
    if (isTypingInAField()) return KeyEventResult.ignored;
    var keys = HardwareKeyboard.instance;
    var nudging = keys.isAltPressed;
    var step = keys.isShiftPressed ? 10.0 : 1.0;

    // Cmd on a Mac, Control everywhere else. HardwareKeyboard reports both,
    // and accepting either means the shortcut works for somebody on a Mac with
    // an external PC keyboard as well.
    var command = keys.isMetaPressed || keys.isControlPressed;
    if (command) {
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

    switch (event.logicalKey) {
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
      case LogicalKeyboardKey.delete:
      case LogicalKeyboardKey.backspace:
        controller.deleteSelected();
      case LogicalKeyboardKey.escape:
        // One thing at a time: the first Escape leaves the picture's frame,
        // and only then does the next one drop the selection.
        if (_framing != null) {
          setState(() => _framing = null);
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
    // Cheap unless the stroke or its settings have actually changed -- see
    // _refreshPreview, which is keyed on them.
    _refreshPreview();
    return _buildStage();
  }

  Widget _buildStage() => LayoutBuilder(
        builder: (context, constraints) {
          _visible = Size(constraints.maxWidth, constraints.maxHeight);
          var content = _contentSize(_visible);
          _viewport = content;

          Widget painter = SizedBox(
            width: content.width,
            height: content.height,
            // Not clipped: the text editor sits in here and a long caption
            // grows past the box it opened in rather than being cut in half.
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                  child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerHover: (e) => _updateHover(e.localPosition),
                onPointerSignal: _onPointerSignal,
                child: MouseRegion(
                  cursor: _cursor(),
                  // Clipped to the stage's own box as well as to the frame
                  // inside it. A CustomPainter is free to draw outside the
                  // bounds it is given and nothing stops it, so without this a
                  // zoomed canvas painted straight over the sidebar, the
                  // settings band and the timeline -- and took the zoom control
                  // with them, leaving no way back out.
                  child: ClipRect(
                    child: CustomPaint(
                      painter: StagePainter(
                        page: _pageRect,
                        view: _viewRect,
                        document: document,
                        frame: controller.frame,
                        scale: _scale,
                        origin: _origin,
                        images: controller.images,
                        hoveredButton: controller.hoveredButton,
                        selection: controller.selection,
                        showHelpers: controller.showHelpers,
                        selectedPath: _selectedPath(),
                        chartLabels: _selectedChartLabels(),
                        tableColumns: _selectedTableColumns(),
                        editingText: _editingText,
                        preview: _preview,
                        previewOn: _previewPlacement(),
                        liveStroke: _liveCanvas,
                        liveStrokeRadius: _liveRadius,
                        liveStrokeKeeps: controller.retouch.keeps,
                        selectionBounds: _selectionBounds,
                        framing: _framingView(),
                        showHandles: _selectionHasOwnGeometry,
                        selectionRotation: _rotationOfSelection,
                        handleFor: _handlePosition,
                        marquee: _marquee,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              )),
              if (_editorFor() case var editor?) editor,
              if (_cellEditorFor() case var cell?) cell,
            ]),
          );

          // Only scrollable when there is something to scroll. A scroll view
          // that never scrolls still claims the wheel, and the wheel is how
          // the pan tool zooms.
          if (content.height > _visible.height) {
            painter = Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                child: painter,
              ),
            );
          }

          return Focus(focusNode: _focus, onKeyEvent: _onKey, child: painter);
        },
      );

  /// _cellEditorFor is the overlay for a cell being typed into.
  ///
  /// A plain field rather than CanvasTextEditor, which draws the element's own
  /// type at the element's own size across the whole box -- right for a
  /// headline and wrong for a cell in a grid, where what is wanted is a slot
  /// the size of the cell.
  Widget? _cellEditorFor() {
    var editing = _editingCell;
    if (editing == null) return null;
    var (id, row, col) = editing;
    var element = document.elementById(id);
    if (element is! TableElement) return null;

    var box =
        tableCellRect(element, element.boundsAt(controller.frame), row, col);
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

  /// _editorFor is the text editor overlay, when one is open.
  ///
  /// Built here rather than by the screen because it has to sit in the same
  /// coordinates as the painting, and the stage is the only thing that knows
  /// what those are.
  Widget? _editorFor() {
    var id = _editingText;
    if (id == null) return null;
    var element = document.elementById(id);
    if (element is! TextElement) return null;

    var box = _editorRect ??= _editorBoxFor(element);
    var topLeft = _toStage(box.topLeft);
    return CanvasTextEditor(
      key: ValueKey("edit-$id"),
      element: element,
      rect: Rect.fromLTWH(
          topLeft.dx, topLeft.dy, box.width * _scale, box.height * _scale),
      scale: _scale,
      onChanged: (text) {
        controller.beginInteraction();
        controller.replaceElement(element.copyWith(text: text),
            transient: true);
      },
      onDone: () {
        controller.endInteraction();
        if (mounted) {
          setState(() {
            _editingText = null;
            _editorRect = null;
          });
        }
      },
    );
  }

  /// _editorBoxFor is the rectangle the editor opens in.
  ///
  /// Over the words, wherever they are -- text riding a line is drawn along
  /// the line and not in its own rectangle, so an editor on the rectangle
  /// opened in an empty part of the canvas.
  ///
  /// But not *tight* around them. The box around the letters is exactly as
  /// wide as the letters, which for a word or two is a slot too small to see
  /// what is being typed and with nowhere for the next word to go. So a
  /// minimum is imposed, generous enough to write a caption in, and the box is
  /// grown about its own centre so what is already there stays put.
  Rect _editorBoxFor(TextElement element) {
    var box = _visualBounds(element);
    if (element.curve == null) return box;

    var line = element.textSpec.fontSize * element.textSpec.lineHeight;
    var wanted = Size(
      math.max(box.width, math.max(line * 8, document.size.width * 0.3)),
      // Room for a few lines rather than exactly one, so a caption that runs
      // on has somewhere to go before the box has to grow.
      math.max(box.height, line * 3),
    );
    return Rect.fromCenter(
      center: box.center,
      width: wanted.width,
      height: wanted.height,
    );
  }

  /// _onPointerSignal decides whether the wheel belongs to this stage or to
  /// the scroll view around it.
  ///
  /// The pan tool claims it, through the resolver, so zooming wins over
  /// scrolling. The select tool does not claim it at all -- which is what lets
  /// a tall fit-width canvas be scrolled with the wheel, and is still "the
  /// select tool does not move the view", because scrolling a page that is
  /// too long to fit is not the same as the view drifting under a careful
  /// adjustment.
  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent) return;
    if (controller.tool != CanvasTool.pan) return;
    GestureBinding.instance.pointerSignalResolver
        .register(signal, (event) => _onScroll(event as PointerScrollEvent));
  }

  MouseCursor _cursor() {
    if (controller.retouch.on && _selectedPicture() != null) {
      return SystemMouseCursors.precise;
    }
    if (_mode == _DragMode.pan) return SystemMouseCursors.grabbing;
    if (controller.tool == CanvasTool.pan) return SystemMouseCursors.grab;
    if (_mode == _DragMode.rotate) return SystemMouseCursors.grabbing;
    if (_mode == _DragMode.move) return SystemMouseCursors.move;
    // A picture being reframed is grabbable everywhere inside it, and saying
    // so is most of what tells the reader they are in a mode at all.
    if (_framing != null) {
      return _mode == _DragMode.imageFrame
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.grab;
    }
    return SystemMouseCursors.basic;
  }
}
