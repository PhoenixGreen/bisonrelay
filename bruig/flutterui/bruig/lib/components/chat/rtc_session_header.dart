import 'dart:io';
import 'dart:async';

import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/context_menu.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/realtimechat/invitetortc.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RTCSessionHeader extends StatefulWidget {
  final RealtimeChatModel rtc;
  final RTDTSessionModel session;
  final AudioModel audio;
  final ClientModel client;
  const RTCSessionHeader(this.rtc, this.session, this.audio, this.client,
      {super.key});

  @override
  State<RTCSessionHeader> createState() => _RTCSessionHeaderState();
}

class _RTCSessionHeaderState extends State<RTCSessionHeader> {
  RTDTSessionModel get session => widget.session;
  RealtimeChatModel get rtc => widget.rtc;
  AudioModel get audio => widget.audio;
  ClientModel get client => widget.client;

  void leaveLiveSession() async {
    try {
      await rtc.leaveLiveSession(session);
      setState(() {
        if (session.isInstant) {
          // Leave instant 1v1 session
          var cm = client.getExistingChat(session.info.metadata.owner);
          cm?.finishInstantCall();
        }
      });
    } catch (exception) {
      showErrorSnackbar(this, "Unable to leave session: $exception");
    }
  }

  void joinLiveSession() async {
    try {
      await rtc.joinLiveSession(session);
      if (ThemeNotifier.of(context, listen: false)
          .areaStyle(ThemeArea.realtimeChat)
          .autoUnmuteOnJoin) {
        // Auto-unmute on join so the user can talk immediately, but make
        // it unmistakable that their mic is now live.
        try {
          if (!session.hasHotAudio) {
            await rtc.switchHotAudio(session);
          }
        } catch (_) {}
        if (mounted) {
          showSuccessSnackbar(this,
              "You're live — your mic is on. Tap the green button to mute.");
        }
      }
    } catch (exception) {
      showErrorSnackbar(this, "Unable to join session: $exception");
    }
  }

  void makeAudioHot() async {
    try {
      await rtc.switchHotAudio(session);
    } catch (exception) {
      showErrorSnackbar(this, "Unable to make audio hot: $exception");
    }
  }

  void disableHotAudio() async {
    try {
      await rtc.disableHotAudio();
    } catch (exception) {
      showErrorSnackbar(this, "Unable to disable hot audio: $exception");
    }
  }

  void doExitSess() async {
    try {
      await rtc.exitSession(session.sessionRV);

      setState(() {
        if (session.isInstant) {
          // Leave instant 1v1 session
          var cm = client.getExistingChat(session.info.metadata.owner);
          cm?.finishInstantCall();
        }
      });
      showSuccessSnackbar(this, "Exited session ${session.sessionShortRV}");
    } catch (exception) {
      showErrorSnackbar(this, "Unable to exit session: $exception");
    }
  }

  void confirmExitSess() {
    showConfirmDialog(context,
        title: "Confirm exit session?",
        content:
            "Really exit this realtime chat session? You can only come back if invited again.",
        onConfirm: doExitSess);
  }

  void doDissolveSess() async {
    try {
      await rtc.dissolveSession(session.sessionRV);
      setState(() {
        if (session.isInstant) {
          for (var m in session.info.members) {
            var cm = client.getExistingChat(m.uid);
            cm?.finishInstantCall();
          }
        }
      });
      showSuccessSnackbar(this, "Dissolved session ${session.sessionShortRV}");
    } catch (exception) {
      showErrorSnackbar(this, "Unable to dissolve session: $exception");
    }
  }

  void confirmDissolveSess() {
    showConfirmDialog(context,
        title: "Confirm dissolve session?",
        content:
            "Really dissolve this realtime chat session? The session cannot be recreated.",
        onConfirm: doDissolveSess);
  }

  void doRotateSessCookies() async {
    try {
      await session.rotateCookies();
      showSuccessSnackbar(
          this, "Rotate session ${session.sessionShortRV} cookies");
    } catch (exception) {
      showErrorSnackbar(this, "Unable to rotate session cookies: $exception");
    }
  }

  void rotateSessCookies() {
    showConfirmDialog(context,
        title: "Rotate session cookies?",
        content:
            "This will prevent any members that were kicked from rejoining. In rare cases, it may disrupt live peers.",
        onConfirm: doRotateSessCookies);
  }

  void sessionUpdated() {
    setState(() {});
  }

  void toggleAndroidSpeaker() async {
    if (audio.playbackDeviceId == audio.androidEarpieceDeviceID) {
      if (audio.androidPrevPlaybackDeviceID != "") {
        audio.playbackDeviceId = audio.androidPrevPlaybackDeviceID;
      } else {
        audio.playbackDeviceId = audio.androidSpeakerDeviceID;
      }
    } else if (audio.playbackDeviceId == audio.androidPrevPlaybackDeviceID) {
      audio.playbackDeviceId = audio.androidSpeakerDeviceID;
    } else {
      audio.playbackDeviceId = audio.androidEarpieceDeviceID;
    }
    setState(() {});
  }

  void refreshIfLive(Timer t) async {
    if (session.inLiveSession) {
      await session.refreshFromLive();
    }
  }

  @override
  void initState() {
    super.initState();
    session.addListener(sessionUpdated);
  }

