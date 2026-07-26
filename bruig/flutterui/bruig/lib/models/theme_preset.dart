import 'dart:io';

import 'package:bruig/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// ThemeArea identifies a distinct visual region of the app that can carry its
// own background/border override, independent of the global color scheme.
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

String themeAreaLabel(ThemeArea area) {
  switch (area) {
    case ThemeArea.masterBackground:
      return "Master";
    case ThemeArea.loginScreen:
      return "Login Screen";
    case ThemeArea.header:
      return "Header";
    case ThemeArea.navBar:
      return "Navigation Bar";
    case ThemeArea.subMenuTabBar:
      return "Sidebar";
    case ThemeArea.chat:
      return "Chat";
    case ThemeArea.feed:
      return "Feed";
    case ThemeArea.realtimeChat:
      return "Realtime Chat";
    case ThemeArea.lnManagement:
      return "LN Management";
    case ThemeArea.pages:
      return "Pages";
    case ThemeArea.manageContent:
      return "Manage Content";
    case ThemeArea.stats:
      return "Stats";
    case ThemeArea.logs:
      return "Logs";
  }
}

// ContentAlign controls where an area's primary content sits (currently
// only wired for the header's title). hidden removes the content entirely.
enum ContentAlign { start, center, end, hidden }

// HeaderPosition controls where (or whether) the header renders:
// - top: today's behavior, a full-width bar above everything (sidebar
//   included).
// - content: a bar the same width as just the content area (to the right
//   of the primary nav sidebar), with the logo/about-button and "new post"
//   button removed since they belong to the global app chrome, not a
//   per-content-area bar.
// - none: no header at all; the content area extends to fill that space.
enum HeaderPosition { top, content, none }

String headerPositionLabel(HeaderPosition p) {
  switch (p) {
    case HeaderPosition.top:
      return "Default (Top)";
    case HeaderPosition.content:
      return "Content";
    case HeaderPosition.none:
      return "None";
  }
}

String contentAlignLabel(ContentAlign a) {
  switch (a) {
    case ContentAlign.start:
      return "Left";
    case ContentAlign.center:
      return "Center";
    case ContentAlign.end:
      return "Right";
    case ContentAlign.hidden:
      return "Remove";
  }
}

// SubMenuStyle controls how a page's sidebar (its sub-navigation tabs, e.g.
// Settings' Account/Appearance/Notifications/... list) shows or hides
// itself; only meaningful for subMenuTabBar. Every sidebar in the app --
// the "tab-style" ones with a small fixed set of destinations (Settings, LN
// Management, Feed, Manage Content, Address Book, the plugin screen
// switcher) as well as the dynamic, potentially-long lists (chat list, RTC
// sessions, page-view sessions) -- is driven by this same setting.
// - alwaysVisible: today's behavior, a persistent column beside the content.
// - hoverReveal: collapses to a thin edge strip and expands to full width
//   while the mouse hovers over it.
// - autoHideOnDetail: hidden entirely while viewing content that doesn't
//   need sub-navigation (e.g. an individual post, a specific chat), and
//   shown otherwise.
// - manualToggle: a persistent collapse/expand handle next to the content,
//   like the primary nav sidebar's own collapse button.
// - resizable: a plain, always-visible, drag-resizable pane (each screen
//   remembers its own width locally -- see SecondarySideMenuLayout).
enum SubMenuStyle {
  alwaysVisible,
  hoverReveal,
  autoHideOnDetail,
  manualToggle,
  resizable
}

String subMenuStyleLabel(SubMenuStyle s) {
  switch (s) {
    case SubMenuStyle.alwaysVisible:
      return "Default (Always visible)";
    case SubMenuStyle.hoverReveal:
      return "Reveal on hover";
    case SubMenuStyle.autoHideOnDetail:
      return "Auto-hide when not needed";
    case SubMenuStyle.manualToggle:
      return "Manual show/hide";
    case SubMenuStyle.resizable:
      return "Resizable (drag to resize)";
  }
}

// MessageLayoutMode controls how chat messages are arranged in the
// conversation view; only meaningful for ThemeArea.chat.
// - standard: today's behavior (own messages right-aligned, others left).
// - leftAlign: every message stacks in a single left-hand column.
// - narrow: the message list is centered into a narrower column.
enum MessageLayoutMode { standard, leftAlign, narrow }

String messageLayoutModeLabel(MessageLayoutMode m) {
  switch (m) {
    case MessageLayoutMode.standard:
      return "Default";
    case MessageLayoutMode.leftAlign:
      return "Left-align messages";
    case MessageLayoutMode.narrow:
      return "Narrow conversation";
  }
}

// FeedImageLayout controls how a feed post's first embedded image is
// displayed; only meaningful for ThemeArea.feed. Only ever applies to the
// first image in a post -- any further embedded images stay wherever they
// fall in the post's normal markdown flow.
// - standard: today's behavior (image renders inline, wherever it appears
//   in the post text -- no special extraction/placement).
// - left/right: image is pulled out of the text flow and placed beside it.
// - full: image is pulled out and placed below the text, full width,
//   uncropped (may be tall).
// - cropped: same as full, but the image is capped to feedImageCropHeight
//   and clipped if it exceeds that.
// - random: each post independently and stably picks one of left/right/
//   full/cropped (never standard) based on the post's own id, so the mix
//   looks varied but doesn't reshuffle on every rebuild.
// - none: every image is stripped out of the post entirely (not just the
//   first).
enum FeedImageLayout { standard, left, right, full, cropped, random, none }

String feedImageLayoutLabel(FeedImageLayout m) {
  switch (m) {
    case FeedImageLayout.standard:
      return "Default";
    case FeedImageLayout.left:
      return "Left";
    case FeedImageLayout.right:
      return "Right";
    case FeedImageLayout.full:
      return "Full width";
    case FeedImageLayout.cropped:
      return "Full width, cropped";
    case FeedImageLayout.random:
      return "Random";
    case FeedImageLayout.none:
      return "None";
  }
}

// FeedTextOrder controls whether a post's text renders before or after its
// first image; only meaningful for ThemeArea.feed, and only when the image
// is actually stacked above/below the text -- i.e. FeedImageLayout.standard
// (once an image has been extracted for ordering purposes), .full, or
// .cropped (including .random when it resolves to one of those). Ignored
// for .left/.right, which already have a fixed side-by-side arrangement.
// - standard: today's behavior -- text first, then the image below it.
// - textFirst: same as standard (explicit, in case standard's meaning
//   changes later).
// - textLast: image first, then the text below it.
enum FeedTextOrder { standard, textFirst, textLast }

String feedTextOrderLabel(FeedTextOrder o) {
  switch (o) {
    case FeedTextOrder.standard:
      return "Default";
    case FeedTextOrder.textFirst:
      return "Text first";
    case FeedTextOrder.textLast:
      return "Text last";
  }
}

// FeedLinksMode controls whether links are stripped out of feed post
// bodies entirely; only meaningful for ThemeArea.feed.
// - standard: today's behavior -- links render and work normally.
// - off: links are stripped from every post's body.
// - offIfImage: links are stripped only from posts that contain an image
//   (regardless of the chosen FeedImageLayout/whether that image ends up
//   specially positioned).
enum FeedLinksMode { standard, off, offIfImage }

String feedLinksModeLabel(FeedLinksMode m) {
  switch (m) {
    case FeedLinksMode.standard:
      return "Default";
    case FeedLinksMode.off:
      return "Turn off links";
    case FeedLinksMode.offIfImage:
      return "Turn off links if image available";
  }
}

// LoginBackgroundPreset picks between the two built-in login-screen
// background looks; only meaningful for ThemeArea.loginScreen, and only
// consulted when mode == AreaBackgroundMode.token (a fully custom
// solid/gradient/image fill via the theme editor's fill picker overrides
// this entirely).
// - standard: today's behavior (the original "network pattern" image).
// - exitus1: a full-bleed portrait background with a soft radial scrim
//   behind the login form, ported from exitus1/chat-redesign.
enum LoginBackgroundPreset { standard, exitus1 }

String loginBackgroundPresetLabel(LoginBackgroundPreset p) {
  switch (p) {
    case LoginBackgroundPreset.standard:
      return "Default";
    case LoginBackgroundPreset.exitus1:
      return "Exitus1 style";
  }
}

// AreaBackgroundMode selects how a fill (background or border) is painted.
// token = "use the app's normal color scheme" (opaque, matches how the area
// looked before this feature existed). none is a distinct, explicit "no
// fill at all" (fully transparent) -- useful e.g. for a submenu/tab-bar
// area where a border/padding is wanted but no background color at all.
enum AreaBackgroundMode { token, none, solid, gradient, image }

// GradientDirection is a small set of named, dropdown-friendly gradient
// directions (rather than a free-form angle input, consistent with this
// app's "dropdowns not fiddly custom controls" settings UX).
enum GradientDirection {
  topLeftToBottomRight,
  topRightToBottomLeft,
  leftToRight,
  topToBottom,
}

String gradientDirectionLabel(GradientDirection d) {
  switch (d) {
    case GradientDirection.topLeftToBottomRight:
      return "Top-left → Bottom-right";
    case GradientDirection.topRightToBottomLeft:
      return "Top-right → Bottom-left";
    case GradientDirection.leftToRight:
      return "Left → Right";
    case GradientDirection.topToBottom:
      return "Top → Bottom";
  }
}

(Alignment, Alignment) gradientDirectionAlignments(GradientDirection d) {
  switch (d) {
    case GradientDirection.topLeftToBottomRight:
      return (Alignment.topLeft, Alignment.bottomRight);
    case GradientDirection.topRightToBottomLeft:
      return (Alignment.topRight, Alignment.bottomLeft);
    case GradientDirection.leftToRight:
      return (Alignment.centerLeft, Alignment.centerRight);
    case GradientDirection.topToBottom:
      return (Alignment.topCenter, Alignment.bottomCenter);
  }
}

GradientDirection gradientDirectionFor(Alignment begin, Alignment end) {
  for (var d in GradientDirection.values) {
    var (b, e) = gradientDirectionAlignments(d);
    if (b == begin && e == end) return d;
  }
  return GradientDirection.topLeftToBottomRight;
}

// _Fill is the resolved paint for one "layer" (a background, or a border
// frame) -- at most one of color/gradient/image is set.
class _Fill {
  final Color? color;
  final Gradient? gradient;
  final DecorationImage? image;
  const _Fill({this.color, this.gradient, this.image});
}

// AreaStyle is the set of visual overrides a user can apply to a single
// ThemeArea. mode == token (the default) means "use the app's normal color
// scheme", producing an identical appearance to what the area rendered
// before this feature existed. The border supports the same four modes as
// the background (default/solid/gradient/image), plus independent padding
// (inset between the border and the content) and margin (outer spacing).
class AreaStyle {
  final AreaBackgroundMode mode;
  final SurfaceColor? tokenOverride;
  final Color? solidColor;
  // solidColorIndex, when set, is an index into the active preset's
  // palette (ThemePreset.palette) that solidColor was picked from --
  // resolution always prefers re-reading palette[solidColorIndex] live
  // over the frozen solidColor snapshot, so editing that palette slot's
  // own color later is picked up automatically instead of solidColor
  // silently going stale (and, if some other slot happens to now hold the
  // old value, appearing to "jump" to a different slot entirely). Null
  // means solidColor is a plain custom-picked color with no live slot to
  // track.
  final int? solidColorIndex;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final String? imagePath; // Relative path within the preset's directory.
  final BoxFit imageFit;

