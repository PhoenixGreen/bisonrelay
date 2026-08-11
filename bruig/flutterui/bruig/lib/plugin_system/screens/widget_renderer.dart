import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/plugin_icons.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:url_launcher/url_launcher.dart';

// widget_renderer.dart interprets the declarative widget tree a plugin returns
// and turns it into Flutter widgets. It is the whole of what a plugin can draw
// and the whole of what the app will draw on a plugin's behalf.
//
// Nothing here is specific to any plugin, and nothing here executes anything a
// plugin sent: a widget tree is data, so the worst a malicious plugin can do
// is describe an ugly screen. That is the property that makes this safe to
// point at more places than the plugin's own tab -- see plugin_slots.dart.
//
// Two rules govern how it grows:
//
//   - An unknown widget type renders nothing rather than failing the screen,
//     so a plugin built against a later host degrades to the parts both sides
//     understand. Combined with the manifest's schema version, a plugin can
//     tell in advance and offer something simpler.
//
//   - Anything specific to one widget type is read from that widget's props
//     rather than from a field of its own, so adding a type is a case in this
//     file and touches neither the Go ABI nor the generated Dart model.
//
// Every value out of props is coerced defensively. It arrived as whatever
// JSON a plugin wrote, and a number where a string was expected must not be a
// crash in the host.

/// PluginEventSink is how an activated widget reports back to its plugin.
typedef PluginEventSink = void Function(
    String event, Map<String, dynamic> payload);

/// PluginUiState owns the text controllers behind one rendered tree, so a
/// field keeps what was typed in it across the rebuilds that follow every
/// event, and so a button can gather the whole form when it is pressed.
///
/// Held by whatever hosts the tree -- a screen, a slot -- rather than by the
/// renderer, because the tree is rebuilt from scratch on each render and the
/// controllers must not be.
class PluginUiState {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController controllerFor(String name, String initialValue) =>
      _controllers.putIfAbsent(
          name, () => TextEditingController(text: initialValue));

  /// collectValues walks the tree gathering every named field's current
  /// value, so a button's event carries the whole form state alongside it.
  Map<String, dynamic> collectValues(List<DynWidget> widgets) {
    var values = <String, dynamic>{};
    void walk(List<DynWidget> ws) {
      for (var w in ws) {
        if (w.name.isNotEmpty) {
          values[w.name] = switch (w.type) {
            "switch" || "checkbox" => w.boolValue,
            "dropdown" => _controllers[w.name]?.text ?? w.value,
            _ => _controllers[w.name]?.text,
          };
        }
        walk(w.items);
      }
    }

    walk(widgets);
    return values;
  }

  /// syncToUi adopts the plugin's canonical values -- clearing the URL field
  /// after a successful "Add Feed", say.
  ///
  /// Called only after a user-initiated event, never on a background refresh:
  /// a poll landing mid-sentence must not wipe out unrelated typing.
  void syncToUi(List<DynWidget> widgets) {
    void walk(List<DynWidget> ws) {
      for (var w in ws) {
        if ((w.type == "textfield" || w.type == "dropdown") &&
            w.name.isNotEmpty) {
          var existing = _controllers[w.name];
          if (existing != null && existing.text != w.value) {
            existing.text = w.value;
          }
        }
        walk(w.items);
      }
    }

    walk(widgets);
  }

  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }
}

/// buildPluginWidgets renders [widgets] as children for a column or list.
///
/// [root] is the whole tree the values of a button press are gathered from,
/// which is not always [widgets] -- a nested row's button still submits the
/// entire form around it.
List<Widget> buildPluginWidgets(
  BuildContext context,
  List<DynWidget> widgets, {
  required List<DynWidget> root,
  required PluginUiState state,
  required PluginEventSink onEvent,
}) =>
    [
      for (var w in widgets)
        buildPluginWidget(context, w, root: root, state: state, onEvent: onEvent)
    ];

