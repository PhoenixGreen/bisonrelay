import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/components/chat/input.dart';
import 'package:bruig/components/chat/messages.dart';
import 'package:bruig/components/chat/rtc_session_header.dart';
import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/equalizer_icon.dart';
import 'package:bruig/components/inputs.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/typing_emoji_panel.dart';
import 'package:bruig/components/volume_control.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/ln/components.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

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
        Tooltip(
            message: "User is online but not sending voice data",
            child: SizedBox(
                width: 24,
                height: 24,
                child:
                    Icon(Icons.mic_off_outlined, color: theme.colors.primary)))
      else if (session.inLiveSession && livePeer != null && livePeer.isLive)
        Tooltip(
            message: "Click to change user volume",
            child: InkWell(
                onTap: () => setState(() => changingVolume = !changingVolume),
                child: EqualizerIcon(isActive: livePeer.hasSound)))
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
      if (theme.areaStyle(ThemeArea.realtimeChat).rtcLiveStage) ...[
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: (livePeer?.hasSound ?? false)
                  ? const Color(0xFF1DFF8C)
                  : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: (livePeer?.hasSound ?? false)
                ? [
                    BoxShadow(
                        color: const Color(0xFF1DFF8C).withValues(alpha: 0.45),
                        blurRadius: 12)
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(2),
          child: UserAvatarFromID(client, publisher.publisherID, radius: 22),
        ),
        const SizedBox(width: 12, height: 48),
        Text(pubNick,
            style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF2F4F3))),
      ] else ...[
        UserAvatarFromID(
          client,
          publisher.publisherID,
          radius: 10,
        ),
        const SizedBox(width: 5, height: 30),
        Txt.S(pubNick),
      ],
      if (session.inLiveSession &&
          peer != null &&
          (peer?.bufferCount ?? 0) > 0) ...[
        const SizedBox(width: 5, height: 30),
        Txt.S(
            "buf: ${formatMsDuration(Duration(milliseconds: (peer?.bufferCount ?? 0) * 20))}")
      ],
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

class ActiveRealtimeChatScreen extends StatefulWidget {
  final RealtimeChatModel rtc;
  final RTDTSessionModel session;
  final AudioModel audio;
  final CustomInputFocusNode inputFocusNode;
  const ActiveRealtimeChatScreen(
      this.rtc, this.session, this.audio, this.inputFocusNode,
      {super.key});

  @override
  State<ActiveRealtimeChatScreen> createState() =>
      _ActiveRealtimeChatScreenState();
}

class _ActiveRealtimeChatScreenState extends State<ActiveRealtimeChatScreen> {
  RTDTSessionModel get session => widget.session;
  RealtimeChatModel get rtc => widget.rtc;
  ClientModel get client => rtc.client;
  List<RMRTDTSessionPublisher> publishers = [];
  bool showInfo = false;

