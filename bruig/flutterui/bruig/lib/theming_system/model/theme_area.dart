// ThemeArea identifies a distinct visual region of the app that can carry its
// own background/border override, independent of the global color scheme.
// Each area's own settings live in a editor/areas/<name>.dart editor file;
// the fields they drive all live on AreaStyle (see area_style.dart).
enum ThemeArea {
  masterBackground,
  loginScreen,
  header,
  navBar,
  // dualPanel is a page's sidebar and content taken together, as one
  // region -- a border on it goes round the outside of both. Every page
  // route is wrapped in it (see OverviewScreen's route builder), which is
  // why the individual pages below no longer carry a background/border of
  // their own.
  dualPanel,
  subMenuTabBar,
  contentArea,
  // inputAreas is every text input in the app taken together -- the chat
  // composer, the feed's post/comment boxes, the search bars -- so they
  // can be given one background, border and corner radius instead of each
  // screen deciding for itself.
  inputAreas,
  // buttons is every button in the app taken together, split into the five
  // roles it actually ships (see ButtonRole) rather than by which screen
  // they sit on -- the same five appearances recur across the login screen,
  // the feed and LN management.
  buttons,
  chat,
  feed,
  realtimeChat,
  account,
  lnManagement,
  pages,
  // manageContent is the Manage screen -- listed as "File Manager", since
  // that's what its pages are (shared files, downloads). It kept its
  // original enum name so presets saved before it had settings of its own
  // still read back into it.
  manageContent,
  stats,
  logs,
  // settingsPages is the Settings screen's own pages -- Account, Stats and
  // Logs -- edited as one entry rather than three. account/stats/logs above
  // are kept only so a preset saved before that can still be read and
  // migrated across (see ThemePreset.fromJson); nothing renders from them.
  settingsPages,
  // mobile is the narrow-screen layout -- chiefly its bottom navigation
  // bar, which is the nav bar's counterpart there. It carries no
  // background/border of its own (the bar's own colors come from the
  // palette, like the nav bar's); it's an area so that what the mobile
  // navigation contains and how it behaves travels with a theme like every
  // other layout decision.
  mobile,
}

const Map<ThemeArea, String> _themeAreaLabels = {
  ThemeArea.masterBackground: "Master",
  ThemeArea.loginScreen: "Login Screen",
  ThemeArea.header: "Header",
  ThemeArea.navBar: "Navigation Bar",
  ThemeArea.dualPanel: "Dual Panel",
  ThemeArea.subMenuTabBar: "Sidebar",
  ThemeArea.contentArea: "Content Area",
  ThemeArea.inputAreas: "Input Areas",
  ThemeArea.buttons: "Buttons",
  ThemeArea.chat: "Chat",
  ThemeArea.feed: "Feed",
  ThemeArea.realtimeChat: "Realtime Chat",
  ThemeArea.account: "Account Page",
  ThemeArea.lnManagement: "LN Management",
  ThemeArea.pages: "Pages",
  ThemeArea.manageContent: "File Manager",
  ThemeArea.stats: "Stats",
  ThemeArea.logs: "Logs",
  ThemeArea.settingsPages: "Settings Pages",
  ThemeArea.mobile: "Mobile",
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
