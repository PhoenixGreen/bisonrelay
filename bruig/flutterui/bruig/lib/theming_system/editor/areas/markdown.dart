import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/editor/areas/sample_image.dart';
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

/// _sampleFor is the markdown the preview renders for one element.
///
/// Each carries a line of ordinary body text as well, because nearly every
/// setting is expressed relative to the body -- a heading at 190% means
/// nothing without the 100% beside it.
String _sampleFor(_Element element) => switch (element) {
      _Element.text => """
# Heading one
Ordinary body text, which is what every other size is measured against. This
paragraph runs long enough to wrap, so the line height has somewhere to show.

A second paragraph, so the space between them is visible.
## Heading two
### Heading three
#### Heading four
##### Heading five
###### Heading six
""",
      _Element.links => """
Body text with [a link](https://decred.org) in the middle of it, and
[another](https://bisonrelay.org) further along.
""",
      _Element.quotes => """
Body text before the quotation.

> A quotation, which shows the bar and the background.
> It runs to a second line so the bar's full height can be seen.

Body text after it.
""",
      _Element.code => """
Body text with `inline code` in it.

```
a fenced block
a second line, for the padding
```
""",
      _Element.lists => """
Body text before the list.

- The first item
- The second item, long enough to wrap onto another line so the indent shows
- The third item

1. A numbered item
2. Another
""",
      _Element.rule => """
Body text above the rule.

---

Body text below it.
""",
      // A real embed, drawn rather than described: the width is a share of
      // the column and the corners, border and spacing are drawn around it,
      // none of which can be judged from a sentence.
      _Element.images => """
Body text above the picture.

${sampleImageMarkdown ?? ""}

Body text below it, so the spacing has something to push against.
""",
    };

/// _Element is which part of a post is being tuned.
///
/// One at a time, picked from a dropdown, for the same reason the Buttons
/// area does it: ten elements' worth of sliders stacked up reads as one
/// undifferentiated wall, and only one of them is being adjusted anyway.
/// Which one is showing is local to the editor and is not stored on a theme.
enum _Element {
  text("Text and headings"),
  links("Links"),
  quotes("Quotes"),
  code("Code"),
  lists("Lists"),
  rule("Horizontal rule"),
  images("Images");

  final String label;
  const _Element(this.label);
}

List<Widget> markdownAreaEditor(AreaEditorContext ctx) =>
    [_MarkdownEditor(ctx)];

class _MarkdownEditor extends StatefulWidget {
  final AreaEditorContext ctx;
  const _MarkdownEditor(this.ctx);

  @override
  State<_MarkdownEditor> createState() => _MarkdownEditorState();
}

class _MarkdownEditorState extends State<_MarkdownEditor> {
  _Element element = _Element.text;

