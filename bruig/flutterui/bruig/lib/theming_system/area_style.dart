import 'dart:io';

import 'package:bruig/theming_system/area_fill.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/area_sides.dart';
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
  // gradientColorIndexes gives each gradient color the same live palette
  // binding solidColorIndex gives the solid one: entry i is the slot
  // gradientColors[i] was picked from, or null for a custom color. Without
  // it a gradient froze whichever colors the palette happened to hold at
  // pick time and then ignored every later edit to those slots.
  final List<int?> gradientColorIndexes;
  final List<double>? gradientStops;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final String? imagePath; // Relative path within the preset's directory.
  final BoxFit imageFit;
  // imagePreset picks one of the built-in background images, for the four
  // areas that offer them (see imageAreas in theming_areas_section.dart).
  // It applies when mode is token (painted over the area's normal color) or
  // image-with-no-imagePath; a user-picked imagePath always wins over it.
  final AreaImagePreset imagePreset;

  // -------------------------------------------------------------------------
  // Border fill -- every area. Same four modes as the background, applied
  // independently, plus width/radius.
  // -------------------------------------------------------------------------
  final AreaBackgroundMode borderMode;
  final Color? borderColor;
  // Same live-slot-tracking role as solidColorIndex above, for borderColor.
  final int? borderColorIndex;
  final List<Color> borderGradientColors;
  // Same live-slot-tracking role as gradientColorIndexes, for the border.
  final List<int?> borderGradientColorIndexes;
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

  // The four *Sides fields are the per-side (per-corner, for the radius)
  // split of the four settings above: null -- the default -- means "not
  // split", i.e. the single value applies all round. Read them through the
  // borderWidths/borderRadii/paddings/margins getters rather than directly,
  // which resolve that fallback. Zero is this app's "use the built-in
  // default" for all four, split or not.
  final SideValues? borderWidthSides;
  final SideValues? borderRadiusSides;
  final SideValues? paddingSides;
  final SideValues? marginSides;

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
  // Same live-slot-tracking role as solidColorIndex, for the divider color.
  final int? sidebarDividerColorIndex;
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
  // Same live-slot-tracking role as solidColorIndex, for the accent color.
  final int? chatListAccentColorIndex;
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
  // avatarTheme colors the fallback avatar circle. Despite living on the
  // Chat area it applies app-wide -- every avatar in the app funnels
  // through the same InteractiveAvatar widget -- but chat is where users
  // see avatars most, and so where they look for the setting.
  final AvatarTheme avatarTheme;
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
  // Account page -- see theming_area_account.dart.
  // -------------------------------------------------------------------------
  // accountCardLayout is a card-based restyle of the Account page: avatar
  // camera badge, and Identity/Relay Counter/Account cards in place of the
  // plain ListTile column. It used to be half of a "Settings page restyle"
  // toggle on the Master area, whose other half -- icon + pill-highlight
  // rows in the Settings left nav -- is gone: every sidebar in the app,
  // Settings' included, already gets that from the Sidebar area's own
  // "Show icons" and "List Rounded Corners" settings.
  final bool accountCardLayout;

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
    this.gradientColorIndexes = const [],
    this.gradientStops,
    this.gradientBegin = Alignment.topLeft,
    this.gradientEnd = Alignment.bottomRight,
    this.imagePath,
    this.imageFit = BoxFit.cover,
    this.imagePreset = AreaImagePreset.standard,
    this.borderMode = AreaBackgroundMode.token,
    this.borderColor,
    this.borderColorIndex,
    this.borderGradientColors = const [],
    this.borderGradientColorIndexes = const [],
    this.borderGradientStops,
    this.borderGradientBegin = Alignment.topLeft,
    this.borderGradientEnd = Alignment.bottomRight,
    this.borderImagePath,
    this.borderImageFit = BoxFit.cover,
    this.borderWidth = 0,
    this.borderRadius = 0,
    this.padding = 0,
    this.margin = 0,
    this.borderWidthSides,
    this.borderRadiusSides,
    this.paddingSides,
    this.marginSides,
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
    this.sidebarDividerColorIndex,
    this.sidebarDividerWidth = 1,
    this.enableMessageActions = false,
    this.showChatListLastMessage = false,
    this.chatListDesignEnabled = false,
    this.chatListCornerRadius,
    this.chatListAccentColor,
    this.chatListAccentColorIndex,
    this.chatListGlowIntensity,
    this.chatListTopHighlight = true,
    this.chatBackdropWash = false,
    this.enableChatSearch = false,
    this.formattingToolbar = false,
    this.composerPolish = false,
    this.squareBubbles = false,
    this.messageLayoutMode,
    this.avatarTheme = AvatarTheme.standard,
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
    this.accountCardLayout = false,
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
    List<int?>? gradientColorIndexes,
    List<double>? gradientStops,
    Alignment? gradientBegin,
    Alignment? gradientEnd,
    String? imagePath,
    bool clearImagePath = false,
    BoxFit? imageFit,
    AreaImagePreset? imagePreset,
    AreaBackgroundMode? borderMode,
    Color? borderColor,
    int? borderColorIndex,
    bool clearBorderColorIndex = false,
    List<Color>? borderGradientColors,
    List<int?>? borderGradientColorIndexes,
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
    // Each of these four takes a clear flag rather than treating null as
    // "leave alone", since null is itself the meaningful "not split" value
    // the editor's per-side toggle switches back to.
    SideValues? borderWidthSides,
    bool clearBorderWidthSides = false,
    SideValues? borderRadiusSides,
    bool clearBorderRadiusSides = false,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    SideValues? marginSides,
    bool clearMarginSides = false,
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
    int? sidebarDividerColorIndex,
    bool clearSidebarDividerColorIndex = false,
    bool clearSidebarDividerColor = false,
    double? sidebarDividerWidth,
    bool? enableMessageActions,
    bool? showChatListLastMessage,
    bool? chatListDesignEnabled,
    double? chatListCornerRadius,
    bool clearChatListCornerRadius = false,
    Color? chatListAccentColor,
    int? chatListAccentColorIndex,
    bool clearChatListAccentColorIndex = false,
    bool clearChatListAccentColor = false,
    double? chatListGlowIntensity,
    bool clearChatListGlowIntensity = false,
    bool? chatListTopHighlight,
    bool? chatBackdropWash,
    bool? enableChatSearch,
    bool? formattingToolbar,
    bool? composerPolish,
    bool? squareBubbles,
    MessageLayoutMode? messageLayoutMode,
    AvatarTheme? avatarTheme,
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
    bool? accountCardLayout,
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
        gradientColorIndexes:
            gradientColorIndexes ?? this.gradientColorIndexes,
        gradientStops: gradientStops ?? this.gradientStops,
        gradientBegin: gradientBegin ?? this.gradientBegin,
        gradientEnd: gradientEnd ?? this.gradientEnd,
        imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
        imageFit: imageFit ?? this.imageFit,
        imagePreset: imagePreset ?? this.imagePreset,
        borderMode: borderMode ?? this.borderMode,
        borderColor: borderColor ?? this.borderColor,
        borderColorIndex: clearBorderColorIndex
            ? null
            : (borderColorIndex ?? this.borderColorIndex),
        borderGradientColors: borderGradientColors ?? this.borderGradientColors,
        borderGradientColorIndexes:
            borderGradientColorIndexes ?? this.borderGradientColorIndexes,
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
        borderWidthSides: clearBorderWidthSides
            ? null
            : (borderWidthSides ?? this.borderWidthSides),
        borderRadiusSides: clearBorderRadiusSides
            ? null
            : (borderRadiusSides ?? this.borderRadiusSides),
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        marginSides:
            clearMarginSides ? null : (marginSides ?? this.marginSides),
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
        sidebarDividerColorIndex: clearSidebarDividerColorIndex
            ? null
            : (sidebarDividerColorIndex ?? this.sidebarDividerColorIndex),
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
        chatListAccentColorIndex: clearChatListAccentColorIndex
            ? null
            : (chatListAccentColorIndex ?? this.chatListAccentColorIndex),
        chatListAccentColor: clearChatListAccentColor
            ? null
            : (chatListAccentColor ?? this.chatListAccentColor),
        chatListGlowIntensity: clearChatListGlowIntensity
            ? null
            : (chatListGlowIntensity ?? this.chatListGlowIntensity),
        chatListTopHighlight: chatListTopHighlight ?? this.chatListTopHighlight,
        chatBackdropWash: chatBackdropWash ?? this.chatBackdropWash,
        enableChatSearch: enableChatSearch ?? this.enableChatSearch,
        formattingToolbar: formattingToolbar ?? this.formattingToolbar,
        composerPolish: composerPolish ?? this.composerPolish,
        squareBubbles: squareBubbles ?? this.squareBubbles,
        avatarTheme: avatarTheme ?? this.avatarTheme,
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
        accountCardLayout: accountCardLayout ?? this.accountCardLayout,
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
        if (gradientColorIndexes.isNotEmpty)
          "gradientColorIndexes": gradientColorIndexes,
        if (gradientStops != null) "gradientStops": gradientStops,
        "gradientBegin": _alignToJson(gradientBegin),
        "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        "imageFit": imageFit.name,
        if (imagePreset != AreaImagePreset.standard)
          "imagePreset": imagePreset.name,
        "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": colorToHex(borderColor!),
        if (borderColorIndex != null) "borderColorIndex": borderColorIndex,
        if (borderGradientColors.isNotEmpty)
          "borderGradientColors": borderGradientColors.map(colorToHex).toList(),
        if (borderGradientColorIndexes.isNotEmpty)
          "borderGradientColorIndexes": borderGradientColorIndexes,
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
        if (borderWidthSides != null)
          "borderWidthSides": borderWidthSides!.toJson(),
        if (borderRadiusSides != null)
          "borderRadiusSides": borderRadiusSides!.toJson(),
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (marginSides != null) "marginSides": marginSides!.toJson(),
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
        if (sidebarDividerColorIndex != null)
          "sidebarDividerColorIndex": sidebarDividerColorIndex,
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
        if (chatListAccentColorIndex != null)
          "chatListAccentColorIndex": chatListAccentColorIndex,
        if (chatListGlowIntensity != null)
          "chatListGlowIntensity": chatListGlowIntensity,
        if (!chatListTopHighlight) "chatListTopHighlight": chatListTopHighlight,
        if (chatBackdropWash) "chatBackdropWash": chatBackdropWash,
        if (enableChatSearch) "enableChatSearch": enableChatSearch,
        if (formattingToolbar) "formattingToolbar": formattingToolbar,
        if (composerPolish) "composerPolish": composerPolish,
        if (squareBubbles) "squareBubbles": squareBubbles,
        if (messageLayoutMode != null)
          "messageLayoutMode": messageLayoutMode!.name,
        if (avatarTheme != AvatarTheme.standard)
          "avatarTheme": avatarTheme.name,
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
        if (accountCardLayout) "accountCardLayout": accountCardLayout,
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
    // Entries are deliberately nullable -- a null slot means that gradient
    // color was custom-picked and has no palette slot to follow.
    List<int?> indexes(String key) => j[key] != null
        ? (j[key] as List).map((e) => (e as num?)?.toInt()).toList()
        : const [];

    return AreaStyle(
      mode: _enumOr(
          AreaBackgroundMode.values, j["mode"], AreaBackgroundMode.token),
      solidColor: color("solidColor"),
      solidColorIndex: (j["solidColorIndex"] as num?)?.toInt(),
      gradientColors: colors("gradientColors"),
      gradientColorIndexes: indexes("gradientColorIndexes"),
      gradientStops: stops("gradientStops"),
      gradientBegin: _alignFromJson(j["gradientBegin"], Alignment.topLeft),
      gradientEnd: _alignFromJson(j["gradientEnd"], Alignment.bottomRight),
      imagePath: j["imagePath"],
      imageFit: _enumOr(BoxFit.values, j["imageFit"], BoxFit.cover),
      // "loginBgPreset" is imagePreset's old, login-screen-only name -- read
      // it as a fallback so presets saved before this became a shared
      // setting keep the login background they were saved with.
      imagePreset: _enumOr(AreaImagePreset.values,
          j["imagePreset"] ?? j["loginBgPreset"], AreaImagePreset.standard),
      borderMode: _enumOr(
          AreaBackgroundMode.values, j["borderMode"], AreaBackgroundMode.token),
      borderColor: color("borderColor"),
      borderColorIndex: (j["borderColorIndex"] as num?)?.toInt(),
      borderGradientColors: colors("borderGradientColors"),
      borderGradientColorIndexes: indexes("borderGradientColorIndexes"),
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
      borderWidthSides: SideValues.fromJson(j["borderWidthSides"]),
      borderRadiusSides: SideValues.fromJson(j["borderRadiusSides"]),
      paddingSides: SideValues.fromJson(j["paddingSides"]),
      marginSides: SideValues.fromJson(j["marginSides"]),
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
      sidebarDividerColorIndex:
          (j["sidebarDividerColorIndex"] as num?)?.toInt(),
      sidebarDividerWidth: number("sidebarDividerWidth") ?? 1,
      enableMessageActions: flag("enableMessageActions"),
      showChatListLastMessage: flag("showChatListLastMessage"),
      chatListDesignEnabled: flag("chatListDesignEnabled"),
      chatListCornerRadius: number("chatListCornerRadius"),
      chatListAccentColor: color("chatListAccentColor"),
      chatListAccentColorIndex: (j["chatListAccentColorIndex"] as num?)?.toInt(),
      chatListGlowIntensity: number("chatListGlowIntensity"),
      chatListTopHighlight: flag("chatListTopHighlight", fallback: true),
      chatBackdropWash: flag("chatBackdropWash"),
      enableChatSearch: flag("enableChatSearch"),
      formattingToolbar: flag("formattingToolbar"),
      composerPolish: flag("composerPolish"),
      squareBubbles: flag("squareBubbles"),
      messageLayoutMode:
          _enumOrNull(MessageLayoutMode.values, j["messageLayoutMode"]),
      // "monochromeAvatars" is what this was before it grew from a toggle
      // into a set of variants, back when it lived on the Master area (see
      // ThemePreset.fromJson for moving it across).
      avatarTheme: _enumOr(
          AvatarTheme.values,
          j["avatarTheme"],
          flag("monochromeAvatars")
              ? AvatarTheme.monochrome
              : AvatarTheme.standard),
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
      // "settingsShellRestyle" is accountCardLayout's old name, from when
      // it lived on the Master area (see ThemePreset.fromJson, which moves
      // it across to the Account area a preset saved then won't have).
      accountCardLayout:
          flag("accountCardLayout") || flag("settingsShellRestyle"),
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

  // borderWidths/borderRadii/paddings/margins are the four spacing settings
  // resolved to a value per side: the per-side split if the user made one,
  // otherwise that setting's single value on all four sides.
  SideValues get borderWidths => borderWidthSides ?? SideValues.all(borderWidth);
  SideValues get borderRadii => borderRadiusSides ?? SideValues.all(borderRadius);
  SideValues get paddings => paddingSides ?? SideValues.all(padding);
  SideValues get margins => marginSides ?? SideValues.all(margin);

  // hasBorderWidth is "this style asks for a border on at least one side",
  // the per-side-aware replacement for the old `borderWidth > 0` checks.
  bool get hasBorderWidth => borderWidths.largest > 0;

  // borderSides builds a flat-color Border honoring each side's own width.
  // Note a zero-width side is BorderSide.none rather than a hairline, so
  // splitting a border and zeroing one side really does drop that edge.
  Border borderSides(Color color) {
    var w = borderWidths;
    BorderSide side(double width) => width > 0
        ? BorderSide(color: color, width: width)
        : BorderSide.none;
    return Border(
      left: side(w.left),
      top: side(w.top),
      right: side(w.right),
      bottom: side(w.bottom),
    );
  }

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
  Color? resolveSidebarDividerColor(ThemeNotifier theme) =>
      _liveColor(theme, sidebarDividerColorIndex, sidebarDividerColor);
  Color? resolveChatListAccentColor(ThemeNotifier theme) =>
      _liveColor(theme, chatListAccentColorIndex, chatListAccentColor);

  // _liveColors is _liveColor over a gradient's color list, pairing each
  // color with its own slot binding. `indexes` may be shorter than `raw`
  // (a gradient saved before those bindings existed, or one whose trailing
  // colors were custom-picked), in which case those fall back to the
  // stored color.
  List<Color> _liveColors(
          ThemeNotifier theme, List<Color> raw, List<int?> indexes) =>
      [
        for (var i = 0; i < raw.length; i++)
          _liveColor(theme, i < indexes.length ? indexes[i] : null, raw[i]) ??
              raw[i],
      ];

  // remapPaletteIndexes rewrites every stored palette-slot binding for the
  // removal of palette entry `removed` (see ThemePreset.palette): anything
  // bound past it shifts down a place to keep pointing at the same color,
  // and anything bound to the removed entry itself is unbound, keeping the
  // color it last resolved to as a plain custom color rather than silently
  // adopting whichever color slid into that index.
  AreaStyle remapPaletteIndexes(int removed) {
    int? remap(int? i) => i == null || i < removed
        ? i
        : i == removed
            ? null
            : i - 1;
    return copyWith(
      solidColorIndex: remap(solidColorIndex),
      clearSolidColorIndex: remap(solidColorIndex) == null,
      borderColorIndex: remap(borderColorIndex),
      clearBorderColorIndex: remap(borderColorIndex) == null,
      gradientColorIndexes: gradientColorIndexes.map(remap).toList(),
      borderGradientColorIndexes:
          borderGradientColorIndexes.map(remap).toList(),
      sidebarDividerColorIndex: remap(sidebarDividerColorIndex),
      clearSidebarDividerColorIndex: remap(sidebarDividerColorIndex) == null,
      chatListAccentColorIndex: remap(chatListAccentColorIndex),
      clearChatListAccentColorIndex: remap(chatListAccentColorIndex) == null,
    );
  }

  // resolveGradientColors/resolveBorderGradientColors are the public form,
  // for the theme editor's own dropdowns.
  List<Color> resolveGradientColors(ThemeNotifier theme) =>
      _liveColors(theme, gradientColors, gradientColorIndexes);
  List<Color> resolveBorderGradientColors(ThemeNotifier theme) =>
      _liveColors(theme, borderGradientColors, borderGradientColorIndexes);

  // _backgroundFill/_borderFill resolve this style's two paint layers.
  AreaFill _backgroundFill(
          ThemeNotifier theme, SurfaceColor fallback, String? presetDir) =>
      _resolveFill(mode, theme, fallback,
          solid: resolveSolidColor(theme),
          gradColors: _liveColors(theme, gradientColors, gradientColorIndexes),
          gradStops: gradientStops,
          gradBegin: gradientBegin,
          gradEnd: gradientEnd,
          imgPath: imagePath,
          imgFit: imageFit,
          preset: imagePreset,
          presetDir: presetDir);

  AreaFill _borderFill(
          ThemeNotifier theme, SurfaceColor fallback, String? presetDir) =>
      _resolveFill(borderMode, theme, fallback,
          gradColors: _liveColors(
              theme, borderGradientColors, borderGradientColorIndexes),
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
    // preset is only passed for the background layer -- borders have no
    // built-in image presets (and no image picker of their own).
    AreaImagePreset? preset,
    String? presetDir,
  }) {
    switch (m) {
      case AreaBackgroundMode.token:
        // A non-default image preset paints *over* the area's normal color
        // rather than replacing it: the tiled patterns are translucent, so
        // the theme's own surface color still shows through behind them.
        return AreaFill(
            color: theme.surfaceColor(fallback),
            image: (preset != null && preset != AreaImagePreset.standard)
                ? areaImagePresetImage(preset)
                : null);
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
        // A user-picked image file wins over the built-in presets; with no
        // file picked, the chosen preset is the image (including "Default",
        // unlike token mode above where Default means "no image at all").
        if (imgPath != null && presetDir != null) {
          return AreaFill(
              image: DecorationImage(
                  image: FileImage(File(path.join(presetDir, imgPath))),
                  fit: imgFit));
        }
        return AreaFill(
            color: theme.surfaceColor(fallback),
            image: preset != null ? areaImagePresetImage(preset) : null);
    }
  }

  BorderRadius? get _radius {
    var r = borderRadii;
    return r.isZero ? null : r.radius;
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
    var liveBorderColor = resolveBorderColor(theme);
    var bg = _backgroundFill(theme, fallback, presetDir);
    var border = (borderMode != AreaBackgroundMode.token &&
            liveBorderColor != null &&
            hasBorderWidth)
        ? borderSides(liveBorderColor)
        : null;
    return BoxDecoration(
      color: bg.color,
      gradient: bg.gradient,
      image: bg.image,
      border: border,
      // Flutter can't paint a border whose sides differ together with a
      // borderRadius (Border.paint throws outright), so a per-side border
      // loses the rounding on this flat path. buildContainer, which owns
      // its own widgets, keeps both by nesting instead -- see there.
      borderRadius: border == null || border.isUniform ? _radius : null,
    );
  }

  // buildContainer wraps `child` in this style's full background + border
  // (solid/gradient/image, matching modes independently) + padding/margin.
  // Two kinds of border can't be expressed as a single BoxDecoration -- a
  // gradient/image one (Border only supports flat per-side colors) and a
  // per-side one that also wants rounded corners (Border.paint refuses to
  // combine a non-uniform border with a borderRadius) -- so for both, this
  // nests two containers: an outer one painted with the border's fill,
  // inset by each side's own width, framing an inner one painted with the
  // background fill. That's the standard technique for non-solid borders in
  // Flutter, and it happens to express per-side widths exactly.
  Widget buildContainer(
    ThemeNotifier theme,
    SurfaceColor fallback, {
    required Widget child,
    String? presetDir,
  }) {
    var bg = _backgroundFill(theme, fallback, presetDir);
    var widths = borderWidths;
    var hasBorder = borderMode != AreaBackgroundMode.token && hasBorderWidth;
    var inlineBorder = hasBorder &&
        borderMode == AreaBackgroundMode.solid &&
        widths.isUniform;

    // Any descendant ListTile needs a Material ancestor to paint its
    // background/ink splashes into. When this style paints a real
    // background/border below, the Containers built below would otherwise
    // be the nearest DecoratedBox sitting between the ListTile and whatever
    // Material happens to be further up the tree (e.g. Scaffold's), which
    // trips Flutter's "ListTile background may be invisible" assertion.
    // MaterialType.transparency paints nothing itself, so it just supplies
    // that ancestor without changing this area's appearance.
    var pad = paddings;
    Widget content = Container(
      padding: pad.isZero ? null : pad.insets,
      decoration: BoxDecoration(
        color: bg.color,
        gradient: bg.gradient,
        image: bg.image,
        borderRadius: _radius,
        // A uniform flat color border goes on this same box (matching
        // toBoxDecoration's cheaper path), no extra nesting needed.
        border: inlineBorder
            ? Border.all(
                color: resolveBorderColor(theme) ??
                    theme.surfaceColor(fallback),
                width: widths.left)
            : null,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );

    if (hasBorder && !inlineBorder) {
      // A solid border only lands here when its sides differ, in which case
      // there's no border *fill* to resolve -- just the flat color, painted
      // as the outer box's own background.
      var borderFill = borderMode == AreaBackgroundMode.solid
          ? AreaFill(
              color:
                  resolveBorderColor(theme) ?? theme.surfaceColor(fallback))
          : _borderFill(theme, fallback, presetDir);
      content = Container(
        padding: widths.insets,
        decoration: BoxDecoration(
            color: borderFill.color,
            gradient: borderFill.gradient,
            image: borderFill.image,
            borderRadius: _radius),
        child: content,
      );
    }

    var mar = margins;
    if (!mar.isZero) {
      content = Container(margin: mar.insets, child: content);
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
        !hasBorderWidth) {
      return child;
    }
    var borderFill = _borderFill(theme, fallback, presetDir);
    return Container(
      padding: borderWidths.insets,
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
