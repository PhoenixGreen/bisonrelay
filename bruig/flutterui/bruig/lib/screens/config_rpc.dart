import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/newconfig.dart';
import 'package:bruig/screens/shutdown.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RpcConfigScreen extends StatefulWidget {
  static const String routeName = "/rpcConfig";
  final NewConfigModel? newConf;
  const RpcConfigScreen({this.newConf, super.key});

  @override
  State<RpcConfigScreen> createState() => _RpcConfigScreenState();
}

class _RpcConfigScreenState extends State<RpcConfigScreen> {
  NewConfigModel? get newConfigModel => widget.newConf;
  TextEditingController rpcListenCtrl = TextEditingController();
  TextEditingController rpcCertPathCtrl = TextEditingController();
  TextEditingController rpcKeyPathCtrl = TextEditingController();
  TextEditingController rpcClientCACtrl = TextEditingController();
  TextEditingController rpcUserCtrl = TextEditingController();
  TextEditingController rpcPassCtrl = TextEditingController();
  TextEditingController rpcAuthModeCtrl = TextEditingController();
  TextEditingController rpcMaxRemoteSendTipAmtCtrl = TextEditingController();
  bool rpcIssueClientCert = false;
  bool rpcAllowRemoteSendTip = false;

  void doRestart() {
    ShutdownScreen.startShutdown(context, restart: true);
    Navigator.pop(context);
  }

  void changeConfig() async {
    await replaceConfig(
      mainConfigFilename,
      jsonRPCListen: rpcListenCtrl.text,
      rpcCertPath: rpcCertPathCtrl.text,
      rpcKeyPath: rpcKeyPathCtrl.text,
      rpcClientCApath: rpcClientCACtrl.text,
      rpcUser: rpcUserCtrl.text,
      rpcPass: rpcPassCtrl.text,
      rpcAuthMode: rpcAuthModeCtrl.text,
      rpcIssueClientCert: rpcIssueClientCert,
      rpcAllowRemoteSendTip: rpcAllowRemoteSendTip,
      rpcMaxRemoteSendTipAmt:
          double.tryParse(rpcMaxRemoteSendTipAmtCtrl.text) ?? 0,
    );
    if (!mounted) return;
    confirmationDialog(
      context,
      doRestart,
      "Restart App?",
      "App restart is required to apply RPC settings changes.",
      "Restart",
      "Cancel",
      onCancel: () {
        Navigator.of(context).pop();
      },
    );
  }

  void confirmAcceptChanges() {
    if (newConfigModel != null) {
      var newConfigModel = Provider.of<NewConfigModel>(context, listen: false);
      newConfigModel.jsonRPCListen =
          rpcListenCtrl.text.split(',').map((addr) => addr.trim()).toList();
      newConfigModel.rpcCertPath = rpcCertPathCtrl.text;
      newConfigModel.rpcKeyPath = rpcKeyPathCtrl.text;
      newConfigModel.rpcClientCApath = rpcClientCACtrl.text;
      newConfigModel.rpcUser = rpcUserCtrl.text;
      newConfigModel.rpcPass = rpcPassCtrl.text;
      newConfigModel.rpcAuthMode = rpcAuthModeCtrl.text;
      newConfigModel.rpcIssueClientCert = rpcIssueClientCert;
      newConfigModel.rpcAllowRemoteSendTip = rpcAllowRemoteSendTip;
      newConfigModel.rpcMaxRemoteSendTipAmt =
          double.tryParse(rpcMaxRemoteSendTipAmtCtrl.text) ?? 0;
      Navigator.of(context).pop();
      return;
    }

    confirmationDialog(
        context,
        changeConfig,
        onCancel: () => Navigator.of(context).pop(),
        "Change Config?",
        "Change RPC config? To apply the changes, the app will require a restart.",
        "Accept",
        "Cancel");
  }

