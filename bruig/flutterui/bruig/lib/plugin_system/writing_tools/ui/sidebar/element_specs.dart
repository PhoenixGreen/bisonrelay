import 'package:flutter/material.dart';

// element_specs.dart is what the Pages and store panel knows about the
// blocks it writes: what each one is for, what it can be told, and what it
// does when told nothing.
//
// Declared rather than described in prose, because the panel has three jobs
// for the same knowledge -- list the settings, show what each one accepts,
// and write the block -- and three prose copies of it would be three copies
// to keep in step with the parsers.
//
// Every value here is one the matching parser actually accepts. A panel
// offering a setting that does nothing is worse than a panel not offering
// it: the writer picks it, sees no change, and has no way to tell whether
// they have made a mistake or found a bug.

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
  bool isSet(Map<String, String> values) => settings
      .any((s) => (values[s.key] ?? "").isNotEmpty);
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
  List<String> _rowBlocks(Map<String, String> values, Map<String, String> chosen) {
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
        if ((values[s.key] ?? "").isNotEmpty) (key: s.key, value: values[s.key]!)
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
        var rowKeys = {for (var r in rows) for (var s in r.settings) s.key};
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

/// _spaces are the answers every padding and margin takes. The same list in
/// both, because they are the same measurement on opposite sides of an edge
/// and offering different numbers for each would suggest otherwise.
const List<ElementOption> _spaces = [
  ElementOption("None", "0"),
  ElementOption("Tight", "8"),
  ElementOption("Normal", "16"),
  ElementOption("Roomy", "24"),
  ElementOption("Generous", "40"),
];

/// _roles are the colours a block may name.
///
/// Named, never given: a page cannot know whether its reader is in a dark
/// theme, so a colour it writes as #000000 is one nobody in one can see.
/// These come from the reader's own palette and are right in both.
const List<ElementOption> _roles = [
  ElementOption("Lines and borders", "outline"),
  ElementOption("Accent", "accent"),
  ElementOption("Muted", "muted"),
  ElementOption("Raised surface", "raised"),
  ElementOption("Quote bar", "quoteBar"),
];

const ElementSpec pageSpec = ElementSpec(
  icon: Icons.web_outlined,
  name: "Page setup",
  tag: "page",
  shape: ElementShape.lines,
  about: "Page setup: how wide this page is, what it sits on, and the room "
      "it keeps around itself. Put it at the top. Delete this note.",
  tip: "Page setup: how wide this page is, what it sits on, and the room "
      "it keeps around itself. Put it at the top. Delete this note.",
  settings: [
    ElementSetting(
      key: "width",
      label: "Width",
      description: "How wide the writing is allowed to get. A banner row "
          "marked flush still runs the whole way across.",
      options: [
        ElementOption("Full window", ""),
        ElementOption("Narrow (600)", "600"),
        ElementOption("Readable (800)", "800", note: "A comfortable measure"),
        ElementOption("Wide (1000)", "1000"),
      ],
    ),
    ElementSetting(
      key: "background",
      label: "Background",
      description: "What the page sits on. Named from the reader's palette, "
          "so it is right in a dark theme and a light one.",
      options: [
        ElementOption("None", ""),
        ElementOption("Raised", "raised", note: "The surface a card sits on"),
        ElementOption("Quiet", "quiet"),
      ],
    ),
    ElementSetting(
      key: "padding",
      label: "Padding",
      description: "Inside the background.",
      options: _spaces,
      defaultIndex: 2,
    ),
    ElementSetting(
      key: "margin",
      label: "Margin",
      description: "Outside the background. Set it to None to run the page "
          "right to the edge of the window.",
      options: _spaces,
      defaultIndex: 2,
    ),
  ],
);

const ElementSpec panelSpec = ElementSpec(
  icon: Icons.crop_square,
  name: "Panel",
  tag: "panel",
  shape: ElementShape.attributes,
  body: "Anything at all, including other blocks.",
  about: "Panel: a box round a piece of the page. Borders take one number for "
      "all four sides, or four -- top, right, bottom, left -- so "
      "border=0 0 0 4 is a rule down the left. Delete this note.",
  tip: "Panel: a box round a piece of the page. Borders take one number for "
      "all four sides, or four -- top, right, bottom, left -- so "
      "border=0 0 0 4 is a rule down the left. Delete this note.",
  settings: [
    ElementSetting(
      key: "padding",
      label: "Padding",
      description: "Between the border and what is inside it.",
      options: _spaces,
      defaultIndex: 2,
    ),
    ElementSetting(
      key: "margin",
      label: "Margin",
      description: "Between the panel and what is around it.",
      options: _spaces,
      defaultIndex: 0,
    ),
    ElementSetting(
      key: "border",
      label: "Border",
      description: "One number for all four sides, or four for each side "
          "from the top going clockwise.",
      options: [
        ElementOption("None", ""),
        ElementOption("Hairline", "1"),
        ElementOption("Medium", "2"),
        ElementOption("Left rule", "0 0 0 4", note: "A line down one side"),
        ElementOption("Top rule", "4 0 0 0"),
      ],
      defaultIndex: 1,
    ),
    ElementSetting(
      key: "style",
      label: "Stroke",
      description: "How the border is drawn.",
      options: [
        ElementOption("Solid", "solid"),
        ElementOption("Dashed", "dashed"),
        ElementOption("Dotted", "dotted"),
        ElementOption("None", "none"),
      ],
    ),
    ElementSetting(
      key: "color",
      label: "Colour",
      description: "The border's colour, from the reader's palette.",
      options: _roles,
    ),
    ElementSetting(
      key: "radius",
      label: "Corners",
      description: "How rounded the corners are. Corners round only when "
          "all four sides have the same thickness.",
      options: [
        ElementOption("Square", "0"),
        ElementOption("Slight", "4"),
        ElementOption("Rounded", "8"),
        ElementOption("Very round", "16"),
      ],
      defaultIndex: 2,
    ),
  ],
);

/// _hexColours are the colours a banner's writing takes.
///
/// Hex, not a role name. The rest of a page names colours from the reader's
/// palette, and a banner deliberately does not: its writing sits on a
/// picture the writer chose, and only they can know what will read against
/// it. The parser takes #rgb, #rrggbb and #rrggbbaa -- the last being
/// see-through, which is what a panel behind the letters wants.
const List<ElementOption> _hexColours = [
  ElementOption("Theme default", ""),
  ElementOption("White", "#ffffff"),
  ElementOption("Black", "#000000"),
  ElementOption("Half-black", "#00000080", note: "See-through"),
];

const ElementSpec headerSpec = ElementSpec(
  icon: Icons.view_day_outlined,
  name: "Header",
  tag: "header",
  shape: ElementShape.lines,
  about: "Header: the banner at the top of a page. At most two rows, at most "
      "two cells each -- copy the row block for a second. A row's settings "
      "go in its brackets in any order: a number is the height, flush runs "
      "it to the banner's edge, and group keeps its two cells together. "
      "Delete this note.",
  rows: [
    RowSpec(
      tag: "row",
      number: 1,
      cells: "left: ![](assets/logo.svg)\nright: # My Site",
      settings: [
        ElementSetting(
          key: "height1",
          label: "Height",
          description: "How tall the row is. Everything in it is sized to "
              "this, so a title comes out level with the logo beside it "
              "without either being told about the other.",
          options: [
            ElementOption("Short (44)", "44", note: "A bar of links"),
            ElementOption("Medium (96)", "96"),
            ElementOption("Tall (200)", "200", note: "A logo and a title"),
          ],
          defaultIndex: 1,
        ),
        ElementSetting(
          key: "layout1",
          label: "Layout",
          description: "Where the row's cells sit. Split pushes them to "
              "either end; left, centre and right hold them together at "
              "that side.",
          options: [
            ElementOption("Left", "left"),
            ElementOption("Centre", "center"),
            ElementOption("Right", "right"),
            ElementOption("Split", "split", note: "One at each end"),
          ],
        ),
        ElementSetting(
          key: "flush1",
          label: "Flush",
          description: "Runs the row to the banner's edge, giving up the "
              "inset it would otherwise keep. What a strip along the top "
              "or bottom of a banner wants.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "flush"),
          ],
        ),
        ElementSetting(
          key: "group1",
          label: "Group",
          description: "Keeps the row's two cells together as a pair "
              "rather than letting the second have the rest of the row -- "
              "a logo and a title beside it, sitting as one thing.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "group"),
          ],
        ),
      ],
    ),
    RowSpec(
      tag: "row",
      number: 2,
      cells: "--include[navigation]--",
      settings: [
        ElementSetting(
          key: "height2",
          label: "Height",
          description: "How tall the row is. Everything in it is sized to "
              "this, so a title comes out level with the logo beside it "
              "without either being told about the other.",
          options: [
            ElementOption("Short (44)", "44", note: "A bar of links"),
            ElementOption("Medium (96)", "96"),
            ElementOption("Tall (200)", "200", note: "A logo and a title"),
          ],
          defaultIndex: 0,
        ),
        ElementSetting(
          key: "layout2",
          label: "Layout",
          description: "Where the row's cells sit. Split pushes them to "
              "either end; left, centre and right hold them together at "
              "that side.",
          options: [
            ElementOption("Left", "left"),
            ElementOption("Centre", "center"),
            ElementOption("Right", "right"),
            ElementOption("Split", "split", note: "One at each end"),
          ],
        ),
        ElementSetting(
          key: "flush2",
          label: "Flush",
          description: "Runs the row to the banner's edge, giving up the "
              "inset it would otherwise keep. What a strip along the top "
              "or bottom of a banner wants.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "flush"),
          ],
        ),
        ElementSetting(
          key: "group2",
          label: "Group",
          description: "Keeps the row's two cells together as a pair "
              "rather than letting the second have the rest of the row -- "
              "a logo and a title beside it, sitting as one thing.",
          options: [
            ElementOption("No", ""),
            ElementOption("Yes", "group"),
          ],
        ),
      ],
    ),
  ],
  groups: [
    SettingGroup(
      label: "Title fill",
      description: "What the writing is filled with. One of these at a time: "
          "a picture is poured through the letters if there is one, then a "
          "gradient, and the colour is what is used otherwise.",
      exclusive: true,
      settings: [
        ElementSetting(
          key: "titlecolor",
          label: "Colour",
          description: "One colour for the writing.",
          kind: SettingKind.colour,
          options: _hexColours,
        ),
        ElementSetting(
          key: "titlegradient",
          label: "Gradient",
          description: "Two or more colours, poured through the letters.",
          kind: SettingKind.colours,
          options: [
            ElementOption("None", ""),
            ElementOption("Two colours", "#f00,#00f"),
          ],
        ),
        ElementSetting(
          key: "titleimage",
          label: "Picture",
          description: "A picture poured through the letters, so the writing "
              "is cut out of it. Name one of the site's own pictures.",
          kind: SettingKind.text,
          options: [
            ElementOption("None", ""),
            ElementOption("A site picture", "![](assets/banner.jpg)",
                note: "Change the name to one of yours"),
          ],
        ),
      ],
    ),
    SettingGroup(
      label: "Title outline",
      description: "A line round each letter, which is what makes writing "
          "readable over a picture.",
      settings: [
        ElementSetting(
          key: "titleoutline",
          label: "Width",
          description: "How thick the line is.",
          options: [
            ElementOption("None", "0"),
            ElementOption("Thin", "2"),
            ElementOption("Medium", "5"),
            ElementOption("Thick", "10"),
          ],
        ),
        ElementSetting(
          key: "titleoutlinecolor",
          label: "Colour",
          description: "The colour of that line.",
          kind: SettingKind.colour,
          options: _hexColours,
        ),
      ],
    ),
    SettingGroup(
      label: "Title panel and lettering",
      description: "The panel behind the writing, and how the words "
          "themselves are set.",
      settings: [
        ElementSetting(
          key: "titlebackground",
          label: "Panel colour",
          description: "A see-through colour keeps the picture visible while "
              "making the words readable.",
          kind: SettingKind.colour,
          options: _hexColours,
        ),
        ElementSetting(
          key: "titlepadding",
          label: "Panel padding",
          description: "Room between the writing and the panel's edge.",
          options: [
            ElementOption("None", "0"),
            ElementOption("Tight", "8"),
            ElementOption("Roomy", "16"),
          ],
        ),
        ElementSetting(
          key: "titleradius",
          label: "Panel corners",
          description: "How rounded the panel's corners are.",
          options: [
            ElementOption("Square", "0"),
            ElementOption("Rounded", "8"),
            ElementOption("Very round", "24"),
          ],
        ),
        ElementSetting(
          key: "titleweight",
          label: "Weight",
          description: "Bold, or as the theme sets it.",
          options: [
            ElementOption("Regular", "regular"),
            ElementOption("Bold", "bold"),
          ],
        ),
        ElementSetting(
          key: "titleitalic",
          label: "Italic",
          description: "Slanted or upright.",
          options: [
            ElementOption("No", "no"),
            ElementOption("Yes", "yes"),
          ],
        ),
        ElementSetting(
          key: "titlecase",
          label: "Case",
          description: "Changes the words themselves rather than drawing "
              "them differently, so what a reader copies out is what they "
              "see.",
          options: [
            ElementOption("As written", ""),
            ElementOption("UPPER", "upper"),
            ElementOption("lower", "lower"),
          ],
        ),
        ElementSetting(
          key: "titletracking",
          label: "Tracking",
          description: "Space between the letters.",
          options: [
            ElementOption("Normal", "0"),
            ElementOption("Open", "0.5"),
            ElementOption("Wide", "2"),
          ],
        ),
      ],
    ),
  ],
  settings: [
    ElementSetting(
      key: "background",
      label: "Background picture",
      description: "A picture from the site's own Pictures, behind the "
          "whole banner. Add one with Add Picture and paste what it gives "
          "you in place of the name here.",
      kind: SettingKind.text,
      options: [
        ElementOption("None", ""),
        ElementOption("A site picture", "![](assets/banner.jpg)",
            note: "Change the name to one of yours"),
      ],
    ),
    ElementSetting(
      key: "titlesize",
      label: "Title size",
      description: "In pixels. Left alone, the writing is set to the height "
          "of the row it is in, which is usually what you want.",
      options: [
        ElementOption("Row height", ""),
        ElementOption("32", "32"),
        ElementOption("48", "48"),
        ElementOption("72", "72"),
      ],
    ),
  ],
);

