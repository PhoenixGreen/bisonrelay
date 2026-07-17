import 'package:bruig/components/containers.dart';
import 'package:flutter/material.dart';

// feedBarItems returns the Feed submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart).
List<SidebarNavItem> feedBarItems(Function tabChange, int selectedIndex) {
  return [
    SidebarNavItem(
        icon: Icons.dynamic_feed_outlined,
        label: "Feed",
        selected: selectedIndex == 0,
        onTap: () => tabChange(0, null)),
    SidebarNavItem(
        icon: Icons.article_outlined,
        label: "Your Posts",
        selected: selectedIndex == 1,
        onTap: () => tabChange(1, null)),
    SidebarNavItem(
        icon: Icons.subscriptions_outlined,
        label: "Subscriptions",
        selected: selectedIndex == 2,
        onTap: () => tabChange(2, null)),
    SidebarNavItem(
        icon: Icons.add_circle_outline,
        label: "New Post",
        selected: selectedIndex == 3,
        onTap: () => tabChange(3, null)),
  ];
}
