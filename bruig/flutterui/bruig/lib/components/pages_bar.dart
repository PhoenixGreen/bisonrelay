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
// [openPages] are the pages currently open, each its own entry below the
// tabs. Pages are kept rather than replaced, so several can be open at once
// and moving to a tab does not close the one being read -- reading somebody's
// site and going to check a setting used to mean losing the page, since the
// browser was the only thing the content area would show.
List<SidebarNavItem> pagesBarItems(
  Function tabChange,
  int selectedIndex, {
  List<OpenPageItem> openPages = const [],
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
    for (var page in openPages)
      SidebarNavItem(
        icon: Icons.article_outlined,
        // Only one entry can be current, and a tab is not it while a page
        // is being read.
        selected: browsing && page.current,
        label: page.label,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 14),
          tooltip: "Close ${page.label}",
          onPressed: page.onClose,
          visualDensity: VisualDensity.compact,
        ),
        onTap: page.onOpen,
      ),
  ];
}

/// OpenPageItem is one open page, for the sidebar.
class OpenPageItem {
  /// label is who is being read, and what of theirs -- "alice" for a front
  /// page, "alice / about" for anything else. The nick alone is not enough
  /// once two pages of the same person's are open.
  final String label;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  const OpenPageItem({
    required this.label,
    required this.current,
    required this.onOpen,
    required this.onClose,
  });
}

/// openPageLabel names an open page for the sidebar.
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