  @override
  void didUpdateWidget(RTCSessionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != session) {
      oldWidget.session.removeListener(sessionUpdated);
      session.addListener(sessionUpdated);
    }
  }

  @override
  void dispose() {
    session.removeListener(sessionUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var isSmallScreen = checkIsScreenSmall(context);

    // Helper to show an icon button or elevated button depending on screen size.
    Widget button(IconData icon, String label, VoidCallback? onPressed,
        {ButtonStyle? style}) {
      if (isSmallScreen) {
        return ElevatedButton(
            onPressed: onPressed, style: style, child: Icon(icon));
      } else {
        return ElevatedButton.icon(
            icon: Icon(icon),
            label: Txt(label),
            onPressed: onPressed,
            style: style);
      }
    }

    return Row(children: [
      Expanded(
          child: Wrap(
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
            if (session.inLiveSession)
              button(Icons.keyboard_return, "Leave Live Session",
                  !session.leavingLiveSession ? leaveLiveSession : null)
            else
              ElevatedButton.icon(
                  icon: const Icon(Icons.join_right),
                  label: const Txt("Join Live Session"),
                  onPressed:
                      !session.joiningLiveSession ? joinLiveSession : null),
            SizedBox(width: isSmallScreen ? 5 : 20),
            if (session.inLiveSession && !session.hasHotAudio)
              ElevatedButton.icon(
                  icon: const Icon(Icons.mic_off, size: 18),
                  label: isSmallScreen
                      ? const SizedBox.shrink()
                      : const Txt("Unmute"),
                  onPressed: makeAudioHot,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A2326),
                      foregroundColor: const Color(0xFFFF6B6B),
                      side: const BorderSide(color: Color(0xFF5A2E33)))),
            if (session.hasHotAudio)
              _MicLiveIndicator(onTap: disableHotAudio, small: isSmallScreen),
            if (Platform.isAndroid &&
                audio.androidFoundPlaybackDevices &&
                session.inLiveSession) ...[
              SizedBox(width: isSmallScreen ? 5 : 20),
              button(
                  audio.playbackDeviceId == audio.androidSpeakerDeviceID
                      ? Icons.speaker
                      : Icons.volume_up,
                  "",
                  toggleAndroidSpeaker),
            ],
            if (session.inLiveSession) ...[
              const SizedBox(width: 10),
              Consumer<RealtimeChatRTTModel>(
                  builder: (context, rtt, child) => rtt.lastRTTNano > 0
                      ? Txt.S("RTT ${rtt.lastRTTNanoStr}")
                      : const Empty())
            ],
            if (session.inLiveSession) ...[
              SizedBox(width: isSmallScreen ? 8 : 16),
              Tooltip(
                message: "Leave the live session before closing Bison Relay. "
                    "Shutting down mid-session can disrupt your Lightning "
                    "Network channels.",
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2410),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF5A4A1E)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: Color(0xFFE0B33A)),
                    if (!isSmallScreen) ...[
                      const SizedBox(width: 7),
                      const Text("Leave session before closing BR",
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFE0B33A),
                              fontWeight: FontWeight.w500)),
                    ],
                  ]),
                ),
              ),
            ],
          ])),
      ContextMenu(
        handleItemTap: (v) {
          switch (v) {
            case "gotosess":
              rtc.active.active = session;
              Navigator.of(context).pushNamed(RealtimeChatScreen.routeName);
              break;
            case "invite":
              Navigator.of(context, rootNavigator: true).pushNamed(
                  InviteToRealtimeChatScreen.routeName,
                  arguments: session);
              break;
            case "exit":
              confirmExitSess();
              break;
            case "dissolve":
              confirmDissolveSess();
              break;
            case "rotcookies":
              rotateSessCookies();
            case null:
              break;
            default:
              showErrorSnackbar(this, "Unknown key in menu: '$v'");
          }
        },
        items: [
          if (session.isAdmin)
            const PopupMenuItem(
                value: "invite", child: Text("Invite to Session")),
          if (!session.isAdmin)
            const PopupMenuItem(
                value: "exit", child: Text("Permanently exit Session")),
          if (session.isAdmin)
            const PopupMenuItem(
                value: "rotcookies", child: Text("Rotate Cookies")),
          if (session.isAdmin)
            const PopupMenuItem(
                value: "dissolve", child: Text("Dissolve Session")),
        ],
        child: const Icon(Icons.menu),
      ),
    ]);
  }
}

// Prominent, pulsing indicator shown while the local mic is hot, when
// live. Makes it obvious the user is
// live/transmitting. Tapping it mutes (disables hot audio).
class _MicLiveIndicator extends StatefulWidget {
  final VoidCallback onTap;
  final bool small;
  const _MicLiveIndicator({required this.onTap, required this.small});

  @override
  State<_MicLiveIndicator> createState() => _MicLiveIndicatorState();
}

class _MicLiveIndicatorState extends State<_MicLiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: "Your mic is live — tap to mute",
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value; // 0..1
            return Container(
              padding: EdgeInsets.symmetric(
                  horizontal: widget.small ? 12 : 16, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF13D673),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1DFF8C)
                        .withValues(alpha: 0.30 + 0.35 * t),
                    blurRadius: 8 + 14 * t,
                    spreadRadius: 1 + 2 * t,
                  ),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(const Color(0xFF04130B),
                        const Color(0xFFFFFFFF), 0.4 + 0.6 * t),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.mic, size: 18, color: Color(0xFF04130B)),
                if (!widget.small) ...[
                  const SizedBox(width: 6),
                  const Text("Click to mute",
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF04130B))),
                ],
              ]),
            );
          },
        ),
      ),
    );
  }
}
