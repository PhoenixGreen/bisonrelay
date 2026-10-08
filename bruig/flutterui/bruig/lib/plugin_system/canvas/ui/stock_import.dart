import 'dart:io';

import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/media_picking.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// stock_import.dart is a stock result being used: fetched, then added the way
// a file from disk would be -- a picture stored and measured, a video through
// ffmpeg for its poster and sound, a sound converted if it has to be -- and
// then credited, so the library says who made it and under what licence.
//
// The same road as a file from disk on purpose. A stock video that skipped
// the poster, or a sound that skipped the measuring, would be an asset that
// behaved differently for having come from somewhere else.

/// fileNameFor is [title] as something safe to name a file after -- which is
/// what the import names the asset after, until the credit renames it.
String fileNameFor(String title) {
  var safe = title
      .replaceAll(RegExp(r"[^\w\- ]+"), "")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (safe.length > 60) safe = safe.substring(0, 60).trim();
  return safe.isEmpty ? "stock" : safe;
}

/// fetchStockItem fetches [item] into the library and returns it as an
/// asset, or null -- having said why -- when it could not be had.
Future<LibraryAsset?> fetchStockItem(
    BuildContext context, CanvasController controller, StockItem item) async {
  var snacks = SnackBarModel.of(context);
  var allowFetching = context.read<CanvasPreferences>().allowFetching;
  void report(String message) => snacks.error(message);

  var proxied = await networkIsProxied();
  var refused =
      StockClient.refusal(allowFetching: allowFetching, proxied: proxied);
  if (refused != null) {
    report(refused);
    return null;
  }

  var name = fileNameFor(item.title);
  var ext = path.extension(Uri.tryParse(item.media)?.path ?? "").toLowerCase();
  if (ext.isEmpty || ext.length > 5) {
    ext = switch (item.kind) {
      AssetKind.picture => ".png",
      AssetKind.vector => ".svg",
      AssetKind.video => ".mp4",
      AssetKind.audio => ".mp3",
    };
  }

  Directory? scratch;
  try {
    scratch = await Directory.systemTemp.createTemp("canvas-stock");
    var file = File(path.join(scratch.path, "$name$ext"));
    var got = await StockClient.instance.download(item.media, file,
        maxBytes: switch (item.kind) {
          AssetKind.picture => maxAssetBytes,
          AssetKind.vector => MediaKind.vector.maxBytes,
          AssetKind.video => MediaKind.video.maxBytes,
          AssetKind.audio => MediaKind.audio.maxBytes,
        },
        allowFetching: allowFetching,
        proxied: proxied);
    if (!got) {
      report("${item.title} could not be fetched from ${item.source.from}.");
      return null;
    }

    String? id;
    switch (item.kind) {
      case AssetKind.picture || AssetKind.vector:
        var bytes = await file.readAsBytes();
        // A drawing -- an icon library's are -- goes with the drawings,
        // whatever the library called it.
        if (String.fromCharCodes(bytes.take(4096))
            .toLowerCase()
            .contains("<svg")) {
          id = await CanvasMedia.saveVector(bytes);
          if (id == null) {
            report("${item.title} is too large a drawing for a canvas.");
            return null;
          }
          await CanvasLibrary.addVector(id, item.title);
          break;
        }
        id = await CanvasAssets.save(bytes);
        if (id == null) {
          report("${item.title} is not a picture the canvas can keep.");
          return null;
        }
        await CanvasLibrary.addPicture(id, item.title, bytes);
      case AssetKind.video:
        if (!context.mounted) return null;
        id = (await addCanvasVideo(context, file.path))?.assetId;
      case AssetKind.audio:
        if (!context.mounted) return null;
        id = (await addCanvasAudio(context, controller, file.path))?.assetId;
    }
    // The video and audio imports have said why already.
    if (id == null) return null;

    await CanvasLibrary.rename(id, item.title);
    await CanvasLibrary.credit(id,
        author: item.author,
        license: item.license,
        origin: item.page,
        from: item.source.from);
    for (var a in await CanvasLibrary.list(kind: item.kind)) {
      if (a.id == id) return a;
    }
    return null;
  } catch (exception) {
    report("Unable to add ${item.title}: $exception");
    return null;
  } finally {
    try {
      await scratch?.delete(recursive: true);
    } catch (_) {}
  }
}
