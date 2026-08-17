import 'dart:async';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/components/chats_list.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/models/notifications.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/needs_out_channel.dart';
import 'package:bruig/screens/realtimechat/instantcallmodal.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:bruig/components/chat/active_chat.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:bruig/components/interactive_avatar.dart';

class ChatsScreenTitle extends StatelessWidget {
  const ChatsScreenTitle({super.key});

  Widget buildInstantCallIcon(
      BuildContext context, RealtimeChatModel rtc, ChatModel chat) {
    return IconButton(
        onPressed: () {
          showInstantCallModal(context, rtc, chat);
        },
        icon: Icon(Icons.call_outlined));
  }

  // buildSearchButton toggles the in-chat search panel, when
  // AreaStyle.enableChatSearch is on.
  Widget buildSearchButton(BuildContext context, ChatModel chat) {
    var ui = Provider.of<ClientModel>(context, listen: false).ui;
    return AnimatedBuilder(
      animation: ui.chatSearch,
      builder: (context, _) => IconButton(
        tooltip: "Search",
        onPressed: () => ui.chatSearch.val = !ui.chatSearch.val,
        icon: Icon(ui.chatSearch.val ? Icons.search_off : Icons.search),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<RealtimeChatModel, ActiveChatModel, ShowProfileModel,
            ThemeNotifier>(
        builder: (context, rtc, activeChat, showProfile, theme, child) {
      var client = rtc.client;
      var activeHeading = activeChat.chat;

      // The name the menu currently gives this destination, or null while it
      // still carries its built-in one -- in which case every state below
      // keeps exactly the wording it already had.
      var menu = Provider.of<MainMenuModel>(context);
      var renamed = menu.headerLabel(ChatsScreen.routeName);

      // No active chat or address book page is active.
      if (activeHeading == null) {
        return Txt.L(renamed ?? "Bison Relay");
      }

      // Has active chat.
      ChatModel chat = activeChat.chat!;
      var enableChatSearch = theme.areaStyle(ThemeArea.chat).enableChatSearch;
      var showCallIcon =
          !theme.areaStyle(ThemeArea.header).hideHeaderCallIcon &&
              !chat.isGC &&
              rtc.active.active == null;

      // On small screen, show only chat nick/title.
      bool isScreenSmall = checkIsScreenSmall(context);
      if (isScreenSmall) {
        // With tap-again-to-close on, this avatar is a toggle for the panel
        // it opens rather than a one-way trip into it -- the same gesture
        // the header's own avatar has. Passing onTap replaces only the tap;
        // the long-press context menu the wrapper provides is untouched.
        var avatarToggles =
            theme.areaStyle(ThemeArea.mobile).mobileAvatarSecondTapCloses;
        return Row(mainAxisAlignment: MainAxisAlignment.start, children: [
          Container(
              width: 40,
              margin:
                  const EdgeInsets.only(top: 0, bottom: 0, left: 0, right: 20),
              child: avatarToggles
                  ? UserMenuAvatar(client, chat, onTap: () {
                      var side = client.ui.chatSideMenuActive;
                      side.chat = side.empty ? chat : null;
                    })
                  : UserMenuAvatar(client, chat, showChatSideMenuOnTap: true)),
          // The nick gives way rather than pushing the icons off the
          // header -- it can be any length, and the header has the back
          // button and avatar in front of it already.
          Flexible(child: Txt.L(chat.nick, overflow: TextOverflow.ellipsis)),
          const Spacer(),
          if (enableChatSearch) buildSearchButton(context, chat),
          if (showCallIcon) buildInstantCallIcon(context, rtc, chat),
        ]);
      }

      // Full chat path.
      bool profile = showProfile.val;
      var suffix = chat.nick != "" ? " / ${chat.nick}" : "";
      var profileSuffix = profile
          ? chat.isGC
              ? " / Manage Group Chat"
              : " / Profile"
          : "";

      // MainAxisSize.min so the header's Text align setting can actually
      // move this: a max-size Row fills the whole title area whatever the
      // AppBar is told to do with it, which pinned the text to the left
      // even with the setting on Center or Right.
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Txt.L("${renamed ?? "Chat"}$suffix$profileSuffix",
                overflow: TextOverflow.ellipsis)),
        if (enableChatSearch) ...[
          const SizedBox(width: 10),
          buildSearchButton(context, chat),
        ],
        if (showCallIcon) ...[
          const SizedBox(width: 10),
          buildInstantCallIcon(context, rtc, chat),
        ],
      ]);
    });
  }
}

class ChatsScreen extends StatefulWidget {
  static const routeName = '/chat';
  final ClientModel client;
  final AppNotifications ntfns;
  final RealtimeChatModel rtc;
  final TypingEmojiSelModel typingEmoji;
  const ChatsScreen(this.client, this.rtc, this.ntfns, this.typingEmoji,
      {super.key});

