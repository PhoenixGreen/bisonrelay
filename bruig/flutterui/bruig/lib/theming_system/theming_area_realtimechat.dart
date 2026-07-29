import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_realtimechat.dart is the "Realtime Chat" area's own settings.
//
// It used to hold seven toggles for the screen's own layout -- the lobby
// header, the live stage, the session-info row, the pre-join audio test, the
// styled session list and its empty-state intro. Those described how the
// page is built, not how it's themed, so they're simply part of the page
// now; what's left here is what a theme actually decides.
// The slider below opens with a plain label carrying no padding of its
// own, unlike the toggles and dropdowns other areas start with, so it needs
// explicit space off the area picker above it.
List<Widget> realtimeChatAreaEditor(AreaEditorContext ctx) => [
      const SizedBox(height: 20),
      ctx.slider("rtcSessionCornerRadius", ctx.style.rtcSessionCornerRadius ?? 12,
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
      ctx.colorPick(
        "Live indicator color",
        value: ctx.style.resolveRtcLiveColor(ctx.theme),
        valueIndex: ctx.style.rtcLiveColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearRtcLiveColor: true, clearRtcLiveColorIndex: true)
            : s.copyWith(
                rtcLiveColor: c,
                rtcLiveColorIndex: i,
                clearRtcLiveColorIndex: i == null)),
      ),
      ctx.note("The live dot and its glow on a session that's in progress."),
      const SizedBox(height: 8),
      ctx.toggle(
        "Auto-unmute on join",
        subtitle: "Automatically unmutes (with a snackbar notice) when "
            "joining a live session",
        value: ctx.style.autoUnmuteOnJoin,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(autoUnmuteOnJoin: v)),
      ),
    ];
