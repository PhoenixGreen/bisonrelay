import 'package:flutter/material.dart';

// element_model.dart is the vocabulary a block's settings are written in:
// what a setting is, what answers it takes, and how those get written down.
//
// Apart from the blocks themselves, because five blocks written in it made
// one file of a thousand lines where the shape of the thing was buried in
// the middle of the banner's fourteen settings. The blocks are in specs/,
// one to a file, and each reads as what it is: a description of one block.

/// ElementOption is one answer a setting will take.
@immutable
class ElementOption {
  final String label;

  /// value is what gets written. Empty means "leave the setting out", which
  /// is not the same as writing a zero.
  final String value;
  final String? note;
  const ElementOption(this.label, this.value, {this.note});
}

/// SettingKind is what sort of answer a setting takes, which is what the
/// panel needs to know to offer it.
enum SettingKind {
  /// One of the listed options and nothing else.
  choice,

  /// A colour: the listed ones, or any other, picked.
  colour,

  /// Two or more colours, written comma separated.
  colours,

  /// Free text -- a picture's path, which only the writer knows.
  text,
}

/// ElementSetting is one thing a block can be told.
@immutable
class ElementSetting {
  final String key;
  final String label;
  final String description;
  final List<ElementOption> options;

  final SettingKind kind;

  /// defaultIndex is the option that is already true of a block that says
  /// nothing -- shown as the active one, so the panel opens describing what
  /// the writer would get rather than an empty form.
  final int defaultIndex;

  const ElementSetting({
    required this.key,
    required this.label,
    required this.description,
    required this.options,
    this.kind = SettingKind.choice,
    this.defaultIndex = 0,
  });

  ElementOption get fallback => options[defaultIndex];
}

/// SettingGroup is several settings shown as one thing to open.
///
/// A banner has fourteen settings, and a list of fourteen is a list nobody
/// reads. Grouped, it is five: what fills the writing, what outlines it,
/// the panel behind it, how the words are set, and the row they sit in.
///
/// [exclusive] marks a group where the settings are alternatives rather than
/// additions -- a title is filled with a colour, or a gradient, or a
/// picture, and picking one means the others are not what is happening.
/// Choosing in an exclusive group clears the rest, so a banner never carries
/// two answers to one question.
@immutable
class SettingGroup {
  final String label;
  final String description;
  final List<ElementSetting> settings;
  final bool exclusive;

  const SettingGroup({
    required this.label,
    required this.description,
    required this.settings,
    this.exclusive = false,
  });
}

/// ElementShape is how a block's settings are written down.
enum ElementShape {
  /// One setting to a line, between an opening and a closing marker.
  lines,

  /// All the settings in brackets on the opening marker.
  attributes,

  /// One line, with the setting bare in the brackets and no closing
  /// marker: --include[header]--.
  single,

  /// The setting bare in the brackets, with a body and a closing marker:
  /// --nav[pills]-- ... --/nav--. Not the same as attributes, which writes
  /// key=value pairs -- a bar written --nav[style=pills]-- matches nothing
  /// and is drawn as the words it is made of.
  valueBlock,
}

/// RowSpec is a block written inside another one, whose settings go in
/// brackets as bare words rather than as key=value.
///
/// A banner's rows are the only case. They are not fields of the banner --
/// a banner may have two of them, each with its own height and layout --
/// and writing them as though they were would produce something the parser
/// reads as a line with a colon in it.
@immutable
class RowSpec {
  final String tag;

  /// number is which row this is, and what keeps two rows' settings apart:
  /// row 1's height is "height1", row 2's is "height2". Without it both
  /// rows would answer to one key and setting either would set both.
  final int number;

  /// cells is what goes inside one row. Named cells for a row that divides,
  /// which is what left: and right: are.
  final String cells;
  final List<ElementSetting> settings;
  const RowSpec({
    required this.tag,
    required this.number,
    required this.cells,
    required this.settings,
  });

  /// isSet is whether this row was asked for at all.
  ///
  /// A banner may have one row or two, so the second is written only when
  /// something has been chosen for it -- an empty second row is a fixed
  /// height of nothing, which reads as a gap the writer cannot account for.
  bool isSet(Map<String, String> values) =>
      settings.any((s) => (values[s.key] ?? "").isNotEmpty);
}

