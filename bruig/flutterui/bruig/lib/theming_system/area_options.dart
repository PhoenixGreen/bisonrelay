// area_options.dart holds the multiple-choice settings (and their dropdown
// labels) belonging to individual theme areas, grouped by area. They live
// here rather than in each area's theming_area_<name>.dart file so the model
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

const Map<SubMenuStyle, String> _subMenuStyleLabels = {
  SubMenuStyle.alwaysVisible: "Default (Always visible)",
  SubMenuStyle.hoverReveal: "Reveal on hover",
  SubMenuStyle.autoHideOnDetail: "Auto-hide when not needed",
  SubMenuStyle.manualToggle: "Manual show/hide",
  SubMenuStyle.resizable: "Resizable (drag to resize)",
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
// Login Screen, Navigation Bar; see imageAreas in theming_areas_section.dart)
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
enum AreaImagePreset { standard, exitus1, grid, dots, diagonal, crosshatch, waves }

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
