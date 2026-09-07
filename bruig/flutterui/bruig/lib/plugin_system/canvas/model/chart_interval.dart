import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_interval.dart is how often a chart takes a reading from a series that
// runs on time.
//
// Thinning a series evenly -- keep one point in thirty -- gives a readable
// chart and a meaningless axis: the labels land wherever the arithmetic put
// them, so a ten-year chart is read against "Mar 17, Nov 19, Jul 22". What
// somebody actually wants is one point a year, on a date they choose, so the
// axis says 2017, 2018, 2019 and each reading is comparable with the one
// before it.
//
// This is the choosing, not the drawing. It answers "which of these rows",
// and everything about how the result looks is the chart's own business.

/// IntervalUnit is how far apart the readings are.
enum IntervalUnit {
  none("Every point"),
  day("Daily"),
  week("Weekly"),
  month("Monthly"),
  quarter("Quarterly"),
  year("Yearly");

  final String label;
  const IntervalUnit(this.label);

  static IntervalUnit fromName(String? name) =>
      values.firstWhere((u) => u.name == name, orElse: () => none);

  /// days is roughly how long one is, which is only used to decide whether a
  /// row is near enough to a mark to stand for it. Roughly is the right word
  /// and the right precision: months are not all the same length and it does
  /// not matter here.
  double get days => switch (this) {
        none => 0,
        day => 1,
        week => 7,
        month => 30.44,
        quarter => 91.31,
        year => 365.25,
      };

  /// hasMonth and hasDay are which parts of the anchor mean anything. A
  /// monthly reading has a day of the month and no month; a weekly one has a
  /// day of the week and neither.
  bool get hasMonth => this == year;
  bool get hasDay => this == month || this == quarter || this == year;
  bool get hasWeekday => this == week;
}

/// ChartInterval is the choosing: how often, and measured from when.
///
/// The anchor is the part that is easy to leave out and is the whole point of
/// the feature. "One a year" starting from whenever the data happens to begin
/// is a chart whose readings are a year apart and land on no date in
/// particular; "one a year on 7 February" is a set of readings that can be
/// compared, and is what somebody charting a season, a financial year or an
/// anniversary is asking for.
class ChartInterval {
  final IntervalUnit unit;

  /// every is how many units between readings -- 2 with [unit] year is one
  /// reading every other year.
  final int every;

  /// month and day are the anchor: the date within the year the readings are
  /// measured from. Ignored where the unit has no such thing.
  final int month;
  final int day;

  /// weekday is the anchor for a weekly reading, 1 for Monday.
  final int weekday;

  const ChartInterval({
    this.unit = IntervalUnit.none,
    this.every = 1,
    this.month = 1,
    this.day = 1,
    this.weekday = DateTime.monday,
  });

  bool get on => unit != IntervalUnit.none;

  ChartInterval copyWith({
    IntervalUnit? unit,
    int? every,
    int? month,
    int? day,
    int? weekday,
  }) =>
      ChartInterval(
        unit: unit ?? this.unit,
        every: every ?? this.every,
        month: month ?? this.month,
        day: day ?? this.day,
        weekday: weekday ?? this.weekday,
      );

  /// marks is every reading date between [first] and [last] inclusive.
  ///
  /// Walked from an anchor rather than from the first datum, so the dates are
  /// the ones asked for: 7 February of each year, whatever day the series
  /// happens to start on. The walk begins at or before [first] so that a
  /// series starting a fortnight after the anchor still has a reading near
  /// its beginning.
  List<DateTime> marks(DateTime first, DateTime last) {
    if (!on || last.isBefore(first)) return const [];
    var step = every < 1 ? 1 : every;
    var at = _anchorFor(first);
    // Back one step if the anchor has already passed the start, so the first
    // mark is not inside the series.
    while (at.isAfter(first)) {
      at = _step(at, -step);
    }

    var out = <DateTime>[];
    // A cap rather than a while(true): a daily interval over twenty years is
    // seven thousand marks, and a chart is a few inches wide.
    for (var i = 0; i < 4000; i++) {
      if (at.isAfter(last)) break;
      out.add(at);
      at = _step(at, step);
    }
    return out;
  }

