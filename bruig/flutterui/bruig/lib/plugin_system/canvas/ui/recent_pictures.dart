import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// recent_pictures.dart is the row of pictures already in the store, for
// putting one on a second canvas without going and finding the file again.
//
// The bytes have been shared from the beginning -- two elements naming the
// same picture have always been one file -- but nothing ever showed what was
// in there, so the only way to reuse anything was to import it a second time.
// That used to write a second copy as well; it does not any more, since a
// picture's name is a hash of its own contents. This is the other half of that:
// being able to see what is there.

/// showRecentPictures opens the picker and returns the chosen picture's id, or
/// null if nothing was chosen.
Future<String?> showRecentPictures(BuildContext context) => showDialog<String>(
      context: context,
      builder: (context) => const _RecentPicturesDialog(),
    );

class _RecentPicturesDialog extends StatefulWidget {
  const _RecentPicturesDialog();

  @override
  State<_RecentPicturesDialog> createState() => _RecentPicturesDialogState();
}

class _RecentPicturesDialogState extends State<_RecentPicturesDialog> {
  /// _ids is what is in the store, newest first, or null while it is being
  /// read.
  List<String>? _ids;

  @override
  void initState() {
    super.initState();
    CanvasAssets.stored().then((ids) {
      if (mounted) setState(() => _ids = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var ids = _ids;

    return AlertDialog(
      title: const Txt.L("Pictures you have used"),
      content: SizedBox(
        width: 520,
        height: 360,
        child: ids == null
            ? const Center(child: CircularProgressIndicator())
            : ids.isEmpty
                ? const Center(
                    child: Txt.S("No pictures yet. Add one and it will be "
                        "here for the next canvas."))
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

/// _Thumbnail draws one stored picture.
///
/// Through the same image store the canvas itself draws from, so a picture
/// already on screen costs nothing to show here and one that is not is decoded
/// once and then shared with the canvas when it is chosen.
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
        child: _StoredImage(id: id),
      ),
    );
  }
}

class _StoredImage extends StatefulWidget {
  final String id;
  const _StoredImage({required this.id});

  @override
  State<_StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends State<_StoredImage> {
  final CanvasImageStore _store = CanvasImageStore();

  @override
  void initState() {
    super.initState();
    _store.addListener(_onLoaded);
  }

  @override
  void dispose() {
    _store.removeListener(_onLoaded);
    _store.dispose();
    super.dispose();
  }

  void _onLoaded() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var image = _store.resolve(widget.id, const BackgroundRemoval());
    if (image == null) return const SizedBox.shrink();
    return RawImage(image: image, fit: BoxFit.cover);
  }
}
