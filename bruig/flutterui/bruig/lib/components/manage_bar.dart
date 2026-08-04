import 'package:bruig/components/containers.dart';
import 'package:flutter/material.dart';

// manageContentBarItems returns the Manage Content submenu's tabs, for use
// with SecondarySideMenuLayout (see containers.dart).
List<SidebarNavItem> manageContentBarItems(
    Function tabChange, int selectedIndex) {
  return [
    SidebarNavItem(
        icon: Icons.add_circle_outline,
        selected: selectedIndex == 0,
        label: "Add",
        onTap: () => tabChange(0)),
    SidebarNavItem(
        icon: Icons.folder_shared_outlined,
        selected: selectedIndex == 1,
        label: "Shared",
        onTap: () => tabChange(1)),
    SidebarNavItem(
        icon: Icons.download_outlined,
        selected: selectedIndex == 2,
        label: "Downloads",
        onTap: () => tabChange(2)),
  ];
}
