import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

/// WrapSide is which side of an obstacle the words go.
enum WrapSide {
  /// both fills every free run on the line, so a narrow obstacle has words on
  /// either side of it.
  both("Both sides"),

  /// left keeps the words to the left of whatever is in the way, and right to
  /// the right of it. What a caption beside a picture wants: one block of
  /// text, not a line broken in two by something in the middle of it.
  left("Left of it"),
  right("Right of it");

  final String label;
  const WrapSide(this.label);

  static WrapSide fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => both);
}

/// TextWrap is words flowing around whatever overlaps their box.
///
/// Off by default, and deliberately: with it on the words are set line by
/// line against the elements around them rather than laid out once as a
/// paragraph, which is a different and slower way of setting type. It earns
/// that where it is wanted -- a picture in the middle of a column -- and pays
/// for nothing where it is not.
class TextWrap {
  final bool on;

  /// gap is how much room is left between the words and the thing they are
  /// going round.
  final double gap;

  final WrapSide side;

  const TextWrap({this.on = false, this.gap = 12, this.side = WrapSide.both});

  TextWrap copyWith({bool? on, double? gap, WrapSide? side}) => TextWrap(
        on: on ?? this.on,
        gap: gap ?? this.gap,
        side: side ?? this.side,
      );

  Map<String, dynamic> toJson() => {
        if (on) "on": true,
        if (gap != 12) "gap": gap,
        if (side != WrapSide.both) "side": side.name,
      };

  factory TextWrap.fromJson(Map<String, dynamic> json) => TextWrap(
        on: jsonBool(json["on"], false),
        gap: jsonDouble(json["gap"], 12).clamp(0, 400),
        side: WrapSide.fromName(json["side"] as String?),
      );
}

/// ColumnRuleStyle is how the line between two columns is drawn.
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

/// TextColumns is how a paragraph is broken into columns.
///
/// Its own object rather than four fields on the element, because three of the
/// four are meaningless when [count] is 1 and grouping them is what lets the
/// settings hide the rule controls until there is a gap to draw one in.
class TextColumns {
  /// count is how many columns the text flows across. One is the ordinary
  /// case and costs nothing extra to draw.
  final int count;

  /// gap is the space between two columns, in design units. The rule, if there
  /// is one, is drawn down the middle of it.
  final double gap;

  final ColumnRuleStyle ruleStyle;
  final double ruleWidth;
  final Color ruleColor;

  /// noBlankStart drops a blank line that would have begun a column.
  ///
  /// The gap between two paragraphs is a line like any other, and when the
  /// break lands on one the next column starts with an empty row and its
  /// text sits lower than its neighbour's -- which reads as a mistake in the
  /// setting rather than as a paragraph break. The line is not moved, it is
  /// dropped: it is a space, and a space at the top of a column is the thing
  /// being complained about.
  ///
  /// On by default: the ragged column top is a fault every time it appears,
  /// so the setting exists to turn the tidying off, not to ask for it.
  final bool noBlankStart;

  const TextColumns({
    this.count = 1,
    this.gap = 24,
    this.noBlankStart = true,
    this.ruleStyle = ColumnRuleStyle.none,
    this.ruleWidth = 1,
    this.ruleColor = const Color(0x66FFFFFF),
  });

  bool get isSingle => count <= 1;

  /// says is whether this has anything to record. A single column with
  /// nothing else set is what every text element starts with, and writing it
  /// out would be a line of noise in every saved file.
  bool get says => !isSingle || !noBlankStart;

  /// columnWidth is how wide each column is inside a box [total] wide.
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

  Map<String, dynamic> toJson() => {
        "count": count,
        "noBlankStart": noBlankStart,
        "gap": gap,
        if (ruleStyle != ColumnRuleStyle.none) "ruleStyle": ruleStyle.name,
        if (ruleStyle != ColumnRuleStyle.none) "ruleWidth": ruleWidth,
        if (ruleStyle != ColumnRuleStyle.none)
          "ruleColor": colorToJson(ruleColor),
      };

