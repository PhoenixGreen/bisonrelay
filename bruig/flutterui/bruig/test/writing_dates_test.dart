import 'package:bruig/writing_tools/engine/analysis.dart';
import 'package:bruig/writing_tools/writing_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';

// writing_dates_test.dart covers the checks that read a calendar: whether a
// weekday matches its date, whether the date exists at all, and whether one
// message mixes two kinds of apostrophe.
//
// The clock is injected throughout. A check that assumes the current year
// would otherwise pass in 2026 and fail in 2027, and a test that only holds
// this year is worse than no test.

// 10 August 2026 is a Monday; 11 August 2026 is a Tuesday.
final _now = DateTime(2026, 8, 7);

AnalysisCheck _check(String id, String message, {String severity = ""}) =>
    AnalysisCheck(id, 0, message, "Consistency", "why", severity, const []);

List<WritingIssue> _run(String text, AnalysisCheck check) =>
    runAnalysisChecks(text, [check], isIgnoredCheck: (_) => false, now: _now);

void main() {
  group("weekday against a written year", () {
    var check =
        _check("date-weekday-mismatch", r"That date was a $2, not a $1");

    test("a wrong weekday is flagged and corrected", () {
      var issue = _run("We shipped on Tuesday, 10 August 2026.", check).single;
      expect(issue.text, "Tuesday");
      expect(issue.message, "That date was a Monday, not a Tuesday");
      expect(issue.suggestions, ["Monday"]);
    });

    test("the right weekday is left alone", () {
      expect(_run("We shipped on Monday, 10 August 2026.", check), isEmpty);
    });

    test("month-first order is read too", () {
      var issue = _run("Due Tuesday, August 10, 2026.", check).single;
      expect(issue.suggestions, ["Monday"]);
    });

    test('"the 10th of August" is read too', () {
      var issue = _run("on Tuesday the 10th of August 2026", check).single;
      expect(issue.suggestions, ["Monday"]);
    });

    test("abbreviations are read", () {
      expect(_run("Tue, 10 Aug 2026", check), hasLength(1));
      expect(_run("Mon, 10 Aug 2026", check), isEmpty);
    });

    // Unlike the grammar-rule corrections, which carry the case of what
    // they replace: a weekday is a proper noun and takes its capital
    // whatever case it was typed in.
    test("a lowercase weekday is corrected to a capitalised one", () {
      expect(_run("see you tuesday, 10 august 2026", check).single.suggestions,
          ["Monday"]);
    });

    // Without a year this check has nothing certain to say, and the other
    // one takes it. Both firing would mark the same word twice.
    test("a date with no year belongs to the other check", () {
      expect(_run("We shipped on Tuesday, 10 August.", check), isEmpty);
    });

    // A date that does not exist has no weekday to disagree with.
    test("an impossible date is not given a weekday", () {
      expect(_run("Monday, 31 February 2026", check), isEmpty);
    });
  });

  group("weekday with the year assumed", () {
    var check = _check(
        "date-weekday-mismatch-this-year", r"This year that date is a $2",
        severity: "suggestion");

    test("the current year is assumed", () {
      var issue = _run("Let's meet Tuesday, 10 August.", check).single;
      expect(issue.message, "This year that date is a Monday");
      expect(issue.kind, WritingIssueKind.phrasing,
          reason: "an assumed year cannot support a red underline");
    });

    // The current year is the obvious guess and it is wrong twice a year.
    // 4 January 2027 is a Monday; 4 January 2026 was a Sunday.
    test("a date just over the new year is read as the nearer one", () {
      var lateDecember = DateTime(2026, 12, 28);
      var issues = runAnalysisChecks("let's meet Monday, 4 January", [check],
          isIgnoredCheck: (_) => false, now: lateDecember);
      expect(issues, isEmpty,
          reason: "in late December, 4 January means the one a week away, "
              "which is a Monday -- not the one eleven months behind");
    });

    // The same in reverse: a December date read in early January belongs to
    // the year just ended. 28 December 2026 is a Monday; 28 December 2027 is
    // a Tuesday.
    test("a date just before the new year is read as the nearer one", () {
      var earlyJanuary = DateTime(2027, 1, 4);
      var issues = runAnalysisChecks("we shipped Monday, 28 December", [check],
          isIgnoredCheck: (_) => false, now: earlyJanuary);
      expect(issues, isEmpty);
    });

    test("a written year belongs to the other check", () {
      expect(_run("Tuesday, 10 August 2026", check), isEmpty);
    });
  });

  group("impossible dates", () {
    var check = _check(
        "impossible-date", r'"$1" is not a date -- that month has $2 days');

    test("a day that month never has is flagged", () {
      var issue = _run("The deadline is 31 February.", check).single;
      expect(issue.text, "31 February");
      expect(issue.message,
          '"31 February" is not a date -- that month has 28 days');
    });

    test("31 in a 30-day month is flagged", () {
      expect(_run("due 31 April", check), hasLength(1));
      expect(_run("due 31 June", check), hasLength(1));
    });

    test("real dates are left alone", () {
      for (var text in [
        "30 April",
        "31 May",
        "29 February 2028",
        "1 January"
      ]) {
        expect(_run(text, check), isEmpty, reason: text);
      }
    });

    // 29 February exists every fourth year, so without a year written out
    // there is nothing to object to.
    test("29 February is only judged when the year is written", () {
      expect(_run("meet on 29 February", check), isEmpty);
      expect(_run("meet on 29 February 2026", check), hasLength(1));
      expect(_run("meet on 29 February 2028", check), isEmpty);
    });

    // The two patterns overlap and would otherwise report the slip twice.
    test("one slip is one finding", () {
      expect(_run("Monday, 31 February 2026 at noon", check), hasLength(1));
    });

    // The whole risk in this check: month names that are ordinary words.
    test("months used as ordinary words are not dates", () {
      for (var text in [
        "we march on the capital",
        "it may rain later",
        "an august institution",
        "I will march 20 miles",
      ]) {
        expect(_run(text, check), isEmpty, reason: text);
      }
    });

    // Without the lookahead on the day, "August 100" reads as the 10th.
    test("a longer number is not a day", () {
      expect(_run("we processed August 100 times", check), isEmpty);
    });
  });

  group("mixed apostrophes", () {
    var check = _check("apostrophe-inconsistency",
        r'Mixed apostrophes -- "$1" is the odd one out',
        severity: "suggestion");

    test("the minority apostrophe is flagged", () {
      var text = "I don’t think it’s right, but I can't say.";
      var issue = _run(text, check).single;
      expect(issue.text, "'");
      expect(issue.suggestions, ["’"]);
    });

    test("one kind used throughout is left alone", () {
      expect(_run("I don't think it's right and can't say.", check), isEmpty);
      expect(_run("I don’t think it’s right.", check), isEmpty);
    });

    // The whole reason this only looks between letters: a quoted message is
    // not an inconsistent one.
    test("quotation marks are not apostrophes", () {
      expect(_run("He said 'hello' and I said ‘hi’.", check), isEmpty);
      expect(_run("She said 'it’s fine' to me.", check), isEmpty);
    });
  });

  // All three date checks at once, over prose of the kind these actually run
  // against. Separately each is easy to keep honest; together they are the
  // only place a pattern that reads too much into an ordinary sentence shows
  // up, and month names are ordinary words.
  test("the date checks together on a real message", () {
    var checks = [
      _check("date-weekday-mismatch", r"$1/$2"),
      _check("date-weekday-mismatch-this-year", r"$1/$2",
          severity: "suggestion"),
      _check("impossible-date", r"$1"),
    ];
    var text = "Hi all -- we march on the release this week. It may slip, "
        "but the plan is still to ship on Tuesday, 10 August 2026. "
        "I have 31 things to finish first and about 12 hours to do them. "
        "The August figures are due later, and I may need 30 more minutes.";
    var issues = runAnalysisChecks(text, checks,
        isIgnoredCheck: (_) => false, now: _now);

    expect(issues, hasLength(1),
        reason: "only the wrong weekday is a finding: everything else here "
            "is a month name or a number doing an ordinary job");
    expect(issues.single.text, "Tuesday");
  });

  test("an empty message is not analysed", () {
    expect(_run("   ", _check("impossible-date", r"$1")), isEmpty);
  });
}
