import 'dart:io';

import 'package:bruig/components/text.dart';
import 'package:bruig/models/store.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:golib_plugin/definitions.dart';

// pick_picture.dart is choosing a product's cover from the pictures the shop
// already has.
//
// The other way in adds one: it opens a file picker, encodes what it finds
// and writes it into the shop. That is the right thing the first time and the
// wrong thing every time after -- a seller with one photograph used by three
// products had to find it on disk three times, and ended up with three copies
// of it in the shop under three names.
//
// Shown as pictures rather than as a list of names, for the reason the
// Pictures tab is: the whole question here is "which one is the cover for
// this", and the answer is the picture.

/// pickShopPicture asks which of the shop's pictures a product should show,
/// and gives back the name a product records -- or null for a seller who
/// changed their mind.
Future<String?> pickShopPicture(
    BuildContext context, StoreModel store, String storeDir) async {
  // Read again on the way in: a picture added from the Pictures tab while
  // this product was open is one the seller expects to find here.
  await store.loadAssets();
  if (!context.mounted) return null;

  return showDialog<String>(
    context: context,
    builder: (context) => _PicturePicker(store: store, storeDir: storeDir),
  );
}

class _PicturePicker extends StatelessWidget {
  final StoreModel store;
  final String storeDir;
  const _PicturePicker({required this.store, required this.storeDir});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var assets = store.assets;

    return AlertDialog(
      title: const Text("The shop's pictures"),
      content: SizedBox(
        width: 420,
        height: 420,
        child: assets.isEmpty
            ? const Center(
                child: Txt.S(
                    "The shop has no pictures yet. Add one from the Pictures "
                    "tab, or with Add a picture.",
                    color: TextColor.onSurfaceVariant,
                    textAlign: TextAlign.center),
              )
            : GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 130,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.85,
                ),
                itemCount: assets.length,
                itemBuilder: (context, i) => _tile(context, theme, assets[i]),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel")),
      ],
    );
  }

  Widget _tile(BuildContext context, ThemeNotifier theme, StoreAsset asset) =>
      InkWell(
        onTap: () => Navigator.of(context).pop(asset.name),
        borderRadius: BorderRadius.circular(6),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _picture(theme, asset)),
          const SizedBox(height: 4),
          Txt.S(asset.name,
              overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          Txt.S(humanReadableSize(asset.size),
              color: TextColor.onSurfaceVariant, textAlign: TextAlign.center),
        ]),
      );

  /// _picture draws it from the file on disk.
  ///
  /// Off the disk rather than through the shop, the same as the Pictures tab:
  /// these are this client's own files, and fetching them from ourselves
  /// would be a round trip to answer a question we can already answer.
  Widget _picture(ThemeNotifier theme, StoreAsset asset) {
    var file = File("$storeDir/shopassets/${asset.name}");
    Widget drawn = asset.type == "image/svg+xml"
        ? SvgPicture.file(file, fit: BoxFit.cover)
        : Image.file(file,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Icon(
                Icons.broken_image_outlined,
                size: 18,
                color: theme.colors.onSurfaceVariant));

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        color: theme.colors.surfaceContainerHighest,
        alignment: Alignment.center,
        child: drawn,
      ),
    );
  }
}
