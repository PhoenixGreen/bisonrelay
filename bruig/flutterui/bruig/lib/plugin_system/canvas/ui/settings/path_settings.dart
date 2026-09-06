import 'package:bruig/plugin_system/canvas/model/elements/line_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';

// path settings.dart is a path's settings.

/// pathSettings is a curve, and what travels along it.
///
/// The follower is chosen from a flat list of everything on the canvas plus
/// every player of every team, because "which player runs this" is the
/// question this feature exists to answer and making it a two-step choice --
/// pick a team, then pick a row -- would be two dropdowns for one decision.
List<Widget> pathSettings(CanvasController controller, PathElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  void now(PathElement next) {
    begin();
    write(next);
    commit();
  }

  /// relink rewrites the follower's keyframes from the curve. Called after
  /// anything that changes the route or its timing, since the movement is
  /// baked rather than evaluated -- see CanvasController.applyPathFollow.
  void relink(PathElement next) {
    now(next);
    controller.applyPathFollow(next);
  }

  return [
    // No caption: the panel header says "Path settings" already, and a
    // group called Path directly under it was the word twice.
    CanvasControlGroup(label: "Path", hideCaption: true, children: [
      CanvasColorButton(
        label: "Colour",
        color: e.color,
        onChanged: (c) => now(e.copyWith(color: c)),
      ),
      CanvasNumberField(
        label: "Width",
        value: e.strokeWidth,
        min: 0.5,
        max: 60,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(strokeWidth: v));
        },
        onCommit: commit,
      ),
      CanvasDropdown<LineStrokeCap>(
        label: "Stroke end",
        value: e.cap,
        width: 92,
        options: [for (var c in LineStrokeCap.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(cap: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "Start",
        value: e.startEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(startEnd: v)),
      ),
      CanvasDropdown<LineEnd>(
        label: "End",
        value: e.endEnd,
        width: 124,
        options: [for (var c in LineEnd.values) (c, c.label)],
        onChanged: (v) => now(e.copyWith(endEnd: v)),
      ),
      CanvasNumberField(
        label: "End size",
        value: e.endSize,
        min: 0.2,
        max: 8,
        decimals: 1,
        width: 58,
        onChanged: (v) {
          begin();
          write(e.copyWith(endSize: v));
        },
        onCommit: commit,
      ),
      CanvasNumberField(
        label: "Dash",
        value: e.dash,
        min: 0,
        max: 200,
        decimals: 1,
        width: 54,
        onChanged: (v) {
          begin();
          write(e.copyWith(dash: v));
        },
        onCommit: commit,
      ),
      CanvasToggle(
        label: "Closed",
        value: e.closed,
        onChanged: (v) => now(e.copyWith(closed: v)),
      ),
      CanvasToggle(
        // A route is scaffolding: the line showing where a player runs helps
        // while the move is being worked out and ruins the picture that comes
        // out of it.
        label: "Guide only",
        value: e.guide,
        onChanged: (v) => now(e.copyWith(guide: v)),
      ),
    ]),
    CanvasControlGroup(label: "Follow", children: [
      CanvasDropdown<String>(
        label: "Who follows",
        value: _followKey(e.follow),
        width: 176,
        options: _followOptions(controller),
        onChanged: (v) {
          var follow = _followFromKey(v);
          if (follow == null) {
            controller.clearPathFollow(e);
            now(e.copyWith(clearFollow: true));
            return;
          }
          // Detaching the old follower first, or its baked keyframes are left
          // behind and it goes on running a route nothing is attached to.
          controller.clearPathFollow(e);
          relink(e.copyWith(follow: follow, guide: true));
        },
      ),
      CanvasNumberField(
        key: const ValueKey("pathStartFrame"),
        label: "Start",
        value: e.firstFrame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => relink(e.spreadFrames(v.round(), e.lastFrame)),
      ),
      CanvasNumberField(
        key: const ValueKey("pathEndFrame"),
        label: "End",
        value: e.lastFrame.toDouble(),
        min: 0,
        max: (controller.document.frames - 1).toDouble(),
        width: 54,
        onChanged: (v) => relink(e.spreadFrames(e.firstFrame, v.round())),
      ),
      CanvasIconButton(
        icon: Icons.horizontal_distribute,
        tooltip: "Space the points evenly over the run",
        onPressed: () => relink(e.spreadFrames(e.firstFrame, e.lastFrame)),
      ),
      CanvasIconButton(
        icon: Icons.sync,
        tooltip: "Re-apply this route to ${controller.followerLabel(e.follow)}",
        onPressed: e.follow == null ? null : () => relink(e),
      ),
      CanvasIconButton(
        icon: Icons.add,
        tooltip: "Carry the path on past its last point",
        onPressed: () =>
            relink(e.appendNode(maxFrame: controller.document.frames - 1)),
      ),
    ]),
    _pathNodeList(controller, e, relink),
  ];
}

