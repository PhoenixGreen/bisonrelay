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

/// PageImage shows one picture from the site being read.
class PageImage extends StatelessWidget {
  final String path;
  final String? alt;
  const PageImage({required this.path, this.alt, super.key});

  @override
  Widget build(BuildContext context) {
    var source = Provider.of<PagesSource?>(context, listen: false);
    if (source != null) {
      // Somebody else's site. Listened to, not read: the picture arrives
      // later and this is what draws it when it does.
      return Consumer<ResourcesModel>(
          builder: (context, resources, _) =>
              _drawn(context, resources.assetFor(source.uid, path)));
    }

    // No site being read, so this is a page being written -- the preview in
    // Writing, and the picture is one of this site's own files. Read from
    // disk rather than fetched: the author has it already, and a preview
    // that went over the wire to reach its own files would be waiting on a
    // round trip to itself.
    //
    // Falling back rather than being told which it is, because a page does
    // not change between being written and being read. The same markdown
    // draws the same picture, and only where the bytes come from differs.
    var pages = Provider.of<PagesModel?>(context, listen: false);
    if (pages == null) {
      // Neither: a picture by path means nothing here, so the alt text is
      // all there is to show.
      return _placeholder(context);
    }
    return Consumer<PagesModel>(
        builder: (context, model, _) =>
            _drawn(context, model.localAssetBytes(path)));
  }

  /// _drawn is the picture itself, or the alt text while there is none.
  ///
  /// One method for both sources: whether the bytes came off the wire or off
  /// the disk changes nothing about how they are shown, and two copies of
  /// this is how a preview comes to look unlike the page it previews.
  Widget _drawn(BuildContext context, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return _placeholder(context);

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
