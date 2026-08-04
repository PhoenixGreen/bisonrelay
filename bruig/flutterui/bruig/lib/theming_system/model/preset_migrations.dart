import 'package:bruig/theming_system/model/area_options.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/color_palette.dart';
import 'package:bruig/theming_system/model/theme_area.dart';

// preset_migrations.dart carries every preset a previous build could have
// written forward to what this one expects. It is pure back-compat: nothing
// here runs for a preset saved by the current version, and a reviewer can
// read ThemePreset (preset.dart) without it.
//
// Two kinds of drift are handled:
//
//   1. The palette was reordered. AreaStyle binds a color by its raw index
//      into ThemePreset.palette, so inserting a slot renumbers every binding
//      past it. Each _legacyPaletteOrderVn below is PaletteSlot's order as
//      of paletteVersion n; migrateLegacyColorIndex maps an old index
//      through it to wherever that slot sits today.
//   2. A setting changed areas. migrateAreas moves those across.

// _legacyPaletteOrderV1 is PaletteSlot's order as it existed before
// paletteVersion 2 (i.e. before Button Border was removed and merged into
// navAccent, and the remaining slots were regrouped by
// background/text/accent tier). Used only to remap solidColorIndex/
// borderColorIndex values -- raw positions into the flat `palette` list
// -- saved by presets written before this change; the old buttonBorder
// slot maps to navAccent, its merge target.
const List<PaletteSlot> _legacyPaletteOrderV1 = [
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

// _legacyPaletteOrderV2 is PaletteSlot's order as it existed before
// paletteVersion 3 -- i.e. before dualBackground/contentBackground were
// inserted just after primary, which pushed every slot after it along by
// two.
const List<PaletteSlot> _legacyPaletteOrderV2 = [
  PaletteSlot.primary,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV3 is PaletteSlot's order as it existed before
// paletteVersion 4 -- i.e. before inputSelected was inserted just after
// navAccent, pushing the three slots below it along by one.
const List<PaletteSlot> _legacyPaletteOrderV3 = [
  PaletteSlot.primary,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV4 is PaletteSlot's order as it existed before
// paletteVersion 5 -- i.e. before inputResting was inserted just before
// inputSelected.
const List<PaletteSlot> _legacyPaletteOrderV4 = [
  PaletteSlot.primary,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.inputSelected,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV5 is PaletteSlot's order as it existed before
// paletteVersion 6 -- i.e. before navSelected was inserted just after
// secondary.
const List<PaletteSlot> _legacyPaletteOrderV5 = [
  PaletteSlot.primary,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.inputResting,
  PaletteSlot.inputSelected,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV6 is PaletteSlot's order as it existed before
// paletteVersion 7 -- i.e. before headerBackground was inserted just
// after primary.
const List<PaletteSlot> _legacyPaletteOrderV6 = [
  PaletteSlot.primary,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.navSelected,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.inputResting,
  PaletteSlot.inputSelected,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV7 is PaletteSlot's order as it existed before
// paletteVersion 8 -- i.e. before inputBackground was appended after
// inputSelected.
const List<PaletteSlot> _legacyPaletteOrderV7 = [
  PaletteSlot.primary,
  PaletteSlot.headerBackground,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.navSelected,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.inputResting,
  PaletteSlot.inputSelected,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

// _legacyPaletteOrderV8 is PaletteSlot's order as it existed before
// paletteVersion 9 -- i.e. before the six remaining Button Colors
// (Secondary/Third background, Border, Hover, Text 1, Text 2) were
// inserted after accentContainer, pushing everything below them along by
// six.
const List<PaletteSlot> _legacyPaletteOrderV8 = [
  PaletteSlot.primary,
  PaletteSlot.headerBackground,
  PaletteSlot.dualBackground,
  PaletteSlot.contentBackground,
  PaletteSlot.tertiary,
  PaletteSlot.secondary,
  PaletteSlot.navSelected,
  PaletteSlot.sidebarBackground,
  PaletteSlot.fourth,
  PaletteSlot.speechBackground,
  PaletteSlot.speechBackgroundSent,
  PaletteSlot.outline,
  PaletteSlot.onSurface,
  PaletteSlot.onSurfaceVariant,
  PaletteSlot.navText,
  PaletteSlot.sidebarText,
  PaletteSlot.accentContainer,
  PaletteSlot.navAccent,
  PaletteSlot.inputResting,
  PaletteSlot.inputSelected,
  PaletteSlot.inputBackground,
  PaletteSlot.sidebarAccent,
  PaletteSlot.error,
  PaletteSlot.success,
];

int? migrateLegacyColorIndex(int? oldIndex, int version) {
  if (oldIndex == null) return null;
  // Mapping through slot *values* means each lands wherever that slot
  // sits today, so these tables don't need touching again when the order
  // changes -- only a new one added for the new layout.
  var order = switch (version) {
    < 2 => _legacyPaletteOrderV1,
    2 => _legacyPaletteOrderV2,
    3 => _legacyPaletteOrderV3,
    4 => _legacyPaletteOrderV4,
    5 => _legacyPaletteOrderV5,
    6 => _legacyPaletteOrderV6,
    7 => _legacyPaletteOrderV7,
    _ => _legacyPaletteOrderV8,
  };
  if (oldIndex < order.length) return order[oldIndex].index;
  // An extra (user-added) color, appended after the fixed roles: rebase
  // it onto however many roles there are now.
  return oldIndex - order.length + PaletteSlot.values.length;
}

// _migrateAreas moves settings that have since changed areas out of the
// area they were saved under. Two lived on Master and were read from
// there app-wide; each now belongs to the area it actually describes, so
// a preset saved before the move still has them on Master, where nothing
// reads them any more. AreaStyle.fromJson parses both legacy keys into
// their new fields (see there), leaving only the hop across areas here.
//
// The destination wins if it already has a value of its own, so this
// can't undo a later edit; and Master keeps its own (now inert) copy
// rather than being rewritten, so an older build reading the same file
// still finds what it expects.
Map<ThemeArea, AreaStyle> migrateAreas(Map<ThemeArea, AreaStyle> areas) {
  var master = areas[ThemeArea.masterBackground];
  if (master == null) return areas;

  var migrated = Map<ThemeArea, AreaStyle>.from(areas);
  if (master.accountCardLayout) {
    var account = migrated[ThemeArea.account] ?? const AreaStyle();
    if (!account.accountCardLayout) {
      migrated[ThemeArea.account] = account.copyWith(accountCardLayout: true);
    }
  }
  if (master.avatarTheme != AvatarTheme.standard) {
    var chat = migrated[ThemeArea.chat] ?? const AreaStyle();
    if (chat.avatarTheme == AvatarTheme.standard) {
      migrated[ThemeArea.chat] = chat.copyWith(avatarTheme: master.avatarTheme);
    }
  }

  // Account, Stats and Logs became one "Settings Pages" area; the two
  // settings they had move with them. Their frames don't -- every page is
  // framed by Dual Panel now -- so a preset that styled a page's
  // background or border keeps that on the old (now unrendered) area
  // rather than having it silently reappear around a different region.
  var settings = migrated[ThemeArea.settingsPages] ?? const AreaStyle();
  var moved = false;
  if (migrated[ThemeArea.account]?.accountCardLayout == true &&
      !settings.accountCardLayout) {
    settings = settings.copyWith(accountCardLayout: true);
    moved = true;
  }
  if (migrated[ThemeArea.stats]?.payStatsCardStyle == true &&
      !settings.payStatsCardStyle) {
    settings = settings.copyWith(payStatsCardStyle: true);
    moved = true;
  }
  if (moved) migrated[ThemeArea.settingsPages] = settings;
  return migrated;
}