  final AreaBackgroundMode borderMode;
  final Color? borderColor;
  // Same live-slot-tracking role as solidColorIndex above, for borderColor.
  final int? borderColorIndex;
  final List<Color> borderGradientColors;
  final List<double>? borderGradientStops;
  final Alignment borderGradientBegin;
  final Alignment borderGradientEnd;
  final String? borderImagePath;
  final BoxFit borderImageFit;
  final double borderWidth;
  final double borderRadius;

  final double padding;
  final double margin;

  // width overrides the area's own layout width -- only meaningful for
  // subMenuTabBar (the one area with a fixed, configurable panel width);
  // null means "use that area's built-in default". Deliberately not
  // exposed for navBar -- the sidebarx package's collapse/extend toggle
  // assumes specific width values for its own animation.
  final double? width;

  // height overrides the area's own layout height -- only meaningful for
  // header (the app bar's height); null means "use the default toolbar
  // height".
  final double? height;

  // contentAlign controls where the area's primary content (currently only
  // wired for the header's title) sits within the area; null means "use
  // that area's default alignment".
  final ContentAlign? contentAlign;

  // logoSize overrides the app-icon logo size; meaningful for header (its
  // own logo, independent of the header's height) and navBar (see
  // showLogo below). Null means the built-in default (40 for header, 32
  // for navBar).
  final double? logoSize;

  // headerPosition controls where/whether the header renders at all; only
  // meaningful for header. Null means HeaderPosition.top (today's
  // behavior).
  final HeaderPosition? headerPosition;

  // showLogo displays the Bison Relay logo at the top of the nav bar; only
  // meaningful for navBar. Intended for when the header is set to
  // HeaderPosition.content or .none, since the header's own logo
  // disappears in both of those (the header only spans the content area,
  // or doesn't render at all), but it's an independent toggle either way.
  final bool showLogo;

  // logoAlign positions the nav bar logo (showLogo above) horizontally;
  // only meaningful for navBar, and only start/center/end are used there
  // (hidden doesn't apply -- showLogo already covers visibility). Null
  // means center.
  final ContentAlign? logoAlign;

  // subMenuStyle controls how a page's submenu shows/hides itself; only
  // meaningful for subMenuTabBar. Null means SubMenuStyle.alwaysVisible
  // (today's behavior).
  final SubMenuStyle? subMenuStyle;

  // showHoverArrow toggles the small chevron indicator shown on the
  // collapsed edge strip when subMenuStyle is hoverReveal; only meaningful
  // for subMenuTabBar. True (shown) is the default/unmodified state.
  final bool showHoverArrow;

  // The following fields are only meaningful for ThemeArea.subMenuTabBar
  // ("Sidebar") and apply uniformly to every sidebar built from
  // SecondarySideMenuList/SecondarySideMenuItem (Settings, LN Management,
  // Feed, Manage Content, Address Book, page-view sessions, the chat list,
  // and the Realtime Chat session list) -- not just one screen.
  final double sidebarCornerRadius; // Corner radius of the pill-highlight
  // rows (generalized from the old Settings-only restyled nav) -- rows are
  // always the pill-highlight style now, this only controls how rounded.
  // 0 reads as a plain square-cornered row. Independent of
  // sidebarShowIcons below (previously nested under a since-removed
  // sidebarIconRows toggle).
  final bool sidebarShowIcons; // Leading icon on each row. Default false
  // (hidden) -- previously defaulted true, but only had any effect when
  // sidebarIconRows was also on, which itself defaulted off.
  // Sidebar/nav bar text+accent colors are no longer per-area overrides --
  // they're always-present top-level palette slots now (sidebarText/
  // sidebarAccent/navText/navAccent on ThemePreset itself), since there's
  // only ever one sidebar/nav bar per theme.
  final bool sidebarShowRightDivider; // The plain right-edge divider line
  // shown when the sidebar is otherwise unmodified; default on. Independent
  // of the general border editor, which can already replace it entirely.
  final Color? sidebarDividerColor; // Null = built-in default
  // (extraColors.sidebarDivider). Only meaningful when
  // sidebarShowRightDivider is on.
  final double sidebarDividerWidth; // Default 1 (BorderSide's own default).

  // The following toggles are only meaningful for ThemeArea.chat. Each
  // gates a distinct chat-page feature ported from the exitus1 fork; all
  // default to false (off) so existing chat behavior is unchanged until a
  // user opts in via the theme editor.
  final bool enableMessageActions; // Reply + Pin context-menu actions.
  final bool showChatListLastMessage; // Last-message preview + timestamp.
  final bool chatListDesignEnabled; // Rounded/glow chat list row styling.
  final double? chatListCornerRadius; // Null = built-in default (14).
  final Color? chatListAccentColor; // Null = built-in default (blue).
  final double?
      chatListGlowIntensity; // Null = built-in default (1.0); 0 = off.
  final bool chatListTopHighlight; // Ambient top-left glow + lit hairline
  // on inactive rows (vs. a flat background); default on.
  // monochromeAvatars is read from ThemeArea.masterBackground (not chat) --
  // every avatar in the app funnels through the same InteractiveAvatar
  // widget, so this has always behaved as an app-wide toggle regardless of
  // which area's style it lived under; the field lives here rather than by
  // masterBackground's other fields for historical reasons only.
  final bool monochromeAvatars; // Graphite fallback avatars, app-wide.
  final bool chatBackdropWash; // Radial-gradient wash behind messages.
  final bool enableChatSearch; // In-chat message search panel.
  final bool formattingToolbar; // Composer markdown formatting toolbar.
  final bool composerPolish; // Tip button, glow send, dynamic hint.
  final bool squareBubbles; // Sharp vs. rounded message bubble corners.
  final MessageLayoutMode? messageLayoutMode; // Null = standard/default.
  final bool expandMessageWidth; // Fill the panel instead of margining in;
  // only meaningful when messageLayoutMode != null/standard.
  final double? expandMessagePadding; // Null = built-in default (0); only
  // meaningful when expandMessageWidth is on.

  // The following toggles are only meaningful for ThemeArea.realtimeChat.
  final bool autoUnmuteOnJoin; // Auto-unmute + snackbar on joining a call.
  final bool enhancedCallIndicators; // Mic-live/mute/warning-chip indicators.
  final bool rtcAudioTestPanel; // Pre-join mic/speaker test panel (pick
  // devices, record, play back) before joining a session.
  final bool rtcCollapsibleSessionInfo; // Tucks RV/Size/Peer ID/Owner behind
  // an expandable "Session info" row instead of always showing them.
  final bool rtcLobbyHero; // Icon-badge + title + member-count header shown
  // while not yet in a live session.
  final bool rtcLiveStage; // Rich live-session view: LIVE badge, session
  // timer, RTT signal bars, speaking-aware avatar rings, mic/speaker device
  // panels, mic activity bars. Needs the RTDTSessionModel.localHasSound
  // model support (always present; not conditional on this toggle).
  final bool rtcStyledSessionList; // Redesigned RTC session-list rows
  // (live-status dot + glow, active-row highlight).
  final bool rtcSessionListIntro; // Empty-state explainer + "Create your
  // first Realtime Chat" button when no session is active.

  // Only meaningful for ThemeArea.stats.
  final bool payStatsCardStyle; // Summary cards (total sent/received) +
  // redesigned per-user rows (avatar, inline sent-amount bar chart,
  // DCR-formatted amounts) on the Payment Stats page.

  // Only meaningful for ThemeArea.masterBackground (the Settings screen
  // isn't itself a per-content ThemeArea, so this rides on the closest
  // "global chrome" area).
  final bool settingsShellRestyle; // Icon + pill-highlight rows in the
  // Settings page's left nav, and a card-based restyle of the Account
  // page (avatar camera badge, Identity/Relay Counter/Account cards).

  // Only meaningful for ThemeArea.loginScreen.
  final LoginBackgroundPreset loginBgPreset; // See LoginBackgroundPreset.

  // The following toggles are only meaningful for ThemeArea.feed. Each
  // gates a distinct feed-page feature ported from the exitus1 fork; all
  // default to false (off). Several only have a visible effect when
  // feedCardRedesign is also on (they render into the new card's action
  // bar, which the old card layout doesn't have).
  final bool feedCardRedesign; // X-style card layout, comment count,
  // clamped body + "Show more", and the post-detail screen's centered width.
  final bool feedCardActions; // Relay/tip/quote-post action-bar icons +
  // nested quote-post rendering. Needs feedCardRedesign.
  final bool feedBookmarks; // Per-post bookmark + "Bookmarks" nav section.
  final bool feedHidePosts; // Per-post hide/unhide + "Hidden" nav section.
  final bool feedSidePanel; // Search/sort/filter nav rail, replacing FeedBar
  // on the main feed tab.
  final bool feedInlineComposer; // Pinned "What's happening?" composer.
  final bool feedComposerFormatting; // Formatting toolbar in the composer.
  // Needs feedInlineComposer.
  final bool feedComposerAttach; // Image/file attach in the composer. Needs
  // feedInlineComposer.
  final bool feedDrafts; // Save/reuse/delete drafts. Needs
  // feedInlineComposer (save button) + feedSidePanel (drafts list).
  final bool feedHideSidebarOnPost; // Drops the feed sidebar entirely while
  // reading a single post, for a more focused reading experience. Needs
  // feedSidePanel.
  final FeedImageLayout feedImageLayout; // How each post's first embedded
  // image is displayed (see FeedImageLayout).
  final double feedImageCropHeight; // Max height (px) for
  // FeedImageLayout.cropped (and for posts randomly assigned "cropped" by
  // FeedImageLayout.random).
  final FeedTextOrder feedTextOrder; // Text before/after the first image
  // (see FeedTextOrder).
  final FeedLinksMode feedLinksMode; // Strips links from feed post bodies
  // (see FeedLinksMode).
  final double feedTextLimit; // Max characters shown per post body; 0 (the
  // default) means unlimited (today's behavior).
  final bool feedStripMarkdown; // Renders post bodies as plain text --
  // headers/bold/italic/strikethrough all render as normal body text.

