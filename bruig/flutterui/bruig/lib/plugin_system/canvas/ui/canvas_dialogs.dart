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
