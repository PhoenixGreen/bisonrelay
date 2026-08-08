import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_field.dart is how the marks get onto the text.
//
// Flutter can do this itself, through SpellCheckConfiguration, and this used
// to. Two things it cannot do ended that:
//
//   - It carries a single misspelledTextStyle for every flagged span, so a
//     wordiness suggestion would be marked exactly like a misspelling. The
//     whole point of the severity contract is that they are not the same and
//     must not look the same.
//
//   - It re-runs the check only when the *text* changes. Adding a word to the
//     dictionary or turning a rule off changes the answer without touching a
//     character, so the old mark sat there until the next keystroke. Working
//     around that took a scope widget that reached down the element tree for
//     the EditableTextState, compared what it held against what it should
//     hold, and wrote the results back by hand -- plus a key on the field to
//     force a rebuild when checking was switched on, because
//     spellCheckConfiguration is read once in initState and never again.
//
// All of that is gone. A controller composes the styled text itself, and
// because it reads the capability from the context it is handed at paint
// time, every change that could alter the answer already rebuilds it. There
// is nothing to keep in sync, so nothing can fall out of sync.

/// WritingTextEditingController is a TextEditingController that underlines
/// what the writing capability finds.
///
/// A composer swaps `TextEditingController()` for this and changes nothing
/// else. With no provider enabled it behaves exactly like the plain one.
/// InlineDecoration is styling for one stretch of the text, supplied by
/// whatever is using the field rather than by the writing tools.
///
/// It exists so a composer can render its own markup -- headings, bold, an
/// embedded image -- without this file knowing anything about markdown, and
/// without a second controller competing with this one to paint the same
/// characters.
class InlineDecoration {
  final int start;
  final int end;

  /// style is merged under the writing marks, so a misspelling inside a
  /// heading keeps its red underline and the heading keeps its size.
  final TextStyle style;

  /// widget replaces the decorated characters when it is set.
  ///
  /// It may only ever stand for exactly one character. Flutter counts a
  /// WidgetSpan as a single character when it maps the caret onto the text,
  /// so a widget covering more than one puts every offset after it out of
  /// step -- clicks land in the wrong place and selection drifts. Anything
  /// longer has to be hidden by style instead.
  final Widget? widget;

  const InlineDecoration(this.start, this.end, this.style, {this.widget});
}

class WritingTextEditingController extends TextEditingController {
  WritingTextEditingController({super.text, this.decorations});

  /// decorations is asked for the caller's own styling on every build, so a
  /// composer that switches between a raw and a rendered view only has to
  /// change what this returns.
  final List<InlineDecoration> Function(String text)? decorations;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // watch, not read: this runs during the field's build, so depending on
    // the capability here is what repaints the text when the word list
    // arrives, when a word is added to the dictionary, or when the whole
    // feature is switched off. It is the entire synchronisation mechanism.
    var capability = context.watch<SpellcheckCapability?>();

    // An active composing region means an IME is mid-word -- a dead key, or a
    // character being assembled. Flutter marks that region with its own
    // underline, and text that is still being formed is not text worth
    // checking, so the default rendering is left alone until it settles.
    var extra = decorations?.call(text) ?? const <InlineDecoration>[];

    if (value.isComposingRangeValid && withComposing) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }

    var issues = capability?.review(text) ?? const <WritingIssue>[];
    if (issues.isEmpty && extra.isEmpty) {
      return capability == null
          ? super.buildTextSpan(
              context: context, style: style, withComposing: withComposing)
          : TextSpan(style: style, text: text);
    }

    return TextSpan(
        style: style, children: _decorate(text, issues, extra, style));
  }
}

/// _decorate cuts [text] into runs and gives each the style of whichever
/// issue covers it.
///
/// Mistakes win over suggestions where the two overlap, which they often do:
/// a long-sentence suggestion covers a whole sentence, and every misspelling
/// inside it has to keep its own red mark rather than being repainted blue.
/// Within each kind the issues are already disjoint -- review() sees to that
/// -- so the only contest is between the two kinds.
List<InlineSpan> _decorate(String text, List<WritingIssue> issues,
    List<InlineDecoration> extra, TextStyle? style) {
  // Every offset where the styling could change, so the text can be walked
  // once rather than searched per issue.
  var boundaries = <int>{0, text.length};
  for (var issue in issues) {
    if (issue.range.start < 0 || issue.range.end > text.length) continue;
    boundaries.add(issue.range.start);
    boundaries.add(issue.range.end);
  }
  for (var decoration in extra) {
    if (decoration.start < 0 || decoration.end > text.length) continue;
    boundaries.add(decoration.start);
    boundaries.add(decoration.end);
  }
  var points = boundaries.toList()..sort();

  var spans = <InlineSpan>[];
  for (var i = 0; i < points.length - 1; i++) {
    var start = points[i];
    var end = points[i + 1];
    if (start >= end) continue;

    // The caller's styling first, so the writing marks land on top of it.
    TextStyle? beneath = style;
    Widget? widget;
    for (var decoration in extra) {
      if (decoration.start > start || decoration.end < end) continue;
      beneath = beneath?.merge(decoration.style) ?? decoration.style;
      if (decoration.widget != null) widget = decoration.widget;
    }

    // Guarded rather than trusted: a widget standing for more than one
    // character would silently misplace every caret position after it, and
    // the wrong text going out is a worse outcome than a missing picture.
    if (widget != null && end - start == 1) {
      spans.add(
          WidgetSpan(child: widget, alignment: PlaceholderAlignment.middle));
      continue;
    }

    WritingIssue? covering;
    for (var issue in issues) {
      if (issue.range.start > start || issue.range.end < end) continue;
      // First one found unless a mistake turns up later, which outranks it.
      if (covering == null ||
          (!covering.kind.isMistake && issue.kind.isMistake)) {
        covering = issue;
      }
    }

    spans.add(TextSpan(
      text: text.substring(start, end),
      style: covering == null
          ? beneath
          : beneath?.merge(SpellcheckCapability.styleFor(covering.kind)) ??
              SpellcheckCapability.styleFor(covering.kind),
    ));
  }
  return spans;
}
