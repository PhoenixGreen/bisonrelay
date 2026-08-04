import 'package:bruig/components/copyable.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/screens/startupscreen.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';

class ContactsLastMsgTimesScreen extends StatefulWidget {
  static const routeName = "contactsLastMsgTimes";
  final ClientModel client;
  // embedded is true when shown inline as Address Book tab content instead
  // of pushed as a full-screen route -- skips StartupScreen's Scaffold/
  // background/About-button/fab chrome, since the embedding page already
  // provides its own frame and there's nothing to "pop" back to.
  final bool embedded;
  const ContactsLastMsgTimesScreen(this.client,
      {this.embedded = false, super.key});

  @override
  State<ContactsLastMsgTimesScreen> createState() =>
      _ContactsLastMsgTimesScreenState();
}

class _UserLastMsgTime extends StatelessWidget {
  final LastUserReceivedTime info;
  final ChatModel chat;
  const _UserLastMsgTime(this.info, this.chat);

  void requestRatchetReset(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    chat.requestKXReset();
    snackbar.success("Attempting to reset ratchet with user");
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 5),
      child: Row(children: [
        Text(
          DateTime.fromMillisecondsSinceEpoch(info.lastDecrypted * 1000)
              .toIso8601String(),
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(width: 10),
        Text(chat.nick),
        const SizedBox(width: 10),
        Expanded(
            child:
                Copyable.txt(Txt(info.uid, overflow: TextOverflow.ellipsis))),
        Align(
            alignment: Alignment.bottomRight,
            child: IconButton(
                onPressed: () => requestRatchetReset(context),
                tooltip: "Request a Ratchet Reset",
                icon: const Icon(Icons.restore)))
      ]),
    );
  }
}

class _ContactsLastMsgTimesScreenState
    extends State<ContactsLastMsgTimesScreen> {
  ClientModel get client => widget.client;
  List<LastUserReceivedTime> users = [];

  void loadList() async {
    try {
      var newList = await Golib.listUsersLastMsgTimes();
      setState(() {
        users = newList;
      });
    } catch (exception) {
      showErrorSnackbar(
          this, "Unable to fetch list of contact's last msg time: $exception");
    }
  }

  @override
  void initState() {
    super.initState();
    loadList();
  }

  void onDone() {
    Navigator.of(context).maybePop();
  }

  // Address Book tabs all use the same title: same size (Txt.L), centred
  // across the full width of the page. Pushed as a standalone route these
  // screens keep the larger startup-screen heading.
  Widget _title(String text) => SizedBox(
      width: double.infinity,
      child: widget.embedded
          ? Txt.L(text, textAlign: TextAlign.center)
          : Txt.H(text, textAlign: TextAlign.center));
  @override
  Widget build(BuildContext context) {
    var children = [
      _title("Last Message Time"),
      // No inset of its own: the page's gutters are the same on both
      // sides, and a right-only padding here made it look lopsided.
      ListView.builder(
          shrinkWrap: true,
          itemCount: users.length,
          itemBuilder: (context, index) => _UserLastMsgTime(
              users[index], client.getExistingChat(users[index].uid)!)),
    ];

    if (widget.embedded) {
      return SingleChildScrollView(
          // The gutters every content-area page uses, so the Address Book
          // tabs sit where the pages beside them do.
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children));
    }

    return StartupScreen(
      children,
      fab: FloatingActionButton.small(
          onPressed: onDone, child: const Icon(Icons.done)),
    );
  }
}
