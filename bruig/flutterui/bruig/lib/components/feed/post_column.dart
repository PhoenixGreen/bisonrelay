import 'package:bruig/components/containers.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// post_column.dart is the shape a post is read in: how wide the column is,
// what it is painted on, and how far the writing sits from the edge.
//
// Here rather than in the screen that reads a post, because the screen that
// *writes* one has to match it. A composer the full width of the window on
// no background is not a preview of anything -- the line lengths are wrong,
// which is most of what a page looks like, and the words sit on the app
// rather than on the post.

/// postColumnMaxWidth is how wide a post is ever drawn.
///
/// A measure rather than the window: a line of text running the full width of
/// a large screen is read by moving your head, and the eye loses its place
/// coming back to the start of the next one. Every typographic manual gives a
/// figure in this range and they are all saying the same thing.
const postColumnMaxWidth = 780.0;

/// postColumnSurface is what a post is painted on.
const postColumnSurface = SurfaceColor.tertiary;

/// postColumnRadius and postColumnPadding are the card's own corners and the
/// space between its edge and the writing.
const postColumnRadius = 3.0;
const postColumnPadding = EdgeInsets.all(16);

/// PostColumn is [child] laid out as a post: centred, no wider than a post is
/// read at, and on the surface a post is read on.
///
/// [fill] makes the column take the whole width it is given rather than
/// shrinking to its contents, which is what the composer wants: an empty post
/// should still show the page it is going to be. Height is left to whatever
/// is around it -- inside a scroll view there is no such thing as "as tall as
/// the screen".
class PostColumn extends StatelessWidget {
  final Widget child;
  final bool fill;
  final EdgeInsetsGeometry padding;

  const PostColumn(
      {required this.child,
      this.fill = false,
      this.padding = postColumnPadding,
      super.key});

  @override
  Widget build(BuildContext context) => Align(
        alignment: fill ? Alignment.topCenter : Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: postColumnMaxWidth),
          child: Box(
            color: postColumnSurface,
            borderRadius: BorderRadius.circular(postColumnRadius),
            padding: padding,
            width: fill ? double.infinity : null,
            child: child,
          ),
        ),
      );
}