  factory TextColumns.fromJson(Map<String, dynamic> json) => TextColumns(
        noBlankStart: jsonBool(json["noBlankStart"], true),
        count: jsonInt(json["count"], 1),
        gap: jsonDouble(json["gap"], 24),
        ruleStyle: ColumnRuleStyle.fromName(json["ruleStyle"] as String?),
        ruleWidth: jsonDouble(json["ruleWidth"], 1),
        ruleColor: colorFromJson(json["ruleColor"], const Color(0x66FFFFFF)),
      );
}

/// TextOnCurve puts a paragraph along another element's line.
///
/// The curve is named rather than copied, so moving or reshaping the line
/// carries its text with it -- which is the whole reason to attach text to a
/// line instead of rotating a text box next to one.
class TextOnCurve {
  /// elementId is a line or a path element. Anything else is ignored, which is
  /// also what happens when the element it names has been deleted: the text
  /// falls back to its box, rather than vanishing.
  final String elementId;

  /// offset slides the text along the curve, as a fraction of its length.
  final double offset;

  /// away flips the text to the other side of the line, for a label that
  /// should sit under it rather than on it.
  final bool away;

  /// spacing is extra room between letters as they are placed, on top of the
  /// spec's own letter spacing. A curve needs more of it on a tight bend than
  /// a straight line does, and the alternative is glyphs overlapping.
  final double spacing;

  /// hideHost leaves the line itself undrawn.
  ///
  /// Usually what is wanted. A line drawn to carry a caption round the top of
  /// a badge is scaffolding: the words are the design and the line is how they
  /// were placed. Hiding the line element itself would work, except that a
  /// hidden element is skipped everywhere -- including here -- so the text
  /// would go with it.
  final bool hideHost;

  /// mask hides whatever has slid off the ends of the line.
  ///
  /// The words follow the line past its ends -- that is what lets a caption
  /// travel off and back on -- so without this a slide carries them across
  /// whatever else is on the canvas. With it the line is a window: a letter
  /// is cut off at the end rather than continuing beyond it, which is what
  /// makes the same slide read as words arriving from behind something.
  final bool mask;

  const TextOnCurve({
    required this.elementId,
    this.offset = 0,
    this.away = false,
    this.spacing = 0,
    this.hideHost = false,
    this.mask = false,
  });

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
        if (offset != 0) "offset": offset,
        if (away) "away": true,
        if (spacing != 0) "spacing": spacing,
        if (hideHost) "hideHost": true,
        if (mask) "mask": true,
      };

  factory TextOnCurve.fromJson(Map<String, dynamic> json) => TextOnCurve(
        elementId: jsonString(json["id"], ""),
        offset: jsonDouble(json["offset"], 0),
        away: jsonBool(json["away"], false),
        spacing: jsonDouble(json["spacing"], 0),
        hideHost: jsonBool(json["hideHost"], false),
        mask: jsonBool(json["mask"], false),
      );
}

/// TextElement is a paragraph in a box.
///
/// Everything about how the letters look is in [textSpec]; everything about
/// the box around them is in [box]. This class is only the string and the
/// wiring, which is why it is short and why adding a type control means
/// touching TextSpec rather than touching every element that draws words.
class TextElement extends CanvasElement {
  final String text;
  final TextSpec textSpec;
  final BoxSpec box;

  /// autoSize grows the type to fill the box rather than wrapping it.
  ///
  /// What a title wants and what a paragraph does not, so it is a switch
  /// rather than a mode: a headline should get bigger when its box does,
  /// while body copy should reflow.
  final bool autoSize;

  /// columns is how the paragraph is broken up. See [TextColumns].
  final TextColumns columns;

  /// animation is how the words arrive. See [TextAnimation].
  final TextAnimation animation;

  /// items are the extra pieces of writing in this element's box, each in a
  /// slot of its own. See [TextItem].
  ///
  /// Empty for nearly every text element. They exist for the one that is a
  /// card rather than a paragraph: a number, a title, a line of small print
  /// and a name in the corner, which used to be four elements and a shape
  /// that had to be moved together.
  final List<TextItem> items;