  // isUnmodified is true only when nothing about this style differs from
  // the area's original, pre-theming-feature appearance. A few render call
  // sites (SecondarySideMenu, the header, the login screen) have a cheaper
  // "reproduce the exact original widget" path for the common unmodified
  // case rather than always paying for the general buildContainer/
  // areaContainer machinery -- they must check *every* field here, not
  // just mode/borderMode, or a padding/margin/width/height/contentAlign
  // change with mode left at its default silently gets ignored by that
  // shortcut.
  bool get isUnmodified =>
      mode == AreaBackgroundMode.token &&
      borderMode == AreaBackgroundMode.token &&
      padding == 0 &&
      margin == 0 &&
      width == null &&
      height == null &&
      contentAlign == null &&
      logoSize == null &&
      headerPosition == null &&
      showLogo == false &&
      logoAlign == null &&
      subMenuStyle == null &&
      showHoverArrow == true &&
      sidebarCornerRadius == 12 &&
      sidebarShowIcons == false &&
      sidebarShowRightDivider == true &&
      sidebarDividerColor == null &&
      sidebarDividerWidth == 1 &&
      enableMessageActions == false &&
      showChatListLastMessage == false &&
      chatListDesignEnabled == false &&
      chatListCornerRadius == null &&
      chatListAccentColor == null &&
      chatListGlowIntensity == null &&
      chatListTopHighlight == true &&
      monochromeAvatars == false &&
      chatBackdropWash == false &&
      enableChatSearch == false &&
      formattingToolbar == false &&
      composerPolish == false &&
      squareBubbles == false &&
      messageLayoutMode == null &&
      expandMessageWidth == false &&
      expandMessagePadding == null &&
      autoUnmuteOnJoin == false &&
      enhancedCallIndicators == false &&
      rtcAudioTestPanel == false &&
      rtcCollapsibleSessionInfo == false &&
      rtcLobbyHero == false &&
      rtcLiveStage == false &&
      rtcStyledSessionList == false &&
      rtcSessionListIntro == false &&
      payStatsCardStyle == false &&
      settingsShellRestyle == false &&
      loginBgPreset == LoginBackgroundPreset.standard &&
      feedCardRedesign == false &&
      feedCardActions == false &&
      feedBookmarks == false &&
      feedHidePosts == false &&
      feedSidePanel == false &&
      feedInlineComposer == false &&
      feedComposerFormatting == false &&
      feedComposerAttach == false &&
      feedDrafts == false &&
      feedHideSidebarOnPost == false &&
      feedImageLayout == FeedImageLayout.standard &&
      feedImageCropHeight == 300 &&
      feedTextOrder == FeedTextOrder.standard &&
      feedLinksMode == FeedLinksMode.standard &&
      feedTextLimit == 0 &&
      feedStripMarkdown == false;

  const AreaStyle({
    this.mode = AreaBackgroundMode.token,
    this.tokenOverride,
    this.solidColor,
    this.solidColorIndex,
    this.gradientColors = const [],
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.imagePath,
    this.imageFit = BoxFit.cover,
    this.borderMode = AreaBackgroundMode.token,
    this.borderColor,
    this.borderColorIndex,
    this.borderGradientColors = const [],
    this.borderGradientStops,
    this.borderGradientBegin = Alignment.topLeft,
    this.borderGradientEnd = Alignment.bottomRight,
    this.borderImagePath,
    this.borderImageFit = BoxFit.cover,
    this.borderWidth = 0,
    this.borderRadius = 0,
    this.padding = 0,
    this.margin = 0,
    this.width,
    this.height,
    this.contentAlign,
    this.logoSize,
    this.headerPosition,
    this.showLogo = false,
    this.logoAlign,
    this.subMenuStyle,
    this.showHoverArrow = true,
    this.sidebarCornerRadius = 12,
    this.sidebarShowIcons = false,
    this.sidebarShowRightDivider = true,
    this.sidebarDividerColor,
    this.sidebarDividerWidth = 1,
    this.enableMessageActions = false,
    this.showChatListLastMessage = false,
    this.chatListDesignEnabled = false,
    this.chatListCornerRadius,
    this.chatListAccentColor,
    this.chatListGlowIntensity,
    this.chatListTopHighlight = true,
    this.monochromeAvatars = false,
    this.chatBackdropWash = false,
    this.enableChatSearch = false,
    this.formattingToolbar = false,
    this.composerPolish = false,
    this.squareBubbles = false,
    this.messageLayoutMode,
    this.expandMessageWidth = false,
    this.expandMessagePadding,
    this.autoUnmuteOnJoin = false,
    this.enhancedCallIndicators = false,
    this.rtcAudioTestPanel = false,
    this.rtcCollapsibleSessionInfo = false,
    this.rtcLobbyHero = false,
    this.rtcLiveStage = false,
    this.rtcStyledSessionList = false,
    this.rtcSessionListIntro = false,
    this.payStatsCardStyle = false,
    this.settingsShellRestyle = false,
    this.loginBgPreset = LoginBackgroundPreset.standard,
    this.feedCardRedesign = false,
    this.feedCardActions = false,
    this.feedBookmarks = false,
    this.feedHidePosts = false,
    this.feedSidePanel = false,
    this.feedInlineComposer = false,
    this.feedComposerFormatting = false,
    this.feedComposerAttach = false,
    this.feedDrafts = false,
    this.feedHideSidebarOnPost = false,
    this.feedImageLayout = FeedImageLayout.standard,
    this.feedImageCropHeight = 300,
    this.feedTextOrder = FeedTextOrder.standard,
    this.feedLinksMode = FeedLinksMode.standard,
    this.feedTextLimit = 0,
    this.feedStripMarkdown = false,
  });

  AreaStyle copyWith({
    AreaBackgroundMode? mode,
    SurfaceColor? tokenOverride,
    Color? solidColor,
    int? solidColorIndex,
    bool clearSolidColorIndex = false,
    List<Color>? gradientColors,
    List<double>? gradientStops,
    Alignment? gradientBegin,
    Alignment? gradientEnd,
    String? imagePath,
    bool clearImagePath = false,
    BoxFit? imageFit,
    AreaBackgroundMode? borderMode,
    Color? borderColor,
    int? borderColorIndex,
    bool clearBorderColorIndex = false,
    List<Color>? borderGradientColors,
    List<double>? borderGradientStops,
    Alignment? borderGradientBegin,
    Alignment? borderGradientEnd,
    String? borderImagePath,
    bool clearBorderImagePath = false,
    BoxFit? borderImageFit,
    double? borderWidth,
    double? borderRadius,
    double? padding,
    double? margin,
    double? width,
    bool clearWidth = false,
    double? height,
    bool clearHeight = false,
    ContentAlign? contentAlign,
    double? logoSize,
    HeaderPosition? headerPosition,
    bool? showLogo,
    ContentAlign? logoAlign,
    SubMenuStyle? subMenuStyle,
    bool? showHoverArrow,
    double? sidebarCornerRadius,
    bool? sidebarShowIcons,
    bool? sidebarShowRightDivider,
    Color? sidebarDividerColor,
    bool clearSidebarDividerColor = false,
    double? sidebarDividerWidth,
    bool? enableMessageActions,
    bool? showChatListLastMessage,
    bool? chatListDesignEnabled,
    double? chatListCornerRadius,
    bool clearChatListCornerRadius = false,
    Color? chatListAccentColor,
    bool clearChatListAccentColor = false,
    double? chatListGlowIntensity,
    bool clearChatListGlowIntensity = false,
    bool? chatListTopHighlight,
    bool? monochromeAvatars,
    bool? chatBackdropWash,
    bool? enableChatSearch,
    bool? formattingToolbar,
    bool? composerPolish,
    bool? squareBubbles,
    MessageLayoutMode? messageLayoutMode,
    bool clearMessageLayoutMode = false,
    bool? expandMessageWidth,
    double? expandMessagePadding,
    bool clearExpandMessagePadding = false,
    bool? autoUnmuteOnJoin,
    bool? enhancedCallIndicators,
    bool? rtcAudioTestPanel,
    bool? rtcCollapsibleSessionInfo,
    bool? rtcLobbyHero,
    bool? rtcLiveStage,
    bool? rtcStyledSessionList,
    bool? rtcSessionListIntro,
    bool? payStatsCardStyle,
    bool? settingsShellRestyle,
    LoginBackgroundPreset? loginBgPreset,
    bool? feedCardRedesign,
    bool? feedCardActions,
    bool? feedBookmarks,
    bool? feedHidePosts,
    bool? feedSidePanel,
    bool? feedInlineComposer,
    bool? feedComposerFormatting,
    bool? feedComposerAttach,
    bool? feedDrafts,
    bool? feedHideSidebarOnPost,
    FeedImageLayout? feedImageLayout,
    double? feedImageCropHeight,
    FeedTextOrder? feedTextOrder,
    FeedLinksMode? feedLinksMode,
    double? feedTextLimit,
    bool? feedStripMarkdown,
  }) =>
      AreaStyle(
        mode: mode ?? this.mode,
        tokenOverride: tokenOverride ?? this.tokenOverride,
        solidColor: solidColor ?? this.solidColor,
        solidColorIndex: clearSolidColorIndex
            ? null
            : (solidColorIndex ?? this.solidColorIndex),
        gradientColors: gradientColors ?? this.gradientColors,
        gradientStops: gradientStops ?? this.gradientStops,
        gradientBegin: gradientBegin ?? this.gradientBegin,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        imageFit: imageFit ?? this.imageFit,
        borderMode: borderMode ?? this.borderMode,
        borderColor: borderColor ?? this.borderColor,
        borderColorIndex: clearBorderColorIndex
            ? null
            : (borderColorIndex ?? this.borderColorIndex),
        borderGradientColors: borderGradientColors ?? this.borderGradientColors,
        borderGradientStops: borderGradientStops ?? this.borderGradientStops,
        borderGradientBegin: borderGradientBegin ?? this.borderGradientBegin,
        borderGradientEnd: borderGradientEnd ?? this.borderGradientEnd,
        borderImagePath: clearBorderImagePath
            ? null
            : (borderImagePath ?? this.borderImagePath),
        borderImageFit: borderImageFit ?? this.borderImageFit,
        borderWidth: borderWidth ?? this.borderWidth,
        borderRadius: borderRadius ?? this.borderRadius,
        padding: padding ?? this.padding,
        margin: margin ?? this.margin,
        width: clearWidth ? null : (width ?? this.width),
        height: clearHeight ? null : (height ?? this.height),
        contentAlign: contentAlign ?? this.contentAlign,
        logoSize: logoSize ?? this.logoSize,
        headerPosition: headerPosition ?? this.headerPosition,
        showLogo: showLogo ?? this.showLogo,
        logoAlign: logoAlign ?? this.logoAlign,
        subMenuStyle: subMenuStyle ?? this.subMenuStyle,
        showHoverArrow: showHoverArrow ?? this.showHoverArrow,
        sidebarCornerRadius: sidebarCornerRadius ?? this.sidebarCornerRadius,
        sidebarShowIcons: sidebarShowIcons ?? this.sidebarShowIcons,
        sidebarShowRightDivider:
            sidebarShowRightDivider ?? this.sidebarShowRightDivider,
        sidebarDividerColor: clearSidebarDividerColor
            ? null
            : (sidebarDividerColor ?? this.sidebarDividerColor),
        sidebarDividerWidth: sidebarDividerWidth ?? this.sidebarDividerWidth,
        enableMessageActions: enableMessageActions ?? this.enableMessageActions,
        showChatListLastMessage:
            showChatListLastMessage ?? this.showChatListLastMessage,
        chatListDesignEnabled:
            chatListDesignEnabled ?? this.chatListDesignEnabled,
        chatListCornerRadius: clearChatListCornerRadius
            ? null
            : (chatListCornerRadius ?? this.chatListCornerRadius),
        chatListAccentColor: clearChatListAccentColor
            ? null
            : (chatListAccentColor ?? this.chatListAccentColor),
        chatListGlowIntensity: clearChatListGlowIntensity
            ? null
            : (chatListGlowIntensity ?? this.chatListGlowIntensity),
        chatListTopHighlight: chatListTopHighlight ?? this.chatListTopHighlight,
        monochromeAvatars: monochromeAvatars ?? this.monochromeAvatars,
        chatBackdropWash: chatBackdropWash ?? this.chatBackdropWash,
        enableChatSearch: enableChatSearch ?? this.enableChatSearch,
        formattingToolbar: formattingToolbar ?? this.formattingToolbar,
        composerPolish: composerPolish ?? this.composerPolish,
        squareBubbles: squareBubbles ?? this.squareBubbles,
        messageLayoutMode: clearMessageLayoutMode
            ? null
            : (messageLayoutMode ?? this.messageLayoutMode),
        expandMessageWidth: expandMessageWidth ?? this.expandMessageWidth,
        expandMessagePadding: clearExpandMessagePadding
            ? null
            : (expandMessagePadding ?? this.expandMessagePadding),
        autoUnmuteOnJoin: autoUnmuteOnJoin ?? this.autoUnmuteOnJoin,
        enhancedCallIndicators:
            enhancedCallIndicators ?? this.enhancedCallIndicators,
        rtcAudioTestPanel: rtcAudioTestPanel ?? this.rtcAudioTestPanel,
        rtcCollapsibleSessionInfo:
            rtcCollapsibleSessionInfo ?? this.rtcCollapsibleSessionInfo,
        rtcLobbyHero: rtcLobbyHero ?? this.rtcLobbyHero,
        rtcLiveStage: rtcLiveStage ?? this.rtcLiveStage,
        rtcStyledSessionList: rtcStyledSessionList ?? this.rtcStyledSessionList,
        rtcSessionListIntro: rtcSessionListIntro ?? this.rtcSessionListIntro,
        payStatsCardStyle: payStatsCardStyle ?? this.payStatsCardStyle,
        settingsShellRestyle: settingsShellRestyle ?? this.settingsShellRestyle,
        loginBgPreset: loginBgPreset ?? this.loginBgPreset,
        feedCardRedesign: feedCardRedesign ?? this.feedCardRedesign,
        feedCardActions: feedCardActions ?? this.feedCardActions,
        feedBookmarks: feedBookmarks ?? this.feedBookmarks,
        feedHidePosts: feedHidePosts ?? this.feedHidePosts,
        feedSidePanel: feedSidePanel ?? this.feedSidePanel,
        feedInlineComposer: feedInlineComposer ?? this.feedInlineComposer,
        feedComposerFormatting:
            feedComposerFormatting ?? this.feedComposerFormatting,
        feedComposerAttach: feedComposerAttach ?? this.feedComposerAttach,
        feedDrafts: feedDrafts ?? this.feedDrafts,
        feedHideSidebarOnPost:
            feedHideSidebarOnPost ?? this.feedHideSidebarOnPost,
        feedImageLayout: feedImageLayout ?? this.feedImageLayout,
        feedImageCropHeight: feedImageCropHeight ?? this.feedImageCropHeight,
        feedTextOrder: feedTextOrder ?? this.feedTextOrder,
        feedLinksMode: feedLinksMode ?? this.feedLinksMode,
        feedTextLimit: feedTextLimit ?? this.feedTextLimit,
        feedStripMarkdown: feedStripMarkdown ?? this.feedStripMarkdown,
      );

