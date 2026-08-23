import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/writing_tools/ui/sidebar/element_specs.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

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

  /// _setting is the one setting whose answers are showing. One at a time,
  /// because the panel is a sidebar column and four settings all open at
  /// once is a list nobody can see the shape of.
  ElementSetting? _setting;

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
                  _setting = null;
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
            for (var setting in spec.allSettings) ...[
              _settingRow(theme, spec, setting),
              if (identical(_setting, setting)) _optionsFor(spec, setting),
              const SizedBox(height: 2),
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
                        _setting = null;
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

  /// _settingRow is one setting and the answer it is currently giving.
  ///
  /// The answer is shown whether or not it has been picked: a block that has
  /// been told nothing is not a block that does nothing, and the panel opens
  /// describing what the writer would actually get.
  Widget _settingRow(
          ThemeNotifier theme, ElementSpec spec, ElementSetting setting) =>
      InkWell(
        onTap: () => setState(
            () => _setting = identical(_setting, setting) ? null : setting),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(
              identical(_setting, setting)
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
            ),
            const SizedBox(width: 4),
            Expanded(child: Txt.S(setting.label)),
            Txt.S(_labelOf(setting, _valueOf(spec, setting)),
                color: TextColor.onSurfaceVariant),
          ]),
        ),
      );

  Widget _optionsFor(ElementSpec spec, ElementSetting setting) => Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Txt.S(setting.description, color: TextColor.onSurfaceVariant),
            const SizedBox(height: 6),
            for (var option in setting.options)
              InkWell(
                onTap: () => setState(
                    () => _forOpen()[setting.key] = option.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(
                      _valueOf(spec, setting) == option.value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Txt.S(option.label)),
                    if (option.note != null)
                      Flexible(
                        child: Txt.S(option.note!,
                            overflow: TextOverflow.ellipsis,
                            color: TextColor.onSurfaceVariant),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      );
}
