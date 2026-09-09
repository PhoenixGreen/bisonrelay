import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

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

  const TextColumns({
    this.count = 1,
    this.gap = 24,
    this.ruleStyle = ColumnRuleStyle.none,
    this.ruleWidth = 1,
    this.ruleColor = const Color(0x66FFFFFF),
  });

  bool get isSingle => count <= 1;

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
  }) =>
      TextColumns(
        count: count ?? this.count,
        gap: gap ?? this.gap,
        ruleStyle: ruleStyle ?? this.ruleStyle,
        ruleWidth: ruleWidth ?? this.ruleWidth,
        ruleColor: ruleColor ?? this.ruleColor,
      );

  Map<String, dynamic> toJson() => {
        "count": count,
        "gap": gap,
        if (ruleStyle != ColumnRuleStyle.none) "ruleStyle": ruleStyle.name,
        if (ruleStyle != ColumnRuleStyle.none) "ruleWidth": ruleWidth,
        if (ruleStyle != ColumnRuleStyle.none)
          "ruleColor": colorToJson(ruleColor),
      };

  factory TextColumns.fromJson(Map<String, dynamic> json) => TextColumns(
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

  const TextOnCurve({
    required this.elementId,
    this.offset = 0,
    this.away = false,
    this.spacing = 0,
    this.hideHost = false,
  });

  TextOnCurve copyWith({
    String? elementId,
    double? offset,
    bool? away,
    double? spacing,
    bool? hideHost,
  }) =>
      TextOnCurve(
        elementId: elementId ?? this.elementId,
        offset: offset ?? this.offset,
        away: away ?? this.away,
        spacing: spacing ?? this.spacing,
        hideHost: hideHost ?? this.hideHost,
      );

  Map<String, dynamic> toJson() => {
        "id": elementId,
        if (offset != 0) "offset": offset,
        if (away) "away": true,
        if (spacing != 0) "spacing": spacing,
        if (hideHost) "hideHost": true,
      };

  factory TextOnCurve.fromJson(Map<String, dynamic> json) => TextOnCurve(
        elementId: jsonString(json["id"], ""),
        offset: jsonDouble(json["offset"], 0),
        away: jsonBool(json["away"], false),
        spacing: jsonDouble(json["spacing"], 0),
        hideHost: jsonBool(json["hideHost"], false),
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

  /// icon is a picture set beside, above or below the words. See TextIcon.
  final TextIcon icon;

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
    this.parts = const [],
    this.highlight,
    this.underline,
    this.icon = const TextIcon(),
    this.flowTo = "",
    this.document = const TextDocumentRef(),
    this.documentParts = const [],
    this.curve,
  });

  @override
  ElementKind get kind => ElementKind.text;

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
  List<TextPart> get drawnParts => [
        // The element's own marks, as a part covering every word.
        if (highlight != null || underline != null)
          TextPart(highlight: highlight, underline: underline),
        // Then what a document's markdown asked for, and then the reader's
        // own parts -- which are last so that they win where they overlap.
        // See partAt: the later part is the one that decides.
        ...documentParts,
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
      parts: parts,
      highlight: highlight,
      underline: underline,
      icon: icon,
      flowTo: flowTo,
      document: document,
      documentParts: documentParts,
      curve: curve);

  TextElement copyWith({
    String? text,
    TextSpec? textSpec,
    BoxSpec? box,
    bool? autoSize,
    TextColumns? columns,
    TextAnimation? animation,
    List<TextPart>? parts,
    PartHighlight? highlight,
    bool clearHighlight = false,
    PartUnderline? underline,
    bool clearUnderline = false,
    TextIcon? icon,
    String? flowTo,
    TextDocumentRef? document,
    List<TextPart>? documentParts,
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
          parts: parts ?? this.parts,
          highlight: clearHighlight ? null : (highlight ?? this.highlight),
          underline: clearUnderline ? null : (underline ?? this.underline),
          icon: icon ?? this.icon,
          flowTo: flowTo ?? this.flowTo,
          document: document ?? this.document,
          documentParts: documentParts ?? this.documentParts,
          curve: clearCurve ? null : (curve ?? this.curve));

  @override
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
        if (!columns.isSingle) "columns": columns.toJson(),
        if (animation.on || animation.closes) "animation": animation.toJson(),
        if (parts.isNotEmpty) "parts": [for (var p in parts) p.toJson()],
        if (highlight != null) "highlight": highlight!.toJson(),
        if (underline != null) "underline": underline!.toJson(),
        if (icon.on) "icon": icon.toJson(),
        if (flowTo.isNotEmpty) "flowTo": flowTo,
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
          icon:
              json["icon"] is Map<String,
                      dynamic>
                  ? TextIcon.fromJson(json["icon"] as Map<String, dynamic>)
                  : const TextIcon(),
          document:
              json["document"] is Map<String,
                      dynamic>
                  ? TextDocumentRef.fromJson(
                      json["document"] as Map<String, dynamic>)
                  : const TextDocumentRef(),
          documentParts: [
            if (json["documentParts"] case List raw)
              for (var p in raw)
                if (p is Map<String, dynamic>) TextPart.fromJson(p),
          ],
          flowTo: jsonString(json["flowTo"], ""),
          columns: jsonSpec(
              json["columns"], TextColumns.fromJson, const TextColumns()),
          curve: json["curve"] is Map<String, dynamic>
              ? TextOnCurve.fromJson(json["curve"] as Map<String, dynamic>)
              : null);
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
