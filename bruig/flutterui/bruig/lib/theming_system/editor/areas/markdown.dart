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

/// _describeImages is the guide's picture rules in words.
///
/// The preview cannot show them: it renders a sample with no embed in it,
/// and an embed is a piece of a real post rather than something that can be
/// written into a sample string. So the settings are stated instead, and the
/// composer's own preview is where they are actually seen.
String _describeImages(ImageRule image) {
  var parts = <String>["${image.boundedWidth.round()}% width"];
  if (image.boundedRadius > 0) {
    parts.add("${image.boundedRadius.round()}px corners");
  }
  if (image.boundedBorder > 0) {
    parts.add("${image.boundedBorder.round()}px border");
  }
  if (image.align != MarkdownAlign.left &&
      image.align != MarkdownAlign.inherit) {
    parts.add(image.align.name);
  }
  parts.add("${image.gap.round()}px above and below");
  return parts.join(", ");
}

List<Widget> markdownAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  var guides = builtInGuides;
  var chosen = guides.any((g) => g.id == style.markdownGuideId)
      ? style.markdownGuideId
      : defaultGuideId;

  return [
    ctx.choice<String>(
      "Style guide",
      value: chosen,
      options: [for (var guide in guides) guide.id],
      labelOf: (id) => guides.firstWhere((g) => g.id == id).name,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(markdownGuideId: v)),
    ),
    ctx.note("How posts are set on this device. Default changes nothing and "
        "is the app as it renders without a guide."),
    ctx.toggle(
      "Let a post choose its guide",
      subtitle: "A published post can name the guide it was written in. With "
          "this off, posts are always read in your own choice above -- and "
          "with it on, a guide you do not have still falls back to yours",
      value: style.markdownHonourPostGuide,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(markdownHonourPostGuide: v)),
    ),
    ctx.note("Images: "
        "${_describeImages(builtInGuideFor(chosen)!.image)}"),
    const SizedBox(height: 12),
    _MarkdownPreview(guideId: chosen),
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
