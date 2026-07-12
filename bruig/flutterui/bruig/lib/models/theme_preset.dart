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
      return "Master Background";
    case ThemeArea.loginScreen:
      return "Login Screen";
    case ThemeArea.header:
      return "Header";
    case ThemeArea.navBar:
      return "Navigation Bar";
    case ThemeArea.subMenuTabBar:
      return "Submenu / Tab Bar";
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

// SubMenuStyle controls how a page's submenu (its sub-navigation tabs, e.g.
// Settings' Account/Appearance/Notifications/... list) shows or hides
// itself; only meaningful for subMenuTabBar, and only wired up for the
// "tab-style" submenus with a small fixed set of destinations (Settings, LN
// Management, Feed, the plugin screen switcher) -- not the dynamic,
// potentially-long lists (chat list, RTC sessions, page-view sessions).
// - alwaysVisible: today's behavior, a persistent column beside the content.
// - hoverReveal: collapses to a thin edge strip and expands to full width
//   while the mouse hovers over it.
// - autoHideOnDetail: hidden entirely while viewing content that doesn't
//   need sub-navigation (e.g. an individual post, a specific chat), and
//   shown otherwise.
// - manualToggle: a persistent collapse/expand handle next to the content,
//   like the primary nav sidebar's own collapse button.
enum SubMenuStyle { alwaysVisible, hoverReveal, autoHideOnDetail, manualToggle }

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
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final String? imagePath; // Relative path within the preset's directory.
  final BoxFit imageFit;

  final AreaBackgroundMode borderMode;
  final Color? borderColor;
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
  final bool resizableChatList; // Draggable-width chat list + search bar.
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
      resizableChatList == false &&
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
    this.gradientColors = const [],
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.imagePath,
    this.imageFit = BoxFit.cover,
    this.borderMode = AreaBackgroundMode.token,
    this.borderColor,
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
    this.resizableChatList = false,
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
    List<Color>? gradientColors,
    List<double>? gradientStops,
    Alignment? gradientBegin,
    Alignment? gradientEnd,
    String? imagePath,
    bool clearImagePath = false,
    BoxFit? imageFit,
    AreaBackgroundMode? borderMode,
    Color? borderColor,
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
    bool? resizableChatList,
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
        gradientColors: gradientColors ?? this.gradientColors,
        gradientStops: gradientStops ?? this.gradientStops,
        gradientBegin: gradientBegin ?? this.gradientBegin,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        imageFit: imageFit ?? this.imageFit,
        borderMode: borderMode ?? this.borderMode,
        borderColor: borderColor ?? this.borderColor,
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
        resizableChatList: resizableChatList ?? this.resizableChatList,
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
        if (gradientColors.isNotEmpty)
          "gradientColors": gradientColors.map(_colorToHex).toList(),
        if (gradientStops != null) "gradientStops": gradientStops,
        "gradientBegin": _alignToJson(gradientBegin),
        "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        "imageFit": imageFit.name,
        "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": _colorToHex(borderColor!),
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
        if (resizableChatList) "resizableChatList": resizableChatList,
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
        resizableChatList: j["resizableChatList"] as bool? ?? false,
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
    var bg = _resolveFill(mode, theme, fallback,
        solid: solidColor,
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
              borderColor != null &&
              borderWidth > 0)
          ? Border.all(color: borderColor!, width: borderWidth)
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
        solid: solidColor,
        gradColors: gradientColors,
        gradStops: gradientStops,
        gradBegin: gradientBegin,
        gradEnd: gradientEnd,
        imgPath: imagePath,
        imgFit: imageFit,
        presetDir: presetDir);
    var radius = borderRadius > 0 ? BorderRadius.circular(borderRadius) : null;

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
                color: borderColor ?? theme.surfaceColor(fallback),
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

// PaletteSlot identifies one of the 10 palette colors. Deliberately fewer,
// more distinct roles than Material3's ColorScheme (which has 4 near-
// identical onPrimary/onSecondary/onTertiary/onError slots in practice) --
// every slot here has a clearly different purpose so there's minimal visual
// overlap between them.
enum PaletteSlot {
  primary,
  secondary,
  tertiary,
  error,
  surface,
  onSurface,
  onAccent,
  outline,
  success,
  accent,
}

