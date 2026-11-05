import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
  /// the right of it: one block of text beside a picture, not lines broken
  /// in two.
  left("Left of it"),
  right("Right of it");

  final String label;
  const WrapSide(this.label);

  static WrapSide fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => both);
}

/// TextWrap is words flowing around whatever overlaps their box.
///
/// Off by default: with it on the words are set line by line against the
/// elements around them rather than laid out once, which is slower.
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
        side: WrapSide.fromName(jsonStr(json["side"])),
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
class TextColumns {
  /// count is how many columns the text flows across. One costs nothing
  /// extra to draw.
  final int count;

  /// gap is the space between two columns, in design units. The rule, if there
  /// is one, is drawn down the middle of it.
  final double gap;

  final ColumnRuleStyle ruleStyle;
  final double ruleWidth;
  final Color ruleColor;

  /// noBlankStart drops a blank line that would have begun a column (or a
  /// box in a chain), so its text does not sit lower than its neighbour's.
  /// On by default; the setting exists to turn it off.
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

  /// says is whether this has anything to record: not the single column
  /// every text element starts with.
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
        count: jsonInt(json["count"], 1).clamp(1, 12),
        gap: jsonDouble(json["gap"], 24).clamp(0.0, 400.0),
        ruleStyle: ColumnRuleStyle.fromName(jsonString(json["ruleStyle"], "")),
        ruleWidth: jsonDouble(json["ruleWidth"], 1).clamp(0.0, 40.0),
        ruleColor: colorFromJson(json["ruleColor"], const Color(0x66FFFFFF)),
      );
}

/// TextOnCurve puts a paragraph along another element's line. The line is
/// named rather than copied, so moving or reshaping it carries the text.
class TextOnCurve {
  /// elementId is a line or a path element. Anything else, or an element
  /// since deleted, is ignored and the text falls back to its box.
  final String elementId;

  /// offset slides the text along the curve, as a fraction of its length.
  final double offset;

  /// away flips the text to the other side of the line, for a label that
  /// should sit under it rather than on it.
  final bool away;

  /// spacing is extra room between letters as they are placed, on top of the
  /// spec's own letter spacing, for tight bends where glyphs would overlap.
  final double spacing;

  /// hideHost leaves the line itself undrawn. Hiding the line element
  /// instead would not do: a hidden element is skipped everywhere, including
  /// here, so the text would go with it.
  final bool hideHost;

  /// mask hides whatever has slid off the ends of the line. The words follow
  /// the line past its ends; with this the line is a window, so a slide
  /// reads as words arriving from behind something.
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

/// TextElement is a paragraph in a box. How the letters look is in
/// [textSpec] and the box around them in [box], so a new type control
/// belongs in TextSpec rather than here.
class TextElement extends CanvasElement {
  final String text;
  final TextSpec textSpec;
  final BoxSpec box;

  /// autoSize grows the type to fill the box rather than wrapping it: a
  /// headline grows with its box, where body copy reflows.
  final bool autoSize;

  /// columns is how the paragraph is broken up. See [TextColumns].
  final TextColumns columns;

  /// animation is how the words arrive. See [TextAnimation].
  final TextAnimation animation;

  /// slot is where the element's own words sit, or null for the box.
  ///
  /// Null, the usual case, fills the box: the words wrap, take columns and
  /// flow on. Given a slot they behave like a piece -- as wide as they come
  /// out, held to that corner -- so they stack with the pieces in it.
  /// Ignored on a line, in columns or in a chain, which arrange the whole box.
  final TextSlot? slot;

  /// items are the extra pieces of writing in this element's box, each in a
  /// slot of its own, for a card rather than a paragraph. See [TextItem].
  final List<TextItem> items;

  /// parts are the runs of this text that are drawn differently -- a word in
  /// another colour, a phrase in bold, its own arrival. See [TextPart].
  final List<TextPart> parts;

  /// highlight and underline are the element's own marks: a band behind all
  /// of the words, a line under all of them. The same two a part carries;
  /// see [drawnParts].
  final PartHighlight? highlight;
  final PartUnderline? underline;

  /// flowTo is the text element the words that do not fit run on into, or ""
  /// for none. One way only: a ring of boxes has no first box, and flowFor
  /// refuses to make one.
  final String flowTo;

