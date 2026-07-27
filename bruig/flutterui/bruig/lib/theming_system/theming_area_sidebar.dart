import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_sidebar.dart is the "Sidebar" area's own settings. They apply
// to every sidebar in the app (Settings, LN Management, Feed, Manage
// Content, Address Book, page-view sessions, the chat list, and the Realtime
// Chat session list), not just one screen.
//
// The sidebar's Background "Default" is the "Sidebar Background" palette
// slot, read live (see SecondarySideMenu in containers.dart), so leaving it
// on Default means it stays edited from the Color Palette section instead.
List<Widget> sidebarAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  var visibility = style.subMenuStyle ?? SubMenuStyle.alwaysVisible;
  return [
    ctx.choice<SubMenuStyle>(
      "Visibility",
      value: visibility,
      options: SubMenuStyle.values,
      labelOf: subMenuStyleLabel,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(subMenuStyle: v)),
    ),
    if (visibility == SubMenuStyle.hoverReveal)
      ctx.toggle(
        "Show hover arrow",
        value: style.showHoverArrow,
        compact: true,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(showHoverArrow: v)),
      ),
    const SizedBox(height: 8),
    ctx.slider("sidebarCornerRadius", style.sidebarCornerRadius,
        label: (v) => "List Rounded Corners: ${v.toStringAsFixed(1)}",
        max: 24,
        onCommit: (v) =>
            ctx.setStyle((s) => s.copyWith(sidebarCornerRadius: v))),
    ctx.toggle(
      "Show icons",
      subtitle: "Leading icon on each row -- applies to every sidebar in "
          "the app",
      value: style.sidebarShowIcons,
      compact: true,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(sidebarShowIcons: v)),
    ),
    ctx.toggle(
      "Show right-edge divider",
      value: style.sidebarShowRightDivider,
      compact: true,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(sidebarShowRightDivider: v)),
    ),
    if (style.sidebarShowRightDivider) ...[
      ctx.colorPick(
        "Divider color",
        value: style.resolveSidebarDividerColor(ctx.theme),
        valueIndex: style.sidebarDividerColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearSidebarDividerColor: true,
                clearSidebarDividerColorIndex: true)
            : s.copyWith(
                sidebarDividerColor: c,
                sidebarDividerColorIndex: i,
                clearSidebarDividerColorIndex: i == null)),
      ),
      ctx.slider("sidebarDividerWidth", style.sidebarDividerWidth,
          label: (v) => "Divider width: ${v.toStringAsFixed(1)}",
          min: 0.5,
          max: 6,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(sidebarDividerWidth: v))),
    ],
  ];
}
