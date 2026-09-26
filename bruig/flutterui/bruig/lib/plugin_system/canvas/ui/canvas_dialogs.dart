import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// canvas_dialogs.dart is the questions the canvas asks before doing
// something there is no undo for.
//
// One of them, four times over: a title, a sentence, Cancel, and a button
// saying what is about to happen. Discarding a canvas, opening a link,
// deleting a file and replacing an element each had their own copy, which is
// four places to fix a dialog that turns out to be wrong in one.

/// askToConfirm puts a yes-or-no question and waits for the answer.
///
/// [confirm] names what is about to happen rather than saying "OK": a button
/// that says Delete tells somebody what they are agreeing to at the moment
/// they agree to it, which is the only moment it matters.
///
/// Dismissed -- tapped outside, or the back gesture -- counts as no.
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
///
/// The Rate dropdown's Custom entry, rather than a box beside it. A number
/// field that is only wanted once a canvas is being given an unusual rate sat
/// on the band forever, saying the same thing the dropdown beside it already
/// said -- and the two together were two controls for one number, where
/// typing in one silently renamed the other.
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