// kMaxPaletteColors caps the *total* palette (10 fixed roles +
// extraPaletteColors) a preset can carry; kMaxExtraPaletteColors is the
// remaining room for extras once the 10 fixed roles are accounted for.
const int kMaxPaletteColors = 20;
// 20 - 10 fixed PaletteSlot roles.
const int kMaxExtraPaletteColors = kMaxPaletteColors - 10;

// kVividPaletteSlots are the 5 roles a ColorPalette library entry (see
// palette_library.dart) actually carries and overwrites when applied --
// error/surface/onSurface/onAccent/outline are functional/neutral roles
// that must stay dark-vs-light-theme-appropriate, so a library palette
// deliberately leaves them alone rather than clobbering them with
// (possibly brightness-mismatched, e.g. a white surface in a dark theme)
// baked-in values.
const List<PaletteSlot> kVividPaletteSlots = [
  PaletteSlot.primary,
  PaletteSlot.secondary,
  PaletteSlot.tertiary,
  PaletteSlot.success,
  PaletteSlot.accent,
];

String paletteSlotLabel(PaletteSlot slot) {
  switch (slot) {
    case PaletteSlot.primary:
      return "Primary";
    case PaletteSlot.secondary:
      return "Secondary";
    case PaletteSlot.tertiary:
      return "Tertiary";
    case PaletteSlot.error:
      return "Error";
    case PaletteSlot.surface:
      return "Surface (Background)";
    case PaletteSlot.onSurface:
      return "On Surface (Text)";
    case PaletteSlot.onAccent:
      return "On Accent (Text on Color)";
    case PaletteSlot.outline:
      return "Outline (Borders)";
    case PaletteSlot.success:
      return "Success";
    case PaletteSlot.accent:
      return "Accent (Custom)";
  }
}

// ThemePreset is one full, nameable, exportable custom theme: a 10-color
// palette plus a set of per-area style overrides.
class ThemePreset {
  final String id;
  final String name;
  final Brightness brightness;

  // The 10-color palette (see PaletteSlot for the rationale behind these
  // specific roles). "accent" carries no fixed ColorScheme role -- it's a
  // free extra swatch available for area styling.
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color error;
  final Color surface;
  final Color onSurface;
  final Color onAccent;
  final Color outline;
  final Color success;
  final Color accent;