  // A muted label/value row for the tucked-away session metadata (only used
  // when AreaStyle.rtcCollapsibleSessionInfo is on).
  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 92,
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF5F6764)))),
          Expanded(
              child: SelectableText(v,
                  maxLines: 1,
                  style: const TextStyle(
                      fontSize: 12.5,
                      letterSpacing: 0,
                      color: Color(0xFF9AA3A0)))),
        ]),
      );
  ChatModel get sessionChat => session.info.gc == ""
      ? session.chat
      : client.getExistingChat(session.info.gc) ?? session.chat;

  late ItemScrollController _itemScrollController;
  late ItemPositionsListener _itemPositionsListener;

  Timer? timerRefresh;

  void sessionUpdated() {
    setState(() {
      publishers = session.info.metadata.publishers;
    });
  }

  void sendMsg(String msg) async {
    var snackbar = SnackBarModel.of(context);
    try {
      if (sessionChat == session.chat) {
        // Ephemeral chat.
        await session.sendMsg(rtc.client, msg);
      } else {
        // GC chat.
        await sessionChat.sendMsg(msg);
      }
    } catch (exception) {
      snackbar.error("Unable to send message: $exception");
    }
  }

  void refreshIfLive(Timer t) async {
    if (session.inLiveSession) {
      await session.refreshFromLive();
    }
  }

  @override
  void initState() {
    super.initState();
    _itemScrollController = ItemScrollController();
    _itemPositionsListener = ItemPositionsListener.create();
    publishers = session.info.metadata.publishers;
    session.addListener(sessionUpdated);

    // Create a timer to refresh details every 1 second (bufferCount, etc).
    timerRefresh = Timer.periodic(Duration(seconds: 1), refreshIfLive);
  }

  @override
  void didUpdateWidget(ActiveRealtimeChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != session) {
      oldWidget.session.removeListener(sessionUpdated);
      session.addListener(sessionUpdated);
      publishers = session.info.metadata.publishers;
    }
  }

  @override
  void dispose() {
    session.removeListener(sessionUpdated);
    timerRefresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var ownerNick = rtc.client.getNick(session.info.metadata.owner);
    var style = ThemeNotifier.of(context).areaStyle(ThemeArea.realtimeChat);
    var live = session.inLiveSession;
    var desc = session.info.metadata.description;
    var lobbyTitle =
        desc.isNotEmpty ? desc : session.info.metadata.rv.substring(0, 10);

    return SizedBox(
        child: Column(children: [
      Box(
        // Info panel
        color: SurfaceColor.primaryContainer,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(left: 10, right: 12, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (style.rtcLobbyHero && !live) ...[
            Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  color: const Color(0xFF0E1A13),
                  border: Border.all(color: const Color(0xFF1D3B2B)),
                ),
                child: const Icon(Icons.headphones, color: Color(0xFF1DFF8C)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lobbyTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFF2F4F3))),
                      const SizedBox(height: 3),
                      Text("${publishers.length} members · not live",
                          style: const TextStyle(
                              fontSize: 12.5, color: Color(0xFF5F6764))),
                    ]),
              ),
            ]),
            const SizedBox(height: 16),
          ],
          RTCSessionHeader(rtc, session, widget.audio, client),
          const SizedBox(height: 10),
          if (session.isInstant)
            Box(
                padding: EdgeInsets.symmetric(horizontal: 10),
                margin: EdgeInsets.only(bottom: 5),
                color: SurfaceColor.tertiary,
                child: Txt.S("Instant Call - will be removed once left")),
          if (style.rtcCollapsibleSessionInfo) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => showInfo = !showInfo),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(showInfo ? Icons.expand_less : Icons.info_outline,
                      size: 16, color: const Color(0xFF9AA3A0)),
                  const SizedBox(width: 6),
                  const Text("Session info",
                      style: TextStyle(fontSize: 13, color: Color(0xFF9AA3A0))),
                ]),
              ),
            ),
            if (showInfo) ...[
              const SizedBox(height: 8),
              _infoRow("RV", session.info.metadata.rv),
              _infoRow("Size", "${session.info.metadata.size}"),
              _infoRow(
                  "Local Peer ID", session.info.localPeerID.toRadixString(16)),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  const SizedBox(
                      width: 92,
                      child: Text("Owner",
                          style: TextStyle(
                              fontSize: 12.5, color: Color(0xFF5F6764)))),
                  UserAvatarFromID(rtc.client, session.info.metadata.owner,
                      radius: 14),
                  const SizedBox(width: 6),
                  Txt.S(ownerNick),
                ]),
              ),
            ],
          ] else ...[
            Txt.S("RV: ${session.info.metadata.rv}"),
            Txt.S("Size: ${session.info.metadata.size}"),
            Txt.S("Description: ${session.info.metadata.description}"),
            Txt.S(
                "Local Peer ID: ${session.info.localPeerID.toRadixString(16)}"),
            Row(
              children: [
                const Txt.S("Owner: "),
                UserAvatarFromID(
                  rtc.client,
                  session.info.metadata.owner,
                  radius: 10,
                ),
                const SizedBox(width: 5),
                Txt.S(ownerNick)
              ],
            ),
          ],
          if (style.rtcAudioTestPanel && !live) ...[
            const SizedBox(height: 14),
            _AudioTestPanel(audio: widget.audio),
          ],
          if (!live) ...[
            const SizedBox(height: 10),
            const LNInfoSectionHeader("Session Members"),
            ...publishers.map((pub) => _RealtimeSessionPublisherW(
                client: rtc.client,
                publisher: pub,
                session: session,
                peer: session.livePeer(pub.peerID))),
          ],
        ]),
      ),
      if (live && style.rtcLiveStage)
        _LiveStage(
            session: session, rtc: rtc, client: client, audio: widget.audio),
      if (session.inLiveSession) ...[
        Expanded(
            child: Stack(children: [
          Messages(sessionChat, rtc.client, _itemScrollController,
              _itemPositionsListener),
          Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Consumer<TypingEmojiSelModel>(
                  builder: (context, typingEmoji, child) => TypingEmojiPanel(
                        model: typingEmoji,
                        focusNode: widget.inputFocusNode,
                      ))),
        ])),
        ChatInput(sendMsg, sessionChat, widget.inputFocusNode,
            allowAudio: false),
        const SizedBox(height: 5),
      ],
    ]));
  }
}

