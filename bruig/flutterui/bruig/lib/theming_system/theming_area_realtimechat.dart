import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_realtimechat.dart is the "Realtime Chat" area's own settings.
List<Widget> realtimeChatAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Auto-unmute on join",
        subtitle: "Automatically unmutes (with a snackbar notice) when "
            "joining a live session",
        value: ctx.style.autoUnmuteOnJoin,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(autoUnmuteOnJoin: v)),
      ),
      ctx.toggle(
        "Enhanced call status indicators",
        subtitle: "Pulsing mic-live indicator, clearer mute/unmute button "
            "states, and a warning chip while in a live session",
        value: ctx.style.enhancedCallIndicators,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(enhancedCallIndicators: v)),
      ),
      ctx.toggle(
        "Pre-join audio test panel",
        subtitle: "Lets you pick a mic/speaker and record+play back a test "
            "clip before joining a session",
        value: ctx.style.rtcAudioTestPanel,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(rtcAudioTestPanel: v)),
      ),
      ctx.toggle(
        "Lobby header",
        subtitle: "Icon badge, session title, and member count shown while "
            "not yet in a live session",
        value: ctx.style.rtcLobbyHero,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(rtcLobbyHero: v)),
      ),
      ctx.toggle(
        "Collapsible session info",
        subtitle: "Tucks RV/Size/Peer ID/Owner behind an expandable row "
            "instead of always showing them",
        value: ctx.style.rtcCollapsibleSessionInfo,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(rtcCollapsibleSessionInfo: v)),
      ),
      ctx.toggle(
        "Live session stage",
        subtitle: "Session timer, LIVE badge, connection-quality signal "
            "bars, speaking-aware avatar rings, and mic/speaker "
            "device panels while in a live session",
        value: ctx.style.rtcLiveStage,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(rtcLiveStage: v)),
      ),
      ctx.toggle(
        "Styled session list",
        subtitle: "Redesigned Realtime Chat session-list rows with a "
            "live-status dot and active-row highlight",
        value: ctx.style.rtcStyledSessionList,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(rtcStyledSessionList: v)),
      ),
      ctx.toggle(
        "Session list empty-state intro",
        subtitle: "Explains what Realtime Chat is and offers a \"Create your "
            "first Realtime Chat\" button when no session is active",
        value: ctx.style.rtcSessionListIntro,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(rtcSessionListIntro: v)),
      ),
    ];