  // extraPaletteColors are user-added swatches beyond the 10 fixed roles
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
    required this.error,
    required this.surface,
    required this.onSurface,
    required this.onAccent,
    required this.outline,
    required this.success,
    required this.accent,
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
      case PaletteSlot.error:
        return error;
      case PaletteSlot.surface:
        return surface;
      case PaletteSlot.onSurface:
        return onSurface;
      case PaletteSlot.onAccent:
        return onAccent;
      case PaletteSlot.outline:
        return outline;
      case PaletteSlot.success:
        return success;
      case PaletteSlot.accent:
        return accent;
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
      case PaletteSlot.error:
        return copyWith(error: color);
      case PaletteSlot.surface:
        return copyWith(surface: color);
      case PaletteSlot.onSurface:
        return copyWith(onSurface: color);
      case PaletteSlot.onAccent:
        return copyWith(onAccent: color);
      case PaletteSlot.outline:
        return copyWith(outline: color);
      case PaletteSlot.success:
        return copyWith(success: color);
      case PaletteSlot.accent:
        return copyWith(accent: color);
    }
  }

  // palette returns the 10 fixed-role colors (in PaletteSlot order) plus
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
    Color? error,
    Color? surface,
    Color? onSurface,
    Color? onAccent,
    Color? outline,
    Color? success,
    Color? accent,
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
        error: error ?? this.error,
        surface: surface ?? this.surface,
        onSurface: onSurface ?? this.onSurface,
        onAccent: onAccent ?? this.onAccent,
        outline: outline ?? this.outline,
        success: success ?? this.success,
        accent: accent ?? this.accent,
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

  // toAppTheme deliberately does NOT force primary/secondary/tertiary/error
  // (or their "on" counterparts) into ColorScheme.fromSeed the way an
  // earlier version of this method did -- those roles drive the foreground
  // of many standard Material widgets (e.g. OutlinedButton's text/icon
  // color defaults to colorScheme.primary), and forcing them to the user's
  // raw palette swatch (which can easily equal or nearly equal `surface`,
  // as the seed defaults below do) produces illegible text-on-background.
  // Only `seedColor` (== primary, exactly as the original hand-built
  // "dark"/"light" AppThemes below only ever passed a single seed) and the
  // background-ish `surface`/its container tones are passed explicitly;
  // Material safely derives properly-contrasting primary/secondary/
  // tertiary/error/onX tones from the seed, exactly like "dark"/"light" do.
  // This also keeps an unedited draft preset (see seedFromDark/Light)
  // visually near-identical to the built-in theme it was cloned from,
  // since it's produced by the same formula with the same seed value.
  AppTheme toAppTheme() {
    var textTheme =
        brightness == Brightness.dark ? interTextTheme : interBlackTextTheme;
    var data = ThemeData.from(
      useMaterial3: true,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        onSurfaceVariant: Colors.grey[600],
        surface: surface,
        surfaceContainerLow: _darken(surface, 0.012),
        surfaceContainerLowest: _darken(surface, 0.022),
      ),
    ).copyWith(
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        selectedTileColor:
            brightness == Brightness.dark ? Colors.grey[850] : Colors.grey[100],
        iconColor: onSurface,
      ),
      hintColor: onSurface.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        scrolledUnderElevation: 0,
      ),
      disabledColor: Colors.grey[850],
    );

    return AppTheme(
      key: "custom:$id",
      descr: name,
      data: data,
      extraColors: CustomColors(successOnSurface: success),
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
        "palette": {
          for (var slot in PaletteSlot.values) slot.name: _hex(forSlot(slot)),
        },
        if (extraPaletteColors.isNotEmpty)
          "extraPaletteColors": extraPaletteColors.map(_hex).toList(),
        "areas": areas.map((k, v) => MapEntry(k.name, v.toJson())),
        if (menuLabels != null) "menuLabels": menuLabels,
        if (menuOrder != null) "menuOrder": menuOrder,
      };

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
    return preset.copyWith(
      extraPaletteColors: j["extraPaletteColors"] != null
          ? (j["extraPaletteColors"] as List)
              .map((h) => _fromHex(h as String))
              .toList()
          : const [],
      // Skip any area key that no longer matches a known ThemeArea (e.g.
      // saved by a future/older version of the app) instead of throwing.
      areas: Map.fromEntries((j["areas"] as Map<String, dynamic>? ?? {})
          .entries
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
  // installable presets, just starting points.
  static ThemePreset seedFromDark() => const ThemePreset(
        id: "custom",
        name: "Default Theme",
        brightness: Brightness.dark,
        primary: Color(0xFF19172C),
        secondary: Color(0xFF47464F),
        tertiary: Color(0xFF6F5573),
        error: Color(0xFFBA1A1A),
        surface: Color(0xFF19172C),
        onSurface: Color(0xFFE5E1E9),
        onAccent: Color(0xFFFFFFFF),
        outline: Color(0xFF47464F),
        success: Color(0xFF2D882D),
        accent: Color(0xFFFFC107),
      );

  static ThemePreset seedFromLight() => const ThemePreset(
        id: "custom",
        name: "Default Theme",
        brightness: Brightness.light,
        primary: Color(0xFFE8E7F3),
        secondary: Color(0xFF45464F),
        tertiary: Color(0xFF6F5573),
        error: Color(0xFFBA1A1A),
        surface: Color(0xFFE8E7F3),
        onSurface: Color(0xFF1B1B1F),
        onAccent: Color(0xFFFFFFFF),
        outline: Color(0xFF45464F),
        success: Color(0xFF2D882D),
        accent: Color(0xFFFF6F00),
      );
}