  @override
  void initState() {
    super.initState();
    // Prepared once, not per frame: this page rebuilds on every drag of
    // every slider.
    if (sampleImageMarkdown == null) {
      var seed = ThemeNotifier.of(context, listen: false)
          .surfaceColor(SurfaceColor.primary);
      prepareSampleImage(seed).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    var ctx = widget.ctx;
    var style = ctx.style;
    var chosen = builtInGuideFor(style.markdownGuideId) == null
        ? defaultGuideId
        : style.markdownGuideId;
    var guide = style.markdownGuide(builtInGuideFor(chosen));

    /// edit changes one rule of the guide.
    ///
    /// A built-in is never changed: the first edit to one forks it into a
    /// guide of the reader's own and every edit after goes to the fork. The
    /// built-ins are what a published post names, so an "Article" quietly
    /// edited here would make a post naming it mean something different on
    /// this machine than on anyone else's.
    void edit(MarkdownStyleGuide Function(MarkdownStyleGuide) change) {
      var next = change(guide.builtIn ? guide.forked("custom") : guide);
      ctx.setStyle((s) => s.copyWith(markdownCustomGuide: next.toJson()));
    }

    var choices = style.markdownGuideChoices(builtInGuides);
    var unsaved = style.markdownCustomGuide != null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: ctx.choice<String>(
            "Style guide",
            value: choices.any((g) => g.id == chosen) ? chosen : defaultGuideId,
            options: [for (var g in choices) g.id],
            labelOf: (id) => choices
                .firstWhere((g) => g.id == id, orElse: () => choices.first)
                .name,
            onChanged: (v) => ctx.setStyle((s) =>
                s.copyWith(markdownGuideId: v, clearMarkdownCustomGuide: true)),
          ),
        ),
        // Save appears only when there is something unsaved to save, and
        // Delete only on a guide that can be deleted -- a built-in cannot,
        // because it is the same everywhere by definition.
        if (unsaved)
          IconButton(
            tooltip: "Save as a style guide of your own",
            icon: const Icon(Icons.save_outlined, size: 20),
            onPressed: () => _askToSave(ctx, guide),
          ),
        if (!guide.builtIn &&
            !unsaved &&
            style.markdownSavedGuides.containsKey(chosen))
          IconButton(
            tooltip: "Delete this style guide",
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _delete(ctx, chosen),
          ),
      ]),
      ctx.note(unsaved
          ? "Unsaved changes. They are in use already -- save them to keep "
              "them under a name of their own, or choose a guide above to "
              "start again from that one."
          : "How posts are set on this device. Changing anything below "
              "starts a guide of your own; the built-in ones are left as "
              "they are."),
      const SizedBox(height: 16),
      ctx.choice<_Element>(
        "Element",
        value: element,
        options: _Element.values,
        labelOf: (e) => e.label,
        onChanged: (e) => setState(() => element = e),
      ),
      const SizedBox(height: 12),
      // The preview sits between the picker and the settings, so a change
      // and its effect are next to each other rather than a scroll apart.
      _MarkdownPreview(element: element),
      const SizedBox(height: 16),
      ..._settingsFor(ctx, guide, edit),
    ]);
  }

  /// _textControls are the five every text rule has.
  List<Widget> _textControls(
    AreaEditorContext ctx,
    String name,
    TextRule rule,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit,
    MarkdownStyleGuide Function(MarkdownStyleGuide, TextRule) put, {
    double maxScale = 3.0,
  }) =>
      [
        ctx.slider("md-$name-scale", rule.scale,
            label: (v) => "Size: ${(v * 100).round()}% of body text",
            min: 0.6,
            max: maxScale,
            divisions: ((maxScale - 0.6) * 20).round(),
            onCommit: (v) => edit((g) => put(g, rule.copyWith(scale: v)))),
        ctx.choice<MarkdownRole?>(
          "Colour",
          value: rule.ink.role,
          options: [null, ...MarkdownRole.values],
          labelOf: (r) => r?.label ?? "Theme default",
          onChanged: (r) => edit((g) => put(
              g,
              rule.copyWith(
                  ink: r == null ? MarkdownInk.inherit : MarkdownInk.of(r)))),
        ),
        ctx.choice<MarkdownFont>(
          "Font",
          value: rule.font,
          options: MarkdownFont.values,
          labelOf: (f) => f.label,
          onChanged: (f) => edit((g) => put(g, rule.copyWith(font: f))),
        ),
        ctx.toggle("Bold",
            value: rule.bold ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(bold: v)))),
        ctx.toggle("Italic",
            value: rule.italic ?? false,
            onChanged: (v) => edit((g) => put(g, rule.copyWith(italic: v)))),
      ];

  /// _askToSave names the working copy and puts it in the library.
  void _askToSave(AreaEditorContext ctx, MarkdownStyleGuide guide) async {
    var controller =
        TextEditingController(text: guide.name.replaceAll(" (edited)", ""));
    var name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Save style guide"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: "Name"),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text("Save")),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    // A fresh id each time, so saving twice under different names keeps both
    // rather than the second quietly replacing the first.
    var id = "guide-${DateTime.now().microsecondsSinceEpoch}";
    var saved = guide.copyWith(id: id, name: name.trim());
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides, id: saved.toJson()},
          markdownGuideId: id,
          clearMarkdownCustomGuide: true,
        ));
  }

  void _delete(AreaEditorContext ctx, String id) {
    ctx.setStyle((s) => s.copyWith(
          markdownSavedGuides: {...s.markdownSavedGuides}..remove(id),
          markdownGuideId: defaultGuideId,
          clearMarkdownCustomGuide: true,
        ));
  }

  /// _inkPick is the editor's own palette dropdown, bound to a guide colour.
  ///
  /// The same control every other area uses, which shows a swatch beside
  /// each slot. The plain text dropdown this replaces named colours without
  /// showing any of them, and offered a short list of roles rather than the
  /// palette the rest of the theme is built from.
  ///
  /// The built-in guides still use roles, which adapt to whatever theme they
  /// are read in. Picking here replaces that with a slot from this palette:
  /// a specific colour, chosen deliberately, which is what reaching for the
  /// picker means. It follows the palette when that is edited, because the
  /// slot is stored beside the colour.
  Widget _inkPick(AreaEditorContext ctx, String label, MarkdownInk current,
          ValueChanged<MarkdownInk> onChanged) =>
      ctx.colorPick(
        label,
        value: current.resolve(ctx.theme.markdownRoleColor,
            paletteColor: ctx.theme.markdownPaletteColor),
        valueIndex: current.paletteIndex,
        noneLabel: "Theme default",
        onChanged: (color, index) => onChanged(color == null
            ? MarkdownInk.inherit
            : MarkdownInk.literal(color, paletteIndex: index)),
      );

  List<Widget> _settingsFor(
    AreaEditorContext ctx,
    MarkdownStyleGuide guide,
    void Function(MarkdownStyleGuide Function(MarkdownStyleGuide)) edit,
  ) {
    List<Widget> ink(String label, MarkdownInk current,
            MarkdownStyleGuide Function(MarkdownStyleGuide, MarkdownInk) put) =>
        [
          _inkPick(ctx, label, current, (i) => edit((g) => put(g, i))),
        ];

    switch (element) {
      case _Element.text:
        return [
          ctx.note("Body text. Everything else is a share of this size."),
          ..._textControls(
              ctx, "body", guide.body, edit, (g, r) => g.copyWith(body: r),
              maxScale: 2.0),
          ctx.slider("md-body-line", guide.body.lineHeight ?? 1.4,
              label: (v) => "Line height: ${v.toStringAsFixed(2)}",
              min: 0.9,
              max: 3.0,
              divisions: 21,
              onCommit: (v) => edit(
                  (g) => g.copyWith(body: g.body.copyWith(lineHeight: v)))),
          ctx.slider("md-blockgap", guide.blockGap,
              label: (v) => "Space between paragraphs: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) => edit((g) => g.copyWith(blockGap: v))),
          const SizedBox(height: 16),
          const Txt.M("Headings"),
          ctx.note("Each level, as a share of the body text size above."),
          for (var i = 0; i < 6; i++)
            ctx.slider("md-h${i + 1}", guide.headings[i].scale,
                label: (v) => "H${i + 1}: ${(v * 100).round()}%",
                min: 0.6,
                max: 3.0,
                divisions: 48,
                onCommit: (v) => edit((g) => g.copyWith(headings: [
                      for (var j = 0; j < 6; j++)
                        j == i
                            ? g.headings[j].copyWith(scale: v)
                            : g.headings[j]
                    ]))),
          ctx.note("Colour, font and weight apply to every level."),
          ..._textControls(
                  ctx,
                  "head",
                  guide.headings[0],
                  edit,
                  (g, r) => g.copyWith(headings: [
                        for (var h in g.headings)
                          h.copyWith(
                              ink: r.ink,
                              font: r.font,
                              bold: r.bold,
                              italic: r.italic)
                      ]))
              // The per-level sliders above already cover size.
              .skip(1),
        ];

      case _Element.links:
        return [
          ..._textControls(
              ctx, "link", guide.link, edit, (g, r) => g.copyWith(link: r),
              maxScale: 2.0),
          ctx.toggle("Underline",
              value: guide.link.underline ?? false,
              onChanged: (v) =>
                  edit((g) => g.copyWith(link: g.link.copyWith(underline: v)))),
        ];

      case _Element.quotes:
        return [
          ..._textControls(
              ctx, "quote", guide.quote, edit, (g, r) => g.copyWith(quote: r),
              maxScale: 2.0),
          ...ink("Bar colour", guide.quoteBarInk,
              (g, i) => g.copyWith(quoteBarInk: i)),
          ctx.slider("md-quotebar", guide.quoteBarWidth,
              label: (v) => v == 0 ? "Bar: None" : "Bar width: ${v.round()}px",
              max: 12,
              divisions: 12,
              onCommit: (v) => edit((g) => g.copyWith(quoteBarWidth: v))),
          ...ink("Background", guide.quoteBackground,
              (g, i) => g.copyWith(quoteBackground: i)),
        ];

      case _Element.code:
        return [
          ..._textControls(
              ctx, "code", guide.code, edit, (g, r) => g.copyWith(code: r),
              maxScale: 2.0),
          ...ink("Block background", guide.codeBackground,
              (g, i) => g.copyWith(codeBackground: i)),
        ];

      case _Element.lists:
        return [
          ..._textControls(ctx, "bullet", guide.listBullet, edit,
              (g, r) => g.copyWith(listBullet: r),
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
        ];

      case _Element.rule:
        return [
          ...ink("Colour", guide.ruleInk, (g, i) => g.copyWith(ruleInk: i)),
          ctx.slider("md-rule", guide.ruleThickness,
              label: (v) => "Thickness: ${v.toStringAsFixed(1)}px",
              min: 0.5,
              max: 8,
              divisions: 15,
              onCommit: (v) => edit((g) => g.copyWith(ruleThickness: v))),
        ];

      case _Element.images:
        return [
          ctx.slider("md-img-width", guide.image.boundedWidth,
              label: (v) => "Width: ${v.round()}% of the column",
              min: 10,
              max: 100,
              divisions: 18,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(widthPercent: v)))),
          ctx.slider("md-img-radius", guide.image.boundedRadius,
              label: (v) =>
                  v == 0 ? "Corners: Square" : "Corners: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(cornerRadius: v)))),
          ctx.slider("md-img-border", guide.image.boundedBorder,
              label: (v) => v == 0 ? "Border: None" : "Border: ${v.round()}px",
              max: 8,
              divisions: 8,
              onCommit: (v) => edit(
                  (g) => g.copyWith(image: g.image.copyWith(borderWidth: v)))),
          ...ink("Border colour", guide.image.borderInk,
              (g, i) => g.copyWith(image: g.image.copyWith(borderInk: i))),
          ctx.slider("md-img-gap", guide.image.gap,
              label: (v) => "Space above and below: ${v.round()}px",
              max: 48,
              divisions: 24,
              onCommit: (v) =>
                  edit((g) => g.copyWith(image: g.image.copyWith(gap: v)))),
          ctx.choice<MarkdownAlign>(
            "Alignment",
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
                edit((g) => g.copyWith(image: g.image.copyWith(align: a))),
          ),
        ];
    }
  }
}

/// _MarkdownPreview renders the sample in the chosen guide.
///
/// The whole reason this page exists before an editor for making guides
/// does: whether the vocabulary is the right one is a question you answer by
/// looking at it, not by reading a list of properties.
class _MarkdownPreview extends StatelessWidget {
  /// element decides what the sample contains.
  ///
  /// A sample showing everything at once means the part being adjusted is
  /// somewhere in the middle of it, and a slider's effect has to be hunted
  /// for. Showing the element being tuned -- with a line of body text around
  /// it for scale, since almost every setting is relative to that -- makes
  /// the change the obvious thing on screen.
  final _Element element;

  const _MarkdownPreview({required this.element});

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
        // No guide passed: the preview shows what this theme renders,
        // which is the reader's own guide once they have edited one. Naming
        // a built-in here is what made every edit look like it did nothing.
        MarkdownArea(_sampleFor(element), false, key: ValueKey(element)),
      ]),
    );
  }
}
