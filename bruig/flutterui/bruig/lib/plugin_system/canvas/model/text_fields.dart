// text_fields.dart is the fields a text may hold, filled in by the page it is
// drawn on: a running head or a page number on the master canvas that reads
// right on every page. Written in braces in the words themselves:
//
//   {page}        the page's number
//   {pages}       how many pages are numbered
//   {text:Name}   the words of the text (or text piece) called Name on the
//                 page: a lesson number read from the lesson's own title
//   {value:Name}  the value called Name the page was given in its settings
//
// On the master canvas, where there is no one page, each field that depends
// on the page shows as "#". Anything else in braces is left as written.

/// TextFieldKind is one kind of field, as the menu that puts one in offers it.
enum TextFieldKind {
  page("Page number", "{page}"),
  pages("Number of pages", "{pages}"),
  text("Words from this page", "{text:Name}"),
  value("A value set on the page", "{value:Name}");

  final String label;

  /// written is how it is typed, with Name to be replaced.
  final String written;
  const TextFieldKind(this.label, this.written);
}

/// _masterMark is what a field that depends on the page shows on the master.
const _masterMark = "#";

/// PageFields is what the fields on one page are filled from.
class PageFields {
  /// page is the page's number, or null for a cover or an unnumbered page.
  final int? page;

  /// pages is how many pages carry a number.
  final int pages;

  /// values are the page's own (CanvasScene.values).
  final Map<String, String> values;

  /// textOf is the words of the text or piece called a name on the page, or
  /// null where there is none.
  final String? Function(String name) textOf;

  /// master is true on the master canvas being edited: per-page fields show
  /// _masterMark.
  final bool master;

  const PageFields({
    this.page,
    this.pages = 0,
    this.values = const {},
    required this.textOf,
    this.master = false,
  });
}

final _field = RegExp(r"\{(page|pages|text:[^{}\n]+|value:[^{}\n]+)\}");

/// hasFields is whether [text] holds a field, cheaply: most words have no
/// brace at all.
bool hasFields(String text) => text.contains("{") && _field.hasMatch(text);

/// fillFields is [text] with its fields filled from [f].
String fillFields(String text, PageFields f) {
  if (!text.contains("{")) return text;
  return text.replaceAllMapped(_field, (m) {
    var what = m.group(1)!;
    if (what == "pages") return "${f.pages}";
    if (f.master) return _masterMark;
    if (what == "page") return f.page == null ? "" : "${f.page}";
    if (what.startsWith("text:")) {
      // The page's own words as written: a field in them is not filled
      // again, so two texts reading each other cannot go round for ever.
      return f.textOf(what.substring(5).trim()) ?? "";
    }
    return f.values[what.substring(6).trim()] ?? "";
  });
}