// Pre-join mic + speaker test: pick devices, record a clip, play it back.
// Gated by AreaStyle.rtcAudioTestPanel.
class _AudioTestPanel extends StatefulWidget {
  final AudioModel audio;
  const _AudioTestPanel({required this.audio});
  @override
  State<_AudioTestPanel> createState() => _AudioTestPanelState();
}

class _AudioTestPanelState extends State<_AudioTestPanel> {
  List<dynamic> _capture = [];
  List<dynamic> _playback = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final devs = await Golib.listAudioDevices();
      if (mounted) {
        setState(() {
          _capture = devs.capture;
          _playback = devs.playback;
        });
      }
    } catch (_) {}
  }

  Widget _deviceRow(IconData ic, String hint, List<dynamic> devices,
      String currentId, ValueChanged<String> onPick) {
    final hasCurrent = devices.any((d) => d.id == currentId);
    return Row(children: [
      Icon(ic, size: 18, color: const Color(0xFF9AA3A0)),
      const SizedBox(width: 10),
      Expanded(
        child: devices.isEmpty
            ? Text(hint,
                style: const TextStyle(fontSize: 13, color: Color(0xFF9AA3A0)))
            : DropdownButton<String>(
                value: hasCurrent ? currentId : null,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox(),
                dropdownColor: const Color(0xFF15171A),
                hint: Text(hint,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF9AA3A0))),
                style: const TextStyle(fontSize: 13, color: Color(0xFFF2F4F3)),
                items: devices
                    .map<DropdownMenuItem<String>>((d) => DropdownMenuItem(
                          value: d.id as String,
                          child: Text(d.name as String,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onPick(v);
                },
              ),
      ),
    ]);
  }

  Widget _testBtn(
      {required IconData icon,
      required String label,
      required Color color,
      required VoidCallback onTap,
      bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF141614),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF23262B)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = widget.audio;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D0C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1C1F1D)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tune, size: 17, color: Color(0xFF1DFF8C)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text("Test audio and microphone prior to joining",
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF2F4F3))),
          ),
        ]),
        const SizedBox(height: 12),
        _deviceRow(Icons.mic, "Default microphone", _capture,
            audio.captureDeviceId, (v) => audio.captureDeviceId = v),
        const SizedBox(height: 8),
        _deviceRow(Icons.headphones, "Default speakers", _playback,
            audio.playbackDeviceId, (v) => audio.playbackDeviceId = v),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: audio,
          builder: (context, _) {
            final recording = audio.recording;
            final playing = audio.playing;
            final hasRecord = audio.hasRecord;
            return Row(children: [
              _testBtn(
                icon: recording ? Icons.stop : Icons.fiber_manual_record,
                label: recording ? "Stop" : "Record",
                color: recording
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF1DFF8C),
                onTap: () async {
                  try {
                    if (recording) {
                      await audio.stop();
                    } else {
                      audio.recordNote();
                    }
                  } catch (_) {}
                },
              ),
              const SizedBox(width: 10),
              _testBtn(
                icon: playing ? Icons.stop : Icons.play_arrow,
                label: playing ? "Stop" : "Play back",
                color: const Color(0xFF4D9FFF),
                enabled: hasRecord && !recording,
                onTap: () async {
                  try {
                    if (playing) {
                      await audio.stop();
                    } else {
                      await audio.playbackNote();
                    }
                  } catch (_) {}
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    recording
                        ? "Recording... speak, then Stop"
                        : hasRecord
                            ? "Play back to hear yourself"
                            : "Record a clip, then play it back",
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9AA3A0))),
              ),
            ]);
          },
        ),
      ]),
    );
  }
}

