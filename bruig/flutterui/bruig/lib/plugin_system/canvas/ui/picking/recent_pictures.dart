import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/assets_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// recent_pictures.dart is the row of pictures already in the store, for
// putting one on a second canvas without finding the file again. A picture's
// name is a hash of its contents, so both elements share the one file.

/// showRecentPictures opens the picker and returns the chosen picture's id,
/// or null. [drawings] shows the Vectors store instead of the pictures.
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
  /// _ids is the store's contents, pictures newest first and drawings in no
  /// order; null while being read.
  List<String>? _ids;

  @override
  void initState() {
    super.initState();
    var read = widget.drawings
        ? CanvasMedia.stored(MediaKind.vector)
        : CanvasAssets.stored().then((ids) => [
              for (var id in ids)
                if (!isMaskId(id)) id
            ]);
    read.then((ids) {
      if (mounted) setState(() => _ids = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var ids = _ids;

    return AlertDialog(
      title: Txt.L(widget.drawings
          ? "Drawings you have used"
          : "Pictures you have used"),
      content: SizedBox(
        width: 520,
        height: 360,
        child: ids == null
            ? const Center(child: CircularProgressIndicator())
            : ids.isEmpty
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
                    itemCount: ids.length,
                    itemBuilder: (context, i) => _Thumbnail(
                      id: ids[i],
                      onTap: () => Navigator.of(context).pop(ids[i]),
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
  final String id;
  final VoidCallback onTap;

  const _Thumbnail({required this.id, required this.onTap});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: theme.colors.outlineVariant),
          color: theme.colors.surfaceContainerLow,
        ),
        clipBehavior: Clip.antiAlias,
        // Decoded small, as the Assets panel's tiles are: a tile is 120
        // pixels, and a picture at full size is tens of megabytes a tile.
        child: AssetThumb(key: ValueKey(id), id: id),
      ),
    );
  }
}
