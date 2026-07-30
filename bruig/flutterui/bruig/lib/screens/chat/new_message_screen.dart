import 'package:bruig/components/usersearch/user_search_panel.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/components/text.dart';
import 'package:flutter/material.dart';

class NewMessageScreen extends StatefulWidget {
  static const routeName = "/chat/newMessage";

  final ClientModel client;
  const NewMessageScreen(this.client, {super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  ClientModel get client => widget.client;

  void goBack() {
    Navigator.of(context).maybePop();
  }

  void chatTapped(ChatModel chat) {
    client.makeTopActive(chat);
    // Switch straight to the Chat page to show the conversation that was
    // just made active -- matches the same pattern used elsewhere (e.g.
    // FeedScreen.showUsersPosts) for jumping to a different main menu item
    // from deep within another one. Works whether this screen is pushed
    // (mobile's FAB) or embedded in place (Address Book's submenu).
    Navigator.of(context).pushReplacementNamed(ChatsScreen.routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        // Same title and gutters as every other Address Book tab -- this
        // page had neither.
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(
              width: double.infinity,
              child: Txt.L("New Message", textAlign: TextAlign.center)),
          const SizedBox(height: 10),
          Expanded(
            child: UserSearchPanel(
              client,
              confirmLabel: "",
              targets: UserSearchPanelTargets.usersAndGCs,
              onCancel: goBack,
              onChatTapped: chatTapped,
            ),
          ),
        ]));
  }
}