// ============================ Live session stage =============================

// Rich "stage" shown while in a live session: session timer + connection
// signal, big speaking avatars (green ring reacts to BR's real sound
// detection), and an inline mic device picker + activity indicator. Gated
// by AreaStyle.rtcLiveStage.
class _LiveStage extends StatefulWidget {
  final RTDTSessionModel session;
  final RealtimeChatModel rtc;
  final ClientModel client;
  final AudioModel audio;
  const _LiveStage(
      {required this.session,
      required this.rtc,
      required this.client,
      required this.audio});

  @override
  State<_LiveStage> createState() => _LiveStageState();
}

class _LiveStageState extends State<_LiveStage>
    with SingleTickerProviderStateMixin {
  late final DateTime _start;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  List<dynamic> _captureDevices = [];
  List<dynamic> _playbackDevices = [];
  late final AnimationController _pulse;

  RTDTSessionModel get session => widget.session;

  @override
  void initState() {
    super.initState();
    _start = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_start));
    });
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 850))
      ..repeat(reverse: true);
    _loadDevices();
    session.addListener(_onSession);
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDevices() async {
    try {
      final devs = await Golib.listAudioDevices();
      if (mounted) {
        setState(() {
          _captureDevices = devs.capture;
          _playbackDevices = devs.playback;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    session.removeListener(_onSession);
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? "${h.toString().padLeft(2, '0')}:$m:$sec" : "$m:$sec";
  }

  int _barsForRTT(int rttNano) {
    if (rttNano <= 0) return 0;
    final ms = rttNano / 1e6;
    if (ms < 60) return 4;
    if (ms < 120) return 3;
    if (ms < 250) return 2;
    return 1;
  }

  bool get _localHasSound => session.localHasSound;

  @override
  Widget build(BuildContext context) {
    final pubs = session.info.metadata.publishers;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 12, 10),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0D0C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1C1F1D)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFFFF4D4D))),
          const SizedBox(width: 7),
          const Text("LIVE",
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Color(0xFFFF6B6B))),
          const SizedBox(width: 10),
          Text(_fmt(_elapsed),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF2F4F3))),
          const Spacer(),
          Consumer<RealtimeChatRTTModel>(builder: (context, rtt, _) {
            return Row(children: [
              _SignalBars(bars: _barsForRTT(rtt.lastRTTNano)),
              const SizedBox(width: 7),
              Text(rtt.lastRTTNano > 0 ? rtt.lastRTTNanoStr : "—",
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF9AA3A0))),
            ]);
          }),
        ]),
        const SizedBox(height: 22),
        Wrap(
          spacing: 30,
          runSpacing: 18,
          alignment: WrapAlignment.center,
          children: pubs.map((pub) {
            final peer = session.livePeer(pub.peerID);
            final isMe = pub.publisherID == widget.client.publicID;
            final speaking =
                isMe ? session.localHasSound : (peer?.hasSound ?? false);
            final muted = isMe
                ? !session.hasHotAudio
                : (peer != null && !peer.hasSoundStream);
            var nick = widget.client.getNick(pub.publisherID);
            if (nick == "") nick = pub.alias;
            return _StageAvatar(
                client: widget.client,
                uid: pub.publisherID,
                nick: nick,
                speaking: speaking,
                muted: muted,
                pulse: _pulse);
          }).toList(),
        ),
        if (pubs.length <= 1) ...[
          const SizedBox(height: 18),
          const Text("You're the only one here",
              style: TextStyle(fontSize: 13.5, color: Color(0xFF9AA3A0))),
          const SizedBox(height: 2),
          const Text("Invite someone from the menu to start talking",
              style: TextStyle(fontSize: 12, color: Color(0xFF5F6764))),
        ],
        const SizedBox(height: 22),
        _MicPanel(
            audio: widget.audio,
            devices: _captureDevices,
            hot: session.hasHotAudio,
            active: _localHasSound,
            pulse: _pulse),
        const SizedBox(height: 10),
        _SpeakerPanel(audio: widget.audio, devices: _playbackDevices),
      ]),
    );
  }
}

