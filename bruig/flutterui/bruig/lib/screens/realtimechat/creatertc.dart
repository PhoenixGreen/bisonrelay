import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/inputs.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/usersearch/selected_users_panel.dart';
import 'package:bruig/components/usersearch/user_search_model.dart';
import 'package:bruig/components/usersearch/user_search_panel.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/screens/overview.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:flutter/material.dart';

/// sessionDescriptionError says why a session cannot be created under the
/// description given, or null if it can.
///
/// A function of its own, and the only place the rule is written: the Create
/// button, the message under the field and the check made when Create is
/// pressed all ask this, so the three cannot come to disagree -- a live
/// button that then refuses is exactly the shape that bug takes.
///
/// The description is the only thing a session is known by. The session list
/// falls back to the first ten characters of its rendezvous point, which is a
/// hex string and tells the reader nothing, so an unnamed session is one
/// nobody can pick out again.
///
/// An instant call is exempt: it is one call to one person, removed as soon
/// as everybody leaves, and it has no description field to fill in.
String? sessionDescriptionError(String raw, {required bool isInstant}) {
  if (isInstant) return null;
  if (raw.trim().isEmpty) return "A description is required";
  return null;
}

class CreateRealtimeChatScreenArgs {
  final bool isInstant;
  final ChatModel? initial;

  CreateRealtimeChatScreenArgs({this.isInstant = false, this.initial});
}

class CreateRealtimeChatScreen extends StatefulWidget {
  static const routeName = "/createRealtimeChatSession";

  final RealtimeChatModel rtc;
  const CreateRealtimeChatScreen(this.rtc, {super.key});

  @override
  State<CreateRealtimeChatScreen> createState() =>
      _CreateRealtimeChatScreenState();
}

class _CreateRealtimeChatScreenState extends State<CreateRealtimeChatScreen> {
  IntEditingController sizeCtrl = IntEditingController();
  TextEditingController descrCtrl = TextEditingController();
  bool creating = false;
  bool isInstant = false;
  final UserSelectionModel userSelModel =
      UserSelectionModel(allowMultiple: true);

  /// description is what the session is called, with the surrounding space
  /// taken off -- a name of three spaces is no name.
  String get description => descrCtrl.text.trim();

  /// descriptionError is why the session cannot be created yet, or null.
  String? get descriptionError =>
      sessionDescriptionError(descrCtrl.text, isInstant: isInstant);

  bool get hasDescription => descriptionError == null;

  @override
  void initState() {
    super.initState();
    sizeCtrl.intvalue = 2;
    // sizeCtrl.text = "2";
    // Rebuild as it is typed in, so Create comes alive on the first
    // character rather than staying dead until something else happens.
    descrCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    descrCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var modalArgs = ModalRoute.of(context)?.settings.arguments;
    if (modalArgs is CreateRealtimeChatScreenArgs) {
      isInstant = modalArgs.isInstant;
      if (modalArgs.initial != null) {
        userSelModel.add(modalArgs.initial!);
      }
    }
  }

  void create() async {
    setState(() => creating = true);
    if (sizeCtrl.intvalue < 2 || sizeCtrl.intvalue > 1 << 16) {
      showErrorSnackbar(context, "Invalid session size");
      setState(() => creating = false);
      return;
    }

    // Checked here as well as by the disabled button. The description is the
    // only thing a session is known by -- the list falls back to the first
    // ten characters of its rendezvous point, which is a hex string and
    // tells the reader nothing -- so an unnamed session is one nobody can
    // pick out again.
    if (!hasDescription) {
      showErrorSnackbar(context, "Please give the session a description");
      setState(() => creating = false);
      return;
    }

    try {
      List<String> toInvite = userSelModel.selected.map((c) => c.id).toList();
      if (isInstant) {
        await widget.rtc.createInstantSession(toInvite);
      } else {
        await widget.rtc
            .createSession(sizeCtrl.intvalue, description, toInvite);
        showSuccessSnackbar(this, "Created realtime chat session!");
      }
      if (mounted) {
        Navigator.of(context).pop();
        if (isInstant) {
          Navigator.of(context).pushReplacementNamed(
              OverviewScreen.subRoute(RealtimeChatScreen.routeName));
        }
      }
    } catch (exception) {
      showErrorSnackbar(this, "Unable to create session: $exception");
    } finally {
      setState(() => creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ClientModel client = ClientModel.of(context, listen: false);

    return Scaffold(
        body: Container(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        (!isInstant
            ? const Txt.H("Create Realtime Chat Session")
            : const Txt.H("Instant Realtime Call")),
        const SizedBox(height: 20),
        if (!isInstant) ...[
          SizedBox(
              width: 100,
              child: Row(children: [
                const Text("Size:"),
                const SizedBox(width: 10),
                Expanded(child: intInput(controller: sizeCtrl)),
              ])),
          SizedBox(
              width: 400,
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text("Description:")),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                  controller: descrCtrl,
                  decoration: InputDecoration(
                    hintText: "What is this session for?",
                    // Only once something has been typed and then taken
                    // away again: a field that opens already complaining
                    // reads as an error the reader has made, and they
                    // have not made one yet.
                    errorText:
                        descrCtrl.text.isNotEmpty ? descriptionError : null,
                  ),
                )),
              ])),
          const SizedBox(height: 10),
        ],
        Expanded(
            child: UserSearchPanel(
          client,
          userSelModel: userSelModel,
          showButtonsRow: false,
        )),
        const SizedBox(height: 10),
        Container(
            padding: const EdgeInsets.all(10),
            height: 60,
            width: 500,
            child:
                SingleChildScrollView(child: SelectedUsersPanel(userSelModel))),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          CancelButton(onPressed: () {
            Navigator.of(context).pop();
          }),
          ElevatedButton(
              onPressed: !creating && hasDescription ? create : null,
              child: !isInstant ? const Text("Create") : const Text("Call")),
        ]),
      ]),
    ));
  }
}
