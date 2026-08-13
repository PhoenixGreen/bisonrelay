import 'package:bruig/components/address_book_bar.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
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

/// AddressBookTab names the screen's pages, for a caller that wants to open
/// it on one of them.
///
/// Pushed as the route's argument: `pushNamed(AddressBookScreen.routeName,
/// arguments: AddressBookTab.generateInvite)`. That is how the chat list's
/// footer row reaches these pages (see chats_list.dart) -- each of its icons
/// is one of them, and every one of them lands here with the rest of the
/// address book alongside rather than on a screen of its own.
enum AddressBookTab {
  newMessage,
  newGroupChat,
  generateInvite,
  messageTimes,
  fetchInvite,
  gcInvitations,
}

class AddressBookScreen extends StatefulWidget {
  static const routeName = '/addressBook';

  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  int tabIndex = 0;

  /// _openedInitialTab keeps the route's argument from reasserting itself.
  ///
  /// The arguments are read in didChangeDependencies rather than initState
  /// because ModalRoute isn't reachable from the latter; that runs again on
  /// any dependency change, which without this would snap the screen back to
  /// the tab it was opened on the moment anything above it rebuilt.
  bool _openedInitialTab = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_openedInitialTab) return;
    _openedInitialTab = true;
    var arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is AddressBookTab) tabIndex = arg.index;
  }

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
    // Deliberately not short-circuited to a bare activeTab() on a small
    // screen: below SecondarySideMenuLayout's collapse width it already
    // renders content-only, but it also hands its item list to
    // CollapsedSidebarModel on the way -- which is what gives the mobile
    // navigation's re-tap gesture (see the Mobile theme area) something to
    // slide in, and what the mobile header's three-dot menu used to be the
    // only route to.
    return Consumer<ConnStateModel>(
      builder: (context, connState, _) => SecondarySideMenuLayout(
        storageKey: "addressBook",
        items: addressBookBarItems(onItemChanged, tabIndex, connState.isOnline),
        content: activeTab(),
      ),
    );
  }
}
