import 'dart:io';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/containers.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/info_grid.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/volume_control.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/log.dart';
import 'package:bruig/models/realtimechat.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/notification_service.dart';
import 'package:bruig/screens/config_network.dart';
import 'package:bruig/screens/list_kxs.dart';
import 'package:bruig/screens/config_rpc.dart';
import 'package:bruig/screens/ln_management.dart';
import 'package:bruig/screens/log.dart';
import 'package:bruig/screens/menu_settings.dart';
import 'package:bruig/screens/manage_content/manage_content.dart';
import 'package:bruig/screens/paystats.dart';
import 'package:bruig/screens/about.dart';
import 'package:bruig/screens/realtimechat/rtclist.dart';
import 'package:bruig/screens/shutdown.dart';
import 'package:bruig/screens/theme_editor.dart';
import 'package:bruig/util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:bruig/theme_manager.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/util.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:bruig/models/client.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:bruig/storage_manager.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/components/copyable.dart';

typedef ChangePageCB = void Function(String);
typedef NotficationsCB = void Function(bool?, bool?);
typedef ResetKXCB = void Function(BuildContext);
typedef ShutdownCB = void Function();

class SettingsScreenTitle extends StatelessWidget {
  const SettingsScreenTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsTitleModel>(
        builder: (context, settingsTitle, child) => Txt.L(settingsTitle.title));
  }
}

class SettingsScreen extends StatefulWidget {
  final ClientModel client;
  const SettingsScreen(this.client, {super.key});
  static String routeName = "/settings";

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ClientModel get client => widget.client;
  bool loading = false;
  late String settingsPage = client.ui.settingsNav.page;
  bool showRPCWarning = true;

  void loadSettings() async {
    var showWarning = await StorageManager.readBool(
        StorageManager.showRPCWarningKey,
        defaultVal: true);
    setState(() {
      showRPCWarning = showWarning;
    });
  }

  void connStateChanged() async {
    setState(() {});
  }

  void resetAllOldKX(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);

    if (loading) return;
    setState(() => loading = true);
    try {
      await Golib.resetAllOldKX(0);
      snackbar
          .success('Requesting KX to all old KX no communicated in 30 days...');
    } catch (exception) {
      snackbar.error('Unable to reset all old KX: $exception');
    } finally {
      setState(() => loading = false);
    }
  }

  void resetAllOldKX1s(BuildContext context) async {
    if (loading) return;
    setState(() => loading = true);
    var snackbar = SnackBarModel.of(context);

    try {
      await Golib.resetAllOldKX(1);
      snackbar.success('Requesting KX to all old KX...');
    } catch (exception) {
      snackbar.error('Unable to reset all old KX: $exception');
    } finally {
      setState(() => loading = false);
    }
  }

  void pickAvatarFile() async {
    var snackbar = SnackBarModel.of(context);

    var filePickRes = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      dialogTitle: "Pick avatar image file",
      type: FileType.custom,
      allowedExtensions: ["bmp", "gif", "jpeg", "jpg", "png", "webp"],
    );
    if (filePickRes == null) return;
    var fPath = filePickRes.files.first.path;
    if (fPath == null) return;
    var filePath = fPath.trim();
    var fileData = await File(filePath).readAsBytes();
    try {
      await Golib.setMyAvatar(fileData);
      client.myAvatar.loadAvatar(fileData);
    } catch (exception) {
      snackbar.error("Unable to set avatar: $exception");
    }
  }

  void subAllPosts() async {
    try {
      await Golib.subscribeToAllRemotePosts();
      showSuccessSnackbar(
          this, "Attempting to subscribe to all remote user's posts");
    } catch (exception) {
      showErrorSnackbar(
          this, "Unable to subscribe to all remote posts: $exception");
    }
  }

  void listKXs() {
    Navigator.of(context, rootNavigator: true)
        .pushNamed(ListKXsScreen.routeName);
  }

  void changePage(String newPage) {
    setState(() {
      client.ui.settingsTitle.title = newPage;
      client.ui.settingsNav.page = newPage;
      settingsPage = newPage;
    });
  }

  void shutdown() {
    ShutdownScreen.startShutdown(context);
  }

  @override
  void initState() {
    super.initState();
    loadSettings();
    client.connState.addListener(connStateChanged);
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      oldWidget.client.connState.removeListener(connStateChanged);
      client.connState.addListener(connStateChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => client.ui.settingsTitle.title = "Settings");
    client.connState.removeListener(connStateChanged);
    super.dispose();
  }

  void showRpcWarningDialog() {
    if (!showRPCWarning) {
      changePage("RPC");
      return;
    }

    bool turnOffAlert = false;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Allow JSON RPC Access"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Enabling JSON RPC allows connections from third-party applications. Are you sure you want to proceed?",
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: turnOffAlert,
                        onChanged: (bool? value) {
                          setDialogState(() => turnOffAlert = value ?? false);
                        },
                      ),
                      const Text("Don’t show this message again"),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // Update the setting if the user chose to disable future alerts
                    if (turnOffAlert) {
                      StorageManager.saveBool(
                          StorageManager.showRPCWarningKey, false);
                      setState(() => showRPCWarning = false);
                    }
                    changePage("RPC");
                  },
                  child: const Text("Continue"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    Widget settingsView = isScreenSmall
        ? MainSettingsScreen(client, pickAvatarFile, changePage, shutdown)
        : const Empty();
    switch (settingsPage) {
      case "Account":
        settingsView = AccountSettingsScreen(client, resetAllOldKX1s,
            resetAllOldKX, pickAvatarFile, subAllPosts, listKXs);
        break;
      case "Appearance":
        settingsView = Consumer<ThemeNotifier>(
            builder: (context, theme, _) =>
                AppearanceSettingsScreen(client, theme));
        break;
      case "Notifications":
        settingsView = const NotificationsSettingsScreen();
        break;
      case "Network":
        settingsView = NetworkSettingsScreen(client);
        break;
      case "RPC":
        settingsView = const RpcConfigScreen();
        break;
      case "About":
        settingsView = const AboutScreen(settings: true);
        break;
      case "Audio":
        settingsView = Consumer<AudioModel>(
            builder: (context, audio, child) =>
                AudioSettingsScreen(audio: audio));
        break;
      case "Stats":
        settingsView = ThemedArea(
            area: ThemeArea.stats,
            child: Consumer<ClientModel>(
                builder: (context, client, child) => PayStatsScreen(client)));
        break;
      case "Logs":
        settingsView = ThemedArea(
            area: ThemeArea.logs,
            child: Consumer<LogModel>(
                builder: (context, log, child) => LogScreen(log)));
        break;
      default:
        break;
    }
    if (isScreenSmall) {
      return Scaffold(
          body: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: settingsView));
    }

    // Desktop-sized version.
    return Consumer<ThemeNotifier>(builder: (context, theme, _) {
      if (theme.areaStyle(ThemeArea.masterBackground).settingsShellRestyle) {
        return Row(children: [
          _RestyledSettingsNav(
              settingsPage: settingsPage,
              changePage: changePage,
              showRpcWarningDialog: showRpcWarningDialog),
          Expanded(child: settingsView),
        ]);
      }
      return SecondarySideMenuLayout(
        width: 130 * (theme.fontScale > 0 ? theme.fontScale : 1),
        storageKey: "settings",
        content: settingsView,
        items: [
          SidebarNavItem(
            icon: Icons.person_outline,
            selected: settingsPage == "Account",
            label: "Account",
            onTap: () => changePage("Account"),
          ),
          SidebarNavItem(
            icon: Icons.palette_outlined,
            selected: settingsPage == "Appearance",
            label: "Appearance",
            onTap: () => changePage("Appearance"),
          ),
          SidebarNavItem(
            icon: Icons.notifications_outlined,
            selected: settingsPage == "Notifications",
            label: "Notifications",
            onTap: () => changePage("Notifications"),
          ),
          SidebarNavItem(
            icon: Icons.public,
            selected: settingsPage == "Network",
            label: "Network",
            onTap: () => changePage("Network"),
          ),
          SidebarNavItem(
            icon: Icons.volume_up_outlined,
            selected: settingsPage == "Audio",
            label: "Audio",
            onTap: () => changePage("Audio"),
          ),
          SidebarNavItem(
            icon: Icons.terminal,
            selected: settingsPage == "RPC",
            label: "RPC",
            onTap: () => showRpcWarningDialog(),
          ),
          SidebarNavItem(
            icon: Icons.bar_chart_outlined,
            selected: settingsPage == "Stats",
            label: "Stats",
            onTap: () => changePage("Stats"),
          ),
          SidebarNavItem(
            icon: Icons.list_outlined,
            selected: settingsPage == "Logs",
            label: "Logs",
            onTap: () => changePage("Logs"),
          ),
        ],
      );
    });
  }
}