/// ElementSpec is one block the panel can write.
@immutable
class ElementSpec {
  final IconData icon;
  final String name;

  /// tag is the word in the markers: "page" for --page-- / --/page--.
  final String tag;
  final ElementShape shape;

  /// about is what the block is for, shown at the top of the panel when it
  /// is opened. Always -- it is the panel's own explanation, and costs the
  /// document nothing.
  final String about;

  /// tip is the note written into the document beside the block, or empty
  /// for a block that goes in with none.
  ///
  /// Empty for the banner. A banner is already fifteen lines, and three
  /// notes in among them -- one for the block and one in each row -- were
  /// more of what was on screen than the settings were. A note earns its
  /// place on a short block where there is something surprising to say; on
  /// a long one it is the thing you delete before you can read what you
  /// wrote.
  ///
  ///
  /// Written as an HTML comment, which the renderer draws as nothing -- so
  /// it is a note to whoever is writing and not something a reader ever
  /// sees. It is ordinary text on an ordinary line, so deleting it is
  /// selecting it and pressing delete, which is what anybody would try.
  final String tip;

  /// body is what goes between the markers, or null for a block with no
  /// inside. A placeholder, so the block reads as something rather than as
  /// an empty pair of markers.
  final String? body;

  final List<ElementSetting> settings;

  /// rows are the blocks written inside this one. Only a banner has any,
  /// and it may have two.
  final List<RowSpec> rows;

  /// groups is how the panel lists the settings, for a block with enough of
  /// them that a flat list is unreadable. Empty means one item each.
  ///
  /// Display only: what gets written comes from [settings], and a test holds
  /// the two together so a setting cannot be grouped out of existence or
  /// left out of every group.
  final List<SettingGroup> groups;

  const ElementSpec({
    required this.icon,
    required this.name,
    required this.tag,
    required this.shape,
    required this.about,
    this.tip = "",
    required this.settings,
    this.body,
    this.rows = const [],
    this.groups = const [],
  });

  /// rowGroups are the rows shown as groups like any other, because to
  /// whoever is writing that is what they are.
  List<SettingGroup> get rowGroups => [
        for (var r in rows)
          SettingGroup(
            label: "Row ${r.number}",
            description: r.number == 1
                ? "The first row, written in its own brackets. A banner is "
                    "at most two rows and each is at most two cells."
                : "A second row, left out entirely unless something here is "
                    "chosen. A short flush row under a tall one is the "
                    "usual shape: a banner with a bar of links beneath it.",
            settings: r.settings,
          ),
      ];

  /// allSettings is every setting this block has, however the panel
  /// happens to arrange them: the ungrouped ones, the grouped ones, then
  /// the row's.
  ///
  /// One list and one definition. A setting belongs to exactly one place --
  /// [settings] if it stands alone, a group if it is shown with others --
  /// so there is nothing to keep in step and no way to define one twice
  /// with different answers.
  List<ElementSetting> get allSettings => [
        ...settings,
        for (var g in groups) ...g.settings,
        for (var r in rows) ...r.settings,
      ];

  /// chosenOrDefault fills in whatever the writer has not picked.
  Map<String, String> chosenOrDefault(Map<String, String> chosen) => {
        for (var s in allSettings) s.key: chosen[s.key] ?? s.fallback.value,
      };

  /// _rowBlock is the row, written from what was picked for it.
  ///
  /// Bare words in brackets and in no particular order: the parser reads a
  /// number as the height and each remaining word for what it is, so
  /// --row[200,center,group]-- and --row[group,center,200]-- are the same
  /// row.
  List<String> _rowBlocks(
      Map<String, String> values, Map<String, String> chosen) {
    var out = <String>[];
    for (var spec in rows) {
      // The first row always, a later one only when it was asked for.
      if (spec.number > 1 && !spec.isSet(chosen)) continue;
      var words = [
        for (var s in spec.settings)
          if ((values[s.key] ?? "").isNotEmpty) values[s.key]!
      ];
      var open = words.isEmpty
          ? "--${spec.tag}--"
          : "--${spec.tag}[${words.join(",")}]--";
      out.add("$open\n${spec.cells}\n--/${spec.tag}--");
    }
    return out;
  }

