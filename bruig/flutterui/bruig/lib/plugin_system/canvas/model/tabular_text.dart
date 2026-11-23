// tabular_text.dart splits a pasted table into rows of cells, for the chart
// and table quick-entry boxes. One separator is chosen for the whole paste,
// so a stray double space cannot split one row differently. A spreadsheet
// header row starts with an empty corner cell, so lines are trimmed at the
// start only when the separator is spaces, or every column would shift.

enum _TableSeparator {
  tab,
  comma,

  /// spaces is a run of two or more, so "Week 1" stays one cell.
  spaces,
}

/// _separatorFor sniffs [text]: tabs (spreadsheet), then commas (CSV), then
/// runs of spaces (lined up by hand).
_TableSeparator _separatorFor(String text) {
  if (text.contains("\t")) return _TableSeparator.tab;
  if (text.contains(",")) return _TableSeparator.comma;
  return _TableSeparator.spaces;
}

final RegExp _spaceRun = RegExp(r"\s{2,}");

/// splitTable turns pasted text into rows of trimmed cells. Blank lines are
/// dropped, since a paste often ends with a newline.
List<List<String>> splitTable(String text) {
  var separator = _separatorFor(text);
  var rows = <List<String>>[];

  for (var raw in text.split("\n")) {
    if (raw.trim().isEmpty) continue;

    // Trailing whitespace always goes; leading only for spaces (see the
    // file header).
    var line = raw.replaceAll("\r", "").trimRight();
    if (separator == _TableSeparator.spaces) line = line.trimLeft();

    var cells = switch (separator) {
      _TableSeparator.tab => line.split("\t"),
      _TableSeparator.comma => _splitQuoted(line),
      _TableSeparator.spaces => line.split(_spaceRun),
    };
    rows.add([for (var cell in cells) cell.trim()]);
  }

  return rows;
}

/// _splitQuoted splits a comma-separated line, honouring double quotes.
/// Only commas need quoting: a comma inside a cell is ordinary.
List<String> _splitQuoted(String line) {
  var cells = <String>[];
  var cell = StringBuffer();
  var quoted = false;

  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (c == '"') {
      // A doubled quote in a quoted cell is one quote, as spreadsheets
      // write it.
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

/// joinTable writes rows as comma-separated text, quoting where needed.
/// Commas, not tabs: a tab cannot be typed in a text field.
String joinTable(List<List<String>> rows) =>
    rows.map((row) => row.map(_quoted).join(",")).join("\n");

String _quoted(String cell) {
  if (!cell.contains(",") && !cell.contains('"') && cell.trim() == cell) {
    return cell;
  }
  return '"${cell.replaceAll('"', '""')}"';
}

/// cellNumber reads a cell as a number, or null. Table sorting and charts
/// both use it, so they agree. Allows a leading plus, thousands separators
/// and a percent sign ("1,240", "+3%").
double? cellNumber(String cell) {
  var text = cell.trim().replaceAll(",", "").replaceAll("%", "");
  if (text.startsWith("+")) text = text.substring(1);
  return text.isEmpty ? null : double.tryParse(text);
}
