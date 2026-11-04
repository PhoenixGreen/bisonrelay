import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';

// chart_interval.dart is how often a chart takes a reading from a series that
// runs on time: one a year on a chosen date, say, rather than one point in
// thirty, so the axis lands on meaningful dates. It chooses rows only; the
// chart does the drawing.

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

  /// days is roughly how long one is, used only to decide whether a row is
  /// near enough to a mark to stand for it.
  double get days => switch (this) {
        none => 0,
        day => 1,
        week => 7,
        month => 30.44,
        quarter => 91.31,
        year => 365.25,
      };

  /// hasMonth, hasDay and hasWeekday are which parts of the anchor mean
  /// anything for this unit.
  bool get hasMonth => this == year;
  bool get hasDay => this == month || this == quarter || this == year;
  bool get hasWeekday => this == week;
}

/// IntervalPick is what a reading is made of: one of the rows in the period,
/// or all of them combined. It is asked rather than guessed: adding up daily
/// transactions makes sense, adding up block times does not, and the numbers
/// cannot tell the two apart.
enum IntervalPick {
  nearest("The reading on that date"),
  total("Added up"),
  mean("Averaged"),
  high("The highest"),
  low("The lowest");

  final String label;
  const IntervalPick(this.label);

  /// combines is whether a reading is made of the whole period
  /// ([groupAtIntervals]) rather than one row in it ([pickAtIntervals]).
  bool get combines => this != nearest;

  static IntervalPick fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => nearest);

  /// of combines the values of one period into the one number drawn for it.
  double of(List<double> values) {
    if (values.isEmpty) return 0;
    switch (this) {
      case IntervalPick.nearest:
        return values.first;
      case IntervalPick.total:
        return values.reduce((a, b) => a + b);
      case IntervalPick.mean:
        return values.reduce((a, b) => a + b) / values.length;
      case IntervalPick.high:
        return values.reduce(math.max);
      case IntervalPick.low:
        return values.reduce(math.min);
    }
  }
}

/// IntervalGroup is one reading's worth of rows: the date it is filed under,
/// and everything that falls in the period beginning there.
class IntervalGroup {
  final DateTime at;
  final List<int> rows;
  const IntervalGroup(this.at, this.rows);
}

/// ChartInterval is how often readings are taken, and the anchor date they
/// are measured from ("one a year on 7 February"), whatever date the data
/// begins on.
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

  /// how is what each reading is made of. See [IntervalPick].
  final IntervalPick how;

  const ChartInterval({
    this.unit = IntervalUnit.none,
    this.every = 1,
    this.month = 1,
    this.day = 1,
    this.weekday = DateTime.monday,
    this.how = IntervalPick.nearest,
  });

  bool get on => unit != IntervalUnit.none;

  ChartInterval copyWith({
    IntervalUnit? unit,
    int? every,
    int? month,
    int? day,
    int? weekday,
    IntervalPick? how,
  }) =>
      ChartInterval(
        unit: unit ?? this.unit,
        every: every ?? this.every,
        month: month ?? this.month,
        day: day ?? this.day,
        weekday: weekday ?? this.weekday,
        how: how ?? this.how,
      );

  /// marks is every reading date from the anchor at or before [first] up to
  /// [last], so a series starting a fortnight after the anchor still has a
  /// reading near its beginning.
  List<DateTime> marks(DateTime first, DateTime last) {
    if (!on || last.isBefore(first)) return const [];
    var step = every < 1 ? 1 : every;
    var at = _anchorFor(first);
    while (at.isAfter(first)) {
      at = _step(at, -step);
    }

    var out = <DateTime>[];
    // Capped: more marks than this cannot be drawn apart anyway.
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

  /// next is the mark after [at], which is where one period ends and the
  /// following one begins.
  DateTime next(DateTime at) => _step(at, every < 1 ? 1 : every);

  /// _step moves a mark on by [by] units, keeping the anchor's day. Months and
  /// years step through the calendar numbers, not by adding days, so the
  /// anniversary does not drift.
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
        if (how != IntervalPick.nearest) "how": how.name,
      };

  factory ChartInterval.fromJson(Map<String, dynamic> json) => ChartInterval(
        unit: IntervalUnit.fromName(jsonStr(json["unit"])),
        every: jsonInt(json["every"], 1).clamp(1, 99),
        month: jsonInt(json["month"], 1).clamp(1, 12),
        day: jsonInt(json["day"], 1).clamp(1, 31),
        weekday: jsonInt(json["weekday"], DateTime.monday).clamp(1, 7),
        how: IntervalPick.fromName(jsonStr(json["how"])),
      );
}

/// groupAtIntervals is which rows *make up* each reading: a period runs from
/// its mark up to the next. Deliberately unlike [pickAtIntervals], which takes
/// the nearest row from either side.
///
/// Empty periods are left out rather than drawn as zero, since zero would
/// claim a value where there is no data.
List<IntervalGroup> groupAtIntervals(
    List<DateTime?> when, ChartInterval interval) {
  if (!interval.on) return const [];

  DateTime? first, last;
  for (var at in when) {
    if (at == null) continue;
    if (first == null || at.isBefore(first)) first = at;
    if (last == null || at.isAfter(last)) last = at;
  }
  if (first == null || last == null) return const [];

  var out = <IntervalGroup>[];
  for (var mark in interval.marks(first, last)) {
    var ends = interval.next(mark);
    var rows = <int>[];
    for (var i = 0; i < when.length; i++) {
      var at = when[i];
      if (at == null) continue;
      if (at.isBefore(mark) || !at.isBefore(ends)) continue;
      rows.add(i);
    }
    if (rows.isNotEmpty) out.add(IntervalGroup(mark, rows));
  }
  return out;
}

/// pickAtIntervals is which rows stand for the readings: for each mark, the
/// nearest unused row, and none where that is more than half an interval
/// away, so a gap in the data stays a gap.
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
