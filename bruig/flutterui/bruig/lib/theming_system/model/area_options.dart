// area_options.dart holds the multiple-choice settings (and their dropdown
// labels) belonging to individual theme areas, grouped by area. They live
// here rather than in each area's editor/areas/<name>.dart file so the model
// layer (AreaStyle, which stores them) never has to depend on the editor UI
// that presents them.
//
// Purely on/off area settings aren't here -- they're plain bools on
// AreaStyle. Settings shared by every area (background/border fill modes)
// live in area_fill.dart; ContentAlign, shared by the header and nav bar,
// lives in theme_area.dart.

// ---------------------------------------------------------------------------
// Header (ThemeArea.header)
// ---------------------------------------------------------------------------

// HeaderPosition controls where (or whether) the header renders:
// - top: today's behavior, a full-width bar above everything (sidebar
//   included).
// - content: a bar the same width as just the content area (to the right
//   of the primary nav sidebar), with the logo/about-button and "new post"
//   button removed since they belong to the global app chrome, not a
//   per-content-area bar.
// - none: no header at all; the content area extends to fill that space.
enum HeaderPosition { top, content, none }

const Map<HeaderPosition, String> _headerPositionLabels = {
  HeaderPosition.top: "Default (Top)",
  HeaderPosition.content: "Content",
  HeaderPosition.none: "None",
};

String headerPositionLabel(HeaderPosition p) => _headerPositionLabels[p]!;

// ---------------------------------------------------------------------------
// Sidebar (ThemeArea.subMenuTabBar)
// ---------------------------------------------------------------------------

// SubMenuStyle controls how a page's sidebar (its sub-navigation tabs, e.g.
// Settings' Account/Appearance/Notifications/... list) shows or hides
// itself. Every sidebar in the app -- the "tab-style" ones with a small
// fixed set of destinations (Settings, LN Management, Feed, Manage Content,
// Address Book, the plugin screen switcher) as well as the dynamic,
// potentially-long lists (chat list, RTC sessions, page-view sessions) --
// is driven by this same setting.
// - alwaysVisible: today's behavior, a persistent column beside the content.
// - resizable: a plain, always-visible, drag-resizable pane (each screen
//   remembers its own width locally -- see SecondarySideMenuLayout).
// - collapsed: not beside the content at all; it opens as a drawer over
//   everything, by tapping the already-selected item in the main
//   navigation. This is what a window too narrow for a sidebar column
//   falls back to on its own; picking it here asks for it at any width.
//
// A preset naming a value this build doesn't have falls back to
// alwaysVisible -- see _enumOrNull in area_style.dart.
enum SubMenuStyle { alwaysVisible, resizable, collapsed }

const Map<SubMenuStyle, String> _subMenuStyleLabels = {
  SubMenuStyle.alwaysVisible: "Default (Always visible)",
  SubMenuStyle.resizable: "Resizable (drag to resize)",
  SubMenuStyle.collapsed: "Collapsed (tap the Nav item again to open)",
};

String subMenuStyleLabel(SubMenuStyle s) => _subMenuStyleLabels[s]!;

// ---------------------------------------------------------------------------
// Chat (ThemeArea.chat)
// ---------------------------------------------------------------------------

// MessageLayoutMode controls how chat messages are arranged in the
// conversation view.
// - standard: today's behavior (own messages right-aligned, others left).
// - leftAlign: every message stacks in a single left-hand column.
// - narrow: the message list is centered into a narrower column.
enum MessageLayoutMode { standard, leftAlign, narrow }

const Map<MessageLayoutMode, String> _messageLayoutModeLabels = {
  MessageLayoutMode.standard: "Default",
  MessageLayoutMode.leftAlign: "Left-align messages",
  MessageLayoutMode.narrow: "Narrow conversation",
};

String messageLayoutModeLabel(MessageLayoutMode m) =>
    _messageLayoutModeLabels[m]!;

// BubbleCornerStyle shapes how a message bubble's corners are cut, at
// whatever radius AreaStyle.bubbleRadius{Sent,Received} sets. Only consulted
// when AreaStyle.bubbleCorners is on.
// - rounded: the ordinary rounded rectangle.
// - beveled: corners cut straight across, an angular/faceted look.
// - speech: rounded, except the bottom corner on the speaker's own side is
//   left square -- the corner a comic speech bubble's tail grows out of, and
//   the shape most chat apps use to point a bubble back at its sender.
// - inverted: corners curve inward rather than out, scooped instead of
//   rounded.
enum BubbleCornerStyle { rounded, beveled, speech, inverted }

const Map<BubbleCornerStyle, String> _bubbleCornerStyleLabels = {
  BubbleCornerStyle.rounded: "Rounded",
  BubbleCornerStyle.beveled: "Cut corners",
  BubbleCornerStyle.speech: "Speech bubble",
  BubbleCornerStyle.inverted: "Inverted corners",
};

String bubbleCornerStyleLabel(BubbleCornerStyle s) =>
    _bubbleCornerStyleLabels[s]!;