  /// parts are the runs of this text that are drawn differently -- a word in
  /// another colour, a phrase in bold. See [TextPart].
  ///
  /// On the element rather than inside any one feature, because "these words,
  /// not the others" is the same question a colour, an animation and an echo
  /// all ask.
  final List<TextPart> parts;

  /// highlight and underline are the element's own marks: a band behind all
  /// of the words, a line under all of them.
  ///
  /// The same two a part carries, because they are the same question asked of
  /// everything rather than of a few words -- and asked far more often. A
  /// highlighted headline should not need a part covering the whole sentence
  /// before it can be highlighted.
  final PartHighlight? highlight;
  final PartUnderline? underline;


  /// flowTo is the text element the words that do not fit run on into, or ""
  /// for none.
  ///
  /// One way, always. A chain is a line of boxes with a head and a tail, and
  /// the words run from one to the next; a link that could point backwards
  /// would let somebody make a ring of boxes, and a ring has no first box to
  /// start reading from. See flowFor, which refuses to make one.
  final String flowTo;

  /// document is the Writing library document these words came from, if any.
  ///
  /// The words themselves are in [text]: read once and copied in, because a
  /// canvas has to draw the same on a machine that has never seen the
  /// library and an export has no disk to wait on. See TextDocumentRef.
  final TextDocumentRef document;

  /// documentParts are the runs the document's own markdown asked for -- a
  /// heading, a bold phrase, a link. Kept apart from [parts] because they are
  /// not the reader's: they are rewritten from scratch every time the
  /// document is read, and a reader's own part must survive that.
  final List<TextPart> documentParts;

  /// wrap flows the words around whatever overlaps the box. See TextWrap.
  final TextWrap wrap;

  /// curve attaches the text to a line, or is null for a paragraph in its own
  /// box. See [TextOnCurve].
  final TextOnCurve? curve;

  const TextElement(
    super.base, {
    this.text = "Text",
    this.textSpec = const TextSpec(),
    this.box = const BoxSpec(),
    this.autoSize = false,
    this.columns = const TextColumns(),
    this.animation = const TextAnimation(),
    this.items = const [],
    this.parts = const [],
    this.highlight,
    this.underline,
    this.flowTo = "",
    this.document = const TextDocumentRef(),
    this.documentParts = const [],
    this.wrap = const TextWrap(),
    this.curve,
  });

  @override
  ElementKind get kind => ElementKind.text;

  /// assetIds is every stored picture this element refers to: the pictures
  /// among its pieces, and one showing through its letters.
  ///
  /// Without this the sweep that clears out pictures nothing is using any
  /// more could not see them -- so a picture lasted until the next sweep and
  /// was gone by the next time the canvas was opened. Every element that can
  /// name a picture has to answer this. See CanvasStorage.liveAssetIds.
  @override
  Set<String> get assetIds => {
        for (var item in items)
          if (item.icon?.assetId.isNotEmpty ?? false) item.icon!.assetId,
        if (textSpec.fill.assetId.isNotEmpty) textSpec.fill.assetId,
      };

  /// drawnParts are the parts the painter works from: the element's own
  /// marks as a part covering every word, and then the parts themselves.
  ///
  /// A part rather than a second mechanism, because "a line under all of it"
  /// is "a line under words one to the end" -- and written that way the
  /// marks, their timing and their drawing on are one piece of code instead
  /// of two that would have to agree.
  ///
  /// First in the list, so a part's own highlight is drawn over the
  /// element's rather than under it, and so a part still decides the colour
  /// and weight of the words it covers.
  List<TextPart> get drawnParts => drawnPartsWith(documentParts);

