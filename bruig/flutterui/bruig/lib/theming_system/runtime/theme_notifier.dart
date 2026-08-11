import 'package:bruig/storage_manager.dart';
import 'package:bruig/theming_system/model/area_style.dart';
import 'package:bruig/theming_system/model/area_style_render.dart';
import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/markdown_guides.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/model/preset.dart';
import 'package:bruig/theming_system/model/preset_theme.dart';
import 'package:bruig/theming_system/model/theme_area.dart';
import 'package:bruig/theming_system/runtime/app_theme.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:bruig/theming_system/storage/theme_preset_storage.dart';
import 'package:bruig/util.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

const double _defaultFontScale = 1;

// ThemeNotifier owns which theme is active and resolves this app's named
// tokens (SurfaceColor/TextColor -- see theme_tokens.dart) into concrete
// colors against it. It's also the registry for user-defined ThemePresets:
// each one compiles into an AppTheme registered under a "custom:<id>" key
// alongside the built-in "dark"/"light" entries in appThemes.
class ThemeNotifier with ChangeNotifier {
  static ThemeNotifier of(BuildContext context, {bool listen = true}) =>
      Provider.of<ThemeNotifier>(context, listen: listen);

  late ThemeData _themeData = appThemes[defaultThemeName]!.data;
  late AppTheme _fullTheme = appThemes[defaultThemeName]!;

  ThemeData get theme => _themeData;
  AppTheme get fullTheme => _fullTheme;
  Brightness get brightness => theme.brightness;
  ColorScheme get colors => _themeData.colorScheme;

  CustomColors _extraColors = const CustomColors();
  CustomColors get extraColors => _extraColors;

  CustomTextStyles _extraTextStyles = const CustomTextStyles();
  CustomTextStyles get extraTextStyles => _extraTextStyles;

  late String _themeMode = "";
  String getThemeMode() => _themeMode;

  late double _fontScale = _defaultFontScale;
  double get fontScale => _fontScale;

  late String _chatImageSize = defaultChatImageSize;
  String get chatImageSize => _chatImageSize;

  bool _themeLoaded = false;
  bool get themeLoaded => _themeLoaded;

  ThemeNotifier({doLoad = true}) {
    if (doLoad) _loadThemeFromConfig();
  }

  // newNotifierWhenLoaded returns a new ThemeNotifier only after it has finished
  // loading the theme data.
  static Future<ThemeNotifier> newNotifierWhenLoaded() async {
    var theme = ThemeNotifier(doLoad: false);
    try {
      await theme._loadThemeFromConfig();
    } catch (exception) {
      debugPrint("Error while loading theme: $exception");

      // Continue to return default theme.
    }
    return theme;
  }

  Future<void> _loadThemeFromConfig() async {
    var fontScaleCfg =
        await StorageManager.readData(StorageManager.fontScaleKey);
    _fontScale = double.parse(fontScaleCfg ?? "0");

    var chatImageSizeCfg =
        await StorageManager.readData(StorageManager.chatImageSizeKey);
    _chatImageSize = appImageSizes.containsKey(chatImageSizeCfg)
        ? chatImageSizeCfg!
        : defaultChatImageSize;

    // Register any saved custom presets into appThemes *before* resolving
    // the persisted theme mode, so a stored "custom:<id>" selection is
    // already available for switchTheme() to find.
    try {
      var presets = await ThemePresetStorage.listPresets();
      for (var preset in presets) {
        registerCustomPreset(preset, notify: false, markSaved: true);
      }
    } catch (exception) {
      debugPrint("Error while loading custom theme presets: $exception");
    }

    var themeModeCfg =
        await StorageManager.readData(StorageManager.themeModeKey);
    switchTheme(themeModeCfg ?? defaultThemeName);
  }

  // customPresets holds the raw (editable) ThemePreset behind each
  // registered "custom:<id>" entry in appThemes -- appThemes only holds the
  // compiled, read-only AppTheme, which isn't enough to drive a palette
  // editor (it doesn't retain the original palette colors).
  final Map<String, ThemePreset> customPresets = {};

