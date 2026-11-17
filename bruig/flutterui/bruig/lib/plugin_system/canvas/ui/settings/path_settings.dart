import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/line_settings.dart';

// path_settings.dart is a path's panel (see element_panel.dart): quick
// strip, Content (points), Look and More (its follower).

Widget pathPanel(
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

  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        panelRow([
          cell(
              CanvasColorButton(
                key: const ValueKey("quickPathColour"),
                label: "Colour",
                color: e.color,
                onChanged: (c) => now(e.copyWith(color: c)),
              ),
              width: 104),
          cell(
              CanvasStepper(
                key: const ValueKey("quickPathWidth"),
                label: "Width",
                value: e.strokeWidth,
                min: 0,
                max: 200,
                decimals: 1,
                step: 1,
                suffix: " px",
                fill: true,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(strokeWidth: v));
                },
                onCommit: commit,
              ),
              width: 132),
        ]),
        const SizedBox(height: 8),
        CanvasToggle(
          key: const ValueKey("quickPathClosed"),
          label: "Closed",
          value: e.closed,
          onChanged: (v) => now(e.copyWith(closed: v)),
        ),
      ]),
      // Its points are why its settings are opened: not folded away.
      contentOpen: true,
      bits: pathBits(context, controller, e, write, begin, commit));
}

/// pathBits are a curve and its follower, chosen from one flat list of the
/// canvas's elements and every team's players: one decision.
List<PanelBit> pathBits(
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

  /// relink rebakes the follower's keyframes after any route or timing
  /// change (see CanvasController.applyPathFollow).
  void relink(PathElement next) {
    begin();
    write(next);
    controller.applyPathFollow(next);
    commit();
  }

  var followed = e.follow == null
      ? "Nobody follows it"
      : "${controller.followerLabel(e.follow)} · "
          "frames ${e.firstFrame}–${e.lastFrame}";
  return [
    PanelBit(PanelSection.look,
        summary: [
          "${shortNumber(e.strokeWidth)} wide",
          if (e.closed) "closed",
          if (e.guide) "guide only",
        ].join(" · "),
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
                // A route is scaffolding: the line helps while the move is
                // worked out and spoils the finished picture.
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
    PanelBit(PanelSection.more, summary: followed, children: [
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
            // The least it can be: wider, and the frame fields and button
            // wrap onto their own line in a narrow sidebar.
            width: 112,
            options: _followOptions(controller),
            onChanged: (v) {
              var follow = _followFromKey(v);
              if (follow == null) {
                controller.clearPathFollow(e);
                now(e.copyWith(clearFollow: true));
                return;
              }
              // Detach the old follower first, or its baked keyframes stay
              // and it keeps running a route nothing is attached to.
              controller.clearPathFollow(e);
              relink(e.copyWith(follow: follow, guide: true));
            },
          ),
          // The run's two ends on their own line, under who runs it.
          const CanvasLineBreak(),
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
          const CanvasLineBreak(),
          CanvasTextButton(
            key: const ValueKey("pathSpread"),
            icon: Icons.horizontal_distribute,
            label: "Space the points evenly",
            onPressed: () => relink(e.spreadFrames(e.firstFrame, e.lastFrame)),
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
            onPressed: () =>
                relink(e.appendNode(maxFrame: controller.document.frames - 1)),
          ),
        ],
      ),
    ]),
    PanelBit(PanelSection.content,
        summary: "${e.nodes.length} points",
        children: [_pathNodeList(controller, e, relink)]),
    // A follower still rides a path that arrives: this is the line itself.
    // Motion lives in the Chain's Motion view.
  ];
}

/// _followKey encodes a follower as one comparable dropdown value: an id
/// and maybe an index.
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

/// _followOptions is everything that could follow a path, players included
/// and paths excluded (a path following a path is a knot).
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

/// _pathNodeList is a row per point: when the follower reaches it and
/// where. Retiming shapes the movement; a plain group, as the points are
/// why the panel is opened.
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
            // A CanvasWrap, so the numbers grow into a wide sidebar, each an
            // equal share so the rows line up in columns.
            child: CanvasWrap(children: [
              CanvasNumberField(
                key: ValueKey("node-frame-$i-${e.id}"),
                // The ends are named: the run is timed against them and the
                // Start and End fields above set them.
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
                // Only between two points: past the last there is no segment
                // to halve, which is what the Follow row's Add is for.
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
