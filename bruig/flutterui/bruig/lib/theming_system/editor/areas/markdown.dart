import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// markdown.dart is the "Markdown" area's settings: which style guide posts
// are read in, and whether a post may ask for a different one.
//
// A style guide is a named set of rules for how a post's headings, quotes,
// code, lists and pictures are set -- see model/markdown_style.dart. It is
// always local. A post carries the name of one and never the guide itself,
// so a name this device has never heard of falls back to Default rather than
// arriving with anything to apply.

/// _sample is what the preview is rendered from.
///
/// Chosen to exercise the things a guide actually changes -- two heading
/// levels, a quote, a list, inline and block code, a link and a rule -- so
/// the differences between the built-ins are visible rather than described.
const _sample = """
# A heading

Ordinary text, with a [link](https://example.com), some **bold** and a little
`inline code`.

## A smaller heading

> A quotation, which is where a guide's bar and spacing show up most.

- The first item
- The second item

```
a block of code
```

---
""";

List<Widget> markdownAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  var custom = style.markdownCustomGuide != null;
  var chosen = builtInGuideFor(style.markdownGuideId) == null
      ? defaultGuideId
      : style.markdownGuideId;
  // What is actually rendered with: the reader's own guide if they have
  // edited one, otherwise the built-in they picked.
  var guide = style.markdownGuide(builtInGuideFor(chosen));

  /// edit changes one rule of the guide.
  ///
  /// A built-in is never changed: the first edit to one forks it into a
  /// guide of the reader's own and every edit after that goes to the fork.
  /// The built-ins have to be identical everywhere, because they are what a
  /// published post names -- an "Article" quietly edited on one machine
  /// would make a post naming it mean something different there.
  void edit(MarkdownStyleGuide Function(MarkdownStyleGuide) change) {
    var next = change(guide.builtIn ? guide.forked("custom") : guide);
    ctx.setStyle((s) => s.copyWith(markdownCustomGuide: next.toJson()));
  }

  /// text is the six controls every text rule has.
  List<Widget> text(String name, TextRule rule,
          MarkdownStyleGuide Function(MarkdownStyleGuide, TextRule) put,
          {double maxScale = 3.0}) =>
      [
        ctx.slider(
          "md-$name-scale",
          rule.scale,
          label: (v) => "$name size: ${(v * 100).round()}% of body text",
          min: 0.6,
          max: maxScale,
          divisions: ((maxScale - 0.6) * 20).round(),
          onCommit: (v) => edit((g) => put(g, rule.copyWith(scale: v))),
        ),
        ctx.choice<MarkdownRole?>(
          "$name colour",
          value: rule.ink.role,
          options: [null, ...MarkdownRole.values],
          labelOf: (r) => r?.label ?? "Theme default",
          onChanged: (r) => edit((g) => put(
              g,
              rule.copyWith(
                  ink: r == null ? MarkdownInk.inherit : MarkdownInk.of(r)))),
        ),
        ctx.choice<MarkdownFont>(
          "$name font",
          value: rule.font,
          options: MarkdownFont.values,
          labelOf: (f) => f.label,
          onChanged: (f) => edit((g) => put(g, rule.copyWith(font: f))),
        ),
        ctx.toggle("$name bold",
            value: rule.bold ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(bold: v)))),
        ctx.toggle("$name italic",
            value: rule.italic ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(italic: v)))),
      ];

  return [
    ctx.choice<String>(
      "Style guide",
      value: chosen,
      options: [for (var g in builtInGuides) g.id],
      labelOf: (id) => builtInGuides.firstWhere((g) => g.id == id).name,
      onChanged: (v) => ctx.setStyle((s) =>
          s.copyWith(markdownGuideId: v, clearMarkdownCustomGuide: true)),
    ),
    ctx.note(custom
        ? "You have changed this guide, so posts are set with your version "
            "of it. Choosing a guide above starts again from that one."
        : "How posts are set on this device. Changing anything below starts "
            "a guide of your own -- the built-in ones stay as they are, "
            "because they are what a published post can name."),
    ctx.toggle(
      "Let a post choose its guide",
      subtitle: "A published post can name the guide it was written in. With "
          "this off, posts are always read in your own choice above -- and "
          "with it on, a guide you do not have still falls back to yours",
      value: style.markdownHonourPostGuide,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(markdownHonourPostGuide: v)),
    ),
    const SizedBox(height: 12),
    _MarkdownPreview(guideId: chosen),
    const SizedBox(height: 16),
    const Txt.M("Body text"),
    ...text("Body", guide.body, (g, r) => g.copyWith(body: r), maxScale: 2.0),
    ctx.slider("md-body-line", guide.body.lineHeight ?? 1.4,
        label: (v) => "Line height: ${v.toStringAsFixed(2)}",
        min: 0.9,
        max: 3.0,
        divisions: 21,
        onCommit: (v) =>
            edit((g) => g.copyWith(body: guide.body.copyWith(lineHeight: v)))),
    ctx.slider("md-blockgap", guide.blockGap,
        label: (v) => "Space between paragraphs: ${v.round()}px",
        max: 48,
        divisions: 24,
        onCommit: (v) => edit((g) => g.copyWith(blockGap: v))),
    const SizedBox(height: 16),
    const Txt.M("Headings"),
    ctx.note("Each level, as a share of the body text size."),
    for (var i = 0; i < 6; i++)
      ctx.slider("md-h${i + 1}", guide.headings[i].scale,
          label: (v) => "H${i + 1}: ${(v * 100).round()}%",
          min: 0.6,
          max: 3.0,
          divisions: 48,
          onCommit: (v) => edit((g) => g.copyWith(headings: [
                for (var j = 0; j < 6; j++)
                  j == i ? g.headings[j].copyWith(scale: v) : g.headings[j]
              ]))),
    ...text("Heading", guide.headings[0],
        (g, r) => g.copyWith(headings: [r, ...g.headings.skip(1)])),
    const SizedBox(height: 16),
    const Txt.M("Links"),
    ...text("Link", guide.link, (g, r) => g.copyWith(link: r), maxScale: 2.0),
    ctx.toggle("Underline links",
        value: guide.link.underline ?? false,
        onChanged: (v) =>
            edit((g) => g.copyWith(link: guide.link.copyWith(underline: v)))),
    const SizedBox(height: 16),
    const Txt.M("Quotes"),
    ...text("Quote", guide.quote, (g, r) => g.copyWith(quote: r),
        maxScale: 2.0),
    ctx.choice<MarkdownRole?>(
      "Quote bar colour",
      value: guide.quoteBarInk.role,
      options: [null, ...MarkdownRole.values],
      labelOf: (r) => r?.label ?? "Theme default",
      onChanged: (r) => edit((g) => g.copyWith(
          quoteBarInk: r == null ? MarkdownInk.inherit : MarkdownInk.of(r))),
    ),
    ctx.slider("md-quotebar", guide.quoteBarWidth,
        label: (v) => v == 0 ? "Quote bar: None" : "Quote bar: ${v.round()}px",
        max: 12,
        divisions: 12,
        onCommit: (v) => edit((g) => g.copyWith(quoteBarWidth: v))),
    const SizedBox(height: 16),
    const Txt.M("Code"),
    ...text("Code", guide.code, (g, r) => g.copyWith(code: r), maxScale: 2.0),
    const SizedBox(height: 16),
    const Txt.M("Lists"),
    ...text("Bullet", guide.listBullet, (g, r) => g.copyWith(listBullet: r),
        maxScale: 2.0),
    ctx.slider("md-listgap", guide.listItemGap,
        label: (v) => "Space between items: ${v.round()}px",
        max: 32,
        divisions: 16,
        onCommit: (v) => edit((g) => g.copyWith(listItemGap: v))),
    ctx.slider("md-listindent", guide.listIndent,
        label: (v) => "Indent: ${v.round()}px",
        min: 8,
        max: 64,
        divisions: 14,
        onCommit: (v) => edit((g) => g.copyWith(listIndent: v))),
    const SizedBox(height: 16),
    const Txt.M("Horizontal rule"),
    ctx.choice<MarkdownRole?>(
      "Rule colour",
      value: guide.ruleInk.role,
      options: [null, ...MarkdownRole.values],
      labelOf: (r) => r?.label ?? "Theme default",
      onChanged: (r) => edit((g) => g.copyWith(
          ruleInk: r == null ? MarkdownInk.inherit : MarkdownInk.of(r))),
    ),
    ctx.slider("md-rule", guide.ruleThickness,
        label: (v) => "Thickness: ${v.toStringAsFixed(1)}px",
        min: 0.5,
        max: 8,
        divisions: 15,
        onCommit: (v) => edit((g) => g.copyWith(ruleThickness: v))),
    const SizedBox(height: 16),
    const Txt.M("Images"),
    ctx.slider("md-img-width", guide.image.boundedWidth,
        label: (v) => "Width: ${v.round()}% of the column",
        min: 10,
        max: 100,
        divisions: 18,
        onCommit: (v) => edit(
            (g) => g.copyWith(image: guide.image.copyWith(widthPercent: v)))),
    ctx.slider("md-img-radius", guide.image.boundedRadius,
        label: (v) => v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
        max: 48,
        divisions: 24,
        onCommit: (v) => edit(
            (g) => g.copyWith(image: guide.image.copyWith(cornerRadius: v)))),
    ctx.slider("md-img-border", guide.image.boundedBorder,
        label: (v) => v == 0 ? "Border: None" : "Border: ${v.round()}px",
        max: 8,
        divisions: 8,
        onCommit: (v) => edit(
            (g) => g.copyWith(image: guide.image.copyWith(borderWidth: v)))),
    ctx.choice<MarkdownRole?>(
      "Image border colour",
      value: guide.image.borderInk.role,
      options: [null, ...MarkdownRole.values],
      labelOf: (r) => r?.label ?? "Theme default",
      onChanged: (r) => edit((g) => g.copyWith(
          image: guide.image.copyWith(
              borderInk: r == null ? MarkdownInk.inherit : MarkdownInk.of(r)))),
    ),
    ctx.slider("md-img-gap", guide.image.gap,
        label: (v) => "Space above and below: ${v.round()}px",
        max: 48,
        divisions: 24,
        onCommit: (v) =>
            edit((g) => g.copyWith(image: guide.image.copyWith(gap: v)))),
    ctx.choice<MarkdownAlign>(
      "Image alignment",
      value: guide.image.align == MarkdownAlign.inherit
          ? MarkdownAlign.left
          : guide.image.align,
      options: const [
        MarkdownAlign.left,
        MarkdownAlign.center,
        MarkdownAlign.right
      ],
      labelOf: (a) => switch (a) {
        MarkdownAlign.center => "Center",
        MarkdownAlign.right => "Right",
        _ => "Left",
      },
      onChanged: (a) =>
          edit((g) => g.copyWith(image: guide.image.copyWith(align: a))),
    ),
  ];
}

/// _MarkdownPreview renders the sample in the chosen guide.
///
/// The whole reason this page exists before an editor for making guides
/// does: whether the vocabulary is the right one is a question you answer by
/// looking at it, not by reading a list of properties.
class _MarkdownPreview extends StatelessWidget {
  final String guideId;
  const _MarkdownPreview({required this.guideId});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfaceColor(SurfaceColor.surfaceContainerLow),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.S("Preview", color: TextColor.onSurfaceVariant),
        const SizedBox(height: 8),
        // Keyed by the guide so switching rebuilds rather than reusing the
        // element tree with a stale stylesheet.
        MarkdownArea(_sample, false, key: ValueKey(guideId), guideId: guideId),
      ]),
    );
  }
}