  /// drawnPartsWith is drawnParts with the document's runs given rather than
  /// taken from the element -- which is what a box in a chain needs, since
  /// the runs it draws are the head's, moved. See TextFlow.parts.
  List<TextPart> drawnPartsWith(List<TextPart> fromDocument) => [
        // The element's own marks, as a part covering every word.
        if (highlight != null || underline != null)
          TextPart(highlight: highlight, underline: underline),
        // Then what a document's markdown asked for, and then the reader's
        // own parts -- which are last so that they win where they overlap.
        // See partAt: the later part is the one that decides.
        ...fromDocument,
        ...parts,
      ];

  /// displayText is what actually goes on the canvas -- the typed string with
  /// the case transform applied. See TextCase on why the transform is not
  /// baked into [text].
  String get displayText => textSpec.textCase.apply(text);

  @override
  CanvasElement rebase(ElementBase base) => TextElement(base,
      text: text,
      textSpec: textSpec,
      box: box,
      autoSize: autoSize,
      columns: columns,
      animation: animation,
      items: items,
      parts: parts,
      highlight: highlight,
      underline: underline,
      flowTo: flowTo,
      document: document,
      documentParts: documentParts,
      wrap: wrap,
      curve: curve);

  TextElement copyWith({
    String? text,
    TextSpec? textSpec,
    BoxSpec? box,
    bool? autoSize,
    TextColumns? columns,
    TextAnimation? animation,
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
          items: items ?? this.items,
          parts: parts ?? this.parts,
          highlight: clearHighlight ? null : (highlight ?? this.highlight),
          underline: clearUnderline ? null : (underline ?? this.underline),
          flowTo: flowTo ?? this.flowTo,
          document: document ?? this.document,
          documentParts: documentParts ?? this.documentParts,
          wrap: wrap ?? this.wrap,
          curve: clearCurve ? null : (curve ?? this.curve));

  @override
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
        // Written whenever it says anything, not only when there is more
        // than one column: No blank first line is asked of a box with one
        // column too -- a chain of boxes is the same question asked of boxes
        // -- so a one-column box that had it turned off saved nothing at all
        // and opened with it on again.
        if (columns.says) "columns": columns.toJson(),
        if (animation.on || animation.closes) "animation": animation.toJson(),
        if (items.isNotEmpty) "items": [for (var i in items) i.toJson()],
        if (parts.isNotEmpty) "parts": [for (var p in parts) p.toJson()],
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (flowTo.isNotEmpty) "flowTo": flowTo,
        if (wrap.toJson().isNotEmpty) "wrap": wrap.toJson(),
        if (document.on) "document": document.toJson(),
        if (documentParts.isNotEmpty)
          "documentParts": [for (var p in documentParts) p.toJson()],
        if (curve != null) "curve": curve!.toJson(),
      };

  factory TextElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      TextElement(b,
          text: jsonString(json["text"], "Text"),
          textSpec: jsonSpec(
              json["textSpec"], TextSpec.fromJson, const TextSpec()),
          box: jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec()),
          autoSize: jsonBool(json["autoSize"], false),
          animation: jsonSpec(json["animation"], TextAnimation.fromJson,
              const TextAnimation()),
          items: _itemsFromJson(json),
          parts: _partsFromJson(json),
          highlight: json["highlight"] is Map<String,
                  dynamic>
              ? PartHighlight.fromJson(json["highlight"] as Map<String,
                  dynamic>)
              : null,
          underline:
              json["underline"] is Map<String,
                      dynamic>
                  ? PartUnderline.fromJson(json["underline"] as Map<String,
                      dynamic>)
                  : null,
          // Not onto the element any more: an icon is a piece, and
          // _itemsFromJson has already made one of it.
          document:
              json["document"] is Map<String,
                      dynamic>
                  ? TextDocumentRef.fromJson(json["document"] as Map<String,
                      dynamic>)
                  : const TextDocumentRef(),
          documentParts: [
            if (json["documentParts"] case List raw)
              for (var p in raw)
                if (p is Map<String, dynamic>) TextPart.fromJson(p),
          ],
          flowTo: jsonString(json["flowTo"], ""),
          wrap:
              json["wrap"]
                      is Map<String, dynamic>
                  ? TextWrap.fromJson(json["wrap"] as Map<String, dynamic>)
                  : const TextWrap(),
          columns: jsonSpec(
              json["columns"], TextColumns.fromJson, const TextColumns()),
          curve: json["curve"] is Map<String, dynamic>
              ? TextOnCurve.fromJson(json["curve"] as Map<String, dynamic>)
              : null);
}

