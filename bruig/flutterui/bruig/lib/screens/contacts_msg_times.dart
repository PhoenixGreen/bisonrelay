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

  @override
  Widget build(BuildContext context) {
    var children = [
      const Txt.H("Last Message Time"),
      Container(
          padding: const EdgeInsets.only(right: 12),
          child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) => _UserLastMsgTime(
                  users[index], client.getExistingChat(users[index].uid)!))),
    ];

    if (widget.embedded) {
      return SingleChildScrollView(
          child: Container(padding: const EdgeInsets.all(20), child: Column(children: children)));
    }

    return StartupScreen(
      children,
      fab: FloatingActionButton.small(
          onPressed: onDone, child: const Icon(Icons.done)),
    );
  }
}