/// _followKey encodes a follower as a dropdown value, since a dropdown wants
/// one comparable thing and a follower is an id and maybe an index.

/// _followKey encodes a follower as a dropdown value, since a dropdown wants
/// one comparable thing and a follower is an id and maybe an index.
String _followKey(PathFollow? follow) =>
    follow == null ? "" : "${follow.elementId}/${follow.playerIndex ?? -1}";

PathFollow? _followFromKey(String key) {
  if (key.isEmpty) return null;
  var at = key.lastIndexOf("/");
  if (at < 0) return PathFollow(elementId: key);
  var index = int.tryParse(key.substring(at + 1)) ?? -1;
  return PathFollow(
    elementId: key.substring(0, at),
    playerIndex: index < 0 ? null : index,
  );
}

/// _followOptions is everything on the canvas that could follow a path,
/// players included and paths excluded -- a path following a path is a knot.
List<(String, String)> _followOptions(CanvasController controller) {
  var out = <(String, String)>[("", "Nothing")];
  for (var element in controller.document.elements) {
    if (element is PathElement) continue;
    if (element is TeamElement) {
      for (var i = 0; i < element.players.length; i++) {
        var spot = element.players[i];
        var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
        out.add(("${element.id}/$i", "$who — ${element.name}"));
      }
      continue;
    }
    out.add(("${element.id}/-1", element.name));
  }
  return out;
}

/// _pathNodeList is one row per point: when the follower reaches it, and where
/// it is.
///
/// The frame is the interesting column. Retiming a point is how the movement
/// is made to look right -- fast out of the turn, slow into the box -- and
/// doing it by dragging the marks on the timeline is the other half of the
/// same control.

/// _pathNodeList is one row per point: when the follower reaches it, and where
/// it is.
///
/// The frame is the interesting column. Retiming a point is how the movement
/// is made to look right -- fast out of the turn, slow into the box -- and
/// doing it by dragging the marks on the timeline is the other half of the
/// same control.
/// An ordinary group rather than something to open. A path has a handful of
/// points, they are the thing anybody came to this panel for, and a section
/// that has to be opened before the main work can start is a press paid every
/// time.
Widget _pathNodeList(CanvasController controller, PathElement e,
        void Function(PathElement) relink) =>
    CanvasControlGroup(
      label: "Points (${e.nodes.length})",
      children: [
        for (var i = 0; i < e.nodes.length; i++)
          Padding(
            key: ValueKey("path-node-$i-${e.id}"),
            padding: const EdgeInsets.only(bottom: 2),
            child:
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              CanvasNumberField(
                key: ValueKey("node-frame-$i-${e.id}"),
                // The two ends are named, because they are what the run is
                // timed against and what the Start and End fields above set.
                label: i == 0
                    ? "Start"
                    : i == e.nodes.length - 1
                        ? "End"
                        : "Frame",
                value: e.nodes[i].frame.toDouble(),
                min: 0,
                max: (controller.document.frames - 1).toDouble(),
                width: 54,
                onChanged: (v) => relink(
                    e.withNode(i, e.nodes[i].copyWith(frame: v.round()))),
              ),
              CanvasNumberField(
                key: ValueKey("node-x-$i-${e.id}"),
                label: "X",
                value: e.pointOf(e.nodes[i]).dx,
                min: -100000,
                max: 100000,
                width: 54,
                onChanged: (v) => relink(e.withNode(
                    i,
                    e.nodes[i]
                        .copyWith(x: e.width == 0 ? 0 : (v - e.x) / e.width))),
              ),
              CanvasNumberField(
                key: ValueKey("node-y-$i-${e.id}"),
                label: "Y",
                value: e.pointOf(e.nodes[i]).dy,
                min: -100000,
                max: 100000,
                width: 54,
                onChanged: (v) => relink(e.withNode(
                    i,
                    e.nodes[i].copyWith(
                        y: e.height == 0 ? 0 : (v - e.y) / e.height))),
              ),
              CanvasIconButton(
                icon: Icons.add,
                tooltip: "Add a point after this one",
                // Only between two points -- past the last one there is no
                // segment to halve, and that is what the Add button on the
                // Follow row is for.
                onPressed: i >= e.nodes.length - 1
                    ? null
                    : () => relink(e.insertAfter(i,
                        maxFrame: controller.document.frames - 1)),
              ),
              CanvasIconButton(
                icon: Icons.close,
                tooltip: "Remove this point",
                onPressed:
                    e.nodes.length <= 2 ? null : () => relink(e.withoutNode(i)),
              ),
            ]),
          ),
      ],
    );

/// _tableRuleName says what a rule picks out, for its own heading and for the
/// button that removes it.
