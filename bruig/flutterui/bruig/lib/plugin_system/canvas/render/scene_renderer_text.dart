part of 'scene_renderer.dart';

// Drawing a text element: its box or line of words, their arrival part by part,
// and the type it is drawn in. Part of scene_renderer.dart.

void _paintText(
    ui.Canvas canvas, Rect bounds, TextElement e, CanvasDocument? doc,
    {Keyframe pose = Keyframe.rest,
    int frame = 0,
    CanvasImageSource? images,
    String? skipItem,
    LayerPainter? onLayer}) {
  _paintTextBody(canvas, bounds, e, doc,
      pose: pose, frame: frame, images: images, onLayer: onLayer);
  // The extra pieces of writing, over the paragraph in the same box: out
  // here because the body returns from many places. Not on a line (no box).
  if (e.items.isEmpty || _curveFor(e, doc, frame) != null) return;
  var (animation, reveal) = _arrival(e, pose);
  paintTextItems(canvas, bounds, e,
      animation: animation,
      reveal: reveal,
      images: images,
      skip: skipItem,
      onLayer: onLayer);
}

void _paintTextBody(
    ui.Canvas canvas, Rect bounds, TextElement e, CanvasDocument? doc,
    {Keyframe pose = Keyframe.rest,
    int frame = 0,
    CanvasImageSource? images,
    LayerPainter? onLayer}) {
  // The words with the looks laid on them alone, where there are any.
  void letters(ui.Canvas canvas, Rect box, void Function(ui.Canvas) draw) {
    if (onLayer == null) return draw(canvas);
    onLayer(canvas, box, MotionDevice.bodyLayer, draw);
  }

  // Text on a curve has no box of its own to fill or frame.
  var curve = _curveFor(e, doc, frame);
  if (curve != null) {
    // The pose may slide the words along the line (KeyframeChannel.slide):
    // an absolute position, not an offset.
    var on = e.curve!;
    var slide = pose.values[KeyframeChannel.slide];
    // The words still arrive letter by letter, each in its turned frame.
    var (curveAnimation, curveReveal) = _arrival(e, pose);
    letters(
        canvas,
        bounds,
        (canvas) => paintTextOnPath(canvas, e.displayText, e.textSpec, curve,
            slide == null ? on : on.copyWith(offset: slide),
            animation: curveAnimation,
            reveal: curveReveal,
            parts: e.drawnParts,
            timings: _partTimings(e, frame, pose),
            asOne: (pose.values[KeyframeChannel.close] ?? 0) > 0,
            images: images));
    return;
  }

  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) {
    if (!_waitingToArrive(e, pose, e.drawnParts)) {
      paintBox(canvas, bounds, e.box, images);
    }
    return;
  }

  // Given a slot, the element's own words are a block in the box like any
  // piece, so they stack with the pieces. See TextElement.slot.
  inner = textBodyRect(e, bounds) ?? inner;
  if (inner.width <= 0 || inner.height <= 0) {
    if (!_waitingToArrive(e, pose, e.drawnParts)) {
      paintBox(canvas, bounds, e.box, images);
    }
    return;
  }

  var spec = drawnTextSpec(e, bounds);

  // A box in a chain sharing one text draws its own share. See flowFor.
  var flow = flowFor(e, doc, inner, spec, frame: frame, images: images);
  var words = flow.text;
  // The styled runs for these words, from this box's first (TextFlow.parts).
  var drawn = e.drawnPartsWith(flow.parts);

  // How much has arrived and has left, the same two channels as a chart
  // (TextAnimation); the words lead the layers when pieces come in turn.
  var (animation, whole) = _arrival(e, pose);
  var reveal = animation.pieceReveal(whole, 0, e.items.length + 1);
  var timings = _partTimings(e, frame, pose);

  // Leaving, the paragraph goes as one: parts have no leaving of their own.
  var leaving = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  // Nothing yet, its box included, so a slab or bubble does not stand empty
  // waiting for its words from the start of the scene. See _waitingToArrive.
  if (_waitingToArrive(e, pose, drawn)) return;
  paintBox(canvas, bounds, e.box, images);

  // The words, and what is drawn with them -- after the box, which is not
  // theirs: see MotionDevice.layer.
  void drawWords(ui.Canvas canvas) {
    // Set line by line round whatever is in the way (text_wrap.dart).
    var blocked = wrapObstacles(e, doc, frame, inner, images: images);
    if (e.wrap.on &&
        blocked.isNotEmpty &&
        wrapFits(words, spec, inner, blocked, e.wrap)) {
      // Marks and arrival apply as a block: set line by line, there are no
      // pieces to move. Outline and fill as everywhere (outlineSpecFor).
      var wrapped = layoutWrapped(words, spec, inner, blocked, e.wrap,
          parts: drawn,
          outlineSpec: outlineSpecFor(spec,
              parts: drawn, animation: animation, reveal: reveal));
      var frameOf = animation.on && (reveal < 1 || animation.keeps)
          ? applyMotionSpec(
              canvas, inner, animation.spec, animation.progressAt(reveal, 0, 1),
              from: animation.spec.from)
          : const MotionFrame(1, 0, false);
      if (frameOf.alpha > 0) {
        if (frameOf.alpha < 1) {
          canvas.saveLayer(inner.inflate(inner.height),
              Paint()..color = Color.fromRGBO(0, 0, 0, frameOf.alpha));
        }
        // The stroke drawn onto the words, where that is the preset: the
        // motion leaves the opacity alone (applyMotion), so it is done here.
        var p = animation.progressAt(reveal, 0, 1);
        var stroke = animation.on &&
            animation.preset.motion == TextMotion.strokeOn &&
            reveal < 1;
        var written = stroke ? p : null;
        var fillAlpha =
            stroke && animation.draw.start == TextDrawStart.fadeText ? p : null;
        if (!spec.fill.on) {
          paintWrapped(canvas, wrapped, spec,
              written: written, fillAlpha: fillAlpha);
        } else {
          paintWrapped(canvas, wrapped, spec,
              phase: TextDrawPhase.behind, written: written);
          paintThroughText(
              canvas,
              inner,
              spec.fill,
              images,
              () => paintWrapped(canvas, wrapped, spec,
                  phase: TextDrawPhase.letters,
                  written: written,
                  fillAlpha: fillAlpha));
        }
        if (frameOf.alpha < 1) canvas.restore();
      }
      for (var r = 0; r < frameOf.depth; r++) {
        canvas.restore();
      }
      return;
    }

    if (e.columns.isSingle) {
      // Clipped to its box at rest, so words that do not fit are hidden (and
      // can run on into another box, see flowFor) -- but not while arriving,
      // since many presets bring the words in from outside the box.
      var arriving = animation.on && (reveal < 1 || animation.keeps);
      paintTextInBox(canvas, words, spec, inner,
          clip: !arriving && !partsAnimate(drawn),
          animation: animation,
          reveal: reveal,
          parts: drawn,
          timings: timings,
          asOne: leaving,
          images: images);
      return;
    }
    // Pieces are worked out once for the whole paragraph and drawn column by
    // column, so a stagger runs on; tidied tops are TextFlow.tidyStart's.
    paintTextInColumns(canvas, words, spec, inner,
        e.columns.copyWith(noBlankStart: flow.tidyStart),
        animation: animation,
        reveal: reveal,
        parts: drawn,
        timings: timings,
        asOne: leaving,
        images: images);
  }

  letters(canvas, inner, drawWords);
}

