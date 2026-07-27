import 'dart:io';

import 'package:bruig/theming_system/area_fill.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/color_hex.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theme_notifier.dart';
import 'package:bruig/theming_system/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// _enumOr resolves a stored enum *name* back to its value, falling back to
// `fallback` for anything unrecognized (data written by a newer/older build).
T _enumOr<T extends Enum>(List<T> values, dynamic name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

// _enumOrNull is _enumOr for a nullable field, where absent means "use this
// area's built-in default" rather than a specific value.
T? _enumOrNull<T extends Enum>(List<T> values, dynamic name) => name == null
    ? null
    : values.where((e) => e.name == name).firstOrNull;

Alignment _alignFromJson(dynamic j, Alignment fallback) => j != null
    ? Alignment((j[0] as num).toDouble(), (j[1] as num).toDouble())
    : fallback;
List<double> _alignToJson(Alignment a) => [a.x, a.y];

// AreaStyle is the full set of visual overrides a user can apply to a single
// ThemeArea. mode == token (the default) means "use the app's normal color
// scheme", producing an identical appearance to what the area rendered
// before this feature existed.
//
// Fields are grouped below in the same order the theme editor presents them:
// first the ones shared by every area (background fill, border fill, spacing
// and size), then one block per area, each matching a theming_area_<name>.
// dart editor file. Everything an area contributes lives on this one class
// -- the whole style is persisted, copied and diffed as a single value.
class AreaStyle {
  // -------------------------------------------------------------------------
  // Background fill -- every area. See area_fill.dart.
  // -------------------------------------------------------------------------
  final AreaBackgroundMode mode;
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

  // -------------------------------------------------------------------------
  // Border fill -- every area. Same four modes as the background, applied
  // independently, plus width/radius.
  // -------------------------------------------------------------------------
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

  // -------------------------------------------------------------------------
  // Spacing and size -- every area (with the noted exceptions).
  // -------------------------------------------------------------------------
  final double padding; // Inset between the border and the content.
  final double margin; // Outer spacing around the whole area.

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

  // -------------------------------------------------------------------------
  // Header -- see theming_area_header.dart.
  // -------------------------------------------------------------------------

  // contentAlign controls where the area's primary content (the header's
  // title) sits within the area; null means "use the default alignment".
  final ContentAlign? contentAlign;

  // headerPosition controls where/whether the header renders at all. Null
  // means HeaderPosition.top (today's behavior).
  final HeaderPosition? headerPosition;

  // logoSize overrides the app-icon logo size; meaningful for header (its
  // own logo, independent of the header's height) and navBar (see
  // showLogo below). Null means the built-in default (40 for header, 32
  // for navBar).
  final double? logoSize;

  // -------------------------------------------------------------------------
  // Navigation bar -- see theming_area_navbar.dart.
  // -------------------------------------------------------------------------

  // showLogo displays the Bison Relay logo at the top of the nav bar.
  // Intended for when the header is set to HeaderPosition.content or .none,
  // since the header's own logo disappears in both of those (the header
  // only spans the content area, or doesn't render at all), but it's an
  // independent toggle either way.
  final bool showLogo;

  // logoAlign positions the nav bar logo (showLogo above) horizontally;
  // only start/center/end are used (hidden doesn't apply -- showLogo
  // already covers visibility). Null means center.
  final ContentAlign? logoAlign;

  // -------------------------------------------------------------------------
  // Sidebar -- see theming_area_sidebar.dart. These apply uniformly to every
  // sidebar built from SecondarySideMenuList/SecondarySideMenuItem
  // (Settings, LN Management, Feed, Manage Content, Address Book, page-view
  // sessions, the chat list, and the Realtime Chat session list) -- not just
  // one screen. Sidebar/nav bar text+accent *colors* are not here: they're
  // always-present top-level palette slots (sidebarText/sidebarAccent/
  // navText/navAccent on ThemePreset), since there's only ever one sidebar/
  // nav bar per theme.
  // -------------------------------------------------------------------------

  // subMenuStyle controls how a page's submenu shows/hides itself. Null
  // means SubMenuStyle.alwaysVisible (today's behavior).
  final SubMenuStyle? subMenuStyle;

  // showHoverArrow toggles the small chevron indicator shown on the
  // collapsed edge strip when subMenuStyle is hoverReveal. True (shown) is
  // the default/unmodified state.
  final bool showHoverArrow;

  // sidebarCornerRadius is the corner radius of the pill-highlight rows;
  // 0 reads as a plain square-cornered row.
  final double sidebarCornerRadius;
  final bool sidebarShowIcons; // Leading icon on each row.
  final bool sidebarShowRightDivider; // The plain right-edge divider line
  // shown when the sidebar is otherwise unmodified; default on. Independent
  // of the general border editor, which can already replace it entirely.
  final Color? sidebarDividerColor; // Null = built-in default
  // (extraColors.sidebarDivider). Only meaningful when
  // sidebarShowRightDivider is on.
  final double sidebarDividerWidth; // Default 1 (BorderSide's own default).

  // -------------------------------------------------------------------------
  // Chat -- see theming_area_chat.dart. Each toggle gates a distinct chat
  // feature ported from the exitus1 fork; all default to false (off) so
  // existing chat behavior is unchanged until a user opts in.
  // -------------------------------------------------------------------------
  final bool enableMessageActions; // Reply + Pin context-menu actions.
  final bool showChatListLastMessage; // Last-message preview + timestamp.
  final bool chatListDesignEnabled; // Rounded/glow chat list row styling.
  final double? chatListCornerRadius; // Null = built-in default (14).
  final Color? chatListAccentColor; // Null = built-in default (blue).
  final double?
      chatListGlowIntensity; // Null = built-in default (1.0); 0 = off.
  final bool chatListTopHighlight; // Ambient top-left glow + lit hairline
  // on inactive rows (vs. a flat background); default on.
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

  // -------------------------------------------------------------------------
  // Realtime chat -- see theming_area_realtimechat.dart.
  // -------------------------------------------------------------------------
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

  // -------------------------------------------------------------------------
  // Stats -- see theming_area_stats.dart.
  // -------------------------------------------------------------------------
  final bool payStatsCardStyle; // Summary cards (total sent/received) +
  // redesigned per-user rows (avatar, inline sent-amount bar chart,
  // DCR-formatted amounts) on the Payment Stats page.

  // -------------------------------------------------------------------------
  // Master background -- see theming_area_master.dart. The app-wide chrome
  // settings; the Settings screen isn't itself a per-content ThemeArea, so
  // its restyle rides on the closest "global chrome" area.
  // -------------------------------------------------------------------------
  final bool settingsShellRestyle; // Icon + pill-highlight rows in the
  // Settings page's left nav, and a card-based restyle of the Account
  // page (avatar camera badge, Identity/Relay Counter/Account cards).
  // monochromeAvatars is app-wide: every avatar in the app funnels through
  // the same InteractiveAvatar widget.
  final bool monochromeAvatars; // Graphite fallback avatars, app-wide.

  // -------------------------------------------------------------------------
  // Login screen -- see theming_area_login.dart.
  // -------------------------------------------------------------------------
  final LoginBackgroundPreset loginBgPreset; // See LoginBackgroundPreset.

  // -------------------------------------------------------------------------
  // Feed -- see theming_area_feed.dart. Each toggle gates a distinct feed
  // feature ported from the exitus1 fork; all default to false (off).
  // Several only have a visible effect when feedCardRedesign is also on
  // (they render into the new card's action bar, which the old card layout
  // doesn't have).
  // -------------------------------------------------------------------------
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

  const AreaStyle({
    this.mode = AreaBackgroundMode.token,
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

  // toJson omits every field still at its default, so a preset's saved
  // "areas" map only records what the user actually changed.
  Map<String, dynamic> toJson() => {
        "mode": mode.name,
        if (solidColor != null) "solidColor": colorToHex(solidColor!),
        if (solidColorIndex != null) "solidColorIndex": solidColorIndex,
        if (gradientColors.isNotEmpty)
          "gradientColors": gradientColors.map(colorToHex).toList(),
        if (gradientStops != null) "gradientStops": gradientStops,
        "gradientBegin": _alignToJson(gradientBegin),
        "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        "imageFit": imageFit.name,
        "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": colorToHex(borderColor!),
        if (borderColorIndex != null) "borderColorIndex": borderColorIndex,
        if (borderGradientColors.isNotEmpty)
          "borderGradientColors": borderGradientColors.map(colorToHex).toList(),
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
          "sidebarDividerColor": colorToHex(sidebarDividerColor!),
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
          "chatListAccentColor": colorToHex(chatListAccentColor!),
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

  factory AreaStyle.fromJson(Map<String, dynamic> j) {
    Color? color(String key) =>
        j[key] != null ? colorFromHex(j[key] as String) : null;
    double? number(String key) => (j[key] as num?)?.toDouble();
    bool flag(String key, {bool fallback = false}) =>
        j[key] as bool? ?? fallback;
    List<Color> colors(String key) => j[key] != null
        ? (j[key] as List).map((e) => colorFromHex(e as String)).toList()
        : const [];
    List<double>? stops(String key) => j[key] != null
        ? (j[key] as List).map((e) => (e as num).toDouble()).toList()
        : null;

    return AreaStyle(
      mode: _enumOr(
          AreaBackgroundMode.values, j["mode"], AreaBackgroundMode.token),
      solidColor: color("solidColor"),
      solidColorIndex: (j["solidColorIndex"] as num?)?.toInt(),
      gradientColors: colors("gradientColors"),
      gradientStops: stops("gradientStops"),
      gradientBegin: _alignFromJson(j["gradientBegin"], Alignment.topLeft),
      gradientEnd: _alignFromJson(j["gradientEnd"], Alignment.bottomRight),
      imagePath: j["imagePath"],
      imageFit: _enumOr(BoxFit.values, j["imageFit"], BoxFit.cover),
      borderMode: _enumOr(
          AreaBackgroundMode.values, j["borderMode"], AreaBackgroundMode.token),
      borderColor: color("borderColor"),
      borderColorIndex: (j["borderColorIndex"] as num?)?.toInt(),
      borderGradientColors: colors("borderGradientColors"),
      borderGradientStops: stops("borderGradientStops"),
      borderGradientBegin:
          _alignFromJson(j["borderGradientBegin"], Alignment.topLeft),
      borderGradientEnd:
          _alignFromJson(j["borderGradientEnd"], Alignment.bottomRight),
      borderImagePath: j["borderImagePath"],
      borderImageFit: _enumOr(BoxFit.values, j["borderImageFit"], BoxFit.cover),
      borderWidth: number("borderWidth") ?? 0,
      borderRadius: number("borderRadius") ?? 0,
      padding: number("padding") ?? 0,
      margin: number("margin") ?? 0,
      width: number("width"),
      height: number("height"),
      contentAlign: _enumOrNull(ContentAlign.values, j["contentAlign"]),
      logoSize: number("logoSize"),
      headerPosition: _enumOrNull(HeaderPosition.values, j["headerPosition"]),
      showLogo: flag("showLogo"),
      logoAlign: _enumOrNull(ContentAlign.values, j["logoAlign"]),
      subMenuStyle: _enumOrNull(SubMenuStyle.values, j["subMenuStyle"]),
      showHoverArrow: flag("showHoverArrow", fallback: true),
      sidebarCornerRadius: number("sidebarCornerRadius") ?? 12,
      sidebarShowIcons: flag("sidebarShowIcons"),
      sidebarShowRightDivider: flag("sidebarShowRightDivider", fallback: true),
      sidebarDividerColor: color("sidebarDividerColor"),
      sidebarDividerWidth: number("sidebarDividerWidth") ?? 1,
      enableMessageActions: flag("enableMessageActions"),
      showChatListLastMessage: flag("showChatListLastMessage"),
      chatListDesignEnabled: flag("chatListDesignEnabled"),
      chatListCornerRadius: number("chatListCornerRadius"),
      chatListAccentColor: color("chatListAccentColor"),
      chatListGlowIntensity: number("chatListGlowIntensity"),
      chatListTopHighlight: flag("chatListTopHighlight", fallback: true),
      monochromeAvatars: flag("monochromeAvatars"),
      chatBackdropWash: flag("chatBackdropWash"),
      enableChatSearch: flag("enableChatSearch"),
      formattingToolbar: flag("formattingToolbar"),
      composerPolish: flag("composerPolish"),
      squareBubbles: flag("squareBubbles"),
      messageLayoutMode:
          _enumOrNull(MessageLayoutMode.values, j["messageLayoutMode"]),
      expandMessageWidth: flag("expandMessageWidth"),
      expandMessagePadding: number("expandMessagePadding"),
      autoUnmuteOnJoin: flag("autoUnmuteOnJoin"),
      enhancedCallIndicators: flag("enhancedCallIndicators"),
      rtcAudioTestPanel: flag("rtcAudioTestPanel"),
      rtcCollapsibleSessionInfo: flag("rtcCollapsibleSessionInfo"),
      rtcLobbyHero: flag("rtcLobbyHero"),
      rtcLiveStage: flag("rtcLiveStage"),
      rtcStyledSessionList: flag("rtcStyledSessionList"),
      rtcSessionListIntro: flag("rtcSessionListIntro"),
      payStatsCardStyle: flag("payStatsCardStyle"),
      settingsShellRestyle: flag("settingsShellRestyle"),
      loginBgPreset: _enumOr(LoginBackgroundPreset.values, j["loginBgPreset"],
          LoginBackgroundPreset.standard),
      feedCardRedesign: flag("feedCardRedesign"),
      feedCardActions: flag("feedCardActions"),
      feedBookmarks: flag("feedBookmarks"),
      feedHidePosts: flag("feedHidePosts"),
      feedSidePanel: flag("feedSidePanel"),
      feedInlineComposer: flag("feedInlineComposer"),
      feedComposerFormatting: flag("feedComposerFormatting"),
      feedComposerAttach: flag("feedComposerAttach"),
      feedDrafts: flag("feedDrafts"),
      feedHideSidebarOnPost: flag("feedHideSidebarOnPost"),
      feedImageLayout: _enumOr(
          FeedImageLayout.values, j["feedImageLayout"], FeedImageLayout.standard),
      feedImageCropHeight: number("feedImageCropHeight") ?? 300,
      feedTextOrder: _enumOr(
          FeedTextOrder.values, j["feedTextOrder"], FeedTextOrder.standard),
      feedLinksMode: _enumOr(
          FeedLinksMode.values, j["feedLinksMode"], FeedLinksMode.standard),
      feedTextLimit: number("feedTextLimit") ?? 0,
      feedStripMarkdown: flag("feedStripMarkdown"),
    );
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

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

  // _backgroundFill/_borderFill resolve this style's two paint layers.
  AreaFill _backgroundFill(
          ThemeNotifier theme, SurfaceColor fallback, String? presetDir) =>
      _resolveFill(mode, theme, fallback,
          solid: resolveSolidColor(theme),
          gradColors: gradientColors,
          gradStops: gradientStops,
          gradBegin: gradientBegin,
          gradEnd: gradientEnd,
          imgPath: imagePath,
          imgFit: imageFit,
          presetDir: presetDir);

  AreaFill _borderFill(
          ThemeNotifier theme, SurfaceColor fallback, String? presetDir) =>
      _resolveFill(borderMode, theme, fallback,
          gradColors: borderGradientColors,
          gradStops: borderGradientStops,
          gradBegin: borderGradientBegin,
          gradEnd: borderGradientEnd,
          imgPath: borderImagePath,
          imgFit: borderImageFit,
          presetDir: presetDir);

  AreaFill _resolveFill(
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
        return AreaFill(color: theme.surfaceColor(fallback));
      case AreaBackgroundMode.none:
        return const AreaFill(color: Colors.transparent);
      case AreaBackgroundMode.solid:
        return AreaFill(color: solid ?? theme.surfaceColor(fallback));
      case AreaBackgroundMode.gradient:
        if (gradColors.length >= 2) {
          return AreaFill(
              gradient: LinearGradient(
                  begin: gradBegin,
                  end: gradEnd,
                  colors: gradColors,
                  stops: gradStops));
        }
        return AreaFill(color: theme.surfaceColor(fallback));
      case AreaBackgroundMode.image:
        if (imgPath != null && presetDir != null) {
          return AreaFill(
              image: DecorationImage(
                  image: FileImage(File(path.join(presetDir, imgPath))),
                  fit: imgFit));
        }
        return AreaFill(color: theme.surfaceColor(fallback));
    }
  }

  BorderRadius? get _radius =>
      borderRadius > 0 ? BorderRadius.circular(borderRadius) : null;

  // toBoxDecoration resolves this style's *background* (and, if the border
  // is a flat color, a matching BorderSide) into a single BoxDecoration.
  // This is the cheap path used by areas that are composed into an existing
  // widget's own decoration (app bar, side nav, sub-menu divider) rather
  // than wrapped in their own container -- it can't express a gradient or
  // image border (see buildContainer for that), but reproduces the area's
  // original appearance exactly when mode is token and there's no border.
  BoxDecoration toBoxDecoration(ThemeNotifier theme, SurfaceColor fallback,
      {String? presetDir}) {
    var liveBorderColor = resolveBorderColor(theme);
    var bg = _backgroundFill(theme, fallback, presetDir);
    return BoxDecoration(
      color: bg.color,
      gradient: bg.gradient,
      image: bg.image,
      border: (borderMode != AreaBackgroundMode.token &&
              liveBorderColor != null &&
              borderWidth > 0)
          ? Border.all(color: liveBorderColor, width: borderWidth)
          : null,
      borderRadius: _radius,
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
    var bg = _backgroundFill(theme, fallback, presetDir);
    var hasBorder =
        borderMode != AreaBackgroundMode.token && borderWidth > 0;
    var solidBorder = hasBorder && borderMode == AreaBackgroundMode.solid;

    // Any descendant ListTile needs a Material ancestor to paint its
    // background/ink splashes into. When this style paints a real
    // background/border below, the Containers built below would otherwise
    // be the nearest DecoratedBox sitting between the ListTile and whatever
    // Material happens to be further up the tree (e.g. Scaffold's), which
    // trips Flutter's "ListTile background may be invisible" assertion.
    // MaterialType.transparency paints nothing itself, so it just supplies
    // that ancestor without changing this area's appearance.
    Widget content = Container(
      padding: padding > 0 ? EdgeInsets.all(padding) : null,
      decoration: BoxDecoration(
        color: bg.color,
        gradient: bg.gradient,
        image: bg.image,
        borderRadius: _radius,
        // A flat color border goes on this same box (matching
        // toBoxDecoration's cheaper path), no extra nesting needed.
        border: solidBorder
            ? Border.all(
                color: resolveBorderColor(theme) ??
                    theme.surfaceColor(fallback),
                width: borderWidth)
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

    if (hasBorder && !solidBorder) {
      var borderFill = _borderFill(theme, fallback, presetDir);
      content = Container(
        padding: EdgeInsets.all(borderWidth),
        decoration: BoxDecoration(
            color: borderFill.color,
            gradient: borderFill.gradient,
            image: borderFill.image,
            borderRadius: _radius),
        child: content,
      );
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
    var borderFill = _borderFill(theme, fallback, presetDir);
    return Container(
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        color: borderFill.color,
        gradient: borderFill.gradient,
        image: borderFill.image,
        borderRadius: _radius,
      ),
      child: child,
    );
  }
}