// Restyled left nav for AreaStyle.settingsShellRestyle: icon + pill
// highlight rows instead of plain ListTiles.
class _RestyledSettingsNav extends StatelessWidget {
  final String settingsPage;
  final ChangePageCB changePage;
  final VoidCallback showRpcWarningDialog;
  const _RestyledSettingsNav(
      {required this.settingsPage,
      required this.changePage,
      required this.showRpcWarningDialog});

  Widget _navItem(
      BuildContext context, ThemeNotifier theme, String page, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    final sel = settingsPage == page;
    // Matches the same preset-driven accent every other sidebar in the app
    // uses (see containers.dart's _SidebarNavRow) instead of falling back
    // to colorScheme.primary/surfaceContainerHighest, which don't follow
    // the user's chosen Sidebar Accent color.
    final accent = theme.activePreset?.sidebarAccent ?? cs.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: sel ? accent.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              page == "RPC" ? showRpcWarningDialog() : changePage(page),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 19, color: sel ? accent : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Text(page,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                    color: sel ? cs.onSurface : cs.onSurfaceVariant,
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Container(
      width: 200,
      decoration: BoxDecoration(
        border: Border(
            right: BorderSide(color: Theme.of(context).colorScheme.outline)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        children: [
          _navItem(context, theme, "Account", Icons.person_outline),
          _navItem(context, theme, "Appearance", Icons.palette_outlined),
          _navItem(context, theme, "Notifications",
              Icons.notifications_outlined),
          _navItem(context, theme, "Network", Icons.public),
          _navItem(context, theme, "Audio", Icons.volume_up_outlined),
          _navItem(context, theme, "RPC", Icons.terminal),
          _navItem(context, theme, "Stats", Icons.bar_chart_outlined),
          _navItem(context, theme, "Logs", Icons.list_outlined),
        ],
      ),
    );
  }
}

class MainSettingsScreen extends StatelessWidget {
  final ClientModel client;
  final VoidCallback pickAvatarFile;
  final ChangePageCB changePage;
  final ShutdownCB shutdown;
  const MainSettingsScreen(
      this.client, this.pickAvatarFile, this.changePage, this.shutdown,
      {super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => ListView(
              children: [
                ListTile(
                    title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                      Container(
                        margin: const EdgeInsets.all(10),
                        child: SelfAvatar(client, onTap: pickAvatarFile),
                      ),
                      Column(children: [
                        Text(client.nick),
                        SizedBox(
                            width: 150,
                            child: Copyable.txt(
                              Txt(client.publicID,
                                  overflow: TextOverflow.ellipsis),
                            ))
                      ])
                    ])),
                ListTile(
                    onTap: () => changePage("Account"),
                    leading: const Icon(Icons.person_outline),
                    title: const Text("Account")),
                ListTile(
                    onTap: () => changePage("Appearance"),
                    leading: const Icon(Icons.brightness_medium_outlined),
                    title: const Text("Appearance")),
                ListTile(
                    onTap: () => changePage("Notifications"),
                    leading: const Icon(Icons.notifications_outlined),
                    title: const Text("Notifications")),
                Consumer<ConnStateModel>(
                    builder: (context, connState, child) => Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                            tileColor: connState.state.state ==
                                    connStateOffline
                                ? Colors.red
                                : (connState.checkWalletErr ?? "") != ""
                                    ? Colors.amber[800]
                                    : null,
                            onTap: () => changePage("Network"),
                            leading: const Icon(Icons.shield),
                            title: const Text("Network")))),
                ListTile(
                    onTap: () => changePage("Audio"),
                    leading: const Icon(Icons.perm_camera_mic_outlined),
                    title: const Text("Audio")),
                Consumer<LiveRTDTSessionsModel>(
                    builder: (context, liveSessions, child) => Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                            tileColor: liveSessions.hasSessions
                                ? Colors.green.shade700
                                : null,
                            onTap: () {
                              Navigator.of(context).pushReplacementNamed(
                                  RealtimeChatScreen.routeName);
                            },
                            leading: const Icon(Icons.voice_chat),
                            title: const Text("Realtime chat")))),
                ListTile(
                    onTap: () {
                      Navigator.of(context)
                          .pushReplacementNamed(LNScreen.routeName);
                    },
                    leading: const SidebarSvgIcon(
                        "assets/icons/icons-menu-lnmng.svg"),
                    title: const Text("LN Management")),
                ListTile(
                    onTap: () {
                      Navigator.of(context)
                          .pushReplacementNamed(ManageContent.routeName);
                    },
                    leading: const SidebarSvgIcon(
                        "assets/icons/icons-menu-files.svg"),
                    title: const Text("Manage Content")),
                ListTile(
                    onTap: () => changePage("Stats"),
                    leading: const SidebarSvgIcon(
                        "assets/icons/icons-menu-stats.svg"),
                    title: const Text("Payment Stats")),
                ListTile(
                    onTap: () => changePage("Logs"),
                    leading: const Icon(Icons.list_outlined),
                    title: const Text("Logs")),
                ListTile(
                    onTap: () => changePage("About"),
                    leading: const Icon(Icons.question_mark_outlined),
                    title: const Text("About Bison Relay")),
                ListTile(
                    onTap: shutdown,
                    leading: const Icon(Icons.exit_to_app),
                    title: const Text("Quit Bison Relay")),
              ],
            ));
  }
}

