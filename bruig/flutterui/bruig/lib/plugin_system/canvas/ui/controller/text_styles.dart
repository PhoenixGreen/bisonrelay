part of '../canvas_controller.dart';

// Part of CanvasController: replacing a colour everywhere, and the document's
// named text styles, counters' among them.

extension CanvasTextStyles on CanvasController {
  /// replaceColour makes every use of [from] in the document [to], as one
  /// change, keeping each use's opacity (see replacing): every scene, the
  /// master, the cast, text styles, sheets, keyed Design colours and a 3D
  /// character's, shown or not. What is the editor's or must match footage
  /// is left alone (see mapColours). Where nothing matches the document is
  /// the very same, and apply makes no undo step of it.
  void replaceColour(Color from, Color to) =>
      apply(_document.mapColours(replacing(from, to)));

  List<NamedTextStyle> get textStyles => _document.textStyles;

  /// saveTextStyle makes [e]'s type a named style -- the next "Style N" if
  /// no name is given -- and sets [e] in it.
  String saveTextStyle(TextElement e, {String name = ""}) {
    var taken = {for (var t in textStyles) t.name};
    if (name.isEmpty || taken.contains(name)) {
      for (var n = textStyles.length + 1;; n++) {
        if (!taken.contains("Style $n")) {
          name = "Style $n";
          break;
        }
      }
    }
    var next = _document.copyWith(
        textStyles: [...textStyles, NamedTextStyle(name, e.textSpec)]);
    apply(_replacedAnywhere(next, e.copyWith(style: name)) ?? next);
    return name;
  }

  /// useTextStyle sets text [id] in style [name], or its own type for "".
  void useTextStyle(String id, String name) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! TextElement) return e;
      // A style's shadow, glow and outline are looks on the words, as the
      // text's own are: see text_looks.dart.
      return style == null
          ? e.copyWith(style: "")
          : textLooksLifted(e.copyWith(style: name, textSpec: style.spec));
    }));
  }

  /// updateTextStyle makes style [name] [spec], and restyles every text set
  /// in it, in every scene and on the master, as one change.
  void updateTextStyle(String name, TextSpec spec) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == name ? NamedTextStyle(name, spec) : t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberSpec: e.numberStyle == name ? spec : null,
            affixSpec: e.wordStyle == name ? spec : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return textLooksLifted(e.copyWith(textSpec: spec));
    }));
  }

  /// useCounterStyle is useTextStyle for counter [id]'s number, or [words].
  void useCounterStyle(String id, String name, {bool words = false}) {
    var style = textStyles.where((t) => t.name == name).firstOrNull;
    apply(_everyElement(_document, (e, _) {
      if (e.id != id || e is! CounterElement) return e;
      var link = style == null ? "" : name;
      return words
          ? e.copyWith(wordStyle: link, affixSpec: style?.spec)
          : e.copyWith(numberStyle: link, numberSpec: style?.spec);
    }));
  }

  /// saveCounterStyle is saveTextStyle for counter [e]'s number, or [words].
  String saveCounterStyle(CounterElement e, {bool words = false}) {
    var taken = {for (var t in textStyles) t.name};
    var name = "";
    for (var n = textStyles.length + 1;; n++) {
      if (!taken.contains("Style $n")) {
        name = "Style $n";
        break;
      }
    }
    var spec = words ? e.affixSpec : e.numberSpec;
    var next = _document
        .copyWith(textStyles: [...textStyles, NamedTextStyle(name, spec)]);
    var linked =
        words ? e.copyWith(wordStyle: name) : e.copyWith(numberStyle: name);
    apply(_replacedAnywhere(next, linked) ?? next);
    return name;
  }

  /// renameTextStyle renames a style, and every text set in it with it.
  void renameTextStyle(String from, String to, {bool transient = false}) {
    if (to.isEmpty || textStyles.any((t) => t.name == to)) return;
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == from ? NamedTextStyle(to, t.spec) : t,
    ]);
    apply(
        _everyElement(next, (e, _) {
          if (e is CounterElement) {
            return e.copyWith(
                numberStyle: e.numberStyle == from ? to : null,
                wordStyle: e.wordStyle == from ? to : null);
          }
          if (e is! TextElement || e.style != from) return e;
          return e.copyWith(style: to);
        }),
        transient: transient);
  }

  /// removeTextStyle forgets style [name]; its texts keep its type as theirs.
  void removeTextStyle(String name) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles)
        if (t.name != name) t,
    ]);
    apply(_everyElement(next, (e, _) {
      if (e is CounterElement) {
        return e.copyWith(
            numberStyle: e.numberStyle == name ? "" : null,
            wordStyle: e.wordStyle == name ? "" : null);
      }
      if (e is! TextElement || e.style != name) return e;
      return e.copyWith(style: "");
    }));
  }

  /// staggerArrivals has elements [ids] arrive [gap] frames apart, left to
  /// right or, [downwards], top to bottom. The first keeps its timing; the
  /// rest have their keyframes shifted to start [gap] after the one before.
  void staggerArrivals(List<String> ids, int gap, {bool downwards = false}) {
    var rate = math.max(1, _document.frameRate);
    // Its arrival's start; or, with none, its first keyframe or clip.
    int? arrivalOf(CanvasElement e) {
      if (ownSpan(e, MotionKind.arrive, rate) case (var at, _)) return at;
      var keys = e.base.track?.keys ?? const <Keyframe>[];
      if (keys.isNotEmpty) return keys.first.frame;
      var placed = e.base.motion.placed;
      if (placed.isEmpty) return null;
      return (placed.map((p) => p.start).reduce(math.min) * rate).round();
    }

    var picked = [
      for (var id in ids)
        if (_document.elementById(id) case var e? when arrivalOf(e) != null) e,
    ];
    if (picked.length < 2) return;
    picked.sort((a, b) => downwards
        ? a.base.y.compareTo(b.base.y)
        : a.base.x.compareTo(b.base.x));

    var first = arrivalOf(picked.first)!;
    var next = _document;
    for (var (i, e) in picked.indexed) {
      var by = first + i * gap - arrivalOf(e)!;
      if (by == 0) continue;
      // Keyframes and clips alike: whatever it does moves with it.
      var track = e.base.track;
      next = next.withElement(e.withBase(
          track: track == null || track.isEmpty ? track : _shifted(track, by),
          motion: e.base.motion.shiftedBy(by / rate)));
    }
    apply(next);
  }

  /// _runStartOf is where [id]'s frames count from: its scene's start, or 0.
  int _runStartOf(String id) {
    for (var (i, scene) in _document.allScenes.indexed) {
      if (scene.elements.any((e) => e.id == id)) {
        return _document.hasScenes ? _document.startOfScene(i) : 0;
      }
    }
    return 0;
  }
}
