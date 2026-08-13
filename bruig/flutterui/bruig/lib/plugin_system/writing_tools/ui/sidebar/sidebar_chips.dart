import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// sidebar_chips.dart is the two or three small pieces every page of the
// sidebar draws, kept together so the pages do not each grow their own
// slightly different version of them.

/// sidebarNote is the sidebar's way of saying nothing needs doing, or that
/// something is switched off. Muted and unemphatic on purpose: an empty page
/// is the good outcome and should not look like an error.
Widget sidebarNote(ThemeNotifier theme, String text) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text,
          style: TextStyle(fontSize: 12, color: theme.colors.onSurfaceVariant)),
    );

/// suggestionChip offers a replacement: the thing on the row that is meant to
/// be pressed, so it is the one that is filled in.
Widget suggestionChip(String label, VoidCallback onTap) => ActionChip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );

/// alternativeChip is a thesaurus word. [opposite] marks an antonym, because
/// an opposite is never a like-for-like swap and must not sit unlabelled among
/// words that are.
Widget alternativeChip(ThemeNotifier theme, String label, VoidCallback onTap,
        {bool opposite = false}) =>
    ActionChip(
      visualDensity: VisualDensity.compact,
      avatar: opposite
          ? Icon(Icons.swap_horiz,
              size: 14, color: theme.colors.onSurfaceVariant)
          : null,
      tooltip: opposite ? "Opposite meaning" : null,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
    );

/// dismissChip is a way out of an issue rather than a fix for it -- "ignore
/// this", "turn this off". Outlined rather than filled, so the chips that
/// change the text and the chips that stop it being mentioned do not look
/// alike on a row that carries both.
Widget dismissChip(ThemeNotifier theme, String label, VoidCallback onTap) =>
    ActionChip(
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.transparent,
      side: BorderSide(color: theme.colors.outlineVariant),
      label: Text(label,
          style: TextStyle(fontSize: 11, color: theme.colors.onSurfaceVariant)),
      onPressed: onTap,
    );
