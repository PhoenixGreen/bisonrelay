import 'dart:async';
import 'dart:collection';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chat/new_gc_screen.dart';
import 'package:bruig/screens/address_book_screen.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/screens/contacts_msg_times.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/user_context_menu.dart';
import 'package:bruig/components/gc_context_menu.dart';
import 'package:bruig/components/chat/types.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:file_picker/file_picker.dart';

// --- Chat list preview redesign tokens (AreaStyle.chatListDesignEnabled/
// showChatListLastMessage). ---
const _clpBlue = Color(0xFF4D9FFF); // you / unread / search
const _clpNickColor = Color(0xFFE6EAE8);
const _clpPreviewMuted = Color(0xFF9AA3A0);
const _clpPreviewBright = Color(0xFFCED4D2);

class _ChatHeadingW extends StatefulWidget {
  final ChatModel chat;
  final ClientModel client;
  final MakeActiveCB makeActive;
  final ShowSubMenuCB showSubMenu;
  final bool isActiveRTC;

  const _ChatHeadingW(
    this.chat,
    this.client,
    this.makeActive,
    this.showSubMenu,
    this.isActiveRTC,
  );

  @override
  State<_ChatHeadingW> createState() => _ChatHeadingWState();
}

class _ChatHeadingWState extends State<_ChatHeadingW> {
  ChatModel get chat => widget.chat;
  ClientModel get client => widget.client;
  bool get isActiveRTC => widget.isActiveRTC;

  void chatUpdated() => setState(() {});

  @override
  void initState() {
    chat.addListener(chatUpdated);
    super.initState();
  }

  @override
  void didUpdateWidget(_ChatHeadingW oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.chat.removeListener(chatUpdated);
    chat.addListener(chatUpdated);
  }

  @override
  void dispose() {
    chat.removeListener(chatUpdated);
    super.dispose();
  }

  // Replace --embed[...]-- markers with a clean label based on their type,
  // so previews show "Audio note" / "Image" instead of raw embed markup.
  String _cleanEmbeds(String src) {
    return src.replaceAllMapped(RegExp(r'--embed\[(.*?)\]--'), (m) {
      final attrs = m.group(1) ?? '';
      final type = RegExp(r'type=([^,\]]+)').firstMatch(attrs)?.group(1) ?? '';
      if (type.startsWith('image/')) return 'Image';
      if (type.startsWith('audio/')) return 'Audio note';
      if (type.startsWith('video/')) return 'Video';
      return 'File';
    });
  }

