import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';

/// WrapSide is which side of an obstacle the words go.
enum WrapSide {
  /// both fills every free run on the line, words either side of an obstacle.
  both("Both sides"),

  /// left keeps the words left of whatever is in the way, right to its right:
  /// one block of text beside a picture, not lines broken in two.
  left("Left of it"),
  right("Right of it");

  final String label;
  const WrapSide(this.label);

  static WrapSide fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => both);
}

/// TextWrap is words flowing around whatever overlaps their box. Off by
/// default: on, the words are set line by line against the elements around
/// them rather than laid out once, which is slower.
class TextWrap {
  final bool on;

  /// gap is the room left between the words and what they go round.
  final double gap;

  final WrapSide side;

  const TextWrap({this.on = false, this.gap = 12, this.side = WrapSide.both});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextWrap();

  TextWrap copyWith({bool? on, double? gap, WrapSide? side}) => TextWrap(
        on: on ?? this.on,
        gap: gap ?? this.gap,
        side: side ?? this.side,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        if (gap != _defaults.gap) "gap": gap,
        if (side != _defaults.side) "side": side.name,
      };

  factory TextWrap.fromJson(Map<String, dynamic> json) => TextWrap(
        on: jsonBool(json["on"], false),
        gap: jsonLength(json["gap"], _defaults.gap),
        side: WrapSide.fromName(jsonStr(json["side"])),
      );
}

enum ColumnRuleStyle {
  none("None"),
  solid("Solid"),
  dashed("Dashed"),
  dotted("Dotted");

  final String label;
  const ColumnRuleStyle(this.label);

  static ColumnRuleStyle fromName(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => ColumnRuleStyle.none,
      );
}

class TextColumns {
  final int count;

  /// gap is the space between columns in design units; a rule runs down it.
  final double gap;

  final ColumnRuleStyle ruleStyle;
  final double ruleWidth;
  final Color ruleColor;

  /// noBlankStart (on by default) drops a blank line that would begin a
  /// column or chained box, so it does not sit lower than its neighbour.
  final bool noBlankStart;

