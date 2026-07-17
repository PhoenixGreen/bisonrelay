import 'package:bruig/components/containers.dart';
import 'package:flutter/material.dart';

// lnManagementBarItems returns the LN Management submenu's tabs, for use
// with SecondarySideMenuLayout (see containers.dart).
List<SidebarNavItem> lnManagementBarItems(
    Function tabChange, int selectedIndex) {
  return [
    SidebarNavItem(
        icon: Icons.dashboard_outlined,
        selected: selectedIndex == 0,
        label: "Overview",
        onTap: () => tabChange(0)),
    SidebarNavItem(
        icon: Icons.account_balance_wallet_outlined,
        selected: selectedIndex == 1,
        label: "Accounts",
        onTap: () => tabChange(1)),
    SidebarNavItem(
        icon: Icons.link,
        selected: selectedIndex == 2,
        label: "On-Chain",
        onTap: () => tabChange(2)),
    SidebarNavItem(
        icon: Icons.hub_outlined,
        selected: selectedIndex == 3,
        label: "Channels",
        onTap: () => tabChange(3)),
    SidebarNavItem(
        icon: Icons.swap_horiz,
        selected: selectedIndex == 4,
        label: "Payments",
        onTap: () => tabChange(4)),
    SidebarNavItem(
        icon: Icons.public,
        selected: selectedIndex == 5,
        label: "Network",
        onTap: () => tabChange(5)),
    SidebarNavItem(
        icon: Icons.backup_outlined,
        selected: selectedIndex == 6,
        label: "Backups",
        onTap: () => tabChange(6)),
  ];
}
