import 'package:bruig/writing_tools/engine/analysis.dart';
import 'package:golib_plugin/definitions.dart';

// dates.dart is the only family here that does arithmetic rather than
// counting, and the only one certain about something a careful reader would
// still miss: nobody proofreads a date against a calendar. "We ship Monday,
// 10 August" is a sentence you can read twenty times without noticing the
// 10th is a Tuesday.
//
// The month and weekday names are the trap. "May", "March" and "August" are
// ordinary words, so a pattern looking for a month alone would fire on "we
// march on" constantly. Every pattern below therefore requires a month beside
// a day number, and the two weekday checks require a weekday beside both --
// which is a shape that ordinary prose does not accidentally form.

/// dateWeekdayMismatchId fires when a written weekday is not the weekday that
/// date fell on, with the year written out. `$1` is the weekday as typed, `$2`
/// the weekday it actually was.
const dateWeekdayMismatchId = "date-weekday-mismatch";

/// dateWeekdayMismatchThisYearId is the same check where no year was written
/// and the nearest one is assumed. A separate id because the two are not
/// equally certain and must not be equally loud, and because either should be
/// switchable off on its own.
const dateWeekdayMismatchThisYearId = "date-weekday-mismatch-this-year";

/// impossibleDateId fires on a day number the month never has. `$1` is the
/// date as typed, `$2` the number of days that month has.
const impossibleDateId = "impossible-date";

final Map<String, AnalysisRunner> dateChecks = {
  dateWeekdayMismatchId: (context, check) =>
      _weekdayAgreement(context, check, wantYear: true),
  dateWeekdayMismatchThisYearId: (context, check) =>
      _weekdayAgreement(context, check, wantYear: false),
  impossibleDateId: _impossibleDates,
};

const _monthNumbers = {
  "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3,
  "april": 4, "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7,
  "august": 8, "aug": 8, "september": 9, "sept": 9, "sep": 9, "october": 10,
  "oct": 10, "november": 11, "nov": 11, "december": 12, "dec": 12,
};

const _weekdayNumbers = {
  "monday": 1, "mon": 1, "tuesday": 2, "tues": 2, "tue": 2, "wednesday": 3,
  "weds": 3, "wed": 3, "thursday": 4, "thurs": 4, "thur": 4, "thu": 4,
  "friday": 5, "fri": 5, "saturday": 6, "sat": 6, "sunday": 7, "sun": 7,
};

