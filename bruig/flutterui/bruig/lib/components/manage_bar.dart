import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// manageContentBarItems returns the Manage Content submenu's tabs, for use
// with SecondarySideMenuLayout (see containers.dart).
List<ListTile> manageContentBarItems(Function tabChange, int selectedIndex) {
  return [
    ListTile(
        selected: selectedIndex == 0,
        title: const Txt.S("Add"),
        onTap: () => tabChange(0)),
    ListTile(
        selected: selectedIndex == 1,
        title: const Txt.S("Shared"),
        onTap: () => tabChange(1)),
    ListTile(
        selected: selectedIndex == 2,
        title: const Txt.S("Downloads"),
        onTap: () => tabChange(2)),
  ];
}