/// _waitingToArrive is whether [e] has an arrival still to come on this
/// frame, and so shows nothing yet -- unless it is a mark drawn on words
/// already there (an underline under a finished sentence), or one of its
/// [parts] arrives on its own account and this frame may be its moment.
bool _waitingToArrive(TextElement e, Keyframe pose, List<TextPart> parts) {
  var (animation, reveal) = _arrival(e, pose);
  return animation.on &&
      reveal <= 0 &&
      !(animation.keeps && animation.draw.start == TextDrawStart.showText) &&
      !partsAnimate(parts);
}

/// _partTimings is where each of [e]'s parts has got on [frame], measured
/// from the element's arrival (_arrivalFrames) so a part's offset moves with
/// it. While the element leaves, all are there: the paragraph goes as one.
List<PartTiming> _partTimings(TextElement e, int frame, Keyframe pose) {
  // Against drawnParts, which includes the element's own marks, so the list
  // lines up with the one the painter uses.
  var parts = e.drawnParts;
  if (parts.isEmpty) return const [];
  var closing = (pose.values[KeyframeChannel.close] ?? 0) > 0;
  if (closing) return [for (var _ in parts) PartTiming.there];

  var (from, to) = _arrivalFrames(e, pose);
  // No arrival stretch to measure against: every part follows the element.
  if (from == null || to == null || to <= from) {
    var reveal = pose.values[KeyframeChannel.reveal] ?? 1;
    return [
      for (var part in parts)
        PartTiming(
            part.animation.on ? reveal : 1, part.animation.marks ? reveal : 1),
    ];
  }
  return [
    for (var part in parts)
      timingOf(part, frame: frame, from: from, span: to - from),
  ];
}

/// drawnTextSpec is the type a text element is drawn in: with Fit to box
/// on, sized to the room inside [bounds] (padding included). The editor asks
/// too, so a fitted paragraph keeps its size when clicked into.
TextSpec drawnTextSpec(TextElement e, Rect bounds) {
  var spec = e.textSpec;
  if (!e.autoSize) return spec;

  var inner = e.box.inner(bounds);
  if (inner.width <= 0 || inner.height <= 0) return spec;

  // Against one column's width, the width a line is given, but all the
  // columns' room, which is where the text goes.
  var column = Size(e.columns.columnWidth(inner.width), inner.height);
  return spec.copyWith(
      fontSize:
          fitFontSize(e.displayText, spec, column, columns: e.columns.count));
}

/// _arrival is the animation a text element plays on this frame and how far
/// through it is: the two channels a chart uses, for box and line text alike.
(TextAnimation, double) _arrival(TextElement e, Keyframe pose) {
  var animation = e.animation;
  var reveal = pose.values[KeyframeChannel.reveal] ?? 1;
  var close = pose.values[KeyframeChannel.close] ?? 0;
  if (animation.closes && close > 0) {
    return (animation.leaving, 1 - close.clamp(0.0, 1.0));
  }
  return (animation, reveal);
}