/// _weekdayNames is indexed by DateTime.weekday, which counts Monday as 1.
const _weekdayNames = [
  "",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// _alternation joins names longest-first, so "september" is preferred to
/// "sep" and "tuesday" to "tue". A regex alternation takes the first branch
/// that matches rather than the longest, so the order is the whole of what
/// makes the abbreviations safe to include.
String _alternation(Iterable<String> names) {
  var sorted = names.toList()..sort((a, b) => b.length.compareTo(a.length));
  return sorted.join("|");
}

final _months = _alternation(_monthNumbers.keys);
final _weekdays = _alternation(_weekdayNumbers.keys);

/// _dayNumber is a day with an optional ordinal ending, refusing to match
/// part of a longer number: without the lookahead, "August 100" reads as the
/// 10th.
const _dayNumber = r"(\d{1,2})(?:st|nd|rd|th)?(?!\d)";

/// _optionalYear is four digits after a comma or a space.
const _optionalYear = r"(?:[,\s]+(\d{4})(?!\d))?";

/// The weekday separator allows a full stop so "Mon. 10 Aug." is read.
const _sep = r"[.,\s]+";

/// Weekday given: "Monday, 10 August 2026" and "Monday the 10th of August".
/// Groups: 1 weekday, 2 day, 3 month, 4 year.
final _weekdayDayFirst = RegExp(
    "\\b($_weekdays)\\b$_sep(?:the\\s+)?$_dayNumber\\s+(?:of\\s+)?($_months)\\b$_optionalYear",
    caseSensitive: false);

/// "Monday, August 10, 2026". Groups: 1 weekday, 2 month, 3 day, 4 year.
final _weekdayMonthFirst = RegExp(
    "\\b($_weekdays)\\b$_sep($_months)\\s+$_dayNumber$_optionalYear",
    caseSensitive: false);

/// The same two without a weekday, for the impossible-date check, which has
/// no use for one. Keeping them separate means the flagged range is the date
/// itself rather than the weekday in front of it.
/// Groups: 1 day, 2 month, 3 year.
final _bareDayFirst = RegExp(
    "\\b$_dayNumber\\s+(?:of\\s+)?($_months)\\b$_optionalYear",
    caseSensitive: false);

/// Groups: 1 month, 2 day, 3 year.
final _bareMonthFirst =
    RegExp("\\b($_months)\\s+$_dayNumber$_optionalYear", caseSensitive: false);

/// _nearestYear picks the year a date with no year written most likely means:
/// the one that puts it closest to today.
///
/// The current year is the obvious guess and it is wrong twice a year. Someone
/// writing "Monday, 4 January" in late December means the January a week away,
/// not the one eleven months behind them, and checking the weekday against the
/// wrong year produces a confident correction that is itself wrong. The same
/// happens in reverse in early January for a date in December.
///
/// Returns null when the day does not exist in any candidate year, which is
/// the impossible-date check's business rather than this one's.
int? _nearestYear(int month, int day, DateTime now) {
  int? best;
  Duration? closest;
  for (var year in [now.year - 1, now.year, now.year + 1]) {
    if (day < 1 || day > _daysInMonth(month, year)) continue;
    var gap = DateTime(year, month, day).difference(now).abs();
    if (closest == null || gap < closest) {
      closest = gap;
      best = year;
    }
  }
  return best;
}

bool _isLeapYear(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);

int _daysInMonth(int month, int year) {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return lengths[month - 1];
}

/// _weekdayAgreement flags a weekday that is not the one that date fell on.
///
/// [wantYear] splits the two declared checks. With the year written out the
/// answer is certain and the check is an error; without it the nearest year is
/// assumed, "Monday 10 August" may be a date in some other year, and the check
/// is a suggestion. Each match belongs to exactly one of the two, so running
/// both produces one finding rather than two.
void _weekdayAgreement(
  AnalysisContext context,
  AnalysisCheck check, {
  required bool wantYear,
}) {
  var text = context.text;
  void consider(
      RegExpMatch m, String? weekday, int? day, int? month, String? yearText) {
    if (weekday == null || day == null || month == null) return;
    if ((yearText != null) != wantYear) return;
    var year = yearText == null
        ? _nearestYear(month, day, context.now)
        : int.parse(yearText);
    if (year == null) return;
    // A date that does not exist has no weekday to disagree with, and saying
    // so is the impossible-date check's job rather than this one's. Only
    // reachable with a year written out; _nearestYear has already rejected
    // the rest.
    if (day < 1 || day > _daysInMonth(month, year)) return;

    var actual = DateTime(year, month, day).weekday;
    var written = _weekdayNumbers[weekday.toLowerCase()];
    if (written == null || written == actual) return;

    // The weekday sits at the start of the match, which is what lets its
    // range be taken without per-group offsets -- something Dart's Match does
    // not expose.
    context.report(check, m.start, m.start + weekday.length,
        subject: weekday,
        detail: _weekdayNames[actual],
        // The date is assumed to be the part that was looked up and the
        // weekday the part typed from memory, so the weekday is what gets
        // corrected. Stated in the explanation, because the other way round
        // is just as possible and only the writer knows.
        //
        // Capitalised whatever case was typed, unlike every other correction
        // in this module: a weekday is a proper noun, so "tuesday" wants
        // "Monday" and not "monday". Running it through matchCase would be a
        // no-op -- it only ever adds a capital -- and would read as though
        // the case were being carried over.
        suggestions: [_weekdayNames[actual]]);
  }

  for (var m in _weekdayDayFirst.allMatches(text)) {
    consider(m, m.group(1), int.tryParse(m.group(2) ?? ""),
        _monthNumbers[m.group(3)?.toLowerCase()], m.group(4));
  }
  for (var m in _weekdayMonthFirst.allMatches(text)) {
    consider(m, m.group(1), int.tryParse(m.group(3) ?? ""),
        _monthNumbers[m.group(2)?.toLowerCase()], m.group(4));
  }
}

/// _impossibleDates flags a day number the month never has.
void _impossibleDates(AnalysisContext context, AnalysisCheck check) {
  var text = context.text;
  var seen = <int>{};
  void consider(RegExpMatch m, int? day, int? month, String? yearText) {
    if (day == null || month == null) return;
    // 29 February is a real date every fourth year, so without a year written
    // out there is nothing to object to. 30 and 31 February are wrong
    // whatever the year, and still caught.
    if (yearText == null && month == 2 && day == 29) return;
    var year = yearText == null ? context.now.year : int.parse(yearText);
    var days = _daysInMonth(month, year);
    if (day >= 1 && day <= days) return;
    // The two patterns overlap on some text; the same slip is one finding.
    if (!seen.add(m.start)) return;
    context.report(check, m.start, m.end,
        subject: text.substring(m.start, m.end), detail: "$days");
  }

  for (var m in _bareDayFirst.allMatches(text)) {
    consider(m, int.tryParse(m.group(1) ?? ""),
        _monthNumbers[m.group(2)?.toLowerCase()], m.group(3));
  }
  for (var m in _bareMonthFirst.allMatches(text)) {
    consider(m, int.tryParse(m.group(2) ?? ""),
        _monthNumbers[m.group(1)?.toLowerCase()], m.group(3));
  }
}
