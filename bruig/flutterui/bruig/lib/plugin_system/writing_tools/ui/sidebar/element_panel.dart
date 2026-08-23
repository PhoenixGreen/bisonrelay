import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/element_specs.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// element_panel.dart is the Pages and store panel: the blocks a page is
// built from, what each can be told, and what it does when told nothing.
//
// Two steps down rather than one dialog. Picking a block shows what it can
// be told, with the answer it already gives marked; picking one of those
// shows what it will take. Nothing is written until Insert, so choosing four
// settings writes one block rather than four.
//
// The alternative was a button per block that wrote it and left the writer
// to find out the rest from the markdown. That is what this replaces: every
// setting here is one that was already understood and nowhere offered.

/// insertBlock puts [text] in at the caret, on lines of its own.
///
/// Separated from what surrounds it without piling up blank lines where
/// there already are some -- the same bargain the snippet buttons make, and
/// for the same reason: a block run onto the end of a paragraph is not a
/// block.
void insertBlock(TextEditingController editor, String text) {
  var value = editor.value;
  var selection = value.selection;
  var at = selection.isValid ? selection.start : value.text.length;
  var end = selection.isValid ? selection.end : value.text.length;

  var before = value.text.substring(0, at);
  var after = value.text.substring(end);

  var lead = before.isEmpty || before.endsWith("\n\n")
      ? ""
      : (before.endsWith("\n") ? "\n" : "\n\n");
  var tail = after.isEmpty || after.startsWith("\n") ? "" : "\n";

  editor.value = TextEditingValue(
    text: "$before$lead$text$tail$after",
    selection:
        TextSelection.collapsed(offset: before.length + lead.length + text.length),
  );
}

/// parseHexColour reads the hex a banner is written with: #rgb, #rrggbb or
/// #rrggbbaa. Anything else is nothing, which is what the banner itself does
/// with it.
Color? parseHexColour(String? raw) {
  var t = (raw ?? "").trim();
  if (!t.startsWith("#")) return null;
  var hex = t.substring(1);
  if (hex.length == 3) {
    hex = hex.split("").map((c) => "$c$c").join();
  }
  // Written as #rrggbb or #rrggbbaa, wanted as ARGB. Handled as two
  // separate cases rather than by padding and then reordering: padding
  // first makes a six-digit colour look like an eight-digit one, and the
  // reorder then moves an alpha that was never written -- which turned
  // #ff0000 into a transparent cyan.
  var argb = switch (hex.length) {
    6 => "ff$hex",
    8 => hex.substring(6) + hex.substring(0, 6),
    _ => null,
  };
  if (argb == null) return null;
  var n = int.tryParse(argb, radix: 16);
  return n == null ? null : Color(n);
}

/// hexOf writes a colour the way a banner reads one, keeping the alpha only
/// when there is some to keep -- #ffffff rather than #ffffffff, because that
/// is what anybody would have typed.
String hexOf(Color c) {
  String two(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, "0");
  var rgb = "#${two(c.r)}${two(c.g)}${two(c.b)}";
  return c.a >= 1.0 ? rgb : "$rgb${two(c.a)}";
}

/// pickHexColour asks for a colour, and gives back the hex for it.
Future<String?> pickHexColour(BuildContext context, Color start,
    {required String title}) async {
  var chosen = start;
  var ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: start,
          // Alpha, because a panel behind a banner's writing is usually
          // meant to be seen through -- that is what #rrggbbaa is for.
          enableAlpha: true,
          displayThumbColor: true,
          hexInputBar: true,
          onColorChanged: (c) => chosen = c,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Use this")),
      ],
    ),
  );
  return ok == true ? hexOf(chosen) : null;
}

/// ElementPanel lists the blocks and what each of them takes.
class ElementPanel extends StatefulWidget {
  final TextEditingController? editor;
  final List<ElementSpec> specs;
  const ElementPanel({
    super.key,
    required this.editor,
    this.specs = pageElementSpecs,
  });

  @override
  State<ElementPanel> createState() => _ElementPanelState();
}

class _ElementPanelState extends State<ElementPanel> {
  /// _open is the block being looked at, or null with none chosen.
  ElementSpec? _open;

