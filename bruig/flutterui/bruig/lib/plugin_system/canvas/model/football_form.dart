import 'package:bruig/plugin_system/canvas/model/data_source.dart';

// football_form.dart works out each club's recent results from the fixtures.
//
// football-data.org sends a "form" field on a standings row and it is null on
// the free plan -- their pricing lists trend and form data from the ML Pack
// tier up. Results, though, are free: the matches resource lists every
// finished game with who played and who won. A form guide is those grouped by
// club, in date order, most recent last, which is what this does.
//
// It is a second request rather than a cleverer first one, and that is the
// whole cost: one more call out of ten a minute, for a column the plan does
// not include. The alternative was a column of dashes and no way to know why.
//
// Everything here is pure. The fetching is the caller's -- see
// storage/canvas_data.dart -- so what a match means can be checked against a
// handful of maps rather than against a season.

/// FootballForm is every club's recent results, by every name the club is
/// known by.
///
/// Several keys per club on purpose: a table's own column might hold the short
/// name, the full name or the three-letter abbreviation depending on how it
/// was set up, and the guide has to be findable by whichever it is.
typedef FootballForm = Map<String, String>;

/// _key is how a club's name is looked up: case and spacing are not part of
/// the question.
String _key(String name) => name.trim().toLowerCase();

/// footballForms reads the matches resource into a form guide per club.
///
/// [count] is how many games a guide holds -- five, matching what the paid
/// field would have said, so the same column setting lays either out.
///
/// Matches with no result yet are ignored whatever their status says. A
/// fixture list asked for finished games can still carry a postponed one, and
/// a game with no score is not a result.
FootballForm footballForms(dynamic json, {int count = 5}) {
  var matches = valueAtPath(json, "matches");
  if (matches is! List) return const {};

  // Club id to the results it has, oldest first.
  var results = <String, List<(String, String)>>{};
  var names = <String, Set<String>>{};

  for (var match in matches) {
    if (match is! Map) continue;
    var winner = "${valueAtPath(match, "score.winner") ?? ""}";
    if (winner.isEmpty || winner == "null") continue;
    var date = "${valueAtPath(match, "utcDate") ?? ""}";

    for (var side in ["homeTeam", "awayTeam"]) {
      var id = "${valueAtPath(match, "$side.id") ?? ""}";
      if (id.isEmpty) continue;

      var outcome = winner == "DRAW"
          ? "D"
          : (winner == "HOME_TEAM") == (side == "homeTeam")
              ? "W"
              : "L";
      (results[id] ??= []).add((date, outcome));

      // Every name this club goes by, so the table can be matched on whichever
      // one it happens to hold.
      for (var field in ["name", "shortName", "tla"]) {
        var name = "${valueAtPath(match, "$side.$field") ?? ""}";
        if (name.isNotEmpty) (names[id] ??= {}).add(_key(name));
      }
    }
  }

  var out = <String, String>{};
  for (var entry in results.entries) {
    // By date rather than by the order they arrived: the matches resource is
    // not promised in any order, and a guide that is not in time order is not
    // a guide.
    var games = entry.value..sort((a, b) => a.$1.compareTo(b.$1));
    var recent =
        games.length > count ? games.sublist(games.length - count) : games;
    var form = [for (var (_, outcome) in recent) outcome].join(",");

    out[entry.key] = form;
    for (var name in names[entry.key] ?? const <String>{}) {
      out[name] = form;
    }
  }
  return out;
}

/// fillFootballForm writes the guide into the rows.
///
/// The column filled is whichever one is mapped to "form", so a table that has
/// been rearranged still gets it in the right place. Rows are found by the
/// column the source matches rows on -- the club's name -- falling back to any
/// column that looks like a name if none is set.
///
/// A club with no finished games keeps whatever was there, which for a source
/// that sent nothing is empty, which lays out as a row of dashes.
List<List<String>> fillFootballForm(
  List<List<String>> rows,
  DataSource source,
  FootballForm forms, {
  bool headerRow = true,
}) {
  if (forms.isEmpty || rows.length < 2) return rows;

  var target = -1;
  for (var i = 0; i < source.columns.length; i++) {
    if (source.columns[i].path == "form") target = i;
  }
  if (target < 0) return rows;

  // Which column names the club. The source's own answer first, since that is
  // the one the reader chose for keeping their badges in step.
  var by = source.matchColumn;
  if (by < 0) {
    for (var i = 0; i < source.columns.length; i++) {
      if (source.columns[i].path.startsWith("team.")) {
        by = i;
        break;
      }
    }
  }
  if (by < 0) return rows;

  var out = [
    for (var row in rows) [...row]
  ];
  for (var r = headerRow ? 1 : 0; r < out.length; r++) {
    if (by >= out[r].length || target >= out[r].length) continue;
    var form = forms[_key(out[r][by])];
    // Laid out by the same code the mapping uses, so a guide worked out here
    // and one that arrived in the response are the same shape.
    if (form != null) {
      out[r][target] = spreadValue(form, source.columns[target]);
    }
  }
  return out;
}

/// footballFormFromResults is the preset's second look: the form guide worked
/// out from the fixtures, because the plan that includes it as a field costs
/// money and the results are free.
///
/// The address is the standings one with the resource swapped, so it follows
/// whatever competition the table is set to without being told which.
///
/// Anything that goes wrong here leaves the rows exactly as they were. A form
/// guide is one column of a table that is otherwise correct, and a refresh
/// that threw away a league table because the fixtures did not answer would
/// be a poor trade.
Future<List<List<String>>> footballFormFromResults(
  List<List<String>> rows,
  DataSource source,
  Future<dynamic> Function(String url) get,
) async {
  var wanted = source.columns.any((c) => c.path == "form");
  if (!wanted || !source.where.contains("/standings")) return rows;

  var results = await get(
      source.where.replaceFirst("/standings", "/matches?status=FINISHED"));
  if (results == null) return rows;

  return fillFootballForm(rows, source, footballForms(results));
}
