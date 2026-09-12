import 'package:bruig/components/tooltips.dart';
import 'package:flutter/material.dart';

// app_frame.dart is what wraps everything the app navigates to.
//
// Two things, both of which have to sit outside every route:
//
// - AppTooltips, so the hover-text settings reach the login screens too.
//   Flutter's TooltipVisibility applies to its whole subtree, which is why
//   nothing below has to know about it.
//
// - A RepaintBoundary, so that the app's content is its own layer. Without
//   one, anything that repaints -- a route sliding in, a tooltip fading, a
//   caret blinking -- invalidates the whole window's raster together with
//   it, and moving between menu items goes from instant to visibly late.
//
// The boundary was removed once, on the grounds that it had been added for
// the in-app eyedropper to capture the app's own frame and the eyedropper
// was gone. It was doing two jobs, and only one of them went.

/// appContentLayer names the boundary, so that a test can tell it from the
/// several Flutter puts up on its own account -- without a name, "is there a
/// repaint boundary above this?" is answered yes whether ours is there or
/// not.
const Key appContentLayer = Key("app-content-layer");

/// appFrame is the app's content, wrapped in what has to be above all of it.
Widget appFrame(Widget? child) => AppTooltips(
      child: RepaintBoundary(
        key: appContentLayer,
        child: child ?? const Text("no child"),
      ),
    );
