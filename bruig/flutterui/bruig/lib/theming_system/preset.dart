import 'package:bruig/theming_system/app_theme.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/area_style.dart';
import 'package:bruig/theming_system/color_hex.dart';
import 'package:bruig/theming_system/color_palette.dart';
import 'package:bruig/theming_system/theme_area.dart';
import 'package:bruig/theming_system/theme_tokens.dart';
import 'package:flutter/material.dart';

// ThemePreset is one full, nameable, exportable custom theme: a palette (one
// color per PaletteSlot, plus any user-added extras) and a set of per-area
// style overrides. toAppTheme() compiles it into the same AppTheme shape the
// built-in dark/light themes use, so custom presets render through the
// pipeline the rest of the app already trusts.
class ThemePreset {
  final String id;
  final String name;
  final Brightness brightness;

  // ---------------------------------------------------------------------------
  // The palette -- one color per PaletteSlot, in the roles documented there.
  // ---------------------------------------------------------------------------
  final Color primary; // Main app background (and ColorScheme.fromSeed's
  // seed color). Also the Theme Areas section's select-menu popup
  // background.
  // The Dual Panel and Content Area areas' default backgrounds. Both are
  // seeded to primary's own value, so an untouched preset looks exactly as
  // it did when those regions simply let the master background show
  // through -- see PaletteSlot.dualBackground.
  final Color dualBackground;
  final Color contentBackground;
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

  // extraPaletteColors are user-added swatches beyond the fixed roles
  // above -- free-form, no fixed semantic meaning, just additional options
  // offered wherever an area style needs a color picked (see `palette`
  // below and the theme editor's palette-color dropdowns). Capped at
  // kMaxExtraPaletteColors so the total palette never exceeds
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
    required this.dualBackground,
    required this.contentBackground,
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

  Color forSlot(PaletteSlot slot) => switch (slot) {
        PaletteSlot.primary => primary,
        PaletteSlot.dualBackground => dualBackground,
        PaletteSlot.contentBackground => contentBackground,
        PaletteSlot.secondary => secondary,
        PaletteSlot.tertiary => tertiary,
        PaletteSlot.fourth => fourth,
        PaletteSlot.sidebarBackground => sidebarBackground,
        PaletteSlot.speechBackground => speechBackground,
        PaletteSlot.speechBackgroundSent => speechBackgroundSent,
        PaletteSlot.accentContainer => accentContainer,
        PaletteSlot.onSurface => onSurface,
        PaletteSlot.onSurfaceVariant => onSurfaceVariant,
        PaletteSlot.navText => navText,
        PaletteSlot.navAccent => navAccent,
        PaletteSlot.sidebarText => sidebarText,
        PaletteSlot.sidebarAccent => sidebarAccent,
        PaletteSlot.outline => outline,
        PaletteSlot.error => error,
        PaletteSlot.success => success,
      };

  ThemePreset withSlot(PaletteSlot slot, Color c) => switch (slot) {
        PaletteSlot.primary => copyWith(primary: c),
        PaletteSlot.dualBackground => copyWith(dualBackground: c),
        PaletteSlot.contentBackground => copyWith(contentBackground: c),
        PaletteSlot.secondary => copyWith(secondary: c),
        PaletteSlot.tertiary => copyWith(tertiary: c),
        PaletteSlot.fourth => copyWith(fourth: c),
        PaletteSlot.sidebarBackground => copyWith(sidebarBackground: c),
        PaletteSlot.speechBackground => copyWith(speechBackground: c),
        PaletteSlot.speechBackgroundSent => copyWith(speechBackgroundSent: c),
        PaletteSlot.accentContainer => copyWith(accentContainer: c),
        PaletteSlot.onSurface => copyWith(onSurface: c),
        PaletteSlot.onSurfaceVariant => copyWith(onSurfaceVariant: c),
        PaletteSlot.navText => copyWith(navText: c),
        PaletteSlot.navAccent => copyWith(navAccent: c),
        PaletteSlot.sidebarText => copyWith(sidebarText: c),
        PaletteSlot.sidebarAccent => copyWith(sidebarAccent: c),
        PaletteSlot.outline => copyWith(outline: c),
        PaletteSlot.error => copyWith(error: c),
        PaletteSlot.success => copyWith(success: c),
      };

