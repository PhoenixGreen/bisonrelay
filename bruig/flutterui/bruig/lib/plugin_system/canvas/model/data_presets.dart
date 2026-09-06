import 'package:bruig/plugin_system/canvas/model/data_source.dart';

// data_presets.dart is the recipes that fill a DataSource in.
//
// A general mapping from JSON to rows is the right machinery and the wrong
// starting point: nobody opens a design tool wanting to write "standings.0.
// table" in a text field. A preset is the same mapping, already written, for a
// source somebody is likely to want -- so the ordinary path is choosing a
// league from a list, and the paths underneath stay editable for everything
// else.

/// DataPreset is one named recipe.
class DataPreset {
  final String id;
  final String label;

  /// note says what the reader has to do for themselves, which for every one
  /// of these is "get a key".
  final String note;

  /// choices are the interchangeable part of the address -- which competition,
  /// which season -- as a code and a name.
  final List<(String, String)> choices;
  final String choiceLabel;

  final String Function(String choice) address;
  final String rowsPath;
  final List<SourceColumn> columns;

  const DataPreset({
    required this.id,
    required this.label,
    required this.note,
    required this.choices,
    required this.choiceLabel,
    required this.address,
    required this.rowsPath,
    required this.columns,
  });

  /// applyTo is [source] with this recipe written into it.
  DataSource applyTo(DataSource source, String choice) => source.copyWith(
        kind: DataKind.url,
        where: address(choice),
        rowsPath: rowsPath,
        columns: columns,
        preset: id,
      );
}

/// footballDataColumns is the league table everybody recognises.
///
/// The order is the one every published table uses, and the first column is
/// deliberately the position: it is what the table's own sort pins in place,
/// and having it here means a refreshed table already reads 1, 2, 3 without
/// anybody sorting anything.
const List<SourceColumn> footballDataColumns = [
  SourceColumn(header: "", path: "position"),
  SourceColumn(header: "", path: "team.crest", picture: true),
  SourceColumn(header: "Team", path: "team.shortName"),
  SourceColumn(header: "Played", path: "playedGames"),
  SourceColumn(header: "Won", path: "won"),
  SourceColumn(header: "Drawn", path: "draw"),
  SourceColumn(header: "Lost", path: "lost"),
  SourceColumn(header: "For", path: "goalsFor"),
  SourceColumn(header: "Against", path: "goalsAgainst"),
  SourceColumn(header: "GD", path: "goalDifference"),
  SourceColumn(header: "Points", path: "points"),
];

/// footballData is football-data.org's standings.
///
/// Recommended over the alternatives for one reason above the others: its
/// standings response is already a league table. Every column below is a field
/// on the record rather than something to be counted up or joined from a
/// second call, so the mapping is a list of names and the refresh is one
/// request. The free tier covers the competitions most people want a table of,
/// including both English divisions, and rate-limits at ten requests a minute
/// -- which for a thing a person presses is no limit at all.
final DataPreset footballData = DataPreset(
  id: "football-data.org",
  label: "Football league table (football-data.org)",
  note: "Needs a free key from football-data.org, which arrives by email. "
      "The key is kept on this machine and never saved into the canvas, so a "
      "canvas you send carries the table and not your key.",
  choiceLabel: "Competition",
  // The free tier's competitions. Codes rather than ids, because a code is
  // readable in the address bar when something is not working.
  choices: const [
    ("PL", "Premier League"),
    ("ELC", "Championship"),
    ("BL1", "Bundesliga"),
    ("SA", "Serie A"),
    ("PD", "La Liga"),
    ("FL1", "Ligue 1"),
    ("DED", "Eredivisie"),
    ("PPL", "Primeira Liga"),
    ("BSA", "Brasileirão"),
    ("CL", "Champions League"),
    ("EC", "European Championship"),
    ("WC", "World Cup"),
  ],
  address: (code) =>
      "https://api.football-data.org/v4/competitions/$code/standings",
  // The response holds a list of standings -- the whole table, then home and
  // away for some competitions -- and the first is the one anybody means.
  rowsPath: "standings.0.table",
  columns: footballDataColumns,
);

/// dataPresets is every recipe there is.
final List<DataPreset> dataPresets = [footballData];

DataPreset? presetById(String id) {
  for (var preset in dataPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
