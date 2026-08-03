import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/equalizer_icon.dart';
import 'package:bruig/components/inputs.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/volume_control.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/realtimechat/activertc.dart';
import 'package:bruig/screens/realtimechat/creatertc.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

class RealtimeChatTitle extends StatelessWidget {
  const RealtimeChatTitle({super.key});

  @override
  Widget build(BuildContext context) {
    var headerStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.header);
    // MainAxisSize.min so the header's Text align setting can actually
    // move this: a max-size Row fills the whole title area whatever the
    // AppBar is told to do with it, which pinned the text to the left even
    // with the setting on Center or Right.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Txt.L("Realtime Chat"),
      if (!headerStyle.hideHeaderNewSession)
        IconButton(
            onPressed: () {
              Navigator.of(context)
                  .pushNamed(CreateRealtimeChatScreen.routeName);
            },
            icon: const Icon(Icons.add_box),
            tooltip: "Create new session"),
    ]);
  }
}

class _RealtimeSessionPublisherW extends StatefulWidget {
  final ClientModel client;
  final RTDTSessionModel session;
  final RTDTLivePeerModel? peer;
  final RMRTDTSessionPublisher publisher;
  const _RealtimeSessionPublisherW(
      {required this.client,
      required this.session,
      required this.peer,
      required this.publisher});

  @override
  State<_RealtimeSessionPublisherW> createState() =>
      __RealtimeSessionPublisherWState();
}

class __RealtimeSessionPublisherWState
    extends State<_RealtimeSessionPublisherW> {
  ClientModel get client => widget.client;
  RTDTSessionModel get session => widget.session;
  RTDTLivePeerModel? get peer => widget.peer;
  RMRTDTSessionPublisher get publisher => widget.publisher;
  ChatModel? get peerChat => client.getExistingChat(publisher.publisherID);

  bool changingVolume = false;

  void update() {
    setState(() {});
  }

  void confirmKick() {
    if (peerChat == null) {
      return;
    }

    int banSeconds = 0;
    showConfirmDialog(
      context,
      title: "Confirm temporary kick",
      onConfirm: () async {
        await session.kickMember(peer?.peerID ?? 0, banSeconds);
        peerChat!.append(
            ChatEventModel(
                SynthChatEvent(
                    "Kicked ${peerChat?.nick} from live realtime session "
                    "(temp banned for $banSeconds seconds)"),
                null),
            false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Txt.L("Really kick user ${peerChat?.nick} from session?"),
          const SizedBox(height: 10),
          Row(children: [
            const Txt("Temporary ban duration (seconds): "),
            SizedBox(
                width: 75, child: intInput(onChanged: (v) => banSeconds = v)),
          ]),
        ],
      ),
    );
  }

  void confirmRemove() {
    if (peerChat == null) {
      return;
    }

    showConfirmDialog(
      context,
      title: "Confirm permanent removal?",
      onConfirm: () async {
        await session.removeMember(peerChat!.id);
        peerChat!.append(
            ChatEventModel(
                SynthChatEvent(
                    "Permanently removed ${peerChat?.nick} from live realtime session"),
                null),
            false);
      },
      content:
          "Really remove user ${peerChat?.nick} from session? This cannot be undone.",
    );
  }

  @override
  void initState() {
    super.initState();
    if (peer != null) {
      peer!.addListener(update);
    }
  }

  @override
  void didUpdateWidget(_RealtimeSessionPublisherW oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget != widget) {
      if (oldWidget.peer != null) {
        oldWidget.peer!.removeListener(update);
      }
      if (peer != null) {
        peer!.addListener(update);
      }
    }
  }

  @override
  void dispose() {
    if (peer != null) {
      peer!.removeListener(update);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context, listen: false);
    String pubNick = publisher.alias;
    var knownNick = client.getNick(publisher.publisherID);
    if (knownNick != "") pubNick = knownNick;
    var livePeer = session.livePeer(publisher.peerID);
    return Row(children: [
      if (session.inLiveSession &&
          livePeer != null &&
          livePeer.isLive &&
          !livePeer.hasSoundStream)
        SizedBox(
            width: 24,
            height: 24,
            child: Icon(Icons.mic_off_outlined, color: theme.colors.primary))
      else if (session.inLiveSession && livePeer != null && livePeer.isLive)
        InkWell(
            onTap: () => setState(() => changingVolume = !changingVolume),
            child: EqualizerIcon(isActive: livePeer.hasSound))
      else
        const SizedBox(width: 24, height: 24),
      if (session.inLiveSession &&
          livePeer != null &&
          livePeer.isLive &&
          changingVolume)
        VolumeGainControl(
            initialValue: livePeer.gain,
            onChangedDelta: (delta) async {
              await livePeer.modifyGain(delta);
            }),
      const SizedBox(width: 8),
      UserAvatarFromID(
        client,
        publisher.publisherID,
        radius: 10,
      ),
      const SizedBox(width: 5, height: 30),
      Txt.S(pubNick),
      const SizedBox(width: 5),
      if (session.inLiveSession &&
          session.isAdmin &&
          peerChat != null &&
          peer != null &&
          peer!.isLive)
        IconButton(
          onPressed: confirmKick,
          icon: const Icon(Icons.remove_circle),
          tooltip: "Temporarily kick from session",
        ),
      const SizedBox(width: 5),
      if (session.isAdmin && peerChat != null)
        IconButton(
          onPressed: confirmRemove,
          icon: const Icon(Icons.person_remove),
          tooltip: "Permanently remove from session",
        ),
    ]);
  }
}

