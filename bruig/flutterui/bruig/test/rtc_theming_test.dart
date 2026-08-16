import 'package:bruig/components/chat/rtc_colors.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// rtc_theming_test.dart covers the Realtime Chat screen following the theme.
//
// The three files that draw it named ninety-six colours by hand -- a
// near-black for every panel, a grey for every label, a green for live -- so
// the theme could be set to anything at all and the page looked the same.
// RtcColors is where that now comes from, and this pins that it really is
// asking the theme rather than answering from a table of its own.

/// _colors resolves the screen's palette against a theme, the way the page
/// does.
Future<RtcColors> _colors(WidgetTester tester, {AreaStyle? style}) async {
  var theme = ThemeNotifier(doLoad: false);
  if (style != null) {
    theme.previewPreset(ThemePreset.seedFromDark()
        .copyWith(areas: {ThemeArea.realtimeChat: style}));
  }
  late RtcColors out;
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
    value: theme,
    child: MaterialApp(
      home: Builder(builder: (context) {
        out = RtcColors.of(context);
        return const SizedBox.shrink();
      }),
    ),
  ));
  await tester.pump();
  return out;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The whole complaint about this page: it looked the same whatever the
  // theme said. Text and panels are taken by role, so a light theme and a
  // dark one cannot come out identical.
  testWidgets("the page's own colours change with the theme", (tester) async {
    var dark = await _colors(tester);
    expect(dark.text, isNot(dark.panel),
        reason: "text has to read against the panel it sits on");
    expect(dark.subtext, isNot(dark.text),
        reason: "a description is quieter than the name above it");
    expect(dark.faintText, isNot(dark.subtext));
  });

  // Unset, muted follows the theme's own error colour rather than a fixed
  // red -- every theme already has an answer for "something is wrong".
  testWidgets("muted falls back to the theme's error colour", (tester) async {
    var theme = ThemeNotifier(doLoad: false);
    late RtcColors c;
    late Color error;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
      value: theme,
      child: MaterialApp(
        home: Builder(builder: (context) {
          c = RtcColors.of(context);
          error = ThemeNotifier.of(context).colors.error;
          return const SizedBox.shrink();
        }),
      ),
    ));
    await tester.pump();
    expect(c.muted, error);
  });

  // The three status colours are settings of their own because each means
  // something. Setting one has to be what the page then draws.
  testWidgets("each status colour set on the theme is what is used",
      (tester) async {
    const live = Color(0xFF00AAFF);
    const muted = Color(0xFFAA00FF);
    const warning = Color(0xFFFFAA00);
    var c = await _colors(tester,
        style: const AreaStyle(
            rtcLiveColor: live,
            rtcMutedColor: muted,
            rtcWarningColor: warning));
    expect(c.live, live);
    expect(c.muted, muted);
    expect(c.warning, warning);
  });

  testWidgets("the live stage settings reach the page", (tester) async {
    var plain = await _colors(tester);
    expect(plain.stageAvatarRadius, 34, reason: "the built-in size");
    expect(plain.stageCollapsed, isFalse);

    var set = await _colors(tester,
        style:
            const AreaStyle(rtcStageAvatarRadius: 48, rtcStageCollapsed: true));
    expect(set.stageAvatarRadius, 48);
    expect(set.stageCollapsed, isTrue);
  });

  testWidgets("the session row's corners follow the theme", (tester) async {
    expect((await _colors(tester)).sessionCornerRadius, 12);
    expect(
        (await _colors(tester,
                style: const AreaStyle(rtcSessionCornerRadius: 0)))
            .sessionCornerRadius,
        0);
  });

  group("the new settings survive being saved and read back", () {
    test("colours and stage settings round-trip", () {
      const style = AreaStyle(
        rtcMutedColor: Color(0xFFAA00FF),
        rtcMutedColorIndex: 3,
        rtcWarningColor: Color(0xFFFFAA00),
        rtcWarningColorIndex: 4,
        rtcStageAvatarRadius: 48,
        rtcStageCollapsed: true,
      );
      var back = AreaStyle.fromJson(style.toJson());
      expect(back.rtcMutedColor, style.rtcMutedColor);
      expect(back.rtcMutedColorIndex, 3);
      expect(back.rtcWarningColor, style.rtcWarningColor);
      expect(back.rtcWarningColorIndex, 4);
      expect(back.rtcStageAvatarRadius, 48);
      expect(back.rtcStageCollapsed, isTrue);
    });

    // A theme saved before these existed says nothing about them, and has to
    // come back as the page was.
    test("a theme that says nothing about them is unchanged", () {
      var back = AreaStyle.fromJson(const AreaStyle().toJson());
      expect(back.rtcMutedColor, isNull);
      expect(back.rtcWarningColor, isNull);
      expect(back.rtcStageAvatarRadius, isNull);
      expect(back.rtcStageCollapsed, isFalse);
    });
  });
}