  void readConfig() async {
    if (newConfigModel != null) {
      setState(() {
        rpcListenCtrl.text = newConfigModel!.jsonRPCListen.join(", ");
        rpcCertPathCtrl.text = newConfigModel!.rpcCertPath;
        rpcKeyPathCtrl.text = newConfigModel!.rpcKeyPath;
        rpcClientCACtrl.text = newConfigModel!.rpcClientCApath;
        rpcUserCtrl.text = newConfigModel!.rpcUser;
        rpcPassCtrl.text = newConfigModel!.rpcPass;
        rpcAuthModeCtrl.text = newConfigModel!.rpcAuthMode;
        rpcIssueClientCert = newConfigModel!.rpcIssueClientCert;
        rpcAllowRemoteSendTip = newConfigModel!.rpcAllowRemoteSendTip;
        rpcMaxRemoteSendTipAmtCtrl.text =
            newConfigModel!.rpcMaxRemoteSendTipAmt.toString();
      });
      return;
    }

    var cfg = await loadConfig(mainConfigFilename);
    setState(() {
      rpcListenCtrl.text = cfg.jsonRPCListen.join(", ");
      rpcCertPathCtrl.text = cfg.rpcCertPath;
      rpcKeyPathCtrl.text = cfg.rpcKeyPath;
      rpcClientCACtrl.text = cfg.rpcClientCApath;
      rpcUserCtrl.text = cfg.rpcUser;
      rpcPassCtrl.text = cfg.rpcPass;
      rpcAuthModeCtrl.text = cfg.rpcAuthMode;
      rpcIssueClientCert = cfg.rpcIssueClientCert;
      rpcAllowRemoteSendTip = cfg.rpcAllowRemoteSendTip;
      rpcMaxRemoteSendTipAmtCtrl.text = cfg.rpcMaxRemoteSendTipAmt.toString();
    });
  }

  // The first six fields are the ones that give away how to reach and
  // authenticate against this client's RPC, so they start masked on every
  // visit -- including after a config is loaded into them -- rather than
  // being readable by anyone who happens to be looking at the screen.
  // Tracked per field so revealing the password doesn't also expose the
  // certificate paths.
  final Set<TextEditingController> _revealed = {};

  Widget _secretField(TextEditingController ctrl,
      {required String label, required String hint}) {
    var shown = _revealed.contains(ctrl);
    return TextField(
      controller: ctrl,
      obscureText: !shown,
      // Without this, a masked field silently drops autocorrect/suggestion
      // behaviour differences between platforms into the value.
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(shown ? Icons.visibility : Icons.visibility_off),
          tooltip: shown ? "Hide" : "Show",
          onPressed: () => setState(() {
            if (shown) {
              _revealed.remove(ctrl);
            } else {
              _revealed.add(ctrl);
            }
          }),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    readConfig();
  }

  @override
  Widget build(BuildContext context) {
    var children = [
      const Txt.H("Configure RPC Options"),
      const SizedBox(height: 20),
      _secretField(rpcListenCtrl,
          label: "JSON-RPC Listen Address", hint: "127.0.0.1:7676"),
      const SizedBox(height: 10),
      _secretField(rpcCertPathCtrl,
          label: "RPC Certificate Path", hint: "/path/to/cert"),
      const SizedBox(height: 10),
      _secretField(rpcKeyPathCtrl, label: "RPC Key Path", hint: "/path/to/key"),
      const SizedBox(height: 10),
      _secretField(rpcClientCACtrl,
          label: "RPC Client CA Path", hint: "/path/to/ca"),
      const SizedBox(height: 10),
      _secretField(rpcUserCtrl, label: "RPC Username", hint: "rpcuser"),
      const SizedBox(height: 10),
      _secretField(rpcPassCtrl, label: "RPC Password", hint: "rpcpass"),
      const SizedBox(height: 10),
      TextField(
          controller: rpcAuthModeCtrl,
          decoration: const InputDecoration(
              labelText: "RPC Auth Mode", hintText: "authmode")),
      const SizedBox(height: 10),
      TextField(
          keyboardType: TextInputType.number,
          controller: rpcMaxRemoteSendTipAmtCtrl,
          decoration: const InputDecoration(
              labelText: "Max Remote Send Tip Amount", hintText: "0.0")),
      const SizedBox(height: 20),
      SwitchListTile(
        title: const Text("Issue Client Certificate"),
        value: rpcIssueClientCert,
        onChanged: (value) => setState(() => rpcIssueClientCert = value),
      ),
      const SizedBox(height: 10),
      SwitchListTile(
        title: const Text("Allow Remote Send Tip"),
        value: rpcAllowRemoteSendTip,
        onChanged: (value) => setState(() => rpcAllowRemoteSendTip = value),
      ),
      const SizedBox(height: 30),
      Wrap(runSpacing: 10, children: [
        OutlinedButton(
            onPressed: confirmAcceptChanges, child: const Text("Accept")),
        const SizedBox(width: 50),
        CancelButton(onPressed: () => Navigator.of(context).maybePop()),
      ]),
    ];

    // Full width of the content area, with the same 16px gutters the
    // Account and Appearance pages use -- this was a centred 400px column,
    // which read as a different page shape from the rest of Settings.
    return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children));
  }
}