  static String _colorToHex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color _colorFromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));
  static List<double> _alignToJson(Alignment a) => [a.x, a.y];
  static Alignment _alignFromJson(dynamic j, Alignment fallback) => j != null
      ? Alignment((j[0] as num).toDouble(), (j[1] as num).toDouble())
      : fallback;

  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        if (tokenOverride != null) "tokenOverride": tokenOverride!.name,
        if (solidColor != null) "solidColor": _colorToHex(solidColor!),
        if (solidColorIndex != null) "solidColorIndex": solidColorIndex,
        if (gradientColors.isNotEmpty)
          "gradientColors": gradientColors.map(_colorToHex).toList(),
        if (gradientStops != null) "gradientStops": gradientStops,
        "gradientBegin": _alignToJson(gradientBegin),
        "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        "imageFit": imageFit.name,
        "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": _colorToHex(borderColor!),
        if (borderColorIndex != null) "borderColorIndex": borderColorIndex,
        if (borderGradientColors.isNotEmpty)
          "borderGradientColors":
              borderGradientColors.map(_colorToHex).toList(),
        if (borderGradientStops != null)
          "borderGradientStops": borderGradientStops,
        "borderGradientBegin": _alignToJson(borderGradientBegin),
        "borderGradientEnd": _alignToJson(borderGradientEnd),
        if (borderImagePath != null) "borderImagePath": borderImagePath,
        "borderImageFit": borderImageFit.name,
        "borderWidth": borderWidth,
        "borderRadius": borderRadius,
        "padding": padding,
        "margin": margin,
        if (width != null) "width": width,
        if (height != null) "height": height,
        if (contentAlign != null) "contentAlign": contentAlign!.name,
        if (logoSize != null) "logoSize": logoSize,
        if (headerPosition != null) "headerPosition": headerPosition!.name,
        if (showLogo) "showLogo": showLogo,
        if (logoAlign != null) "logoAlign": logoAlign!.name,
        if (subMenuStyle != null) "subMenuStyle": subMenuStyle!.name,
        if (!showHoverArrow) "showHoverArrow": showHoverArrow,
        if (sidebarCornerRadius != 12)
          "sidebarCornerRadius": sidebarCornerRadius,
        if (sidebarShowIcons) "sidebarShowIcons": sidebarShowIcons,
        if (!sidebarShowRightDivider)
          "sidebarShowRightDivider": sidebarShowRightDivider,
        if (sidebarDividerColor != null)
          "sidebarDividerColor": _colorToHex(sidebarDividerColor!),
        if (sidebarDividerWidth != 1)
          "sidebarDividerWidth": sidebarDividerWidth,
        if (enableMessageActions) "enableMessageActions": enableMessageActions,
        if (showChatListLastMessage)
          "showChatListLastMessage": showChatListLastMessage,
        if (chatListDesignEnabled)
          "chatListDesignEnabled": chatListDesignEnabled,
        if (chatListCornerRadius != null)
          "chatListCornerRadius": chatListCornerRadius,
        if (chatListAccentColor != null)
          "chatListAccentColor": _colorToHex(chatListAccentColor!),
        if (chatListGlowIntensity != null)
          "chatListGlowIntensity": chatListGlowIntensity,
        if (!chatListTopHighlight) "chatListTopHighlight": chatListTopHighlight,
        if (monochromeAvatars) "monochromeAvatars": monochromeAvatars,
        if (chatBackdropWash) "chatBackdropWash": chatBackdropWash,
        if (enableChatSearch) "enableChatSearch": enableChatSearch,
        if (formattingToolbar) "formattingToolbar": formattingToolbar,
        if (composerPolish) "composerPolish": composerPolish,
        if (squareBubbles) "squareBubbles": squareBubbles,
        if (messageLayoutMode != null)
          "messageLayoutMode": messageLayoutMode!.name,
        if (expandMessageWidth) "expandMessageWidth": expandMessageWidth,
        if (expandMessagePadding != null)
          "expandMessagePadding": expandMessagePadding,
        if (autoUnmuteOnJoin) "autoUnmuteOnJoin": autoUnmuteOnJoin,
        if (enhancedCallIndicators)
          "enhancedCallIndicators": enhancedCallIndicators,
        if (rtcAudioTestPanel) "rtcAudioTestPanel": rtcAudioTestPanel,
        if (rtcCollapsibleSessionInfo)
          "rtcCollapsibleSessionInfo": rtcCollapsibleSessionInfo,
        if (rtcLobbyHero) "rtcLobbyHero": rtcLobbyHero,
        if (rtcLiveStage) "rtcLiveStage": rtcLiveStage,
        if (rtcStyledSessionList) "rtcStyledSessionList": rtcStyledSessionList,
        if (rtcSessionListIntro) "rtcSessionListIntro": rtcSessionListIntro,
        if (payStatsCardStyle) "payStatsCardStyle": payStatsCardStyle,
        if (settingsShellRestyle) "settingsShellRestyle": settingsShellRestyle,
        if (loginBgPreset != LoginBackgroundPreset.standard)
          "loginBgPreset": loginBgPreset.name,
        if (feedCardRedesign) "feedCardRedesign": feedCardRedesign,
        if (feedCardActions) "feedCardActions": feedCardActions,
        if (feedBookmarks) "feedBookmarks": feedBookmarks,
        if (feedHidePosts) "feedHidePosts": feedHidePosts,
        if (feedSidePanel) "feedSidePanel": feedSidePanel,
        if (feedInlineComposer) "feedInlineComposer": feedInlineComposer,
        if (feedComposerFormatting)
          "feedComposerFormatting": feedComposerFormatting,
        if (feedComposerAttach) "feedComposerAttach": feedComposerAttach,
        if (feedDrafts) "feedDrafts": feedDrafts,
        if (feedHideSidebarOnPost)
          "feedHideSidebarOnPost": feedHideSidebarOnPost,
        if (feedImageLayout != FeedImageLayout.standard)
          "feedImageLayout": feedImageLayout.name,
        if (feedImageCropHeight != 300)
          "feedImageCropHeight": feedImageCropHeight,
        if (feedTextOrder != FeedTextOrder.standard)
          "feedTextOrder": feedTextOrder.name,
        if (feedLinksMode != FeedLinksMode.standard)
          "feedLinksMode": feedLinksMode.name,
        if (feedTextLimit != 0) "feedTextLimit": feedTextLimit,
        if (feedStripMarkdown) "feedStripMarkdown": feedStripMarkdown,
      };

  factory AreaStyle.fromJson(Map<String, dynamic> j) => AreaStyle(
        mode: AreaBackgroundMode.values.firstWhere((e) => e.name == j["mode"],
            orElse: () => AreaBackgroundMode.token),
        tokenOverride: j["tokenOverride"] != null
            ? SurfaceColor.values
                .firstWhere((e) => e.name == j["tokenOverride"])
            : null,
        solidColor:
            j["solidColor"] != null ? _colorFromHex(j["solidColor"]) : null,
        solidColorIndex: (j["solidColorIndex"] as num?)?.toInt(),
        gradientColors: j["gradientColors"] != null
            ? (j["gradientColors"] as List)
                .map((e) => _colorFromHex(e as String))
                .toList()
            : const [],
        gradientStops: j["gradientStops"] != null
            ? (j["gradientStops"] as List)
                .map((e) => (e as num).toDouble())
                .toList()
            : null,
        gradientBegin: _alignFromJson(j["gradientBegin"], Alignment.topLeft),
        gradientEnd: _alignFromJson(j["gradientEnd"], Alignment.bottomRight),
        imagePath: j["imagePath"],
        imageFit: BoxFit.values.firstWhere((e) => e.name == j["imageFit"],
            orElse: () => BoxFit.cover),
        borderMode: AreaBackgroundMode.values.firstWhere(
            (e) => e.name == j["borderMode"],
            orElse: () => AreaBackgroundMode.token),
        borderColor:
            j["borderColor"] != null ? _colorFromHex(j["borderColor"]) : null,
        borderColorIndex: (j["borderColorIndex"] as num?)?.toInt(),
        borderGradientColors: j["borderGradientColors"] != null
            ? (j["borderGradientColors"] as List)
                .map((e) => _colorFromHex(e as String))
                .toList()
            : const [],
        borderGradientStops: j["borderGradientStops"] != null
            ? (j["borderGradientStops"] as List)
                .map((e) => (e as num).toDouble())
                .toList()
            : null,
        borderGradientBegin:
            _alignFromJson(j["borderGradientBegin"], Alignment.topLeft),
        borderGradientEnd:
            _alignFromJson(j["borderGradientEnd"], Alignment.bottomRight),
        borderImagePath: j["borderImagePath"],
        borderImageFit: BoxFit.values.firstWhere(
            (e) => e.name == j["borderImageFit"],
            orElse: () => BoxFit.cover),
        borderWidth: (j["borderWidth"] as num?)?.toDouble() ?? 0,
        borderRadius: (j["borderRadius"] as num?)?.toDouble() ?? 0,
        padding: (j["padding"] as num?)?.toDouble() ?? 0,
        margin: (j["margin"] as num?)?.toDouble() ?? 0,
        width: (j["width"] as num?)?.toDouble(),
        height: (j["height"] as num?)?.toDouble(),
        contentAlign: j["contentAlign"] != null
            ? ContentAlign.values.firstWhere((e) => e.name == j["contentAlign"])
            : null,
        logoSize: (j["logoSize"] as num?)?.toDouble(),
        headerPosition: j["headerPosition"] != null
            ? HeaderPosition.values
                .firstWhere((e) => e.name == j["headerPosition"])
            : null,
        showLogo: j["showLogo"] as bool? ?? false,
        logoAlign: j["logoAlign"] != null
            ? ContentAlign.values.firstWhere((e) => e.name == j["logoAlign"])
            : null,
        subMenuStyle: j["subMenuStyle"] != null
            ? SubMenuStyle.values.firstWhere((e) => e.name == j["subMenuStyle"])
            : null,
        showHoverArrow: j["showHoverArrow"] as bool? ?? true,
        sidebarCornerRadius:
            (j["sidebarCornerRadius"] as num?)?.toDouble() ?? 12,
        sidebarShowIcons: j["sidebarShowIcons"] as bool? ?? false,
        sidebarShowRightDivider: j["sidebarShowRightDivider"] as bool? ?? true,
        sidebarDividerColor: j["sidebarDividerColor"] != null
            ? _colorFromHex(j["sidebarDividerColor"])
            : null,
        sidebarDividerWidth:
            (j["sidebarDividerWidth"] as num?)?.toDouble() ?? 1,
        enableMessageActions: j["enableMessageActions"] as bool? ?? false,
        showChatListLastMessage: j["showChatListLastMessage"] as bool? ?? false,
        chatListDesignEnabled: j["chatListDesignEnabled"] as bool? ?? false,
        chatListCornerRadius: (j["chatListCornerRadius"] as num?)?.toDouble(),
        chatListAccentColor: j["chatListAccentColor"] != null
            ? _colorFromHex(j["chatListAccentColor"])
            : null,
        chatListGlowIntensity: (j["chatListGlowIntensity"] as num?)?.toDouble(),
        chatListTopHighlight: j["chatListTopHighlight"] as bool? ?? true,
        monochromeAvatars: j["monochromeAvatars"] as bool? ?? false,
        chatBackdropWash: j["chatBackdropWash"] as bool? ?? false,
        enableChatSearch: j["enableChatSearch"] as bool? ?? false,
        formattingToolbar: j["formattingToolbar"] as bool? ?? false,
        composerPolish: j["composerPolish"] as bool? ?? false,
        squareBubbles: j["squareBubbles"] as bool? ?? false,
        messageLayoutMode: j["messageLayoutMode"] != null
            ? MessageLayoutMode.values
                .firstWhere((e) => e.name == j["messageLayoutMode"])
            : null,
        expandMessageWidth: j["expandMessageWidth"] as bool? ?? false,
        expandMessagePadding: (j["expandMessagePadding"] as num?)?.toDouble(),
        autoUnmuteOnJoin: j["autoUnmuteOnJoin"] as bool? ?? false,
        enhancedCallIndicators: j["enhancedCallIndicators"] as bool? ?? false,
        rtcAudioTestPanel: j["rtcAudioTestPanel"] as bool? ?? false,
        rtcCollapsibleSessionInfo:
            j["rtcCollapsibleSessionInfo"] as bool? ?? false,
        rtcLobbyHero: j["rtcLobbyHero"] as bool? ?? false,
        rtcLiveStage: j["rtcLiveStage"] as bool? ?? false,
        rtcStyledSessionList: j["rtcStyledSessionList"] as bool? ?? false,
        rtcSessionListIntro: j["rtcSessionListIntro"] as bool? ?? false,
        payStatsCardStyle: j["payStatsCardStyle"] as bool? ?? false,
        settingsShellRestyle: j["settingsShellRestyle"] as bool? ?? false,
        loginBgPreset: j["loginBgPreset"] != null
            ? LoginBackgroundPreset.values.firstWhere(
                (e) => e.name == j["loginBgPreset"],
                orElse: () => LoginBackgroundPreset.standard)
            : LoginBackgroundPreset.standard,
        feedCardRedesign: j["feedCardRedesign"] as bool? ?? false,
        feedCardActions: j["feedCardActions"] as bool? ?? false,
        feedBookmarks: j["feedBookmarks"] as bool? ?? false,
        feedHidePosts: j["feedHidePosts"] as bool? ?? false,
        feedSidePanel: j["feedSidePanel"] as bool? ?? false,
        feedInlineComposer: j["feedInlineComposer"] as bool? ?? false,
        feedComposerFormatting: j["feedComposerFormatting"] as bool? ?? false,
        feedComposerAttach: j["feedComposerAttach"] as bool? ?? false,
        feedDrafts: j["feedDrafts"] as bool? ?? false,
        feedHideSidebarOnPost: j["feedHideSidebarOnPost"] as bool? ?? false,
        feedImageLayout: j["feedImageLayout"] != null
            ? FeedImageLayout.values.firstWhere(
                (e) => e.name == j["feedImageLayout"],
                orElse: () => FeedImageLayout.standard)
            : FeedImageLayout.standard,
        feedImageCropHeight:
            (j["feedImageCropHeight"] as num?)?.toDouble() ?? 300,
        feedTextOrder: j["feedTextOrder"] != null
            ? FeedTextOrder.values.firstWhere(
                (e) => e.name == j["feedTextOrder"],
                orElse: () => FeedTextOrder.standard)
            : FeedTextOrder.standard,
        feedLinksMode: j["feedLinksMode"] != null
            ? FeedLinksMode.values.firstWhere(
                (e) => e.name == j["feedLinksMode"],
                orElse: () => FeedLinksMode.standard)
            : FeedLinksMode.standard,
        feedTextLimit: (j["feedTextLimit"] as num?)?.toDouble() ?? 0,
        feedStripMarkdown: j["feedStripMarkdown"] as bool? ?? false,
      );

  // _liveColor prefers re-reading preset.palette[index] over the frozen
  // `raw` snapshot whenever index is set -- see solidColorIndex's doc.
  Color? _liveColor(ThemeNotifier theme, int? index, Color? raw) {
    if (index != null) {
      var palette = theme.activePreset?.palette;
      if (palette != null && index < palette.length) return palette[index];
    }
    return raw;
  }

  // resolveBorderColor/resolveSolidColor are _liveColor's public form --
  // for the handful of render sites (navBar, the Sidebar's own
  // SecondarySideMenu) that build their decoration by hand instead of
  // going through toBoxDecoration/buildContainer, and for the theme
  // editor's own Color dropdown, which needs the live-resolved value (not
  // the frozen snapshot) to display the right slot selected.
  Color? resolveBorderColor(ThemeNotifier theme) =>
      _liveColor(theme, borderColorIndex, borderColor);
  Color? resolveSolidColor(ThemeNotifier theme) =>
      _liveColor(theme, solidColorIndex, solidColor);

  _Fill _resolveFill(
    AreaBackgroundMode m,
    ThemeNotifier theme,
    SurfaceColor fallback, {
    Color? solid,
    List<Color> gradColors = const [],
    List<double>? gradStops,
    Alignment gradBegin = Alignment.topLeft,
    Alignment gradEnd = Alignment.bottomRight,
    String? imgPath,
    BoxFit imgFit = BoxFit.cover,
    String? presetDir,
  }) {
    switch (m) {
      case AreaBackgroundMode.token:
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
      case AreaBackgroundMode.none:
        return const _Fill(color: Colors.transparent);
      case AreaBackgroundMode.solid:
        return _Fill(color: solid ?? theme.surfaceColor(fallback));
      case AreaBackgroundMode.gradient:
        if (gradColors.length >= 2) {
          return _Fill(
              gradient: LinearGradient(
                  begin: gradBegin,
                  end: gradEnd,
                  colors: gradColors,
                  stops: gradStops));
        }
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
      case AreaBackgroundMode.image:
        if (imgPath != null && presetDir != null) {
          return _Fill(
              image: DecorationImage(
                  image: FileImage(File(path.join(presetDir, imgPath))),
                  fit: imgFit));
        }
        return _Fill(color: theme.surfaceColor(tokenOverride ?? fallback));
    }
  }

  // toBoxDecoration resolves this style's *background* (and, if the border
  // is a flat color, a matching BorderSide) into a single BoxDecoration.
  // This is the cheap path used by areas that are composed into an existing
  // widget's own decoration (app bar, side nav, sub-menu divider) rather
  // than wrapped in their own container -- it can't express a gradient or
  // image border (see buildContainer for that), but reproduces the area's
  // original appearance exactly when mode is token and there's no border.
  BoxDecoration toBoxDecoration(ThemeNotifier theme, SurfaceColor fallback,
      {String? presetDir}) {
    var liveBorderColor = _liveColor(theme, borderColorIndex, borderColor);
    var bg = _resolveFill(mode, theme, fallback,
        solid: _liveColor(theme, solidColorIndex, solidColor),
        gradColors: gradientColors,
        gradStops: gradientStops,
        gradBegin: gradientBegin,
        gradEnd: gradientEnd,
        imgPath: imagePath,
        imgFit: imageFit,
        presetDir: presetDir);
    return BoxDecoration(
      color: bg.color,
      gradient: bg.gradient,
      image: bg.image,
      border: (borderMode != AreaBackgroundMode.token &&
              liveBorderColor != null &&
              borderWidth > 0)
          ? Border.all(color: liveBorderColor, width: borderWidth)
          : null,
      borderRadius:
          borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
    );
  }

  // buildContainer wraps `child` in this style's full background + border
  // (solid/gradient/image, matching modes independently) + padding/margin.
  // A gradient or image border can't be expressed as a single BoxDecoration
  // (Border only supports flat per-side colors), so when the border isn't
  // a flat color, this nests two containers: an outer one painted with the
  // border's fill, inset by borderWidth, framing an inner one painted with
  // the background fill -- the standard technique for non-solid borders in
  // Flutter.
  Widget buildContainer(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
  }) {
    var bg = _resolveFill(mode, theme, fallback,
        solid: _liveColor(theme, solidColorIndex, solidColor),
        gradColors: gradientColors,
        gradStops: gradientStops,
        gradBegin: gradientBegin,
        gradEnd: gradientEnd,
        imgPath: imagePath,
        imgFit: imageFit,
        presetDir: presetDir);
    var radius = borderRadius > 0 ? BorderRadius.circular(borderRadius) : null;

    // Any descendant ListTile needs a Material ancestor to paint its
    // background/ink splashes into. When this style paints a real
    // background/border below, the Containers built below would otherwise
    // be the nearest DecoratedBox sitting between the ListTile and whatever
    // Material happens to be further up the tree (e.g. Scaffold's), which
    // trips Flutter's "ListTile background may be invisible" assertion.
    // MaterialType.transparency paints nothing itself, so it just supplies
    // that ancestor without changing this area's appearance.
    child = Material(type: MaterialType.transparency, child: child);

    Widget content = Container(
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      decoration: BoxDecoration(
          color: bg.color,
          gradient: bg.gradient,
          image: bg.image,
          borderRadius: radius),
      child: child,
    );

    if (borderMode != AreaBackgroundMode.token && borderWidth > 0) {
      if (borderMode == AreaBackgroundMode.solid) {
        // Flat color: a plain Border on the same box is enough (matches
        // toBoxDecoration's cheaper path), no extra nesting needed.
        content = Container(
          padding: padding > 0 ? EdgeInsets.all(padding) : null,
          decoration: BoxDecoration(
            color: bg.color,
            gradient: bg.gradient,
            image: bg.image,
            borderRadius: radius,
            border: Border.all(
                color: _liveColor(theme, borderColorIndex, borderColor) ??
                    theme.surfaceColor(fallback),
                width: borderWidth),
          ),
          child: child,
        );
      } else {
        var borderFill = _resolveFill(borderMode, theme, fallback,
            gradColors: borderGradientColors,
            gradStops: borderGradientStops,
            gradBegin: borderGradientBegin,
            gradEnd: borderGradientEnd,
            imgPath: borderImagePath,
            imgFit: borderImageFit,
            presetDir: presetDir);
        content = Container(
          padding: EdgeInsets.all(borderWidth),
          decoration: BoxDecoration(
              color: borderFill.color,
              gradient: borderFill.gradient,
              image: borderFill.image,
              borderRadius: radius),
          child: content,
        );
      }
    }

    if (margin > 0) {
      content = Container(margin: EdgeInsets.all(margin), child: content);
    }
    return content;
  }

  // wrapBorderOnly wraps `child` in just this style's *border* -- for a
  // caller that paints its own background through some other fixed API
  // that only accepts a flat BoxDecoration (e.g. the third-party sidebarx
  // package's SidebarXTheme.decoration) and so can't itself embed a
  // gradient/image border, but can still wrap its whole widget with one via
  // this. A solid border is a no-op here (the caller's own decoration
  // already embeds it as a plain BorderSide, same as toBoxDecoration).
  Widget wrapBorderOnly(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
  }) {
    if (borderMode == AreaBackgroundMode.token ||
        borderMode == AreaBackgroundMode.solid ||
        borderWidth <= 0) {
      return child;
    }
    var borderFill = _resolveFill(borderMode, theme, fallback,
        gradColors: borderGradientColors,
        gradStops: borderGradientStops,
        gradBegin: borderGradientBegin,
        gradEnd: borderGradientEnd,
        imgPath: borderImagePath,
        imgFit: borderImageFit,
        presetDir: presetDir);
    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        color: borderFill.color,
        gradient: borderFill.gradient,
        image: borderFill.image,
        borderRadius:
            borderRadius > 0 ? BorderRadius.circular(borderRadius) : null,
      ),
      child: child,
    );
  }
}