  static gotoChatScreenFor(BuildContext context, ChatModel chat) {
    ClientModel.of(context, listen: false).active = chat;
    Navigator.of(context).pushNamed(routeName);
  }

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _FundsNeededPage extends StatelessWidget {
  const _FundsNeededPage();

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(20),
        child: Center(
            child: Column(children: [
          const SizedBox(height: 34),
          const Txt.H("Fund Wallet and Channels"),
          const SizedBox(height: 34),
          const Text('''
Bison relay requires active LN channels with outbound capacity to pay to send messages to the server.
'''),
          const SizedBox(height: 34),
          Wrap(runSpacing: 10, children: [
            LoadingScreenButton(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .pushNamed("/needsFunds"),
              text: "Add wallet funds",
            ),
            const SizedBox(height: 20, width: 34),
            LoadingScreenButton(
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .pushNamed(NeedsOutChannelScreen.routeName),
              text: "Create outbound channels",
            )
          ])
        ])));
  }
}

class _LoadingAddressBookPage extends StatelessWidget {
  const _LoadingAddressBookPage();

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, child) => Container(
            padding: const EdgeInsets.all(20),
            child: Center(
                child: Column(children: [
              const SizedBox(height: 34),
              const Txt.H("Loading Address Book"),
              const SizedBox(height: 20),
              LoadingAnimationWidget.waveDots(
                color: theme.colors.onSurface,
                size: 50,
              ),
            ]))));
  }
}

class _InviteNeededPage extends StatefulWidget {
  const _InviteNeededPage();

  @override
  State<_InviteNeededPage> createState() => _InviteNeededPageState();
}

class _InviteNeededPageState extends State<_InviteNeededPage> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void debouncedLoadInvite(BuildContext context) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      loadInvite(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
        child: Center(
            child: Column(children: [
          const Txt.H("Initial Invitation"),
          const SizedBox(height: 34),
          const Text('''
Bison Relay does not rely on a central server for user accounts, so to chat with someone else you need to exchange an invitation with them. This is just a file that should be sent via some other secure transfer method.

After the invitation is accepted, you'll be able to chat with them, and if they know other people, they'll be able to connect you with them.
'''),
          const SizedBox(height: 34),
          Wrap(runSpacing: 10, children: [
            LoadingScreenButton(
              onPressed: () => debouncedLoadInvite(context),
              text: "Load Invitation",
            ),
            const SizedBox(height: 20, width: 34),
            LoadingScreenButton(
              onPressed: () => generateInvite(context),
              text: "Create Invitation",
            )
          ]),
        ])));
  }
}

typedef AddEmojiCallback = Function(Emoji?);

// This class is a hack to pass a FocusNode down the component stack along with
// callbacks for the Input() class to know when to send vs when to add new lines
// to the input component. There should to be a better way to do this.
class CustomInputFocusNode {
  bool get anyMod {
    final kb = HardwareKeyboard.instance;
    return kb.isControlPressed ||
        kb.isAltPressed ||
        kb.isShiftPressed ||
        kb.isMetaPressed;
  }

  late final FocusNode inputFocusNode;

  TextEditingController? controller; // set from ChatInput
  TextSelection? _savedSelection;

  void saveSelection() {
    final c = controller;
    if (c == null) return;

    final sel = c.selection;

    if (!inputFocusNode.hasFocus) return;
    if (!sel.isValid) return;

    // Ignore Flutter's fallback 0/0 collapse
    if (sel.isCollapsed && sel.start == 0) return;

    _savedSelection = sel;
  }

  TextSelection? takeSavedSelection() {
    final s = _savedSelection;
    return s;
  }

  /// Called on plain Enter (no modifiers).
  Function? noModEnterKeyHandler;

  /// Insert the chosen emoji (called with the selected Emoji).
  AddEmojiCallback? addEmojiHandler;

  /// Called when a paste accelerator is detected (Ctrl/Cmd + V).
  Function? pasteEventHandler;

  static const Duration _pasteDebounce = Duration(milliseconds: 300);
  DateTime? _lastPasteTime;

  CustomInputFocusNode(TypingEmojiSelModel typingEmoji) {
    inputFocusNode = FocusNode(onKeyEvent: (node, event) {
      final kb = HardwareKeyboard.instance;

      // Emoji mode (when typing a shortcode)
      if (typingEmoji.isTypingEmoji) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown)) {
          typingEmoji.changeSelection(
              event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1);
          return KeyEventResult.handled;
        }

        // Commit selection with Enter (on KeyUp to avoid double action)
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          if (event is KeyUpEvent) {
            if (typingEmoji.selectedEmoji != null) {
              addEmojiHandler?.call(null);
              typingEmoji.clearSelection();
            }
          }
          // Block enter from sending while in emoji mode
          return KeyEventResult.handled;
        }

