import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_strip.dart is the strip of settings that sits over the design.
//
// Two of them: the canvas settings and the guides. They were the same
// forty lines twice over -- an opaque Material with a shadow, a tight
// padding, a rule along the bottom, a sideways scroll with no bar on it and
// a scope that puts the captions beside their controls -- differing only in
// what they put in the row. Two copies of a strip is two strips that stop
// matching each other the first time one of them is adjusted.

/// CanvasSettingsStrip is a line of control groups over the top of a canvas.
class CanvasSettingsStrip extends StatefulWidget {
  /// groups is the row's contents: CanvasControlGroups, laid out sideways.
  final List<Widget> Function(BuildContext context) groups;

  const CanvasSettingsStrip({required this.groups, super.key});

  @override
  State<CanvasSettingsStrip> createState() => _CanvasSettingsStripState();
}

class _CanvasSettingsStripState extends State<CanvasSettingsStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Material(
      // Opaque, and with a shadow. It is sitting on top of the design rather
      // than above it, so it has to read as a thing in front rather than as
      // part of the canvas.
      color: theme.colors.surfaceContainerLow,
      elevation: 6,
      child: Container(
        width: double.infinity,
        // Tight. The strip is over the design rather than beside it, so every
        // pixel of padding is a pixel of canvas -- and with the captions
        // beside their controls there is nothing here that needs the room.
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        // Scrolls sideways rather than wrapping. A group is a Row and a Row
        // cannot break, so one wider than the window overflows instead of
        // wrapping -- which is what the band used to do at anything under
        // about a thousand pixels.
        child: ScrollConfiguration(
          behavior: const CanvasNoScrollbar(),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 5),
            // Captions beside their controls, which is what makes this two
            // lines rather than three. See CanvasControlScope.inline.
            child: CanvasControlScope(
              maxWidth: 400,
              inline: true,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: widget.groups(context)),
            ),
          ),
        ),
      ),
    );
  }
}