class _RTDTSessionW extends StatefulWidget {
  final RealtimeChatModel rtc;
  final RTDTSessionModel session;
  final ClientModel client;
  const _RTDTSessionW(this.rtc, this.client, this.session);

  @override
  State<_RTDTSessionW> createState() => __RTDTSessionWState();
}

class __RTDTSessionWState extends State<_RTDTSessionW> {
  RTDTSessionModel get session => widget.session;
  ClientModel get client => widget.client;
  RealtimeChatModel get rtc => widget.rtc;
  List<RMRTDTSessionPublisher> publishers = [];
  bool isActive = false;

  void sessionUpdated() {
    setState(() {
      publishers = session.info.metadata.publishers;
    });
  }

  void activeSessionChanged() {
    var newIsActive = rtc.active.active == session;
    if (newIsActive != isActive) {
      setState(() {
        isActive = newIsActive;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    publishers = session.info.metadata.publishers;
    session.addListener(sessionUpdated);
    rtc.active.addListener(activeSessionChanged);
    isActive = rtc.active.active == session;
  }

  @override
  void didUpdateWidget(_RTDTSessionW oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != session) {
      oldWidget.session.removeListener(sessionUpdated);
      session.addListener(sessionUpdated);
      publishers = session.info.metadata.publishers;
      isActive = rtc.active.active == session;
    }
  }

  @override
  void dispose() {
    session.removeListener(sessionUpdated);
    rtc.active.removeListener(activeSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final live = session.hasHotAudio || session.inLiveSession;
    // The three things a theme decides about this row (see the Realtime
    // Chat theme area); each keeps its built-in value until set.
    var rtcStyle = ThemeNotifier.of(context).areaStyle(ThemeArea.realtimeChat);
    var radius =
        BorderRadius.circular(rtcStyle.rtcSessionCornerRadius ?? 12);
    var activeColor = rtcStyle.resolveRtcActiveSessionColor(
            ThemeNotifier.of(context)) ??
        const Color(0xFF0B0F16);
    var liveColor =
        rtcStyle.resolveRtcLiveColor(ThemeNotifier.of(context)) ??
            const Color(0xFF1DFF8C);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: isActive ? activeColor : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => !isActive ? rtc.active.active = session : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(children: [
              // Live status dot (green + glow when audio is live).
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live ? liveColor : const Color(0xFF3A403D),
                  boxShadow: live
                      ? [
                          BoxShadow(
                            color:
                                liveColor.withValues(alpha: 0.6),
                            blurRadius: 7,
                          )
                        ]
                      : null,
                ),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.info.metadata.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w500,
                            color: isActive
                                ? const Color(0xFF4D9FFF)
                                : const Color(0xFFF2F4F3),
                          )),
                      const SizedBox(height: 2),
                      Text(session.info.metadata.rv.substring(0, 10),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF5F6764))),
                    ]),
              ),
              if (session.hasHotAudio)
                Icon(Icons.mic, size: 18, color: liveColor)
              else if (session.inLiveSession)
                const Icon(Icons.headphones,
                    size: 18, color: Color(0xFF4D9FFF)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RTDTSessionsList extends StatefulWidget {
  final RealtimeChatModel rtc;
  final ClientModel client;
  const _RTDTSessionsList(this.rtc, this.client);

  @override
  State<_RTDTSessionsList> createState() => __RTDTSessionsListState();
}

class __RTDTSessionsListState extends State<_RTDTSessionsList> {
  RealtimeChatModel get rtc => widget.rtc;
  ClientModel get client => widget.client;

  void sessionsUpdated() async {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    rtc.addListener(sessionsUpdated);
    rtc.refreshSessions();
  }

  @override
  void didUpdateWidget(_RTDTSessionsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rtc != rtc) {
      oldWidget.rtc.removeListener(sessionsUpdated);
      rtc.addListener(sessionsUpdated);
    }
  }

  @override
  void dispose() {
    rtc.removeListener(sessionsUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var sessions = rtc.sessions;
    return ListView(
        shrinkWrap: true,
        children: sessions
            .map((sess) =>
                SecondarySideMenuItem(_RTDTSessionW(rtc, client, sess)))
            .toList());
  }
}

class RealtimeChatScreen extends StatefulWidget {
  static String routeName = "/realtimechat";
  final TypingEmojiSelModel typingEmoji;
  const RealtimeChatScreen(this.typingEmoji, {super.key});

  @override
  State<RealtimeChatScreen> createState() => _RealtimeChatScreenState();
}

class _RealtimeChatScreenState extends State<RealtimeChatScreen> {
  late CustomInputFocusNode inputFocusNode;

  @override
  void initState() {
    super.initState();
    inputFocusNode = CustomInputFocusNode(widget.typingEmoji);
  }

  @override
  Widget build(BuildContext context) {
    var rtc = RealtimeChatModel.of(context, listen: false);
    var client = ClientModel.of(context, listen: false);
    var audio = AudioModel.of(context, listen: false);
    return SecondarySideMenuLayout(
      width: 200,
      storageKey: "realtimeChat",
      list: _RTDTSessionsList(rtc, client),
      content: Consumer<ActiveRealTimeSessionChatModel>(
          builder: (context, activeModel, child) => activeModel.active != null
              ? ActiveRealtimeChatScreen(
                  rtc, activeModel.active!, audio, inputFocusNode)
              : _RTDTIntro(hasSessions: rtc.sessions.isNotEmpty)),
    );
  }
}

// Empty-state / intro shown when no realtime session is active. Explains
// what Realtime Chat (RTDT) actually is and urges the user to create one.
class _RTDTIntro extends StatelessWidget {
  final bool hasSessions;
  const _RTDTIntro({required this.hasSessions});

  Widget _feature(IconData ic, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF101826),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(ic, size: 16, color: const Color(0xFF4D9FFF)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF2F4F3))),
              const SizedBox(height: 1),
              Text(body,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.35, color: Color(0xFF9AA3A0))),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    // Was a hardcoded bright-green gradient with no palette field behind
    // it -- now uses the same "Accent (Buttons/Toggles)" slot the rest of
    // the app's unthemed buttons/toggles were pinned to.
    var accent =
        theme.activePreset?.accentContainer ?? const Color(0xFF1DFF8C);
    var onAccent = theme.activePreset?.onSurface ?? const Color(0xFF04130B);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                boxShadow: [
                  BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 20,
                      spreadRadius: 1),
                ],
              ),
              child: Icon(Icons.graphic_eq, size: 29, color: onAccent),
            ),
            const SizedBox(height: 16),
            const Text("Realtime Chat",
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF2F4F3))),
            const SizedBox(height: 6),
            const Text(
                "Encrypted realtime voice over Bison Relay, with live group "
                "messaging in the same session. Audio is relayed through an "
                "RTDT server but stays end-to-end encrypted along the way.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: Color(0xFF9AA3A0))),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0D0C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF1C1F1D)),
              ),
              child: Column(children: [
                _feature(
                    Icons.lock_outline,
                    "End-to-end encrypted",
                    "Audio and messages use a key only session participants "
                        "share — the relay can't read them."),
                _feature(
                    Icons.groups_outlined,
                    "Group voice + chat",
                    "Talk live with multiple peers and send messages in the "
                        "same session."),
                _feature(
                    Icons.bolt_outlined,
                    "Realtime UDP transport",
                    "RTDT (Real Time Datagram Tunneling) is built on UDP for "
                        "live audio; round-trip time is shown during calls."),
                _feature(
                    Icons.bolt,
                    "Pay-as-you-go",
                    "Senders pre-pay a small Lightning allowance for the "
                        "realtime data they send."),
              ]),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context, rootNavigator: true)
                    .pushNamed(CreateRealtimeChatScreen.routeName),
                icon: Icon(Icons.add, size: 18, color: onAccent),
                label: Text(
                    hasSessions
                        ? "Create a new Realtime Chat"
                        : "Create your first Realtime Chat",
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: onAccent)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
              ),
            ),
            if (hasSessions) ...[
              const SizedBox(height: 10),
              const Text("…or pick an existing session on the left",
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF5F6764))),
            ],
          ]),
        ),
      ),
    );
  }
}