class AccountSettingsScreen extends StatelessWidget {
  final ClientModel client;
  final ResetKXCB resetAllKXCB;
  final ResetKXCB resetKXCB;
  final VoidCallback subAllPostsCB;
  final VoidCallback pickAvatarCB;
  final VoidCallback listKXs;
  const AccountSettingsScreen(this.client, this.resetAllKXCB, this.resetKXCB,
      this.pickAvatarCB, this.subAllPostsCB, this.listKXs,
      {super.key});

  Widget _settLabel(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 9),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant)),
      );

  Widget _settCard(ColorScheme cs, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _settChip(IconData icon, ColorScheme cs) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(9)),
        alignment: Alignment.center,
        child: Icon(icon, size: 19, color: cs.onSurfaceVariant),
      );

  Widget _settDivider(ColorScheme cs) =>
      Divider(height: 1, thickness: 1, indent: 66, color: cs.outlineVariant);

  Widget _settRow(ColorScheme cs,
          {required IconData icon,
          required String title,
          String? subtitle,
          Widget? trailing,
          VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            _settChip(icon, cs),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
            if (onTap != null && trailing == null)
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ]),
        ),
      );

  Widget _restyled(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Center(
          child: Column(children: [
            Stack(alignment: Alignment.center, children: [
              SizedBox(
                  width: 96,
                  height: 96,
                  child: SelfAvatar(client, onTap: pickAvatarCB)),
              Positioned(
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.surface, width: 2),
                    ),
                    child:
                        Icon(Icons.photo_camera, size: 16, color: cs.onPrimary),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(client.nick,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface)),
            const SizedBox(height: 2),
            Text("Tap the avatar to change it",
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: 24),
        _settLabel("Identity", cs),
        _settCard(cs, [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(children: [
              _settChip(Icons.fingerprint, cs),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Public identity",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                        "Your unique Bison Relay ID. Share it so others "
                        "can add you.",
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Copyable(client.publicID),
          ),
        ]),
        const SizedBox(height: 22),
        _settLabel("Relay Counter", cs),
        AnimatedBuilder(
          animation: client,
          builder: (context, _) => _settCard(cs, [
            _settRow(cs,
                icon: Icons.insights,
                title: "Relay Counter",
                subtitle: "Messages you've sent",
                trailing: Text("${client.msgsSent}",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: cs.primary))),
            _settDivider(cs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                _settChip(Icons.tag, cs),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Count Relays",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface)),
                      const SizedBox(height: 2),
                      Text("Show a running count of messages you send",
                          style: TextStyle(
                              fontSize: 12.5, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                    value: client.countRelays,
                    onChanged: (v) => client.setCountRelays(v)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        _settLabel("Account", cs),
        _settCard(cs, [
          _settRow(cs,
              icon: Icons.refresh,
              title: "Reset all KX",
              onTap: () => resetAllKXCB(context)),
          _settDivider(cs),
          _settRow(cs,
              icon: Icons.history,
              title: "Reset KX from users 30d stale",
              onTap: () => resetKXCB(context)),
          _settDivider(cs),
          _settRow(cs,
              icon: Icons.rss_feed,
              title: "Subscribe to all posts",
              onTap: () => subAllPostsCB()),
          _settDivider(cs),
          _settRow(cs,
              icon: Icons.list_alt,
              title: "List ongoing KX attempts",
              onTap: () => listKXs()),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (theme.areaStyle(ThemeArea.masterBackground).settingsShellRestyle) {
      return _restyled(context);
    }

    return Column(children: [
      const SizedBox(height: 10),
      SizedBox(
          width: 100,
          height: 100,
          child: SelfAvatar(client, onTap: pickAvatarCB)),
      const SizedBox(height: 10),
      Text(client.nick),
      const SizedBox(height: 10),
      Copyable(client.publicID),
      const SizedBox(height: 10),
      Expanded(
          child: ListView(children: [
        AnimatedBuilder(
          animation: client,
          builder: (context, _) => Column(children: [
            ListTile(
              title: const Text("Relay Counter"),
              subtitle: const Text("Messages you've sent"),
              trailing: Text("${client.msgsSent}"),
            ),
            SwitchListTile(
              title: const Text("Count Relays"),
              subtitle: const Text("Show a running count of messages you send"),
              value: client.countRelays,
              onChanged: (v) => client.setCountRelays(v),
            ),
          ]),
        ),
        const Divider(),
        ListTile(
          title: const Text("Reset all KX"),
          onTap: () => resetAllKXCB(context),
        ),
        ListTile(
          title: const Text("Reset KX from users 30d stale"),
          onTap: () => resetKXCB(context),
        ),
        ListTile(
          title: const Text("Subscribe to all posts"),
          onTap: () => subAllPostsCB(),
        ),
        ListTile(
          title: const Text("List ongoing KX attempts"),
          onTap: () => listKXs(),
        ),
      ]))
    ]);
  }
}

class AppearanceSettingsScreen extends StatefulWidget {
  final ClientModel client;
  final ThemeNotifier theme;
  const AppearanceSettingsScreen(this.client, this.theme, {super.key});
  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

/// This is the private State class that goes with MyStatefulWidget.
class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  ThemeNotifier get theme => widget.theme;
  ClientModel get client => widget.client;

  @override
  Widget build(BuildContext context) {
    var mainMenu = Provider.of<MainMenuModel>(context, listen: false);
    return Column(
      children: [
        // Kept outside the ListView (rather than as a pinned/sliver header)
        // so it stays fixed in place while the rest of the page scrolls --
        // the active preset and its actions are relevant no matter which
        // section below is being edited.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                  title: Txt.S("Active Theme: ${theme.presetDisplayName}")),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ThemeModeDropdown(theme, mainMenu),
                      OutlinedButton.icon(
                        onPressed: () => createNewPreset(theme),
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text("New Preset"),
                      ),
                      IconButton(
                        onPressed: () =>
                            importPresetFile(context, theme, mainMenu),
                        icon: const Icon(Icons.file_upload_outlined),
                        tooltip: "Import",
                      ),
                      IconButton(
                        onPressed: () => exportPresetFile(context, theme),
                        icon: const Icon(Icons.file_download_outlined),
                        tooltip: "Export",
                      ),
                      IconButton(
                        onPressed: () => resetToDefaultTheme(theme, mainMenu),
                        icon: const Icon(Icons.restart_alt_outlined),
                        tooltip: "Reset to Default",
                      ),
                      IconButton(
                        onPressed: () => savePreset(context, theme, mainMenu),
                        icon: const Icon(Icons.save_outlined),
                        tooltip: "Save",
                      ),
                      IconButton(
                        onPressed: theme.activePreset != null
                            ? () => deletePreset(context, theme)
                            : null,
                        icon: const Icon(Icons.delete_outline),
                        tooltip: "Delete",
                      ),
                    ]),
              ),
              const Divider(),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _SettingsGroupCard(
                theme: theme,
                child: const PaletteExpansionTile(),
              ),
              _SettingsGroupCard(
                theme: theme,
                child: ExpansionTile(
                  title: const Txt.S("Theme Areas"),
                  initiallyExpanded: client.ui.settingsNav.themeAreasExpanded,
                  onExpansionChanged: (v) =>
                      client.ui.settingsNav.themeAreasExpanded = v,
                  children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: AreasSection(
                          initialArea: client.ui.settingsNav.selectedThemeArea,
                          onAreaChanged: (a) =>
                              client.ui.settingsNav.selectedThemeArea = a,
                        ))
                  ],
                ),
              ),
              _SettingsGroupCard(
                theme: theme,
                child: ExpansionTile(
                  title: const Txt.S("Menu"),
                  initiallyExpanded: false,
                  children: const [MenuSection()],
                ),
              ),
              const Divider(),
              ListTile(
                title: const Txt.S("Message font size"),
                trailing: FontSizeDropdown(theme),
              ),
              if (kDebugMode) ...[
                const Divider(),
                ListTile(
                    title: const Text("Widget Test Screen"),
                    onTap: () {
                      Navigator.of(context, rootNavigator: true)
                          .pushNamed(ThemeTestScreen.routeName);
                    }),
                ListTile(
                    title: const Text("Unset Unkx Members Notice Flag"),
                    onTap: () async {
                      await StorageManager.saveBool(
                          StorageManager.notifiedGCUnkxdMembers, false);
                      if (context.mounted) {
                        showSuccessSnackbar(context, "Done");
                      }
                    })
              ]
            ],
          ),
        ),
      ],
    );
  }
}

// _SettingsGroupCard wraps one of the Appearance page's collapsible
// sections (Color Palette/Theme Areas/Menu) in a visibly distinct card, so
// they read as separate groups instead of blending into one long list.
// Uses surfaceContainerHigh explicitly (rather than relying on Card's own
// default M3 elevation tint) since the active preset's own
// surfaceContainerLow/Lowest tones are deliberately very subtle -- too
// close to the page background to read as a separate section on their own.
class _SettingsGroupCard extends StatelessWidget {
  final ThemeNotifier theme;
  final Widget child;
  const _SettingsGroupCard({required this.theme, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      color: theme.colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: child,
    );
  }
}

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool notificationsEnabled = false;
  bool foregroundService = false;
  bool pms = false;
  bool gcms = false;
  bool gcMentions = false;

  void loadSettings() async {
    var enabled = await StorageManager.readBool(StorageManager.notificationsKey,
        defaultVal: true);
    var fgSvc = await StorageManager.readBool(StorageManager.ntfnFgSvcKey);
    var newPms =
        await StorageManager.readBool(StorageManager.ntfnPMs, defaultVal: true);
    var newGcms = await StorageManager.readBool(StorageManager.ntfnGCMs);
    var mentions = await StorageManager.readBool(StorageManager.ntfnGCMentions,
        defaultVal: true);
    setState(() {
      notificationsEnabled = enabled;
      foregroundService = fgSvc;
      pms = newPms;
      gcms = newGcms;
      gcMentions = mentions;
    });
  }

  void updateEnabled(bool value) {
    StorageManager.saveData(StorageManager.notificationsKey, value);
    if (Platform.isAndroid) {
      Golib.setNtfnsEnabled(value);
    }
    setState(() => notificationsEnabled = value);

    // When disabling notifications, also disable foreground service.
    if (!value) updateForegroundSvc(false);
    NotificationService().updateUIConfig();
  }

  void updateForegroundSvc(bool value) {
    if (!Platform.isAndroid) {
      return;
    }

    StorageManager.saveData(StorageManager.ntfnFgSvcKey, value);
    if (value) {
      Golib.startForegroundSvc();
    } else {
      Golib.stopForegroundSvc();
    }

    setState(() => foregroundService = value);
  }

  void updatePMs(bool value) {
    StorageManager.saveData(StorageManager.ntfnPMs, value);
    setState(() => pms = value);
    NotificationService().updateUIConfig();
  }

  void updateGCMs(bool value) {
    StorageManager.saveData(StorageManager.ntfnGCMs, value);
    setState(() => gcms = value);
    NotificationService().updateUIConfig();
  }

  void updateGCMentions(bool value) {
    StorageManager.saveData(StorageManager.ntfnGCMentions, value);
    setState(() => gcMentions = value);
    NotificationService().updateUIConfig();
  }

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      // See https://github.com/MaikuB/flutter_local_notifications/issues/746
      return Container(
          padding: const EdgeInsets.all(10),
          alignment: Alignment.topLeft,
          child: const Text("Notifications are not supported on Windows"));
    }

    return ListView(children: [
      ListTile(
          title: const Text("Notifications"),
          trailing: Switch(
            value: notificationsEnabled,
            onChanged: updateEnabled,
          )),
      Platform.isAndroid
          ? ListTile(
              title: const Text("Use Foreground Service"),
              trailing: Switch(
                value: foregroundService,
                onChanged: updateForegroundSvc,
              ))
          : const Empty(),
      ListTile(
          title: const Text("Notify on PMs"),
          trailing: Switch(
            value: pms,
            onChanged: updatePMs,
          )),
      ListTile(
          title: const Text("Notify on GC Messages"),
          trailing: Switch(
            value: gcms,
            onChanged: updateGCMs,
          )),
      ListTile(
          title: const Text("Notify on GC Mentions"),
          trailing: Switch(
            value: gcMentions,
            onChanged: updateGCMentions,
          )),
      if (kDebugMode)
        ListTile(
          title: const Text("Test Notification"),
          onTap: () {
            NotificationService().testNotification();
          },
        )
    ]);
  }
}