        // Commit with Tab (immediate on KeyDown)
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          if (typingEmoji.selectedEmoji != null) {
            addEmojiHandler?.call(null);
            typingEmoji.clearSelection();
          }
          return KeyEventResult.handled;
        }

        // Cancel with Esc
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          typingEmoji.clearSelection();
          return KeyEventResult.handled;
        }
      }

      // Paste shortcut: Ctrl/Cmd + V (with debounce)
      if ((kb.isControlPressed || kb.isMetaPressed) &&
          event.logicalKey == LogicalKeyboardKey.keyV &&
          event is KeyDownEvent) {
        final now = DateTime.now();
        if (_lastPasteTime == null ||
            now.difference(_lastPasteTime!) > _pasteDebounce) {
          _lastPasteTime = now;
          pasteEventHandler?.call();
        }
        return KeyEventResult.handled;
      }

      // Plain Enter (no modifiers) -> send
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (noModEnterKeyHandler != null && !anyMod) {
          if (event is KeyDownEvent) {
            noModEnterKeyHandler!();
          }
          return KeyEventResult.handled;
        }
      }

      return KeyEventResult.ignored;
    });
  }
}

class _ChatsScreenState extends State<ChatsScreen> {
  ClientModel get client => widget.client;
  RealtimeChatModel get rtc => widget.rtc;
  AppNotifications get ntfns => widget.ntfns;
  late CustomInputFocusNode inputFocusNode;
  bool hasLNBalance = false;
  List<PostListItem> userPostList = [];
  Timer? checkLNTimer;

  // check if ln wallet has balance. busywait, needs to be changed into a ntf.
  void keepCheckingLNHasBalance() async {
    if (client.activeChats.isNotEmpty) {
      // Doesn't matter, we already have contacts, so won't show onboard pages.
      return;
    }

    check() async {
      var balances = await Golib.lnGetBalances();
      var newHasBalance = balances.channel.maxOutboundAmount > 0;
      if (!newHasBalance) return false;
      if (mounted) {
        setState(() {
          hasLNBalance = newHasBalance;
        });
      }
      return true;
    }

    if (await check()) return;

    checkLNTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (await check()) timer.cancel();
    });
  }

  @override
  void initState() {
    super.initState();
    inputFocusNode = CustomInputFocusNode(widget.typingEmoji);
    keepCheckingLNHasBalance();
  }

  @override
  void didUpdateWidget(ChatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    checkLNTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!client.hasChats && !client.loadingAddressBook) {
      if (!hasLNBalance) {
        // Only show f user never had any contacts.
        return const _FundsNeededPage();
      }
      return const _InviteNeededPage();
    }
    if (client.loadingAddressBook) {
      return const _LoadingAddressBookPage();
    }

    AudioModel audio = AudioModel.of(context, listen: false);

    bool isScreenSmall = checkIsScreenSmall(context);
    // On a phone the two halves are whole pages rather than a pane and a
    // sidebar: the chat list, which carries its own New Message / New Group
    // Chat buttons, or the conversation. Re-tapping Chat in the mobile
    // navigation goes back to that list (see OverviewScreen._onNavTapped) --
    // it's a better destination than the list as a slide-in drawer would be,
    // so this screen deliberately hands no sidebar to the drawer at all.
    //
    // One Consumer around both layouts rather than one inside each, because
    // the note follows the conversation and has to be declared whichever
    // layout is drawing it. A note here is about the chat, not about the
    // page: walking away and coming back to the same person finds it again.
    return Consumer<ActiveChatModel>(
        builder: (context, activeChat, child) => NoteTargetScope(
              target: _noteTargetFor(activeChat.chat),
              child: !isScreenSmall
                  ? ActiveChatsListMenu(
                      client,
                      inputFocusNode,
                      rtc,
                      isDetail: !activeChat.empty,
                      detailKey: activeChat.chat?.id,
                      content: Container(
                        margin: const EdgeInsets.all(1),
                        child: ActiveChat(client, rtc, audio, inputFocusNode),
                      ),
                    )
                  : activeChat.empty
                      ? ActiveChatsListMenu(client, inputFocusNode, rtc)
                      : _MobileActiveChat(client, rtc, audio, inputFocusNode),
            ));
  }

  /// _noteTargetFor is the open conversation, or nothing when the chat list is
  /// showing on its own -- a list of everybody is not a thing to take notes
  /// about, and the app-wide note is the better answer there.
  NoteTarget? _noteTargetFor(ChatModel? chat) => chat == null
      ? null
      : NoteTarget.chat(chat.id, chat.nick, isGC: chat.isGC);
}

// _MobileActiveChat is the conversation as a full page, and the one screen
// in the app that reaches CollapsedSidebarModel without a
// SecondarySideMenuLayout to do it: the chat list isn't built at all while
// a conversation is open here, so nothing else is in a position to hand the
// drawer back, and it would otherwise still be holding whichever page's
// sidebar was registered last.
class _MobileActiveChat extends StatelessWidget {
  final ClientModel client;
  final RealtimeChatModel rtc;
  final AudioModel audio;
  final CustomInputFocusNode inputFocusNode;
  const _MobileActiveChat(
      this.client, this.rtc, this.audio, this.inputFocusNode);

  @override
  Widget build(BuildContext context) {
    client.ui.collapsedSidebar.unregister();
    return ActiveChat(client, rtc, audio, inputFocusNode);
  }
}
