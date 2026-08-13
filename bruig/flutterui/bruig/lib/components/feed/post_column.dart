import 'package:bruig/components/containers.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
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
/// It is a cap on the card layout only. The app's original post layout has
/// no cap at all -- it takes the width it is given, less [postColumnInset]
/// either side -- and that one is still the default. See [PostColumnWidth].
const postColumnMaxWidth = 780.0;

/// postColumnInset is how far an uncapped post sits from the edge of the
/// area it is read in.
///
/// post_content.dart's own figure: 10 of scroll padding and 50 of margin.
/// Named here because the composer has to arrive at the same number, and two
/// screens each adding up to 60 in their own way is how they came to differ.
const postColumnInset = 60.0;

/// postColumnSmallInset is the same for a phone, where 60 either side would
/// be most of the screen.
const postColumnSmallInset = 10.0;

/// PostColumnWidth is how wide a post is drawn on this device, under the
/// theme in force.
///
/// Two layouts, because there are two. The Feed area's "Card redesign"
/// draws a post as a centred card no wider than [postColumnMaxWidth]; with
/// it off -- which is the default -- a post takes the width it is given.
/// The composer read the first figure whatever the theme said, so on the
/// default theme it wrote in a column narrower than the post it was a
/// preview of.
class PostColumnWidth {
  /// inset is the space either side of the post.
  final double inset;

  /// maxWidth is how wide it may then grow, or null for as wide as it is
  /// given.
  final double? maxWidth;

  const PostColumnWidth({required this.inset, this.maxWidth});

  /// of resolves the two from the theme and the size of the window.
  static PostColumnWidth of(BuildContext context) {
    if (checkIsScreenSmall(context)) {
      return const PostColumnWidth(inset: postColumnSmallInset);
    }
    var redesign =
        ThemeNotifier.of(context).areaStyle(ThemeArea.feed).feedCardRedesign;
    return redesign
        ? const PostColumnWidth(
            inset: postColumnSmallInset, maxWidth: postColumnMaxWidth)
        : const PostColumnWidth(inset: postColumnInset);
  }
}

/// postColumnSurface is what a post is painted on.
const postColumnSurface = SurfaceColor.tertiary;

/// postColumnRadius and postColumnPadding are the card's own corners and the
/// space between its edge and the writing.
const postColumnRadius = 3.0;
const postColumnPadding = EdgeInsets.all(16);

/// PostColumn is [child] laid out as a post: inset and capped the way a post
/// is under the theme in force, and on the surface a post is read on.
///
/// It carries its own horizontal inset rather than being handed one, because
/// the inset and the cap are one decision -- a caller that padded to suit the
/// card layout would be wrong the moment the theme was on the other one.
/// Whatever it is put inside should pad it vertically only.
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
  Widget build(BuildContext context) {
    var width = PostColumnWidth.of(context);
    var card = Box(
      color: postColumnSurface,
      borderRadius: BorderRadius.circular(postColumnRadius),
      padding: padding,
      width: fill ? double.infinity : null,
      child: child,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width.inset),
      child: Align(
        alignment: fill ? Alignment.topCenter : Alignment.center,
        child: width.maxWidth == null
            ? card
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width.maxWidth!),
                child: card,
              ),
      ),
    );
  }
}
