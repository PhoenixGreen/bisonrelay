import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';

// path settings.dart is a path's settings.

/// pathSettings is a curve, and what travels along it.
///
/// The follower is chosen from a flat list of everything on the canvas plus
/// every player of every team, because "which player runs this" is the
/// question this feature exists to answer and making it a two-step choice --
/// pick a team, then pick a row -- would be two dropdowns for one decision.
List<Widget> pathSettings(
    BuildContext context,
    CanvasController controller,
    PathElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
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

  var followed = e.follow == null
      ? "Nobody follows it"
      : "${controller.followerLabel(e.follow)} · "
          "frames ${e.firstFrame}–${e.lastFrame}";
  return [
    section(e, "path",
        icon: Icons.gesture,
        title: "Path",
        summary: [
          "${shortNumber(e.strokeWidth)} wide",
          if (e.closed) "closed",
          if (e.guide) "guide only",
        ].join(" · "),
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "Stroke",
            help: "The route's colour and weight, whether it joins up at the "
                "end, and whether it is only a guide -- shown while the move "
                "is worked out, and left out of what is exported.",
            rule: false,
            children: [
              CanvasColorButton(
                label: "Colour",
                color: e.color,
                gradient: e.fade,
                onChanged: (c) => now(e.copyWith(color: c)),
                onGradientChanged: (g) => now(
                    g == null ? e.copyWith(flat: true) : e.copyWith(fade: g)),
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
            ],
          ),
          CanvasControlGroup(
            label: "Ends and dashes",
            help: "How the stroke is finished at each end, and how long each "
                "dash is -- 0 is a solid line.",
            rule: false,
            children: [
              ...strokeEndControls(
                cap: e.cap,
                startEnd: e.startEnd,
                endEnd: e.endEnd,
                endSize: e.endSize,
                onCap: (v) => now(e.copyWith(cap: v)),
                onStart: (v) => now(e.copyWith(startEnd: v)),
                onEnd: (v) => now(e.copyWith(endEnd: v)),
                onEndSize: (v) {
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
            ],
          ),
        ]),
    section(e, "follow",
        icon: Icons.directions_run,
        title: "Follow",
        summary: followed,
        children: [
          CanvasControlGroup(
            label: "The run",
            help: "What runs along the path -- anything on the canvas, or "
                "one player of a team -- and the frames the run starts and "
                "ends on. The points between are timed in Points.",
            rule: false,
            children: [
              CanvasDropdown<String>(
                label: "Who follows",
                value: _followKey(e.follow),
                // The least it will be. At a hundred and seventy-six the two
                // frame fields and the button were pushed onto a line of their
                // own the moment anybody pulled the sidebar in; it grows back
                // into a wide one.
                width: 112,
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
              // The run's two ends on a line of their own, under who runs it.
              const CanvasLineBreak(),
              CanvasNumberField(
                key: const ValueKey("pathStartFrame"),
                label: "Start",
                value: e.firstFrame.toDouble(),
                min: 0,
                max: (controller.document.frames - 1).toDouble(),
                width: 54,
                onChanged: (v) =>
                    relink(e.spreadFrames(v.round(), e.lastFrame)),
              ),
              CanvasNumberField(
                key: const ValueKey("pathEndFrame"),
                label: "End",
                value: e.lastFrame.toDouble(),
                min: 0,
                max: (controller.document.frames - 1).toDouble(),
                width: 54,
                onChanged: (v) =>
                    relink(e.spreadFrames(e.firstFrame, v.round())),
              ),
              const CanvasLineBreak(),
              CanvasTextButton(
                key: const ValueKey("pathSpread"),
                icon: Icons.horizontal_distribute,
                label: "Space the points evenly",
                onPressed: () =>
                    relink(e.spreadFrames(e.firstFrame, e.lastFrame)),
              ),
              CanvasTextButton(
                key: const ValueKey("pathRelink"),
                icon: Icons.sync,
                label: "Apply again",
                onPressed: e.follow == null ? null : () => relink(e),
              ),
              CanvasTextButton(
                key: const ValueKey("pathCarryOn"),
                icon: Icons.add,
                label: "Carry it on",
                onPressed: () => relink(
                    e.appendNode(maxFrame: controller.document.frames - 1)),
              ),
            ],
          ),
        ]),
    section(e, "points",
        icon: Icons.scatter_plot_outlined,
        title: "Points",
        summary: "${e.nodes.length} points",
        children: [_pathNodeList(controller, e, relink)]),
    // A path that carries a follower still carries it: this is the line
    // itself coming on, not the thing travelling along it.
    animationPanelSection(controller, e, e.animation,
        (a) => write(e.copyWith(animation: a)), begin, commit),
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
      help: "When the follower reaches each point, and where the point is. "
          "The marks on the timeline retime them too.",
      rule: false,
      children: [
        for (var i = 0; i < e.nodes.length; i++)
          Padding(
            key: ValueKey("path-node-$i-${e.id}"),
            padding: const EdgeInsets.only(bottom: 2),
            // A CanvasWrap rather than a Wrap, so the three numbers grow into
            // a wide sidebar the way every other line of settings does. Every
            // point has the same controls, so they all take the same share and
            // the rows come out in columns.
            child: CanvasWrap(children: [
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
