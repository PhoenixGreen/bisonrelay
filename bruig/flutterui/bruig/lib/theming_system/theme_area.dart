// ThemeArea identifies a distinct visual region of the app that can carry its
// own background/border override, independent of the global color scheme.
// Each area's own settings live in a theming_area_<name>.dart editor file;
// the fields they drive all live on AreaStyle (see area_style.dart).
enum ThemeArea {
  masterBackground,
  loginScreen,
  header,
  navBar,
  subMenuTabBar,
  chat,
  feed,
  realtimeChat,
  lnManagement,
  pages,
  manageContent,
  stats,
  logs,
}

const Map<ThemeArea, String> _themeAreaLabels = {
  ThemeArea.masterBackground: "Master",
  ThemeArea.loginScreen: "Login Screen",
  ThemeArea.header: "Header",
  ThemeArea.navBar: "Navigation Bar",
  ThemeArea.subMenuTabBar: "Sidebar",
  ThemeArea.chat: "Chat",
  ThemeArea.feed: "Feed",
  ThemeArea.realtimeChat: "Realtime Chat",
  ThemeArea.lnManagement: "LN Management",
  ThemeArea.pages: "Pages",
  ThemeArea.manageContent: "Manage Content",
  ThemeArea.stats: "Stats",
  ThemeArea.logs: "Logs",
};

String themeAreaLabel(ThemeArea area) => _themeAreaLabels[area]!;

// ContentAlign controls where an area's primary content sits (the header's
// title, and the nav bar's logo). hidden removes the content entirely, and
// is only meaningful for the header -- the nav bar logo has its own
// visibility toggle (AreaStyle.showLogo).
enum ContentAlign { start, center, end, hidden }

const Map<ContentAlign, String> _contentAlignLabels = {
  ContentAlign.start: "Left",
  ContentAlign.center: "Center",
  ContentAlign.end: "Right",
  ContentAlign.hidden: "Remove",
};

String contentAlignLabel(ContentAlign a) => _contentAlignLabels[a]!;
