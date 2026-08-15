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
    var corners =
        styleFor(ButtonAreaStyle(borderRadiusSides: SideValues([1, 2, 3, 4])))
            .shape!
            .resolve({});
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
        ButtonRole.tonal:
            ButtonAreaStyle(background: Color(0xFF000001), backgroundIndex: 0),
      }),
    });
    var style = preset.toAppTheme().buttonStyles[ButtonRole.tonal]!;
    expect(style.backgroundColor!.resolve({}), preset.primary);
  });

  group('text colour', () {
    ButtonStyle styleFor(ButtonRole role, ButtonAreaStyle spec) =>
        ThemePreset.seedFromDark()
            .copyWith(areas: {
              ThemeArea.buttons: AreaStyle(buttonStyles: {role: spec}),
            })
            .toAppTheme()
            .buttonStyles[role]!;

    test('untouched, each role keeps the palette text colour it names', () {
      var preset = ThemePreset.seedFromDark();
      var styles = preset.toAppTheme().buttonStyles;
      const on = <WidgetState>{};
      // The unfilled roles read against the page, the filled ones against
      // their own fill -- which is what the palette's two button text
      // colours are for.
      expect(styles[ButtonRole.plain]!.foregroundColor!.resolve(on),
          preset.buttonText1);
      expect(styles[ButtonRole.outlined]!.foregroundColor!.resolve(on),
          preset.buttonText1);
      for (var role in [
        ButtonRole.primary,
        ButtonRole.tonal,
        ButtonRole.danger
      ]) {
        expect(styles[role]!.foregroundColor!.resolve(on), preset.buttonText2,
            reason: '${role.name} does not use Text Color 2');
      }
    });

    test('a chosen colour replaces it, on the label and the icon', () {
      var style = styleFor(
          ButtonRole.primary, const ButtonAreaStyle(text: Color(0xFF00FF00)));
      expect(style.foregroundColor!.resolve({}), const Color(0xFF00FF00));
      // The icon goes with the label -- a button whose text and icon
      // disagreed about their colour would read as two things.
      expect(style.iconColor!.resolve({}), const Color(0xFF00FF00));
    });

    test('a bound slot beats the frozen colour, and still fades', () {
      var preset = ThemePreset.seedFromDark().copyWith(areas: {
        ThemeArea.buttons: const AreaStyle(buttonStyles: {
          ButtonRole.plain:
              ButtonAreaStyle(text: Color(0xFF000001), textIndex: 0),
        }),
      });
      var style = preset.toAppTheme().buttonStyles[ButtonRole.plain]!;
      expect(style.foregroundColor!.resolve({}), preset.primary);
      // Disabled fades the chosen colour, not the default it replaced.
      var off = style.foregroundColor!.resolve({WidgetState.disabled})!;
      expect(off.a, lessThan(preset.primary.a));
      expect(off.r, preset.primary.r);
    });

    test('it round-trips, and an untouched role writes nothing', () {
      var spec = const ButtonAreaStyle(text: Color(0xFF884444), textIndex: 5);
      var style = AreaStyle(buttonStyles: {ButtonRole.danger: spec});
      var back =
          AreaStyle.fromJson(style.toJson()).buttonStyles[ButtonRole.danger]!;
      expect(back.text, const Color(0xFF884444));
      expect(back.textIndex, 5);
      expect(const ButtonAreaStyle().toJson().containsKey('text'), isFalse);
      // A role with only a text colour set is still a role that has been
      // touched, so it survives the isEmpty shortcut.
      expect(spec.isEmpty, isFalse);
    });

    test('removing the bound palette entry shifts the binding', () {
      // Same rule as the other three colour bindings: an entry removed from
      // the palette must not leave this one pointing at its neighbour.
      var spec = const ButtonAreaStyle(text: Color(0xFF884444), textIndex: 5);
      expect(spec.remapPaletteIndexes(3).textIndex, 4);
      // The entry it was bound to is the one removed, so the binding goes
      // and the frozen colour is what is left.
      expect(spec.remapPaletteIndexes(5).textIndex, isNull);
      expect(spec.remapPaletteIndexes(5).text, const Color(0xFF884444));
    });
  });
}