// PaletteSlot identifies one of the 17 palette colors. Deliberately fewer,
// more distinct roles than Material3's ColorScheme (which has 4 near-
// identical onPrimary/onSecondary/onTertiary/onError slots in practice) --
// every slot here has a clearly different purpose so there's minimal visual
// overlap between them. Grouped by tier (backgrounds, then text, then
// accents, then semantic) so the palette editor and dropdowns read as a
// coherent list rather than an arbitrary historical order. `buttonBorder`
// used to be its own slot here; it's been removed and merged into
// `navAccent` (see toAppTheme) since every built-in palette already set it
// to an exact duplicate of navAccent's own value.
enum PaletteSlot {
  primary,
  tertiary,
  secondary,
  sidebarBackground,
  fourth,
  speechBackground,
  speechBackgroundSent,
  outline,
  onSurface,
  onSurfaceVariant,
  navText,
  sidebarText,
  accentContainer,
  navAccent,
  sidebarAccent,
  error,
  success,
}

// kMaxPaletteColors caps the *total* palette (17 fixed roles +
// extraPaletteColors) a preset can carry; kMaxExtraPaletteColors is the
// remaining room for extras once the 17 fixed roles are accounted for.
const int kMaxPaletteColors = 20;
// 20 - 17 fixed PaletteSlot roles.
const int kMaxExtraPaletteColors = kMaxPaletteColors - 17;

