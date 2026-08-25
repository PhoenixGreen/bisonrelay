import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// store_tabs.dart is the row along the top of the Store section.
//
// The shop had one long page: hosting, then the order book, then the
// catalogue, then the pages it renders. Each of those is a different job --
// answering somebody, adding a product, changing how the front page looks --
// and stacking them meant scrolling past two of them to reach the third.
//
// The tabs are a view of one screen rather than four screens: what is being
// edited stays open behind them, so opening Orders to answer a question does
// not throw away a half-written product.

enum StoreTabKind {
  products("Products", Icons.sell_outlined),
  orders("Orders", Icons.receipt_long_outlined),
  assets("Pictures", Icons.image_outlined),
  templates("Pages", Icons.description_outlined);

  final String label;
  final IconData icon;
  const StoreTabKind(this.label, this.icon);
}

/// StoreTabs is the row of tabs, with a count beside the one that has
/// something waiting.
class StoreTabs extends StatelessWidget {
  final StoreTabKind current;
  final ValueChanged<StoreTabKind> onChanged;

  /// needsAnswer is how many orders have been written on and not answered.
  /// Shown on the tab, so a seller looking at the catalogue can see there
  /// is a question waiting without going to look.
  final int needsAnswer;

  const StoreTabs({
    super.key,
    required this.current,
    required this.onChanged,
    this.needsAnswer = 0,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var kind in StoreTabKind.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: OutlinedButton(
              onPressed: () => onChanged(kind),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    kind == current ? theme.colors.surfaceContainerHighest : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kind.icon, size: 15),
                const SizedBox(width: 6),
                Txt.S(kind.label,
                    color: kind == current
                        ? TextColor.onSurface
                        : TextColor.onSurfaceVariant),
                if (kind == StoreTabKind.orders && needsAnswer > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Txt.S("$needsAnswer",
                        color: TextColor.onPrimary),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    );
  }
}