class NetworkSettingsScreen extends StatefulWidget {
  final ClientModel client;
  const NetworkSettingsScreen(this.client, {super.key});
  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

/// This is the private State class that goes with MyStatefulWidget.
class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  ClientModel get client => widget.client;

  void connStateChanged() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    client.connState.addListener(connStateChanged);
  }

  @override
  void didUpdateWidget(NetworkSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != client) {
      oldWidget.client.connState.removeListener(connStateChanged);
      client.connState.addListener(connStateChanged);
    }
  }

  @override
  void dispose() {
    client.connState.removeListener(connStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget actionWidget;
    switch (client.connState.state.state) {
      case connStateOnline:
        actionWidget = ListTile(
            onTap: Golib.remainOffline,
            leading: const Icon(Icons.cloud_off),
            title: const Text("Remain Offline"));
        break;

      case connStateCheckingWallet:
        actionWidget = ListTile(
            onTap: Golib.skipWalletCheck,
            leading: const Icon(Icons.cloud_off),
            title: const Text("Skip Wallet Check"));
        break;

      case connStateOffline:
        actionWidget = ListTile(
            onTap: Golib.goOnline,
            leading: const Icon(Icons.cloud_done),
            title: const Text("Go Online"));
        break;

      default:
        actionWidget = const Empty();
        break;
    }

    var policy = client.connState.state.policy;
    var maxPayloadSize = maxMsgPayloadSize(policy.maxMsgSizeVersion);
    var pushDcrGbRate = policy.calcPushCostMAtoms(1000000000).toDouble() / 1e11;

    var isSmallScreen = checkIsScreenSmall(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListView(shrinkWrap: true, children: [
        ListTile(
            onTap: () => Navigator.of(context, rootNavigator: true)
                .pushNamed(ConfigNetworkScreen.routeName),
            leading: const Icon(Icons.network_ping),
            title: const Text("Proxy Settings")),
        actionWidget,
        // const Divider(),
        // const Txt.L("Server Policy"),
        // Txt("Max Message Payload Size: ${ibSize(maxPayloadSize)} (version ${policy.maxMsgSizeVersion})"),
        // Txt("Push Rate: ${pushDcrGbRate.toStringAsFixed(8)} DCR/GB (min ${formatDCR(milliatomsToDCR(policy.pushPayRateMinMAtoms))})"),
        // Txt("Subscription Rate: ${formatDCR(milliatomsToDCR(policy.subPayRate))}/RV"),
        // Txt("Expiration days: ${policy.expirationDays}"),
      ]),
      if (client.connState.isCheckingWallet &&
          client.connState.checkWalletErr != "") ...[
        Divider(),
        Container(
            padding: EdgeInsets.all(10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Copyable(
                      "Offline due to failed wallet check: ${client.connState.checkWalletErr}"),
                ]))
      ],
      if (client.connState.isOnline) ...[
        Divider(),
        Container(
            padding: EdgeInsets.all(10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Txt.L("Server Policy"),
                  const SizedBox(height: 5),
                  SimpleInfoGridAdv(
                      colLabelSize: isSmallScreen ? 100 : 200,
                      items: [
                        [
                          "Max Message Payload Size",
                          "${ibSize(maxPayloadSize)} (version ${policy.maxMsgSizeVersion})"
                        ],
                        [
                          "Push Rate",
                          "${pushDcrGbRate.toStringAsFixed(8)} DCR/GB (min ${formatDCR(milliatomsToDCR(policy.pushPayRateMinMAtoms))})"
                        ],
                        [
                          "Subscription Rate",
                          "${formatDCR(milliatomsToDCR(policy.subPayRate))}/RV"
                        ],
                        ["Expiration Days", "${policy.expirationDays}"],
                      ]),
                  if (policy.clientVersions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Txt.L("Suggested Client Versions"),
                    const SizedBox(height: 5),
                    SimpleInfoGridAdv(
                        colLabelSize: 80,
                        items: policy.clientVersions
                            .map((cv) => [cv.client, cv.version])
                            .toList()),
                  ],
                ]))
      ],
    ]);
  }
}

