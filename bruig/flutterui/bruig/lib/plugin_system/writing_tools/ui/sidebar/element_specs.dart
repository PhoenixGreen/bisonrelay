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

  const ElementSpec({
    required this.icon,
    required this.name,
    required this.tag,
    required this.shape,
    required this.tip,
    required this.settings,
    this.body,
  });

  /// chosenOrDefault fills in whatever the writer has not picked.
  Map<String, String> chosenOrDefault(Map<String, String> chosen) => {
        for (var s in settings) s.key: chosen[s.key] ?? s.fallback.value,
      };

  /// write builds the block, with its note above it.
  ///
  /// A setting whose value is empty is left out rather than written as
  /// nothing: "background:" with no answer is a line the parser reads and
  /// discards, and a writer looking at it cannot tell it is doing nothing.
  String write(Map<String, String> chosen) {
    var values = chosenOrDefault(chosen);
    var set = [
      for (var s in settings)
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
        var lines = set.map((e) => "${e.key}: ${e.value}").join("\n");
        return [
          note,
          "--$tag--",
          if (lines.isNotEmpty) lines,
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

const ElementSpec headerSpec = ElementSpec(
  icon: Icons.view_day_outlined,
  name: "Header",
  tag: "header",
  shape: ElementShape.lines,
  body: "--row[96,split]--\n# My Site\n--/row--",
  tip: "Header: the banner at the top of a page. At most two rows, at most "
      "two cells each. A row is --row[height,layout]-- and may add flush "
      "to run to the edge, or group to keep its two cells together. "
      "Delete this note.",
  settings: [
    ElementSetting(
      key: "background",
      label: "Background picture",
      description: "A picture from the site's own Pictures, behind the whole "
          "banner. Add one with Add Picture and paste what it gives you.",
      options: [
        ElementOption("None", ""),
        ElementOption("A site picture", "![](assets/banner.jpg)",
            note: "Change the name to one of yours"),
      ],
    ),
    ElementSetting(
      key: "titlesize",
      label: "Title size",
      description: "How big the writing in the banner is set. Fill grows it "
          "to the height of the row.",
      options: [
        ElementOption("As written", ""),
        ElementOption("Fill the row", "fill"),
      ],
    ),
    ElementSetting(
      key: "titlecase",
      label: "Title case",
      description: "How the writing is cased, whatever was typed.",
      options: [
        ElementOption("As written", ""),
        ElementOption("UPPER", "upper"),
        ElementOption("lower", "lower"),
      ],
    ),
    ElementSetting(
      key: "titlecolor",
      label: "Title colour",
      description: "From the reader's palette.",
      options: [
        ElementOption("Theme default", ""),
        ElementOption("Accent", "accent"),
        ElementOption("Muted", "muted"),
        ElementOption("Text", "text"),
      ],
    ),
    ElementSetting(
      key: "titleoutline",
      label: "Title outline",
      description: "A line round each letter, which is what makes writing "
          "readable over a picture.",
      options: [
        ElementOption("None", ""),
        ElementOption("Thin", "1"),
        ElementOption("Thick", "3"),
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
