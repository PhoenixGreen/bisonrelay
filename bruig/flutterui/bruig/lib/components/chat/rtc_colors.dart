import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// rtc_colors.dart is the Realtime Chat screen's palette, worked out once from
// the active theme.
//
// The three files that draw this screen -- the session list, the active
// session and its header -- between them named ninety-six colours by hand:
// a near-black for every panel, a grey for every label, a green for live and
// a red for muted. A theme could be changed to anything at all and the page
// looked exactly the same, which is the whole of the complaint about it.
//
// Only what a state *means* is a setting of its own (see the Realtime Chat
// theme area): live, muted, and the middle ground. Everything else is a
// surface or a text colour the theme already answers for, so it is asked for
// by role here rather than picked. That is what makes the page follow the
// theme rather than merely permit it.
class RtcColors {
  /// live is a session in progress: the dot and its glow, the ring around
  /// whoever is speaking, a microphone that is on.
  final Color live;

  /// muted is the other end of that: a muted badge, a microphone that is
  /// off, the LIVE label, the weakest connection reading.
  final Color muted;

  /// warning is the state between them -- a connection that is neither good
  /// nor bad.
  final Color warning;

  /// accent is the theme's own, for the things that are merely selected
  /// rather than in any state: the active session's name, the headphones on
  /// a session being listened to.
  final Color accent;

  /// activeSessionFill is the selected row's background in the session list.
  final Color activeSessionFill;

  /// text, subtext and faintText are the screen's three levels of writing:
  /// a name, a description under it, and a label beside a value.
  final Color text;
  final Color subtext;
  final Color faintText;

  /// panel is a raised box on the page -- the live stage, the audio test,
  /// the intro's feature list -- and panelBorder is the line round it.
  final Color panel;
  final Color panelBorder;

  /// inset is a box *inside* a panel (the mic and speaker pickers), which
  /// has to read as recessed against it rather than as another panel.
  final Color inset;
  final Color insetBorder;

  /// menu is the background a dropdown opens over.
  final Color menu;

  /// idle is an indicator that is switched off: an unlit dot, a signal bar
  /// below the current strength. Quiet rather than invisible.
  final Color idle;

  /// stageAvatarRadius and stageCollapsed come from the theme area's Live
  /// stage settings.
  final double stageAvatarRadius;
  final bool stageCollapsed;

  /// sessionCornerRadius is the session row's own rounding.
  final double sessionCornerRadius;

  const RtcColors._({
    required this.live,
    required this.muted,
    required this.warning,
    required this.accent,
    required this.activeSessionFill,
    required this.text,
    required this.subtext,
    required this.faintText,
    required this.panel,
    required this.panelBorder,
    required this.inset,
    required this.insetBorder,
    required this.menu,
    required this.idle,
    required this.stageAvatarRadius,
    required this.stageCollapsed,
    required this.sessionCornerRadius,
  });

  factory RtcColors.of(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var style = theme.areaStyle(ThemeArea.realtimeChat);
    var onSurfaceVariant = theme.textColor(TextColor.onSurfaceVariant);

    return RtcColors._(
      // The built-in green stays the fallback: it is what this screen has
      // always been, and a theme that has not been asked about it should not
      // have one guessed for it.
      live: style.resolveRtcLiveColor(theme) ?? const Color(0xFF1DFF8C),
      // Unset, muted follows the theme's own error colour rather than a
      // fixed red -- every theme already has an answer for "something is
      // wrong", and this is that.
      muted: style.resolveRtcMutedColor(theme) ?? theme.colors.error,
      warning: style.resolveRtcWarningColor(theme) ?? const Color(0xFFE2B340),
      accent: theme.colors.primary,
      activeSessionFill: style.resolveRtcActiveSessionColor(theme) ??
          theme.surfaceColor(SurfaceColor.surfaceContainerHigh),
      text: theme.textColor(TextColor.onSurface),
      subtext: onSurfaceVariant,
      // Derived from the one above rather than named separately: it is the
      // same voice, quieter, and deriving it means it stays legible in a
      // light theme as well as a dark one.
      faintText: onSurfaceVariant.withValues(alpha: 0.65),
      panel: theme.surfaceColor(SurfaceColor.surfaceContainerLow),
      panelBorder: theme.colors.outlineVariant,
      inset: theme.surfaceColor(SurfaceColor.surfaceContainerLowest),
      insetBorder: theme.colors.outlineVariant,
      menu: theme.surfaceColor(SurfaceColor.surfaceContainerHigh),
      idle: onSurfaceVariant.withValues(alpha: 0.35),
      stageAvatarRadius: style.rtcStageAvatarRadius ?? 34,
      stageCollapsed: style.rtcStageCollapsed,
      sessionCornerRadius: style.rtcSessionCornerRadius ?? 12,
    );
  }

  /// tint is a status colour used as a background rather than as ink -- the
  /// disc behind a muted badge, the tile behind the lobby's headphones.
  static Color tint(Color status) => status.withValues(alpha: 0.15);
}