class AudioSettingsScreen extends StatefulWidget {
  final AudioModel audio;
  const AudioSettingsScreen({required this.audio, super.key});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  AudioModel get audio => widget.audio;
  AudioDevices devices = AudioDevices([], []);

  void listAudioDevices() async {
    if (Platform.isAndroid || Platform.isIOS) {
      var micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        showErrorSnackbar(this, "Microphone permission not given");
        return;
      }
    }

    try {
      var devs = await Golib.listAudioDevices();

      setState(() {
        devices = devs;
      });
    } catch (exception) {
      showErrorSnackbar(this, "Unable to list audio devices: $exception");
    }
  }

  void stopAudio() async {
    try {
      await audio.stop();
    } catch (exception) {
      showErrorSnackbar(this, "Unable to stop audio: $exception");
    }
  }

  void recordAudio() async {
    try {
      await audio.recordNote();
    } catch (exception) {
      showErrorSnackbar(this, "Unable to start audio recording: $exception");
    }
  }

  void playbackAudio() async {
    try {
      await audio.playbackNote();
    } catch (exception) {
      showErrorSnackbar(this, "Unable to start audio playback: $exception");
    }
  }

  void updated() {
    setState(() {});
  }

  void clearRecord() async {
    // Sleep is needed on slower computers to avoid recursive/locked setState
    // exceptions (because clearRecord is called from init/dispose).
    await sleep(const Duration(milliseconds: 1));
    audio.clearRecorded();
  }

  @override
  void initState() {
    super.initState();
    clearRecord();
    audio.addListener(updated);
    listAudioDevices();
  }

  @override
  void dispose() {
    super.dispose();
    audio.removeListener(updated);
    clearRecord();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Capture Device"),
          SizedBox(
              width: double.infinity,
              child: DropdownButton(
                  value: audio.captureDeviceId == ""
                      ? null
                      : audio.captureDeviceId,
                  items: devices.capture
                      .map<DropdownMenuItem<String?>>((e) =>
                          DropdownMenuItem<String?>(
                              value: e.id, child: Txt.S(e.name)))
                      .toList(),
                  onChanged: (newVal) {
                    if (newVal == null) {
                      return;
                    }
                    if (newVal == audio.captureDeviceId) {
                      return;
                    }
                    audio.captureDeviceId = newVal;
                  })),
          const SizedBox(height: 30),
          const Text("Playback Device"),
          SizedBox(
              width: double.infinity,
              child: DropdownButton(
                  value: audio.playbackDeviceId == ""
                      ? null
                      : audio.playbackDeviceId,
                  items: devices.playback
                      .map<DropdownMenuItem<String?>>((e) =>
                          DropdownMenuItem<String?>(
                              value: e.id, child: Txt.S(e.name)))
                      .toList(),
                  onChanged: (newVal) {
                    if (newVal == null) {
                      return;
                    }
                    if (newVal == audio.playbackDeviceId) {
                      return;
                    }
                    audio.playbackDeviceId = newVal;
                  })),
          const SizedBox(height: 30),
          Box(
            padding: const EdgeInsets.all(10),
            margin:
                const EdgeInsets.only(top: 2, bottom: 5, left: 10, right: 12),
            color: SurfaceColor.secondaryContainer,
            child: Wrap(spacing: 5, runSpacing: 10, children: [
              const Text("Microphone Volume"),
              VolumeGainControl(
                initialValue: audio.captureGain.value,
                onChanged: (value) async {
                  await audio.captureGain.set(value);
                },
              ),
            ]),
          ),
          const SizedBox(height: 30),
          Box(
            padding: const EdgeInsets.all(10),
            margin:
                const EdgeInsets.only(top: 2, bottom: 5, left: 10, right: 12),
            color: SurfaceColor.secondaryContainer,
            child: Wrap(spacing: 5, runSpacing: 10, children: [
              const Text("Output Volume"),
              VolumeGainControl(
                initialValue: audio.playbackGain.value,
                onChanged: (value) async {
                  await audio.playbackGain.set(value);
                },
              ),
            ]),
          ),
          Wrap(spacing: 10, runSpacing: 10, children: [
            TextButton.icon(
                onPressed:
                    !audio.recording && !audio.playing ? recordAudio : null,
                label: const Text("Record Audio Test"),
                icon: const Icon(Icons.record_voice_over_outlined)),
            if (audio.hasRecord)
              TextButton.icon(
                  onPressed:
                      !audio.recording && !audio.playing ? playbackAudio : null,
                  label: const Text("Play Audio Test"),
                  icon: const Icon(Icons.play_arrow_outlined)),
            if (audio.recording || audio.playing)
              TextButton.icon(
                  onPressed: stopAudio,
                  label: const Text("Stop"),
                  icon: const Icon(Icons.stop)),
          ]),
        ]));
  }
}

