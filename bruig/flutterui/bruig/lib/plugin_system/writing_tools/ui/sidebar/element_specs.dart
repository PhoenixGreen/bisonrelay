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

/// ElementSetting is one thing a block can be told.
@immutable
class ElementSetting {
  final String key;
  final String label;
  final String description;
  final List<ElementOption> options;

  /// defaultIndex is the option that is already true of a block that says
  /// nothing -- shown as the active one, so the panel opens describing what
  /// the writer would get rather than an empty form.
  final int defaultIndex;

  const ElementSetting({
    required this.key,
    required this.label,
    required this.description,
    required this.options,
    this.defaultIndex = 0,
  });

  ElementOption get fallback => options[defaultIndex];
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

  /// cells is what goes inside one row. Named cells for a row that divides,
  /// which is what left: and right: are.
  final String cells;
  final List<ElementSetting> settings;
  const RowSpec({
    required this.tag,
    required this.cells,
    required this.settings,
  });
}

/// ElementSpec is one block the panel can write.
@immutable
class ElementSpec {
  final IconData icon;
  final String name;

  /// tag is the word in the markers: "page" for --page-- / --/page--.
  final String tag;
  final ElementShape shape;

  /// tip is the note written in beside the block, explaining what it is for.
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

  /// rows is the block written inside this one, or null for a block with
  /// none. Only a banner has one.
  final RowSpec? rows;

  const ElementSpec({
    required this.icon,
    required this.name,
    required this.tag,
    required this.shape,
    required this.tip,
    required this.settings,
    this.body,
    this.rows,
  });