  // savedPresetIds tracks which custom presets have actually been written
  // to disk (via saveActivePreset/import) as opposed to existing only as an
  // in-memory live-preview draft (via previewPreset). Only saved presets
  // are offered in the "load preset" list or are exportable -- editing
  // colors must never silently create a persisted, named preset on its
  // own; that only happens when the user explicitly saves.
  final Set<String> savedPresetIds = {};
  bool isPresetSaved(String id) => savedPresetIds.contains(id);

  // activePreset returns the raw ThemePreset behind the active theme, or
  // null if the active theme is one of the built-ins (dark/light/system).
  ThemePreset? get activePreset => _themeMode.startsWith("custom:")
      ? customPresets[_themeMode.substring("custom:".length)]
      : null;

  List<Color> _activePalette = const [];

  // activePalette is the active preset's full palette (fixed slots then
  // extras), empty for a built-in theme. Cached rather than rebuilt per
  // read: every palette-bound color an area renders resolves through it
  // (see AreaStyleRender), so on a themed frame it is read dozens of times,
  // and ThemePreset.palette allocates a new 30-entry list each time.
  List<Color> get activePalette => _activePalette;

  void _refreshActivePalette() {
    _activePalette = activePreset?.palette ?? const [];
  }

  // presetDisplayName returns the name to show the user for the active
  // theme, defaulting to "Default Theme" for the unmodified built-in, and
  // flagging an active draft that hasn't been saved yet.
  String get presetDisplayName {
    var p = activePreset;
    if (p != null) {
      return isPresetSaved(p.id) ? p.name : "${p.name} (unsaved)";
    }
    if (_themeMode == defaultThemeName) return "Default Theme";
    return appThemes[_themeMode]?.descr ?? "Default Theme";
  }

  // registerCustomPreset compiles a ThemePreset into an AppTheme and adds it
  // to appThemes under a "custom:<id>" key, making it selectable/switchable
  // exactly like the built-in "dark"/"light" themes. This alone never
  // touches disk -- see saveActivePreset for that.
  void registerCustomPreset(ThemePreset preset,
      {bool notify = true, bool markSaved = false}) {
    customPresets[preset.id] = preset;
    appThemes["custom:${preset.id}"] = preset.toAppTheme();
    if (markSaved) savedPresetIds.add(preset.id);
    // Re-registering the preset that's already active (saving it, say)
    // replaces its colors without going through switchTheme.
    if (_themeMode == "custom:${preset.id}") _refreshActivePalette();
    if (notify) notifyListeners();
  }

  // previewPreset applies an edited preset live (in memory only, no disk
  // write) so editors (palette/area sections) can show immediate feedback
  // without that turning into a persisted, named, loadable preset until the
  // user explicitly presses Save.
  void previewPreset(ThemePreset preset) {
    registerCustomPreset(preset, notify: false);
    switchTheme("custom:${preset.id}");
  }

  // saveActivePreset persists the currently active custom preset to disk,
  // optionally renaming it and/or embedding a menu rename/reorder
  // snapshot (see MainMenuModel.currentLabels/currentOrder) first, and
  // marks it as a saved/loadable preset. No-op if the active theme isn't a
  // custom preset.
  Future<void> saveActivePreset(
      {String? name,
      Map<String, String>? menuLabels,
      List<String>? menuOrder}) async {
    var preset = activePreset;
    if (preset == null) return;
    if (name != null && name.trim().isNotEmpty) {
      preset = preset.copyWith(name: name.trim());
    }
    if (menuLabels != null) preset = preset.copyWith(menuLabels: menuLabels);
    if (menuOrder != null) preset = preset.copyWith(menuOrder: menuOrder);
    var saved = await ThemePresetStorage.savePreset(preset);
    registerCustomPreset(saved, markSaved: true);
  }

  // deleteActivePreset removes the currently active custom preset -- from
  // disk too, if it had been saved -- and falls back to the default theme.
  // No-op if the active theme isn't a custom preset.
  Future<void> deleteActivePreset() async {
    var preset = activePreset;
    if (preset == null) return;
    if (isPresetSaved(preset.id)) {
      await ThemePresetStorage.deletePreset(preset.id);
    }
    unregisterCustomPreset(preset.id);
  }

