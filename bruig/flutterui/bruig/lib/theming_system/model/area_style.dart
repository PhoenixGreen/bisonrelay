import 'package:bruig/theming_system/model/area_fill.dart';
import 'package:bruig/theming_system/model/area_options.dart';
import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/model/theme_area.dart';
import 'package:flutter/material.dart';

// _enumOr resolves a stored enum *name* back to its value, falling back to
// `fallback` for anything unrecognized (data written by a newer/older build).
T _enumOr<T extends Enum>(List<T> values, dynamic name, T fallback) =>
    values.firstWhere((e) => e.name == name, orElse: () => fallback);

// _enumOrNull is _enumOr for a nullable field, where absent means "use this
// area's built-in default" rather than a specific value.
T? _enumOrNull<T extends Enum>(List<T> values, dynamic name) =>
    name == null ? null : values.where((e) => e.name == name).firstOrNull;

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
// and size), then one block per area, each matching an editor/areas/<name>.
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
  // areas that offer them (see imageAreas in editor/areas_section.dart).
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

  // height overrides the area's own layout height -- only meaningful for
  // header (the app bar's height); null means "use the default toolbar
  // height".
  final double? height;

  // -------------------------------------------------------------------------
  // Header -- see editor/areas/header.dart.
  // -------------------------------------------------------------------------

  // contentAlign controls where the area's primary content (the header's
  // title) sits within the area; null means "use the default alignment".
  final ContentAlign? contentAlign;

  // headerPosition controls where/whether the header renders at all. Null
  // means HeaderPosition.top (today's behavior).
  final HeaderPosition? headerPosition;

  // logoPath replaces the Bison Relay icon app-wide with the user's own
  // image, as a path relative to the preset's directory (same storage as
  // the background images). Null -- the default -- is the built-in icon,
  // which is what clearing this returns to. It lives on the header area
  // because that's where it's edited, but every place the app draws its
  // icon reads it (see BisonRelayLogo).
  final String? logoPath;

  // logoSize overrides the app-icon logo size; meaningful for header (its
  // own logo, independent of the header's height) and navBar (see
  // showLogo below). Null means the built-in default (40 for header, 32
  // for navBar).
  final double? logoSize;

  // loginLogoSize is the same icon where it appears on the login/startup
  // screens (the About button in their top-left corner). It lives on the
  // header area beside the other icon settings even though it isn't the
  // header, because the icon itself is one app-wide setting and splitting
  // its sizes across two areas would hide half of them. Null = the 24 the
  // icon theme gives that button.
  final double? loginLogoSize;

  // The header's individual elements, each switchable off on its own. They
  // apply wherever the header renders -- HeaderPosition.top and .content
  // draw the same set of elements, so which of them appear is this
  // decision rather than a side effect of where the bar sits. Stored as
  // "hide" flags so that false (everything visible, which is what the
  // header always looked like before these existed) stays out of the saved
  // JSON entirely.
  //
  // hideHeaderTitle is the same outcome as ContentAlign.hidden, which
  // predates it and still works; it's here too so the title switches off
  // beside the other elements rather than only from the alignment
  // dropdown.
  final bool hideHeaderLogo; // The app icon / "About Bison Relay" button.
  final bool hideHeaderTitle; // The page title text.
  final bool hideHeaderNewPost; // The "Create a new post" icon.
  final bool hideHeaderCallIcon; // The chat "call" icon.
  final bool hideHeaderNewSession; // Realtime Chat's "Create new session".

  // Hover text, in two halves (master area; see components/tooltips.dart).
  // hideTooltips drops the labels on controls a user already recognises --
  // the avatars, the post/attach icons, the app icon -- which read as
  // clutter once the app is familiar. hideHelpTooltips is the separate
  // decision about the few tooltips that explain something not written
  // anywhere else, like the help icon beside a content cost.
  final bool hideTooltips;
  final bool hideHelpTooltips;

  // Chat: the fill behind the conversation itself -- the region the
  // message bubbles sit on, as distinct from the chat list beside it.
  // Unset it follows the palette's Content Background, which is what
  // showed through before it could be set at all.
  final Color? messageAreaColor;
  final int? messageAreaColorIndex;

  // Chat: collapses the composer's tool icons behind a single button that
  // opens them to the right. On a narrow screen those icons take so much
  // of the row that the text field is left a few characters wide (the hint
  // wraps one letter per line), and the microphone sitting outside the
  // field costs it more still.
  final bool collapseComposerIcons;

  // Input Areas: one background, border and shape for every text input in
  // the app. All null/zero means each input keeps Flutter's own default
  // for that property, which is what they looked like before this area
  // existed -- so an untouched theme is unchanged.
  final Color? inputBackgroundColor;
  final int? inputBackgroundColorIndex;
  final Color? inputBorderColor;
  final int? inputBorderColorIndex;
  final double inputBorderWidth;
  final double inputBorderRadius;

  // Buttons: one entry per ButtonRole, holding that role's background,
  // hover, border, padding and margin overrides. A map (rather than five
  // sets of flat fields here) because the five roles are the same handful
  // of settings five times over, and because it lets a role be absent
  // entirely -- which is what "this button is untouched" means, and what
  // keeps an untouched preset's JSON as small as it was before the area
  // existed. See button_style.dart.
  final Map<ButtonRole, ButtonAreaStyle> buttonStyles;

  // File Manager: drops the on-disk path from each downloaded file, which
  // is the longest line in the row and the same leading directories on
  // every one of them. What's left is the file name over its size and
  // sender.
  final bool hideFilePaths;

  // -------------------------------------------------------------------------
  // Navigation bar -- see editor/areas/navbar.dart.
  // -------------------------------------------------------------------------

  // navRoutes is which main-menu destinations the navigation carries, by
  // route name. Null -- the default -- means all of them.
  //
  // One list for both bars. The desktop nav bar and the phone's bottom bar
  // are the same navigation at two sizes, and a destination switched off in
  // one of them but not the other is a destination the user has to remember
  // the shape of the window to find. Set in Settings > Appearance > Menu,
  // beside the reorder and rename controls for the same items, rather than
  // in an area editor -- which of them the navigation carries is a fact
  // about the menu, like their order and their names.
  //
  // Only *which* items, never their order or their labels -- both of those
  // come from the menu itself, so the two bars can't drift into disagreeing
  // about what a destination is called or where it sits. An unknown route
  // name in a saved list resolves to nothing: a list from a build (or a
  // plugin) that had a destination this one doesn't just carries one item
  // fewer.
  final List<String>? navRoutes;

  // showLogo displays the Bison Relay logo at the top of the nav bar.
  // Intended for when the header is set to HeaderPosition.content or .none,
  // since the header's own logo disappears in both of those (the header
  // only spans the content area, or doesn't render at all), but it's an
  // independent toggle either way.
  final bool showLogo;

  // The DCR/BTC price rows at the foot of the nav bar: a coin icon with a
  // direction arrow over it, and the price beside it while the bar is
  // extended. Off by default -- the prices come from the client's own rate
  // tracker (see ExchangeRateModel), so showing them costs nothing, but
  // they're not something every theme wants.
  final bool showDcrPrice;
  final bool showBtcPrice;
  final double? priceIconSize; // Null = the built-in 26.
  // Inset around each price row, and its per-side split -- one per coin,
  // so a row can be nudged or spaced independently of the other. Applied
  // only while the nav bar is extended: collapsed, the icons are centred in
  // a column with barely more room than the icon itself, so a horizontal
  // inset there could only push them off-centre or clip them.
  final double dcrPricePadding;
  final SideValues? dcrPricePaddingSides;
  final double btcPricePadding;
  final SideValues? btcPricePaddingSides;

  // logoAlign positions the nav bar logo (showLogo above) horizontally;
  // only start/center/end are used (hidden doesn't apply -- showLogo
  // already covers visibility). Null means center.
  final ContentAlign? logoAlign;

  // -------------------------------------------------------------------------
  // Sidebar -- see editor/areas/sidebar.dart. These apply uniformly to every
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

  // sidebarCornerRadius is the corner radius of the pill-highlight rows;
  // 0 reads as a plain square-cornered row.
  final double sidebarCornerRadius;
  final bool sidebarShowIcons; // Leading icon on each row.
  // The sidebar's right edge is the area's ordinary Border -- Border color
  // plus the right side of a per-side Border width -- rather than a second,
  // sidebar-only way to say the same thing. Left alone, the sidebar still
  // draws its built-in divider (see SecondarySideMenu).

  // -------------------------------------------------------------------------
  // Chat -- see editor/areas/chat.dart. Each toggle gates a distinct chat
  // feature ported from the exitus1 fork; all default to false (off) so
  // existing chat behavior is unchanged until a user opts in.
  // -------------------------------------------------------------------------
  final bool enableMessageActions; // Reply + Pin context-menu actions.
  final bool showChatListLastMessage; // Last-message preview + timestamp.
  final bool chatListDesignEnabled; // Rounded/glow chat list row styling.
  final double? chatListCornerRadius; // Null = built-in default (14).
  final Color? chatListAccentColor; // Null = built-in default (blue).
  // chatListBackgroundColor is the row background the whole chat-list
  // design is shaded from -- its hover and selected treatments included.
  // Null = the built-in near-black.
  final Color? chatListBackgroundColor;
  final int? chatListBackgroundColorIndex;
  // chatListSelectedColor is the selected row's own fill. Null keeps the
  // built-in default, which is chatListBackgroundColor shaded a little
  // darker (see _shade in chats_list.dart).
  final Color? chatListSelectedColor;
  final int? chatListSelectedColorIndex;
  // Same live-slot-tracking role as solidColorIndex, for the accent color.
  final int? chatListAccentColorIndex;
  final double?
      chatListGlowIntensity; // Null = built-in default (1.0); 0 = off.
  final bool chatListTopHighlight; // Ambient top-left glow + lit hairline
  // on inactive rows (vs. a flat background); default on.
  final bool chatBackdropWash; // Radial-gradient wash behind messages.
  final bool enableChatSearch; // In-chat message search panel.
  // chatSidebarFooter is the row of icons under the chat list -- generate
  // an invite, list message times, fetch an invite, new group chat, new
  // message, GC invitations. Default on.
  //
  // Every one of them is a page of the Address Book, and that is where each
  // now goes: the row is a shortcut into it rather than six dead-end
  // screens of its own. Left as a setting because the Address Book's own
  // menu item reaches all six as well, so on a narrow window it is a second
  // route to the same six places.
  final bool chatSidebarFooter;
  final bool formattingToolbar; // Composer markdown formatting toolbar.
  final bool composerPolish; // Tip button, glow send, dynamic hint.
  // bubbleCorners hands the message bubbles' corners to the user: a radius
  // per direction (each splittable per corner via the *Sides fields) and a
  // shape for how those corners are cut. Off -- the default -- leaves both
  // directions on the built-in radius.
  final bool bubbleCorners;
  final double bubbleRadiusSent;
  final SideValues? bubbleRadiusSentSides;
  final double bubbleRadiusReceived;
  final SideValues? bubbleRadiusReceivedSides;
  final BubbleCornerStyle bubbleCornerStyle;
  final MessageLayoutMode? messageLayoutMode; // Null = standard/default.
  // messageSpacing is the gap above a message from a different sender than
  // the one before it. Null = the built-in 10. Messages from the *same*
  // sender keep their tighter gap, at the same proportion the built-in
  // pair already uses (2 of 10), so a conversation still reads as groups of
  // messages rather than an evenly spaced list however far it is opened up.
  final double? messageSpacing;
  // avatarTheme colors the fallback avatar circle. Despite living on the
  // Chat area it applies app-wide -- every avatar in the app funnels
  // through the same InteractiveAvatar widget -- but chat is where users
  // see avatars most, and so where they look for the setting.
  final AvatarTheme avatarTheme;
  final bool expandMessageWidth; // Fill the panel instead of margining in;
  // only meaningful when messageLayoutMode != null/standard.
  // expandMessagePadding is the room around the whole conversation viewport:
  // above it, beside it, and before the input bar. Null = the built-in 0,
  // which fills the panel edge-to-edge as the chat always did.
  //
  // Despite the name it shares with the two fields around it, this applies in
  // every message layout and whether or not expandMessageWidth is on. The
  // name is the accident of it having shipped with them; what it does is
  // unrelated -- those are the width of a *message*, this is the space around
  // the *viewport*. It was gated on them once, which made the editor offer a
  // slider on the Default layout that moved nothing.
  final double? expandMessagePadding;
  final SideValues? expandMessagePaddingSides; // Per-side split of it.

  // -------------------------------------------------------------------------
  // Realtime chat -- see editor/areas/realtimechat.dart.
  // -------------------------------------------------------------------------
  // The screen's own layout -- its lobby header, live stage, session-info
  // row and pre-join audio test -- is simply how the page is built, not a
  // theme setting: a theme area is the wrong place to decide whether a
  // screen has a header. Only the two below are genuinely per-theme.
  final bool autoUnmuteOnJoin; // Auto-unmute + snackbar on joining a call.
  // The session-list row's own corner radius, matching the chat list's --
  // 0 reads as a plain square-cornered row. Null = the built-in 12.
  final double? rtcSessionCornerRadius;
  // The active session row's fill. Null = the built-in near-black.
  final Color? rtcActiveSessionColor;
  final int? rtcActiveSessionColorIndex;
  // The live/speaking accent: the live dot, its glow, and the speaking
  // ring around an avatar. Null = the built-in green.
  final Color? rtcLiveColor;
  final int? rtcLiveColorIndex;
  // The muted/trouble accent: a muted badge, the "LIVE" label, a mic that
  // is off, the weakest signal bar. Null = the built-in red.
  final Color? rtcMutedColor;
  final int? rtcMutedColorIndex;
  // The middling accent, used where a state is neither good nor bad: the
  // two-bar connection reading. Null = the built-in amber.
  final Color? rtcWarningColor;
  final int? rtcWarningColorIndex;
  // How large a speaker is drawn on the live stage, as the avatar's radius.
  // Null = the built-in 34.
  final double? rtcStageAvatarRadius;
  // Whether the live stage opens folded away, leaving the session's
  // messages the whole page. It can still be opened by hand.
  final bool rtcStageCollapsed;

  // -------------------------------------------------------------------------
  // Stats -- see editor/areas/settings_pages.dart.
  // -------------------------------------------------------------------------
  final bool payStatsCardStyle; // Summary cards (total sent/received) +
  // redesigned per-user rows (avatar, inline sent-amount bar chart,
  // DCR-formatted amounts) on the Payment Stats page.

  // -------------------------------------------------------------------------
  // Account page -- see editor/areas/settings_pages.dart.
  // -------------------------------------------------------------------------
  // accountCardLayout is a card-based restyle of the Account page: avatar
  // camera badge, and Identity/Relay Counter/Account cards in place of the
  // plain ListTile column. Settings' left nav isn't part of it -- every
  // sidebar in the app, that one included, already takes its icons and
  // rounded rows from the Sidebar area.
  final bool accountCardLayout;

  // -------------------------------------------------------------------------
  // Feed -- see editor/areas/feed.dart. Each toggle gates a distinct feed
  // feature ported from the exitus1 fork; all default to false (off).
  // Several only have a visible effect when feedCardRedesign is also on
  // (they render into the new card's action bar, which the old card layout
  // doesn't have).
  // -------------------------------------------------------------------------
  final bool feedCardRedesign; // X-style card layout, comment count,
  // clamped body + "Show more", and the post-detail screen's centered width.
  final bool feedCardActions; // Relay/tip/quote-post action-bar icons +
  // nested quote-post rendering. Needs feedCardRedesign.
  // feedCardActions also covers bookmarking (per-post bookmark +
  // "Bookmarks" nav section) and hiding (per-post hide/unhide + "Hidden"
  // section): all three live on the same action bar and are the same kind
  // of thing -- something you do to a post.
  final bool feedSidePanel; // Search/sort/filter nav rail, replacing FeedBar
  // on the main feed tab.
  final bool feedInlineComposer; // Pinned "What's happening?" composer.
  // feedInlineComposer covers the composer's formatting toolbar, image/
  // file attach and drafts too -- each is useless without the composer, and
  // anyone who wants a composer wants it to work.
  final bool feedHideSidebarOnPost; // Drops the feed sidebar entirely while
  // reading a single post, for a more focused reading experience. Needs
  // feedSidePanel.
  // markdownGuideId is the style guide posts are read in on this device --
  // see model/markdown_style.dart. It travels with a theme because how text
  // is set is part of how the app looks, and because someone who has built a
  // theme has usually decided this too.
  final String markdownGuideId;

  // The Markdown area's picture settings. Null means "whatever the chosen
  // guide says", which is how every area here expresses inheriting: a theme
  // that has never touched these follows Article or Compact exactly, and one
  // that has overrides only the parts it named.
  //
  // Held here rather than as a guide of the user's own because a theme
  // already is the thing that travels with somebody's taste. Building and
  // naming whole guides is a larger feature; adjusting the pictures in the
  // one you picked is the part that was actually asked for.
  final double? markdownImageWidthPercent;
  final double? markdownImageRadius;
  final double? markdownImageBorderWidth;
  final Color? markdownImageBorderColor;
  // The palette slot the colour above was chosen from, so it follows the
  // palette when that is edited rather than staying at whatever value the
  // slot happened to hold.
  final int? markdownImageBorderColorIndex;
  final double? markdownImageGap;
  final MarkdownAlign? markdownImageAlign;

  /// markdownCustomGuide is the guide being edited, as JSON, or null when a
  /// built-in is in use unchanged.
  ///
  /// The working copy, not the library. Changing a built-in forks it into
  /// here immediately so nothing is lost, and it stays unnamed until it is
  /// saved -- which is what markdownSavedGuides is for.
  final Map<String, Object?>? markdownCustomGuide;

  /// markdownSavedGuides are the guides the reader has named and kept, by
  /// id.
  ///
  /// Beside the built-ins in the picker, and unlike them they can be deleted.
  /// Kept on the theme so they travel with it, like every other decision the
  /// theme editor makes.
  final Map<String, Object?> markdownSavedGuides;

  /// markdownGuide is the guide this theme actually renders with.
  ///
  /// The custom one when there is one, otherwise the named built-in,
  /// otherwise Default. The picture overrides are folded on last, and exist
  /// only to carry forward themes saved when they were the whole of this
  /// feature.
  MarkdownStyleGuide markdownGuide(MarkdownStyleGuide? named) {
    var saved = markdownSavedGuides[markdownGuideId];
    var base = markdownCustomGuide != null
        ? MarkdownStyleGuide.fromJson(markdownCustomGuide!)
        : saved is Map
            ? MarkdownStyleGuide.fromJson(Map<String, Object?>.from(saved))
            : (named ??
                const MarkdownStyleGuide(id: "default", name: "Default"));
    return base.copyWith(image: markdownImage(base.image));
  }

  /// markdownGuideChoices is every guide the picker offers: the built-ins
  /// first, then the reader's own.
  List<MarkdownStyleGuide> markdownGuideChoices(
          List<MarkdownStyleGuide> builtIns) =>
      [
        ...builtIns,
        for (var entry in markdownSavedGuides.entries)
          if (entry.value is Map)
            MarkdownStyleGuide.fromJson(
                Map<String, Object?>.from(entry.value as Map)),
      ];

  /// markdownImage is [guide]'s picture rules with this theme's overrides
  /// folded over them.
  ///
  /// Anything the theme has not touched comes from the guide, so picking
  /// Article and changing only the corners keeps Article's width and gap.
  ImageRule markdownImage(ImageRule guide) => guide.copyWith(
        widthPercent: markdownImageWidthPercent,
        cornerRadius: markdownImageRadius,
        borderWidth: markdownImageBorderWidth,
        borderInk: markdownImageBorderColor == null
            ? null
            : MarkdownInk.literal(markdownImageBorderColor!),
        gap: markdownImageGap,
        align: markdownImageAlign,
      );

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

  // -------------------------------------------------------------------------
  // Pages -- see editor/areas/pages.dart.
  //
  // A page states its own width and background, in the page, because that is
  // the only thing that reaches a reader (markdown_page.dart). These two are
  // the reader's half of that: the page knows its design, the reader knows
  // their screen, and neither can answer for the other.
  // -------------------------------------------------------------------------

  // pagesWidthCap is the widest any page may draw itself, whatever it asked
  // for; 0 (the default) means whatever it asked for. A ceiling rather than
  // a measurement -- it never widens a page that wanted to be narrow.
  final double pagesWidthCap;

  // pagesHonourBackground is whether a page may sit on a surface of its own
  // choosing. Off means every page uses this area's background, which is
  // what a reader who has themed Pages to their liking wants.
  final bool pagesHonourBackground;

  // pagesBackgroundColor is the colour a page sits on when it asks for one.
  // Null leaves that to the role the page named -- raised or quiet, resolved
  // from this theme -- which is what a reader who has not chosen gets.
  //
  // A reader's choice rather than the page's: the page says *that* it wants
  // to sit on something, in a word that means the same in a dark theme and
  // a light one, and this says what that comes out as here.
  final Color? pagesBackgroundColor;
  final int? pagesBackgroundColorIndex;

  // -------------------------------------------------------------------------
  // Mobile -- see editor/areas/mobile.dart.
  // -------------------------------------------------------------------------

  // mobileTapOpensSidebar makes re-tapping the destination you're already
  // on open that page's own sidebar, sliding in from the left -- the same
  // drawer, and the same gesture, the desktop nav bar already uses when
  // the window is too narrow for a sidebar column (see
  // CollapsedSidebarModel and Sidebar.switchScreen). It also takes the
  // three-dot page menu out of the mobile header: with the sidebar a
  // re-tap away, that button is a second route to the same place.
  final bool mobileTapOpensSidebar;

  // mobileNavHideLabels drops the destination names from the bottom bar,
  // leaving the icons alone -- which also lets more of them fit before it
  // has to start scrolling. The bar shortens to suit rather than leaving
  // the space the labels used to take.
  final bool mobileNavHideLabels;

  // mobileSidebarAvatarCloses turns the right sidebar's avatar -- the
  // profile / manage-group-chat panel's big one at the top -- into a button
  // that closes the panel, in place of the context menu it opens by
  // default. That menu's entries are the same ones already listed down the
  // panel below it, and on a phone the panel is the whole screen with no
  // close button in its corner (the desktop layout's one is hidden there),
  // so a tap that dismisses it is worth more than a second route to the
  // same commands.
  final bool mobileSidebarAvatarCloses;

  // mobileAvatarOpensProfile sends the header's self-avatar to the Account
  // page -- your own profile: avatar, nick and identity -- rather than to
  // the top of Settings. Only where that avatar already goes somewhere;
  // it's the last step of the header's back chain, so it still unwinds an
  // open chat or panel first (see OverviewScreen's leading widget).
  final bool mobileAvatarOpensProfile;

  // mobileHideBackButton drops the header's back arrow, leaving the
  // self-avatar in its place at all times. The arrow retraces exactly what
  // the navigation bar's re-tap gesture does (see mobileTapOpensSidebar),
  // so with that on it's a second control for the same job in the corner
  // the avatar wants.
  final bool mobileHideBackButton;

  // mobileHideSelfAvatar takes your own avatar out of the header corner
  // altogether. Independent of mobileHideBackButton: with both off the
  // corner alternates between the two as it always has, and with both on
  // it's empty and the title starts at the screen edge.
  //
  // The header also drops it on its own, toggle or not, wherever the title
  // already carries an avatar -- a conversation on a phone puts the other
  // party's there (see ChatsScreenTitle), and two avatars side by side in
  // one header is one too many.
  final bool mobileHideSelfAvatar;

  // mobileAvatarSecondTapCloses makes the header avatar undo its own last
  // tap: it closes the right sidebar if that's open, and otherwise leaves
  // the Account page it opened, returning to whichever screen you were on
  // when you tapped it. Without this the avatar only ever goes one way,
  // and getting back out is the navigation bar's job.
  final bool mobileAvatarSecondTapCloses;

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
    this.height,
    this.contentAlign,
    this.logoPath,
    this.logoSize,
    this.loginLogoSize,
    this.hideHeaderLogo = false,
    this.hideHeaderTitle = false,
    this.hideHeaderNewPost = false,
    this.hideHeaderCallIcon = false,
    this.hideHeaderNewSession = false,
    this.hideTooltips = false,
    this.hideHelpTooltips = false,
    this.hideFilePaths = false,
    this.messageAreaColor,
    this.messageAreaColorIndex,
    this.collapseComposerIcons = false,
    this.inputBackgroundColor,
    this.inputBackgroundColorIndex,
    this.inputBorderColor,
    this.inputBorderColorIndex,
    this.inputBorderWidth = 0,
    this.inputBorderRadius = 0,
    this.buttonStyles = const {},
    this.headerPosition,
    this.navRoutes,
    this.showLogo = false,
    this.showDcrPrice = false,
    this.showBtcPrice = false,
    this.priceIconSize,
    this.dcrPricePadding = 0,
    this.dcrPricePaddingSides,
    this.btcPricePadding = 0,
    this.btcPricePaddingSides,
    this.logoAlign,
    this.subMenuStyle,
    this.sidebarCornerRadius = 12,
    this.sidebarShowIcons = false,
    this.enableMessageActions = false,
    this.showChatListLastMessage = false,
    this.chatListDesignEnabled = false,
    this.chatListCornerRadius,
    this.chatListAccentColor,
    this.chatListBackgroundColor,
    this.chatListBackgroundColorIndex,
    this.chatListSelectedColor,
    this.chatListSelectedColorIndex,
    this.chatListAccentColorIndex,
    this.chatListGlowIntensity,
    this.chatListTopHighlight = true,
    this.chatBackdropWash = false,
    this.enableChatSearch = false,
    this.chatSidebarFooter = true,
    this.formattingToolbar = false,
    this.composerPolish = false,
    this.bubbleCorners = false,
    this.bubbleRadiusSent = 10,
    this.bubbleRadiusSentSides,
    this.bubbleRadiusReceived = 10,
    this.bubbleRadiusReceivedSides,
    this.bubbleCornerStyle = BubbleCornerStyle.rounded,
    this.messageLayoutMode,
    this.messageSpacing,
    this.avatarTheme = AvatarTheme.standard,
    this.expandMessageWidth = false,
    this.expandMessagePadding,
    this.expandMessagePaddingSides,
    this.autoUnmuteOnJoin = false,
    this.rtcSessionCornerRadius,
    this.rtcActiveSessionColor,
    this.rtcActiveSessionColorIndex,
    this.rtcLiveColor,
    this.rtcLiveColorIndex,
    this.rtcMutedColor,
    this.rtcMutedColorIndex,
    this.rtcWarningColor,
    this.rtcWarningColorIndex,
    this.rtcStageAvatarRadius,
    this.rtcStageCollapsed = false,
    this.payStatsCardStyle = false,
    this.accountCardLayout = false,
    this.feedCardRedesign = false,
    this.feedCardActions = false,
    this.feedSidePanel = false,
    this.feedInlineComposer = false,
    this.feedHideSidebarOnPost = false,
    this.markdownCustomGuide,
    this.markdownSavedGuides = const {},
    this.markdownImageWidthPercent,
    this.markdownImageRadius,
    this.markdownImageBorderWidth,
    this.markdownImageBorderColor,
    this.markdownImageBorderColorIndex,
    this.markdownImageGap,
    this.markdownImageAlign,
    this.markdownGuideId = "default",
    this.feedImageLayout = FeedImageLayout.standard,
    this.feedImageCropHeight = 300,
    this.feedTextOrder = FeedTextOrder.standard,
    this.feedLinksMode = FeedLinksMode.standard,
    this.feedTextLimit = 0,
    this.feedStripMarkdown = false,
    this.pagesWidthCap = 0,
    this.pagesHonourBackground = true,
    this.pagesBackgroundColor,
    this.pagesBackgroundColorIndex,
    this.mobileTapOpensSidebar = false,
    this.mobileNavHideLabels = false,
    this.mobileSidebarAvatarCloses = false,
    this.mobileAvatarOpensProfile = false,
    this.mobileHideBackButton = false,
    this.mobileHideSelfAvatar = false,
    this.mobileAvatarSecondTapCloses = false,
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
    double? height,
    bool clearHeight = false,
    ContentAlign? contentAlign,
    String? logoPath,
    bool clearLogoPath = false,
    double? logoSize,
    double? loginLogoSize,
    bool? hideHeaderLogo,
    bool? hideHeaderTitle,
    bool? hideHeaderNewPost,
    bool? hideHeaderCallIcon,
    bool? hideHeaderNewSession,
    bool? hideTooltips,
    bool? hideHelpTooltips,
    bool? hideFilePaths,
    Color? messageAreaColor,
    int? messageAreaColorIndex,
    bool clearMessageAreaColor = false,
    bool clearMessageAreaColorIndex = false,
    bool? collapseComposerIcons,
    Color? inputBackgroundColor,
    int? inputBackgroundColorIndex,
    bool clearInputBackgroundColor = false,
    bool clearInputBackgroundColorIndex = false,
    Color? inputBorderColor,
    int? inputBorderColorIndex,
    bool clearInputBorderColor = false,
    bool clearInputBorderColorIndex = false,
    double? inputBorderWidth,
    double? inputBorderRadius,
    Map<ButtonRole, ButtonAreaStyle>? buttonStyles,
    HeaderPosition? headerPosition,
    List<String>? navRoutes,
    bool clearNavRoutes = false,
    bool? showLogo,
    bool? showDcrPrice,
    bool? showBtcPrice,
    double? priceIconSize,
    double? dcrPricePadding,
    SideValues? dcrPricePaddingSides,
    bool clearDcrPricePaddingSides = false,
    double? btcPricePadding,
    SideValues? btcPricePaddingSides,
    bool clearBtcPricePaddingSides = false,
    bool clearPriceIconSize = false,
    ContentAlign? logoAlign,
    SubMenuStyle? subMenuStyle,
    double? sidebarCornerRadius,
    bool? sidebarShowIcons,
    bool? enableMessageActions,
    bool? showChatListLastMessage,
    bool? chatListDesignEnabled,
    double? chatListCornerRadius,
    bool clearChatListCornerRadius = false,
    Color? chatListAccentColor,
    Color? chatListBackgroundColor,
    bool clearChatListBackgroundColor = false,
    int? chatListBackgroundColorIndex,
    bool clearChatListBackgroundColorIndex = false,
    Color? chatListSelectedColor,
    bool clearChatListSelectedColor = false,
    int? chatListSelectedColorIndex,
    bool clearChatListSelectedColorIndex = false,
    int? chatListAccentColorIndex,
    bool clearChatListAccentColorIndex = false,
    bool clearChatListAccentColor = false,
    double? chatListGlowIntensity,
    bool clearChatListGlowIntensity = false,
    bool? chatListTopHighlight,
    bool? chatBackdropWash,
    bool? enableChatSearch,
    bool? chatSidebarFooter,
    bool? formattingToolbar,
    bool? composerPolish,
    bool? bubbleCorners,
    double? bubbleRadiusSent,
    SideValues? bubbleRadiusSentSides,
    bool clearBubbleRadiusSentSides = false,
    double? bubbleRadiusReceived,
    SideValues? bubbleRadiusReceivedSides,
    bool clearBubbleRadiusReceivedSides = false,
    BubbleCornerStyle? bubbleCornerStyle,
    MessageLayoutMode? messageLayoutMode,
    double? messageSpacing,
    bool clearMessageSpacing = false,
    AvatarTheme? avatarTheme,
    bool clearMessageLayoutMode = false,
    bool? expandMessageWidth,
    double? expandMessagePadding,
    SideValues? expandMessagePaddingSides,
    bool clearExpandMessagePaddingSides = false,
    bool clearExpandMessagePadding = false,
    bool? autoUnmuteOnJoin,
    double? rtcSessionCornerRadius,
    bool clearRtcSessionCornerRadius = false,
    Color? rtcActiveSessionColor,
    bool clearRtcActiveSessionColor = false,
    int? rtcActiveSessionColorIndex,
    bool clearRtcActiveSessionColorIndex = false,
    Color? rtcLiveColor,
    bool clearRtcLiveColor = false,
    int? rtcLiveColorIndex,
    bool clearRtcLiveColorIndex = false,
    Color? rtcMutedColor,
    bool clearRtcMutedColor = false,
    int? rtcMutedColorIndex,
    bool clearRtcMutedColorIndex = false,
    Color? rtcWarningColor,
    bool clearRtcWarningColor = false,
    int? rtcWarningColorIndex,
    bool clearRtcWarningColorIndex = false,
    double? rtcStageAvatarRadius,
    bool clearRtcStageAvatarRadius = false,
    bool? rtcStageCollapsed,
    bool? payStatsCardStyle,
    bool? accountCardLayout,
    bool? feedCardRedesign,
    bool? feedCardActions,
    bool? feedSidePanel,
    bool? feedInlineComposer,
    bool? feedHideSidebarOnPost,
    Map<String, Object?>? markdownCustomGuide,
    bool clearMarkdownCustomGuide = false,
    Map<String, Object?>? markdownSavedGuides,
    double? markdownImageWidthPercent,
    double? markdownImageRadius,
    double? markdownImageBorderWidth,
    Color? markdownImageBorderColor,
    int? markdownImageBorderColorIndex,
    bool clearMarkdownImageBorderColor = false,
    double? markdownImageGap,
    MarkdownAlign? markdownImageAlign,
    bool clearMarkdownImages = false,
    String? markdownGuideId,
    FeedImageLayout? feedImageLayout,
    double? feedImageCropHeight,
    FeedTextOrder? feedTextOrder,
    FeedLinksMode? feedLinksMode,
    double? feedTextLimit,
    bool? feedStripMarkdown,
    double? pagesWidthCap,
    bool? pagesHonourBackground,
    Color? pagesBackgroundColor,
    bool clearPagesBackgroundColor = false,
    int? pagesBackgroundColorIndex,
    bool clearPagesBackgroundColorIndex = false,
    bool? mobileTapOpensSidebar,
    bool? mobileNavHideLabels,
    bool? mobileSidebarAvatarCloses,
    bool? mobileAvatarOpensProfile,
    bool? mobileHideBackButton,
    bool? mobileHideSelfAvatar,
    bool? mobileAvatarSecondTapCloses,
  }) =>
      AreaStyle(
        mode: mode ?? this.mode,
        solidColor: solidColor ?? this.solidColor,
        solidColorIndex: clearSolidColorIndex
            ? null
            : (solidColorIndex ?? this.solidColorIndex),
        gradientColors: gradientColors ?? this.gradientColors,
        gradientColorIndexes: gradientColorIndexes ?? this.gradientColorIndexes,
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
        height: clearHeight ? null : (height ?? this.height),
        contentAlign: contentAlign ?? this.contentAlign,
        logoPath: clearLogoPath ? null : (logoPath ?? this.logoPath),
        logoSize: logoSize ?? this.logoSize,
        loginLogoSize: loginLogoSize ?? this.loginLogoSize,
        hideHeaderLogo: hideHeaderLogo ?? this.hideHeaderLogo,
        hideHeaderTitle: hideHeaderTitle ?? this.hideHeaderTitle,
        hideHeaderNewPost: hideHeaderNewPost ?? this.hideHeaderNewPost,
        hideHeaderCallIcon: hideHeaderCallIcon ?? this.hideHeaderCallIcon,
        hideHeaderNewSession: hideHeaderNewSession ?? this.hideHeaderNewSession,
        hideTooltips: hideTooltips ?? this.hideTooltips,
        hideHelpTooltips: hideHelpTooltips ?? this.hideHelpTooltips,
        hideFilePaths: hideFilePaths ?? this.hideFilePaths,
        messageAreaColor: clearMessageAreaColor
            ? null
            : (messageAreaColor ?? this.messageAreaColor),
        messageAreaColorIndex: clearMessageAreaColorIndex
            ? null
            : (messageAreaColorIndex ?? this.messageAreaColorIndex),
        collapseComposerIcons:
            collapseComposerIcons ?? this.collapseComposerIcons,
        inputBackgroundColor: clearInputBackgroundColor
            ? null
            : (inputBackgroundColor ?? this.inputBackgroundColor),
        inputBackgroundColorIndex: clearInputBackgroundColorIndex
            ? null
            : (inputBackgroundColorIndex ?? this.inputBackgroundColorIndex),
        inputBorderColor: clearInputBorderColor
            ? null
            : (inputBorderColor ?? this.inputBorderColor),
        inputBorderColorIndex: clearInputBorderColorIndex
            ? null
            : (inputBorderColorIndex ?? this.inputBorderColorIndex),
        inputBorderWidth: inputBorderWidth ?? this.inputBorderWidth,
        inputBorderRadius: inputBorderRadius ?? this.inputBorderRadius,
        buttonStyles: buttonStyles ?? this.buttonStyles,
        headerPosition: headerPosition ?? this.headerPosition,
        navRoutes: clearNavRoutes ? null : (navRoutes ?? this.navRoutes),
        showLogo: showLogo ?? this.showLogo,
        showDcrPrice: showDcrPrice ?? this.showDcrPrice,
        showBtcPrice: showBtcPrice ?? this.showBtcPrice,
        dcrPricePadding: dcrPricePadding ?? this.dcrPricePadding,
        dcrPricePaddingSides: clearDcrPricePaddingSides
            ? null
            : (dcrPricePaddingSides ?? this.dcrPricePaddingSides),
        btcPricePadding: btcPricePadding ?? this.btcPricePadding,
        btcPricePaddingSides: clearBtcPricePaddingSides
            ? null
            : (btcPricePaddingSides ?? this.btcPricePaddingSides),
        priceIconSize:
            clearPriceIconSize ? null : (priceIconSize ?? this.priceIconSize),
        logoAlign: logoAlign ?? this.logoAlign,
        subMenuStyle: subMenuStyle ?? this.subMenuStyle,
        sidebarCornerRadius: sidebarCornerRadius ?? this.sidebarCornerRadius,
        sidebarShowIcons: sidebarShowIcons ?? this.sidebarShowIcons,
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
        chatListBackgroundColor: clearChatListBackgroundColor
            ? null
            : (chatListBackgroundColor ?? this.chatListBackgroundColor),
        chatListSelectedColor: clearChatListSelectedColor
            ? null
            : (chatListSelectedColor ?? this.chatListSelectedColor),
        chatListSelectedColorIndex: clearChatListSelectedColorIndex
            ? null
            : (chatListSelectedColorIndex ?? this.chatListSelectedColorIndex),
        chatListBackgroundColorIndex: clearChatListBackgroundColorIndex
            ? null
            : (chatListBackgroundColorIndex ??
                this.chatListBackgroundColorIndex),
        chatListAccentColor: clearChatListAccentColor
            ? null
            : (chatListAccentColor ?? this.chatListAccentColor),
        chatListGlowIntensity: clearChatListGlowIntensity
            ? null
            : (chatListGlowIntensity ?? this.chatListGlowIntensity),
        chatListTopHighlight: chatListTopHighlight ?? this.chatListTopHighlight,
        chatBackdropWash: chatBackdropWash ?? this.chatBackdropWash,
        enableChatSearch: enableChatSearch ?? this.enableChatSearch,
        chatSidebarFooter: chatSidebarFooter ?? this.chatSidebarFooter,
        formattingToolbar: formattingToolbar ?? this.formattingToolbar,
        composerPolish: composerPolish ?? this.composerPolish,
        bubbleCorners: bubbleCorners ?? this.bubbleCorners,
        bubbleRadiusSent: bubbleRadiusSent ?? this.bubbleRadiusSent,
        bubbleRadiusSentSides: clearBubbleRadiusSentSides
            ? null
            : (bubbleRadiusSentSides ?? this.bubbleRadiusSentSides),
        bubbleRadiusReceived: bubbleRadiusReceived ?? this.bubbleRadiusReceived,
        bubbleRadiusReceivedSides: clearBubbleRadiusReceivedSides
            ? null
            : (bubbleRadiusReceivedSides ?? this.bubbleRadiusReceivedSides),
        bubbleCornerStyle: bubbleCornerStyle ?? this.bubbleCornerStyle,
        avatarTheme: avatarTheme ?? this.avatarTheme,
        messageLayoutMode: clearMessageLayoutMode
            ? null
            : (messageLayoutMode ?? this.messageLayoutMode),
        messageSpacing: clearMessageSpacing
            ? null
            : (messageSpacing ?? this.messageSpacing),
        expandMessageWidth: expandMessageWidth ?? this.expandMessageWidth,
        expandMessagePaddingSides: clearExpandMessagePaddingSides
            ? null
            : (expandMessagePaddingSides ?? this.expandMessagePaddingSides),
        expandMessagePadding: clearExpandMessagePadding
            ? null
            : (expandMessagePadding ?? this.expandMessagePadding),
        autoUnmuteOnJoin: autoUnmuteOnJoin ?? this.autoUnmuteOnJoin,
        rtcSessionCornerRadius: clearRtcSessionCornerRadius
            ? null
            : (rtcSessionCornerRadius ?? this.rtcSessionCornerRadius),
        rtcActiveSessionColor: clearRtcActiveSessionColor
            ? null
            : (rtcActiveSessionColor ?? this.rtcActiveSessionColor),
        rtcActiveSessionColorIndex: clearRtcActiveSessionColorIndex
            ? null
            : (rtcActiveSessionColorIndex ?? this.rtcActiveSessionColorIndex),
        rtcLiveColor:
            clearRtcLiveColor ? null : (rtcLiveColor ?? this.rtcLiveColor),
        rtcLiveColorIndex: clearRtcLiveColorIndex
            ? null
            : (rtcLiveColorIndex ?? this.rtcLiveColorIndex),
        rtcMutedColor:
            clearRtcMutedColor ? null : (rtcMutedColor ?? this.rtcMutedColor),
        rtcMutedColorIndex: clearRtcMutedColorIndex
            ? null
            : (rtcMutedColorIndex ?? this.rtcMutedColorIndex),
        rtcWarningColor: clearRtcWarningColor
            ? null
            : (rtcWarningColor ?? this.rtcWarningColor),
        rtcWarningColorIndex: clearRtcWarningColorIndex
            ? null
            : (rtcWarningColorIndex ?? this.rtcWarningColorIndex),
        rtcStageAvatarRadius: clearRtcStageAvatarRadius
            ? null
            : (rtcStageAvatarRadius ?? this.rtcStageAvatarRadius),
        rtcStageCollapsed: rtcStageCollapsed ?? this.rtcStageCollapsed,
        payStatsCardStyle: payStatsCardStyle ?? this.payStatsCardStyle,
        accountCardLayout: accountCardLayout ?? this.accountCardLayout,
        feedCardRedesign: feedCardRedesign ?? this.feedCardRedesign,
        feedCardActions: feedCardActions ?? this.feedCardActions,
        feedSidePanel: feedSidePanel ?? this.feedSidePanel,
        feedInlineComposer: feedInlineComposer ?? this.feedInlineComposer,
        feedHideSidebarOnPost:
            feedHideSidebarOnPost ?? this.feedHideSidebarOnPost,
        markdownCustomGuide: clearMarkdownCustomGuide
            ? null
            : (markdownCustomGuide ?? this.markdownCustomGuide),
        markdownSavedGuides: markdownSavedGuides ?? this.markdownSavedGuides,
        markdownImageWidthPercent: clearMarkdownImages
            ? null
            : (markdownImageWidthPercent ?? this.markdownImageWidthPercent),
        markdownImageRadius: clearMarkdownImages
            ? null
            : (markdownImageRadius ?? this.markdownImageRadius),
        markdownImageBorderWidth: clearMarkdownImages
            ? null
            : (markdownImageBorderWidth ?? this.markdownImageBorderWidth),
        markdownImageBorderColor:
            clearMarkdownImages || clearMarkdownImageBorderColor
                ? null
                : (markdownImageBorderColor ?? this.markdownImageBorderColor),
        markdownImageBorderColorIndex:
            clearMarkdownImages || clearMarkdownImageBorderColor
                ? null
                : (markdownImageBorderColorIndex ??
                    this.markdownImageBorderColorIndex),
        markdownImageGap: clearMarkdownImages
            ? null
            : (markdownImageGap ?? this.markdownImageGap),
        markdownImageAlign: clearMarkdownImages
            ? null
            : (markdownImageAlign ?? this.markdownImageAlign),
        markdownGuideId: markdownGuideId ?? this.markdownGuideId,
        feedImageLayout: feedImageLayout ?? this.feedImageLayout,
        feedImageCropHeight: feedImageCropHeight ?? this.feedImageCropHeight,
        feedTextOrder: feedTextOrder ?? this.feedTextOrder,
        feedLinksMode: feedLinksMode ?? this.feedLinksMode,
        feedTextLimit: feedTextLimit ?? this.feedTextLimit,
        feedStripMarkdown: feedStripMarkdown ?? this.feedStripMarkdown,
        pagesWidthCap: pagesWidthCap ?? this.pagesWidthCap,
        pagesHonourBackground:
            pagesHonourBackground ?? this.pagesHonourBackground,
        pagesBackgroundColor: clearPagesBackgroundColor
            ? null
            : (pagesBackgroundColor ?? this.pagesBackgroundColor),
        pagesBackgroundColorIndex: clearPagesBackgroundColorIndex
            ? null
            : (pagesBackgroundColorIndex ?? this.pagesBackgroundColorIndex),
        mobileTapOpensSidebar:
            mobileTapOpensSidebar ?? this.mobileTapOpensSidebar,
        mobileNavHideLabels: mobileNavHideLabels ?? this.mobileNavHideLabels,
        mobileSidebarAvatarCloses:
            mobileSidebarAvatarCloses ?? this.mobileSidebarAvatarCloses,
        mobileAvatarOpensProfile:
            mobileAvatarOpensProfile ?? this.mobileAvatarOpensProfile,
        mobileHideBackButton: mobileHideBackButton ?? this.mobileHideBackButton,
        mobileHideSelfAvatar: mobileHideSelfAvatar ?? this.mobileHideSelfAvatar,
        mobileAvatarSecondTapCloses:
            mobileAvatarSecondTapCloses ?? this.mobileAvatarSecondTapCloses,
      );

  // toJson omits every field still at its default, so a preset's saved
  // "areas" map only records what the user actually changed -- and an area
  // the user never touched writes as an empty object. Every omission below
  // has a matching default in fromJson.
  Map<String, dynamic> toJson() => {
        if (mode != AreaBackgroundMode.token) "mode": mode.name,
        if (solidColor != null) "solidColor": colorToHex(solidColor!),
        if (solidColorIndex != null) "solidColorIndex": solidColorIndex,
        if (gradientColors.isNotEmpty)
          "gradientColors": gradientColors.map(colorToHex).toList(),
        if (gradientColorIndexes.isNotEmpty)
          "gradientColorIndexes": gradientColorIndexes,
        if (gradientStops != null) "gradientStops": gradientStops,
        if (gradientBegin != Alignment.topLeft)
          "gradientBegin": _alignToJson(gradientBegin),
        if (gradientEnd != Alignment.bottomRight)
          "gradientEnd": _alignToJson(gradientEnd),
        if (imagePath != null) "imagePath": imagePath,
        if (imageFit != BoxFit.cover) "imageFit": imageFit.name,
        if (imagePreset != AreaImagePreset.standard)
          "imagePreset": imagePreset.name,
        if (borderMode != AreaBackgroundMode.token)
          "borderMode": borderMode.name,
        if (borderColor != null) "borderColor": colorToHex(borderColor!),
        if (borderColorIndex != null) "borderColorIndex": borderColorIndex,
        if (borderGradientColors.isNotEmpty)
          "borderGradientColors": borderGradientColors.map(colorToHex).toList(),
        if (borderGradientColorIndexes.isNotEmpty)
          "borderGradientColorIndexes": borderGradientColorIndexes,
        if (borderGradientStops != null)
          "borderGradientStops": borderGradientStops,
        if (borderGradientBegin != Alignment.topLeft)
          "borderGradientBegin": _alignToJson(borderGradientBegin),
        if (borderGradientEnd != Alignment.bottomRight)
          "borderGradientEnd": _alignToJson(borderGradientEnd),
        if (borderImagePath != null) "borderImagePath": borderImagePath,
        if (borderImageFit != BoxFit.cover)
          "borderImageFit": borderImageFit.name,
        if (borderWidth != 0) "borderWidth": borderWidth,
        if (borderRadius != 0) "borderRadius": borderRadius,
        if (padding != 0) "padding": padding,
        if (margin != 0) "margin": margin,
        if (borderWidthSides != null)
          "borderWidthSides": borderWidthSides!.toJson(),
        if (borderRadiusSides != null)
          "borderRadiusSides": borderRadiusSides!.toJson(),
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (marginSides != null) "marginSides": marginSides!.toJson(),
        if (height != null) "height": height,
        if (contentAlign != null) "contentAlign": contentAlign!.name,
        if (logoPath != null) "logoPath": logoPath,
        if (logoSize != null) "logoSize": logoSize,
        if (loginLogoSize != null) "loginLogoSize": loginLogoSize,
        if (hideHeaderLogo) "hideHeaderLogo": hideHeaderLogo,
        if (hideHeaderTitle) "hideHeaderTitle": hideHeaderTitle,
        if (hideHeaderNewPost) "hideHeaderNewPost": hideHeaderNewPost,
        if (hideHeaderCallIcon) "hideHeaderCallIcon": hideHeaderCallIcon,
        if (hideHeaderNewSession) "hideHeaderNewSession": hideHeaderNewSession,
        if (hideTooltips) "hideTooltips": hideTooltips,
        if (hideHelpTooltips) "hideHelpTooltips": hideHelpTooltips,
        if (hideFilePaths) "hideFilePaths": hideFilePaths,
        if (messageAreaColor != null)
          "messageAreaColor": colorToHex(messageAreaColor!),
        if (messageAreaColorIndex != null)
          "messageAreaColorIndex": messageAreaColorIndex,
        if (collapseComposerIcons)
          "collapseComposerIcons": collapseComposerIcons,
        if (inputBackgroundColor != null)
          "inputBackgroundColor": colorToHex(inputBackgroundColor!),
        if (inputBackgroundColorIndex != null)
          "inputBackgroundColorIndex": inputBackgroundColorIndex,
        if (inputBorderColor != null)
          "inputBorderColor": colorToHex(inputBorderColor!),
        if (inputBorderColorIndex != null)
          "inputBorderColorIndex": inputBorderColorIndex,
        if (inputBorderWidth != 0) "inputBorderWidth": inputBorderWidth,
        if (inputBorderRadius != 0) "inputBorderRadius": inputBorderRadius,
        // Only the roles the user has actually touched are written, keyed
        // by role name so reordering ButtonRole can't renumber them.
        if (buttonStyles.values.any((s) => !s.isEmpty))
          "buttonStyles": {
            for (var e in buttonStyles.entries)
              if (!e.value.isEmpty) e.key.name: e.value.toJson(),
          },
        if (headerPosition != null) "headerPosition": headerPosition!.name,
        // An empty list is a real setting -- "no navigation items at all"
        // -- and has to survive a save, so this writes whenever the list
        // isn't null rather than whenever it isn't empty.
        if (navRoutes != null) "navRoutes": navRoutes,
        if (showLogo) "showLogo": showLogo,
        if (showDcrPrice) "showDcrPrice": showDcrPrice,
        if (showBtcPrice) "showBtcPrice": showBtcPrice,
        if (priceIconSize != null) "priceIconSize": priceIconSize,
        if (dcrPricePadding != 0) "dcrPricePadding": dcrPricePadding,
        if (dcrPricePaddingSides != null)
          "dcrPricePaddingSides": dcrPricePaddingSides!.toJson(),
        if (btcPricePadding != 0) "btcPricePadding": btcPricePadding,
        if (btcPricePaddingSides != null)
          "btcPricePaddingSides": btcPricePaddingSides!.toJson(),
        if (logoAlign != null) "logoAlign": logoAlign!.name,
        if (subMenuStyle != null) "subMenuStyle": subMenuStyle!.name,
        if (sidebarCornerRadius != 12)
          "sidebarCornerRadius": sidebarCornerRadius,
        if (sidebarShowIcons) "sidebarShowIcons": sidebarShowIcons,
        if (enableMessageActions) "enableMessageActions": enableMessageActions,
        if (showChatListLastMessage)
          "showChatListLastMessage": showChatListLastMessage,
        if (chatListDesignEnabled)
          "chatListDesignEnabled": chatListDesignEnabled,
        if (chatListCornerRadius != null)
          "chatListCornerRadius": chatListCornerRadius,
        if (chatListAccentColor != null)
          "chatListAccentColor": colorToHex(chatListAccentColor!),
        if (chatListBackgroundColor != null)
          "chatListBackgroundColor": colorToHex(chatListBackgroundColor!),
        if (chatListBackgroundColorIndex != null)
          "chatListBackgroundColorIndex": chatListBackgroundColorIndex,
        if (chatListSelectedColor != null)
          "chatListSelectedColor": colorToHex(chatListSelectedColor!),
        if (chatListSelectedColorIndex != null)
          "chatListSelectedColorIndex": chatListSelectedColorIndex,
        if (chatListAccentColorIndex != null)
          "chatListAccentColorIndex": chatListAccentColorIndex,
        if (chatListGlowIntensity != null)
          "chatListGlowIntensity": chatListGlowIntensity,
        if (!chatListTopHighlight) "chatListTopHighlight": chatListTopHighlight,
        if (chatBackdropWash) "chatBackdropWash": chatBackdropWash,
        if (enableChatSearch) "enableChatSearch": enableChatSearch,
        if (!chatSidebarFooter) "chatSidebarFooter": chatSidebarFooter,
        if (formattingToolbar) "formattingToolbar": formattingToolbar,
        if (composerPolish) "composerPolish": composerPolish,
        if (bubbleCorners) "bubbleCorners": bubbleCorners,
        if (bubbleRadiusSent != 10) "bubbleRadiusSent": bubbleRadiusSent,
        if (bubbleRadiusSentSides != null)
          "bubbleRadiusSentSides": bubbleRadiusSentSides!.toJson(),
        if (bubbleRadiusReceived != 10)
          "bubbleRadiusReceived": bubbleRadiusReceived,
        if (bubbleRadiusReceivedSides != null)
          "bubbleRadiusReceivedSides": bubbleRadiusReceivedSides!.toJson(),
        if (bubbleCornerStyle != BubbleCornerStyle.rounded)
          "bubbleCornerStyle": bubbleCornerStyle.name,
        if (messageLayoutMode != null)
          "messageLayoutMode": messageLayoutMode!.name,
        if (messageSpacing != null) "messageSpacing": messageSpacing,
        if (avatarTheme != AvatarTheme.standard)
          "avatarTheme": avatarTheme.name,
        if (expandMessageWidth) "expandMessageWidth": expandMessageWidth,
        if (expandMessagePadding != null)
          "expandMessagePadding": expandMessagePadding,
        if (expandMessagePaddingSides != null)
          "expandMessagePaddingSides": expandMessagePaddingSides!.toJson(),
        if (autoUnmuteOnJoin) "autoUnmuteOnJoin": autoUnmuteOnJoin,
        if (rtcSessionCornerRadius != null)
          "rtcSessionCornerRadius": rtcSessionCornerRadius,
        if (rtcActiveSessionColor != null)
          "rtcActiveSessionColor": colorToHex(rtcActiveSessionColor!),
        if (rtcActiveSessionColorIndex != null)
          "rtcActiveSessionColorIndex": rtcActiveSessionColorIndex,
        if (rtcLiveColor != null) "rtcLiveColor": colorToHex(rtcLiveColor!),
        if (rtcLiveColorIndex != null) "rtcLiveColorIndex": rtcLiveColorIndex,
        if (rtcMutedColor != null) "rtcMutedColor": colorToHex(rtcMutedColor!),
        if (rtcMutedColorIndex != null)
          "rtcMutedColorIndex": rtcMutedColorIndex,
        if (rtcWarningColor != null)
          "rtcWarningColor": colorToHex(rtcWarningColor!),
        if (rtcWarningColorIndex != null)
          "rtcWarningColorIndex": rtcWarningColorIndex,
        if (rtcStageAvatarRadius != null)
          "rtcStageAvatarRadius": rtcStageAvatarRadius,
        if (rtcStageCollapsed) "rtcStageCollapsed": rtcStageCollapsed,
        if (payStatsCardStyle) "payStatsCardStyle": payStatsCardStyle,
        if (accountCardLayout) "accountCardLayout": accountCardLayout,
        if (feedCardRedesign) "feedCardRedesign": feedCardRedesign,
        if (feedCardActions) "feedCardActions": feedCardActions,
        if (feedSidePanel) "feedSidePanel": feedSidePanel,
        if (feedInlineComposer) "feedInlineComposer": feedInlineComposer,
        if (markdownCustomGuide != null)
          "markdownCustomGuide": markdownCustomGuide,
        if (markdownSavedGuides.isNotEmpty)
          "markdownSavedGuides": markdownSavedGuides,
        if (markdownImageWidthPercent != null)
          "markdownImageWidthPercent": markdownImageWidthPercent,
        if (markdownImageRadius != null)
          "markdownImageRadius": markdownImageRadius,
        if (markdownImageBorderWidth != null)
          "markdownImageBorderWidth": markdownImageBorderWidth,
        if (markdownImageBorderColor != null)
          "markdownImageBorderColor": colorToHex(markdownImageBorderColor!),
        if (markdownImageBorderColorIndex != null)
          "markdownImageBorderColorIndex": markdownImageBorderColorIndex,
        if (markdownImageGap != null) "markdownImageGap": markdownImageGap,
        if (markdownImageAlign != null)
          "markdownImageAlign": markdownImageAlign!.name,
        if (markdownGuideId != "default") "markdownGuideId": markdownGuideId,
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
        if (pagesWidthCap != 0) "pagesWidthCap": pagesWidthCap,
        if (pagesBackgroundColor != null)
          "pagesBackgroundColor": colorToHex(pagesBackgroundColor!),
        if (pagesBackgroundColorIndex != null)
          "pagesBackgroundColorIndex": pagesBackgroundColorIndex,
        if (!pagesHonourBackground)
          "pagesHonourBackground": pagesHonourBackground,
        if (mobileTapOpensSidebar)
          "mobileTapOpensSidebar": mobileTapOpensSidebar,
        if (mobileNavHideLabels) "mobileNavHideLabels": mobileNavHideLabels,
        if (mobileSidebarAvatarCloses)
          "mobileSidebarAvatarCloses": mobileSidebarAvatarCloses,
        if (mobileAvatarOpensProfile)
          "mobileAvatarOpensProfile": mobileAvatarOpensProfile,
        if (mobileHideBackButton) "mobileHideBackButton": mobileHideBackButton,
        if (mobileHideSelfAvatar) "mobileHideSelfAvatar": mobileHideSelfAvatar,
        if (mobileAvatarSecondTapCloses)
          "mobileAvatarSecondTapCloses": mobileAvatarSecondTapCloses,
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
      height: number("height"),
      contentAlign: _enumOrNull(ContentAlign.values, j["contentAlign"]),
      logoPath: j["logoPath"],
      logoSize: number("logoSize"),
      loginLogoSize: number("loginLogoSize"),
      hideHeaderLogo: flag("hideHeaderLogo"),
      hideHeaderTitle: flag("hideHeaderTitle"),
      hideHeaderNewPost: flag("hideHeaderNewPost"),
      hideHeaderCallIcon: flag("hideHeaderCallIcon"),
      hideHeaderNewSession: flag("hideHeaderNewSession"),
      hideTooltips: flag("hideTooltips"),
      hideHelpTooltips: flag("hideHelpTooltips"),
      hideFilePaths: flag("hideFilePaths"),
      messageAreaColor: color("messageAreaColor"),
      messageAreaColorIndex: (j["messageAreaColorIndex"] as num?)?.toInt(),
      collapseComposerIcons: flag("collapseComposerIcons"),
      inputBackgroundColor: color("inputBackgroundColor"),
      inputBackgroundColorIndex:
          (j["inputBackgroundColorIndex"] as num?)?.toInt(),
      inputBorderColor: color("inputBorderColor"),
      inputBorderColorIndex: (j["inputBorderColorIndex"] as num?)?.toInt(),
      inputBorderWidth: number("inputBorderWidth") ?? 0,
      inputBorderRadius: number("inputBorderRadius") ?? 0,
      // Any role name this build doesn't know (written by a newer one) is
      // skipped rather than throwing, same as the areas map itself.
      buttonStyles: {
        for (var e
            in (j["buttonStyles"] as Map<String, dynamic>? ?? {}).entries)
          if (ButtonRole.values.where((r) => r.name == e.key).firstOrNull
              case var role?)
            role: ButtonAreaStyle.fromJson(e.value as Map<String, dynamic>),
      },
      headerPosition: _enumOrNull(HeaderPosition.values, j["headerPosition"]),
      navRoutes:
          (j["navRoutes"] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      showLogo: flag("showLogo"),
      showDcrPrice: flag("showDcrPrice"),
      showBtcPrice: flag("showBtcPrice"),
      priceIconSize: number("priceIconSize"),
      // The padding was one setting for both coins before it was split in
      // two; a preset saved then seeds both rows with it.
      dcrPricePadding: number("dcrPricePadding") ?? number("pricePadding") ?? 0,
      dcrPricePaddingSides: SideValues.fromJson(
          j["dcrPricePaddingSides"] ?? j["pricePaddingSides"]),
      btcPricePadding: number("btcPricePadding") ?? number("pricePadding") ?? 0,
      btcPricePaddingSides: SideValues.fromJson(
          j["btcPricePaddingSides"] ?? j["pricePaddingSides"]),
      logoAlign: _enumOrNull(ContentAlign.values, j["logoAlign"]),
      subMenuStyle: _enumOrNull(SubMenuStyle.values, j["subMenuStyle"]),
      sidebarCornerRadius: number("sidebarCornerRadius") ?? 12,
      sidebarShowIcons: flag("sidebarShowIcons"),
      enableMessageActions: flag("enableMessageActions"),
      showChatListLastMessage: flag("showChatListLastMessage"),
      chatListDesignEnabled: flag("chatListDesignEnabled"),
      chatListCornerRadius: number("chatListCornerRadius"),
      chatListAccentColor: color("chatListAccentColor"),
      chatListBackgroundColor: color("chatListBackgroundColor"),
      chatListBackgroundColorIndex:
          (j["chatListBackgroundColorIndex"] as num?)?.toInt(),
      chatListSelectedColor: color("chatListSelectedColor"),
      chatListSelectedColorIndex:
          (j["chatListSelectedColorIndex"] as num?)?.toInt(),
      chatListAccentColorIndex:
          (j["chatListAccentColorIndex"] as num?)?.toInt(),
      chatListGlowIntensity: number("chatListGlowIntensity"),
      chatListTopHighlight: flag("chatListTopHighlight", fallback: true),
      chatBackdropWash: flag("chatBackdropWash"),
      enableChatSearch: flag("enableChatSearch"),
      chatSidebarFooter: flag("chatSidebarFooter", fallback: true),
      formattingToolbar: flag("formattingToolbar"),
      composerPolish: flag("composerPolish"),
      // "squareBubbles" is what this was before the corners became fully
      // adjustable: a toggle whose on state meant a 4px radius both ways.
      bubbleCorners: flag("bubbleCorners") || flag("squareBubbles"),
      bubbleRadiusSent:
          number("bubbleRadiusSent") ?? (flag("squareBubbles") ? 4 : 10),
      bubbleRadiusSentSides: SideValues.fromJson(j["bubbleRadiusSentSides"]),
      bubbleRadiusReceived:
          number("bubbleRadiusReceived") ?? (flag("squareBubbles") ? 4 : 10),
      bubbleRadiusReceivedSides:
          SideValues.fromJson(j["bubbleRadiusReceivedSides"]),
      bubbleCornerStyle: _enumOr(BubbleCornerStyle.values,
          j["bubbleCornerStyle"], BubbleCornerStyle.rounded),
      messageLayoutMode:
          _enumOrNull(MessageLayoutMode.values, j["messageLayoutMode"]),
      messageSpacing: (j["messageSpacing"] as num?)?.toDouble(),
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
      expandMessagePaddingSides:
          SideValues.fromJson(j["expandMessagePaddingSides"]),
      autoUnmuteOnJoin: flag("autoUnmuteOnJoin"),
      rtcSessionCornerRadius: number("rtcSessionCornerRadius"),
      rtcActiveSessionColor: color("rtcActiveSessionColor"),
      rtcActiveSessionColorIndex:
          (j["rtcActiveSessionColorIndex"] as num?)?.toInt(),
      rtcLiveColor: color("rtcLiveColor"),
      rtcLiveColorIndex: (j["rtcLiveColorIndex"] as num?)?.toInt(),
      rtcMutedColor: color("rtcMutedColor"),
      rtcMutedColorIndex: (j["rtcMutedColorIndex"] as num?)?.toInt(),
      rtcWarningColor: color("rtcWarningColor"),
      rtcWarningColorIndex: (j["rtcWarningColorIndex"] as num?)?.toInt(),
      rtcStageAvatarRadius: number("rtcStageAvatarRadius"),
      rtcStageCollapsed: j["rtcStageCollapsed"] == true,
      payStatsCardStyle: flag("payStatsCardStyle"),
      // "settingsShellRestyle" is accountCardLayout's old name, from when
      // it lived on the Master area (see ThemePreset.fromJson, which moves
      // it across to the Account area a preset saved then won't have).
      accountCardLayout:
          flag("accountCardLayout") || flag("settingsShellRestyle"),
      feedCardRedesign: flag("feedCardRedesign"),
      // Bookmarks and hiding were folded into feedCardActions; a preset
      // that had either on gets the bundle.
      feedCardActions: flag("feedCardActions") ||
          flag("feedBookmarks") ||
          flag("feedHidePosts"),
      feedSidePanel: flag("feedSidePanel"),
      // Likewise the composer's formatting/attach/drafts toggles.
      feedInlineComposer: flag("feedInlineComposer") ||
          flag("feedComposerFormatting") ||
          flag("feedComposerAttach") ||
          flag("feedDrafts"),
      feedHideSidebarOnPost: flag("feedHideSidebarOnPost"),
      markdownCustomGuide: j["markdownCustomGuide"] is Map
          ? Map<String, Object?>.from(j["markdownCustomGuide"] as Map)
          : null,
      markdownSavedGuides: j["markdownSavedGuides"] is Map
          ? Map<String, Object?>.from(j["markdownSavedGuides"] as Map)
          : const {},
      markdownImageWidthPercent: number("markdownImageWidthPercent"),
      markdownImageRadius: number("markdownImageRadius"),
      markdownImageBorderWidth: number("markdownImageBorderWidth"),
      markdownImageBorderColor: j["markdownImageBorderColor"] is String
          ? colorFromHex(j["markdownImageBorderColor"] as String)
          : null,
      markdownImageBorderColorIndex:
          (j["markdownImageBorderColorIndex"] as num?)?.toInt(),
      markdownImageGap: number("markdownImageGap"),
      markdownImageAlign:
          _enumOrNull(MarkdownAlign.values, j["markdownImageAlign"]),
      markdownGuideId: j["markdownGuideId"] is String
          ? j["markdownGuideId"] as String
          : "default",
      feedImageLayout: _enumOr(FeedImageLayout.values, j["feedImageLayout"],
          FeedImageLayout.standard),
      feedImageCropHeight: number("feedImageCropHeight") ?? 300,
      feedTextOrder: _enumOr(
          FeedTextOrder.values, j["feedTextOrder"], FeedTextOrder.standard),
      feedLinksMode: _enumOr(
          FeedLinksMode.values, j["feedLinksMode"], FeedLinksMode.standard),
      feedTextLimit: number("feedTextLimit") ?? 0,
      feedStripMarkdown: flag("feedStripMarkdown"),
      pagesWidthCap: number("pagesWidthCap") ?? 0,
      pagesBackgroundColor: color("pagesBackgroundColor"),
      pagesBackgroundColorIndex: (j["pagesBackgroundColorIndex"] as num?)?.toInt(),
      // Defaults to on, so its absence cannot be read as off: every style
      // saved before this existed has no key here at all.
      pagesHonourBackground: flag("pagesHonourBackground", fallback: true),
      mobileTapOpensSidebar: flag("mobileTapOpensSidebar"),
      mobileNavHideLabels: flag("mobileNavHideLabels"),
      mobileSidebarAvatarCloses: flag("mobileSidebarAvatarCloses"),
      mobileAvatarOpensProfile: flag("mobileAvatarOpensProfile"),
      mobileHideBackButton: flag("mobileHideBackButton"),
      mobileHideSelfAvatar: flag("mobileHideSelfAvatar"),
      mobileAvatarSecondTapCloses: flag("mobileAvatarSecondTapCloses"),
    );
  }

  // ---------------------------------------------------------------------------
  // Resolved values
  // ---------------------------------------------------------------------------

  // borderWidths/borderRadii/paddings/margins are the four spacing settings
  // resolved to a value per side: the per-side split if the user made one,
  // otherwise that setting's single value on all four sides.
  SideValues get borderWidths =>
      borderWidthSides ?? SideValues.all(borderWidth);
  SideValues get borderRadii =>
      borderRadiusSides ?? SideValues.all(borderRadius);
  SideValues get paddings => paddingSides ?? SideValues.all(padding);
  SideValues get margins => marginSides ?? SideValues.all(margin);

  // The chat bubbles' corner radii and the conversation panel's inset,
  // resolved the same way: the per-side split if there is one, otherwise
  // the single value all round.
  SideValues get bubbleRadiiSent =>
      bubbleRadiusSentSides ?? SideValues.all(bubbleRadiusSent);
  SideValues get bubbleRadiiReceived =>
      bubbleRadiusReceivedSides ?? SideValues.all(bubbleRadiusReceived);
  SideValues get expandMessagePaddings =>
      expandMessagePaddingSides ?? SideValues.all(expandMessagePadding ?? 0);

  // messageGap/sameUserMessageGap are the two vertical gaps between chat
  // messages: above one from a new sender, and above one from whoever just
  // spoke. Untouched they are the 10 and 2 the conversation has always
  // used; setting the first scales the second by the proportion those two
  // already stood in, so opening the conversation up keeps a run of
  // messages reading as one group rather than flattening it into an evenly
  // spaced list.
  static const double _defaultMessageGap = 10;
  static const double _sameUserGapRatio = 0.2; // 2 of 10.
  double get messageGap => messageSpacing ?? _defaultMessageGap;
  double get sameUserMessageGap => messageGap * _sameUserGapRatio;
  SideValues get dcrPricePaddings =>
      dcrPricePaddingSides ?? SideValues.all(dcrPricePadding);
  SideValues get btcPricePaddings =>
      btcPricePaddingSides ?? SideValues.all(btcPricePadding);

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
      chatListAccentColorIndex: remap(chatListAccentColorIndex),
      clearChatListAccentColorIndex: remap(chatListAccentColorIndex) == null,
      rtcActiveSessionColorIndex: remap(rtcActiveSessionColorIndex),
      clearRtcActiveSessionColorIndex:
          remap(rtcActiveSessionColorIndex) == null,
      rtcLiveColorIndex: remap(rtcLiveColorIndex),
      clearRtcLiveColorIndex: remap(rtcLiveColorIndex) == null,
      rtcMutedColorIndex: remap(rtcMutedColorIndex),
      clearRtcMutedColorIndex: remap(rtcMutedColorIndex) == null,
      rtcWarningColorIndex: remap(rtcWarningColorIndex),
      clearRtcWarningColorIndex: remap(rtcWarningColorIndex) == null,
      chatListBackgroundColorIndex: remap(chatListBackgroundColorIndex),
      clearChatListBackgroundColorIndex:
          remap(chatListBackgroundColorIndex) == null,
      chatListSelectedColorIndex: remap(chatListSelectedColorIndex),
      clearChatListSelectedColorIndex:
          remap(chatListSelectedColorIndex) == null,
      messageAreaColorIndex: remap(messageAreaColorIndex),
      clearMessageAreaColorIndex: remap(messageAreaColorIndex) == null,
      inputBackgroundColorIndex: remap(inputBackgroundColorIndex),
      clearInputBackgroundColorIndex: remap(inputBackgroundColorIndex) == null,
      inputBorderColorIndex: remap(inputBorderColorIndex),
      clearInputBorderColorIndex: remap(inputBorderColorIndex) == null,
      buttonStyles: {
        for (var e in buttonStyles.entries)
          e.key: e.value.remapPaletteIndexes(removed),
      },
    );
  }
}