  /// _anchorFor is the reading date in [when]'s own year or month.
  DateTime _anchorFor(DateTime when) {
    switch (unit) {
      case IntervalUnit.none:
        return when;
      case IntervalUnit.day:
        return DateTime(when.year, when.month, when.day);
      case IntervalUnit.week:
        // The most recent [weekday] at or before the date.
        var back = (when.weekday - weekday) % 7;
        var at = DateTime(when.year, when.month, when.day);
        return at.subtract(Duration(days: back));
      case IntervalUnit.month:
        return DateTime(
            when.year, when.month, _clampDay(when.year, when.month));
      case IntervalUnit.quarter:
        // The quarter's own first month, so the readings sit on the quarter
        // boundaries rather than three months from wherever the data starts.
        var month = ((when.month - 1) ~/ 3) * 3 + 1;
        return DateTime(when.year, month, _clampDay(when.year, month));
      case IntervalUnit.year:
        return DateTime(when.year, month, _clampDay(when.year, month));
    }
  }

  /// _step moves a mark on by [by] units, keeping the anchor's day.
  ///
  /// Through the year and month numbers rather than by adding days, because a
  /// month is not a fixed number of them and a year is not either -- adding
  /// 365 days repeatedly walks the anniversary backwards through the calendar
  /// one day every four years.
  DateTime _step(DateTime at, int by) {
    switch (unit) {
      case IntervalUnit.none:
        return at;
      case IntervalUnit.day:
        return at.add(Duration(days: by));
      case IntervalUnit.week:
        return at.add(Duration(days: by * 7));
      case IntervalUnit.month:
      case IntervalUnit.quarter:
        var months = by * (unit == IntervalUnit.quarter ? 3 : 1);
        var total = at.year * 12 + (at.month - 1) + months;
        var year = total ~/ 12;
        var month = total % 12 + 1;
        return DateTime(year, month, _clampDay(year, month));
      case IntervalUnit.year:
        return DateTime(
            at.year + by, at.month, _clampDay(at.year + by, at.month));
    }
  }

  /// _clampDay keeps the anchor inside the month it lands in: the 31st of
  /// February is the 28th, or the 29th, and never the 3rd of March.
  int _clampDay(int year, int month) {
    var wanted = day < 1 ? 1 : day;
    var last = DateTime(year, month + 1, 0).day;
    return wanted > last ? last : wanted;
  }

  Map<String, dynamic> toJson() => {
        "unit": unit.name,
        if (every != 1) "every": every,
        if (month != 1) "month": month,
        if (day != 1) "day": day,
        if (weekday != DateTime.monday) "weekday": weekday,
      };

  factory ChartInterval.fromJson(Map<String, dynamic> json) => ChartInterval(
        unit: IntervalUnit.fromName(json["unit"] as String?),
        every: jsonInt(json["every"], 1).clamp(1, 99),
        month: jsonInt(json["month"], 1).clamp(1, 12),
        day: jsonInt(json["day"], 1).clamp(1, 31),
        weekday: jsonInt(json["weekday"], DateTime.monday).clamp(1, 7),
      );
}

/// pickAtIntervals is which rows stand for the readings.
///
/// For each mark, the row nearest it -- and none where the nearest row is
/// more than half an interval away, because a chart that draws a point for a
/// year it has no data for is a chart telling a lie about the gap. The same
/// row is never used twice: a series that stops half way through has fewer
/// readings, not the same reading over and over.
List<int> pickAtIntervals(List<DateTime?> when, ChartInterval interval) {
  if (!interval.on) return [for (var i = 0; i < when.length; i++) i];

  DateTime? first, last;
  for (var at in when) {
    if (at == null) continue;
    if (first == null || at.isBefore(first)) first = at;
    if (last == null || at.isAfter(last)) last = at;
  }
  if (first == null || last == null) {
    return [for (var i = 0; i < when.length; i++) i];
  }

  var reach = Duration(
      milliseconds: (interval.unit.days *
              (interval.every < 1 ? 1 : interval.every) *
              Duration.millisecondsPerDay ~/
              2)
          .toInt());

  var out = <int>[];
  var taken = <int>{};
  for (var mark in interval.marks(first, last)) {
    int? best;
    Duration? nearest;
    for (var i = 0; i < when.length; i++) {
      var at = when[i];
      if (at == null || taken.contains(i)) continue;
      var gap = at.difference(mark).abs();
      if (gap > reach) continue;
      if (nearest == null || gap < nearest) {
        nearest = gap;
        best = i;
      }
    }
    if (best == null) continue;
    taken.add(best);
    out.add(best);
  }
  out.sort();
  return out;
}
