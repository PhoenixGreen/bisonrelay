import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// The app draws two quite different things with the same Tooltip widget.
//
// Most of them label a control that a regular user already recognises --
// the icon for a new post, an avatar, the app icon. Those are useful while
// you're learning the app and pure noise once you aren't, which is what
// AreaStyle.hideTooltips (on the master area) turns off wholesale.
//
// A few genuinely explain something that isn't visible anywhere else: the
// help icon beside "Cost" when publishing content, say. Hiding those is a
// separate decision, so they're wrapped in HelpTooltip, which opts out of
// the blanket setting and follows hideHelpTooltips instead.
//
// Both work through Flutter's own TooltipVisibility, so nothing has to be
// threaded through the widgets in between: an enclosing TooltipVisibility
// switches off every Tooltip below it, and a nearer one wins.

// AppTooltips wraps the whole app, applying the blanket setting.
class AppTooltips extends StatelessWidget {
  final Widget child;
  const AppTooltips({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var style = theme.areaStyle(ThemeArea.masterBackground);
      return TooltipVisibility(visible: !style.hideTooltips, child: child);
    });
  }
}

// HelpTooltip is a Tooltip on something whose whole purpose is to be
// hovered -- a help/question-mark icon. It reads hideHelpTooltips rather
// than hideTooltips, in both directions: hiding the labels leaves these
// alone, and hiding these leaves the labels alone.
class HelpTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  const HelpTooltip({required this.message, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      var style = theme.areaStyle(ThemeArea.masterBackground);
      return TooltipVisibility(
        visible: !style.hideHelpTooltips,
        child: Tooltip(message: message, child: child),
      );
    });
  }
}
