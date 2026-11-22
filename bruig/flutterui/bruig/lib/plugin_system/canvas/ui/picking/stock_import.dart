import 'dart:io';

import 'package:bruig/plugin_system/canvas/ui/picking/model_picking.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/picture_import.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_sources.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/media_picking.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// stock_import.dart is a stock result being used: fetched, then added by the
// same road as a file from disk (a picture stored and measured, a video through
// ffmpeg for its poster and sound, a sound converted if need be), so it behaves
// like any other asset, and then credited with its maker and licence.

/// fileNameFor is [title] made safe as a file name, which the asset is named
/// after until the credit renames it.
String fileNameFor(String title) {
  var safe = title
      .replaceAll(RegExp(r"[^\w\- ]+"), "")
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
  if (safe.length > 60) safe = safe.substring(0, 60).trim();
  return safe.isEmpty ? "stock" : safe;
}

/// fetchStockItem fetches [item] into the library and returns it as an
/// asset, or null (having said why) when it could not be had.
Future<LibraryAsset?> fetchStockItem(
    BuildContext context, CanvasController controller, StockItem item) async {
  var snacks = SnackBarModel.of(context);
  var allowFetching = context.read<CanvasPreferences>().allowFetching;
  var (:asset, :problem, :notice) = await importStockItem(item,
      allowFetching: allowFetching,
      proxied: await networkIsProxied(),
      addVideo: (file) async => context.mounted
          ? (await addCanvasVideo(context, file))?.assetId
          : null,
      addAudio: (file) async => context.mounted
          ? (await addCanvasAudio(context, controller, file))?.assetId
          : null);
  if (problem != null) snacks.error(problem);
  // NASA's rules, with the picture kept, are said plainly, not as a
  // failure.
  if (notice != null) snacks.success(notice);
  return asset;
}

/// StockImport is what importing a stock result came to: the [asset] in
/// the library, or the [problem] that kept it out (null when an import on
/// screen has said why already); and with an asset, a [notice] to pass on
/// to whoever used it, such as NASA's rules or a model's warning.
typedef StockImport = ({LibraryAsset? asset, String? problem, String? notice});

/// importStockItem fetches [item] into the library: the asset, or why not
/// (see StockImport).
/// A video or a sound is added through [addVideo] or [addAudio], which ask
/// on screen and say why themselves if they cannot (the problem is then
/// null); without them, those kinds are refused. Needs no BuildContext, so
/// an assistant can use it too.
Future<StockImport> importStockItem(
  StockItem item, {
  required bool allowFetching,
  required bool proxied,
  Future<String?> Function(String file)? addVideo,
  Future<String?> Function(String file)? addAudio,
}) async {
  var refused =
      StockClient.refusal(allowFetching: allowFetching, proxied: proxied);
  if (refused != null) return (asset: null, problem: refused, notice: null);
  if ((item.kind == AssetKind.video && addVideo == null) ||
      (item.kind == AssetKind.audio && addAudio == null)) {
    return (
      asset: null,
      problem:
          "A ${item.kind == AssetKind.video ? "video" : "sound"} from stock "
              "is added from the Stock panel.",
      notice: null,
    );
  }

  var name = fileNameFor(item.title);
  var ext = path.extension(Uri.tryParse(item.media)?.path ?? "").toLowerCase();
  if (ext.isEmpty || ext.length > 5) {
    ext = switch (item.kind) {
      AssetKind.picture => ".png",
      AssetKind.vector => ".svg",
      AssetKind.video => ".mp4",
      AssetKind.audio => ".mp3",
      AssetKind.model => ".glb",
    };
  }

  Directory? scratch;
  try {
    scratch = await Directory.systemTemp.createTemp("canvas-stock");
    var file = File(path.join(scratch.path, "$name$ext"));
    // Poly Haven's models are several files, packed into one as they come.
    var got = item.source == StockSource.polyHaven
        ? await StockClient.instance.fetchPolyHavenModel(item.id, file,
            maxBytes: MediaKind.model.maxBytes,
            allowFetching: allowFetching,
            proxied: proxied)
        : await StockClient.instance.download(await _mediaOf(item), file,
            maxBytes: switch (item.kind) {
              AssetKind.picture => maxAssetBytes,
              AssetKind.vector => MediaKind.vector.maxBytes,
              AssetKind.video => MediaKind.video.maxBytes,
              AssetKind.audio => MediaKind.audio.maxBytes,
              AssetKind.model => MediaKind.model.maxBytes,
            },
            allowFetching: allowFetching,
            proxied: proxied);
    if (!got) {
      return (
        asset: null,
        problem: "${item.title} could not be fetched from ${item.source.from}.",
        notice: null,
      );
    }

    LibraryAsset? asset;
    String? warning;
    switch (item.kind) {
      case AssetKind.picture || AssetKind.vector:
        // Kept as it arrives, by what it holds: a drawing (as an icon
        // library's are) goes with the drawings, whatever the library
        // called it.
        var kept = await importPicture(await file.readAsBytes(),
            name: item.title,
            author: item.author,
            license: item.license,
            origin: item.page,
            from: item.source.from);
        if (kept.asset == null) {
          return (asset: null, problem: kept.problem, notice: null);
        }
        asset = kept.asset;
      case AssetKind.video:
        asset = await _credited(await addVideo!(file.path), item);
      case AssetKind.audio:
        asset = await _credited(await addAudio!(file.path), item);
      case AssetKind.model:
        var added = await addCanvasModel(file.path, item.title);
        // Said even when the model was added: then it is a warning.
        warning = added.problem;
        if (added.id == null) {
          return (asset: null, problem: warning, notice: null);
        }
        asset = await _credited(added.id, item);
    }
    // The video and audio imports have said why already.
    if (asset == null) return (asset: null, problem: warning, notice: null);

    // NASA's pictures come with NASA's rules, said each time one is used.
    if (item.source == StockSource.nasa) warning ??= nasaRule;
    return (asset: asset, problem: null, notice: warning);
  } catch (exception) {
    return (
      asset: null,
      problem: "Unable to add ${item.title}: $exception",
      notice: null,
    );
  } finally {
    try {
      await scratch?.delete(recursive: true);
    } catch (_) {}
  }
}

/// _credited names stored asset [id] after [item] and credits its maker,
/// for the kinds kept by a road of their own, which names the asset after
/// its file; the asset as listed, or null for none.
Future<LibraryAsset?> _credited(String? id, StockItem item) async {
  if (id == null) return null;
  await CanvasLibrary.rename(id, item.title);
  await CanvasLibrary.credit(id,
      author: item.author,
      license: item.license,
      origin: item.page,
      from: item.source.from);
  return CanvasLibrary.byId(id);
}

/// _mediaOf is where [item]'s file is: as it says, or for a Poly Haven
/// texture, its colour map, found now.
Future<String> _mediaOf(StockItem item) async {
  const texture = "polyhaven-texture:";
  if (!item.media.startsWith(texture)) return item.media;
  return await StockClient.instance
          .polyHavenPicture(item.media.substring(texture.length)) ??
      "";
}

/// nasaRule is NASA's media guidelines, as they bear on a picture used here.
const nasaRule = "From NASA: credit NASA, and never suggest NASA endorses "
    "anything -- cryptocurrency included -- or use it as an NFT.";