/// buildPluginWidget renders one node.
Widget buildPluginWidget(
  BuildContext context,
  DynWidget w, {
  required List<DynWidget> root,
  required PluginUiState state,
  required PluginEventSink onEvent,
}) {
  List<Widget> children() => buildPluginWidgets(context, w.items,
      root: root, state: state, onEvent: onEvent);

  switch (w.type) {
    case "text":
      return _text(context, w);

    case "textfield":
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          controller: state.controllerFor(w.name, w.value),
          obscureText: _bool(w.props, "obscure"),
          minLines: _bool(w.props, "multiline") ? 3 : 1,
          maxLines: _bool(w.props, "multiline") ? 8 : 1,
          decoration: InputDecoration(labelText: w.hint, hintText: w.hint),
        ),
      );

    case "switch":
      return SwitchListTile(
        title: Txt.S(w.text),
        value: w.boolValue,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) => onEvent(w.event, {w.name: v}),
      );

    case "checkbox":
      return CheckboxListTile(
        title: Txt.S(w.text),
        value: w.boolValue,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => onEvent(w.event, {w.name: v ?? false}),
      );

    case "dropdown":
      return _dropdown(context, w, state, onEvent);

    case "button":
      return _button(context, w, root: root, state: state, onEvent: onEvent);

    case "list":
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var item in w.items) _listItem(context, item, onEvent),
        ],
      );

    // section is a heading over a group. It was documented in the ABI long
    // before it was implemented here, so a plugin using it rendered nothing
    // at all -- silently, because an unknown type is skipped by design.
    case "section":
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (w.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Txt.S(w.text,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ...children(),
        ]),
      );

    case "row":
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: _rowAlign(_string(w.props, "align")),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children(),
        ),
      );

    case "column":
      return Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children());

    case "card":
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (w.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Txt.S(w.text,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ...children(),
            ],
          ),
        ),
      );

    case "divider":
      return const Divider(height: 17);

    case "spacer":
      return SizedBox(height: _double(w.props, "size") ?? 8);

    case "image":
      return _image(w);

    case "icon":
      var theme = ThemeNotifier.of(context);
      return Icon(
        pluginIcon(_string(w.props, "icon")),
        size: _double(w.props, "size") ?? 20,
        // Resolved through the theme rather than taken literally: a plugin
        // names a role and the active palette decides the colour, so a plugin
        // cannot draw something illegible against the user's own background.
        color: switch (w) {
          _ when w.danger => theme.textColor(TextColor.error),
          _ when w.muted => theme.textColor(TextColor.onSurfaceVariant),
          _ => null,
        },
      );

    case "progress":
      var value = _double(w.props, "value");
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(
          // Absent means indeterminate, which is the honest rendering for a
          // plugin that knows it is working but not how far along it is.
          value: value?.clamp(0.0, 1.0),
        ),
      );

    default:
      // Deliberately silent in release: this is how a plugin built against a
      // newer host degrades. Logged in debug so a plugin author developing
      // against this build can see the typo they made.
      assert(() {
        debugPrint("plugin widget renderer: unknown widget type '${w.type}'");
        return true;
      }());
      return const SizedBox.shrink();
  }
}

Widget _text(BuildContext context, DynWidget w) {
  var color = w.danger
      ? TextColor.error
      : (w.muted ? TextColor.onSurfaceVariant : null);
  var body = Txt.S(w.text,
      color: color,
      style: w.openUrl.isNotEmpty
          ? const TextStyle(decoration: TextDecoration.underline)
          : null);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: w.openUrl.isEmpty
        ? body
        : InkWell(onTap: () => _open(w.openUrl), child: body),
  );
}

Widget _dropdown(BuildContext context, DynWidget w, PluginUiState state,
    PluginEventSink onEvent) {
  var options = _options(w.props);
  // The selection rides in the same controller a textfield would use, so
  // collectValues finds it without a special case and so the plugin's own
  // canonical value can be synced back after an event.
  var controller = state.controllerFor(w.name, w.value);
  var current = options.any((o) => o.$1 == controller.text)
      ? controller.text
      : (options.isEmpty ? null : options.first.$1);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: InputDecorator(
      decoration: InputDecoration(labelText: w.hint, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: current,
          isExpanded: true,
          items: [
            for (var (value, label) in options)
              DropdownMenuItem(value: value, child: Txt.S(label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            controller.text = v;
            if (w.event.isNotEmpty) onEvent(w.event, {w.name: v});
          },
        ),
      ),
    ),
  );
}

Widget _button(
  BuildContext context,
  DynWidget w, {
  required List<DynWidget> root,
  required PluginUiState state,
  required PluginEventSink onEvent,
}) {
  void onPressed() {
    if (w.event.isEmpty && w.openUrl.isNotEmpty) {
      _open(w.openUrl);
      return;
    }
    // The named fields from the whole screen, plus this button's own value
    // under "value" -- a per-item action (a bookmark toggle, a row's delete)
    // is not a named field but still has to say which item it was.
    var payload = state.collectValues(root);
    if (w.value.isNotEmpty) payload["value"] = w.value;
    onEvent(w.event, payload);
  }

  var icon = pluginIconOrNull(_string(w.props, "icon"));
  var label = Text(w.text);

  // muted means "secondary action" on a button (a back link), distinct from
  // its list-item sense of "already read" -- one flag for "de-emphasize
  // this", read in the way each widget type can honour.
  Widget button;
  if (w.muted) {
    button = icon == null
        ? TextButton(onPressed: onPressed, child: label)
        : TextButton.icon(
            onPressed: onPressed, icon: Icon(icon, size: 18), label: label);
  } else {
    var style = w.danger
        ? ElevatedButton.styleFrom(
            foregroundColor: Colors.white, backgroundColor: Colors.red)
        : null;
    button = icon == null
        ? ElevatedButton(onPressed: onPressed, style: style, child: label)
        : ElevatedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: label);
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    // Without this the button stretches to the full row width inside a
    // ListView and centres its label, reading as an odd full-width pill.
    child: Align(alignment: Alignment.centerLeft, child: button),
  );
}

