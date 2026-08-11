import 'dart:async';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/plugin_nav.dart';
import 'package:bruig/plugin_system/screens/widget_renderer.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/theming_system/runtime/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';

/// PluginScreen is the one generic screen every screen-contributing plugin's
/// nav item points at (see PluginNavModel): it renders whichever of the
/// plugin's declared [screens] is active by interpreting the DynScreenUI JSON
/// the plugin's WebAssembly module returns, and forwards activations back to
/// the plugin as events. No plugin-specific Dart code exists anywhere in this
/// widget -- the RSS plugin's "My Feeds"/"Add Feed"/"RSS Settings" pages are
/// just data this widget happens to be showing.
///
/// It owns the page: the sub-page navigation, the load and error states, and
/// the round trip to the plugin. Drawing the tree itself belongs to
/// widget_renderer.dart, which this shares with every other place a plugin
/// contributes UI -- see plugin_slots.dart.
class PluginScreen extends StatefulWidget {
  final String pluginId;
  final List<ScreenDef> screens;
  const PluginScreen(this.pluginId, this.screens, {super.key});

  @override
  State<PluginScreen> createState() => _PluginScreenState();
}

class _PluginScreenState extends State<PluginScreen> {
  String? activeScreen;
  DynScreenUI? ui;
  bool loading = false;
  String? error;
  StreamSubscription<String>? _updateSub;
  final PluginUiState _uiState = PluginUiState();

  @override
  void initState() {
    super.initState();
    if (widget.screens.isNotEmpty) {
      activeScreen = widget.screens.first.id;
    }
    _load();

    // Fired after a background poll (e.g. the RSS plugin fetching new feed
    // items) completes, so this screen picks up new data live rather than
    // only on next manual navigation. Goes through PluginNavModel's
    // re-broadcast stream, not Golib.dynPluginScreenUpdated() directly --
    // that one is single-subscription and this widget gets recreated each
    // time its nav item is visited, so a second raw .listen() here would
    // throw "Stream has already been listened to."
    var nav = Provider.of<PluginNavModel>(context, listen: false);
    _updateSub = nav.pluginScreenUpdated.listen((pluginId) {
      if (pluginId == widget.pluginId && mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    _uiState.dispose();
    super.dispose();
  }

  void changeScreen(String screenId) {
    if (screenId == activeScreen) return;
    setState(() {
      activeScreen = screenId;
      ui = null;
      error = null;
    });
    _load();
  }

  void _load() async {
    var screenId = activeScreen;
    if (screenId == null) return;
    setState(() => loading = true);
    try {
      var res = await Golib.renderDynPluginScreen(widget.pluginId, screenId);
      if (!mounted || activeScreen != screenId) return;
      setState(() {
        ui = res;
        loading = false;
        error = null;
      });
    } catch (exception) {
      if (!mounted || activeScreen != screenId) return;
      setState(() {
        loading = false;
        error = "Unable to render screen: $exception";
      });
    }
  }

  void _handleEvent(String event, Map<String, dynamic> payload) async {
    var screenId = activeScreen;
    if (screenId == null || event.isEmpty) return;
    try {
      var res = await Golib.handleDynPluginEvent(
          widget.pluginId, screenId, event, payload);
      if (!mounted || activeScreen != screenId) return;
      setState(() => ui = res);
      // Adopt the plugin's canonical field values -- clearing the URL field
      // after a successful Add Feed. Only after a user-initiated event, never
      // on a background _load(), so an in-progress poll cannot wipe out
      // unrelated typing.
      _uiState.syncToUi(res.widgets);
    } catch (exception) {
      if (!mounted) return;
      showErrorSnackbar(context, "Unable to perform action: $exception");
    }
  }

  Widget _buildContent() {
    if (error != null) {
      return Center(child: Txt.S(error!, color: TextColor.error));
    }
    if (loading && ui == null) {
      return const Center(child: CircularProgressIndicator());
    }
    var screenUI = ui;
    if (screenUI == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Txt.L(screenUI.title),
        const SizedBox(height: 10),
        ...buildPluginWidgets(
          context,
          screenUI.widgets,
          root: screenUI.widgets,
          state: _uiState,
          onEvent: _handleEvent,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildContent();

    if (checkIsScreenSmall(context) || widget.screens.length < 2) {
      return content;
    }

    return SecondarySideMenuLayout(
      storageKey: "pluginScreens",
      items: widget.screens
          .map((s) => SidebarNavItem(
                selected: activeScreen == s.id,
                label: s.label,
                onTap: () => changeScreen(s.id),
              ))
          .toList(),
      content: content,
    );
  }
}