  // unregisterCustomPreset removes a previously-registered custom preset
  // from memory (does not touch disk -- see deleteActivePreset for that).
  // If it's the currently active theme, falls back to the default theme.
  void unregisterCustomPreset(String id) {
    customPresets.remove(id);
    appThemes.remove("custom:$id");
    savedPresetIds.remove(id);
    if (_themeMode == "custom:$id") {
      switchTheme(defaultThemeName);
    }
  }

  // areaStyle returns the style override for the given area in the active
  // theme, or the default (token-based, i.e. unchanged) style if the active
  // theme doesn't customize that area.
  AreaStyle areaStyle(ThemeArea area) =>
      _fullTheme.areaStyles[area] ?? const AreaStyle();

  // buttonStyle returns the compiled ButtonStyle for one of the app's five
  // button roles (see button_style.dart) -- for the two roles Material has
  // no theme slot for, which this app's own widgets render instead.
  ButtonStyle buttonStyle(ButtonRole role) =>
      _fullTheme.buttonStyles[role] ?? const ButtonStyle();

  // areaDecoration resolves the given area's style into a concrete
  // BoxDecoration, falling back to the given SurfaceColor token. Only
  // supports a flat-color border (see AreaStyle.toBoxDecoration) -- for the
  // full solid/gradient/image border treatment, use areaContainer instead.
  BoxDecoration areaDecoration(ThemeArea area, SurfaceColor fallback) =>
      areaStyle(area)
          .toBoxDecoration(this, fallback, presetDir: _fullTheme.presetDir);

  // areaContainer wraps `child` in the given area's full background+border
  // (solid/gradient/image, independently) + padding/margin styling.
  Widget areaContainer(ThemeArea area, SurfaceColor fallback,
          {required Widget child, Color? tokenColor}) =>
      areaStyle(area).buildContainer(this, fallback,
          child: child,
          presetDir: _fullTheme.presetDir,
          tokenColor: tokenColor);

  void switchTheme(String value) async {
    // "system" has no theme of its own -- on every platform it resolves to
    // the default theme.
    var theme = appThemes[value == "system" ? defaultThemeName : value] ??
        appThemes[defaultThemeName] ??
        AppTheme.empty();
    _themeData = theme.data;
    _themeMode = value;
    _extraColors = theme.extraColors;
    _extraTextStyles = theme.extraTextStyles;
    _fullTheme = theme;
    _refreshActivePalette();
    await StorageManager.saveData(StorageManager.themeModeKey, value);
    _clearTxtStyleCache();
    _rebuildMarkdownStyleSheet();
    _rebuildEmojiPickerConfig();

    _themeLoaded = true;
    notifyListeners();
  }

  void setFontSize(double fs) async {
    _fontScale = fs;
    StorageManager.saveData(StorageManager.fontScaleKey, fs.toString());
    _clearTxtStyleCache();
    notifyListeners();
  }

  void setChatImageSize(String size) async {
    if (!appImageSizes.containsKey(size)) return;
    _chatImageSize = size;
    StorageManager.saveData(StorageManager.chatImageSizeKey, size);
    notifyListeners();
  }

  final Map<TextSize?, Map<TextColor?, TextStyle>> _txtStyleCache = {
    null: {},
    TextSize.small: {},
    TextSize.medium: {},
    TextSize.large: {},
    TextSize.huge: {}
  };

  void _clearTxtStyleCache() {
    _txtStyleCache.forEach((k, v) {
      v.clear();
    });
    _nickTextStyles.clear();
  }

