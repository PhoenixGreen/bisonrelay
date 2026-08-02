import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('palette v8 indexes migrate past the inserted button slots', () {
    var seed = ThemePreset.seedFromDark();
    // A v8 preset binding an area colour to navAccent (index 17 back then)
    // and an extra colour (index 24, just past the 24 fixed roles).
    var json = seed.toJson();
    json['paletteVersion'] = 8;
    json['extraPaletteColors'] = ['#FF123456'];
    json['areas'] = {
      'chat': {'solidColorIndex': 17, 'borderColorIndex': 24},
    };
    var loaded = ThemePreset.fromJson(json);
    var chat = loaded.areas[ThemeArea.chat]!;
    expect(chat.solidColorIndex, PaletteSlot.navAccent.index);
    expect(chat.borderColorIndex, PaletteSlot.values.length);
    expect(loaded.palette[chat.borderColorIndex!], const Color(0xFF123456));
  });

  test('an old preset inherits its button border/label from navAccent', () {
    var json = ThemePreset.seedFromDark().toJson();
    (json['palette'] as Map).remove(PaletteSlot.buttonBorderColor.name);
    (json['palette'] as Map).remove(PaletteSlot.buttonText1.name);
    (json['palette'] as Map)[PaletteSlot.navAccent.name] = '#FFAABBCC';
    var loaded = ThemePreset.fromJson(json);
    expect(loaded.buttonBorderColor, const Color(0xFFAABBCC));
    expect(loaded.buttonText1, const Color(0xFFAABBCC));
  });

  test('button area overrides round-trip through JSON', () {
    var style = AreaStyle(buttonStyles: {
      ButtonRole.danger: ButtonAreaStyle(
        background: const Color(0xFF884444),
        backgroundIndex: 3,
        borderWidth: 2,
        margin: 6,
        paddingSides: SideValues([1, 2, 3, 4]),
      ),
    });
    var back = AreaStyle.fromJson(style.toJson());
    var d = back.buttonStyles[ButtonRole.danger]!;
    expect(d.background, const Color(0xFF884444));
    expect(d.backgroundIndex, 3);
    expect(d.borderWidth, 2);
    expect(d.margins, const EdgeInsets.all(6));
    expect(d.paddings, const EdgeInsets.fromLTRB(1, 2, 3, 4));
    // Untouched roles aren't written at all.
    expect(style.toJson()['buttonStyles'], hasLength(1));
    expect(const AreaStyle().toJson().containsKey('buttonStyles'), isFalse);
  });

  test('an untouched role compiles to the palette defaults', () {
    var preset = ThemePreset.seedFromDark();
    var styles = preset.toAppTheme().buttonStyles;
    const enabled = <WidgetState>{};
    expect(styles[ButtonRole.danger]!.backgroundColor!.resolve(enabled),
        preset.buttonBackgroundSecondary);
    expect(styles[ButtonRole.tonal]!.backgroundColor!.resolve(enabled),
        preset.buttonBackgroundThird);
    expect(styles[ButtonRole.primary]!.backgroundColor!.resolve(enabled),
        preset.accentContainer);
    // The two unfilled roles pin transparent rather than leaving the
    // widget's own default -- ElevatedButton's is a solid
    // surfaceContainerLow, which would give every plain ElevatedButton in
    // the app a pill this role is specified not to have.
    expect(styles[ButtonRole.plain]!.backgroundColor!.resolve(enabled),
        Colors.transparent);
    expect(styles[ButtonRole.outlined]!.backgroundColor!.resolve(enabled),
        Colors.transparent);
    // And nothing casts a shadow.
    for (var role in ButtonRole.values) {
      expect(styles[role]!.elevation!.resolve(enabled), 0);
    }
    expect(styles[ButtonRole.outlined]!.side!.resolve(enabled)!.color,
        preset.buttonBorderColor);
    expect(styles[ButtonRole.plain]!.side, isNull);
    // No margin set, so no backgroundBuilder takeover.
    expect(styles[ButtonRole.primary]!.backgroundBuilder, isNull);
  });

  test('a disabled button still fades', () {
    var preset = ThemePreset.seedFromDark();
    var styles = preset.toAppTheme().buttonStyles;
    const off = {WidgetState.disabled};
    for (var role in ButtonRole.values) {
      var s = styles[role]!;
      expect(s.foregroundColor!.resolve(off)!.a,
          lessThan(s.foregroundColor!.resolve({})!.a),
          reason: '${role.name} label does not fade when disabled');
      // A transparent fill has nothing to fade, so only the filled roles
      // are checked here.
      var fill = s.backgroundColor!.resolve({})!;
      if (fill.a > 0) {
        expect(s.backgroundColor!.resolve(off)!.a, lessThan(fill.a),
            reason: '${role.name} fill does not fade when disabled');
      }
    }
    expect(styles[ButtonRole.outlined]!.side!.resolve(off)!.color.a,
        lessThan(styles[ButtonRole.outlined]!.side!.resolve({})!.color.a));
  });

  test('border radius replaces the pill shape, and only when set', () {
    ButtonStyle styleFor(ButtonAreaStyle spec) => ThemePreset.seedFromDark()
        .copyWith(areas: {
          ThemeArea.buttons: AreaStyle(buttonStyles: {ButtonRole.plain: spec}),
        })
        .toAppTheme()
        .buttonStyles[ButtonRole.plain]!;

    // Untouched: no shape at all, so the widget keeps its own stadium (and
    // raisedButtonStyle's wider login pill survives the merge).
    expect(styleFor(const ButtonAreaStyle()).shape, isNull);

    expect(styleFor(const ButtonAreaStyle(borderRadius: 6)).shape!.resolve({}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)));

    // Split per corner.
    var corners = styleFor(ButtonAreaStyle(
        borderRadiusSides: SideValues([1, 2, 3, 4]))).shape!.resolve({});
    expect(
        corners,
        const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
          topLeft: Radius.circular(1),
          topRight: Radius.circular(2),
          bottomRight: Radius.circular(3),
          bottomLeft: Radius.circular(4),
        )));

    // A radius set alongside a margin reaches the builder's own pill too.
    expect(
        styleFor(const ButtonAreaStyle(borderRadius: 6, margin: 4))
            .backgroundBuilder,
        isNotNull);
  });

  test('a margin moves the fill off the Material and into the builder', () {
    var preset = ThemePreset.seedFromDark().copyWith(areas: {
      ThemeArea.buttons: const AreaStyle(buttonStyles: {
        ButtonRole.danger: ButtonAreaStyle(margin: 8),
      }),
    });
    var style = preset.toAppTheme().buttonStyles[ButtonRole.danger]!;
    expect(style.backgroundColor!.resolve({}), Colors.transparent);
    expect(style.overlayColor!.resolve({}), Colors.transparent);
    expect(style.backgroundBuilder, isNotNull);
  });

  test('a bound slot beats the frozen colour', () {
    var preset = ThemePreset.seedFromDark().copyWith(areas: {
      ThemeArea.buttons: const AreaStyle(buttonStyles: {
        // Stale snapshot, live binding to Master Background.
        ButtonRole.tonal: ButtonAreaStyle(
            background: Color(0xFF000001), backgroundIndex: 0),
      }),
    });
    var style = preset.toAppTheme().buttonStyles[ButtonRole.tonal]!;
    expect(style.backgroundColor!.resolve({}), preset.primary);
  });
}
