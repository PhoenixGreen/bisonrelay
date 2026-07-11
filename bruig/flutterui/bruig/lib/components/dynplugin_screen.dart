import 'dart:async';

import 'package:bruig/components/containers.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/dynplugins.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// DynPluginScreen is the one generic screen every dynamic-wasm plugin's
/// nav item points at (see DynPluginsModel): it renders whichever of the
/// plugin's declared [screens] is active by interpreting the DynScreenUI
/// JSON the plugin's WebAssembly module returns, and forwards
/// button/switch/list-item activations back to the plugin as events. No
/// plugin-specific Dart code exists anywhere in this widget -- the RSS
/// plugin's "My Feeds"/"Add Feed"/"RSS Settings" pages are just data this
/// widget happens to be showing.
class DynPluginScreen extends StatefulWidget {
  final String pluginId;
  final List<ScreenDef> screens;
  const DynPluginScreen(this.pluginId, this.screens, {super.key});

  @override
  State<DynPluginScreen> createState() => _DynPluginScreenState();
}

class _DynPluginScreenState extends State<DynPluginScreen> {
  String? activeScreen;
  DynScreenUI? ui;
  bool loading = false;
  String? error;
  StreamSubscription<String>? _updateSub;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.screens.isNotEmpty) {
      activeScreen = widget.screens.first.id;
    }
    _load();

    // Fired after a background poll (e.g. the RSS plugin fetching new feed
    // items) completes, so this screen picks up new data live rather than
    // only on next manual navigation. Goes through DynPluginsModel's
    // re-broadcast stream, not Golib.dynPluginScreenUpdated() directly --
    // that one is single-subscription and this widget gets recreated each
    // time its nav item is visited, so a second raw .listen() here would
    // throw "Stream has already been listened to."
    var dynPlugins = Provider.of<DynPluginsModel>(context, listen: false);
    _updateSub = dynPlugins.pluginScreenUpdated.listen((pluginId) {
      if (pluginId == widget.pluginId && mounted) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    for (var c in _controllers.values) {
      c.dispose();
    }
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
      // Sync existing textfield controllers to the server's canonical
      // value (e.g. clearing the URL field after a successful Add Feed)
      // -- but only after a user-initiated event, not on every _load(),
      // so an in-progress-poll refresh can't wipe out unrelated typing.
      _syncControllersToUI(res);
    } catch (exception) {
      if (!mounted) return;
      showErrorSnackbar(context, "Unable to perform action: $exception");
    }
  }

  TextEditingController _controllerFor(String name, String initialValue) {
    return _controllers.putIfAbsent(
        name, () => TextEditingController(text: initialValue));
  }

  void _syncControllersToUI(DynScreenUI ui) {
    void walk(List<DynWidget> ws) {
      for (var w in ws) {
        if (w.type == "textfield" && w.name.isNotEmpty) {
          var existing = _controllers[w.name];
          if (existing != null && existing.text != w.value) {
            existing.text = w.value;
          }
        }
        walk(w.items);
      }
    }

    walk(ui.widgets);
  }

  // _collectValues walks the whole current screen's widget tree gathering
  // every named field's current value, so a button's tap event carries the
  // full form state alongside it (mirroring how components/pages/forms.dart
  // collects field values on submit).
  Map<String, dynamic> _collectValues(List<DynWidget> widgets) {
    var values = <String, dynamic>{};
    void walk(List<DynWidget> ws) {
      for (var w in ws) {
        if (w.name.isNotEmpty) {
          values[w.name] =
              w.type == "switch" ? w.boolValue : _controllers[w.name]?.text;
        }
        walk(w.items);
      }
    }

    walk(widgets);
    return values;
  }

  Widget _buildWidget(DynWidget w, List<DynWidget> root) {
    switch (w.type) {
      case "text":
        var color = w.danger
            ? TextColor.error
            : (w.muted ? TextColor.onSurfaceVariant : null);
        if (w.openUrl.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: InkWell(
              onTap: () => launchUrl(Uri.parse(w.openUrl)),
              child: Txt.S(w.text,
                  color: color,
                  style: const TextStyle(decoration: TextDecoration.underline)),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Txt.S(w.text, color: color),
        );

      case "textfield":
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: TextFormField(
            controller: _controllerFor(w.name, w.value),
            decoration: InputDecoration(labelText: w.hint, hintText: w.hint),
          ),
        );

      case "switch":
        return SwitchListTile(
          title: Txt.S(w.text),
          value: w.boolValue,
          onChanged: (v) => _handleEvent(w.event, {w.name: v}),
        );

      case "button":
        void onPressed() {
          // _collectValues gathers named textfield/switch values from the
          // whole screen (e.g. "Add Feed"'s url field); a button's own
          // Value (e.g. an item id for a per-item action button like a
          // bookmark toggle) isn't a named field, so it's added separately
          // under "value" to match the convention list items already use.
          var payload = _collectValues(root);
          if (w.value.isNotEmpty) payload["value"] = w.value;
          _handleEvent(w.event, payload);
        }
        // Muted here is a style hint meaning "secondary/plain action"
        // (e.g. a back button), distinct from its list-item meaning of
        // "already read" -- reusing one bool for "de-emphasize this"
        // across widget types rather than adding a type-specific field.
        var button = w.muted
            ? TextButton(onPressed: onPressed, child: Text(w.text))
            : ElevatedButton(
                style: w.danger
                    ? ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.red)
                    : null,
                onPressed: onPressed,
                child: Text(w.text),
              );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // Without this, the button stretches to the full row width
          // inside the ListView and centers its label, reading as an odd
          // full-width pill rather than a normal compact button.
          child: Align(alignment: Alignment.centerLeft, child: button),
        );

      case "list":
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: w.items.map(_buildListItem).toList(),
        );

      default:
        debugPrint("dynplugin_screen: unknown widget type '${w.type}'");
        return const SizedBox.shrink();
    }
  }

  Widget _buildListItem(DynWidget item) {
    // Non-danger events (e.g. "open this post") fire on tapping the row
    // itself, matching typical list-navigation UX; danger events (e.g.
    // "remove this feed") stay on the explicit trailing icon only, so a
    // stray tap can't trigger a destructive action.
    VoidCallback? onTap;
    if (item.event.isNotEmpty && !item.danger) {
      onTap = () => _handleEvent(item.event, {"value": item.value});
    } else if (item.openUrl.isNotEmpty) {
      onTap = () => launchUrl(Uri.parse(item.openUrl));
    }

    // bookmarkable/bookmarked add a star toggle independent of the row's
    // primary tap action, always via the conventional "toggleBookmark"
    // event (see wasmhost's Widget doc) -- a plugin opts in per item by
    // setting Bookmarkable, it doesn't pick the event name itself.
    var trailingIcons = <Widget>[];
    if (item.bookmarkable) {
      trailingIcons.add(IconButton(
        icon: Icon(item.bookmarked ? Icons.star : Icons.star_border,
            color: item.bookmarked ? Colors.amber : null),
        onPressed: () =>
            _handleEvent("toggleBookmark", {"value": item.value}),
      ));
    }
    if (item.danger && item.event.isNotEmpty) {
      trailingIcons.add(IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => _handleEvent(item.event, {"value": item.value}),
      ));
    }

    return ListTile(
      title:
          Txt.S(item.text, color: item.muted ? TextColor.onSurfaceVariant : null),
      subtitle: item.hint.isNotEmpty ? Txt.S(item.hint) : null,
      trailing: trailingIcons.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: trailingIcons),
      onTap: onTap,
    );
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
        ...screenUI.widgets.map((w) => _buildWidget(w, screenUI.widgets)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var content = _buildContent();

    if (checkIsScreenSmall(context) || widget.screens.length < 2) {
      return content;
    }

    return Row(children: [
      SecondarySideMenuList(
        width: 180,
        items: widget.screens
            .map((s) => ListTile(
                  selected: activeScreen == s.id,
                  title: Txt.S(s.label),
                  onTap: () => changeScreen(s.id),
                ))
            .toList(),
      ),
      Expanded(child: content),
    ]);
  }
}
