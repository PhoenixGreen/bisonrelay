import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_dialogs.dart is the questions the canvas asks before doing
// something there is no undo for: discarding a canvas, opening a link,
// deleting a file, replacing an element.

/// askToConfirm puts a yes-or-no question and waits for the answer.
///
/// [confirm] names what is about to happen ("Delete") rather than "OK".
/// Dismissed (tapped outside, or the back gesture) counts as no.
Future<bool> askToConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm)),
        ],
      ),
    ) ??
    false;

/// askForFrameRate asks how many frames a second, with [initial] filled in.
/// It is the Rate dropdown's Custom entry.
Future<int?> askForFrameRate(BuildContext context, {required int initial}) {
  var text = TextEditingController(text: "$initial");
  int? answer() {
    return int.tryParse(text.text.trim())?.clamp(minFrameRate, maxFrameRate);
  }

  return showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Frames a second"),
      content: TextField(
        controller: text,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
            labelText: "Rate",
            helperText: "$minFrameRate to $maxFrameRate",
            suffixText: "fps"),
        onSubmitted: (_) => Navigator.of(context).pop(answer()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
        TextButton(
            onPressed: () => Navigator.of(context).pop(answer()),
            child: const Text("OK")),
      ],
    ),
  );
}

/// askForName puts up a one-field dialog for a name, [initial] filled in,
/// and waits for it: null when cancelled or dismissed.
///
/// The field's controller belongs to the dialog and is disposed with it:
/// the dialog still uses it while it animates away after answering.
Future<String?> askForName(
  BuildContext context, {
  required String title,
  String label = "",
  String initial = "",
  String ok = "OK",
  int? maxLength,
  Key? fieldKey,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
          title: title,
          label: label,
          initial: initial,
          ok: ok,
          maxLength: maxLength,
          fieldKey: fieldKey),
    );

/// askForPresetName asks what to call a preset, with [initial] filled in:
/// everything that saves or renames one asks through here, so all ask in
/// the same words and allow the same length.
Future<String?> askForPresetName(BuildContext context, String title,
        {String initial = ""}) =>
    askForName(context,
        title: title, label: "Name", initial: initial, maxLength: 60);

class _NameDialog extends StatefulWidget {
  final String title, label, initial, ok;
  final int? maxLength;
  final Key? fieldKey;
  const _NameDialog(
      {required this.title,
      required this.label,
      required this.initial,
      required this.ok,
      this.maxLength,
      this.fieldKey});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: widget.fieldKey,
          controller: _text,
          autofocus: true,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
              labelText: widget.label.isEmpty ? null : widget.label),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(_text.text),
              child: Text(widget.ok)),
        ],
      );
}
