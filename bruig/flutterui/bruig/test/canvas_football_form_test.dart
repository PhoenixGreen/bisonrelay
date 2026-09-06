import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/football_form.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_football_form_test.dart is about a column the free plan does not
// include being worked out from one that it does.
//
// football-data.org sends "form" on a standings row and it is null unless the
// subscription covers trend data. The results are free, so the guide is those
// grouped by club in date order. What is checked here is that a match means
// the same thing to both clubs in it, that the order is by date rather than by
// however the fixtures arrived, and that nothing about a failure costs the
// table the rest of its numbers.

void main() {
  Map<String, dynamic> match({
    required String date,
    required int home,
    required int away,
    required String winner,
    String homeName = "Hull City",
    String awayName = "Arsenal",
  }) =>
      {
        "utcDate": date,
        "status": "FINISHED",
        "homeTeam": {
          "id": home,
          "shortName": homeName,
          "tla": homeName.substring(0, 3)
        },
        "awayTeam": {
          "id": away,
          "shortName": awayName,
          "tla": awayName.substring(0, 3)
        },
        "score": {"winner": winner},
      };

  test("a win for one club is a loss for the other", () {
    var forms = footballForms({
      "matches": [
        match(date: "2026-08-01", home: 1, away: 2, winner: "HOME_TEAM"),
      ],
    });
    expect(forms["hull city"], "W");
    expect(forms["arsenal"], "L");
    expect(forms["1"], "W", reason: "and is findable by the club's id");
  });

  test("a draw is a draw for both", () {
    var forms = footballForms({
      "matches": [match(date: "2026-08-01", home: 1, away: 2, winner: "DRAW")],
    });
    expect(forms["hull city"], "D");
    expect(forms["arsenal"], "D");
  });

  test("an away win is read from the other side", () {
    var forms = footballForms({
      "matches": [
        match(date: "2026-08-01", home: 1, away: 2, winner: "AWAY_TEAM"),
      ],
    });
    expect(forms["hull city"], "L");
    expect(forms["arsenal"], "W");
  });

  test("the guide is in date order, whatever order the fixtures arrive in", () {
    // The matches resource is not promised in any order, and a guide that is
    // not in time order is not a guide.
    var forms = footballForms({
      "matches": [
        match(date: "2026-08-15", home: 1, away: 2, winner: "HOME_TEAM"),
        match(date: "2026-08-01", home: 1, away: 2, winner: "DRAW"),
        // Away at Arsenal, so the names swap with the ids -- a club is not
        // the side of the pitch it is standing on.
        match(
            date: "2026-08-08",
            home: 2,
            away: 1,
            winner: "HOME_TEAM",
            homeName: "Arsenal",
            awayName: "Hull City"),
      ],
    });
    expect(forms["hull city"], "D,L,W",
        reason: "oldest first, as the API's "
            "own field is");
  });

  test("only the last few are kept", () {
    var forms = footballForms({
      "matches": [
        for (var day = 1; day <= 8; day++)
          match(
              date: "2026-08-0$day",
              home: 1,
              away: 2,
              winner: day == 8 ? "DRAW" : "HOME_TEAM"),
      ],
    }, count: 5);
    expect(forms["hull city"], "W,W,W,W,D");
  });

  test("a game with no result is not a result", () {
    // A fixture list asked for finished games can still carry a postponed one.
    var forms = footballForms({
      "matches": [
        match(date: "2026-08-01", home: 1, away: 2, winner: "HOME_TEAM"),
        {
          "utcDate": "2026-08-08",
          "homeTeam": {"id": 1, "shortName": "Hull City"},
          "awayTeam": {"id": 2, "shortName": "Arsenal"},
          "score": {"winner": null},
        },
      ],
    });
    expect(forms["hull city"], "W");
  });

  test("nothing at all is nothing, not a crash", () {
    expect(footballForms(null), isEmpty);
    expect(footballForms({"matches": "not a list"}), isEmpty);
    expect(footballForms({"matches": []}), isEmpty);
  });

  group("writing it into the table", () {
    var source = const DataSource(
      kind: DataKind.url,
      where: "https://api.football-data.org/v4/competitions/PL/standings",
      matchColumn: 0,
      preset: "football-data.org",
      columns: [
        SourceColumn(header: "Team", path: "team.shortName"),
        SourceColumn(header: "Points", path: "points"),
        SourceColumn(header: "Form", path: "form", spread: 5, divider: "|"),
      ],
    );

    List<List<String>> table() => [
          ["Team", "Points", "Form"],
          ["Hull City", "6", "— — — — | —"],
          ["Arsenal", "4", "— — — — | —"],
        ];

    test("it lands in the column mapped to form, laid out", () {
      var filled = fillFootballForm(
          table(), source, {"hull city": "W,D,W", "arsenal": "L"});
      expect(filled[1][2], "— — W D | W");
      expect(filled[2][2], "— — — — | L");
      expect(filled[1][1], "6", reason: "and nothing else is touched");
    });

    test("a club with no games keeps its dashes", () {
      var filled = fillFootballForm(table(), source, {"hull city": "W"});
      expect(filled[2][2], "— — — — | —");
    });

    test("a table with no form column is left alone", () {
      var plain = source.copyWith(columns: [
        for (var c in source.columns)
          if (c.path != "form") c,
      ]);
      var rows = table();
      expect(identical(fillFootballForm(rows, plain, {"hull city": "W"}), rows),
          isTrue);
    });
  });

  group("the second request", () {
    test("it asks the fixtures for the same competition", () async {
      var asked = <String>[];
      var source = footballData.applyTo(const DataSource(), "ELC");
      await footballFormFromResults([
        ["Team"],
        ["Hull City"],
      ], source, (url) async {
        asked.add(url);
        return null;
      });

      expect(
          asked.single,
          "https://api.football-data.org/v4/competitions/ELC/matches"
          "?status=FINISHED",
          reason: "it follows whatever competition the table is set to");
    });

    test("a failure costs the form guide and nothing else", () async {
      // A form guide is one column of a table that is otherwise correct.
      var rows = [
        ["Team", "Points"],
        ["Hull City", "6"],
      ];
      var source = footballData.applyTo(const DataSource(), "PL");
      expect(
          await footballFormFromResults(rows, source, (_) async => null), rows);
    });

    test("a table that does not want a form guide does not ask", () async {
      var asked = 0;
      var source = footballData.applyTo(const DataSource(), "PL").copyWith(
        columns: const [SourceColumn(header: "Team", path: "team.shortName")],
      );
      await footballFormFromResults([
        ["Team"],
      ], source, (_) async {
        asked++;
        return null;
      });
      expect(asked, 0, reason: "a request nobody needed is a request not made");
    });
  });

  group("a plan that does send the field", () {
    // The derived guide is a stand-in for a plan that sends nothing, not a
    // correction to one that does. What the source said is what the source
    // should be believed about.
    var source = const DataSource(
      kind: DataKind.url,
      where: "https://api.football-data.org/v4/competitions/PL/standings",
      matchColumn: 0,
      columns: [
        SourceColumn(header: "Team", path: "team.shortName"),
        SourceColumn(
            header: "Custom form", path: "form", spread: 6, divider: "|"),
      ],
    );

    test("a guide that arrived is left alone", () {
      var rows = [
        ["Team", "Custom form"],
        ["Hull City", "W L D W W | L"],
      ];
      expect(
          fillFootballForm(rows, source, {"hull city": "D,D,D,D,D,D"}), rows);
    });

    test("a row of dashes is filled in", () {
      var filled = fillFootballForm(
          [
            ["Team", "Custom form"],
            ["Hull City", "— — — — — | —"],
          ],
          source,
          {"hull city": "W,L"});
      expect(filled[1][1], "— — — — W | L");
    });
  });
}