  // Reduce markdown to plain text for the one-line preview: drop blockquote
  // markers, bold/italic/strike/code punctuation, link syntax and headers.
  String _stripMarkdown(String src) {
    var s = src;
    s = s.replaceAll(RegExp(r'^\s*>+\s?', multiLine: true), '');
    s = s.replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    s = s.replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[*_~`]'), '');
    return s;
  }

  // Cheap last-message preview: first loaded message event's text. Blank
  // for chats whose history isn't loaded this session. Prefix "You: " for
  // your own messages; in group chats, prefix the sender's nick.
  String? _lastMsgPreview() {
    final draft = chat.workingMsg.trim();
    if (draft.isNotEmpty) return "Draft: ${draft.replaceAll('\n', ' ')}";
    for (final e in chat.msgs) {
      if (e.isMessage) {
        final t = _stripMarkdown(_cleanEmbeds(e.event.msg))
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (t.isEmpty) continue;
        if (e.source == null) return "You: $t";
        if (chat.isGC) {
          final who = e.source!.nick;
          if (who.isNotEmpty) return "$who: $t";
        }
        return t;
      }
    }
    return null;
  }

  // Relative time of the last loaded message: HH:MM if today, else 3d / 2w
  // / date.
  String _lastMsgTime() {
    for (final e in chat.msgs) {
      if (!e.isMessage) continue;
      if (e.event.msg.trim().isEmpty) continue;
      final ev = e.event;
      int raw;
      if (ev is PM) {
        raw = ev.timestamp;
      } else if (ev is GCMsg) {
        raw = ev.timestamp;
      } else {
        continue;
      }
      final ms = e.source?.nick == null ? raw : raw * 1000;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms);
      final diff = DateTime.now().difference(dt);
      if (diff.inHours < 24) {
        return "${dt.hour.toString().padLeft(2, '0')}:"
            "${dt.minute.toString().padLeft(2, '0')}";
      }
      final days = diff.inDays;
      if (days < 7) return "${days}d";
      if (days < 28) return "${(days / 7).floor()}w";
      return "${dt.month}/${dt.day}";
    }
    return "";
  }

  // _shade lightens (positive) or darkens (negative) a color by a fixed
  // step of HSL lightness. The chat-list design derives every one of its
  // row treatments from a single background color this way, so picking a
  // new background re-shades the hover glow, the top hairline and the
  // selected row's fill along with it, instead of those staying pinned to
  // the near-blacks the design was originally drawn against.
  static Color _shade(Color base, double delta) {
    var hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
  }

  // Rounded card w/ soft glow (inactive) or an accent-colored selected-left-
  // edge + glow (active). Only used when chatListDesignEnabled is on --
  // otherwise the tile keeps its plain ListTile selected/tileColor styling.
  //
  // The deltas below reproduce the original design's own relationships to
  // its background (0xFF171717): the hover/ambient glow sits about 5% of
  // lightness above it, its far edge ~3.5% below, the top hairline ~9%
  // above, and a selected row's fill ~3% below.
  Widget _wrapSelected(
      bool isActive,
      double radius,
      Color accent,
      double glowIntensity,
      bool topHighlight,
      Color background,
      Color selectedBackground,
      Widget tile) {
    // ListTile.tileColor/selectedTileColor need a nearby Material ancestor
    // to paint into and to render ink splashes -- the ClipRRect below
    // otherwise leaves them without one. MaterialType.transparency paints
    // nothing itself, so the surrounding Container's decoration still
    // shows through.
    tile = Material(type: MaterialType.transparency, child: tile);
    if (!isActive) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: topHighlight ? null : background,
          gradient: topHighlight
              ? RadialGradient(
                  center: const Alignment(-0.76, -1.2),
                  radius: 1.2,
                  colors: [
                    _shade(background, 0.05),
                    _shade(background, -0.035),
                  ],
                  stops: const [0.0, 0.52],
                )
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              tile,
              if (topHighlight)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child:
                        Container(height: 1, color: _shade(background, 0.09)),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // Full opacity: this is the selected row's accent edge, and the
        // user picked an exact color for it. It used to be painted at 55%,
        // which blended it into whatever was behind -- a pure white accent
        // came out light grey, and every other accent came out a muted
        // version of the swatch shown in the palette. The glow below stays
        // translucent, since a glow is meant to fall off.
        color: accent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glowIntensity <= 0
            ? const []
            : [
                BoxShadow(
                  color: accent.withValues(
                      alpha: (0.15 * glowIntensity).clamp(0, 1)),
                  blurRadius: 10 * glowIntensity,
                  spreadRadius: 0,
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 3),
        child: ClipRRect(
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(radius > 3 ? radius - 3 : 0),
            right: Radius.circular(radius),
          ),
          child: Container(
            color: selectedBackground,
            child: tile,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var chatStyle = theme.areaStyle(ThemeArea.chat);
    var showLastMessage = chatStyle.showChatListLastMessage;
    var chatListDesign = chatStyle.chatListDesignEnabled;
    var cornerRadius = chatStyle.chatListCornerRadius ?? 14;
    var accentColor = chatStyle.resolveChatListAccentColor(theme) ??
        theme.activePreset?.sidebarAccent ??
        _clpBlue;
    // Defaults to the palette's "Content Background" so the chat rows sit
    // on the same color as the content area beside them, rather than the
    // near-black the design was originally drawn against -- which is still
    // the fallback for the built-in themes, which have no palette to read.
    // Every other shade in the design derives from this (see _shade).
    var backgroundColor = chatStyle.resolveChatListBackgroundColor(theme) ??
        theme.activePreset?.contentBackground ??
        const Color(0xFF171717);
    // The selected row's fill: its own setting when one is picked, else the
    // palette's "Speech Background (Send)" -- the same color the selected
    // chat's own outgoing bubbles use, so the list and the conversation
    // agree on what "this chat" looks like. Falls back to the design's own
    // slightly-darker shade for the built-in themes.
    // Null for the built-in dark/light themes, which have no palette to
    // read: they keep Material's own selectedTileColor from the app theme
    // (a distinctly lighter grey), which is what the app has always shown
    // when no preset is active.
    var selectedBackgroundColor =
        chatStyle.resolveChatListSelectedColor(theme) ??
            theme.activePreset?.speechBackgroundSent;
    var glowIntensity = chatStyle.chatListGlowIntensity ?? 1.0;
    var topHighlight = chatStyle.chatListTopHighlight;
    var isActive = chat.active;
    var hasUnread = chat.unreadMsgCount > 0 || chat.unreadEventCount > 0;

    // Show 1k+ if unread cound goes about 1000
    var unreadCount = chat.unreadMsgCount > 1000 ? "1k+" : chat.unreadMsgCount;

    Widget unreadIndicator;
    if (chat.unreadMsgCount > 0) {
      // Show unread message count.
      unreadIndicator = Container(
        margin: const EdgeInsets.all(1),
        child: CircleAvatar(
          radius: 10,
          backgroundColor: chatListDesign ? accentColor : null,
          child: Text(
            "$unreadCount",
            style: chatListDesign
                ? const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF07101D),
                  )
                : null,
          ),
        ),
      );
    } else if (chat.unreadEventCount > 0) {
      // Show only a dot indicator.
      unreadIndicator = Container(
        margin: const EdgeInsets.all(1),
        child: CircleAvatar(
            radius: 3, backgroundColor: chatListDesign ? accentColor : null),
      );
    } else {
      // Show nothing.
      unreadIndicator = const SizedBox(width: 21);
    }

    var popMenuButton = InteractiveAvatar(
      chatNick: chat.nick,
      radius: chatListDesign ? 23 : null,
      onTap: () {
        widget.makeActive(chat);
        widget.showSubMenu();
      },
      avatar: chat.avatar.image,
      toolTip: true,
    );

    Widget titleWidget = chatListDesign
        ? Text(
            chat.nick,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: hasUnread
                  ? FontWeight.w700
                  : (isActive ? FontWeight.w600 : FontWeight.w500),
              color: isActive ? accentColor : _clpNickColor,
            ),
          )
        : Txt(
            chat.nick,
            overflow: TextOverflow.ellipsis,
            color: TextColor.onSurfaceVariant,
          );

    Widget? subtitleWidget;
    if (showLastMessage) {
      final preview = _lastMsgPreview();
      if (preview != null) {
        subtitleWidget = Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.25,
              color: hasUnread ? _clpPreviewBright : _clpPreviewMuted,
              fontWeight: hasUnread ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        );
      }
    }

    Widget trailingWith(Widget bottom) {
      if (!showLastMessage) return bottom;
      final timeStr = _lastMsgTime();
      if (timeStr.isEmpty) return bottom;
      return Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: hasUnread ? accentColor : const Color(0xFF5F6764),
            ),
          ),
          const SizedBox(height: 6),
          bottom,
        ],
      );
    }

    // Even with the redesign off, the tile below may set a real tileColor
    // (e.g. isActiveRTC's green highlight) that needs a nearby Material to
    // paint into -- see the comment on _wrapSelected.
    Widget wrap(Widget tile) => chatListDesign
        ? _wrapSelected(
            isActive,
            cornerRadius,
            accentColor,
            glowIntensity,
            topHighlight,
            backgroundColor,
            selectedBackgroundColor ?? _shade(backgroundColor, -0.03),
            tile)
        : Material(type: MaterialType.transparency, child: tile);

    bool isScreenSmall = checkIsScreenSmall(context);
    return Consumer<ThemeNotifier>(
      builder: (context, theme, _) => Container(
        child: chat.isGC
            ? GcContexMenu(
                mobile: isScreenSmall
                    ? (context) {
                        widget.makeActive(chat);
                        widget.showSubMenu();
                      }
                    : null,
                targetGcChat: chat,
                child: wrap(
                  ListTile(
                    tileColor: chatListDesign ? Colors.transparent : null,
                    // With the design on, the selected fill is painted by
                    // _wrapSelected and this stays out of the way; with it
                    // off, the plain list used Material's own selected
                    // color, which no palette slot named. Both routes end
                    // up on the same setting now.
                    selectedTileColor: chatListDesign
                        ? Colors.transparent
                        : selectedBackgroundColor,
                    // Hovering lifts the row off its own background rather
                    // than washing it with Material's theme-wide hover
                    // color, which is derived from the app's primary and so
                    // wouldn't follow the background chosen here.
                    // Not on the selected row: its fill is a color of its
                    // own, and lifting that toward the unselected
                    // background on hover just washes it out.
                    hoverColor: chatListDesign && !chat.active
                        ? _shade(backgroundColor, 0.06)
                        : null,
                    horizontalTitleGap: 12,
                    contentPadding: const EdgeInsets.only(
                      left: 10,
                      right: 8,
                    ),
                    minVerticalPadding: chatListDesign ? 20 : 4,
                    enabled: true,
                    title: titleWidget,
                    subtitle: subtitleWidget,
                    leading: popMenuButton,
                    trailing: trailingWith(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "gc",
                          style: theme.extraTextStyles.chatListGcIndicator,
                        ),
                        const SizedBox(width: 5),
                        unreadIndicator,
                      ],
                    )),
                    selected: chat.active,
                    onTap: () => widget.makeActive(chat),
                  ),
                ),
              )
            : UserContextMenu(
                client: client,
                targetUserChat: chat,
                child: wrap(
                  ListTile(
                    tileColor: isActiveRTC
                        ? Colors.green.shade600
                        : (chatListDesign ? Colors.transparent : null),
                    selectedTileColor: isActiveRTC
                        ? Colors.green.shade600
                        : (chatListDesign ? Colors.transparent : null),
                    horizontalTitleGap: 12,
                    contentPadding: const EdgeInsets.only(
                      left: 10,
                      right: 8,
                    ),
                    minVerticalPadding: chatListDesign ? 20 : 4,
                    enabled: true,
                    title: titleWidget,
                    subtitle: subtitleWidget,
                    leading: popMenuButton,
                    trailing: trailingWith(unreadIndicator),
                    selected: chat.active,
                    onTap: () => widget.makeActive(chat),
                  ),
                ),
              ),
      ),
    );
  }
}

Future<void> generateInvite(BuildContext context) async {
  Navigator.of(context, rootNavigator: true).pushNamed('/generateInvite');
}

Future<void> fetchInvite(BuildContext context) async {
  Navigator.of(context, rootNavigator: true).pushNamed('/fetchInvite');
}

void gotoContactsLastMsgTimeScreen(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).pushNamed(ContactsLastMsgTimesScreen.routeName);
}

class ActiveChatsListMenu extends StatefulWidget {
  final ClientModel client;
  final CustomInputFocusNode inputFocusNode;
  final RealtimeChatModel rtc;
  // content/isDetail are only used on desktop-sized layouts, where this
  // widget composes itself with the main chat pane via
  // SecondarySideMenuLayout (see containers.dart) so the submenu
  // Visibility theme setting applies here too.
  final Widget? content;
  final bool isDetail;
  final Object? detailKey;
  const ActiveChatsListMenu(this.client, this.inputFocusNode, this.rtc,
      {this.content, this.isDetail = false, this.detailKey, super.key});

  @override
  State<ActiveChatsListMenu> createState() => _ActiveChatsListMenuState();
}

Future<void> loadInvite(BuildContext context) async {
  // Decode the invite and send to the user verification screen.
  var filePickRes = await FilePicker.platform.pickFiles();
  if (filePickRes == null) return;
  var filePath = filePickRes.files.first.path;
  if (filePath == null) return;
  filePath = filePath.trim();
  if (filePath == "") return;
  var invite = await Golib.decodeInvite(filePath);
  if (context.mounted) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed('/verifyInvite', arguments: invite);
  }
}

class _SmallScreenFabIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _SmallScreenFabIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<ThemeNotifier, ConnStateModel>(
      builder: (context, theme, connState, child) => Material(
        borderRadius: BorderRadius.circular(30),
        color: theme.colors.surfaceContainerHigh.withValues(alpha: 0.7),
        child: Stack(
          children: [
            IconButton(
              splashRadius: 28,
              hoverColor: theme.colors.surfaceContainerHigh,
              iconSize: 40,
              tooltip: tooltip,
              disabledColor: theme.theme.disabledColor,
              onPressed: onPressed,
              icon: Icon(icon, size: 49),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveChatsListMenuState extends State<ActiveChatsListMenu>
    with SingleTickerProviderStateMixin {
  ClientModel get client => widget.client;
  FocusNode get inputFocusNode => widget.inputFocusNode.inputFocusNode;
  RealtimeChatModel get rtc => widget.rtc;
  UnmodifiableListView<ChatModel> chats = UnmodifiableListView([]);
  Timer? debounce;
  ScrollController sortedListScroll = ScrollController();

  void doUpdateState() {
    if (mounted) {
      setState(() {
        chats = client.activeChats.sorted;
      });
    }
    debounce = null;
  }

  void activeChatsListUpdated() {
    // Limit changes when updating chat list very fast.
    debounce ??= Timer(const Duration(milliseconds: 250), doUpdateState);
  }

  // Returns a callback to make chat c active.
  void makeActive(ChatModel? c) {
    client.active = c;
    // Picking a chat out of the collapsed drawer puts it away -- otherwise
    // it stays covering the very conversation it was just asked for. The
    // fixed-item sidebars get this from SecondarySideMenuLayout's
    // closeOnTap wrapper, which can't reach into a dynamic `list:` like
    // this one; this is that same behaviour, applied where the taps
    // actually are.
    client.ui.collapsedSidebar.close();
  }

  void showSubMenu() => client.ui.chatSideMenuActive.chat = client.active;

  // The Address Book rather than the bare New Message screen: it opens on
  // New Message anyway (its first tab), but with its own sidebar alongside,
  // so creating a GC, generating or fetching an invite and the rest are all
  // one click away instead of being dead ends from here.
  void gotoNewMessage() =>
      Navigator.of(context).pushNamed(AddressBookScreen.routeName);

  void gotoNewGroupChat() =>
      Navigator.of(context).pushNamed(NewGcScreen.routeName);

  bool hasLiveRTCSess = false;
  bool hasHotAudio = false;
  bool get hasAnimation => hasLiveRTCSess || hasHotAudio;

  late AnimationController bgColorCtrl;
  late Animation<Color?> bgColorAnim;

  void rtcChanged() {
    bool newHasHotAudio = rtc.hotAudioSession.active?.inLiveSession ?? false;
    bool newHasLive = rtc.liveSessions.hasSessions;
    if (newHasLive != hasLiveRTCSess || newHasHotAudio != hasHotAudio) {
      setState(() {
        hasLiveRTCSess = newHasLive;
        hasHotAudio = newHasHotAudio;
      });
      if (hasAnimation) {
        bgColorCtrl.repeat();
      } else {
        bgColorCtrl.stop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    client.activeChats.addListener(activeChatsListUpdated);
    activeChatsListUpdated();

    rtc.hotAudioSession.addListener(rtcChanged);
    rtc.liveSessions.addListener(rtcChanged);

    // Initialize animation controller
    bgColorCtrl = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    // Create the color animation sequence
    bgColorAnim = TweenSequence<Color?>([
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade600,
          end: Colors.green.shade900,
        ),
      ),
      TweenSequenceItem(
        weight: 1.0,
        tween: ColorTween(
          begin: Colors.green.shade900,
          end: Colors.green.shade600,
        ),
      ),
    ]).animate(bgColorCtrl);
  }

  @override
  void didUpdateWidget(ActiveChatsListMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != client) {
      oldWidget.client.activeChats.removeListener(activeChatsListUpdated);
      client.activeChats.addListener(activeChatsListUpdated);
      activeChatsListUpdated();
    }
  }

  @override
  void dispose() {
    client.activeChats.removeListener(activeChatsListUpdated);

    bgColorCtrl.dispose();
    rtc.hotAudioSession.removeListener(rtcChanged);
    rtc.liveSessions.removeListener(rtcChanged);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);

    // Mobile version: the list of chats is the whole page, so there's no
    // sidebar to hand to the drawer -- and saying so matters, because the
    // drawer holds whatever was registered last until someone takes it
    // back. Without this, re-tapping Chat in the mobile navigation (see the
    // Mobile theme area) slid in the previous page's sidebar.
    if (isScreenSmall) {
      client.ui.collapsedSidebar.unregister();
      return Container(
        padding: const EdgeInsets.all(0),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.only(
                left: 0,
                right: 5,
                top: 5,
                bottom: 5,
              ),
              child: ListView.builder(
                physics: const ScrollPhysics(),
                controller: sortedListScroll,
                scrollDirection: Axis.vertical,
                shrinkWrap: true,
                itemCount: chats.length,
                itemBuilder: (context, index) => _ChatHeadingW(
                    chats[index],
                    client,
                    makeActive,
                    showSubMenu,
                    chats[index].hasInstantCall),
              ),
            ),
            Positioned(
              bottom: 20,
              right: 10,
              child: _SmallScreenFabIconButton(
                tooltip: "New Message",
                icon: Icons.edit_outlined,
                onPressed: gotoNewMessage,
              ),
            ),
            Positioned(
              bottom: 100,
              right: 10,
              child: _SmallScreenFabIconButton(
                tooltip: "Create new group chat",
                icon: Icons.people_outlined,
                onPressed: gotoNewGroupChat,
              ),
            ),
          ],
        ),
      );
    }

    // Desktop version, display side menu.
    return Consumer<ThemeNotifier>(
      builder: (context, theme, _) {
        var chatList = ListView.builder(
          controller: sortedListScroll,
          scrollDirection: Axis.vertical,
          itemCount: chats.length,
          itemBuilder: (context, index) => SecondarySideMenuItem(
            _ChatHeadingW(chats[index], client, makeActive, showSubMenu,
                chats[index].hasInstantCall),
          ),
        );

        var showSearchBar = theme.areaStyle(ThemeArea.chat).enableChatSearch;

        return SecondarySideMenuLayout(
          width: 205 * (theme.fontScale > 0 ? theme.fontScale : 1),
          storageKey: "chats",
          isDetail: widget.isDetail,
          detailKey: widget.detailKey,
          content: widget.content ?? const SizedBox.shrink(),
          header: !showSearchBar
              ? null
              : GestureDetector(
                  onTap: gotoNewMessage,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(10, 12, 10, 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0E0D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1C1F1D)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.search, size: 18, color: Color(0xFF5F6764)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text("Search or start a chat",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13.5, color: Color(0xFF5F6764))),
                      ),
                    ]),
                  ),
                ),
          list: chatList,
          // Generate Invite / Received Message Time / Fetch or Accept
          // Invite / Show GC Invitations moved to the Address Book main
          // menu item's submenu (see address_book_bar.dart). New
          // Message/New Group Chat remain reachable here too via
          // gotoNewMessage/gotoNewGroupChat (used by the mobile FAB
          // buttons above).
        );
      },
    );
  }
}
