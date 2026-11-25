import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// inspector_fold.dart is the right-hand column of the Keys strip and the
// Curves (Ken, 2026-11-25: give the editor the room). A slim edge with a
// chevron shuts the inspector; shut, the edge alone stays, to open it again.
// Shut or open is the same for both, and kept for the session.

class InspectorFold extends StatelessWidget {
  /// id names its edge's key: "${id}Fold".
  final String id;
  final bool shut;
  final VoidCallback onToggle;

  /// width is the column's open, edge and all.
  final double width;
  final Widget child;
  const InspectorFold(
      {required this.id,
      required this.shut,
      required this.onToggle,
      required this.width,
      required this.child,
      super.key});

  /// edgeWidth is what a shut column keeps.
  static const edgeWidth = 16.0;

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var edge = Semantics(
      button: true,
      label: shut ? "Show the inspector" : "Hide the inspector",
      child: InkWell(
        key: ValueKey("${id}Fold"),
        onTap: onToggle,
        child: Container(
          width: edgeWidth,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: studio.edge))),
          child: Icon(shut ? Icons.chevron_left : Icons.chevron_right,
              size: 14, color: studio.muted),
        ),
      ),
    );
    if (shut) return edge;
    return SizedBox(
      width: width,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        edge,
        Expanded(child: child),
      ]),
    );
  }
}
