// tabular_text.dart splits a pasted table into rows of cells, for both the
// chart's and the table element's quick-entry boxes.
//
// The separator is chosen once for the whole paste, not per line or cell, so
// a stray double space cannot make one row split differently from the rest.
//
// A spreadsheet header row starts with an empty corner cell; trimming the
// line before splitting would eat it and shift every column left. So lines
// are trimmed at the start only when the separator is spaces.

/// TableSeparator is what divides the columns of one paste.
enum TableSeparator {
  tab,
  comma,

  /// spaces is a run of two or more, so a single space ("Week 1") stays
  /// inside its cell.
  spaces,
}

/// separatorFor sniffs which one [text] uses: tabs (a spreadsheet paste),
/// then commas (CSV), then runs of spaces (lined up by hand).
TableSeparator separatorFor(String text) {
  if (text.contains("\t")) return TableSeparator.tab;
  if (text.contains(",")) return TableSeparator.comma;
  return TableSeparator.spaces;
}

final RegExp _spaceRun = RegExp(r"\s{2,}");

/// splitTable turns pasted text into rows of trimmed cells.
///
/// Blank lines are dropped rather than becoming empty rows, since a paste
/// often ends with a newline.
List<List<String>> splitTable(String text) {
  var separator = separatorFor(text);
  var rows = <List<String>>[];

  for (var raw in text.split("\n")) {
    if (raw.trim().isEmpty) continue;

    // Trailing whitespace always goes; leading only for the spaces
    // separator (see the top of the file).
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
/// Only commas need quoting: a comma inside a cell is ordinary.
List<String> _splitQuoted(String line) {
  var cells = <String>[];
  var cell = StringBuffer();
  var quoted = false;

  for (var i = 0; i < line.length; i++) {
    var c = line[i];
    if (c == '"') {
      // A doubled quote inside a quoted cell is one quote, as spreadsheets
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

/// joinTable writes rows back out as comma-separated text, quoting the cells
/// that need it.
///
/// Commas rather than tabs, because a tab cannot be typed in a text field
/// without leaving it.
String joinTable(List<List<String>> rows) =>
    rows.map((row) => row.map(_quoted).join(",")).join("\n");

String _quoted(String cell) {
  if (!cell.contains(",") && !cell.contains('"') && cell.trim() == cell) {
    return cell;
  }
  return '"${cell.replaceAll('"', '""')}"';
}

/// cellNumber reads a cell as a number, or null when it is not one.
///
/// The one reading both table sorting and charts use, so they agree.
/// Allows a leading plus, thousands separators and a percent sign ("1,240",
/// "+3%").
double? cellNumber(String cell) {
  var text = cell.trim().replaceAll(",", "").replaceAll("%", "");
  if (text.startsWith("+")) text = text.substring(1);
  return text.isEmpty ? null : double.tryParse(text);
}