const ElementSpec navSpec = ElementSpec(
  icon: Icons.menu_open,
  name: "Navigation bar",
  tag: "nav",
  shape: ElementShape.valueBlock,
  body: "[Home](index.md)\n[About](about.md)\n[Store](store)",
  about: "Navigation bar: one link a line, between the markers. Link a page "
      "with [About](about.md) and your store with [Store](store). What is "
      "not set here comes from the reader's Markdown theme, which is where "
      "the colours live. Delete this note.",
  tip: "Navigation bar: one link a line, between the markers. Link a page "
      "with [About](about.md) and your store with [Store](store). What is "
      "not set here comes from the reader's Markdown theme, which is where "
      "the colours live. Delete this note.",
  settings: [
    ElementSetting(
      key: "style",
      label: "Shape",
      description: "How each link is drawn. Its colours come from the "
          "reader's Markdown theme.",
      options: [
        ElementOption("Plain", "plain", note: "Words with space between"),
        ElementOption("Pills", "pills"),
        ElementOption("Underline", "underline"),
        ElementOption("Boxed", "boxed"),
      ],
    ),
  ],
  groups: [
    SettingGroup(
      label: "Background",
      description: "What the bar itself sits on, behind the links, and how "
          "tall that is.",
      settings: [
        ElementSetting(
          key: "background",
          label: "Colour",
          description: "A colour from the reader's palette, or one of your "
              "own. A bar on a page belongs to the reader's theme like "
              "everything else; one in a banner sits over a picture you "
              "chose, and only you know what will read against it -- which "
              "is why both are offered. A see-through colour keeps the "
              "picture visible.",
          kind: SettingKind.colour,
          options: [
            ElementOption("Theme default", ""),
            ElementOption("None", "none", note: "No background at all"),
            ElementOption("Raised surface", "raised", note: "From the palette"),
            ElementOption("Half-black", "#00000080", note: "See-through"),
            ElementOption("White", "#ffffff"),
          ],
        ),
        ElementSetting(
          key: "height",
          label: "Height",
          description: "How tall the bar is, with the links held in the "
              "middle of it. Left alone, it is as tall as the links need.",
          options: [
            ElementOption("As tall as the links", ""),
            ElementOption("Short (36)", "36"),
            ElementOption("Medium (44)", "44"),
            ElementOption("Tall (64)", "64"),
          ],
        ),
      ],
    ),
    SettingGroup(
      label: "Placement",
      description: "Where the bar sits and how much room it keeps. Left "
          "alone, a bar follows the row it is in and the reader's theme.",
      settings: [
        ElementSetting(
          key: "align",
          label: "Align",
          description: "Which way the links run. Left alone, a bar in a "
              "banner row follows that row, and a bar on the page runs "
              "from the left.",
          options: [
            ElementOption("As the row", ""),
            ElementOption("Left", "left"),
            ElementOption("Middle", "center"),
            ElementOption("Right", "right"),
          ],
        ),
        ElementSetting(
          key: "width",
          label: "Width",
          description: "Whether the bar's background runs the whole way "
              "across or only under the links. Only visible once the bar "
              "has a background, which the theme sets.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Under the links", "fit"),
            ElementOption("Full width", "full"),
          ],
        ),
        ElementSetting(
          key: "gap",
          label: "Space between links",
          description: "How far apart the links are.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Tight", "6"),
            ElementOption("Normal", "12"),
            ElementOption("Wide", "24"),
          ],
        ),
        ElementSetting(
          key: "radius",
          label: "Corners on each link",
          description: "How rounded a pill or a box is. Nothing to see on a "
              "plain bar, where the links are just words.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("Square", "0"),
            ElementOption("Slight", "4"),
            ElementOption("Rounded", "10"),
            ElementOption("Fully round", "40"),
          ],
        ),
        ElementSetting(
          key: "padding",
          label: "Padding in each link",
          description: "Room inside a link, which is what gives a pill or "
              "a box its size. Nothing to see on a plain bar, where the "
              "links are just words.",
          options: [
            ElementOption("Theme default", ""),
            ElementOption("None", "0"),
            ElementOption("Tight", "6"),
            ElementOption("Roomy", "14"),
          ],
        ),
        ElementSetting(
          key: "margin",
          label: "Margin",
          description: "Room around the bar. One number for all four sides, "
              "or four for each side from the top going clockwise.\n\n"
              "In a banner row the row holds the bar in its middle, so room "
              "added evenly on both sides moves nothing -- it makes the bar "
              "taller and the middle is still the middle. Use one of the "
              "one-sided answers to shift it.",
          options: [
            ElementOption("None", ""),
            ElementOption("Push down", "16 0 0 0", note: "Room above only"),
            ElementOption("Push up", "0 0 16 0", note: "Room below only"),
            ElementOption("Indent", "0 0 0 24", note: "Room at the left only"),
            ElementOption("All round", "16", note: "Not in a banner row"),
          ],
        ),
      ],
    ),
  ],
);

