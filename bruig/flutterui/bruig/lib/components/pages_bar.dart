import 'package:bruig/components/containers.dart';
import 'package:flutter/material.dart';

// Pages tabs. Visit is first because it is what the section is for most of
// the time: reading someone else's site. My Site and Store are the authoring
// half, and Store only appears when one is being hosted.
const int pagesTabVisit = 0;
const int pagesTabMySite = 1;
const int pagesTabStore = 2;

// pagesTabLabels are the tab names by index. Kept beside the items below so
// the heading can name the open tab without needing PagesModel -- the
// heading is built in places that have no running client.
const List<String> pagesTabLabels = ["Visit", "My Site", "Store"];

// pagesBarItems returns the Pages submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart).
List<SidebarNavItem> pagesBarItems(
    Function tabChange, int selectedIndex, bool hasStore) {
  return [
    SidebarNavItem(
        icon: Icons.travel_explore_outlined,
        selected: selectedIndex == pagesTabVisit,
        label: pagesTabLabels[pagesTabVisit],
        onTap: () => tabChange(pagesTabVisit)),
    SidebarNavItem(
        icon: Icons.web_outlined,
        selected: selectedIndex == pagesTabMySite,
        label: pagesTabLabels[pagesTabMySite],
        onTap: () => tabChange(pagesTabMySite)),
    if (hasStore)
      SidebarNavItem(
          icon: Icons.storefront_outlined,
          selected: selectedIndex == pagesTabStore,
          label: pagesTabLabels[pagesTabStore],
          onTap: () => tabChange(pagesTabStore)),
  ];
}
