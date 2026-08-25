import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:golib_plugin/definitions.dart';

// store_assets.dart is the shop's pictures: what it has, and what a page
// writes to show one.
//
// With a thumbnail beside each, because a list of file names is a list
// nobody can use: the whole question a seller has here is "which one is the
// cover for that product", and the answer is the picture.

class StoreAssets extends StatefulWidget {
  final StoreModel store;

  /// storeDir is where the shop is served from, so a thumbnail can be read
  /// off the disk rather than fetched from ourselves.
  final String storeDir;
  const StoreAssets({super.key, required this.store, required this.storeDir});

  @override
  State<StoreAssets> createState() => _StoreAssetsState();
}

class _StoreAssetsState extends State<StoreAssets> {
  @override
  void initState() {
    super.initState();
    widget.store.loadAssets();
  }

  Future<void> _delete(StoreAsset asset) async {
    var snackbar = SnackBarModel.of(context);
    var ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Delete ${asset.name}?"),
        content: const Txt.M(
            "Any product or page still naming this picture will show "
            "nothing where it was."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.store.deleteAsset(asset.name);
    } catch (exception) {
      snackbar.error("Unable to delete ${asset.name}: $exception");
    }
  }

  /// _thumbnail draws the picture itself, from the file on disk.
  ///
  /// Off the disk rather than through the shop: these are this client's own
  /// files, and fetching them from ourselves would be a round trip to answer
  /// a question we can already answer.
  Widget _thumbnail(ThemeNotifier theme, StoreAsset asset) {
    var file = File("${widget.storeDir}/shopassets/${asset.name}");
    Widget picture = asset.type == "image/svg+xml"
        ? SvgPicture.file(file, fit: BoxFit.cover)
        : Image.file(file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) =>
                Icon(Icons.broken_image_outlined,
                    size: 18, color: theme.colors.onSurfaceVariant));

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 40,
        height: 40,
        color: theme.colors.surfaceContainerHighest,
        child: picture,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var assets = widget.store.assets;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Txt.L("The shop's pictures"),
      const SizedBox(height: 6),
      const Txt.S(
          "Product covers and anything a page shows. Add one from a "
          "product, or paste what a picture gives you into a page.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 12),
      if (assets.isEmpty)
        const Txt.S("No pictures yet.", color: TextColor.onSurfaceVariant)
      else
        for (var asset in assets)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _thumbnail(theme, asset),
            title: Txt.M(asset.name),
            subtitle: Txt.S(humanReadableSize(asset.size),
                color: TextColor.onSurfaceVariant),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: "Delete ${asset.name}",
              onPressed: () => _delete(asset),
            ),
          ),
    ]);
  }
}