  // surfaceColor returns the theme color for the given color token.
  Color surfaceColor(SurfaceColor color) {
    switch (color) {
      case SurfaceColor.primary:
        return colors.primary;
      case SurfaceColor.secondary:
        return colors.secondary;
      case SurfaceColor.tertiary:
        return colors.tertiary;
      case SurfaceColor.error:
        return colors.error;
      case SurfaceColor.primaryContainer:
        return colors.primaryContainer;
      case SurfaceColor.secondaryContainer:
        return colors.secondaryContainer;
      case SurfaceColor.tertiaryContainer:
        return colors.tertiaryContainer;
      case SurfaceColor.errorContainer:
        return colors.errorContainer;
      case SurfaceColor.surface:
        return colors.surface;
      case SurfaceColor.surfaceContainerLowest:
        return colors.surfaceContainerLowest;
      case SurfaceColor.surfaceContainerLow:
        return colors.surfaceContainerLow;
      case SurfaceColor.surfaceContainer:
        return colors.surfaceContainer;
      case SurfaceColor.surfaceContainerHigh:
        return colors.surfaceContainerHigh;
      case SurfaceColor.surfaceContainerHighest:
        return colors.surfaceContainerHighest;
      case SurfaceColor.surfaceBright:
        return colors.surfaceBright;
      case SurfaceColor.surfaceDim:
        return colors.surfaceDim;
      case SurfaceColor.inverseSurface:
        return colors.inverseSurface;
      case SurfaceColor.inversePrimary:
        return colors.inversePrimary;
      case SurfaceColor.primaryFixed:
        return colors.primaryFixed;
      case SurfaceColor.primaryFixedDim:
        return colors.primaryFixedDim;
      case SurfaceColor.secondaryFixed:
        return colors.secondaryFixed;
      case SurfaceColor.secondaryFixedDim:
        return colors.secondaryFixedDim;
      case SurfaceColor.tertiaryFixed:
        return colors.tertiaryFixed;
      case SurfaceColor.tertiaryFixedDim:
        return colors.tertiaryFixedDim;
    }
  }

  // textColor returns the theme color for the given text color token.
  Color textColor(TextColor color) {
    switch (color) {
      case TextColor.onPrimary:
        return colors.onPrimary;
      case TextColor.onSecondary:
        return colors.onSecondary;
      case TextColor.onTertiary:
        return colors.onTertiary;
      case TextColor.onError:
        return colors.onError;
      case TextColor.onPrimaryContainer:
        return colors.onPrimaryContainer;
      case TextColor.onSecondaryContainer:
        return colors.onSecondaryContainer;
      case TextColor.onTertiaryContainer:
        return colors.onTertiaryContainer;
      case TextColor.onErrorContainer:
        return colors.onErrorContainer;
      case TextColor.onSurface:
        return colors.onSurface;
      case TextColor.onSurfaceVariant:
        return colors.onSurfaceVariant;
      case TextColor.onInverseSurface:
        return colors.onInverseSurface;
      case TextColor.onPrimaryFixed:
        return colors.onPrimaryFixed;
      case TextColor.onPrimaryFixedVariant:
        return colors.onPrimaryFixedVariant;
      case TextColor.onSecondaryFixed:
        return colors.onSecondaryFixed;
      case TextColor.onSecondaryFixedVariant:
        return colors.onSecondaryFixedVariant;
      case TextColor.onTertiaryFixed:
        return colors.onTertiaryFixed;
      case TextColor.onTertiaryFixedVariant:
        return colors.onTertiaryFixedVariant;
      case TextColor.inversePrimary:
        return colors.inversePrimary;
      case TextColor.error:
        return colors.error;
      case TextColor.successOnSurface:
        return extraColors.successOnSurface;
    }
  }

  // textStyleFor returns the cached text style for a text of the given size and
  // color.
  TextStyle? textStyleFor(
      BuildContext context, TextSize? size, TextColor? color) {
    // Null size and color means no style (i.e. inherited/default style).
    if (size == null && color == null) {
      return null;
    }

    // Already cached style.
    var cached = _txtStyleCache[size]?[color];
    if (cached != null) {
      return cached;
    }

    // Null font color means default/inherited color.
    var fontColor = color != null ? textColor(color) : null;

    // Cache to reuse.
    var ts = TextStyle(fontSize: fontSize(size), color: fontColor);
    _txtStyleCache[size]?[color] = ts;
    return ts;
  }

  final Map<String, TextStyle> _nickTextStyles = {};