  /// document is the Writing library document these words came from, if any.
  /// The words are copied into [text], so the canvas draws without the
  /// library and an export never waits on disk. See TextDocumentRef.
  final TextDocumentRef document;

  /// documentParts are the runs the document's own markdown asked for -- a
  /// heading, a bold phrase, a link. Kept apart from [parts] because they are
  /// rewritten every time the document is read, and the reader's must survive.
  final List<TextPart> documentParts;

  /// wrap flows the words around whatever overlaps the box. See TextWrap.
  final TextWrap wrap;

  /// style is the name of the document's text style this text is set in,
  /// or empty for its own -- see CanvasDocument.textStyles. Changing the
  /// style restyles every text that names it.
  final String style;

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

  @override
  ElementKind get kind => ElementKind.text;

  /// assetIds is every stored picture this element refers to: the pictures
  /// among its pieces, and one showing through its letters. A picture left
  /// out is swept away as unused; see CanvasStorage.liveAssetIds.
  @override
  Set<String> get assetIds => {
        for (var item in items) ...{
          if (item.icon?.assetId.isNotEmpty ?? false) item.icon!.assetId,
          ...item.box.assetIds,
          ...?item.icon?.box.assetIds,
        },
        if (textSpec.fill.assetId.isNotEmpty) textSpec.fill.assetId,
        ...box.assetIds,
      };

  /// drawnParts are the parts the painter works from: the element's own
  /// marks as a part covering every word, so they share the parts' drawing
  /// and timing, and then the parts themselves. The marks come first, so a
  /// part's own highlight is drawn over them and a part still decides the
  /// colour and weight of its words.
  List<TextPart> get drawnParts => drawnPartsWith(documentParts);

  /// drawnPartsWith is drawnParts with the document's runs given rather than
  /// taken from the element -- which is what a box in a chain needs, since
  /// the runs it draws are the head's, moved. See TextFlow.parts.
  List<TextPart> drawnPartsWith(List<TextPart> fromDocument) => [
        if (highlight != null || underline != null)
          TextPart(highlight: highlight, underline: underline),
        // The reader's own parts last, so they win where they overlap: see
        // partAt, where the later part decides.
        ...fromDocument,
        ...parts,
      ];

  /// displayText is what actually goes on the canvas -- the typed string with
  /// the case transform applied. See TextCase on why the transform is not
  /// baked into [text].
  String get displayText => textSpec.textCase.apply(text);

  @override
  bool get scalesInside => true;

  /// scaledBy is the words, the pieces and the box at [by] times the size.
  /// Not a curve's offset, which is a fraction of the line, and not the
  /// column count. See CanvasElement.scaledBy.
  @override
  CanvasElement scaledBy(double by) => copyWith(
        textSpec: textSpec.scaledBy(by),
        box: box.scaledBy(by),
        items: [for (var item in items) item.scaledBy(by)],
        columns: columns.copyWith(gap: columns.gap * by),
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
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
        // Written whenever it says anything, not only for several columns:
        // No blank first line applies to a one-column box in a chain too.
        if (columns.says) "columns": columns.toJson(),
        if (animation.any) "animation": animation.toJson(),
        if (slot != null) "slot": slot!.name,
        if (items.isNotEmpty) "items": [for (var i in items) i.toJson()],
        if (parts.isNotEmpty) "parts": [for (var p in parts) p.toJson()],
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (flowTo.isNotEmpty) "flowTo": flowTo,
        if (wrap.toJson().isNotEmpty) "wrap": wrap.toJson(),
        if (style.isNotEmpty) "style": style,
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
          slot: json[
                  "slot"] is String
              ? TextSlot.fromName(jsonStr(json["slot"]))
              : null,
          items: [
            if (json["items"] case List raw)
              for (var i in raw)
                if (i is Map<String, dynamic>) TextItem.fromJson(i),
          ],
          parts: [
            if (json["parts"] case List raw)
              for (var p in raw)
                if (p is Map<String, dynamic>) TextPart.fromJson(p),
          ],
          highlight:
              json["highlight"] is Map<String,
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
          style: jsonString(json["style"], ""),
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
