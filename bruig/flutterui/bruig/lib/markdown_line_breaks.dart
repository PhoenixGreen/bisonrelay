// markdown_line_breaks.dart turns the line breaks somebody typed into line
// breaks every markdown reader will honour.
//
// Markdown joins consecutive lines into one paragraph: "one\ntwo" is the
// single line "one two", and a break has to be asked for with two trailing
// spaces or a backslash. That is the specification working as intended, and it
// is not what anyone typing into a post editor expects -- a break was pressed
// and no break appeared.
//
// The fix is applied to what is *sent* rather than to how it is drawn, and
// that choice is the whole design. A post is rendered by each reader's own
// client, so a renderer told to break on every newline shows the writer one
// layout and everybody on a stock client another. Two trailing spaces are in
// the text itself, so every conforming reader breaks in the same place, and
// brclient -- which has no markdown renderer at all and shows the source --
// displays them as nothing, which is the best available outcome there.
//
// Two spaces rather than a backslash for that last reason. Both parse
// identically in the renderer this app ships, but a backslash is a visible
// character to anyone reading the raw text, and a trailing space is not.

/// _fence opens or closes a fenced code block. Up to three leading spaces are
/// still a fence; four would be an indented code block.
final _fence = RegExp(r"^\s{0,3}(```|~~~)");

/// _blockStart matches a line that begins a block of its own -- a heading, a
/// quote, a list item, a fence, a table row, a thematic break.
///
/// A line before one of these is already at the end of its paragraph, so the
/// break happens with or without help and adding the spaces would be invisible
/// noise in somebody's post.
final _blockStart = RegExp(
    r"^\s{0,3}(#{1,6}\s|>|[-*+]\s|\d+[.)]\s|```|~~~|\||-{3,}\s*$|\*{3,}\s*$|_{3,}\s*$)");

/// _setextUnderline is the `===` or `---` that turns the line above it into a
/// heading. Adding a hard break to that line would be adding it to a heading.
final _setextUnderline = RegExp(r"^\s{0,3}(=+|-+)\s*$");

/// _embed is this app's own block syntax, which owns its whole line and is
/// matched elsewhere by a pattern that does not expect anything after it.
final _embed = RegExp(r"--embed\[");

/// hardenSoftLineBreaks gives every line that would otherwise be swallowed by
/// the line after it the two trailing spaces that make the break explicit.
///
/// Only where it changes the reading. A line already followed by a blank one
/// is a paragraph and is left alone; so is a line before a heading or a list,
/// which breaks anyway; so is anything inside a fenced code block, where the
/// text is not markdown and two spaces would be two characters of somebody's
/// program.
///
/// Idempotent: a line that already ends in a hard break -- two spaces or a
/// backslash -- is left exactly as it is, so running this over text that has
/// been through it once changes nothing.
String hardenSoftLineBreaks(String markdown) {
  if (!markdown.contains("\n")) return markdown;

  var lines = markdown.split("\n");
  var out = <String>[];
  var inFence = false;

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];

    if (_fence.hasMatch(line)) {
      inFence = !inFence;
      out.add(line);
      continue;
    }
    // The last line has nothing after it to be joined to.
    if (inFence || i == lines.length - 1) {
      out.add(line);
      continue;
    }

    var next = lines[i + 1];
    if (line.trim().isEmpty || next.trim().isEmpty) {
      out.add(line);
      continue;
    }
    if (line.endsWith("  ") || line.endsWith("\\")) {
      out.add(line);
      continue;
    }
    if (_embed.hasMatch(line) || _embed.hasMatch(next)) {
      out.add(line);
      continue;
    }
    if (_blockStart.hasMatch(next) || _setextUnderline.hasMatch(next)) {
      out.add(line);
      continue;
    }
    // An indented code block: four spaces or a tab, and its newlines are the
    // program's rather than the prose's.
    if (line.startsWith("    ") ||
        line.startsWith("\t") ||
        next.startsWith("    ") ||
        next.startsWith("\t")) {
      out.add(line);
      continue;
    }

    out.add("$line  ");
  }
  return out.join("\n");
}