  // textStyleForNick returns the text style to use for the given remote user
  // nick (nick will be the same color as the avatar color).
  TextStyle textStyleForNick(String nick) {
    var res = _nickTextStyles[nick];
    if (res != null) {
      return res;
    }

    var color = colorFromNick(nick, brightness);
    res = TextStyle(color: color);
    _nickTextStyles[nick] = res;
    return res;
  }

  /// markdownGuideId is the style guide posts are read in, from the
  /// Markdown theme area.
  String get markdownGuideId => areaStyle(ThemeArea.markdown).markdownGuideId;

  /// markdownGuide is the style guide this theme renders posts with: the
  /// reader's own when they have edited one, otherwise the built-in named
  /// in the Markdown area.
  MarkdownStyleGuide get markdownGuide => areaStyle(ThemeArea.markdown)
      .markdownGuide(builtInGuideFor(markdownGuideId));

  /// markdownImageRule is [guide]'s picture rules with the Markdown area's
  /// own overrides folded over them.
  ImageRule markdownImageRule(MarkdownStyleGuide guide) =>
      areaStyle(ThemeArea.markdown).markdownImage(guide.image);

  /// markdownPaletteColor looks a palette slot up in the live palette, so a
  /// colour picked in a guide follows the palette when that is edited.
  Color? markdownPaletteColor(int index) {
    var palette = activePalette;
    return index >= 0 && index < palette.length ? palette[index] : null;
  }

  /// markdownInk turns one of a style guide's colours into a real one.
  ///
  /// A guide names a colour three ways -- a role, a palette slot, or a
  /// literal -- and which of them wins, and what the live palette currently
  /// holds, is this object's business rather than every caller's. Spelled out
  /// at each call site it was the same two arguments repeated with a fallback
  /// bolted on, and one of them getting the pair wrong would be invisible.
  Color? markdownInk(MarkdownInk ink) =>
      ink.resolve(markdownRoleColor, paletteColor: markdownPaletteColor);

  /// markdownTextStyle folds one of a guide's text rules onto [base].
  ///
  /// The companion to markdownInk, and here for the same reason: a rule
  /// needs both the role resolver and the palette resolver, and the two
  /// always travel together.
  TextStyle markdownTextStyle(TextRule rule, TextStyle base) =>
      rule.applyTo(base, markdownRoleColor, paletteColor: markdownPaletteColor);

  /// markdownRoleColor resolves the short list of colours a style guide can
  /// name against the live theme.
  ///
  /// The mapping is here rather than in the model because it is the one
  /// place that knows what the reader's theme currently is -- which is the
  /// whole reason a guide names roles instead of colours.
  Color markdownRoleColor(MarkdownRole role) => switch (role) {
        MarkdownRole.text => textColor(TextColor.onSurface),
        MarkdownRole.muted => textColor(TextColor.onSurfaceVariant),
        MarkdownRole.accent => surfaceColor(SurfaceColor.primary),
        MarkdownRole.link => surfaceColor(SurfaceColor.primary),
        MarkdownRole.quote => textColor(TextColor.onSurfaceVariant),
        MarkdownRole.quoteBar => surfaceColor(SurfaceColor.inverseSurface),
        MarkdownRole.raised => surfaceColor(SurfaceColor.surfaceContainer),
        MarkdownRole.outline => colors.outlineVariant,
      };

  /// markdownLinkStyle is [base] set as a link would be set in a post.
  ///
  /// The theme's link colour with the active style guide's Links rule folded
  /// on -- the same two steps applyGuide takes for the `a` entry of a
  /// stylesheet, offered here for the things that draw a link without going
  /// through one.
  ///
  /// The link-card plugin is the reason it exists. It draws a bare URL
  /// itself, and did so in the raw Material accent with an underline it
  /// added unconditionally -- so a written-out link and a bare URL in the
  /// same post were two different colours, and Links > Underline was obeyed
  /// by one of them and not the other.
  TextStyle markdownLinkStyle(TextStyle? base) {
    var ink = markdownRoleColor(MarkdownRole.link);
    return markdownGuide.link.applyTo(
      (base ?? const TextStyle()).copyWith(color: ink, decorationColor: ink),
      markdownRoleColor,
      paletteColor: markdownPaletteColor,
    );
  }

