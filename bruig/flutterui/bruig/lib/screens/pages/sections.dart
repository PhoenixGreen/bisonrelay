import 'package:flutter/material.dart';

/// PagesSections holds the four things the Pages content area can show, and
/// shows one of them.
///
/// All four stay built while one is looked at. That is the whole point of it
/// being here rather than a switch in the screen's build: the page editor and
/// the product editor keep what has been typed, and which item is open, in
/// their own State -- so building only the visible section threw a half-
/// written page away the moment a tab was clicked, with no warning and
/// nothing to undo it with.
///
/// [browser] is separate from the sections rather than being one of them
/// because it is not a destination: it is whichever page is open, and there
/// may be none.
class PagesSections extends StatelessWidget {
  /// index is the section to show, or [browserIndex] for the open page.
  final int index;
  final Widget visit;
  final Widget mySite;
  final Widget store;
  final Widget browser;

  static const int browserIndex = 3;

  const PagesSections({
    super.key,
    required this.index,
    required this.visit,
    required this.mySite,
    required this.store,
    required this.browser,
  });

  @override
  Widget build(BuildContext context) => IndexedStack(
        index: index.clamp(0, browserIndex),
        sizing: StackFit.expand,
        children: [visit, mySite, store, browser],
      );
}
