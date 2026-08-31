import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
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
        if (ruleStyle != ColumnRuleStyle.none) "ruleColor": colorToJson(ruleColor),
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

  const TextOnCurve({
    required this.elementId,
    this.offset = 0,
    this.away = false,
    this.spacing = 0,
  });

  TextOnCurve copyWith({
    String? elementId,
    double? offset,
    bool? away,
    double? spacing,
  }) =>
      TextOnCurve(
        elementId: elementId ?? this.elementId,
        offset: offset ?? this.offset,
        away: away ?? this.away,
        spacing: spacing ?? this.spacing,
      );

  Map<String, dynamic> toJson() => {
        "id": elementId,
        if (offset != 0) "offset": offset,
        if (away) "away": true,
        if (spacing != 0) "spacing": spacing,
      };

  factory TextOnCurve.fromJson(Map<String, dynamic> json) => TextOnCurve(
        elementId: jsonString(json["id"], ""),
        offset: jsonDouble(json["offset"], 0),
        away: jsonBool(json["away"], false),
        spacing: jsonDouble(json["spacing"], 0),
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
    this.curve,
  });

  @override
  ElementKind get kind => ElementKind.text;

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
      curve: curve);

  TextElement copyWith({
    String? text,
    TextSpec? textSpec,
    BoxSpec? box,
    bool? autoSize,
    TextColumns? columns,
    TextOnCurve? curve,
    bool clearCurve = false,
  }) =>
      TextElement(base,
          text: text ?? this.text,
          textSpec: textSpec ?? this.textSpec,
          box: box ?? this.box,
          autoSize: autoSize ?? this.autoSize,
          columns: columns ?? this.columns,
          curve: clearCurve ? null : (curve ?? this.curve));

  @override
  Map<String, dynamic> props() => {
        "text": text,
        "textSpec": textSpec.toJson(),
        "box": box.toJson(),
        if (autoSize) "autoSize": true,
        if (!columns.isSingle) "columns": columns.toJson(),
        if (curve != null) "curve": curve!.toJson(),
      };

  factory TextElement.fromJson(Map<String, dynamic> json, ElementBase b) =>
      TextElement(b,
          text: jsonString(json["text"], "Text"),
          textSpec: jsonSpec(json["textSpec"], TextSpec.fromJson,
              const TextSpec()),
          box: jsonSpec(json["box"], BoxSpec.fromJson, const BoxSpec()),
          autoSize: jsonBool(json["autoSize"], false),
          columns: jsonSpec(json["columns"], TextColumns.fromJson,
              const TextColumns()),
          curve: json["curve"] is Map<String, dynamic>
              ? TextOnCurve.fromJson(json["curve"] as Map<String, dynamic>)
              : null);
}
