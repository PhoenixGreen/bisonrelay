import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/kaykit_packs.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/model_picking.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// kaykit_browser.dart offers KayKit's 3D characters (Kay Lousberg, CC0) to
// download: each pack says what is in it, how much room it takes and how
// much this computer has, and only then is fetched -- under Canvas's own
// rule that nothing is fetched unless allowed. Downloaded, each character
// is one of the person's 3D objects, credited, its animations with it.

class KayKitBrowser extends StatefulWidget {
  final CanvasController controller;
  const KayKitBrowser({required this.controller, super.key});

  /// freeSpace finds the room left on a disk: df, unless a test says
  /// otherwise.
  static Future<int?> Function(String dir) freeSpace = freeBytesAt;

  @override
  State<KayKitBrowser> createState() => KayKitBrowserState();
}

class KayKitBrowserState extends State<KayKitBrowser> {
  int? _free;

  /// _have are the characters already in the library, by their address.
  Set<String> _have = const {};

  /// _fetching is the pack being downloaded, and _said how it is going.
  String? _fetching;
  String _said = "";

  @override
  void initState() {
    super.initState();
    _look();
  }

  Future<void> _look() async {
    var dir = await CanvasStorage.libraryDir();
    var free = await KayKitBrowser.freeSpace(
        Directory(dir).existsSync() ? dir : path.dirname(dir));
    var have = {
      for (var a in await CanvasLibrary.list(kind: AssetKind.model)) a.origin
    };
    if (!mounted) return;
    setState(() {
      _free = free;
      _have = have;
    });
  }

  int _left(KayKitPack pack) => pack.characters
      .where((c) => !_have.contains(pack.url(c)))
      .fold(0, (n, c) => n + c.bytes);

  Future<void> _download(KayKitPack pack) async {
    var allowFetching = context.read<CanvasPreferences>().allowFetching;
    var proxied = await networkIsProxied();
    var refused =
        StockClient.refusal(allowFetching: allowFetching, proxied: proxied);
    if (refused != null) {
      setState(() => _said = refused);
      return;
    }
    setState(() => _fetching = pack.id);
    var scratch = await Directory.systemTemp.createTemp("kaykit");
    var got = 0, failed = <String>[];
    var wanted =
        pack.characters.where((c) => !_have.contains(pack.url(c))).toList();
    try {
      for (var (i, c) in wanted.indexed) {
        if (!mounted) return;
        setState(() => _said = "Downloading ${c.name} "
            "(${i + 1} of ${wanted.length}, ${megabytes(c.bytes)})…");
        var file = File(path.join(scratch.path, c.file));
        var ok = await StockClient.instance.download(pack.url(c), file,
            maxBytes: MediaKind.model.maxBytes,
            allowFetching: allowFetching,
            proxied: proxied);
        if (!ok) {
          failed.add(c.name);
          continue;
        }
        var added = await addCanvasModel(file.path, c.name,
            author: "Kay Lousberg",
            license: "CC0 1.0",
            origin: pack.url(c),
            from: "KayKit ${pack.title}");
        if (added.id == null) {
          failed.add(c.name);
        } else {
          got++;
        }
      }
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
    await _look();
    if (!mounted) return;
    setState(() {
      _fetching = null;
      _said = failed.isEmpty
          ? "$got downloaded: they are in your 3D objects, in the Assets "
              "panel."
          : "$got downloaded; ${failed.join(", ")} could not be. Check the "
              "connection, and try again for the rest.";
    });
  }

  @override
  Widget build(BuildContext context) {
    var free = _free;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const CanvasStatus("KayKit's characters, by Kay Lousberg: rigged and "
          "animated 3D figures, CC0 -- free for anything, no credit asked. "
          "They are large, so each pack is downloaded only when you ask."),
      CanvasStatus(free == null
          ? "How much room this computer has could not be found out."
          : "Room on this computer: ${megabytes(free)}."),
      for (var pack in kayKitPacks) ...[
        const SizedBox(height: 8),
        CanvasControlGroup(
          key: ValueKey("kayKit-${pack.id}"),
          label: pack.title,
          rule: false,
          children: [
            CanvasStatus("${pack.about} "
                "${pack.characters.map((c) => c.name).join(", ")}."),
            if (_left(pack) == 0)
              const CanvasStatus("Downloaded: in your 3D objects.")
            else ...[
              CanvasStatus("Needs ${megabytes(_left(pack))} of room"
                  "${free != null && free < _left(pack) * 2 ? " -- more than "
                      "this computer can spare" : ""}."),
              CanvasTextButton(
                key: ValueKey("kayKitDownload-${pack.id}"),
                label: "Download (${megabytes(_left(pack))})",
                icon: Icons.download_outlined,
                primary: true,
                onPressed:
                    _fetching != null || (free != null && free < _left(pack))
                        ? null
                        : () => _download(pack),
              ),
            ],
          ],
        ),
      ],
      if (_fetching != null) const LinearProgressIndicator(minHeight: 2),
      if (_said.isNotEmpty) CanvasStatus(_said),
    ]);
  }
}
