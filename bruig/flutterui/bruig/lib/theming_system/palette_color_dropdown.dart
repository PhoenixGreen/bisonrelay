import 'package:bruig/components/eyedropper.dart';
import 'package:bruig/theming_system/color_palette.dart';
import 'package:bruig/theming_system/preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

// PaletteColorDropdown lets the user pick one of the active palette's colors
// (plus, optionally, "None", and always a free-form "Custom color...") for a
// single field -- no popup dialog for the common case, just a standard
// dropdown menu. Used by every area editor that needs a color.
class PaletteColorDropdown extends StatelessWidget {
  final ThemePreset preset;
  final Color? value;
  // onChanged's second argument is the picked palette slot's index (into
  // preset.palette), or null for "None"/a custom-picked color -- callers
  // that persist it (rather than just the resolved Color) get a live
  // binding: re-resolving preset.palette[index] on every rebuild means
  // editing that slot's own color later is picked up automatically,
  // instead of the field being stuck on a frozen snapshot of whatever the
  // slot's color happened to be at pick time (which stops matching, or
  // worse, silently starts matching a *different* slot, the moment any
  // slot's value changes).
  final void Function(Color? color, int? index) onChanged;
  final bool allowNone;
  // noneLabel overrides the "None" entry's label -- e.g. "Default" for a
  // field whose null value doesn't mean "no color at all" but "use the
  // built-in computed default" (unlike, say, an accent color that's truly
  // absent when unset).
  final String noneLabel;
  const PaletteColorDropdown(
      {required this.preset,
      required this.value,
      required this.onChanged,
      this.allowNone = false,
      this.noneLabel = "None",
      super.key});

  // -2 is a sentinel dropdown value for "Custom color..." -- distinct from
  // -1 (None, only present when allowNone) and from any real palette index
  // (>= 0). Picking it opens a full color picker so a field isn't limited
  // to the fixed palette slots.
  static const _customValue = -2;

  Future<void> _pickCustomColor(BuildContext context, Color initial) async {
    var result = await showDialog<_ColorPickResult>(
      context: context,
      builder: (context) => _CustomColorDialog(initial: initial),
    );
    if (result == null) return;
    if (result.useEyedropper) {
      // The dialog is already closed at this point (see _CustomColorDialog's
      // eyedropper button), so the capture below sees whatever's actually
      // behind it, not the dialog's own chrome.
      if (!context.mounted) return;
      var picked = await pickColorFromApp(context);
      if (picked != null) onChanged(picked, null);
      return;
    }
    if (result.color != null) onChanged(result.color, null);
  }

  @override
  Widget build(BuildContext context) {
    var palette = preset.palette;
    var matchIdx = value == null
        ? -1
        : palette.indexWhere((c) => c.toARGB32() == value!.toARGB32());
    // A value that doesn't match any current palette slot is a previously
    // picked custom color -- show it as such instead of silently falling
    // back to the first palette entry.
    var isCustom = value != null && matchIdx < 0;
    if (matchIdx < 0 && !allowNone && !isCustom) matchIdx = 0;
    if (isCustom) matchIdx = _customValue;

    return DropdownButton<int>(
      value: matchIdx,
      items: [
        if (allowNone) DropdownMenuItem(value: -1, child: Text(noneLabel)),
        for (var i = 0; i < PaletteSlot.values.length; i++)
          DropdownMenuItem(
            value: i,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              colorSwatchBox(palette[i]),
              const SizedBox(width: 8),
              Text(paletteSlotLabel(PaletteSlot.values[i])),
            ]),
          ),
        DropdownMenuItem(
          value: _customValue,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            isCustom
                ? colorSwatchBox(value!)
                : const Icon(Icons.palette_outlined, size: 18),
            const SizedBox(width: 8),
            const Text("Custom color..."),
          ]),
        ),
      ],
      onChanged: (i) {
        if (i == null) return;
        if (i == _customValue) {
          _pickCustomColor(context, value ?? palette.first);
        } else if (i < 0) {
          onChanged(null, null);
        } else {
          onChanged(palette[i], i);
        }
      },
    );
  }
}

// colorSwatchBox is the small rounded color chip used wherever the editor
// shows "this is the color" -- dropdown entries and palette rows.
Widget colorSwatchBox(Color color, {double size = 18, double radius = 3}) =>
    Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

// _ColorPickResult is _CustomColorDialog's pop() value: either a committed
// color (Select) or a request to hand off to the in-app eyedropper (which
// needs the dialog closed first so it can capture what's behind it).
class _ColorPickResult {
  final Color? color;
  final bool useEyedropper;
  const _ColorPickResult.color(this.color) : useEyedropper = false;
  const _ColorPickResult.eyedropper()
      : color = null,
        useEyedropper = true;
}

// _CustomColorDialog lets the user pick an arbitrary color (not limited to
// the active preset's fixed palette slots) for a single AreaStyle field,
// via PaletteColorDropdown's "Custom color..." entry.
class _CustomColorDialog extends StatefulWidget {
  final Color initial;
  const _CustomColorDialog({required this.initial});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late Color _color = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text("Custom color")),
        IconButton(
          icon: const Icon(Icons.colorize),
          tooltip: "Pick color from app (eyedropper)",
          onPressed: () =>
              Navigator.of(context).pop(const _ColorPickResult.eyedropper()),
        ),
      ]),
      content: SingleChildScrollView(
        child: ColorPicker(
          pickerColor: _color,
          enableAlpha: true,
          displayThumbColor: true,
          hexInputBar: true,
          onColorChanged: (c) => setState(() => _color = c),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_ColorPickResult.color(_color)),
          child: const Text("Select"),
        ),
      ],
    );
  }
}
