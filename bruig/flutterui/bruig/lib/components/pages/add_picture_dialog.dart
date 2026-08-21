import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/components/feed/picture_options_controls.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// add_picture_dialog.dart adds a picture to the site: how wide to scale it,
// how hard to compress it, what to encode it as, and what a page writes to
// show it.
//
// The same decision as putting a picture into a post, and the same pipeline
// underneath -- see embed_options.dart -- but the answer lands somewhere
// else. A post carries its pictures; a site keeps them as files, so what
// comes out of here is a file name and a line of Markdown rather than base64
// in the middle of the text.
//
// Why it matters more here than for a post: a banner behind every page of a
// site is fetched once and kept, so its size is paid once per reader rather
// than once per page. The other side of that is that it is the first thing
// anyone waits for, and a 4 MB photograph straight off a camera is a site
// that takes a visible moment to appear.

/// showAddPictureDialog picks a file, offers the size choices, and adds it.
///
/// Returns what a page writes to show the picture -- "assets/banner.png" --
/// or null if it was cancelled.
Future<String?> showAddPictureDialog(
  BuildContext context,
  PagesModel pages,
  String sourcePath,
) =>
    showDialog<String?>(
      context: context,
      builder: (context) => _AddPictureDialog(pages, sourcePath),
    );

/// slugFileName makes a name a page can actually link to.
///
/// A picture is reached by writing ![](assets/name.jpg), and a Markdown link
/// stops at the first space. A file straight off a camera or a download is
/// routinely called "Decred - Open Source in the AI Era.jpg", which would be
/// written and served perfectly and then not show, because the link ends at
/// "Decred". So the name is fixed here, where it can be shown before the
/// picture is added rather than discovered afterwards.
///
/// Lowercased as well, because two files differing only in capitals are the
/// same file on a Mac and different ones on Linux, and a site whose pictures
/// appear only for the author is a hard thing to work out.
String slugFileName(String stem) {
  var out = stem
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9._-]+"), "-")
      .replaceAll(RegExp(r"-{2,}"), "-")
      .replaceAll(RegExp(r"^[-.]+|[-.]+$"), "");
  // Everything can be stripped -- a name of nothing but punctuation, or a
  // name in a script with no ASCII in it at all. Both are real, and neither
  // is a reason to refuse the picture.
  return out.isEmpty ? "picture" : out;
}

/// pickAndAddPicture asks for a file and then adds it.
///
/// The whole gesture in one place, because it is offered from two: the site's
/// own Pictures list, and the Writing sidebar while a page is being written.
/// Two copies would be two file pickers with slightly different titles and,
/// in time, two different sets of size choices.
Future<String?> pickAndAddPicture(BuildContext context, PagesModel pages) async {
  var picked = await FilePicker.platform.pickFiles(
    type: FileType.image,
    dialogTitle: "Picture to add to the site",
  );
  var path = picked?.files.single.path;
  if (path == null) return null;
  if (!context.mounted) return null;
  return showAddPictureDialog(context, pages, path);
}

class _AddPictureDialog extends StatefulWidget {
  final PagesModel pages;
  final String sourcePath;
  const _AddPictureDialog(this.pages, this.sourcePath);

  @override
  State<_AddPictureDialog> createState() => _AddPictureDialogState();
}

class _AddPictureDialogState extends State<_AddPictureDialog> {
  /// _options are remembered between pictures. Somebody who has decided
  /// their site's pictures should be 1200 wide has decided it for the site,
  /// not for this one file.
  static EmbedOptions _options =
      const EmbedOptions(maxWidth: 1600, quality: 80);

  Uint8List? _original;
  PreparedEmbed? _prepared;
  bool _preparing = false;
  String? _error;

  String get _sourceName => widget.sourcePath.split(Platform.pathSeparator).last;

  /// _mime is taken from the name, which is all there is to go on before the
  /// file is read and all the pipeline needs: it distinguishes a vector from
  /// a bitmap, and everything else is decided by decoding the bytes.
  String get _mime {
    var ext = _sourceName.toLowerCase().split(".").last;
    switch (ext) {
      case "svg":
        return "image/svg+xml";
      case "jpg":
      case "jpeg":
        return "image/jpeg";
      case "gif":
        return "image/gif";
      case "webp":
        return "image/webp";
      default:
        return "image/png";
    }
  }

  bool get _isVector => isSvgMime(_mime);

  @override
  void initState() {
    super.initState();
    _read();
  }

