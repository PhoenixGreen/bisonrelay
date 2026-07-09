import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

// feedBarItems returns the Feed submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart).
List<ListTile> feedBarItems(Function tabChange, int selectedIndex) {
  return [
    ListTile(
        title: Txt.S("Feed"),
        selected: selectedIndex == 0,
        onTap: () => tabChange(0, null)),
    ListTile(
        title: const Txt.S("Your Posts"),
        selected: selectedIndex == 1,
        onTap: () => tabChange(1, null)),
    ListTile(
        title: const Txt.S("Subscriptions"),
        selected: selectedIndex == 2,
        onTap: () => tabChange(2, null)),
    ListTile(
        title: const Txt.S("New Post"),
        selected: selectedIndex == 3,
        onTap: () => tabChange(3, null)),
  ];
}
