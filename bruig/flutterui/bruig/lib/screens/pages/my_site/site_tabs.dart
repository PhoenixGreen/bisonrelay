import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// site_tabs.dart is the row along the top of Site Settings.
//
// The same three jobs the shop's tabs separate, for the same reason: the
// pages of a site, the fragments they share, and the pictures they show are
// different things to be doing, and one long page meant scrolling past two
// of them to reach the third.

enum SiteTabKind {
  pages("Pages", Icons.article_outlined),
  fragments("Fragments", Icons.extension_outlined),
  pictures("Pictures", Icons.image_outlined);

  final String label;
  final IconData icon;
  const SiteTabKind(this.label, this.icon);
}

/// SiteTabs is the row of tabs, with a count beside the pages that have been
/// written since they were last published.
class SiteTabs extends StatelessWidget {
  final SiteTabKind current;
  final ValueChanged<SiteTabKind> onChanged;

  /// unpublished is how many pages a visitor is reading an older version of.
  /// Shown on the tab, because that is the thing somebody would want to
  /// know without going to look.
  final int unpublished;

  const SiteTabs({
    super.key,
    required this.current,
    required this.onChanged,
    this.unpublished = 0,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var kind in SiteTabKind.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton(
              onPressed: () => onChanged(kind),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
                backgroundColor: kind == current
                    ? theme.colors.surfaceContainerHighest
                    : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kind.icon, size: 15),
                const SizedBox(width: 6),
                Txt.S(kind.label,
                    color: kind == current
                        ? TextColor.onSurface
                        : TextColor.onSurfaceVariant),
                if (kind == SiteTabKind.pages && unpublished > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Txt.S("$unpublished", color: TextColor.onPrimary),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    );
  }
}
