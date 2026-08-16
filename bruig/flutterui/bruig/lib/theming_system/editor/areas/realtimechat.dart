import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// realtimechat.dart is the "Realtime Chat" area's own settings.
//
// It used to hold seven toggles for the screen's own layout -- the lobby
// header, the live stage, the session-info row, the pre-join audio test, the
// styled session list and its empty-state intro. Those described how the
// page is built, not how it's themed, so they're simply part of the page
// now; what's left here is what a theme actually decides.
//
// The four colours below are the ones the page cannot take from the palette
// on its own, because they say something rather than sit somewhere: live,
// muted, and the middle ground between them. Everything else on the screen
// -- every panel, every label, every border -- is drawn from the theme's own
// surfaces and text colours, so it follows the active theme without being
// named here.
List<Widget> realtimeChatAreaEditor(AreaEditorContext ctx) => [
      ctx.slider(
          "rtcSessionCornerRadius", ctx.style.rtcSessionCornerRadius ?? 12,
          label: (v) => v <= 0
              ? "Session row corners: Square"
              : "Session row corners: ${v.toStringAsFixed(1)}",
          max: 24,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(rtcSessionCornerRadius: v))),
      ctx.colorPick(
        "Active session color",
        value: ctx.style.resolveRtcActiveSessionColor(ctx.theme),
        valueIndex: ctx.style.rtcActiveSessionColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearRtcActiveSessionColor: true,
                clearRtcActiveSessionColorIndex: true)
            : s.copyWith(
                rtcActiveSessionColor: c,
                rtcActiveSessionColorIndex: i,
                clearRtcActiveSessionColorIndex: i == null)),
      ),
      ctx.note("The selected session's row in the session list."),
      const SizedBox(height: 16),
      const Txt.M("Status colours"),
      ctx.note("The three states a session reports. They are set here rather "
          "than taken from the palette because each one means something -- "
          "green for live, red for trouble -- and a palette slot that happens "
          "to sit beside them says nothing of the kind."),
      ctx.colorPick(
        "Live",
        value: ctx.style.resolveRtcLiveColor(ctx.theme),
        valueIndex: ctx.style.rtcLiveColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(clearRtcLiveColor: true, clearRtcLiveColorIndex: true)
            : s.copyWith(
                rtcLiveColor: c,
                rtcLiveColorIndex: i,
                clearRtcLiveColorIndex: i == null)),
      ),
      ctx.note("The live dot and its glow, the ring around whoever is "
          "speaking, and a microphone that is on."),
      ctx.colorPick(
        "Muted and trouble",
        value: ctx.style.resolveRtcMutedColor(ctx.theme),
        valueIndex: ctx.style.rtcMutedColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearRtcMutedColor: true, clearRtcMutedColorIndex: true)
            : s.copyWith(
                rtcMutedColor: c,
                rtcMutedColorIndex: i,
                clearRtcMutedColorIndex: i == null)),
      ),
      ctx.note("A muted badge, a microphone that is off, the LIVE label, and "
          "the weakest connection reading."),
      ctx.colorPick(
        "Middling",
        value: ctx.style.resolveRtcWarningColor(ctx.theme),
        valueIndex: ctx.style.rtcWarningColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearRtcWarningColor: true, clearRtcWarningColorIndex: true)
            : s.copyWith(
                rtcWarningColor: c,
                rtcWarningColorIndex: i,
                clearRtcWarningColorIndex: i == null)),
      ),
      ctx.note("A connection that is neither good nor bad."),
      const SizedBox(height: 16),
      const Txt.M("Live stage"),
      ctx.note("The panel of speaking faces shown while a session is in "
          "progress."),
      ctx.slider("rtcStageAvatarRadius", ctx.style.rtcStageAvatarRadius ?? 34,
          label: (v) => "Speaker size: ${v.toStringAsFixed(0)}",
          min: 16,
          max: 64,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(rtcStageAvatarRadius: v))),
      ctx.toggle(
        "Start the stage folded away",
        subtitle: "Opens a live session on its messages, with the speakers "
            "collapsed to a single line you can open when you want it. For "
            "sessions you read more than you watch",
        value: ctx.style.rtcStageCollapsed,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(rtcStageCollapsed: v)),
      ),
      const SizedBox(height: 16),
      const Txt.M("Joining"),
      ctx.toggle(
        "Auto-unmute on join",
        subtitle: "Automatically unmutes (with a snackbar notice) when "
            "joining a live session",
        value: ctx.style.autoUnmuteOnJoin,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(autoUnmuteOnJoin: v)),
      ),
    ];