// Connection-quality bars derived from RTT.
class _SignalBars extends StatelessWidget {
  final int bars; // 0..4
  const _SignalBars({required this.bars});
  @override
  Widget build(BuildContext context) {
    const heights = [7.0, 11.0, 15.0, 19.0];
    Color colorFor(int i) {
      if (i >= bars) return const Color(0xFF2A2E2B);
      if (bars >= 3) return const Color(0xFF1DFF8C);
      if (bars == 2) return const Color(0xFFE2B340);
      return const Color(0xFFFF6B6B);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
          4,
          (i) => Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Container(
                    width: 3.5,
                    height: heights[i],
                    decoration: BoxDecoration(
                        color: colorFor(i),
                        borderRadius: BorderRadius.circular(2))),
              )),
    );
  }
}

// A large avatar with a green ring that reacts to real sound detection.
class _StageAvatar extends StatelessWidget {
  final ClientModel client;
  final String uid;
  final String nick;
  final bool speaking;
  final bool muted;
  final AnimationController pulse;
  const _StageAvatar(
      {required this.client,
      required this.uid,
      required this.nick,
      required this.speaking,
      required this.muted,
      required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedBuilder(
        animation: pulse,
        builder: (context, _) {
          final t = speaking ? pulse.value : 0.0;
          return Stack(children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: speaking
                      ? Color.lerp(
                          const Color(0xFF13D673), const Color(0xFF1DFF8C), t)!
                      : const Color(0xFF23262B),
                  width: 3,
                ),
                boxShadow: speaking
                    ? [
                        BoxShadow(
                            color: const Color(0xFF1DFF8C)
                                .withValues(alpha: 0.25 + 0.35 * t),
                            blurRadius: 14 + 12 * t,
                            spreadRadius: 1 + 2 * t),
                      ]
                    : null,
              ),
              child: UserAvatarFromID(client, uid, radius: 34),
            ),
            if (muted)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF2A1416),
                    border:
                        Border.all(color: const Color(0xFF0C0D0C), width: 2),
                  ),
                  child: const Icon(Icons.mic_off,
                      size: 14, color: Color(0xFFFF6B6B)),
                ),
              ),
          ]);
        },
      ),
      const SizedBox(height: 10),
      Text(nick,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF2F4F3))),
      const SizedBox(height: 2),
      Text(speaking ? "speaking" : (muted ? "muted" : ""),
          style: TextStyle(
              fontSize: 11.5,
              color: speaking
                  ? const Color(0xFF1DFF8C)
                  : const Color(0xFFFF6B6B))),
    ]);
  }
}

