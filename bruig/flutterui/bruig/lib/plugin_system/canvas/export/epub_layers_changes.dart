part of 'epub_layers.dart';

// What about an element changes over a page and where it can draw: whether it
// moves, hovers or can be switched, the region it needs, and a name for its
// look at each frame. Part of epub_layers.dart.

/// _switchable is a chart key's series a reader can switch, with each
/// entry's place: at most five (32 pictures). Empty for anything else.
List<(int, Rect)> _switchable(CanvasElement e) {
  if (e is! ChartElement || !e.visible) return const [];
  return chartLegendRects(e, e.bounds).take(5).toList();
}

/// _hovers is whether [e] looks different under the pointer.
bool _hovers(ButtonElement e) => e.hoverFill.a > 0 || e.hoverTextColor.a > 0;

/// _regionFor is the part of the page, in page pixels, that [e] can draw in
/// at rest: its box, turned, with room for what reaches outside it (a
/// shadow, an outline, an arrival that slides or grows in). Within the page
/// unless [moves], when what is off the page can be brought onto it.
Rect _regionFor(
    CanvasElement e, double pixels, Rect pageBox, CanvasDocument document,
    {required bool moves}) {
  var bounds = e.bounds;
  // An element reused is drawn as all of its instances, each where it is
  // put (its place is in the picture; the shared move in the CSS).
  if (e.base.motion.instances case var set?) {
    for (var x in set.items) {
      bounds = bounds.expandToInclude(e.bounds.shift(Offset(x.dx, x.dy)));
    }
  }
  // Things drawn somewhere other than their own box: text riding a line, and
  // a page number mirrored to the outside edge of a left-hand leaf.
  var elsewhere =
      (e is TextElement && e.wordsSetIn(document) == WordsSet.onLine) ||
          (e is CounterElement && e.isPageNumber);
  Rect region;
  if (elsewhere) {
    region = pageBox;
  } else {
    var turned = _turnedBounds(bounds, e.rotationRadians);
    var side = math.max(bounds.width, bounds.height);
    // An arrival that slides, grows, spins or scatters reaches as far
    // again as it is big; anything else only as far as a shadow.
    var room = (_travels(e) ? side : side * 0.1 + 24) +
        // Its looks reach as far as they reach (see motion_looks.dart).
        looksReach(e.base.motion.looks);
    region = Rect.fromLTRB(
        (turned.left - room) * pixels,
        (turned.top - room) * pixels,
        (turned.right + room) * pixels,
        (turned.bottom + room) * pixels);
  }
  var limit = moves
      ? pageBox.inflate(math.max(pageBox.width, pageBox.height) / 2)
      : pageBox;
  region = region.intersect(limit);
  return Rect.fromLTRB(region.left.floorToDouble(), region.top.floorToDouble(),
      region.right.ceilToDouble(), region.bottom.ceilToDouble());
}

/// _travels is whether [e] arrives or leaves beyond its own box.
bool _travels(CanvasElement e) {
  if (e is TextElement) return e.animation.on || e.animation.closes;
  var a = switch (e) {
    ShapeElement e => e.animation,
    ImageElement e => e.animation,
    VectorElement e => e.animation,
    LineElement e => e.animation,
    PathElement e => e.animation,
    TableElement e => e.animation,
    CounterElement e => e.animation,
    ButtonElement e => e.animation,
    AudioElement e => e.animation,
    VideoElement e => e.animation,
    Character3dElement e => e.animation,
    _ => null,
  };
  return a != null && (a.on || a.closes);
}

Rect _turnedBounds(Rect box, double radians) {
  if (radians == 0) return box;
  var c = box.center;
  var cos = math.cos(radians), sin = math.sin(radians);
  var xs = <double>[], ys = <double>[];
  for (var p in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
    var dx = p.dx - c.dx, dy = p.dy - c.dy;
    xs.add(c.dx + dx * cos - dy * sin);
    ys.add(c.dy + dx * sin + dy * cos);
  }
  return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min),
      xs.reduce(math.max), ys.reduce(math.max));
}