  /// _setting is the one setting or group whose answers are showing. One at
  /// a time, because the panel is a sidebar column and four settings all
  /// open at once is a list nobody can see the shape of.
  ///
  /// Holds a group's label or a setting's key, since either can be the
  /// thing that is open.
  String? _showing;

  /// _chosen is what has been picked, by block and then by setting. Kept
  /// across opening and closing a block, so going back to change one answer
  /// does not lose the other three.
  final Map<String, Map<String, String>> _chosen = {};

  Map<String, String> _forOpen() => _chosen[_open!.tag] ??= {};

  String _valueOf(ElementSpec spec, ElementSetting setting) =>
      _chosen[spec.tag]?[setting.key] ?? setting.fallback.value;

  String _labelOf(ElementSetting setting, String value) => setting.options
      .firstWhere((o) => o.value == value, orElse: () => setting.fallback)
      .label;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var spec in widget.specs)
              OutlinedButton(
                onPressed: () => setState(() {
                  _open = identical(_open, spec) ? null : spec;
                  _showing = null;
                }),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: identical(_open, spec)
                      ? theme.colors.surfaceContainerHighest
                      : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(spec.icon, size: 15),
                  const SizedBox(width: 6),
                  Txt.S(spec.name),
                ]),
              ),
          ],
        ),
        if (_open != null) ...[
          const SizedBox(height: 10),
          _settingsFor(theme, _open!),
        ],
      ],
    );
  }

  Widget _settingsFor(ThemeNotifier theme, ElementSpec spec) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colors.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What the block is for, before what it can be told. It is the
            // same note that goes in beside it.
            Txt.S(spec.tip.replaceAll(" Delete this note.", ""),
                color: TextColor.onSurfaceVariant),
            const SizedBox(height: 10),
            // Grouped where a block has more settings than a list can
            // carry: a banner has eighteen, and eighteen rows is a list
            // nobody reads.
            for (var setting in spec.settings) ...[
              _row(theme, setting.label, _labelOf(setting, _valueOf(spec, setting)),
                  setting.key),
              if (_showing == setting.key)
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Txt.S(setting.description,
                          color: TextColor.onSurfaceVariant),
                      const SizedBox(height: 6),
                      _chips(theme, spec, setting),
                    ],
                  ),
                ),
            ],
            for (var group in [
              ...spec.groups,
              if (spec.rowGroup != null) spec.rowGroup!,
            ]) ...[
              _row(theme, group.label, _summaryOf(spec, group), group.label),
              if (_showing == group.label) _groupBody(theme, spec, group),
            ],
            const SizedBox(height: 8),
            FilledButton(
              onPressed: widget.editor == null
                  ? null
                  : () {
                      insertBlock(
                          widget.editor!, spec.write(_chosen[spec.tag] ?? {}));
                      setState(() {
                        _open = null;
                        _showing = null;
                      });
                    },
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                visualDensity: VisualDensity.compact,
              ),
              child: Txt.S("Insert ${spec.name.toLowerCase()}"),
            ),
          ],
        ),
      );

  /// _row is one line in the panel: what it is, what it currently says,
  /// and whether it is open.
  Widget _row(ThemeNotifier theme, String label, String value, String id) =>
      InkWell(
        onTap: () => setState(() => _showing = _showing == id ? null : id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(
              _showing == id
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
            ),
            const SizedBox(width: 4),
            Expanded(child: Txt.S(label)),
            Flexible(
              child: Txt.S(value,
                  overflow: TextOverflow.ellipsis,
                  color: TextColor.onSurfaceVariant),
            ),
          ]),
        ),
      );

  /// _summaryOf is what a group says without being opened.
  ///
  /// The settings that are actually saying something, rather than all of
  /// them: a group whose summary lists seven defaults tells the reader
  /// nothing they could not have assumed.
  String _summaryOf(ElementSpec spec, SettingGroup group) {
    var said = [
      for (var s in group.settings)
        if (_chosen[spec.tag]?[s.key] != null &&
            (_chosen[spec.tag]![s.key] ?? "").isNotEmpty)
          _labelOf(s, _valueOf(spec, s))
    ];
    if (said.isNotEmpty) return said.join(", ");
    if (group.exclusive) return "None";
    return "${group.settings.length} settings";
  }

  /// _groupBody is a group opened: its settings, one under another.
  ///
  /// An exclusive group is different -- its settings are alternatives, so
  /// it asks which one first and then shows only that one. A title is
  /// filled with a colour, or a gradient, or a picture, and offering all
  /// three at once invites two answers to one question.
  Widget _groupBody(
          ThemeNotifier theme, ElementSpec spec, SettingGroup group) =>
      Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Txt.S(group.description, color: TextColor.onSurfaceVariant),
            const SizedBox(height: 8),
            if (group.exclusive)
              ..._exclusiveBody(theme, spec, group)
            else
              for (var setting in group.settings) ...[
                Txt.S(setting.label),
                const SizedBox(height: 4),
                _chips(theme, spec, setting),
                const SizedBox(height: 8),
              ],
          ],
        ),
      );

  List<Widget> _exclusiveBody(
      ThemeNotifier theme, ElementSpec spec, SettingGroup group) {
    var picked = group.settings.where((s) {
      var v = _chosen[spec.tag]?[s.key];
      return v != null && v.isNotEmpty;
    }).firstOrNull;

    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        _chip(theme, "None", picked == null, () => setState(() {
              for (var s in group.settings) {
                _forOpen().remove(s.key);
              }
            })),
        for (var setting in group.settings)
          _chip(theme, setting.label, identical(picked, setting), () {
            setState(() {
              // Clearing the rest is the whole point of an exclusive
              // group: two of these set is a banner asked two things.
              for (var s in group.settings) {
                _forOpen().remove(s.key);
              }
              _forOpen()[setting.key] = setting.options
                  .firstWhere((o) => o.value.isNotEmpty)
                  .value;
            });
          }),
      ]),
      if (picked != null) ...[
        const SizedBox(height: 8),
        Txt.S(picked.description, color: TextColor.onSurfaceVariant),
        const SizedBox(height: 4),
        _chips(theme, spec, picked),
      ],
    ];
  }

  /// _chips is a setting's answers, side by side.
  ///
  /// With a colour among them where the setting takes one: the listed
  /// colours are a starting point, and a banner's writing sits on a picture
  /// the writer chose, so the one they need is rarely on any list.
  Widget _chips(
          ThemeNotifier theme, ElementSpec spec, ElementSetting setting) =>
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var option in setting.options)
            _chip(theme, option.label, _valueOf(spec, setting) == option.value,
                () => setState(() => _forOpen()[setting.key] = option.value),
                swatch: _swatchOf(setting, option.value)),
          if (setting.kind == SettingKind.colour ||
              setting.kind == SettingKind.colours)
            _chip(theme, setting.kind == SettingKind.colours ? "Pick two…" : "Pick…",
                false, () => _pickColour(spec, setting)),
        ],
      );

  Color? _swatchOf(ElementSetting setting, String value) {
    if (setting.kind != SettingKind.colour) return null;
    return parseHexColour(value);
  }

  Widget _chip(ThemeNotifier theme, String label, bool on, VoidCallback onTap,
          {Color? swatch}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: on ? theme.colors.primaryContainer : null,
            border: Border.all(color: theme.colors.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (swatch != null) ...[
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: swatch,
                  border: Border.all(color: theme.colors.outlineVariant),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
            ],
            Txt.S(label),
          ]),
        ),
      );

  /// _pickColour asks for a colour and writes it as the hex a banner reads.
  Future<void> _pickColour(ElementSpec spec, ElementSetting setting) async {
    var many = setting.kind == SettingKind.colours;
    var start = (_chosen[spec.tag]?[setting.key] ?? "").split(",");
    var first = await pickHexColour(
        context, parseHexColour(start.first) ?? const Color(0xffffffff),
        title: many ? "First colour" : setting.label);
    if (first == null || !mounted) return;

    if (!many) {
      setState(() => _forOpen()[setting.key] = first);
      return;
    }
    var second = await pickHexColour(
        context,
        parseHexColour(start.length > 1 ? start[1] : "") ??
            const Color(0xff000000),
        title: "Second colour");
    if (second == null || !mounted) return;
    setState(() => _forOpen()[setting.key] = "$first,$second");
  }
}