Widget _listItem(
    BuildContext context, DynWidget item, PluginEventSink onEvent) {
  // A non-destructive event fires on tapping the row, matching ordinary list
  // navigation; a destructive one stays on its explicit trailing icon, so a
  // stray tap cannot delete anything.
  VoidCallback? onTap;
  if (item.event.isNotEmpty && !item.danger) {
    onTap = () => onEvent(item.event, {"value": item.value});
  } else if (item.openUrl.isNotEmpty) {
    onTap = () => _open(item.openUrl);
  }

  var trailing = <Widget>[];
  // bookmarkable/bookmarked add a star toggle independent of the row's own
  // tap action, always via the conventional "toggleBookmark" event -- a
  // plugin opts in per item rather than naming the event itself.
  if (item.bookmarkable) {
    trailing.add(IconButton(
      icon: Icon(item.bookmarked ? Icons.star : Icons.star_border,
          color: item.bookmarked ? Colors.amber : null),
      onPressed: () => onEvent("toggleBookmark", {"value": item.value}),
    ));
  }
  if (item.danger && item.event.isNotEmpty) {
    trailing.add(IconButton(
      icon: const Icon(Icons.delete_outline, color: Colors.red),
      onPressed: () => onEvent(item.event, {"value": item.value}),
    ));
  }

  var leading = pluginIconOrNull(_string(item.props, "icon"));
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: leading == null ? null : Icon(leading),
    title: Txt.S(item.text,
        color: item.muted ? TextColor.onSurfaceVariant : null),
    subtitle: item.hint.isNotEmpty ? Txt.S(item.hint) : null,
    trailing: trailing.isEmpty
        ? null
        : Row(mainAxisSize: MainAxisSize.min, children: trailing),
    onTap: onTap,
  );
}

/// _image renders bytes the plugin supplied itself.
///
/// Bytes rather than a URL on purpose. A URL in a widget tree would make
/// merely opening a screen into a network request to somewhere the plugin
/// chose -- a tracking pixel the user never agreed to, outside the proxied
/// fetch_url path everything else goes through. A plugin that wants a remote
/// image fetches it through the host and sends what it got.
Widget _image(DynWidget w) {
  Uint8List? bytes;
  try {
    var raw = _string(w.props, "dataB64");
    if (raw.isNotEmpty) bytes = base64Decode(raw);
  } catch (_) {
    bytes = null;
  }
  if (bytes == null) return const SizedBox.shrink();

  var height = _double(w.props, "height");
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Image.memory(
      bytes,
      height: height,
      fit: height == null ? BoxFit.contain : BoxFit.cover,
      // A plugin can send bytes that are not an image; that is its mistake to
      // make and must not take the screen down with it.
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    ),
  );
}

void _open(String url) {
  var uri = Uri.tryParse(url);
  // Only the two schemes a link in a plugin screen can reasonably mean.
  // Anything else -- file:, javascript:, a custom scheme registered by some
  // other application -- is not something a plugin gets to hand the OS.
  if (uri == null || (uri.scheme != "http" && uri.scheme != "https")) return;
  launchUrl(uri);
}

MainAxisAlignment _rowAlign(String align) => switch (align) {
      "center" => MainAxisAlignment.center,
      "end" => MainAxisAlignment.end,
      "between" => MainAxisAlignment.spaceBetween,
      _ => MainAxisAlignment.start,
    };

/// _options reads a dropdown's choices, accepting either a list of
/// {"value","label"} objects or a bare list of strings, since a plugin whose
/// values and labels are the same thing should not have to write both.
List<(String, String)> _options(Map<String, dynamic> props) {
  var raw = props["options"];
  if (raw is! List) return const [];
  var out = <(String, String)>[];
  for (var entry in raw) {
    if (entry is String) {
      out.add((entry, entry));
    } else if (entry is Map) {
      var value = entry["value"]?.toString() ?? "";
      if (value.isEmpty) continue;
      out.add((value, entry["label"]?.toString() ?? value));
    }
  }
  return out;
}

String _string(Map<String, dynamic> props, String key) =>
    props[key]?.toString() ?? "";

bool _bool(Map<String, dynamic> props, String key) => props[key] == true;

/// _double accepts a number or a string holding one, and returns null for
/// anything else -- which every caller reads as "not specified".
double? _double(Map<String, dynamic> props, String key) {
  var raw = props[key];
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}