  MarkdownStyleSheet _mdStyleSheet = MarkdownStyleSheet();
  MarkdownStyleSheet get mdStyleSheet => _mdStyleSheet;
  void _rebuildMarkdownStyleSheet() {
    _mdStyleSheet = MarkdownStyleSheet(
      // Links, in the theme's own accent rather than flutter_markdown's
      // hard-coded Colors.blue -- which is what a link rendered as until
      // this was set, in every theme, whatever the palette said.
      //
      // decorationColor with it, so an underline drawn on a link (the style
      // guide's Links > Underline) is the colour of the link and not of the
      // paragraph the link happens to sit in.
      a: TextStyle(
          color: markdownRoleColor(MarkdownRole.link),
          decorationColor: markdownRoleColor(MarkdownRole.link)),
      // Explicit color: without it, flutter_markdown falls back to the raw
      // Material3 seed ColorScheme instead of this app's theme, which is
      // where the stray, un-themed purple tint on inline code/relayed text
      // came from.
      // Transparent, not absent: MarkdownStyleSheet.fromTheme gives `code` a
      // backgroundColor of the card colour, and that is painted behind the
      // letters themselves. Inside a code block -- which already has a
      // background of its own -- it showed as a second, darker shape folded
      // tightly around the text and broken between the lines. A TextStyle
      // field cannot be un-set by copyWith, so it is painted with nothing.
      code: extraTextStyles.monospaced.copyWith(
          color: textColor(TextColor.onSurfaceVariant),
          backgroundColor: Colors.transparent),
      codeblockDecoration:
          BoxDecoration(color: surfaceColor(SurfaceColor.surfaceContainer)),
      // A quotation is set quieter than the body on a raised panel, both
      // taken from the palette.
      //
      // It used to use the tertiary container pair, which is not a palette
      // colour at all: ColorScheme.fromSeed derives it from the seed's own
      // tonal ramp, so whatever the palette said, a quotation came out on
      // Material's stock purple. Reported as an unknown purple, and it was.
      blockquote: TextStyle(color: textColor(TextColor.onSurfaceVariant)),
      blockquoteDecoration: BoxDecoration(
          color: surfaceColor(SurfaceColor.surfaceContainerHigh),
          border: Border(
              left: BorderSide(
                  color: surfaceColor(SurfaceColor.inverseSurface), width: 2))),
    );
    // <pre> is what a fenced code block parses to, and the sheet's own map
    // sets it from the paragraph style. Code blocks are set in the code
    // face, so it is pointed at that instead.
    _mdStyleSheet.styles["pre"] = _mdStyleSheet.code;
    _mdStyleSheet.styles["embedtext"] = _mdStyleSheet.code;
  }

  late emoji_picker.Config _emojiPickerConfig;
  emoji_picker.Config get emojiPickerConfig => _emojiPickerConfig;
  void _rebuildEmojiPickerConfig() {
    _emojiPickerConfig = emoji_picker.Config(
      emojiTextStyle: TextStyle(fontFamily: emojifont),
      categoryViewConfig: emoji_picker.CategoryViewConfig(
        backgroundColor: colors.secondaryContainer,
        // outlineVariant (not outline) -- a muted, blend-in icon tint,
        // not a button border that needs to stand out.
        iconColor: colors.outlineVariant,
        iconColorSelected: colors.secondary,
        indicatorColor: colors.secondary,
      ),
      emojiViewConfig: emoji_picker.EmojiViewConfig(
        backgroundColor: colors.primaryContainer,
      ),
      searchViewConfig: emoji_picker.SearchViewConfig(
        backgroundColor: colors.secondaryContainer,
      ),
      bottomActionBarConfig: emoji_picker.BottomActionBarConfig(
        backgroundColor: colors.tertiaryContainer,
        buttonColor: colors.onSurfaceVariant,
        showBackspaceButton: false,
      ),
      skinToneConfig: emoji_picker.SkinToneConfig(
        dialogBackgroundColor: colors.secondaryContainer,
      ),
    );
  }
}