// kVividPaletteSlots are the 12 roles a ColorPalette library entry (see
// palette_library.dart) actually carries and overwrites when applied --
// 6 background-tier hues (used exactly as stored -- see theme_editor.dart's
// _applyPalette) plus 6 real accent/semantic colors. Each background tier
// gets its own hue input (rather than all deriving from `primary`) so a
// palette's sidebar/chat areas can each have a distinct character instead
// of looking like minor tints of the same background. Tertiary also drives
// the Feed post card/post-detail background and the Settings page's group
// panels (see post_content.dart/feed_posts.dart/settings.dart's
// _SettingsGroupCard) -- previously a separate `newsBackground` slot
// duplicated this role for feed cards only, leaving Settings on an
// unrelated color; merged into Tertiary so every "second background" tier
// in the app reads as the same deliberate color. speechBackgroundSent (the
// "sent"/own chat bubble) is included alongside speechBackground (the
// "received" bubble) so the two can read as deliberately distinct colors
// per palette -- e.g. WhatsApp's real outgoing-bubble teal -- instead of
// speechBackgroundSent silently falling back to the Default/Light seed's
// own value (identical across every other palette) the way it used to.
// accentContainer (drives Switch/tonal-button backgrounds) is included for
// the same reason -- it used to always fall back to the Default/Light
// seed's own pale lavender, which reads as a random, brand-mismatched
// "Buttons/Toggles" color on e.g. WhatsApp-green or Reddit-orange palettes.
// error is included too so each palette can use a dark-mode-appropriate
// red tuned for its own background instead of a single flat value that was
// occasionally too dark/muddy against certain panel tones -- it's still
// deliberately kept a similar, conventional "danger" red across every
// palette (not brand-tinted) since a semantic color like error should stay
// visually predictable regardless of theme. outline is included so each
// palette can tune its own divider color to blend into that palette's
// specific background tone -- a single flat grey doesn't blend equally
// well with, say, WhatsApp's teal-black vs Snapchat's amber-black.
// onSurface/navText/sidebarText/success are functional/neutral roles that
// must stay dark-vs-light-theme-appropriate, so a library palette
// deliberately leaves them alone (they're reset from palette.brightness's
// own seed instead -- see _applyPalette) rather than clobbering them with
// (possibly brightness-mismatched) baked-in values. fourth (the reply-
// preview box and success/error toast background) IS included, appended
// at the tail -- it used to always fall back to the Default/Light seed's
// own flat purple-blue regardless of which palette was active, so e.g.
// applying WhatsApp's teal-black or Snapchat's warm amber-black look
// still showed an unrelated purple notification box; each built-in
// palette now tunes its own third-background-tier tone to match.
const List<PaletteSlot> kVividPaletteSlots = [
  PaletteSlot.primary,
  PaletteSlot.secondary,
  PaletteSlot.tertiary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.navAccent,
  PaletteSlot.sidebarAccent,
  PaletteSlot.accentContainer,
  PaletteSlot.error,
  PaletteSlot.outline,
  PaletteSlot.fourth,
];

String paletteSlotLabel(PaletteSlot slot) {
  switch (slot) {
    case PaletteSlot.primary:
      return "Primary Background";
    case PaletteSlot.tertiary:
      return "Secondary Background";
    case PaletteSlot.secondary:
      return "Navigation Background";
    case PaletteSlot.sidebarBackground:
      return "Sidebar Background";
    case PaletteSlot.fourth:
      return "Notifications Background";
    case PaletteSlot.speechBackground:
      return "Speech Background (Receive)";
    case PaletteSlot.speechBackgroundSent:
      return "Speech Background (Send)";
    case PaletteSlot.outline:
      return "Outline (Borders/Dividers)";
    case PaletteSlot.onSurface:
      return "Primary Text Color";
    case PaletteSlot.onSurfaceVariant:
      return "Secondary Text Color";
    case PaletteSlot.navText:
      return "Navigation Text Color";
    case PaletteSlot.sidebarText:
      return "Sidebar Text Color";
    case PaletteSlot.accentContainer:
      return "Button Background";
    case PaletteSlot.navAccent:
      return "Button Accent Background";
    case PaletteSlot.sidebarAccent:
      return "Sidebar Accent Color";
    case PaletteSlot.error:
      return "Error";
    case PaletteSlot.success:
      return "Success";
  }
}

// ThemePreset is one full, nameable, exportable custom theme: a 12-color
// palette plus a set of per-area style overrides.
class ThemePreset {
  final String id;
  final String name;
  final Brightness brightness;

  // The 15-color palette (see PaletteSlot for the rationale behind these
  // specific roles).
  final Color primary; // Main app background (and ColorScheme.fromSeed's
  // seed color). Also the Theme Areas section's select-menu popup
  // background.
  final Color secondary; // Nav bar's background fill.
  final Color tertiary; // Shares the compiled ColorScheme's tertiary/
  // tertiaryContainer roles -- the RTC instant-call banner, voice-recorder
  // box, markdown blockquotes, Feed post card/post-detail background, the
  // Settings page's group panels (_SettingsGroupCard), and the Settings >
  // Audio microphone/output volume sliders' track background -- this
  // app's general-purpose "second background" tier.
  final Color fourth; // A 4th, more deeply nested background tier -- the
  // chat reply-preview box and the success/error snackbar ("popup
  // notification") background.
  final Color sidebarBackground; // Sidebar (subMenuTabBar) row/tile
  // background -- Settings/LN Management/Feed/etc.'s left nav list.
  final Color speechBackground; // Chat message bubble (received) background.
  final Color speechBackgroundSent; // Chat message bubble (sent/own)
  // background -- previously unthemed (always theme.colors.surfaceContainer,
  // a Primary-derived tone), so sent bubbles never actually followed any
  // preset color the way received bubbles did.
  final Color accentContainer; // Backs Material's primaryContainer/secondary/
  // secondaryContainer roles (default Switch track+thumb, FilledButton.tonal,
  // CancelButton's background, etc.) -- these were never
  // pinned to anything in toAppTheme's ColorScheme.fromSeed, so they were
  // left to Material's own tonal derivation from Primary's seed color, same
  // as the bug that made colorScheme.primary itself render as an unrelated,
  // oddly-tinted color (see navAccent's doc) -- except here nothing was
  // pinned at all, so it surfaced as a stray, uncontrollable pink showing up
  // across the app with no palette field to fix it from. CancelButton
  // previously used `error` instead (a genuine mislabeling -- "Cancel"
  // is a neutral dismiss action at nearly every one of its ~24 call sites,
  // not a failure/danger state), which is what made "Error" appear to
  // control far more of the UI than its name suggested.
  final Color onSurface; // General app text/icons -- NOT the nav bar or
  // sidebar, which have their own dedicated text/accent slots below.
  final Color onSurfaceVariant; // Muted/secondary text+icons -- toolbar
  // icon buttons, hint text, etc. Previously hardcoded (Colors.grey[600])
  // in toAppTheme with no palette field behind it at all, so it couldn't
  // be themed like onSurface can.
  final Color navText; // Nav bar's unselected-item text+icon color.
  final Color navAccent; // Nav bar's selected-item text+icon color.
  final Color sidebarText; // Sidebar's unselected-item text+icon color.
  final Color sidebarAccent; // Sidebar's selected-item text+icon color.
  final Color outline; // Borders/dividers that should blend into the
  // background (drives colorScheme.outlineVariant) -- panel dividers,
  // card/list-item borders, muted icon tints. Deliberately low-contrast.
  final Color error; // Genuine failure/danger states only -- validation
  // errors, exception messages, upload/parse failures, hanging up a live
  // call. Deliberately NOT used for the generic CancelButton (see
  // accentContainer's doc) or any other plain "step back"/dismiss action.
  final Color success;

