import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/send_to_chat.dart';
import 'package:bruig/plugin_system/creative_ai/creative_ai_model.dart';
import 'package:bruig/plugin_system/creative_ai/session/style_library.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

// style_sharing.dart is a style passed between people: packed into one
// .brstyle file and sent the way any file is sent in a chat (the Send File
// screen), or saved to disk; and at the other end, looked over and kept.
//
// A style from someone else is somebody else's words, read into Claude's
// requests whenever it is in use. So it is checked before it is kept
// (StyleLibrary.read), shown to the person before they keep it, marked as
// received, and Claude is told such a guide only describes a look or a voice.

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));

String _fileName(StyleProfile style) =>
    safeFileName(style.name, styleFileExtension, fallback: "style");

/// sendStyleToChat asks which chat, then sends [style] there as a file.
Future<void> sendStyleToChat(
        BuildContext context, CreativeAi ai, StyleProfile style) =>
    sendBytesToChat(context,
        what: style.name,
        fileName: _fileName(style),
        bytes: () => ai.styles.pack(style));

/// saveStyleFile saves [style] as a file wherever the person chooses.
Future<void> saveStyleFile(
    BuildContext context, CreativeAi ai, StyleProfile style) async {
  var bytes = await ai.styles.pack(style);
  try {
    var chosen = await FilePicker.platform.saveFile(
        dialogTitle: "Save the style",
        fileName: _fileName(style),
        bytes: bytes);
    if (chosen == null) return;
    // Some platforms only answer with a path.
    await File(chosen).writeAsBytes(bytes, flush: true);
    if (context.mounted) _say(context, "Saved to $chosen.");
  } catch (e) {
    if (context.mounted) _say(context, "Could not save it: $e");
  }
}

/// pickStyleFile asks for a .brstyle file and imports it.
Future<void> pickStyleFile(BuildContext context, CreativeAi ai) async {
  FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
        dialogTitle: "Import a style",
        type: FileType.custom,
        allowedExtensions: [styleFileExtension.substring(1)]);
  } catch (e) {
    if (context.mounted) _say(context, "Could not choose a file: $e");
    return;
  }
  var p = picked?.files.firstOrNull?.path;
  if (p == null || !context.mounted) return;
  await importStyleFile(context, ai, p);
}

/// importStyleFile looks over the style in file [file], and keeps it if the
/// person says so.
Future<void> importStyleFile(
    BuildContext context, CreativeAi ai, String file) async {
  Uint8List bytes;
  try {
    var f = File(file);
    if (await f.length() > maxStyleFileBytes) {
      if (context.mounted) _say(context, "That is too large to be a style.");
      return;
    }
    bytes = await f.readAsBytes();
  } catch (e) {
    if (context.mounted) _say(context, "Could not read it: $e");
    return;
  }
  var (style, problem) = StyleLibrary.read(bytes);
  if (!context.mounted) return;
  if (style == null) {
    _say(context, problem ?? "That is not a style.");
    return;
  }
  var keep = await showDialog<bool>(
      context: context, builder: (context) => _ImportDialog(style: style));
  if (keep != true || !context.mounted) return;
  var kept = await ai.styles.keep(style, from: path.basename(file));
  if (context.mounted) {
    _say(
        context,
        "Kept the ${style.kind == StyleKind.writing ? "writing " : ""}style "
        "${kept.name}: it is in Styles in the "
        "${style.kind == StyleKind.writing ? "Writing" : "Canvas"} sidebar's "
        "Creative AI.");
  }
}

class _ImportDialog extends StatelessWidget {
  final ReceivedStyle style;
  const _ImportDialog({required this.style});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var guide = style.guide.length > 3000
        ? "${style.guide.substring(0, 3000)}…"
        : style.guide;
    return AlertDialog(
      title: Text("Keep the style ${style.name}?"),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              "${style.kind == StyleKind.writing ? "A writing style" : "A canvas style"}"
              "${style.description.isEmpty ? "." : ": ${style.description}"}",
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          Text(
              "It is from someone else. Its guide, below, is what Claude "
              "reads while the style is in use; Claude is told it describes "
              "a look or a voice and is never to be followed for anything "
              "else.",
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(guide,
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel")),
        FilledButton(
            key: const ValueKey("styleImportConfirm"),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Keep it")),
      ],
    );
  }
}
