import 'package:bruig/components/md_elements.dart';
import 'dart:typed_data';

import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

// page_image.dart draws a picture a page keeps as a file of its own, written
// as an ordinary Markdown image with a path: ![A banner](assets/banner.png).
//
// Its own file rather than written into the page, because a banner behind
// every page of a site written into every page is that banner sent every
// time. Asked for on its own and kept, it crosses the wire once -- and the
// page arrives and draws while it is still on its way, rather than waiting
// for it.
//
// A reader whose client does not know any of this sees the alt text, which
// is what a Markdown image has always degraded to.

/// isPageAssetPath is whether a link points at a file of this site's rather
/// than out at the world.
///
/// Anything with a scheme belongs to somebody else -- http, br:// and the
/// rest -- and is left to whatever handles those. What is left is a path
/// inside the site being read.
bool isPageAssetPath(String url) {
  var parsed = Uri.tryParse(url);
  return parsed != null && !parsed.hasScheme && url.isNotEmpty;
}

/// pageAssetBytes is the bytes of the picture at [path], or null while it is
/// on its way or if there are none.
///
/// The one place that knows where a site's pictures come from, because there
/// are two answers and the difference must not spread. Reading somebody
/// else's site, they arrive over the wire; writing your own, they are files
/// on this disk. Everything that draws one -- an ordinary Markdown image, a
/// banner background, a logo, the picture poured into a title -- asks here.
///
/// Watched rather than read, so whatever called this rebuilds when the
/// picture lands. That is what makes a page draw immediately and fill in as
/// its pictures arrive, rather than waiting for all of them.
Uint8List? pageAssetBytes(BuildContext context, String path) {
  if (!isPageAssetPath(path)) return null;

  var source = Provider.of<PagesSource?>(context, listen: false);
  if (source != null) {
    var bytes = context.watch<ResourcesModel>().assetFor(source.uid, path);
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  // No site being read, so this is a page being written and the picture is
  // one of this site's own files. Read from disk rather than fetched: the
  // author has it already, and going over the wire to reach your own files
  // would be waiting on a round trip to yourself.
  var pages = Provider.of<PagesModel?>(context, listen: false);
  if (pages == null) return null;
  var bytes = context.watch<PagesModel>().localAssetBytes(path);
  return (bytes == null || bytes.isEmpty) ? null : bytes;
}

/// pageAssetMime is the type of a picture, from its name.
///
/// The name is all there is: nothing declares a type for a file a page
/// points at. Only the vector case actually matters -- an SVG is drawn by a
/// different widget from everything else -- so the rest resolve to something
/// harmless.
String pageAssetMime(String path) {
  var ext = path.toLowerCase().split(".").last;
  return switch (ext) {
    "svg" => "image/svg+xml",
    "jpg" || "jpeg" => "image/jpeg",
    "gif" => "image/gif",
    "webp" => "image/webp",
    _ => "image/png",
  };
}

/// pageAssetPicture is one of the site's own pictures drawn to fill whatever
/// it is put in, or null while it is on its way and if there are none.
///
/// Separate from PageImage, which draws a picture as a block of a page at its
/// own shape. This is a picture used as a surface -- the one behind a panel,
/// which is what a shop front's product cards are made of -- so the caller
/// says how it is fitted and which part of it survives being cropped.
///
/// Null rather than a placeholder: what is behind a panel is behind it, and a
/// panel that draws its alt text as a background while the picture is on its
/// way is a card with a word written across it.
Widget? pageAssetPicture(BuildContext context, String path,
    {BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    bool fillWidth = false}) {
  var bytes = pageAssetBytes(context, path);
  if (bytes == null) return null;

  // fillWidth is for a picture that is the box rather than something in it.
  //
  // A picture left to its own width is drawn at its own width: put in
  // something wider -- a card in a grid, which is stretched to its share of
  // the row -- it sits at one end with space beside it. Everything drawn
  // from the box rather than from the picture then lands in the wrong place:
  // rounded corners cut the empty space at the far end and looked like two
  // of the four corners simply not working.
  var width = fillWidth ? double.infinity : null;

  return path.toLowerCase().endsWith(".svg")
      ? SvgPicture.memory(bytes, fit: fit, alignment: alignment, width: width)
      : Image.memory(bytes,
          fit: fit,
          alignment: alignment,
          width: width,
          errorBuilder: (context, error, stack) => const SizedBox.shrink());
}

/// PageImage shows one picture from the site being read.
class PageImage extends StatelessWidget {
  final String path;
  final String? alt;
  const PageImage({required this.path, this.alt, super.key});

  @override
  Widget build(BuildContext context) {
    var bytes = pageAssetBytes(context, path);
    if (bytes == null) return _placeholder(context);

    var image = path.toLowerCase().endsWith(".svg")
        ? SvgPicture.memory(bytes, fit: BoxFit.contain)
        : Image.memory(bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => _placeholder(context));

    var rule = MarkdownGuideScope.of(context);
    return ClipRRect(
      borderRadius:
          BorderRadius.circular(rule == null ? 8 : rule.boundedRadius),
      child: image,
    );
  }

  /// _placeholder is what stands in while a picture is on its way, and what
  /// is left if it never comes.
  ///
  /// The alt text rather than a spinner or a broken-image mark: a page whose
  /// pictures are still arriving is readable, and one whose pictures are
  /// missing should say what they were.
  Widget _placeholder(BuildContext context) {
    var text = (alt ?? "").trim();
    if (text.isEmpty) return const SizedBox.shrink();
    var theme = ThemeNotifier.of(context);
    return Text(text,
        style: TextStyle(
            fontStyle: FontStyle.italic, color: theme.colors.onSurfaceVariant));
  }
}