const _loremOneLine =
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua";

const _testMarkdownText = """This is a sample markdown text.

Following this is a code fence section.

```go
func TestOne(t *testing.T) {
  t.Parallel()
  var i uint32 = 1 << 10
  if i == 42 {
    t.Fatalf("You have made a mistake: %v", i)
  }
}
```

Following is a block quote section.

> This is a quote from
> somewhere that i found
> over the internet. There
> will be a second-level quote
> below:
>
>> Second-level quote now
>> full of some text
>> that explains things.

""";

class ThemeTestScreen extends StatelessWidget {
  static String routeName = "/themeTest";

  final ThemeNotifier theme;
  const ThemeTestScreen(this.theme, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        ThemeModeDropdown(
            theme, Provider.of<MainMenuModel>(context, listen: false)),
        FontSizeDropdown(theme),
        IconButton(
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () => Navigator.of(context).pop()),
      ]),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(40),
          child: Wrap(runSpacing: 20, spacing: 40, children: [
            // These are build "manually" for comparison. In parciular, on
            // material design v3, the "onXXXContainer" for primary and tertiary
            // are different on dark mode.
            const SizedBox(
                width: double.infinity,
                child: Text("The following are manually specified components")),

            Container(
              padding: const EdgeInsets.all(20),
              color: theme.colors.primaryContainer,
              constraints: const BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                const Text("Primary Container"),
                Text("Text with on color",
                    style: TextStyle(color: theme.colors.onPrimaryContainer)),
                const Text(
                  "Custom color text",
                  style: TextStyle(color: Colors.amber),
                )
              ]),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              color: theme.colors.tertiaryContainer,
              constraints: const BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                const Text("Tertiary Container"),
                Text("Text with on color",
                    style: TextStyle(color: theme.colors.onTertiaryContainer)),
                const Text(
                  "Custom color text",
                  style: TextStyle(color: Colors.amber),
                )
              ]),
            ),

            const Divider(),
            const SizedBox(
                width: double.infinity,
                child: Text("Containers specified with app components")),

            // Following are using the custom app components.

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.primaryContainer,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Primary Container"),
                Txt("Text with on color", color: TextColor.onPrimaryContainer),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.secondaryContainer,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Secondary Container"),
                Txt("Text with on color",
                    color: TextColor.onSecondaryContainer),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.tertiaryContainer,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Tertiary Container"),
                Txt("Text with on color", color: TextColor.onTertiaryContainer),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.errorContainer,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Error Container"),
                Txt("Text with on color", color: TextColor.onErrorContainer),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surface,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceContainer,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface Container"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceBright,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface bright"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceDim,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface dim"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceContainerLowest,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface container lowest"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceContainerLow,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface container low"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceContainerHigh,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface container high"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.surfaceContainerHighest,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Surface container highest"),
                Txt("Text with on color", color: TextColor.onSurface),
                Txt("Text with on variant color",
                    color: TextColor.onSurfaceVariant),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.inverseSurface,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Inverse Surface"),
                Txt("Text with on color", color: TextColor.onInverseSurface),
                Txt("Text with on inverse primary",
                    color: TextColor.inversePrimary),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const SizedBox(
                width: double.infinity,
                child: Txt("Text on surface (all defaults)")),

            const Divider(),
            const SizedBox(
                width: double.infinity,
                child: Text(
                    "Active colors (not usually used for containers, only for components)")),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.primary,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Primary"),
                Txt("Text with on color", color: TextColor.onPrimary),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.secondary,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Secondary"),
                Txt("Text with on color", color: TextColor.onSecondary),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.tertiary,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Tertiary"),
                Txt("Text with on color", color: TextColor.onTertiary),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.error,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Error"),
                Txt("Text with on color", color: TextColor.onError),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Box(
              padding: EdgeInsets.all(20),
              color: SurfaceColor.inversePrimary,
              constraints: BoxConstraints.tightFor(width: 400),
              child: Column(children: [
                Text("Inverse Primary"),
                Text("(used when the background surface is inverseSurface)"),
                Txt("Text with on color", color: TextColor.onSurface),
                Text("Custom color text", style: TextStyle(color: Colors.amber))
              ]),
            ),

            const Divider(),
            const SizedBox(width: double.infinity, child: Text("Typography")),

            const SizedBox(
                width: double.infinity, child: Txt.S("Small $_loremOneLine")),
            const SizedBox(
                width: double.infinity, child: Txt("System $_loremOneLine")),
            const SizedBox(
                width: double.infinity, child: Txt.M("Medium $_loremOneLine")),
            const SizedBox(
                width: double.infinity, child: Txt.L("Large $_loremOneLine")),
            const SizedBox(
                width: double.infinity, child: Txt.H("Huge $_loremOneLine")),

            const Divider(),
            const SizedBox(width: double.infinity, child: Text("Components")),

            Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints.tightFor(width: 400),
              child: Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  const SizedBox(
                      width: double.infinity, child: Text("Buttons")),
                  ElevatedButton(
                      onPressed: () {}, child: const Text("Elevated Button")),
                  TextButton(
                      onPressed: () {}, child: const Text("Text Button")),
                  FilledButton(
                      onPressed: () {}, child: const Text("Filled Button")),
                  FilledButton.tonal(
                      onPressed: () {},
                      child: const Text("Filled Tonal Button")),
                  OutlinedButton(
                      onPressed: () {}, child: const Text("Outlined Button")),
                  CancelButton(onPressed: () {}),
                  IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.baby_changing_station_rounded)),
                  FloatingActionButton.small(
                      heroTag: "test.fab.small",
                      onPressed: () {},
                      child: const Icon(Icons.settings)),
                  FloatingActionButton.large(
                      heroTag: "test.fab.large",
                      key: const Key("test.fab.large"),
                      onPressed: () {},
                      child: const Icon(Icons.checklist_sharp)),
                  FloatingActionButton.extended(
                      heroTag: "test.fab.extended",
                      key: const Key("test.fab.extended"),
                      onPressed: () {},
                      label: const Text("Do the thing"),
                      icon: const Icon(Icons.account_tree)),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints.tightFor(width: 400),
              child: const Wrap(
                spacing: 20,
                runSpacing: 10,
                children: [
                  SizedBox(
                      width: double.infinity, child: Text("Disabled Buttons")),
                  ElevatedButton(
                      onPressed: null, child: Text("Elevated Button")),
                  TextButton(onPressed: null, child: Text("Text Button")),
                  FilledButton(onPressed: null, child: Text("Filled Button")),
                  FilledButton.tonal(
                      onPressed: null, child: Text("Filled Tonal Button")),
                  OutlinedButton(
                      onPressed: null, child: Text("Outlined Button")),
                  CancelButton(onPressed: null),
                  IconButton(
                      onPressed: null,
                      icon: Icon(Icons.baby_changing_station_rounded)),
                  FloatingActionButton.small(
                      heroTag: "test.fab.small.disabled",
                      onPressed: null,
                      child: Icon(Icons.settings)),
                  FloatingActionButton.large(
                      heroTag: "test.fab.large.disabled",
                      onPressed: null,
                      child: Icon(Icons.checklist_sharp)),
                  FloatingActionButton.extended(
                      heroTag: "test.fab.extended.disabled",
                      onPressed: null,
                      label: Text("Do the thing"),
                      icon: Icon(Icons.account_tree)),
                ],
              ),
            ),

            Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints.tightFor(width: 800),
                child: Wrap(spacing: 20, runSpacing: 10, children: [
                  const SizedBox(width: double.infinity, child: Text("List")),
                  SizedBox(
                      height: 180,
                      child: ListView.builder(
                          itemCount: 10,
                          itemBuilder: (context, index) => ListTile(
                                selected: index == 6,
                                title: Txt.S("Item $index"),
                                onTap: () {},
                              )))
                ])),

            Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints.tightFor(width: 400),
                child: MarkdownArea(_testMarkdownText, false)),
          ])),
    );
  }
}