const ElementSpec fragmentSpec = ElementSpec(
  icon: Icons.extension_outlined,
  name: "Shared fragment",
  tag: "include",
  shape: ElementShape.single,
  about: "Shared fragment: a piece several pages share -- a banner, a "
      "navigation bar, a footer. Write it once in Writing > Library > "
      "Fragments, then name it here and it appears in its place. It is "
      "filled in before the page is sent, so a reader gets one page. "
      "Delete this note.",
  tip: "Shared fragment: a piece several pages share -- a banner, a "
      "navigation bar, a footer. Write it once in Writing > Library > "
      "Fragments, then name it here and it appears in its place. It is "
      "filled in before the page is sent, so a reader gets one page. "
      "Delete this note.",
  settings: [
    ElementSetting(
      key: "name",
      label: "Which fragment",
      description: "The fragment's name, as it is called in Fragments. "
          "Letters, numbers and dashes.",
      options: [
        ElementOption("header", "header"),
        ElementOption("navigation", "navigation"),
        ElementOption("footer", "footer"),
      ],
    ),
  ],
);

/// pageElementSpecs are the blocks the Pages and store panel explains, in
/// the order it lists them: the page itself, then what goes on it.
const List<ElementSpec> pageElementSpecs = [
  pageSpec,
  headerSpec,
  navSpec,
  panelSpec,
  fragmentSpec,
];