  /// allSettings is everything the panel lists: the block's own, then the
  /// row's. One list, because to whoever is writing they are all just
  /// things a banner can be told.
  List<ElementSetting> get allSettings => [...settings, ...?rows?.settings];

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
  String? _rowBlock(Map<String, String> values) {
    var spec = rows;
    if (spec == null) return null;
    var words = [
      for (var s in spec.settings)
        if ((values[s.key] ?? "").isNotEmpty) values[s.key]!
    ];
    var open = words.isEmpty
        ? "--${spec.tag}--"
        : "--${spec.tag}[${words.join(",")}]--";
    return "$open\n${spec.cells}\n--/${spec.tag}--";
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

    var note = "<!-- $tip -->";
    switch (shape) {
      case ElementShape.single:
        return "$note\n--$tag${set.isEmpty ? "" : "[${set.first.value}]"}--";
      case ElementShape.valueBlock:
        var only = set.isEmpty ? "" : "[${set.first.value}]";
        return "$note\n--$tag$only--\n${body ?? ""}\n--/$tag--";
      case ElementShape.attributes:
        var attrs = set.map((e) => "${e.key}=${e.value}").join(", ");
        var open = attrs.isEmpty ? "--$tag--" : "--$tag[$attrs]--";
        return "$note\n$open\n${body ?? ""}\n--/$tag--";
      case ElementShape.lines:
        var own = {for (var s in settings) s.key};
        var lines = set
            .where((e) => own.contains(e.key))
            .map((e) => "${e.key}: ${e.value}")
            .join("\n");
        var row = _rowBlock(values);
        return [
          note,
          "--$tag--",
          if (lines.isNotEmpty) lines,
          if (row != null) row,
          if (body != null) body!,
          "--/$tag--",
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
  tip: "Header: the banner at the top of a page. At most two rows, at most "
      "two cells each -- copy the row block for a second. A row's settings "
      "go in its brackets in any order: a number is the height, flush runs "
      "it to the banner's edge, and group keeps its two cells together. "
      "Delete this note.",
  rows: RowSpec(
    tag: "row",
    cells: "left: ![](assets/logo.svg)\nright: # My Site",
    settings: [
      ElementSetting(
        key: "height",
        label: "Row height",
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
        key: "layout",
        label: "Row layout",
        description: "Where the row's cells sit. Split pushes them to "
            "either end; left, centre and right hold them together at that "
            "side.",
        options: [
          ElementOption("Left", "left"),
          ElementOption("Centre", "center"),
          ElementOption("Right", "right"),
          ElementOption("Split", "split", note: "One at each end"),
        ],
      ),
      ElementSetting(
        key: "flush",
        label: "Flush",
        description: "Runs the row to the banner's edge, giving up the "
            "inset it would otherwise keep. What a strip along the top or "
            "bottom of a banner wants.",
        options: [
          ElementOption("No", ""),
          ElementOption("Yes", "flush"),
        ],
      ),
      ElementSetting(
        key: "group",
        label: "Group",
        description: "Keeps the row's two cells together as a pair rather "
            "than letting the second have the rest of the row -- a logo "
            "and a title beside it, sitting as one thing.",
        options: [
          ElementOption("No", ""),
          ElementOption("Yes", "group"),
        ],
      ),
    ],
  ),
  settings: [
    ElementSetting(
      key: "background",
      label: "Background picture",
      description: "A picture from the site's own Pictures, behind the "
          "whole banner. Add one with Add Picture and paste what it gives "
          "you in place of the name here.",
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
    ElementSetting(
      key: "titlecolor",
      label: "Title colour",
      description: "The colour of the writing.",
      options: _hexColours,
    ),
    ElementSetting(
      key: "titlegradient",
      label: "Title gradient",
      description: "Two or more colours, separated by commas, poured "
          "through the letters. Used instead of the colour above.",
      options: [
        ElementOption("None", ""),
        ElementOption("Two colours", "#f00,#00f"),
      ],
    ),
    ElementSetting(
      key: "titleoutline",
      label: "Title outline",
      description: "A line round each letter, which is what makes writing "
          "readable over a picture.",
      options: [
        ElementOption("None", "0"),
        ElementOption("Thin", "2"),
        ElementOption("Medium", "5"),
        ElementOption("Thick", "10"),
      ],
    ),
    ElementSetting(
      key: "titleoutlinecolor",
      label: "Outline colour",
      description: "The colour of that line.",
      options: _hexColours,
    ),
    ElementSetting(
      key: "titlebackground",
      label: "Title background",
      description: "A panel behind the writing. A see-through colour keeps "
          "the picture visible while making the words readable.",
      options: _hexColours,
    ),
    ElementSetting(
      key: "titlepadding",
      label: "Title padding",
      description: "Room between the writing and the edge of that panel.",
      options: [
        ElementOption("None", "0"),
        ElementOption("Tight", "8"),
        ElementOption("Roomy", "16"),
      ],
    ),
    ElementSetting(
      key: "titleradius",
      label: "Title corners",
      description: "How rounded that panel's corners are.",
      options: [
        ElementOption("Square", "0"),
        ElementOption("Rounded", "8"),
        ElementOption("Very round", "24"),
      ],
    ),
    ElementSetting(
      key: "titleweight",
      label: "Title weight",
      description: "Bold, or as the theme sets it.",
      options: [
        ElementOption("Regular", "regular"),
        ElementOption("Bold", "bold"),
      ],
    ),
    ElementSetting(
      key: "titleitalic",
      label: "Title italic",
      description: "Slanted or upright.",
      options: [
        ElementOption("No", "no"),
        ElementOption("Yes", "yes"),
      ],
    ),
    ElementSetting(
      key: "titlecase",
      label: "Title case",
      description: "Changes the words themselves rather than drawing them "
          "differently, so what a reader copies out is what they see.",
      options: [
        ElementOption("As written", ""),
        ElementOption("UPPER", "upper"),
        ElementOption("lower", "lower"),
      ],
    ),
    ElementSetting(
      key: "titletracking",
      label: "Title tracking",
      description: "Space between the letters.",
      options: [
        ElementOption("Normal", "0"),
        ElementOption("Open", "0.5"),
        ElementOption("Wide", "2"),
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
  tip: "Navigation bar: one link a line, between the markers. Link a page "
      "with [About](about.md) and your store with [Store](store). Its "
      "colours and position come from the reader's Markdown theme, not "
      "from here. Delete this note.",
  settings: [
    ElementSetting(
      key: "style",
      label: "Shape",
      description: "How each link is drawn. The colours come from the "
          "reader's Markdown theme.",
      options: [
        ElementOption("Plain", "plain", note: "Words with space between"),
        ElementOption("Pills", "pills"),
        ElementOption("Underline", "underline"),
        ElementOption("Boxed", "boxed"),
      ],
    ),
  ],
);

const ElementSpec fragmentSpec = ElementSpec(
  icon: Icons.extension_outlined,
  name: "Shared fragment",
  tag: "include",
  shape: ElementShape.single,
  tip: "Shared fragment: a piece several pages share -- a banner, a "
      "navigation bar, a footer. Write it once in Writing > My Posts > "
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