  // palette returns the fixed-role colors (in PaletteSlot order) plus any
  // extraPaletteColors -- this is the full set of colors offered wherever
  // an area style needs a color picked (see the theme editor's
  // palette-color dropdowns).
  List<Color> get palette =>
      [...PaletteSlot.values.map(forSlot), ...extraPaletteColors];

  ThemePreset copyWith({
    String? id,
    String? name,
    Brightness? brightness,
    Color? primary,
    Color? dualBackground,
    Color? contentBackground,
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
        dualBackground: dualBackground ?? this.dualBackground,
        contentBackground: contentBackground ?? this.contentBackground,
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

  static Color _darken(Color c, double amount) {
    var hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  // toAppTheme compiles this preset into an AppTheme using exactly the same
  // ColorScheme.fromSeed()+copyWith() formula the built-in "dark"/"light"
  // themes are hand-written with (see appThemes), so custom presets render
  // through the same pipeline the rest of the app already trusts.
  //
  // It deliberately does NOT force secondary (or most Material-derived
  // roles) into ColorScheme.fromSeed -- those roles drive the foreground of
  // many standard Material widgets, and forcing them to the user's raw
  // palette swatch can produce illegible text-on-background. `primary` (the
  // seed), `tertiary`, `error`, and `onSurface` are safe to pass through
  // directly since ColorScheme.fromSeed independently derives a full,
  // properly-contrasting tonal ramp (onTertiary/tertiaryContainer/onError/
  // errorContainer/etc.) from each -- the same way `surface` already was.
  // `onSurface` in particular is what "On surface text" actually needs to
  // drive general app text/icon color (most Text/Icon widgets read
  // colorScheme.onSurface when given no explicit color) -- without passing
  // it here, editing that palette slot had no visible effect anywhere.
  AppTheme toAppTheme() {
    // interTextTheme/interBlackTextTheme hardcode Colors.white70/black54 on
    // every style -- reused as-is, a plain Text widget with no explicit
    // color (i.e. most of them; only this app's own Txt component with an
    // explicit TextColor reads colorScheme.onSurface directly) would never
    // reflect a custom preset's "On surface text" pick at all, regardless
    // of the colorScheme.onSurface override below. .apply() recolors every
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

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        "id": id,
        "name": name,
        "brightness": brightness.name,
        // paletteVersion marks which PaletteSlot layout a preset's stored
        // color *indexes* were written against -- 2 after the reorder and
        // buttonBorder removal, 3 after Dual/Content Background were
        // inserted below primary. The palette map itself is keyed by slot
        // *name*, so it's unaffected by either; only AreaStyle's index
        // fields (raw positions into the flat `palette` list) need this to
        // know whether they still need remapping on load.
        "paletteVersion": 3,
        "palette": {
          for (var slot in PaletteSlot.values)
            slot.name: colorToHex(forSlot(slot)),
        },
        if (extraPaletteColors.isNotEmpty)
          "extraPaletteColors": extraPaletteColors.map(colorToHex).toList(),
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

  // _legacyPaletteOrderV2 is PaletteSlot's order as it existed before
  // paletteVersion 3 -- i.e. before dualBackground/contentBackground were
  // inserted just after primary, which pushed every slot after it along by
  // two.
  static const List<PaletteSlot> _legacyPaletteOrderV2 = [
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

  static int? _migrateLegacyColorIndex(int? oldIndex, int version) {
    if (oldIndex == null) return null;
    // Mapping through slot *values* means each lands wherever that slot
    // sits today, so these tables don't need touching again when the order
    // changes -- only a new one added for the new layout.
    var order = version < 2 ? _legacyPaletteOrderV1 : _legacyPaletteOrderV2;
    if (oldIndex < order.length) return order[oldIndex].index;
    // An extra (user-added) color, appended after the fixed roles: rebase
    // it onto however many roles there are now.
    return oldIndex - order.length + PaletteSlot.values.length;
  }

  factory ThemePreset.fromJson(Map<String, dynamic> j) {
    var p = j["palette"] as Map<String, dynamic>;
    var preset = seedFor(
      j["brightness"] == "light" ? Brightness.light : Brightness.dark,
    ).copyWith(id: j["id"], name: j["name"] ?? "Default Theme");
    for (var slot in PaletteSlot.values) {
      var hex = p[slot.name];
      if (hex != null) preset = preset.withSlot(slot, colorFromHex(hex));
    }
    var rawAreas = j["areas"] as Map<String, dynamic>? ?? {};
    var paletteVersion = (j["paletteVersion"] as num?)?.toInt() ?? 1;
    if (paletteVersion != 3) {
      rawAreas = rawAreas.map((k, v) {
        var area = Map<String, dynamic>.from(v as Map<String, dynamic>);
        // Every field holding a raw position into the flat palette list.
        for (var key in [
          "solidColorIndex",
          "borderColorIndex",
          "sidebarDividerColorIndex",
          "chatListAccentColorIndex",
          "chatListBackgroundColorIndex",
          "chatListSelectedColorIndex",
        ]) {
          if (area[key] != null) {
            area[key] = _migrateLegacyColorIndex(
                (area[key] as num).toInt(), paletteVersion);
          }
        }
        for (var key in ["gradientColorIndexes", "borderGradientColorIndexes"]) {
          if (area[key] is List) {
            area[key] = (area[key] as List)
                .map((e) => e == null
                    ? null
                    : _migrateLegacyColorIndex(
                        (e as num).toInt(), paletteVersion))
                .toList();
          }
        }
        return MapEntry(k, area);
      });
    }
    return preset.copyWith(
      extraPaletteColors: j["extraPaletteColors"] != null
          ? (j["extraPaletteColors"] as List)
              .map((h) => colorFromHex(h as String))
              .toList()
          : const [],
      // Skip any area key that no longer matches a known ThemeArea (e.g.
      // saved by a future/older version of the app) instead of throwing.
      areas: _migrateAreas({
        for (var e in rawAreas.entries)
          if (ThemeArea.values.where((a) => a.name == e.key).firstOrNull
              case var area?)
            area: AreaStyle.fromJson(e.value as Map<String, dynamic>)
      }),
      menuLabels: j["menuLabels"] != null
          ? (j["menuLabels"] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String))
          : null,
      menuOrder: j["menuOrder"] != null
          ? (j["menuOrder"] as List).cast<String>()
          : null,
    );
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
  static Map<ThemeArea, AreaStyle> _migrateAreas(
      Map<ThemeArea, AreaStyle> areas) {
    var master = areas[ThemeArea.masterBackground];
    if (master == null) return areas;

    var migrated = Map<ThemeArea, AreaStyle>.from(areas);
    if (master.accountCardLayout) {
      var account = migrated[ThemeArea.account] ?? const AreaStyle();
      if (!account.accountCardLayout) {
        migrated[ThemeArea.account] =
            account.copyWith(accountCardLayout: true);
      }
    }
    if (master.avatarTheme != AvatarTheme.standard) {
      var chat = migrated[ThemeArea.chat] ?? const AreaStyle();
      if (chat.avatarTheme == AvatarTheme.standard) {
        migrated[ThemeArea.chat] =
            chat.copyWith(avatarTheme: master.avatarTheme);
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

  // ---------------------------------------------------------------------------
  // Seeds
  // ---------------------------------------------------------------------------

  // seedFor returns the starting-point preset for a base brightness -- not a
  // separate installable preset, just what the palette editor pre-fills with
  // (and what a freshly-created "New Theme" starts from).
  static ThemePreset seedFor(Brightness brightness) =>
      brightness == Brightness.dark ? seedFromDark() : seedFromLight();

  // secondary/sidebarBackground/navText/navAccent/sidebarText/sidebarAccent
  // are read straight off appThemes' real ColorScheme rather than
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
      // Same as primary: a page shows the master background through until
      // one of these is deliberately moved off it.
      dualBackground: const Color(0xFF19172C),
      contentBackground: const Color(0xFF19172C),
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
      dualBackground: const Color(0xFFE8E7F3),
      contentBackground: const Color(0xFFE8E7F3),
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
