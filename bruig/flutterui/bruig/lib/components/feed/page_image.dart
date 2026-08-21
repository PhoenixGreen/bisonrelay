import 'package:bruig/components/md_elements.dart';
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
    if (source == null) {
      // Not inside a page: a picture by path means nothing here, so the alt
      // text is all there is to show.
      return _placeholder(context);
    }

    // Listened to, not read: the picture arrives later and this is what
    // draws it when it does.
    return Consumer<ResourcesModel>(builder: (context, resources, _) {
      var bytes = resources.assetFor(source.uid, path);
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
    });
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
