# theming_system

User-editable themes for bruig: a **ThemePreset** (a named palette plus a set
of per-area overrides) compiles into an **AppTheme** — the same shape the
built-in dark/light themes already have — so a custom theme renders through
the pipeline the rest of the app already uses. Nothing here changes how an
untouched app looks: every setting defaults to what the widget rendered
before the feature existed.

## Layout

Three barrel files sit at the root. **Everything outside this folder imports
one of those three**, never a file underneath them.

| Barrel | Layer | Imported by |
| --- | --- | --- |
| `theme_manager.dart` | runtime — read the active theme | ~75 widget files |
| `theme_preset.dart` | model — the editable data | ~29 files |
| `theme_editor.dart` | editor — the Settings > Appearance UI | `screens/settings.dart` |

```
theming_system/
  theme_manager.dart          barrel over runtime/
  theme_preset.dart           barrel over model/
  theme_editor.dart           barrel over editor/ (+ the whole-preset actions)

  model/                      no dependency on the editor; one on the runtime
    theme_area.dart             ThemeArea: which region of the app
    area_options.dart           the per-area multiple-choice settings
    area_fill.dart              how a background/border layer is painted
    area_sides.dart             SideValues: a spacing setting split per side
    area_style.dart             AreaStyle: one area's overrides + its JSON
    area_style_render.dart      AreaStyle's rendering half
    bubble_shape.dart           chat bubble corners as a ShapeBorder
    button_style.dart           ButtonRole + compiling a ButtonStyle
    markdown_style.dart         a post's style guide: the vocabulary
    markdown_guides.dart        the guides that ship with the app
    markdown_style_render.dart  a guide -> MarkdownStyleSheet
    color_palette.dart          PaletteSlot: the fixed colour roles
    palette_library.dart        ColorPalette + the built-in palettes
    color_contrast.dart         WCAG luminance/contrast maths
    color_hex.dart              the shared #AARRGGBB codec
    preset.dart                 ThemePreset + its JSON + the two seeds
    preset_theme.dart           ThemePreset -> AppTheme
    preset_migrations.dart      pure back-compat; skippable on first read

  runtime/
    theme_tokens.dart           TextSize/TextColor/SurfaceColor + Inter themes
    app_theme.dart              AppTheme, and the built-in dark/light entries
    theme_notifier.dart         owns the active theme; resolves tokens

  storage/
    theme_preset_storage.dart   presets as <appdata>/themes/<id>/
    palette_library_storage.dart palettes as <appdata>/palettes/<id>.json

  editor/                       Settings > Appearance only
    color_palette_section.dart  the "Color Palette" section
    palette_color_dropdown.dart the palette-slot colour picker
    areas_section.dart          the "Theme Areas" section
    area_editor_context.dart    the API each per-area file is handed
    editor_controls.dart        the shared slider/row/caption widgets
    menus_section.dart          the "Menu" section
    areas/<name>.dart           one file per area's own settings
```

## Reading it in order

1. `model/theme_area.dart` — the twenty regions a theme can address.
2. `model/color_palette.dart` — the thirty colour roles a theme carries.
3. `model/preset.dart` — one whole theme, and what it seeds from.
4. `model/preset_theme.dart` — how that becomes a Material `ThemeData`.
5. `model/area_style.dart` + `area_style_render.dart` — one area's overrides,
   and how they paint.
6. `runtime/theme_notifier.dart` — what a widget actually talks to.
7. `editor/` — the UI, which adds no behaviour of its own.

`model/preset_migrations.dart` can be skipped entirely on a first pass: it
only runs for a preset written by an older build.

## Adding a setting

Add the field to `AreaStyle` (constructor, `copyWith`, `toJson`, `fromJson`),
then a control for it in that area's `editor/areas/<name>.dart` built through
`AreaEditorContext` — `ctx.toggle` / `choice` / `colorPick` / `slider` /
`spacing` / `note` — never a raw `SwitchListTile`/`DropdownButton`/`Slider`.
That is what keeps every area's settings looking and behaving alike.

If the addition reorders `PaletteSlot`, bump `paletteVersion` in
`ThemePreset.toJson` and add the previous order to `preset_migrations.dart`:
an `AreaStyle` binds a colour by its raw index into the palette, so inserting
a slot renumbers every binding past it.

## Tests

- `test/palette_contrast_test.dart` — every shipped palette through the real
  apply path, asserting WCAG contrast for each text/background pair.
- `test/buttons_theming_test.dart` — the five button roles compile correctly,
  and palette indexes migrate across the version bump.
- `test/mobile_nav_test.dart` — the mobile navigation list resolves against
  the menu rather than the saved list.
