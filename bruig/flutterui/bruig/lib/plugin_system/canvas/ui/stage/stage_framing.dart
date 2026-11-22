part of 'canvas_stage.dart';

// The camera's framing, guides dragged from the rulers, stroke previews, and
// the players on a pitch. Part of CanvasStageState: its fields, lifecycle and
// build are in canvas_stage.dart.

extension StageFramingDrag on CanvasStageState {
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
    var inner = e.box.inner(_hit.posed(e));
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
          pivot: _hit.posed(e).center,
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
    var inner = picture.box.inner(_hit.posed(picture));
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
    _previewDebounce = Timer(CanvasStageState._previewDelay, () {
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
    var hit = _hit;
    for (var i = document.elements.length - 1; i >= 0; i--) {
      var element = document.elements[i];
      if (element is! TeamElement || element.locked || !element.visible) {
        continue;
      }
      var index = hit.playerOf(element, doc);
      if (index != null) return (element, index);
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
        e.id: _hit.posed(e),
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
}
