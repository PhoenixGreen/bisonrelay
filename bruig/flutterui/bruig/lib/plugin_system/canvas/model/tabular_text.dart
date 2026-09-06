// tabular_text.dart splits a pasted table into rows of cells.
//
// Shared by the chart's quick-entry box and the table element's, because they
// are the same box: paste a table, get the thing. Two implementations would
// mean a paste that worked in one and not the other, which is worse than
// either being wrong.
//
// The separator is chosen once for the whole paste rather than per line, and
// that is the correction that matters here. Deciding per cell -- splitting on
// "a tab, or a comma, or a run of spaces", whichever is found -- means a
// header row like "<tab>Sales<tab>Costs" and a data row like "Q1<tab>10" are
// treated differently the moment one of them contains a stray double space.
//
// The leading empty cell is the other one. A table copied out of a spreadsheet
// starts its header row with an empty cell -- the corner above the row labels
// -- and trimming the line before splitting silently eats it, which shifts
// every series one column left and loses the last one entirely. So the line is
// only trimmed at the end, and only trimmed at the start when the separator is
// whitespace and leading spaces cannot mean anything else.

/// TableSeparator is what divides the columns of one paste.
enum TableSeparator {
  tab,
  comma,

  /// spaces is a run of two or more, so a single space inside a cell -- "Week
  /// 1", "Manchester United" -- is part of the cell rather than a division.
  spaces,
}

/// separatorFor sniffs which one [text] uses.
///
/// Tabs first because a spreadsheet paste is the commonest source and always
/// uses them; then commas, for a CSV; then runs of spaces, for a table
/// somebody has typed or lined up by hand. Asking the reader which it is would
/// be a dialog in front of the one feature that exists to be fast.
TableSeparator separatorFor(String text) {
  if (text.contains("\t")) return TableSeparator.tab;
  if (text.contains(",")) return TableSeparator.comma;
  return TableSeparator.spaces;
}

final RegExp _spaceRun = RegExp(r"\s{2,}");

/// splitTable turns pasted text into rows of trimmed cells.
///
/// Blank lines are dropped rather than becoming empty rows: a paste routinely
/// arrives with a trailing newline, and an empty final category on every chart
/// would be a permanent bug wearing the disguise of the reader's own data.
List<List<String>> splitTable(String text) {
  var separator = separatorFor(text);
  var rows = <List<String>>[];

  for (var raw in text.split("\n")) {
    if (raw.trim().isEmpty) continue;

    // Trailing whitespace always goes: it is never a column. Leading
    // whitespace goes only when it could not be a separator -- with tabs or
    // commas dividing the columns, a line starting with one has a genuine
    // empty first cell.
    var line = raw.replaceAll("\r", "").trimRight();
    if (separator == TableSeparator.spaces) line = line.trimLeft();

    var cells = switch (separator) {
      TableSeparator.tab => line.split("\t"),
      TableSeparator.comma => _splitQuoted(line),
      TableSeparator.spaces => line.split(_spaceRun),
    };
    rows.add([for (var cell in cells) cell.trim()]);
  }

  return rows;
}

/// _splitQuoted splits a comma-separated line, honouring double quotes.
///
/// Only for commas. A tab cannot appear inside a cell anybody typed and a run
/// of spaces is already ambiguous, but a comma inside a cell is ordinary --
/// "Brighton & Hove Albion, 2nd" -- and without quoting there is no way to
/// write one at all.
List<String> _splitQuoted(String line) {
  var cells = <String>[];
  var cell = StringBuffer();
  var quoted = false;

  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (c == '"') {
      // A doubled quote inside a quoted cell is one quote, which is what every
      // spreadsheet writes and so what every spreadsheet paste contains.
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (c == "," && !quoted) {
      cells.add(cell.toString());
      cell.clear();
      continue;
    }
    cell.write(c);
  }
  cells.add(cell.toString());
  return cells;
}

/// joinTable writes rows back out as comma-separated text, quoting the cells
/// that need it.
///
/// Commas rather than tabs, which is what this used to write. A tab in a text
/// field is a wide invisible gap that cannot be typed without leaving the
/// field, so a table written out with tabs could be read and not edited --
/// and the one thing this box is for is editing.
String joinTable(List<List<String>> rows) =>
    rows.map((row) => row.map(_quoted).join(",")).join("\n");

String _quoted(String cell) {
  if (!cell.contains(",") && !cell.contains('"') && cell.trim() == cell) {
    return cell;
  }
  return '"${cell.replaceAll('"', '""')}"';
}
