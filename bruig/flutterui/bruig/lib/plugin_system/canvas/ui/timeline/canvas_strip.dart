import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_strip.dart is the strip of settings that sits over the design:
// the canvas settings and the guides share it.

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
      // Opaque, with a shadow: it sits on top of the design, so it has to read
      // as a thing in front rather than as part of the canvas.
      color: theme.colors.surfaceContainerLow,
      elevation: 6,
      child: Container(
        width: double.infinity,
        // Tight: every pixel of padding here is a pixel of canvas.
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 7),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: theme.colors.outlineVariant, width: 1)),
        ),
        // Scrolls sideways rather than wrapping: a group is a Row, which cannot
        // break, so a wide one would overflow.
        child: ScrollConfiguration(
          behavior: const CanvasNoScrollbar(),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 5),
            // Captions beside their controls. See CanvasControlScope.inline.
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
