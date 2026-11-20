import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/models/client.dart';
import 'package:bruig/models/uploads.dart';
import 'package:bruig/screens/send_file.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// send_to_chat.dart sends something a feature made -- a style, an image
// action -- to somebody, the way any file is sent in a chat: asks who, then
// hands the bytes to the Send File screen as a file of their own name.

/// safeFileName is [name] with what a file name cannot hold taken out,
/// [fallback] when nothing is left, and [extension] on the end.
String safeFileName(String name, String extension, {String fallback = "file"}) {
  var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), " ").trim();
  return "${safe.isEmpty ? fallback : safe}$extension";
}

/// sendBytesToChat asks which chat, then sends [bytes] there as [fileName].
/// [what] names the thing in the question: "Send [what] to".
Future<void> sendBytesToChat(BuildContext context,
    {required String what,
    required String fileName,
    required Future<Uint8List> Function() bytes}) async {
  var client = Provider.of<ClientModel>(context, listen: false);
  var chats = client.activeChats.sorted.where((c) => !c.isGC).toList();
  if (chats.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("There is nobody to send it to yet.")));
    return;
  }
  var chat = await showDialog<ChatModel>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text("Send $what to"),
      children: [
        SizedBox(
          width: 360,
          height: 360,
          child: ListView(children: [
            for (var c in chats)
              ListTile(
                key: ValueKey("sendTo-${c.nick}"),
                dense: true,
                title: Text(c.nick),
                onTap: () => Navigator.pop(context, c),
              ),
          ]),
        ),
      ],
    ),
  );
  if (chat == null || !context.mounted) return;
  var data = await bytes();
  var dir = await Directory.systemTemp.createTemp("bruig-send");
  var file = File(path.join(dir.path, fileName));
  await file.writeAsBytes(data);
  if (!context.mounted) return;
  await showSendFileScreen(context,
      chat: chat,
      file: file,
      uploads: Provider.of<UploadsModel>(context, listen: false));
}
