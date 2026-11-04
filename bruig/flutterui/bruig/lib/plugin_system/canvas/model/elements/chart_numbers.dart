import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_numbers.dart is how a number is written on a chart. The value axis,
// the bars and the legend all use it, so they always agree.

/// NumberStyle is the shape a number is written in.
enum NumberStyle {
  /// automatic is the default; see [automaticNumber].
  automatic("Automatic", "1000000, 12.5"),

  /// compact picks the unit per number (see [compactUnit]): a thousand is
  /// 1.0K and a trillion 1.0T on the same axis. The fixed styles below scale
  /// everything by one amount, so they suit numbers of one size only.
  compact("Shortened", "1.2K, 3.4M, 5.6B"),
  plain("In full", "1,000,000"),
  thousands("Thousands", "1,000K"),
  millions("Millions", "1.0M"),
  billions("Billions", "0.0B");

  final String label;

  /// example is a sample shown beside the name, which tells the styles apart
  /// better than their names do.
  final String example;

  const NumberStyle(this.label, this.example);

  static NumberStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => automatic);

  /// by is what a number is divided by before it is written. Meaningless for
  /// [compact], which picks per number.
  double get by => switch (this) {
        automatic || compact || plain => 1,
        thousands => 1e3,
        millions => 1e6,
        billions => 1e9,
      };

  /// suffix is the letter after it.
  String get suffix => switch (this) {
        automatic || compact || plain => "",
        thousands => "K",
        millions => "M",
        billions => "B",
      };
}

/// ChartNumbers is the style, the decimal places, and whether the thousands
/// are grouped.
///
/// [decimals] applies to every style but [NumberStyle.automatic], which picks
/// its own. Zero means no decimal point at all rather than a nought after it:
/// "1M", not "1.M" and not "1.0M".
class ChartNumbers {
  final NumberStyle style;
  final int decimals;

  /// separators groups the thousands: 1,000,000 rather than 1000000. On the
  /// scaled styles too, since a chart in thousands can still reach 1,000K.
  final bool separators;

  /// before and after are written either side of every number: a currency
  /// sign or a unit ("\$300", "11.11 DCR", "40%"). Kept out of the data so the
  /// figures stay numbers.
  final String before;
  final String after;

  const ChartNumbers({
    this.style = NumberStyle.automatic,
    this.decimals = 1,
    this.separators = true,
    this.before = "",
    this.after = "",
  });

  ChartNumbers copyWith(
          {NumberStyle? style,
          int? decimals,
          bool? separators,
          String? before,
          String? after}) =>
      ChartNumbers(
        style: style ?? this.style,
        decimals: decimals ?? this.decimals,
        separators: separators ?? this.separators,
        before: before ?? this.before,
        after: after ?? this.after,
      );

  /// format writes [v] out, with whatever goes either side of it. A minus
  /// sign goes before the currency's: -\$5, not \$-5.
  String format(double v) {
    var figures = _figures(v);
    if (figures.isEmpty || (before.isEmpty && after.isEmpty)) return figures;
    var negative = figures.startsWith("-");
    if (negative) figures = figures.substring(1);
    return "${negative ? "-" : ""}$before$figures$after";
  }

  String _figures(double v) {
    if (!v.isFinite) return "";
    if (style == NumberStyle.automatic) return automaticNumber(v);

    var (by, suffix) = style == NumberStyle.compact
        ? compactUnit(v)
        : (style.by, style.suffix);
    var scaled = v / by;
    var places = decimals.clamp(0, 6);
    var text = scaled.toStringAsFixed(places);
    // Trailing noughts are kept: two places gives "1.50M".
    return "${separators ? _grouped(text) : text}$suffix";
  }

  /// _grouped puts the separators into the whole part and leaves the rest
  /// alone -- the decimals are not grouped, and neither is the minus sign.
  static String _grouped(String text) {
    var negative = text.startsWith("-");
    var body = negative ? text.substring(1) : text;
    var point = body.indexOf(".");
    var whole = point < 0 ? body : body.substring(0, point);
    var rest = point < 0 ? "" : body.substring(point);

    var out = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) out.write(",");
      out.write(whole[i]);
    }
    return "${negative ? "-" : ""}$out$rest";
  }

  Map<String, dynamic> toJson() => {
        if (style != NumberStyle.automatic) "style": style.name,
        if (decimals != 1) "decimals": decimals,
        if (!separators) "plain": true,
        if (before.isNotEmpty) "pre": before,
        if (after.isNotEmpty) "post": after,
      };

  factory ChartNumbers.fromJson(Map<String, dynamic> json) => ChartNumbers(
        style: NumberStyle.fromName(jsonStr(json["style"])),
        decimals: jsonInt(json["decimals"], 1).clamp(0, 6),
        separators: !jsonBool(json["plain"], false),
        before: jsonString(json["pre"], ""),
        after: jsonString(json["post"], ""),
      );
}

/// compactUnit is what to divide [v] by and what letter to put after it: the
/// largest unit it reaches, up to Q (quadrillion).
(double, String) compactUnit(double v) {
  var size = v.abs();
  if (size >= 1e15) return (1e15, "Q");
  if (size >= 1e12) return (1e12, "T");
  if (size >= 1e9) return (1e9, "B");
  if (size >= 1e6) return (1e6, "M");
  if (size >= 1e3) return (1e3, "K");
  return (1, "");
}

/// automaticNumber writes [v] in the [NumberStyle.automatic] style: whole
/// numbers as they are, from ten thousand shortened (12k, 1.5M), and a
/// fraction given one or two places.
String automaticNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    var n = v.round();
    if (n.abs() >= 1000000) return "${(n / 1000000).toStringAsFixed(1)}M";
    if (n.abs() >= 10000) return "${(n / 1000).toStringAsFixed(0)}k";
    return "$n";
  }
  return v.toStringAsFixed(v.abs() < 1 ? 2 : 1);
}