/// _itemsFromJson reads the pieces, and turns an older document's single
/// icon into one of them.
///
/// An icon was a feature of its own: one per element, with a place, an
/// alignment and a gap that were all its own rather than the ones the words
/// use. It is a piece now, like any other -- see TextItem -- so the place and
/// the alignment it had become the slot they add up to.
///
/// It does not lay out quite as it did: an icon *before* the words used to
/// take its room out of the box and push them along, where a piece sits over
/// the box in the corner its slot names. A document with one may want a
/// little left padding to get its old arrangement back, which is one setting
/// against a feature that had eight.
List<TextItem> _itemsFromJson(Map<String, dynamic> json) {
  var items = [
    if (json["items"] case List raw)
      for (var i in raw)
        if (i is Map<String, dynamic>) TextItem.fromJson(i),
  ];
  if (json["icon"] case Map<String, dynamic> raw) {
    var icon = TextIcon.fromJson(raw);
    if (icon.on) {
      items.add(TextItem(
        id: newElementId(),
        slot: _slotForIcon(icon),
        icon: icon,
        gap: 0,
      ));
    }
  }
  return items;
}

/// _slotForIcon is the corner an old icon's place and alignment add up to.
///
/// Beside the words, the place says which side and the alignment says how far
/// down; above or below them, the place says how far down and the alignment
/// says which side. Two questions and nine answers, which is exactly what a
/// slot is.
TextSlot _slotForIcon(TextIcon icon) {
  if (icon.place.beside) {
    var left = icon.place == IconPlace.start;
    return switch (icon.align) {
      TextIconAlign.start => left ? TextSlot.topLeft : TextSlot.topRight,
      TextIconAlign.middle => left ? TextSlot.middleLeft : TextSlot.middleRight,
      TextIconAlign.end => left ? TextSlot.bottomLeft : TextSlot.bottomRight,
    };
  }
  var over = icon.place == IconPlace.over;
  return switch (icon.align) {
    TextIconAlign.start => over ? TextSlot.topLeft : TextSlot.bottomLeft,
    TextIconAlign.middle => over ? TextSlot.topCentre : TextSlot.bottomCentre,
    TextIconAlign.end => over ? TextSlot.topRight : TextSlot.bottomRight,
  };
}

/// _partsFromJson reads the parts, and moves an old document's pointed
/// animation onto the part it pointed at.
///
/// The arrival used to be able to name one part and happen to that instead of
/// to the whole paragraph. It is the part's own animation now -- so the rest
/// of the sentence can have an arrival too, and the part can land at its own
/// moment -- and a document saved before that would otherwise open with the
/// animation apparently applied to everything.
List<TextPart> _partsFromJson(Map<String, dynamic> json) {
  var parts = [
    if (json["parts"] case List raw)
      for (var p in raw)
        if (p is Map<String, dynamic>) TextPart.fromJson(p),
  ];

  var animation = json["animation"];
  if (animation is! Map<String, dynamic>) return parts;
  var at = jsonInt(animation["part"], -1);
  if (at < 0 || at >= parts.length) return parts;
  var preset = TextAnimationPreset.fromName(animation["preset"] as String?);
  if (preset == TextAnimationPreset.none) return parts;

  return [
    for (var (i, part) in parts.indexed)
      if (i != at)
        part
      else
        part.copyWith(
            animation: part.animation.copyWith(
                preset: preset,
                gap: jsonDouble(animation["gap"], 0.35),
                scale: jsonDouble(animation["scale"], 0),
                ease: ChartEase.fromName(animation["ease"] as String?))),
  ];
}