/// _changes is whether [e] looks different, or is somewhere different, at
/// any frame of a page [frames] long.
bool _changes(CanvasElement e, int frames, CanvasDocument page) {
  if (frames <= 1) return false;
  // A score sheet lights its notes and moves its playhead as the page
  // plays; an instrument lights its keys.
  if (e is SheetElement && sheetViewOf(e, e.bounds, page, 0) != null) {
    return true;
  }
  // An instrument on the page is played by the reader, its keys lit.
  if (e is AudioElement && e.instrument != null && e.visible) return true;
  // And so is a synth's keyboard module.
  if (e is SynthModuleElement &&
      e.module == SynthModuleKind.keys &&
      e.visible) {
    return true;
  }
  var rate = page.frameRate;
  Keyframe poseAt(int f) => poseWithMotion(e, f, page);
  var first = poseAt(0);
  var firstLook =
      _lookAt(e, 0, first, frames, rate, poseAt: poseAt, page: page);
  for (var f = 1; f < frames; f++) {
    var pose = poseAt(f);
    if (pose.dx != first.dx ||
        pose.dy != first.dy ||
        pose.rotate != first.rotate ||
        pose.scale != first.scale ||
        pose.opacity != first.opacity) {
      return true;
    }
    if (_lookAt(e, f, pose, frames, rate, poseAt: poseAt, page: page) !=
        firstLook) {
      return true;
    }
  }
  return false;
}

/// _lookAt names [e]'s look at frame [f] of [page], pose aside: the same
/// name is the same picture. Mostly the pose's pinned channels; what reads
/// the frame itself (staggered text, series, players, patterns) adds it.
String _lookAt(CanvasElement e, int f, Keyframe pose, int frames, int rate,
    {Keyframe Function(int frame)? poseAt, required CanvasDocument page}) {
  var values = pose.values.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  var named = values.map((v) => "${v.key}=${v.value}").join(";");
  // A chart whose series start apart is named by how far each has got.
  if (e is ChartElement) {
    if (chartSeriesReveal(e, f, rate, poseAt: poseAt) case var series?) {
      named = "$named;series=${series.join(",")}";
    }
  }
  var span = _frameSpan(e, frames, poseAt, page, rate: rate);
  if (span == null) return named;
  var (from, to) = span;
  var when = f < from
      ? "before"
      : f > to
          ? "after"
          : "$f";
  return "$named@$when";
}

/// _frameSpan is the stretch of frames over which [e]'s look on [page]
/// depends on the frame itself, or null where it never does.
(int, int)? _frameSpan(CanvasElement e, int frames,
    Keyframe Function(int frame)? poseAt, CanvasDocument page,
    {int rate = 24}) {
  var all = (0, frames - 1);
  switch (e) {
    // A Code panel holds still in a book (its files are frames, see
    // _liveFrames); a Run panel changes when it runs.
    case CodeElement _:
      return null;
    case CodeRunElement r:
      // Its Code panel is not to hand here: when it runs is after its
      // typing, worked out where the page is (see _codeRunSpan).
      return _codeRunSpan[r.id];
    case BackgroundElement b:
      return b.spec.animated ? all : null;
    case TeamElement t:
      return t.players.any((p) => p.track?.isEmpty == false) ? all : null;
    case TextElement t:
      if (t.wordsSetIn(page) == WordsSet.onLine) return all;
      return _valuedSpan(t, frames, poseAt);
    case ChartElement _:
      // Named by its channels and its series -- see _lookAt.
      return null;
    default:
      return null;
  }
}

/// _valuedSpan is from the first channel-pinning keyframe to the last;
/// with clips, where their poses' values change, sampled via [poseAt].
(int, int)? _valuedSpan(
    CanvasElement e, int frames, Keyframe Function(int frame)? poseAt) {
  if (poseAt != null && !e.base.motion.isEmpty) {
    int? from, to;
    var was = poseAt(0).values;
    for (var f = 1; f < frames; f++) {
      var now = poseAt(f).values;
      if (!_sameValues(was, now)) {
        from ??= f - 1;
        to = f;
      }
      was = now;
    }
    // Values held the whole way still count from the start.
    if (from == null && poseAt(0).values.isNotEmpty) return (0, 0);
    return from == null ? null : (from, to!);
  }
  var keys = [
    for (var k in e.track?.keys ?? const <Keyframe>[])
      if (k.values.isNotEmpty) k.frame,
  ];
  if (keys.isEmpty) return null;
  return (keys.reduce(math.min), keys.reduce(math.max));
}

bool _sameValues(Map<String, double> a, Map<String, double> b) =>
    a.length == b.length && a.entries.every((x) => b[x.key] == x.value);
