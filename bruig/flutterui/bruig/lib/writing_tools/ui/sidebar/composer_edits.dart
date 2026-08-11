import 'package:bruig/writing_tools/engine/writing_issue.dart';
import 'package:flutter/widgets.dart';

// composer_edits.dart is the one place the sidebar writes back to the field.
//
// Every page of the sidebar ends in the same action -- swap this span for
// that text -- and each of them used to do it itself, with its own bounds
// check and its own caret arithmetic. They did not agree: one verified the
// span still held what it did when the list was built and one did not, which
// is exactly the check that matters, because a list of issues is a set of
// offsets into text the writer may have kept typing into.

/// ComposerEdits applies a sidebar's choices to the composer under review.
///
/// The controller is nullable for the frame or two while a composer is being
/// rebuilt -- see ComposerSidebarController.visible -- and every method here
/// is a no-op in that state rather than the caller's problem.
class ComposerEdits {
  final TextEditingController? controller;
  const ComposerEdits(this.controller);

  /// text is what the field holds right now, which is not necessarily what the
  /// list on screen was built from.
  String get text => controller?.text ?? "";

  TextSelection get selection =>
      controller?.selection ?? const TextSelection.collapsed(offset: -1);

  /// applyToIssue replaces one issue's span, leaving the caret after it.
  ///
  /// The text is re-read here rather than taken from when the list was built:
  /// applying one fix shifts every later issue's offsets, and the list the
  /// user is looking at may already be one edit stale. A span whose text no
  /// longer matches is left alone rather than spliced blindly.
  void applyToIssue(WritingIssue issue, String replacement) => replaceRange(
        issue.range.start,
        issue.range.end,
        replacement,
        expected: issue.text,
      );

  /// replaceRange swaps [start]..[end] for [replacement].
  ///
  /// [expected] is what that span held when the choice was offered. Passing it
  /// is what stops a stale offset rewriting whatever now occupies it.
  void replaceRange(int start, int end, String replacement,
      {String? expected}) {
    var editor = controller;
    if (editor == null) return;
    var text = editor.text;
    if (start < 0 || end > text.length || start > end) return;
    if (expected != null && text.substring(start, end) != expected) return;

    editor.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }
}