  void _read() async {
    try {
      var bytes = await File(widget.sourcePath).readAsBytes();
      if (!mounted) return;
      setState(() => _original = bytes);
      _prepare();
    } catch (exception) {
      if (!mounted) return;
      setState(() => _error = "Unable to read the picture: $exception");
    }
  }

  /// _prepare applies the current options, so the size shown is the size
  /// that will be written rather than an estimate of it.
  void _prepare() async {
    var original = _original;
    if (original == null || _preparing) return;
    setState(() => _preparing = true);
    var out = await prepareEmbed(original, _mime, _options);
    if (!mounted) return;
    setState(() {
      _prepared = out;
      _preparing = false;
    });
  }

  void _setOptions(EmbedOptions next) {
    _options = next;
    _prepare();
  }

  /// _fileName is what the picture is stored as.
  ///
  /// The extension follows the encoding rather than the file that was
  /// picked: a PNG screenshot compressed to JPEG is not a .png any more,
  /// and a page pointing at the old name would show nothing.
  String get _fileName {
    var stem = _sourceName.contains(".")
        ? _sourceName.substring(0, _sourceName.lastIndexOf("."))
        : _sourceName;
    var mime = _prepared?.mime ?? _mime;
    var ext = switch (mime) {
      "image/jpeg" => "jpg",
      "image/svg+xml" => "svg",
      "image/gif" => "gif",
      "image/webp" => "webp",
      _ => "png",
    };
    return "${slugFileName(stem)}.$ext";
  }

  void _add() async {
    var original = _original;
    if (original == null) return;
    var navigator = Navigator.of(context);
    // Whatever the options produced, falling back to the original if the
    // work has not finished: pressing Add is not a reason to be made to
    // wait, and the original is always valid.
    var ready = _prepared ?? PreparedEmbed(original, _mime);
    try {
      var path = await widget.pages.addAssetBytes(_fileName, ready.data);
      navigator.pop(path);
    } catch (exception) {
      if (!mounted) return;
      setState(() => _error = "Unable to add the picture: $exception");
    }
  }

  /// _sizeLine says what the picture will cost, and what it costs now.
  ///
  /// Measured rather than estimated -- the options are applied and the
  /// result weighed -- because anything else would be advertising a saving
  /// that might not arrive.
  Widget _sizeLine() {
    var original = _original;
    var prepared = _prepared;
    if (original == null) return const SizedBox.shrink();
    if (_preparing || prepared == null) {
      return const Txt.S("Working out the size...",
          color: TextColor.onSurfaceVariant);
    }
    // The bytes on disk, not base64: this becomes a file, and the file is
    // what crosses the wire.
    var was = (original.length / 1024).round();
    var now = (prepared.data.length / 1024).round();
    var size =
        prepared.width == null ? "" : "  ${prepared.width}x${prepared.height}";
    return Txt.S(now < was ? "$was KB down to $now KB$size" : "$now KB$size",
        color: TextColor.onSurfaceVariant);
  }

  Widget _preview() {
    var original = _original;
    if (original == null) {
      return const Center(child: CircularProgressIndicator());
    }
    var shown = _prepared?.data ?? original;
    return _isVector
        ? SvgPicture.memory(shown, fit: BoxFit.contain)
        : Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var error = _error;
    return AlertDialog(
      title: const Text("Add a picture"),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 220, child: _preview()),
          const SizedBox(height: 12),
          if (_isVector)
            // A vector has no pixels to scale and no quality to trade away.
            // Offering the controls anyway would be offering settings that
            // do nothing, so it says why instead.
            Txt.S(
                "A vector picture is drawn at whatever size it is shown, so "
                "there is nothing to scale or compress. It is added as it "
                "is, and it is almost certainly already the smallest thing "
                "on the page.",
                color: TextColor.onSurfaceVariant)
          else
            PictureOptionsControls(
              options: _options,
              onChanged: _setOptions,
              onSliding: (next) => setState(() => _options = next),
              sizeLine: Align(
                  alignment: Alignment.centerLeft, child: _sizeLine()),
            ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Txt.S("Pages will show it with  ![]($_fileName)",
                color: TextColor.onSurfaceVariant),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(error, style: TextStyle(color: theme.colors.error)),
            ),
          ],
        ]),
      ),
      actions: [
        CancelButton(onPressed: () => Navigator.of(context).pop()),
        OutlinedButton(
          onPressed: _original == null ? null : _add,
          child: const Text("Add"),
        ),
      ],
    );
  }
}
