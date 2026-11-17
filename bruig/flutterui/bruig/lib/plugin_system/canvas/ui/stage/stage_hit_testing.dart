part of 'canvas_stage.dart';

// What is under the pointer: elements, their handles, parts and pieces. Part of
// CanvasStageState: its fields, lifecycle and build are in canvas_stage.dart.

extension StageHitTesting on CanvasStageState {
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
        var twice = clock.now().difference(_lastClickAt) < CanvasStageState._doubleClickWindow;
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
}
