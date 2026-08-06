import 'package:bruig/plugin_system/capabilities/spellcheck.dart';
import 'package:bruig/plugin_system/capabilities/spellcheck_actions.dart';
import 'package:bruig/plugin_system/capabilities/thesaurus_menu.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// writing_popup.dart is the whole right-click experience for a text field the
// writing capabilities are attached to: one call from a composer, and the
// menu it opens is either an explanation of what is wrong or the ordinary
// menu, depending on what was clicked.
//
// It replaces the menu rather than adding to it, but only where that trade
// pays. A list of bare replacement words tells someone *what* to change and
// never *why*, which is no use at all to the person likeliest to right-click:
// the one who does not already know the rule. The explanation needs room a
// menu row does not have.
//
// The ordinary entries are not lost to that -- the composer passes them in
// and they are laid along the bottom -- so nothing a right-click used to do
// stops working when a word happens to be flagged.

/// _popupWidth is fixed rather than sized to fit. The explanation is a
/// paragraph, and a popup that grew and shrank with the length of each one
/// would jump around the screen as it moved between issues.
const double _popupWidth = 320;

/// _popupMaxHeight bounds a word with several issues, or several meanings.
/// Past this the content scrolls inside the popup.
const double _popupMaxHeight = 360;

/// writingContextMenu builds a composer's selection toolbar.
///
/// It returns the explanatory popup when the selection is on something
/// flagged, and the ordinary menu otherwise -- with [fallbackItems] as its
/// contents and a lookup entry appended when a provider can answer for the
/// selected word.
///
/// A composer calls this and passes the entries it would have shown itself.
/// Nothing about which plugin is enabled, or whether any is, reaches the
/// composer.
Widget writingContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  required List<ContextMenuButtonItem> fallbackItems,
}) {
  var issues = issuesAtSelection(context, editableTextState);
  if (issues.isNotEmpty) {
    return _WritingPopup(
      editableTextState: editableTextState,
      issues: issues,
      otherItems: fallbackItems,
    );
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      ...fallbackItems,
      // Whatever an enabled plugin capability adds; empty when none does,
      // which is why nothing here names one.
      ...thesaurusContextMenuItems(context, editableTextState),
    ],
  );
}

class _WritingPopup extends StatelessWidget {
  final EditableTextState editableTextState;
  final List<WritingIssue> issues;
  final List<ContextMenuButtonItem> otherItems;

  const _WritingPopup({
    required this.editableTextState,
    required this.issues,
    required this.otherItems,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var anchors = editableTextState.contextMenuAnchors;

    // Flutter's own delegate rather than arithmetic here. It decides whether
    // the popup fits above the selection and clamps it to the screen -- which
    // is what keeps a popup opened near the right-hand edge on screen instead
    // of pushed off it.
    return CustomSingleChildLayout(
      delegate: TextSelectionToolbarLayoutDelegate(
        anchorAbove: anchors.primaryAnchor,
        anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      ),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        color: theme.colors.surfaceContainerHigh,
        child: SizedBox(
          width: _popupWidth,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _popupMaxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < issues.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1),
                            ),
                          _issue(context, theme, issues[i]),
                        ],
                      ],
                    ),
                  ),
                ),
                if (otherItems.isNotEmpty) _footer(context, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _issue(BuildContext context, ThemeNotifier theme, WritingIssue issue) {
    var muted = TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(
            issue.kind == WritingIssueKind.spelling
                ? Icons.spellcheck
                : Icons.edit_note,
            size: 15,
            color: theme.colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(issue.title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
        // The message is shown under the title only when it says something
        // the title does not. For a rule with no category the two are the
        // same string, and printing it twice reads as a mistake.
        if (issue.message != issue.title)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(issue.message, style: muted),
          ),
        if (issue.explanation.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(issue.explanation, style: muted.copyWith(height: 1.35)),
          ),
        if (issue.suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var suggestion in issue.suggestions.take(maxCorrections))
                  _correction(theme, suggestion, () {
                    applyCorrection(editableTextState, issue.range, suggestion,
                        expected: issue.text);
                  }),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _actions(context, theme, issue),
          ),
        ),
      ],
    );
  }

  /// _actions are the ways out of an issue that are not a correction: stop
  /// flagging this word, or stop running this check at all.
  List<Widget> _actions(
      BuildContext context, ThemeNotifier theme, WritingIssue issue) {
    var capability = context.read<SpellcheckCapability?>();
    if (capability == null) return const [];
    var prefs = capability.preferences;

    // No refresh afterwards: the field paints from the capability, and
    // changing a preference rebuilds it in the same frame.
    void act(VoidCallback change) {
      editableTextState.hideToolbar();
      change();
    }

    if (issue.checkId != null) {
      return [
        _action(theme, "Turn off this check", () {
          act(() =>
              prefs.disableCheck(issue.checkId!, description: issue.message));
        }),
      ];
    }
    return [
      _action(
          theme, "Ignore once", () => act(() => prefs.ignoreOnce(issue.text))),
      _action(theme, "Add to dictionary",
          () => act(() => prefs.addToDictionary(issue.text))),
    ];
  }

  Widget _correction(ThemeNotifier theme, String label, VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: theme.colors.primaryContainer,
        side: BorderSide.none,
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colors.onPrimaryContainer)),
        onPressed: onTap,
      );

  Widget _action(ThemeNotifier theme, String label, VoidCallback onTap) =>
      ActionChip(
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: theme.colors.outlineVariant),
        label: Text(label,
            style:
                TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
        onPressed: onTap,
      );

  /// _footer carries the entries the composer would have shown on its own, so
  /// replacing the menu costs nothing that was there before.
  Widget _footer(BuildContext context, ThemeNotifier theme) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.colors.outlineVariant)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Wrap(
          children: [
            for (var item in otherItems)
              TextButton(
                onPressed: () {
                  // Ordering matters: several of these read the selection,
                  // which hiding the toolbar can collapse.
                  item.onPressed?.call();
                  editableTextState.hideToolbar();
                },
                child: Text(
                  // Flutter's own labels, so "Paste" reads as it does in
                  // every other menu and is translated where the app is.
                  AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      );
}