// Inline mic device picker + activity indicator (a prettier in-session
// version of the Settings mic chooser). The activity bars reflect BR's
// sound detection (active vs silent) -- BR does not expose a numeric
// loudness level.
class _MicPanel extends StatelessWidget {
  final AudioModel audio;
  final List<dynamic> devices;
  final bool hot;
  final bool active;
  final AnimationController pulse;
  const _MicPanel(
      {required this.audio,
      required this.devices,
      required this.hot,
      required this.active,
      required this.pulse});

  @override
  Widget build(BuildContext context) {
    final currentId = audio.captureDeviceId;
    final hasCurrent = devices.any((d) => d.id == currentId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E100E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F231F)),
      ),
      child: Row(children: [
        Icon(hot ? Icons.mic : Icons.mic_off,
            size: 20,
            color: hot ? const Color(0xFF1DFF8C) : const Color(0xFF5F6764)),
        const SizedBox(width: 10),
        Expanded(
          child: devices.isEmpty
              ? const Text("Default microphone",
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF9AA3A0)))
              : DropdownButton<String>(
                  value: hasCurrent ? currentId : null,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox(),
                  dropdownColor: const Color(0xFF15171A),
                  hint: const Text("Default microphone",
                      style:
                          TextStyle(fontSize: 13.5, color: Color(0xFF9AA3A0))),
                  style:
                      const TextStyle(fontSize: 13.5, color: Color(0xFFF2F4F3)),
                  items: devices
                      .map<DropdownMenuItem<String>>((d) => DropdownMenuItem(
                            value: d.id as String,
                            child: Text(d.name as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) audio.captureDeviceId = v;
                  },
                ),
        ),
        const SizedBox(width: 10),
        _MicActivityBars(active: hot && active, pulse: pulse),
      ]),
    );
  }
}

// Output (headphones/speakers) device picker.
class _SpeakerPanel extends StatelessWidget {
  final AudioModel audio;
  final List<dynamic> devices;
  const _SpeakerPanel({required this.audio, required this.devices});

  @override
  Widget build(BuildContext context) {
    final currentId = audio.playbackDeviceId;
    final hasCurrent = devices.any((d) => d.id == currentId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0E100E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F231F)),
      ),
      child: Row(children: [
        const Icon(Icons.headphones, size: 20, color: Color(0xFF9AA3A0)),
        const SizedBox(width: 10),
        Expanded(
          child: devices.isEmpty
              ? const Text("Default speakers",
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF9AA3A0)))
              : DropdownButton<String>(
                  value: hasCurrent ? currentId : null,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox(),
                  dropdownColor: const Color(0xFF15171A),
                  hint: const Text("Default speakers",
                      style:
                          TextStyle(fontSize: 13.5, color: Color(0xFF9AA3A0))),
                  style:
                      const TextStyle(fontSize: 13.5, color: Color(0xFFF2F4F3)),
                  items: devices
                      .map<DropdownMenuItem<String>>((d) => DropdownMenuItem(
                            value: d.id as String,
                            child: Text(d.name as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) audio.playbackDeviceId = v;
                  },
                ),
        ),
      ]),
    );
  }
}

// Animated bars that come alive when BR detects sound from the local mic.
class _MicActivityBars extends StatelessWidget {
  final bool active;
  final AnimationController pulse;
  const _MicActivityBars({required this.active, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = pulse.value;
        double h(int i) {
          if (!active) return 4;
          final phases = [0.0, 0.33, 0.66, 0.5, 0.15];
          final v = (1 + math.sin((t + phases[i % phases.length]) * 6.283)) / 2;
          return 4 + v * 14;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(
              5,
              (i) => Padding(
                    padding: const EdgeInsets.only(left: 2.5),
                    child: Container(
                      width: 3,
                      height: h(i),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF1DFF8C)
                            : const Color(0xFF2A2E2B),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )),
        );
      },
    );
  }
}