  // extraPaletteColors are user-added swatches beyond the 12 fixed roles
  // above -- free-form, no fixed semantic meaning, just additional options
  // offered wherever an area style needs a color picked (see `palette`
  // below and theme_editor.dart's palette-color dropdowns). Capped at
  // kMaxExtraPaletteColors (see below) so the total palette never exceeds
  // kMaxPaletteColors.
  final List<Color> extraPaletteColors;

  final Map<ThemeArea, AreaStyle> areas;

  // Menu rename/reorder customization is saved as *part of this preset*
  // (rather than as a single global setting) so that switching themes
  // switches menu layout too, and "Reset to Default" (which switches to
  // the built-in default theme, unaffected by any custom preset) can't
  // accidentally erase what's saved in a *different*, still-selectable
  // preset. Null means "no customization" (always true for the built-in
  // dark/light themes). Keyed/ordered by routeName, same shape as
  // MainMenuModel.currentLabels()/currentOrder().
  final Map<String, String>? menuLabels;
  final List<String>? menuOrder;

  // Directory this preset was loaded from on disk (null for a preset that
  // only exists in memory, e.g. mid-edit before its first save). Area
  // background images are stored relative to this directory.
  final String? sourceDir;

  const ThemePreset({
    required this.id,
    this.name = "Default Theme",
    this.brightness = Brightness.dark,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.fourth,
    required this.sidebarBackground,
    required this.speechBackground,
    required this.speechBackgroundSent,
    required this.accentContainer,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.navText,
    required this.navAccent,
    required this.sidebarText,
    required this.sidebarAccent,
    required this.outline,
    required this.error,
    required this.success,
    this.extraPaletteColors = const [],
    this.areas = const {},
    this.menuLabels,
    this.menuOrder,
    this.sourceDir,
  });

  Color forSlot(PaletteSlot slot) {
    switch (slot) {
      case PaletteSlot.primary:
        return primary;
      case PaletteSlot.secondary:
        return secondary;
      case PaletteSlot.tertiary:
        return tertiary;
      case PaletteSlot.fourth:
        return fourth;
      case PaletteSlot.sidebarBackground:
        return sidebarBackground;
      case PaletteSlot.speechBackground:
        return speechBackground;
      case PaletteSlot.speechBackgroundSent:
        return speechBackgroundSent;
      case PaletteSlot.accentContainer:
        return accentContainer;
      case PaletteSlot.onSurface:
        return onSurface;
      case PaletteSlot.onSurfaceVariant:
        return onSurfaceVariant;
      case PaletteSlot.navText:
        return navText;
      case PaletteSlot.navAccent:
        return navAccent;
      case PaletteSlot.sidebarText:
        return sidebarText;
      case PaletteSlot.sidebarAccent:
        return sidebarAccent;
      case PaletteSlot.outline:
        return outline;
      case PaletteSlot.error:
        return error;
      case PaletteSlot.success:
        return success;
    }
  }

  ThemePreset withSlot(PaletteSlot slot, Color color) {
    switch (slot) {
      case PaletteSlot.primary:
        return copyWith(primary: color);
      case PaletteSlot.secondary:
        return copyWith(secondary: color);
      case PaletteSlot.tertiary:
        return copyWith(tertiary: color);
      case PaletteSlot.fourth:
        return copyWith(fourth: color);
      case PaletteSlot.sidebarBackground:
        return copyWith(sidebarBackground: color);
      case PaletteSlot.speechBackground:
        return copyWith(speechBackground: color);
      case PaletteSlot.speechBackgroundSent:
        return copyWith(speechBackgroundSent: color);
      case PaletteSlot.accentContainer:
        return copyWith(accentContainer: color);
      case PaletteSlot.onSurface:
        return copyWith(onSurface: color);
      case PaletteSlot.onSurfaceVariant:
        return copyWith(onSurfaceVariant: color);
      case PaletteSlot.navText:
        return copyWith(navText: color);
      case PaletteSlot.navAccent:
        return copyWith(navAccent: color);
      case PaletteSlot.sidebarText:
        return copyWith(sidebarText: color);
      case PaletteSlot.sidebarAccent:
        return copyWith(sidebarAccent: color);
      case PaletteSlot.outline:
        return copyWith(outline: color);
      case PaletteSlot.error:
        return copyWith(error: color);
      case PaletteSlot.success:
        return copyWith(success: color);
    }
  }

  // palette returns the 12 fixed-role colors (in PaletteSlot order) plus
  // any extraPaletteColors -- this is the full set of colors offered
  // wherever an area style needs a color picked (see theme_editor.dart's
  // palette-color dropdowns).
  List<Color> get palette =>
      [...PaletteSlot.values.map(forSlot), ...extraPaletteColors];

