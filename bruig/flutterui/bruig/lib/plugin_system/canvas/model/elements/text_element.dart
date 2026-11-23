import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
        gap: jsonDouble(json["gap"], _defaults.gap).clamp(0, 400),
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
        gap: jsonDouble(json["gap"], _defaults.gap).clamp(0.0, 400.0),
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
        elementId: jsonString(json["id"], ""),
        offset: jsonDouble(json["offset"], _defaults.offset),
        away: jsonBool(json["away"], false),
        spacing: jsonDouble(json["spacing"], _defaults.spacing),
        hideHost: jsonBool(json["hideHost"], false),
        mask: jsonBool(json["mask"], false),
      );
}

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
  /// own (see CanvasDocument.textStyles); changing the style restyles all.
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

  /// scaledBy scales the words, pieces, box, marks and gaps by [by], but not
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
        if (wrap.toJson().isNotEmpty) "wrap": wrap.toJson(),
        if (style.isNotEmpty) "style": style,
        if (document.on) "document": document.toJson(),
        if (documentParts.isNotEmpty)
          "documentParts": [for (var p in documentParts) p.toJson()],
        if (curve != null) "curve": curve!.toJson(),
      };

  factory TextElement.fromJson(Map<String, dynamic> json,
          ElementBase b) =>
      TextElement(b,
          text: jsonString(json["text"], _defaults.text),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              _defaults.textSpec),
          box: jsonSpec(json["box"], BoxSpec.fromJson, _defaults.box),
          autoSize: jsonBool(json["autoSize"], false),
          animation:
              jsonSpec(json["animation"], TextAnimation.fromJson,
                  _defaults.animation),
          slot:
              json[
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
          flowTo: jsonString(json["flowTo"], _defaults.flowTo),
          style: jsonString(json["style"], _defaults.style),
          wrap:
              json["wrap"]
                      is Map<String, dynamic>
                  ? TextWrap.fromJson(json["wrap"] as Map<String, dynamic>)
                  : const TextWrap(),
          columns: jsonSpec(
              json["columns"], TextColumns.fromJson, _defaults.columns),
          curve: json["curve"] is Map<String, dynamic>
              ? TextOnCurve.fromJson(json["curve"] as Map<String, dynamic>)
              : null);
}