// AvatarTheme picks how the *fallback* avatar (the colored circle behind a
// user's initial, shown when they have no avatar image of their own) is
// colored. A real avatar image is never affected. Every avatar in the app
// funnels through InteractiveAvatar, so this is app-wide despite living on
// the Chat area -- that's simply where users look for it.
//
// All five hash the nick, so a given user always gets the same color; they
// differ in what they hash it into. See avatarColorFromNick.
// - standard: today's behavior -- a hue from right around the color wheel
//   at middling saturation.
// - monochrome: neutral graphite grays, for a deliberately colorless look.
// - muted: standard's hue, heavily desaturated.
// - vivid: standard's hue, near-fully saturated.
// - palette: one of the active theme's own accent colors, so avatars read
//   as part of the theme rather than an unrelated rainbow. Falls back to
//   standard for the built-in themes, which have no palette to draw on.
enum AvatarTheme { standard, monochrome, muted, vivid, palette }

const Map<AvatarTheme, String> _avatarThemeLabels = {
  AvatarTheme.standard: "Default (colorful)",
  AvatarTheme.monochrome: "Monochrome",
  AvatarTheme.muted: "Muted",
  AvatarTheme.vivid: "Vivid",
  AvatarTheme.palette: "Theme palette",
};

String avatarThemeLabel(AvatarTheme t) => _avatarThemeLabels[t]!;

// ---------------------------------------------------------------------------
// Feed (ThemeArea.feed)
// ---------------------------------------------------------------------------

// FeedImageLayout controls how a feed post's first embedded image is
// displayed. Only ever applies to the first image in a post -- any further
// embedded images stay wherever they fall in the post's normal markdown
// flow.
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

const Map<FeedImageLayout, String> _feedImageLayoutLabels = {
  FeedImageLayout.standard: "Default",
  FeedImageLayout.left: "Left",
  FeedImageLayout.right: "Right",
  FeedImageLayout.full: "Full width",
  FeedImageLayout.cropped: "Full width, cropped",
  FeedImageLayout.random: "Random",
  FeedImageLayout.none: "None",
};

String feedImageLayoutLabel(FeedImageLayout m) => _feedImageLayoutLabels[m]!;

// FeedTextOrder controls whether a post's text renders before or after its
// first image, and only applies when the image is actually stacked above/
// below the text -- i.e. FeedImageLayout.standard (once an image has been
// extracted for ordering purposes), .full, or .cropped (including .random
// when it resolves to one of those). Ignored for .left/.right, which
// already have a fixed side-by-side arrangement.
// - standard: today's behavior -- text first, then the image below it.
// - textFirst: same as standard (explicit, in case standard's meaning
//   changes later).
// - textLast: image first, then the text below it.
enum FeedTextOrder { standard, textFirst, textLast }

const Map<FeedTextOrder, String> _feedTextOrderLabels = {
  FeedTextOrder.standard: "Default",
  FeedTextOrder.textFirst: "Text first",
  FeedTextOrder.textLast: "Text last",
};

String feedTextOrderLabel(FeedTextOrder o) => _feedTextOrderLabels[o]!;

// FeedLinksMode controls whether links are stripped out of feed post
// bodies entirely.
// - standard: today's behavior -- links render and work normally.
// - off: links are stripped from every post's body.
// - offIfImage: links are stripped only from posts that contain an image
//   (regardless of the chosen FeedImageLayout/whether that image ends up
//   specially positioned).
enum FeedLinksMode { standard, off, offIfImage }

const Map<FeedLinksMode, String> _feedLinksModeLabels = {
  FeedLinksMode.standard: "Default",
  FeedLinksMode.off: "Turn off links",
  FeedLinksMode.offIfImage: "Turn off links if image available",
};

String feedLinksModeLabel(FeedLinksMode m) => _feedLinksModeLabels[m]!;

// ---------------------------------------------------------------------------
// Image preset -- the four areas with a background image (Master, Header,
// Login Screen, Navigation Bar; see imageAreas in editor/areas_section.dart)
// ---------------------------------------------------------------------------

// AreaImagePreset picks one of the built-in background images, for an area
// whose background mode is Default or Image (a solid/gradient fill, or a
// user-picked image file, overrides it entirely). See areaImagePresetImage
// in area_fill.dart for what each one paints.
//
// - standard: the original "network pattern" image -- the Default Theme's
//   login background, and so the default here.
// - exitus1: a full-bleed portrait photo, ported from exitus1/chat-redesign
//   (on the login screen it also gets a radial scrim behind the form; see
//   StartupScreen).
// - grid/dots/diagonal/crosshatch/waves: small seamless tiles drawn in a
//   mid-grey that reads over both light and dark backgrounds. Being tiled
//   rather than stretched, they suit any area's size -- a full-screen
//   Master background, a thin Header strip or the narrow Navigation Bar
//   column all get the same-sized motif.
enum AreaImagePreset {
  standard,
  exitus1,
  grid,
  dots,
  diagonal,
  crosshatch,
  waves
}

const Map<AreaImagePreset, String> _areaImagePresetLabels = {
  AreaImagePreset.standard: "Default",
  AreaImagePreset.exitus1: "Exitus1 style",
  AreaImagePreset.grid: "Grid",
  AreaImagePreset.dots: "Dots",
  AreaImagePreset.diagonal: "Diagonal lines",
  AreaImagePreset.crosshatch: "Crosshatch",
  AreaImagePreset.waves: "Waves",
};

String areaImagePresetLabel(AreaImagePreset p) => _areaImagePresetLabels[p]!;