  ThemePreset copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? primary,
    Color? secondary,
    Color? tertiary,
    Color? fourth,
    Color? sidebarBackground,
    Color? speechBackground,
    Color? speechBackgroundSent,
    Color? accentContainer,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? navText,
    Color? navAccent,
    Color? sidebarText,
    Color? sidebarAccent,
    Color? outline,
    Color? error,
    Color? success,
    List<Color>? extraPaletteColors,
    Map<ThemeArea, AreaStyle>? areas,
    Map<String, String>? menuLabels,
    List<String>? menuOrder,
    String? sourceDir,
  }) =>
      ThemePreset(
        id: id ?? this.id,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        tertiary: tertiary ?? this.tertiary,
        fourth: fourth ?? this.fourth,
        sidebarBackground: sidebarBackground ?? this.sidebarBackground,
        speechBackground: speechBackground ?? this.speechBackground,
        speechBackgroundSent:
            speechBackgroundSent ?? this.speechBackgroundSent,
        accentContainer: accentContainer ?? this.accentContainer,
        onSurface: onSurface ?? this.onSurface,
        onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
        navText: navText ?? this.navText,
        navAccent: navAccent ?? this.navAccent,
        sidebarText: sidebarText ?? this.sidebarText,
        sidebarAccent: sidebarAccent ?? this.sidebarAccent,
        outline: outline ?? this.outline,
        error: error ?? this.error,
        success: success ?? this.success,
        extraPaletteColors: extraPaletteColors ?? this.extraPaletteColors,
        areas: areas ?? this.areas,
        menuLabels: menuLabels ?? this.menuLabels,
        menuOrder: menuOrder ?? this.menuOrder,
        sourceDir: sourceDir ?? this.sourceDir,
      );

  // toAppTheme compiles this preset into an AppTheme using exactly the same
  // ColorScheme.fromSeed()+copyWith() formula the built-in "dark"/"light"
  // themes are hand-written with (see appThemes below), so custom presets
  // render through the same pipeline the rest of the app already trusts.
  static Color _darken(Color c, double amount) {
    var hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  // toAppTheme deliberately does NOT force secondary (or most
  // Material-derived roles) into ColorScheme.fromSeed -- those roles drive
  // the foreground of many standard Material widgets, and forcing them to
  // the user's raw palette swatch can produce illegible text-on-background.
  // `primary` (the seed), `tertiary`, `error`, and `onSurface` are safe to
  // pass through directly since ColorScheme.fromSeed independently derives
  // a full, properly-contrasting tonal ramp (onTertiary/tertiaryContainer/
  // onError/errorContainer/etc.) from each -- the same way `surface`
  // already was. `onSurface` in particular is what "On surface text"
  // actually needs to drive general app text/icon color (most Text/Icon
  // widgets read colorScheme.onSurface when given no explicit color) --
  // without passing it here, editing that palette slot had no visible
  // effect anywhere in the app.
  AppTheme toAppTheme() {
    // interTextTheme/interBlackTextTheme hardcode Colors.white70/black54 on
    // every style -- reused as-is, a plain Text widget with no explicit
    // color (i.e. most of them; only this app's own Txt component with an
    // explicit TextColor reads colorScheme.onSurface directly) would never
    // reflect a custom preset's "On surface text" pick at all, regardless
    // of the colorScheme.onSurface override above. .apply() recolors every
    // style to the preset's own onSurface instead.
    var textTheme = (brightness == Brightness.dark
            ? interTextTheme
            : interBlackTextTheme)
        .apply(displayColor: onSurface, bodyColor: onSurface);
    var data = ThemeData.from(
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        // colorScheme.outline is what OutlinedButton's own default M3
        // border reads (plus a few of this app's own custom button
        // styles) -- pinned to `navAccent` ("Button Accent Background"),
        // since a clickable button's edge needs to stand out against the
        // background, unlike a plain divider. This used to be its own
        // `buttonBorder` field, but every built-in palette already set it
        // to an exact duplicate of navAccent's value, so the two were
        // merged into one slot.
        outline: navAccent,
        // colorScheme.outlineVariant is the separate, subtler Material
        // role that this app's own panel/card/divider borders read
        // (Settings' left-nav panel border, Manage Content's card border,
        // the emoji picker's category icons, the About page border, the
        // feed post-detail divider) -- pinned to `outline`, the
        // blend-with-background field. Previously neither role was pinned
        // at all, so every one of these borders (buttons included) showed
        // Material's auto-derived tonal color regardless of what the user
        // picked; now the two palette fields cleanly map to the two roles
        // instead of colliding on one.
        outlineVariant: outline,
        surface: primary,
        surfaceContainerLow: _darken(primary, 0.012),
        surfaceContainerLowest: _darken(primary, 0.022),
        // Continues the same explicit elevation ladder as
        // surfaceContainerLow/Lowest above, rather than leaving these 3
        // tiers to Material's own tonal derivation -- otherwise any
        // unthemed Card/Container that reads one of these (several plain
        // settings panels do) shows the same unpredictable seed-derived
        // tint described above instead of a shade of the actual chosen
        // Primary color.
        surfaceContainer: _darken(primary, 0.006),
        surfaceContainerHigh: _darken(primary, 0.0),
        surfaceContainerHighest: _darken(primary, -0.01),
        tertiary: tertiary,
        // Only `error` (not errorContainer/onErrorContainer) is pinned --
        // same reasoning as tertiary/surface above: ColorScheme.fromSeed
        // independently derives a properly-contrasting errorContainer/
        // onErrorContainer pair from this seed. Previously errorContainer
        // was force-pinned to the exact same flat value as `error` (with
        // onErrorContainer force-pinned to onSurface) because CancelButton
        // read errorContainer for its background -- collapsing Material's
        // normal two-tier tonal system (a brighter `error` for text/icons
        // directly on the background vs. a darker `errorContainer` for
        // surfaces with light text on top) into one flat color that
        // couldn't satisfy both contrast needs at once. Now that
        // CancelButton no longer uses errorContainer (see accentContainer's
        // doc), only genuine error-surface call sites (snackbar error
        // background, failed-upload/unsupported-GC-version event cards)
        // read it, so letting Material derive it properly is strictly
        // better than a hand-pinned flat value.
        error: error,
        // Without this, ColorScheme.fromSeed computes its own tonal
        // derivation of "primary" from the seed rather than using the
        // literal color -- every other unthemed Material widget that falls
        // back to colorScheme.primary (default OutlinedButton/TextButton
        // foreground, container backgrounds, etc.) then shows that
        // computed tone instead of anything the user actually picked. That
        // tone is also unpredictable at the extremes: a fully desaturated
        // seed (e.g. pure black "Primary") has no well-defined hue, and
        // Material's algorithm can resolve it to an unrelated, oddly-tinted
        // color (seen here as a washed-out pink). navAccent is what this
        // app treats as its actual "accent" role, so pinning
        // colorScheme.primary to it keeps every unthemed widget visually
        // consistent with the app's own accent instead of a hidden,
        // seed-derived one.
        primary: navAccent,
        // onPrimary had the exact same never-pinned problem -- Material's
        // default Switch uses it for the ON-state thumb color (track is
        // colorScheme.primary, already pinned above), so it showed the
        // same kind of stray, unpredictable tint (a dark maroon) with no
        // palette field to control it from.
        onPrimary: onSurface,
        // primaryContainer/secondary/secondaryContainer had the exact same
        // problem as primary above, just never pinned at all -- Material's
        // default Switch (track+thumb) and FilledButton.tonal both read
        // one of these, and showed the same stray, unpredictable
        // seed-derived tint (see accentContainer's doc) with no palette
        // field to control it from.
        primaryContainer: accentContainer,
        secondary: accentContainer,
        secondaryContainer: accentContainer,
        onPrimaryContainer: onSurface,
        onSecondary: onSurface,
        onSecondaryContainer: onSurface,
      ),
    ).copyWith(
      // DropdownButton's popup menu (e.g. the Theme Areas section's select)
      // falls back to canvasColor when no explicit dropdownColor is set
      // (true everywhere in this app) -- this connects it to "Primary"
      // without needing to touch every DropdownButton call site.
      canvasColor: primary,
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        selectedTileColor:
            brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
        iconColor: onSurface,
      ),
      hintColor: onSurface.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        scrolledUnderElevation: 0,
      ),
      disabledColor: Colors.grey[850],
    );

    return AppTheme(
      key: "custom:$id",
      descr: name,
      data: data,
      extraColors: CustomColors(
        successOnSurface: success,
        sidebarDivider: outline,
        selectedItemOnSurfaceListView: sidebarAccent,
      ),
      extraTextStyles: CustomTextStyles(
        chatListGcIndicator: TextStyle(
          fontStyle: FontStyle.italic,
          color: onSurface.withValues(alpha: 0.6),
        ),
      ),
      areaStyles: areas,
      presetDir: sourceDir,
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0')}';
  static Color _fromHex(String s) =>
      Color(int.parse(s.replaceFirst('#', ''), radix: 16));

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "brightness": brightness.name,
        // paletteVersion 2 marks presets saved after PaletteSlot's reorder/
        // buttonBorder removal -- see _legacyPaletteOrderV1 below. The
        // palette map itself is keyed by slot *name*, so it's unaffected by
        // reordering; only AreaStyle's solidColorIndex/borderColorIndex
        // (raw positions into the flat `palette` list) need this to know
        // whether they still need remapping on load.
        "paletteVersion": 2,
        "palette": {
          for (var slot in PaletteSlot.values) slot.name: _hex(forSlot(slot)),
        },
        if (extraPaletteColors.isNotEmpty)
          "extraPaletteColors": extraPaletteColors.map(_hex).toList(),
        "areas": areas.map((k, v) => MapEntry(k.name, v.toJson())),
        if (menuLabels != null) "menuLabels": menuLabels,
        if (menuOrder != null) "menuOrder": menuOrder,
      };

  // _legacyPaletteOrderV1 is PaletteSlot's order as it existed before
  // paletteVersion 2 (i.e. before Button Border was removed and merged into
  // navAccent, and the remaining slots were regrouped by
  // background/text/accent tier). Used only to remap solidColorIndex/
  // borderColorIndex values -- raw positions into the flat `palette` list
  // -- saved by presets written before this change; the old buttonBorder
  // slot maps to navAccent, its merge target.
  static const List<PaletteSlot> _legacyPaletteOrderV1 = [
    PaletteSlot.primary,
    PaletteSlot.secondary,
    PaletteSlot.tertiary,
    PaletteSlot.fourth,
    PaletteSlot.sidebarBackground,
    PaletteSlot.speechBackground,
    PaletteSlot.speechBackgroundSent,
    PaletteSlot.accentContainer,
    PaletteSlot.onSurface,
    PaletteSlot.onSurfaceVariant,
    PaletteSlot.navText,
    PaletteSlot.navAccent,
    PaletteSlot.sidebarText,
    PaletteSlot.sidebarAccent,
    PaletteSlot.outline,
    PaletteSlot.navAccent, // was buttonBorder; merged into navAccent
    PaletteSlot.error,
    PaletteSlot.success,
  ];

  static int? _migrateLegacyColorIndex(int? oldIndex) {
    if (oldIndex == null) return null;
    if (oldIndex < _legacyPaletteOrderV1.length) {
      return _legacyPaletteOrderV1[oldIndex].index;
    }
    // An extra (user-added) color, appended after the fixed roles -- shift
    // down by one since the fixed-role count shrank by one.
    return oldIndex - 1;
  }

  factory ThemePreset.fromJson(Map<String, dynamic> j) {
    var p = j["palette"] as Map<String, dynamic>;
    var preset = seedFromDark().copyWith(
      id: j["id"],
      name: j["name"] ?? "Default Theme",
      brightness:
          j["brightness"] == "light" ? Brightness.light : Brightness.dark,
    );
    for (var slot in PaletteSlot.values) {
      var hex = p[slot.name];
      if (hex != null) preset = preset.withSlot(slot, _fromHex(hex));
    }
    var isLegacyPalette = (j["paletteVersion"] as num?)?.toInt() != 2;
    var rawAreas = j["areas"] as Map<String, dynamic>? ?? {};
    if (isLegacyPalette) {
      rawAreas = rawAreas.map((k, v) {
        var area = Map<String, dynamic>.from(v as Map<String, dynamic>);
        if (area["solidColorIndex"] != null) {
          area["solidColorIndex"] = _migrateLegacyColorIndex(
              (area["solidColorIndex"] as num).toInt());
        }
        if (area["borderColorIndex"] != null) {
          area["borderColorIndex"] = _migrateLegacyColorIndex(
              (area["borderColorIndex"] as num).toInt());
        }
        return MapEntry(k, area);
      });
    }
    return preset.copyWith(
      extraPaletteColors: j["extraPaletteColors"] != null
          ? (j["extraPaletteColors"] as List)
              .map((h) => _fromHex(h as String))
              .toList()
          : const [],
      // Skip any area key that no longer matches a known ThemeArea (e.g.
      // saved by a future/older version of the app) instead of throwing.
      areas: Map.fromEntries(rawAreas.entries
          .where((e) => ThemeArea.values.any((a) => a.name == e.key))
          .map((e) => MapEntry(
              ThemeArea.values.firstWhere((a) => a.name == e.key),
              AreaStyle.fromJson(e.value as Map<String, dynamic>)))),
      menuLabels: j["menuLabels"] != null
          ? (j["menuLabels"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : null,
      menuOrder: j["menuOrder"] != null
          ? (j["menuOrder"] as List).cast<String>()
          : null,
    );
  }

  // Seed palettes to pre-fill the palette editor from - not separate
  // installable presets, just starting points. secondary/sidebarBackground/
  // navText/navAccent/sidebarText/sidebarAccent are read straight off
  // appThemes' real ColorScheme (theme_manager.dart) rather than
  // independently-guessed hex literals, so the "Default Theme" card can
  // never silently drift from what the untouched, no-custom-preset app
  // actually looks like (this previously caused the seed's navAccent to be
  // amber/orange while the real default nav accent is ColorScheme.primary,
  // a lavender-purple/indigo).
  //
  // navText/sidebarText and navAccent/sidebarAccent are intentionally set
  // to the *same* source value (onSurfaceVariant / primary) because that's
  // what the real fallback rendering does when no preset is active (see
  // sidebar.dart's navUnselectedIconColor/navSelectedIconColor and
  // containers.dart's sidebarText/sidebarAccent fallbacks) -- Nav and
  // Sidebar are only meant to visibly diverge on sidebarBackground
  // (surfaceContainerLowest vs secondary's surfaceContainerLow), not on
  // text/accent, unless the user explicitly customizes one of them.
  static ThemePreset seedFromDark() {
    var scheme = appThemes["dark"]!.data.colorScheme;
    return ThemePreset(
      id: "custom",
      name: "Default Theme",
      brightness: Brightness.dark,
      primary: const Color(0xFF19172C),
      secondary: scheme.surfaceContainerLow,
      tertiary: const Color(0xFF232030),
      fourth: const Color(0xFF1C1930),
      sidebarBackground: scheme.surfaceContainerLowest,
      speechBackground: const Color(0xFF232030),
      speechBackgroundSent: const Color(0xFF1C1930),
      accentContainer: scheme.primary,
      onSurface: const Color(0xFFE5E1E9),
      onSurfaceVariant: scheme.onSurfaceVariant,
      navText: scheme.onSurfaceVariant,
      navAccent: scheme.primary,
      sidebarText: scheme.onSurfaceVariant,
      sidebarAccent: scheme.primary,
      // Matches extraColors.sidebarDivider, the fallback borders/dividers
      // use when NO preset is active at all -- once any preset (including
      // this "Default Theme" one) is active, activePreset?.outline always
      // takes precedence over extraColors.sidebarDivider (see
      // containers.dart's border color chains), so this must equal that
      // fallback or borders visibly shift the moment a preset is applied.
      outline: appThemes["dark"]!.extraColors.sidebarDivider,
      error: const Color(0xFFBA1A1A),
      success: const Color(0xFF2D882D),
    );
  }

  static ThemePreset seedFromLight() {
    var scheme = appThemes["light"]!.data.colorScheme;
    return ThemePreset(
      id: "custom",
      name: "Default Theme",
      brightness: Brightness.light,
      primary: const Color(0xFFE8E7F3),
      secondary: scheme.surfaceContainerLow,
      tertiary: const Color(0xFFF5F4FA),
      fourth: const Color(0xFFEDEBF5),
      sidebarBackground: scheme.surfaceContainerLowest,
      speechBackground: const Color(0xFFF5F4FA),
      speechBackgroundSent: const Color(0xFFEDEBF5),
      accentContainer: scheme.primary,
      onSurface: const Color(0xFF1B1B1F),
      onSurfaceVariant: scheme.onSurfaceVariant,
      navText: scheme.onSurfaceVariant,
      navAccent: scheme.primary,
      sidebarText: scheme.onSurfaceVariant,
      sidebarAccent: scheme.primary,
      outline: appThemes["light"]!.extraColors.sidebarDivider,
      error: const Color(0xFFBA1A1A),
      success: const Color(0xFF2D882D),
    );
  }
}
