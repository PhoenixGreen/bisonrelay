import 'package:bruig/components/address_book_bar.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chat/new_gc_screen.dart';
import 'package:bruig/screens/chat/new_message_screen.dart';
import 'package:bruig/screens/contacts_msg_times.dart';
import 'package:bruig/screens/fetch_invite.dart';
import 'package:bruig/screens/gc_invitations.dart';
import 'package:bruig/screens/generate_invite.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddressBookScreenTitle extends StatelessWidget {
  const AddressBookScreenTitle({super.key});

  @override
  Widget build(BuildContext context) => const Txt.L("Address Book");
}

class AddressBookScreen extends StatefulWidget {
  static const routeName = '/addressBook';

  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  int tabIndex = 0;

  void onItemChanged(int index) => setState(() => tabIndex = index);

  Widget activeTab() {
    var client = Provider.of<ClientModel>(context, listen: false);
    switch (tabIndex) {
      case 0:
        return NewMessageScreen(client);
      case 1:
        return NewGcScreen(client);
      case 2:
        return const GenerateInviteScreen(embedded: true);
      case 3:
        return ContactsLastMsgTimesScreen(client, embedded: true);
      case 4:
        return const FetchInviteScreen(embedded: true);
      case 5:
        return const GCInvitationsScreen(embedded: true);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    if (isScreenSmall) return activeTab();

    return Consumer<ConnStateModel>(
      builder: (context, connState, _) => SecondarySideMenuLayout(
        width: 200,
        storageKey: "addressBook",
        items: addressBookBarItems(onItemChanged, tabIndex, connState.isOnline),
        content: activeTab(),
      ),
    );
  }
}