  /// write builds the block, with its note above it.
  ///
  /// A setting whose value is empty is left out rather than written as
  /// nothing: "background:" with no answer is a line the parser reads and
  /// discards, and a writer looking at it cannot tell it is doing nothing.
  String write(Map<String, String> chosen) {
    var values = chosenOrDefault(chosen);
    var set = [
      for (var s in allSettings)
        if ((values[s.key] ?? "").isNotEmpty)
          (key: s.key, value: values[s.key]!)
    ];

    var note = tip.isEmpty ? null : "<!-- $tip -->";
    switch (shape) {
      case ElementShape.single:
        return [
          if (note != null) note,
          "--$tag${set.isEmpty ? "" : "[${set.first.value}]"}--",
        ].join("\n");
      case ElementShape.valueBlock:
        // The first setting bare, the rest as key=value. That is the shape
        // a bar has always been written in -- --nav[pills]-- came first and
        // still has to read -- so the settings added since sit beside the
        // bare word rather than replacing it.
        var written = [
          if (set.isNotEmpty) set.first.value,
          for (var e in set.skip(1)) "${e.key}=${e.value}",
        ];
        var only = written.isEmpty ? "" : "[${written.join(", ")}]";
        return [
          if (note != null) note,
          "--$tag$only--",
          body ?? "",
          "--/$tag--",
        ].join("\n");
      case ElementShape.attributes:
        var attrs = set.map((e) => "${e.key}=${e.value}").join(", ");
        var open = attrs.isEmpty ? "--$tag--" : "--$tag[$attrs]--";
        return "$note\n$open\n${body ?? ""}\n--/$tag--";
      case ElementShape.lines:
        // The block's own fields, which is everything but the row's -- a
        // row's settings are words in its brackets, not lines in the block.
        var rowKeys = {
          for (var r in rows)
            for (var s in r.settings) s.key
        };
        var lines = set
            .where((e) => !rowKeys.contains(e.key))
            .map((e) => "${e.key}: ${e.value}")
            .join("\n");
        var rowBlocks = _rowBlocks(values, chosen);

        // The parts of the block, each a run of lines that belongs
        // together: the settings, then each row. Separated by a blank line
        // when there is more than one, and the markers given one too --
        // fifteen lines with no break in them is a wall, and the rows are
        // the part anybody scrolling is looking for.
        //
        // A block with only settings gets none of that, because there is
        // nothing to separate it from.
        var parts = [
          if (lines.isNotEmpty) lines,
          ...rowBlocks,
          if (body != null) body!,
        ];
        var between = parts.length > 1 ? "\n\n" : "\n";
        return [
          if (note != null) note,
          "--$tag--$between${parts.join("\n\n")}$between--/$tag--",
        ].join("\n");
    }
  }
}

/// spaces are the answers every padding and margin takes. The same list in
/// both, because they are the same measurement on opposite sides of an edge
/// and offering different numbers for each would suggest otherwise.
const List<ElementOption> spaces = [
  ElementOption("None", "0"),
  ElementOption("Tight", "8"),
  ElementOption("Normal", "16"),
  ElementOption("Roomy", "24"),
  ElementOption("Generous", "40"),
];

/// roles are the colours a block may name.
///
/// Named, never given: a page cannot know whether its reader is in a dark
/// theme, so a colour it writes as #000000 is one nobody in one can see.
/// These come from the reader's own palette and are right in both.
const List<ElementOption> roles = [
  ElementOption("Lines and borders", "outline"),
  ElementOption("Accent", "accent"),
  ElementOption("Muted", "muted"),
  ElementOption("Raised surface", "raised"),
  ElementOption("Quote bar", "quoteBar"),
];

/// hexColours are the colours a banner's writing takes.
///
/// Hex, not a role name. The rest of a page names colours from the reader's
/// palette, and a banner deliberately does not: its writing sits on a
/// picture the writer chose, and only they can know what will read against
/// it. The parser takes #rgb, #rrggbb and #rrggbbaa -- the last being
/// see-through, which is what a panel behind the letters wants.
const List<ElementOption> hexColours = [
  ElementOption("Theme default", ""),
  ElementOption("White", "#ffffff"),
  ElementOption("Black", "#000000"),
  ElementOption("Half-black", "#00000080", note: "See-through"),
];
