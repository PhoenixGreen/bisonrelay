import 'package:bruig/components/containers.dart';
import 'package:bruig/screens/pages/browser.dart';
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
// "Site Settings" rather than "My Site": with a preview of your own site
// open beside it, two tabs called some arrangement of "site" is one tab too
// many to tell apart. This one is where the site is set up; the other is the
// site itself.
const List<String> pagesTabLabels = ["Visit", "Site Settings", "Store"];

// pagesBarItems returns the Pages submenu's tabs, for use with
// SecondarySideMenuLayout (see containers.dart).
//
// Store is always here, including when no store is being hosted: it is where
// one is set up, so hiding it until one exists would leave no way to make one.
//
// Three destinations and nothing else. Open pages used to be listed here as
// well, because the browser filled the content area and choosing a tab was
// the only way out of it. The browser is the Visit area now, with its own
// tab strip, so the pages are reachable from where they are read and the
// sidebar has nothing to say about them.
List<SidebarNavItem> pagesBarItems(Function tabChange, int selectedIndex) {
  return [
    SidebarNavItem(
        icon: sectionIcon(pagesTabVisit),
        selected: selectedIndex == pagesTabVisit,
        label: pagesTabLabels[pagesTabVisit],
        onTap: () => tabChange(pagesTabVisit)),
    SidebarNavItem(
        icon: sectionIcon(pagesTabMySite),
        selected: selectedIndex == pagesTabMySite,
        label: pagesTabLabels[pagesTabMySite],
        onTap: () => tabChange(pagesTabMySite)),
    SidebarNavItem(
        icon: sectionIcon(pagesTabStore),
        selected: selectedIndex == pagesTabStore,
        label: pagesTabLabels[pagesTabStore],
        onTap: () => tabChange(pagesTabStore)),
  ];
}

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
