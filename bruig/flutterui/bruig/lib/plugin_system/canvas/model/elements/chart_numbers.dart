import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_numbers.dart is how a number is written on a chart.
//
// One place, because a chart writes the same numbers in three: up the value
// axis, on the bars themselves, and in a legend that carries values. A chart
// whose axis said 1,500,000 and whose bar said 1.5M would be a chart that has
// changed its mind half way across.

/// NumberStyle is the shape a number is written in.
enum NumberStyle {
  /// automatic is what a chart did before any of this existed, and is still
  /// the default: whole numbers as they are, big ones shortened, and a
  /// fraction given a decimal place or two.
  ///
  /// It is right nearly always and needs no thought, which is why it stays
  /// the default -- and it is wrong exactly when somebody has an opinion,
  /// which is what the rest of these are for.
  automatic("Automatic", "1000000, 12.5"),

  /// compact shortens every number by its own size: a thousand is 1.0K and a
  /// trillion is 1.0T, on the same axis.
  ///
  /// The fixed styles below scale everything by one amount, which is right
  /// when the numbers are of one size and wrong the moment they are not: a
  /// chart in millions writes a billion as 1000.0M and a thousand as 0.0M.
  /// This picks the unit per number, so an axis that climbs through four
  /// orders of magnitude is readable the whole way up -- which is what a log
  /// axis is usually for, and what somebody asking for K, M, B, T means.
  compact("Shortened", "1.2K, 3.4M, 5.6B"),
  plain("In full", "1,000,000"),
  thousands("Thousands", "1,000K"),
  millions("Millions", "1.0M"),
  billions("Billions", "0.0B");

  final String label;

  /// example is what a million looks like in this style, shown beside the
  /// name: the styles are much easier to tell apart by their answers than by
  /// their names.
  final String example;

  const NumberStyle(this.label, this.example);

  static NumberStyle fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => automatic);

  /// by is what a number is divided by before it is written. Meaningless for
  /// [compact], which picks per number -- see compactUnit.
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

  const ChartNumbers({
    this.style = NumberStyle.automatic,
    this.decimals = 1,
    this.separators = true,
  });

  ChartNumbers copyWith(
          {NumberStyle? style, int? decimals, bool? separators}) =>
      ChartNumbers(
        style: style ?? this.style,
        decimals: decimals ?? this.decimals,
        separators: separators ?? this.separators,
      );

  /// format writes [v] out.
  String format(double v) {
    if (!v.isFinite) return "";
    if (style == NumberStyle.automatic) return automaticNumber(v);

    var (by, suffix) = style == NumberStyle.compact
        ? compactUnit(v)
        : (style.by, style.suffix);
    var scaled = v / by;
    var places = decimals.clamp(0, 6);
    var text = scaled.toStringAsFixed(places);
    // toStringAsFixed(0) rounds to a whole number and leaves no point, which
    // is what zero decimals means; everything else keeps what it was given,
    // trailing noughts included. "1.50M" asked for two places and two places
    // is what it says.
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
      };

  factory ChartNumbers.fromJson(Map<String, dynamic> json) => ChartNumbers(
        style: NumberStyle.fromName(json["style"] as String?),
        decimals: jsonInt(json["decimals"], 1).clamp(0, 6),
        separators: !jsonBool(json["plain"], false),
      );
}

/// automaticNumber writes a number without being told how.
///
/// Whole numbers as they are, big ones shortened so an axis is not four
/// numbers wide, and a fraction given a place or two. This is what every
/// chart did before the styles above existed and is what they all still do
/// until somebody says otherwise -- which is why it is a function rather than
/// a branch inside one: it is the answer, not a case.
/// compactUnit is what to divide [v] by and what letter to put after it: the
/// largest unit it reaches.
///
/// Quadrillion is the last one. Past that the units stop being ones anybody
/// reads at a glance -- a quintillion written Qi is a puzzle, not a label --
/// and a number that large on a canvas is a number that wants its own words.
(double, String) compactUnit(double v) {
  var size = v.abs();
  if (size >= 1e15) return (1e15, "Q");
  if (size >= 1e12) return (1e12, "T");
  if (size >= 1e9) return (1e9, "B");
  if (size >= 1e6) return (1e6, "M");
  if (size >= 1e3) return (1e3, "K");
  return (1, "");
}

String automaticNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    var n = v.round();
    if (n.abs() >= 1000000) return "${(n / 1000000).toStringAsFixed(1)}M";
    if (n.abs() >= 10000) return "${(n / 1000).toStringAsFixed(0)}k";
    return "$n";
  }
  return v.toStringAsFixed(v.abs() < 1 ? 2 : 1);
}
