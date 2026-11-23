part of '../canvas_controller.dart';

// Part of CanvasController: replacing a colour everywhere, the document's
// named text styles (counters' among them), and a text's pieces: the one
// picked in its Layers, and one taken out or copied, the same from the
// Layers, the piece's own panel and the stage. Its state is _TextState, at
// the end of this file.

extension CanvasTextStyles on CanvasController {
  /// replaceColour makes every use of [from] in the document [to], as one
  /// change, keeping each use's opacity (see replacing): every scene, the
  /// master, the cast, text styles, sheets, keyed Design colours and a 3D
  /// character's, shown or not. What is the editor's or must match footage
  /// is left alone (see mapColours). Where nothing matches the document is
  /// the very same, and apply makes no undo step of it.
  void replaceColour(Color from, Color to) =>
      apply(_document.mapColours(replacing(from, to)));

  /// textLayer is the piece of [e] picked in its Layers, or null for its
  /// own words (also returned for a piece since removed).
  TextItem? textLayer(TextElement e) {
    var id = _texts.pieces[e.id];
    if (id == null) return null;
    for (var item in e.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// pickTextLayer picks piece [itemId] of text element [elementId] in its
  /// Layers, or its own words with null.
  void pickTextLayer(String elementId, String? itemId) {
    if (_texts.pieces[elementId] == itemId) return;
    if (itemId == null) {
      _texts.pieces.remove(elementId);
    } else {
      _texts.pieces[elementId] = itemId;
    }
    notifyListeners();
  }

  /// removeTextPiece takes piece [itemId] out of text element [elementId],
  /// with the looks laid on it, as one undo step, and picks the text's own
  /// words in its Layers.
  void removeTextPiece(String elementId, String itemId) {
    if (_document.elementById(elementId) case TextElement e) {
      _changeText(withoutPiece(e, itemId));
    }
    pickTextLayer(elementId, null);
  }

  /// duplicateTextPiece copies piece [itemId] of text element [elementId]
  /// just after it, with the looks laid on it, as one undo step, and picks
  /// the copy in the text's Layers.
  void duplicateTextPiece(String elementId, String itemId) {
    if (_document.elementById(elementId) case TextElement e) {
      var copyId = newElementId();
      var next = withPieceCopied(e, itemId, copyId: copyId);
      if (identical(next, e)) return;
      _changeText(next);
      pickTextLayer(elementId, copyId);
    }
  }

  /// _changeText puts [next] in place of the text it was made from as one
  /// undo step, as the panel writes a change: within a step already open
  /// (typing not yet let go of), it is part of that one.
  void _changeText(TextElement next) {
    beginInteraction();
    replaceElement(next, transient: true);
    endInteraction();
  }

  List<NamedTextStyle> get textStyles => _document.textStyles;

  /// _nextStyleName is [wanted], or the first "Style N" not yet taken when
  /// it is empty or taken.
  String _nextStyleName([String wanted = ""]) {
    var taken = {for (var t in textStyles) t.name};
    if (wanted.isNotEmpty && !taken.contains(wanted)) return wanted;
    for (var n = textStyles.length + 1;; n++) {
      if (!taken.contains("Style $n")) return "Style $n";
    }
  }

  /// _restyled is [e] with each named style it is set in passed through
  /// [change], which is given the style's name and the type set in it, and
  /// gives back the name and type to have instead, or null to leave that
  /// one as it is. A text is set in one style and a counter in two (its
  /// figures' and its words'); no other kind in any. This is the one place
  /// that says so.
  CanvasElement _restyled(CanvasElement e, _Restyle change) {
    switch (e) {
      case TextElement(:var style) when style.isNotEmpty:
        var to = change(style, e.textSpec);
        if (to == null) return e;
        var next = e.copyWith(style: to.name, textSpec: to.spec);
        // A style's shadow, glow and outline are looks on the words, as the
        // text's own are: see text_looks.dart.
        return identical(to.spec, e.textSpec) ? next : textLooksLifted(next);
      case CounterElement(:var numberStyle, :var wordStyle):
        var number =
            numberStyle.isEmpty ? null : change(numberStyle, e.numberSpec);
        var words = wordStyle.isEmpty ? null : change(wordStyle, e.affixSpec);
        if (number == null && words == null) return e;
        return e.copyWith(
            numberStyle: number?.name,
            numberSpec: number?.spec,
            wordStyle: words?.name,
            affixSpec: words?.spec);
      default:
        return e;
    }
  }

  /// saveTextStyle makes [e]'s type a named style -- the next "Style N" if
  /// no name is given -- and sets [e] in it.
  String saveTextStyle(TextElement e, {String name = ""}) {
    name = _nextStyleName(name);
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

  /// updateTextStyle makes style [name] [spec], and restyles every text and
  /// counter set in it, in every scene and on the master, as one change.
  /// One whose type is no longer the style's was changed by hand, and is
  /// left as it is, still carrying the name: so the panel can still push
  /// that edit into the style (the source of a change already has [spec]).
  void updateTextStyle(String name, TextSpec spec) {
    var was = textStyles.where((t) => t.name == name).firstOrNull?.spec;
    if (was == null) return;
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles) t.name == name ? NamedTextStyle(name, spec) : t,
    ]);
    apply(_everyElement(
        next,
        (e, _) => _restyled(
            e,
            (style, own) => style == name && typeFollowsStyle(own, was)
                ? (name: name, spec: spec)
                : null)));
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
    var name = _nextStyleName();
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
        _everyElement(
            next,
            (e, _) => _restyled(e,
                (style, own) => style == from ? (name: to, spec: own) : null)),
        transient: transient);
  }

  /// removeTextStyle forgets style [name]; its texts keep its type as theirs.
  void removeTextStyle(String name) {
    var next = _document.copyWith(textStyles: [
      for (var t in textStyles)
        if (t.name != name) t,
    ]);
    apply(_everyElement(
        next,
        (e, _) => _restyled(
            e, (style, own) => style == name ? (name: "", spec: own) : null)));
  }
}

/// _Restyle is a change to one named style an element is set in: given the
/// style's name and the type set in it, the name and type to have instead,
/// or null to leave it.
typedef _Restyle = ({String name, TextSpec spec})? Function(
    String style, TextSpec own);

/// _TextState is what CanvasTextStyles keeps between calls, for the open
/// canvas only: the controller makes a new one when another opens.
class _TextState {
  /// pieces is the piece picked in each text element's Layers, by element
  /// id; one not here has its own words picked.
  final Map<String, String> pieces = {};
}