  const TextColumns({
    this.count = 1,
    this.gap = 24,
    this.noBlankStart = true,
    this.ruleStyle = ColumnRuleStyle.none,
    this.ruleWidth = 1,
    this.ruleColor = const Color(0x66FFFFFF),
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextColumns();

  bool get isSingle => count <= 1;

  /// says is whether this has anything to record beyond the default.
  bool get says => !isSingle || !noBlankStart;

  double columnWidth(double total) {
    if (count <= 1) return total;
    var used = gap * (count - 1);
    return math.max(0, (total - used) / count);
  }

  TextColumns copyWith({
    int? count,
    double? gap,
    ColumnRuleStyle? ruleStyle,
    double? ruleWidth,
    Color? ruleColor,
    bool? noBlankStart,
  }) =>
      TextColumns(
        count: count ?? this.count,
        gap: gap ?? this.gap,
        ruleStyle: ruleStyle ?? this.ruleStyle,
        ruleWidth: ruleWidth ?? this.ruleWidth,
        ruleColor: ruleColor ?? this.ruleColor,
        noBlankStart: noBlankStart ?? this.noBlankStart,
      );

  /// mapColours maps the rule's colour, shown only with a rule (as it is
  /// saved).
  TextColumns mapColours(ColourMap f) {
    var next = f(ruleColor, shown: ruleStyle != _defaults.ruleStyle);
    return next == ruleColor ? this : copyWith(ruleColor: next);
  }

  Map<String, dynamic> toJson() => {
        "count": count,
        "noBlankStart": noBlankStart,
        "gap": gap,
        if (ruleStyle != _defaults.ruleStyle) "ruleStyle": ruleStyle.name,
        if (ruleStyle != _defaults.ruleStyle) "ruleWidth": ruleWidth,
        if (ruleStyle != _defaults.ruleStyle)
          "ruleColor": colorToJson(ruleColor),
      };

  factory TextColumns.fromJson(Map<String, dynamic> json) => TextColumns(
        noBlankStart: jsonBool(json["noBlankStart"], true),
        count: jsonInt(json["count"], _defaults.count).clamp(1, 12),
        gap: jsonLength(json["gap"], _defaults.gap),
        ruleStyle: ColumnRuleStyle.fromName(jsonString(json["ruleStyle"], "")),
        ruleWidth:
            jsonDouble(json["ruleWidth"], _defaults.ruleWidth).clamp(0.0, 40.0),
        ruleColor: colorFromJson(json["ruleColor"], _defaults.ruleColor),
      );
}

/// TextOnCurve puts a paragraph along another element's line. The line is
/// named rather than copied, so moving or reshaping it carries the text.
class TextOnCurve {
  /// elementId is a line or a path element. Anything else, or a deleted
  /// element, is ignored and the text falls back to its box.
  final String elementId;

  /// offset slides the text along the curve, as a fraction of its length.
  final double offset;

  /// away flips the text to the other side of the line, for a label under it.
  final bool away;

  /// spacing is extra room between letters on top of the spec's own, for
  /// tight bends where glyphs would overlap.
  final double spacing;

  /// hideHost leaves the line undrawn. Hiding the line element would not do:
  /// a hidden element is skipped everywhere, and the text would go with it.
  final bool hideHost;

  /// mask hides what has slid off the line's ends, so the line is a window
  /// and a slide reads as words arriving from behind something.
  final bool mask;

  const TextOnCurve({
    required this.elementId,
    this.offset = 0,
    this.away = false,
    this.spacing = 0,
    this.hideHost = false,
    this.mask = false,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextOnCurve(elementId: "");

  /// canRide is whether [host] is something words can be set along: a
  /// line, or a path with at least two points.
  static bool canRide(CanvasElement? host) =>
      host is LineElement || (host is PathElement && host.nodes.length >= 2);

  TextOnCurve copyWith({
    String? elementId,
    double? offset,
    bool? away,
    double? spacing,
    bool? hideHost,
    bool? mask,
  }) =>
      TextOnCurve(
        elementId: elementId ?? this.elementId,
        offset: offset ?? this.offset,
        away: away ?? this.away,
        spacing: spacing ?? this.spacing,
        hideHost: hideHost ?? this.hideHost,
        mask: mask ?? this.mask,
      );

  Map<String, dynamic> toJson() => {
        "id": elementId,
        if (offset != _defaults.offset) "offset": offset,
        if (away) "away": true,
        if (spacing != _defaults.spacing) "spacing": spacing,
        if (hideHost) "hideHost": true,
        if (mask) "mask": true,
      };

  factory TextOnCurve.fromJson(Map<String, dynamic> json) => TextOnCurve(
        elementId: jsonId(json["id"], ""),
        // A share of the line: the panel slides two lines' length each way.
        offset: jsonDouble(json["offset"], _defaults.offset).clamp(-100, 100),
        away: jsonBool(json["away"], false),
        spacing: jsonLength(json["spacing"], _defaults.spacing, signed: true),
        hideHost: jsonBool(json["hideHost"], false),
        mask: jsonBool(json["mask"], false),
      );
}

/// WordsSet is how a text's words are set on the page. A text may hold the
/// fields of several arrangements at once (a line to ride, wrapping,
/// columns) and keeps them all, so a text taken off its line gets its
/// columns back; TextElement.wordsSetIn is the one place that says which of
/// them wins, and every reader asks it.
enum WordsSet {
  /// onLine is letter by letter along the line or path the text rides
  /// (TextElement.curve). There is no box: no pieces, slot, fitting,
  /// wrapping, columns or flow.
  onLine,

  /// wrapped is line by line round whatever on the page overlaps the box
  /// (text_wrap.dart), on a frame where something does and there is room
  /// round it; on any other frame the words are set as
  /// TextElement.unwrappedSet says.
  wrapped,

  /// inColumns is the box's room shared between columns (TextColumns).
  inColumns,

  /// inBox is one paragraph filling the box, or held in a slot of it: the
  /// usual.
  inBox,
}

/// maxTextPieces and maxTextParts are the most pieces and parts a text is
/// read with: far more than anyone adds by hand, while a received text's
/// million would each be laid out on every frame.
const maxTextPieces = 1000, maxTextParts = 10000;

/// TextElement is a paragraph in a box. The letters' look is in [textSpec]
/// and the box in [box]; a new type control belongs in TextSpec.
class TextElement extends CanvasElement {
  final String text;
  final TextSpec textSpec;
  final BoxSpec box;

  /// autoSize grows the type to fill the box rather than wrapping it.
  final bool autoSize;

  final TextColumns columns;

  final TextAnimation animation;

  /// slot is where the element's own words sit, or null (usual) to fill the
  /// box: wrap, take columns and flow on. In a slot they behave like a piece
  /// -- as wide as they come out, held to that corner -- and stack with the
  /// pieces there. Ignored on a line, in columns or in a chain.
  final TextSlot? slot;

  /// items are the extra pieces of writing in the box, each in its own slot.
  final List<TextItem> items;

  /// parts are runs drawn differently: another colour, bold, own arrival.
  final List<TextPart> parts;

  /// highlight and underline are the element's own marks over all of its
  /// words, the same two a part carries; see [drawnParts].
  final PartHighlight? highlight;
  final PartUnderline? underline;

  /// flowTo is the text element the overflow runs on into, or "" for none.
  /// One way only: a ring of boxes has no first box, and flowFor refuses one.
  final String flowTo;

  /// document is the Writing library document these words came from, if
  /// any; copied into [text], so drawing and export never wait on it.
  final TextDocumentRef document;

  /// documentParts are the runs the document's markdown asked for, apart
  /// from [parts]: they are rewritten on every read; the reader's must stay.
  final List<TextPart> documentParts;

  final TextWrap wrap;

  /// style names the document's text style this is set in, or "" for its
  /// own (see CanvasDocument.textStyles). Changing the style restyles it
  /// while its type is still the style's (CanvasController.updateTextStyle).
  final String style;

  /// curve attaches the text to a line, or is null for its own box.
  final TextOnCurve? curve;

  const TextElement(
    super.base, {
    this.text = "Text",
    this.textSpec = const TextSpec(),
    this.box = const BoxSpec(),
    this.autoSize = false,
    this.columns = const TextColumns(),
    this.animation = const TextAnimation(),
    this.slot,
    this.items = const [],
    this.parts = const [],
    this.highlight,
    this.underline,
    this.flowTo = "",
    this.document = const TextDocumentRef(),
    this.documentParts = const [],
    this.wrap = const TextWrap(),
    this.style = "",
    this.curve,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = TextElement(ElementBase(id: ""));

  @override
  ElementKind get kind => ElementKind.text;

  /// assetIds is every stored picture this element refers to. One left out
  /// is swept away as unused; see CanvasStorage.liveAssetIds.
  @override
  Set<String> get assetIds => {
        for (var item in items) ...{
          if (item.icon?.assetId.isNotEmpty ?? false) item.icon!.assetId,
          // A piece's letters can be painted with a picture of their own.
          if (item.spec.fill.assetId.isNotEmpty) item.spec.fill.assetId,
          ...item.box.assetIds,
          ...?item.icon?.box.assetIds,
        },
        if (textSpec.fill.assetId.isNotEmpty) textSpec.fill.assetId,
        ...box.assetIds,
      };

  /// wordsSetIn is how the words are set on a page of [doc]: the first of
  /// these that holds. Along the line [curve] names, when that line is on the
  /// page (without it, or without a page, the text stays in its own box);
  /// round what is in the way, with [wrap] on; in [columns], with more than
  /// one; in the box. The fields of the ways that lose are kept, unread.
  ///
  /// A new way of setting words is a case in WordsSet and its place in this
  /// order; every reader switches over the answer without a default, so the
  /// compiler names each one that must say what the new way does.
  WordsSet wordsSetIn(CanvasDocument? doc) {
    if (curve case var on?
        when TextOnCurve.canRide(doc?.elementById(on.elementId))) {
      return WordsSet.onLine;
    }
    if (wrap.on) return WordsSet.wrapped;
    return unwrappedSet;
  }

  /// unwrappedSet is how the words are set in the box with nothing in their
  /// way: in columns or in one paragraph. What a wrapped text is set as on a
  /// frame where nothing overlaps it.
  WordsSet get unwrappedSet =>
      columns.isSingle ? WordsSet.inBox : WordsSet.inColumns;

  /// fittedIn is whether the type is sized to fill the box (autoSize) on a
  /// page of [doc]: never on a line, which has no box to fill.
  bool fittedIn(CanvasDocument? doc) =>
      autoSize && wordsSetIn(doc) != WordsSet.onLine;

  /// flowsOnIn is whether the words that do not fit run on into the box
  /// [flowTo] names, on a page of [doc]. Not from a text on a line, which
  /// draws all of its words, nor into one, which draws its own; see
  /// flowFor.
  bool flowsOnIn(CanvasDocument? doc) {
    if (flowTo.isEmpty || wordsSetIn(doc) == WordsSet.onLine) return false;
    var into = doc?.elementById(flowTo);
    return !(into is TextElement && into.wordsSetIn(doc) == WordsSet.onLine);
  }

  /// showsPiecesIn is whether the pieces ([items]) are drawn, and so
  /// pressed, on a page of [doc]: not on a line, where there is no box to
  /// hold them. They are kept, and come back with the box.
  bool showsPiecesIn(CanvasDocument? doc) =>
      items.isNotEmpty && wordsSetIn(doc) != WordsSet.onLine;

  /// bodySlotIn is the slot the text's own words are held in, a block among
  /// the pieces, on a page of [doc]; null for words filling the box. Only in
  /// a box of their own: not on a line, in columns or running on into
  /// another box, and not with no words to hold.
  TextSlot? bodySlotIn(CanvasDocument? doc) {
    if (slot == null || text.isEmpty || flowsOnIn(doc)) return null;
    return switch (wordsSetIn(doc)) {
      WordsSet.onLine || WordsSet.inColumns => null,
      // Round what is in the way within the slot's block; in columns, with
      // nothing in the way, the columns win as they do unwrapped.
      WordsSet.wrapped => columns.isSingle ? slot : null,
      WordsSet.inBox => slot,
    };
  }

  /// wordsFromDocument is whether the words are read from a Writing
  /// document ([document]) rather than typed. Whatever the setting: a line,
  /// columns and wrapping all set the document's words. A box flowed into
  /// draws the head's words, a document's or not (flowFor).
  bool get wordsFromDocument => document.on;

  /// handlesPiece is whether piece [item] is handled on the canvas by a box
  /// of its own, moved by the arrows and dragged: a picture chosen, shown
  /// and unlocked, in an unlocked text whose pieces are drawn on a page of
  /// [doc] (see showsPiecesIn).
  bool handlesPiece(TextItem item, CanvasDocument? doc) =>
      !locked &&
      showsPiecesIn(doc) &&
      item.isIcon &&
      item.icon!.on &&
      !item.hidden &&
      !item.locked;

  /// drawnParts are the parts the painter works from: the element's own marks
  /// as a part over every word, then the parts. Marks first, so a part's
  /// highlight draws over them and a part still decides its words' look.
  List<TextPart> get drawnParts => drawnPartsWith(documentParts);

  /// drawnPartsWith is drawnParts with the document's runs given, as a box in
  /// a chain needs: it draws the head's runs, moved. See TextFlow.parts.
  List<TextPart> drawnPartsWith(List<TextPart> fromDocument) => [
        if (highlight != null || underline != null)
          TextPart(highlight: highlight, underline: underline),
        // The reader's parts last, so they win where they overlap (partAt).
        ...fromDocument,
        ...parts,
      ];

  /// displayText is the typed string with the case transform applied; see
  /// TextCase on why it is not baked into [text].
  String get displayText => textSpec.textCase.apply(text);

  @override
  bool get scalesInside => true;

  /// scaledBy scales the words, pieces, box, marks (drawn ones too) and gaps
  /// by [by], but not
  /// a curve's offset (a fraction of the line) or the column count.
  @override
  CanvasElement scaledBy(double by) => copyWith(
        textSpec: textSpec.scaledBy(by),
        box: box.scaledBy(by),
        items: [for (var item in items) item.scaledBy(by)],
        columns: columns.copyWith(gap: columns.gap * by),
        highlight: highlight?.scaledBy(by),
        underline: underline?.scaledBy(by),
        parts: [for (var part in parts) part.scaledBy(by)],
        documentParts: [for (var part in documentParts) part.scaledBy(by)],
        wrap: wrap.copyWith(gap: wrap.gap * by),
        curve: curve?.copyWith(spacing: curve!.spacing * by),
        animation: animation.copyWith(draw: animation.draw.scaledBy(by)),
      );

  @override
  CanvasElement rebase(ElementBase base) => TextElement(base,
      text: text,
      textSpec: textSpec,
      box: box,
      autoSize: autoSize,
      columns: columns,
      animation: animation,
      slot: slot,
      items: items,
      parts: parts,
      highlight: highlight,
      underline: underline,
      flowTo: flowTo,
      document: document,
      documentParts: documentParts,
      wrap: wrap,
      style: style,
      curve: curve);

  TextElement copyWith({
    String? text,
    TextSpec? textSpec,
    BoxSpec? box,
    bool? autoSize,
    TextColumns? columns,
    TextAnimation? animation,
    TextSlot? slot,
    bool clearSlot = false,
    List<TextItem>? items,
    List<TextPart>? parts,
    PartHighlight? highlight,
    bool clearHighlight = false,
    PartUnderline? underline,
    bool clearUnderline = false,
    String? flowTo,
    TextDocumentRef? document,
    List<TextPart>? documentParts,
    TextWrap? wrap,
    String? style,
    TextOnCurve? curve,
    bool clearCurve = false,
  }) =>
      TextElement(base,
          text: text ?? this.text,
          textSpec: textSpec ?? this.textSpec,
          box: box ?? this.box,
          autoSize: autoSize ?? this.autoSize,
          columns: columns ?? this.columns,
          animation: animation ?? this.animation,
          slot: clearSlot ? null : (slot ?? this.slot),
          items: items ?? this.items,
          parts: parts ?? this.parts,
          highlight: clearHighlight ? null : (highlight ?? this.highlight),
          underline: clearUnderline ? null : (underline ?? this.underline),
          flowTo: flowTo ?? this.flowTo,
          document: document ?? this.document,
          documentParts: documentParts ?? this.documentParts,
          wrap: wrap ?? this.wrap,
          style: style ?? this.style,
          curve: clearCurve ? null : (curve ?? this.curve));

  @override
  TextElement mapOwnColours(ColourMap f) {
    var p = ColourPass(f);
    var textSpec = p.part(this.textSpec, (s) => s.mapColours(f));
    var box = p.part(this.box, (b) => b.mapColours(f));
    var columns = p.part(this.columns, (c) => c.mapColours(f));
    var animation = p.part(this.animation, (a) => a.mapColours(f));
    var items = p.list(this.items, (i) => i.mapColours(f));
    var parts = p.list(this.parts, (x) => x.mapColours(f));
    var highlight = p.partOrNone(this.highlight, (h) => h.mapColours(f));
    var underline = p.partOrNone(this.underline, (u) => u.mapColours(f));
    var document = p.part(this.document, (d) => d.mapColours(f));
    var documentParts = p.list(this.documentParts, (x) => x.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      textSpec: textSpec,
      box: box,
      columns: columns,
      animation: animation,
      items: items,
      parts: parts,
      highlight: highlight,
      underline: underline,
      document: document,
      documentParts: documentParts,
    );
  }

  @override
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
        // Written whenever it says anything: No blank first line applies to
        // a one-column box in a chain too.
        if (columns.says) "columns": columns.toJson(),
        if (animation.any) "animation": animation.toJson(),
        if (slot != null) "slot": slot!.name,
        if (items.isNotEmpty) "items": [for (var i in items) i.toJson()],
        if (parts.isNotEmpty) "parts": [for (var p in parts) p.toJson()],
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (flowTo.isNotEmpty) "flowTo": flowTo,
        if (wrap.toJson() case var w when w.isNotEmpty) "wrap": w,
        if (style.isNotEmpty) "style": style,
        if (document.on) "document": document.toJson(),
        if (documentParts.isNotEmpty)
          "documentParts": [for (var p in documentParts) p.toJson()],
        if (curve != null) "curve": curve!.toJson(),
      };

  factory TextElement.fromJson(Map<String, dynamic> json, ElementBase b) {
    PartHighlight? highlight =
        jsonSpec(json["highlight"], PartHighlight.fromJson, null);
    PartUnderline? underline =
        jsonSpec(json["underline"], PartUnderline.fromJson, null);
    TextOnCurve? curve = jsonSpec(json["curve"], TextOnCurve.fromJson, null);
    return TextElement(b,
        text: jsonString(json["text"], _defaults.text),
        textSpec:
            jsonSpec(json["textSpec"], TextSpec.fromJson, _defaults.textSpec),
        box: jsonSpec(json["box"], BoxSpec.fromJson, _defaults.box),
        autoSize: jsonBool(json["autoSize"], false),
        animation: jsonSpec(
            json["animation"], TextAnimation.fromJson, _defaults.animation),
        slot: json["slot"] is String
            ? TextSlot.fromName(jsonStr(json["slot"]))
            : null,
        items:
            jsonObjects(json["items"], TextItem.fromJson, most: maxTextPieces),
        parts:
            jsonObjects(json["parts"], TextPart.fromJson, most: maxTextParts),
        highlight: highlight,
        underline: underline,
        document: jsonSpec(
            json["document"], TextDocumentRef.fromJson, _defaults.document),
        // A document's runs: one for every ten of its letters is far more
        // than the most marked-up writing has.
        documentParts: jsonObjects(json["documentParts"], TextPart.fromJson,
            most: maxTextLength ~/ 10),
        flowTo: jsonId(json["flowTo"], _defaults.flowTo),
        style: jsonString(json["style"], _defaults.style),
        wrap: jsonSpec(json["wrap"], TextWrap.fromJson, _defaults.wrap),
        columns:
            jsonSpec(json["columns"], TextColumns.fromJson, _defaults.columns),
        curve: curve);
  }
}
