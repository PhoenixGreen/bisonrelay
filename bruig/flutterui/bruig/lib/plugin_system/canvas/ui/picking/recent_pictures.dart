import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// recent_pictures.dart is "use one already added": the Library's pictures,
// or its drawings, for putting one on a second canvas without finding the
// file again. Listed from the Library and not from the stores, which also
// hold what nobody added, such as a video's poster frame and the pictures
// that came inside a canvas somebody shared. A picture's name is a hash of
// its contents, so both elements share the one file.

/// showRecentPictures opens the picker and returns the chosen picture's id,
/// or null. [drawings] shows the Library's drawings instead of its pictures.
Future<String?> showRecentPictures(BuildContext context,
        {bool drawings = false}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _RecentPicturesDialog(drawings: drawings),
    );

class _RecentPicturesDialog extends StatefulWidget {
  final bool drawings;
  const _RecentPicturesDialog({required this.drawings});

  @override
  State<_RecentPicturesDialog> createState() => _RecentPicturesDialogState();
}

class _RecentPicturesDialogState extends State<_RecentPicturesDialog> {
  /// _assets is the Library's pictures or drawings, newest first; null while
  /// being read.
  List<LibraryAsset>? _assets;

  @override
  void initState() {
    super.initState();
    CanvasLibrary.list(
            kind: widget.drawings ? AssetKind.vector : AssetKind.picture)
        .then((assets) {
      if (mounted) setState(() => _assets = assets);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var assets = _assets;

    return AlertDialog(
      title: Txt.L(widget.drawings
          ? "Drawings you have added"
          : "Pictures you have added"),
      content: SizedBox(
        width: 520,
        height: 360,
        child: assets == null
            ? const Center(child: CircularProgressIndicator())
            : assets.isEmpty
                ? Center(
                    child: Txt.S(widget.drawings
                        ? "No drawings yet. Add one and it will be here for "
                            "the next canvas."
                        : "No pictures yet. Add one and it will be here for "
                            "the next canvas."))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (context, i) => _Thumbnail(
                      asset: assets[i],
                      onTap: () => Navigator.of(context).pop(assets[i].id),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Txt.S("Cancel"),
        ),
      ],
      backgroundColor: theme.colors.surfaceContainerHigh,
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final LibraryAsset asset;
  final VoidCallback onTap;

  const _Thumbnail({required this.asset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colors.outlineVariant),
              color: theme.colors.surfaceContainerLow,
            ),
            clipBehavior: Clip.antiAlias,
            // Decoded small, as the Assets panel's tiles are: a tile is 120
            // pixels, and a picture at full size is tens of megabytes a tile.
            child: AssetThumb(key: ValueKey(asset.id), id: asset.id),
          ),
        ),
        // Named as the Library names it, since two pictures can look alike
        // at this size.
        Text(asset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.colors.onSurface)),
      ]),
    );
  }
}
