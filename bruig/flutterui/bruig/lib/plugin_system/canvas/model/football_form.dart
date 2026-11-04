import 'package:bruig/plugin_system/canvas/model/data_source.dart';

// football_form.dart works out each club's recent results from the fixtures.
//
// football-data.org's standings "form" field is null on the free plan, but
// the matches resource (free) lists every finished game. A form guide is
// those grouped by club in date order, most recent last. It costs one more
// request out of the ten a minute allowed.
//
// Everything here is pure; the fetching is the caller's (see
// storage/canvas_data.dart).

/// FootballForm is every club's recent results, by every name the club is
/// known by.
///
/// Several keys per club: a table's column may hold the short name, the full
/// name or the three-letter abbreviation.
typedef FootballForm = Map<String, String>;

/// _key is a club's name as looked up, ignoring case and outer spaces.
String _key(String name) => name.trim().toLowerCase();

/// footballForms reads the matches resource into a form guide per club.
///
/// [count] is how many games a guide holds; footballFormFromResults passes
/// the form column's room.
///
/// Matches with no score are ignored whatever their status says: a list of
/// finished games can still carry a postponed one.
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

      // Every name this club goes by (see FootballForm).
      for (var field in ["name", "shortName", "tla"]) {
        var name = "${valueAtPath(match, "$side.$field") ?? ""}";
        if (name.isNotEmpty) (names[id] ??= {}).add(_key(name));
      }
    }
  }

  var out = <String, String>{};
  for (var entry in results.entries) {
    // By date: the matches resource is not promised in any order.
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
/// The column filled is whichever is mapped to "form". Rows are found by the
/// source's match column (the club's name), falling back to any column that
/// looks like a name. A club with no finished games keeps what was there.
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

  // Which column names the club: the source's match column first.
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

    // Only where the response sent no form: a plan that includes the field
    // is believed.
    if (RegExp("[A-Za-z]").hasMatch(out[r][target])) continue;

    var form = forms[_key(out[r][by])];
    // Laid out by the mapping's own code, so it matches a sent guide.
    if (form != null) {
      out[r][target] = spreadValue(form, source.columns[target]);
    }
  }
  return out;
}

/// footballFormFromResults fills the form column from the fixtures, fetched
/// with [get] from the standings address with the resource swapped (so it
/// follows the table's competition).
///
/// A failure leaves the rows as they were: the rest of the table is still
/// correct.
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

  // As many games as the column has room for.
  var slots = 6;
  for (var column in source.columns) {
    if (column.path == "form" && column.spread > 0) slots = column.spread;
  }
  return fillFootballForm(rows, source, footballForms(results, count: slots));
}
