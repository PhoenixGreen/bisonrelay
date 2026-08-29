import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_steps.dart is a page's title with something small beside it:
//
//   --steps[on=checkout]--
//   Shopping Cart
//   [Cart](/cart) | Checkout | Review | Pay
//   --/steps--
//
// A step written as a Markdown link is one you can go back to. Only the ones
// before the current one are live: going forward past a question you have not
// answered is the thing the sequence exists to prevent, and a step you are
// already on is not somewhere to go.
//
// Two lines: what this page is called, and the sequence it sits in. Written
// that way so a reader whose client does not know the marker sees the title
// and the steps as two ordinary lines, in the right order, rather than a
// table of key-value pairs.
//
// One block rather than a heading and a row of panels, because the thing
// being asked for is that they share a line. Markdown has no way to say that
// -- columns would put the trail at the top of the heading rather than
// beside it, and a header row scales its cells to a fixed height -- so the
// two are laid out here, where their sizes are both known.
//
// What it is for is the question that empties carts: how much more of this is
// there. Four words and a mark on the one you are on answers it in the space
// a heading was using anyway.
//
// The same block draws a chip instead of a trail:
//
//   --steps[chip=2 left, chipink=quoteBar]--
//   A guitar
//   --/steps--
//
// Which is a product's page saying how many are left. A different fact in the
// same shape -- one small thing pinned to the right of a title -- and the
// awkward part of both is the same: sharing a line with a heading, and
// getting out of the way when there is no room to.

/// Step is one word in the trail, and where it goes when it is behind you.
@immutable
class Step {
  final String label;

  /// target is where this step is, or empty for one nothing links to.
  final String target;

  const Step(this.label, [this.target = ""]);

  /// _link reads a step written as a Markdown link, so a client that does not
  /// know this block still shows a line of words with links in it.
  static final _link = RegExp(r'^\[([^\]]*)\]\(([^)]*)\)$');

  static Step parse(String written) {
    var m = _link.firstMatch(written.trim());
    if (m == null) return Step(written.trim());
    return Step((m.group(1) ?? "").trim(), (m.group(2) ?? "").trim());
  }
}

/// StepsRule is one trail.
@immutable
class StepsRule {
  final String title;
  final List<Step> steps;

  /// on is which step is the current one, matched against the step's own
  /// words, or -1 for a trail drawn with nothing marked.
  final int on;

  /// chip is a single bordered label pinned to the right of the title, in
  /// place of a trail, or empty for a title with no chip.
  final String chip;

  /// chipInk is the colour of its border and its writing, or null for the
  /// theme's own lines.
  final MarkdownInk? chipInk;

  const StepsRule({
    this.title = "",
    this.steps = const [],
    this.on = -1,
    this.chip = "",
    this.chipInk,
  });

  /// draws is whether there is anything to draw.
  bool get draws => title.isNotEmpty || steps.isNotEmpty || chip.isNotEmpty;

  static StepsRule parse(String? attributes, String body) {
    var fields = <String, String>{};
    for (var part in (attributes ?? "").split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      fields.putIfAbsent(part.substring(0, at).trim().toLowerCase(),
          () => part.substring(at + 1).trim());
    }

    var lines = body
        .split("\n")
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    var title = lines.isEmpty ? "" : lines.first;
    var steps = lines.length < 2
        ? <Step>[]
        : lines[1]
            .split("|")
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map(Step.parse)
            .toList();

    // Matched on the words rather than on a number, so a page that adds or
    // drops a step does not silently mark the wrong one.
    var want = (fields["on"] ?? "").trim().toLowerCase();
    var on = steps.indexWhere((s) => s.label.toLowerCase() == want);

    return StepsRule(
      title: title,
      steps: steps,
      on: on,
      chip: fields["chip"] ?? "",
      chipInk: _ink(fields["chipink"]),
    );
  }

  /// _ink reads a colour written as one of the guide's role names.
  static MarkdownInk? _ink(String? value) {
    var written = value?.trim() ?? "";
    if (written.isEmpty) return null;
    for (var role in MarkdownRole.values) {
      if (role.name.toLowerCase() == written.toLowerCase()) {
        return MarkdownInk.of(role);
      }
    }
    var ink = MarkdownInk.fromJson(written);
    return ink.isInherit ? null : ink;
  }
}

class StepsBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--steps(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/steps--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var lines = <String>[];
    while (!parser.isDone) {
      if (_close.hasMatch(parser.current.content)) {
        parser.advance();
        break;
      }
      lines.add(parser.current.content);
      parser.advance();
    }

    var element = md.Element.text("steps", "");
    element.attributes["body"] = lines.join("\n");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, for the reason every other block here is: this
    // renderer treats only a fixed list of tags as blocks.
    return md.Element("p", [element]);
  }
}

class StepsMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownSteps(
        rule: StepsRule.parse(
            element.attributes["attrs"], element.attributes["body"] ?? ""),
      );
}

/// MarkdownSteps draws it.
class MarkdownSteps extends StatelessWidget {
  final StepsRule rule;
  const MarkdownSteps({required this.rule, super.key});

  /// _step draws one word of the trail.
  ///
  /// Behind you and linked, it is something to press: the way back to a step
  /// you have already answered, in place of a row of links at the bottom of
  /// the page saying the same thing twice. Ahead of you it is a word --
  /// going forward past a question you have not answered is what the
  /// sequence exists to prevent.
  Widget _step(BuildContext context, ThemeNotifier theme, TextStyle base,
      Step step, int i, Color muted, Color accent) {
    if (i == rule.on) {
      return Text(step.label,
          style: base.copyWith(color: accent, fontWeight: FontWeight.w600));
    }

    var behind = rule.on >= 0 && i < rule.on;
    if (!behind || step.target.isEmpty) {
      return Text(step.label, style: base.copyWith(color: muted));
    }

    return InkWell(
      onTap: () => followMarkdownLink(context, step.target),
      child: Text(step.label, style: theme.markdownLinkStyle(base)),
    );
  }

  /// _foldBelow is the width under which the trail drops beneath the title.
  ///
  /// Side by side, the title takes what it needs and the trail takes the
  /// rest. In a chat-width window there is no rest: four words and three
  /// separators do not fit beside a heading, and squeezing them wraps the
  /// trail into a block that is taller than the title it was meant to sit
  /// beside.
  static const double _foldBelow = 520;

  @override
  Widget build(BuildContext context) {
    if (!rule.draws) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);

    var guide = theme.markdownGuide;
    var base =
        Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);

    // The page's own h1, so the title is set exactly as the heading it
    // replaces. A trail beside a title in a different face is two headings.
    var titleStyle = theme.markdownTextStyle(guide.headings.first, base);
    var muted = theme.markdownInk(const MarkdownInk.of(MarkdownRole.muted)) ??
        theme.colors.onSurfaceVariant;
    var accent = theme.markdownInk(const MarkdownInk.of(MarkdownRole.accent)) ??
        theme.colors.primary;

    var title = rule.title.isEmpty
        ? const SizedBox.shrink()
        : Text(rule.title, style: titleStyle);

    if (rule.steps.isEmpty && rule.chip.isEmpty) {
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: title);
    }

    // Wrap rather than Row: the trail is words, and words that will not fit
    // on one line belong on two rather than clipped or ellipsised. Nothing
    // in it is pressable, so nothing is lost by it moving.
    Widget trail = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < rule.steps.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text("›", style: base.copyWith(color: muted)),
            ),
          _step(context, theme, base, rule.steps[i], i, muted, accent),
        ],
      ],
    );

    Widget? chip;
    if (rule.chip.isNotEmpty) {
      var ink =
          (rule.chipInk == null ? null : theme.markdownInk(rule.chipInk!)) ??
              theme.colors.outlineVariant;
      chip = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: ink),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          rule.chip,
          style: base.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth.isFinite &&
            constraints.maxWidth < _foldBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              title,
              const SizedBox(height: 4),
              // Folded, whatever sits on the right reads left to right under
              // the title: a line pushed to the right edge of a narrow window
              // looks like something that fell off the end.
              Align(
                alignment: Alignment.centerLeft,
                child: chip ??
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: (trail as Wrap).children,
                    ),
              ),
            ],
          );
        }

        // A chip belongs to the title, so it follows it.
        //
        // Pushed to the far edge it read as a second thing on the line
        // rather than as a remark about the name it is next to -- and on a
        // wide page there is a lot of nothing in between for it to be read
        // across. The trail is the opposite: it is about the page rather
        // than about the title, and it goes to the edge.
        if (chip != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: title),
              const SizedBox(width: 12),
              chip,
            ],
          );
        }

        // Both loose, so each takes what it needs and gives way when the
        // other cannot fit; spaceBetween is what pushes the trail to the
        // right edge without a Spacer stealing the room it needs.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: title),
            const SizedBox(width: 16),
            Flexible(child: trail),
          ],
        );
      }),
    );
  }
}
