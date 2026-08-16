import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';

// feed_image.dart draws the one picture a post has had pulled out of it for
// placing -- the "First image display" setting in the Feed theme area.
//
// Shared rather than private to the feed page, because a quoted post is a
// post: it is set in whatever layout the reader chose, so the picture inside
// one is drawn by exactly the same code as the picture in the card around it
// rather than by a second, nearly-identical copy that drifts.

// Renders a feed post's first (extracted) image per FeedImageLayout. Only
// ever called with a concrete (non-standard, non-random) layout --
// FeedImageLayout.random is resolved to one of these by
// _resolveFeedImageLayout before this widget is built.
class FeedFirstImage extends StatelessWidget {
  final Uint8List bytes;
  final String tip;
  final FeedImageLayout layout;
  final double cropHeight;
  // Whether cropHeight should also cap the "full" layout's height -- true
  // when this layout was resolved from FeedImageLayout.random, since the
  // crop-height slider is shown (and implied to apply) for the whole random
  // rotation, not just the 1-in-4 chance it lands on FeedImageLayout.cropped.
  final bool applyCropCapToFull;
  final VoidCallback onTap;
  const FeedFirstImage(
      {required this.bytes,
      required this.tip,
      required this.layout,
      required this.cropHeight,
      this.applyCropCapToFull = false,
      required this.onTap,
      super.key});

  // Surfaces decode failures instead of silently swallowing them into an
  // invisible SizedBox.shrink() -- previously a failed decode left a blank,
  // unexplained gap (the reserved box from the layout's fixed height/width
  // stayed, but nothing indicated why nothing was drawn inside it).
  static Widget errorPlaceholder(Object error, {double? height}) {
    debugPrint("FeedFirstImage unable to decode image: $error");
    return SizedBox(
      height: height,
      width: double.infinity,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    switch (layout) {
      case FeedImageLayout.left:
      case FeedImageLayout.right:
        image = SizedBox(
          height: 140,
          width: double.infinity,
          child: Image.memory(bytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  errorPlaceholder(error, height: 140)),
        );
        break;
      case FeedImageLayout.full:
        image = applyCropCapToFull
            ? CappedHeightImage(bytes: bytes, maxHeight: cropHeight)
            : Image.memory(bytes,
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (context, error, stackTrace) =>
                    errorPlaceholder(error, height: 140));
        break;
      case FeedImageLayout.cropped:
        image = CappedHeightImage(bytes: bytes, maxHeight: cropHeight);
        break;
      case FeedImageLayout.standard:
        // Reached only when the image layout is left at Default but a
        // Text order has been chosen -- the image still needs to be
        // extracted to be positioned, but keeps its natural (inline-like)
        // size rather than being stretched or cropped.
        image = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
          child: Image.memory(bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  errorPlaceholder(error, height: 140)),
        );
        break;
      case FeedImageLayout.random:
      case FeedImageLayout.none:
        image = const SizedBox.shrink(); // Unreachable: resolved earlier.
        break;
    }
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ClipRRect(borderRadius: BorderRadius.circular(8), child: image),
      ),
    );
  }
}

// Renders an image at full available width, only imposing a fixed height
// (and cropping via BoxFit.cover) when the image would naturally render
// taller than maxHeight at that width. Images shorter than maxHeight are
// left at their natural height instead of being scaled up to fill it --
// scaling a short/wide image up to maxHeight while also stretching it to
// fill the available width would crop its sides off, which is the opposite
// of what a height cap should do.
class CappedHeightImage extends StatefulWidget {
  final Uint8List bytes;
  final double maxHeight;
  const CappedHeightImage(
      {required this.bytes, required this.maxHeight, super.key});

  @override
  State<CappedHeightImage> createState() => CappedHeightImageState();
}

class CappedHeightImageState extends State<CappedHeightImage> {
  double? _aspectRatio; // width / height of the decoded image.

  @override
  void initState() {
    super.initState();
    _decodeAspectRatio();
  }

  @override
  void didUpdateWidget(covariant CappedHeightImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes) {
      _aspectRatio = null;
      _decodeAspectRatio();
    }
  }

  void _decodeAspectRatio() {
    ui.decodeImageFromList(widget.bytes, (image) {
      if (!mounted) return;
      setState(() => _aspectRatio = image.width / image.height);
    });
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _aspectRatio;
    if (aspectRatio == null) {
      // Aspect ratio not decoded yet: reserve nothing and let the image
      // pop in at its natural size once decoding completes.
      return Image.memory(widget.bytes,
          width: double.infinity,
          fit: BoxFit.fitWidth,
          errorBuilder: (context, error, stackTrace) =>
              FeedFirstImage.errorPlaceholder(error, height: 140));
    }
    return LayoutBuilder(builder: (context, constraints) {
      final naturalHeight = constraints.maxWidth / aspectRatio;
      if (naturalHeight <= widget.maxHeight) {
        return Image.memory(widget.bytes,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (context, error, stackTrace) =>
                FeedFirstImage.errorPlaceholder(error, height: 140));
      }
      return SizedBox(
        height: widget.maxHeight,
        width: double.infinity,
        child: Image.memory(widget.bytes,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stackTrace) =>
                FeedFirstImage.errorPlaceholder(error,
                    height: widget.maxHeight)),
      );
    });
  }
}
