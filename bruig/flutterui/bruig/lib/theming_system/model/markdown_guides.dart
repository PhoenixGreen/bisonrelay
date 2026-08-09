import 'package:bruig/theming_system/model/markdown_style.dart';

// markdown_guides.dart holds the guides that ship with the app.
//
// These are the ones worth naming in a published post. Every device has
// them, so a post that asks for "Article" is read as an article wherever it
// lands; a guide somebody built themselves exists only on their machine, and
// a post naming it falls back to Default for everyone else.
//
// Each is written as a departure from the theme rather than a full
// specification. A guide says the few things it cares about and leaves the
// rest to whatever the reader has chosen, which is what lets one guide work
// in a light theme and a dark one.

/// defaultGuideId is what a post with nothing to say about style resolves
/// to, and what an unknown name falls back to.
const defaultGuideId = "default";

/// Default changes nothing at all. It is the app exactly as it renders
/// without this feature, and it is here as a named thing so that "use the
/// plain one" is a choice a writer can make rather than an absence.
const _default = MarkdownStyleGuide(
  id: defaultGuideId,
  name: "Default",
  builtIn: true,
);

/// Article is for something meant to be read at length: generous line
/// height, clear space between paragraphs, headings that are quiet rather
/// than loud.
const _article = MarkdownStyleGuide(
  id: "article",
  name: "Article",
  builtIn: true,
  body: TextRule(lineHeight: 1.6),
  headings: [
    TextRule(scale: 1.9, lineHeight: 1.25, bold: true),
    TextRule(scale: 1.5, lineHeight: 1.3, bold: true),
    TextRule(scale: 1.25, lineHeight: 1.35, bold: true),
    TextRule(scale: 1.1, bold: true),
    TextRule(scale: 1.0, bold: true),
    TextRule(scale: 1.0, bold: true, ink: MarkdownInk.of(MarkdownRole.muted)),
  ],
  link: TextRule(ink: MarkdownInk.of(MarkdownRole.link), underline: true),
  quote: TextRule(italic: true, ink: MarkdownInk.of(MarkdownRole.muted)),
  blockGap: 16,
  listItemGap: 4,
  quoteBarInk: MarkdownInk.of(MarkdownRole.accent),
  quoteBarWidth: 3,
  image: ImageRule(widthPercent: 100, cornerRadius: 8, gap: 16),
);

/// Compact is the other direction: as much on the screen as will fit while
/// still being readable. For notes and lists rather than prose.
const _compact = MarkdownStyleGuide(
  id: "compact",
  name: "Compact",
  builtIn: true,
  body: TextRule(scale: 0.95, lineHeight: 1.25),
  headings: [
    TextRule(scale: 1.3, bold: true),
    TextRule(scale: 1.15, bold: true),
    TextRule(scale: 1.05, bold: true),
    TextRule(bold: true),
    TextRule(bold: true),
    TextRule(bold: true, ink: MarkdownInk.of(MarkdownRole.muted)),
  ],
  link: TextRule(ink: MarkdownInk.of(MarkdownRole.link)),
  blockGap: 4,
  listItemGap: 2,
  listIndent: 16,
  image: ImageRule(widthPercent: 60, gap: 4),
);

/// Terminal sets the whole post in the monospaced face, for anything that is
/// mostly command lines and output.
const _terminal = MarkdownStyleGuide(
  id: "terminal",
  name: "Terminal",
  builtIn: true,
  body: TextRule(font: MarkdownFont.mono, scale: 0.95, lineHeight: 1.4),
  headings: [
    TextRule(font: MarkdownFont.mono, scale: 1.4, bold: true),
    TextRule(font: MarkdownFont.mono, scale: 1.2, bold: true),
    TextRule(font: MarkdownFont.mono, scale: 1.1, bold: true),
    TextRule(font: MarkdownFont.mono, bold: true),
    TextRule(font: MarkdownFont.mono, bold: true),
    TextRule(font: MarkdownFont.mono, bold: true),
  ],
  link: TextRule(
      font: MarkdownFont.mono,
      ink: MarkdownInk.of(MarkdownRole.link),
      underline: true),
  quote: TextRule(font: MarkdownFont.mono),
  listBullet: TextRule(font: MarkdownFont.mono),
  blockGap: 10,
  listItemGap: 4,
  quoteBarInk: MarkdownInk.of(MarkdownRole.outline),
  image: ImageRule(widthPercent: 100, borderWidth: 1),
);

/// builtInGuides, in the order they are offered.
const builtInGuides = <MarkdownStyleGuide>[
  _default,
  _article,
  _compact,
  _terminal,
];

/// builtInGuideFor returns the guide with [id], or null when nothing ships
/// under that name.
MarkdownStyleGuide? builtInGuideFor(String id) {
  for (var guide in builtInGuides) {
    if (guide.id == id) return guide;
  }
  return null;
}
