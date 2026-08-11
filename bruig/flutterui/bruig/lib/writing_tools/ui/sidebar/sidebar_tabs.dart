import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/writing_tools/engine/preferences.dart';
import 'package:bruig/writing_tools/ui/sidebar/writing_sidebar.dart';
import 'package:flutter/material.dart';

// sidebar_tabs.dart is the row that switches the sidebar's pages, with the
// feature's own switch on the end of it.
//
// The page's name is not repeated above this row. The icons say which page is
// showing, and a title that only ever restates the selected icon is a line of
// the sidebar's height spent on nothing -- in a column where the height is
// what the content needs.
//
// The counts sit on the two pages that have them, because the reason to look
// at this row is usually to find out whether there is anything to look at --
// and a page with nothing on it should say so before it is opened, not after.
//
// The row is deliberately built from a different set of parts to the icon row
// above it, because for a long time it was built from the same ones: both drew
// the selected item as a filled secondaryContainer rectangle, so two
// navigations one on top of the other were saying "this is the current thing"
// in identical language, and neither read as subordinate to the other.
//
// Here the selection is a line rather than a block. Nothing is filled, the
// active tab is the accent colour with a rule under it, and the rule sits
// flush on the divider that closes the row -- which is what makes four labels
// read as tabs belonging to the panel below rather than as four more buttons.

// Taller than the content needs, and the extra is all above it. The shell
// closes its icon row with a divider, and with no padding here the tab icons
// sat directly on that rule with nothing between the two rows at all.
//
// The gap cannot be repeated underneath: the underline has to reach the
// divider that closes this row, and any padding below it would leave the
// indicator floating clear of the baseline it is meant to sit on. That
// asymmetry is what a tab row is -- space above, attached below, because the
// tab belongs to the panel beneath it rather than to the row above.
const double _rowHeight = 42;
const double _topSpace = 8;
const double _iconSize = 15;
const double _labelGap = 5;
const double _padding = 6;

/// _switchSpace is what the on/off control and its divider take out of the
/// row, reserved before the tabs are measured against what is left.
const double _switchSpace = 58;

/// _countSpace is room for a two-digit count beside a label. Reserved whether
/// or not there is one, so the tabs do not shuffle sideways as the numbers
/// come and go while typing.
const double _countSpace = 18;

class SidebarTabs extends StatelessWidget {
  final WritingSidebarPage current;
  final ValueChanged<WritingSidebarPage> onChanged;
  final WritingPreferences prefs;

  /// counts is the number to show beside a page, for the pages that have one.
  final Map<WritingSidebarPage, int> counts;

  const SidebarTabs({
    required this.current,
    required this.onChanged,
    required this.prefs,
    required this.counts,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var labelStyle = TextStyle(fontSize: 11.5, color: theme.colors.onSurface);
    return SizedBox(
      height: _rowHeight,
      child: LayoutBuilder(builder: (context, box) {
        var showLabels =
            _labelsFit(context, box.maxWidth - _switchSpace - 12, labelStyle);
        return Padding(
          // No bottom padding: the tab underline has to land on the divider
          // beneath this row, and a gap between them reads as two unrelated
          // lines rather than one selected tab.
          padding: const EdgeInsets.fromLTRB(8, _topSpace, 4, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var page in WritingSidebarPage.values)
              Expanded(
                child: _tab(
                    theme, page, counts[page] ?? 0, showLabels, labelStyle),
              ),
            // The switch keeps its place beside the results it governs --
            // turning the tools off from here is the obvious move when the
            // marks are in the way -- but it is not one of the tabs, and until
            // this divider existed it sat in the row looking like one.
            Center(
              child: Container(
                width: 1,
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: theme.colors.outlineVariant,
              ),
            ),
            // Centred rather than stretched: the row sets a height for the
            // tabs, and a switch told to fill it overflows -- Transform.scale
            // changes what is drawn and not what is laid out, so the size has
            // to come off the switch itself.
            Center(
              child: Tooltip(
                message: prefs.enabled ? "Turn writing tools off" : "Turn on",
                child: Transform.scale(
                  // Material's switch is built for a settings row and is half
                  // again the height of the row it now sits in.
                  scale: 0.7,
                  child: Switch(
                    value: prefs.enabled,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => prefs.enabled = v,
                  ),
                ),
              ),
            ),
          ]),
        );
      }),
    );
  }

  /// _labelsFit reports whether every tab can show its name across [width].
  ///
  /// Measured rather than assumed from a breakpoint. The panel is 260 wide by
  /// default and resizable well past that, the labels are words of very
  /// different lengths, and the text scale is the reader's to set -- so the
  /// question is genuinely "does this text fit in this space", and the only
  /// honest way to answer it is to lay the text out and look.
  bool _labelsFit(BuildContext context, double width, TextStyle style) {
    if (width <= 0) return false;
    var scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (var page in WritingSidebarPage.values) {
      var painter = TextPainter(
        text: TextSpan(text: page.short, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    var needed = widest + _iconSize + _labelGap + _padding * 2 + _countSpace;
    return width >= needed * WritingSidebarPage.values.length;
  }

  Widget _tab(ThemeNotifier theme, WritingSidebarPage page, int count,
      bool showLabel, TextStyle labelStyle) {
    var selected = page == current;
    var accent = theme.colors.primary;
    var colour = selected ? accent : theme.colors.onSurfaceVariant;

    Widget content;
    if (showLabel) {
      content = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(page.icon, size: _iconSize, color: colour),
        const SizedBox(width: _labelGap),
        Flexible(
          child: Text(
            page.short,
            overflow: TextOverflow.ellipsis,
            style: labelStyle.copyWith(
              color: colour,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        SizedBox(
          width: _countSpace,
          child: count == 0
              ? null
              : Text("  $count", style: TextStyle(fontSize: 10, color: colour)),
        ),
      ]);
    } else {
      // Too narrow for names. The underline still does the work the fill used
      // to, so the two navigations stay distinguishable at every width.
      content = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(page.icon, size: 17, color: colour),
        SizedBox(
          height: 12,
          child: count == 0
              ? null
              : Text("$count",
                  style: TextStyle(fontSize: 10, height: 1.2, color: colour)),
        ),
      ]);
    }

    return Tooltip(
      message: count > 0 ? "${page.title} ($count)" : page.title,
      child: InkWell(
        onTap: () => onChanged(page),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: _padding),
          decoration: BoxDecoration(
            border: Border(
              // Always present, transparent when unselected: a border that
              // appears only on the active tab changes the height of the
              // others, and the row twitches as the selection moves.
              bottom: BorderSide(
                  color: selected ? accent : Colors.transparent, width: 2),
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}
