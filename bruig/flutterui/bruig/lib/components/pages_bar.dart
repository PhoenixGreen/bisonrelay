import 'package:bruig/components/containers.dart';
import 'package:flutter/material.dart';

// Pages tabs. Visit is first because it is what the section is for most of
// the time: reading someone else's site. My Site and Store are the authoring
// half.
const int pagesTabVisit = 0;
const int pagesTabMySite = 1;
const int pagesTabStore = 2;

// pagesTabLabels are the tab names by index. Kept beside the items below so
// the heading can name the open tab without needing PagesModel -- the
// heading is built in places that have no running client.
const List<String> pagesTabLabels = ["Visit", "My Site", "Store"];

// pagesBarItems returns the Pages submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart).
//
// Store is always here, including when no store is being hosted: it is where
// one is set up, so hiding it until one exists would leave no way to make one.
//
// [openPages] is how many pages are open, and [onResume] the way back to
// them. One entry, not one per page: switching between open pages is the tab
// strip's job, above the address bar, where a browser puts it. What the
// sidebar has to answer is narrower -- a tab was chosen, the page is still
// open, and there has to be a way back to it.
List<SidebarNavItem> pagesBarItems(
  Function tabChange,
  int selectedIndex, {
  int openPages = 0,
  String openLabel = "",
  VoidCallback? onResume,
  bool browsing = false,
}) {
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
    SidebarNavItem(
        icon: Icons.storefront_outlined,
        selected: selectedIndex == pagesTabStore,
        label: pagesTabLabels[pagesTabStore],
        onTap: () => tabChange(pagesTabStore)),
    if (openPages > 0 && onResume != null)
      SidebarNavItem(
        icon: Icons.article_outlined,
        // A tab is not the current thing while a page is being read.
        selected: browsing,
        label: openPagesLabel(openPages, openLabel),
        onTap: onResume,
      ),
  ];
}

/// openPagesLabel names the way back into the browser.
///
/// One page is named, because there is a particular page to go back to.
/// Several are counted, because which one is a choice made in the strip
/// rather than here.
String openPagesLabel(int count, String only) =>
    count == 1 ? only : "$count pages";

/// openPageLabel names an open page, for a tab in the strip or for the
/// sidebar's way back to a single one.
String openPageLabel(String nick, List<String> path) {
  var rest = path.where((e) => e.isNotEmpty).toList();
  // The front page is the site itself, so it is named by whose it is.
  if (rest.isEmpty || (rest.length == 1 && rest.first == "index.md")) {
    return nick;
  }
  var last = rest.last;
  if (last.endsWith(".md")) last = last.substring(0, last.length - 3);
  return "$nick / $last";
}
