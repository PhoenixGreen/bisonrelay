import 'package:bruig/components/usersearch/user_search_panel.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/screens/chats.dart';
import 'package:flutter/widgets.dart';

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
        padding: const EdgeInsets.all(10),
        child: UserSearchPanel(
          client,
          confirmLabel: "",
          targets: UserSearchPanelTargets.usersAndGCs,
          onCancel: goBack,
          onChatTapped: chatTapped,
        ));
  }
}
