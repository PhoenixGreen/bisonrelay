import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stroke_controls.dart';

// path_settings.dart is a path's panel (see element_panel.dart): quick
// strip, Content (points), Look and More (its follower). Its stroke's
// controls are stroke_controls.dart's, which a line's panel uses too.

/// pathPanel is a path's settings, laid out by elementPanel.
Widget pathPanel(
    BuildContext context,
    CanvasController controller,
    PathElement e,
    SettingsWrite write,
    VoidCallback begin,
    VoidCallback commit) {
  var s = StrokeEdit(e, write, begin, commit);
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

  return elementPanel(context, controller, e, write, begin, commit,
      quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
        panelRow([
          cell(strokeColour(s, key: const ValueKey("quickPathColour")),
              width: 104),
          cell(
              strokeWidth(s,
                  key: const ValueKey("quickPathWidth"), quick: true),
              width: 132),
        ]),
        const SizedBox(height: 8),
        _closedToggle(e, now, key: const ValueKey("quickPathClosed")),
      ]),
      // Its points are why its settings are opened: not folded away.
      contentOpen: true,
      bits: [
        _strokeBit(e, s, now),
        _runBit(controller, e, begin, now, relink),
        PanelBit(PanelSection.content,
            summary: "${e.nodes.length} points",
            children: [_pathNodeList(controller, e, relink)]),
        // A follower still rides a path that arrives: this is the line
        // itself. Motion lives in the Chain's Motion view.
      ]);
}

/// _closedToggle joins the path's end back to its start.
Widget _closedToggle(PathElement e, void Function(PathElement) now,
        {Key? key}) =>
    CanvasToggle(
      key: key,
      label: "Closed",
      value: e.closed,
      onChanged: (v) => now(e.copyWith(closed: v)),
    );

/// _strokeBit is the route's stroke, whether it joins up, whether it is
/// only a guide, and its ends and dashes, in Look.
PanelBit _strokeBit(
        PathElement e, StrokeEdit s, void Function(PathElement) now) =>
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
              strokeColour(s),
              strokeWidth(s, quick: false),
              _closedToggle(e, now),
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
                "dash is -- 0 is a solid line. Swap ends puts each end's "
                "mark on the other. Closed, it has no ends: only the cap on "
                "each dash.",
            rule: false,
            children: [
              ...strokeEndControls(s),
              strokeDash(s, quick: false),
            ],
          ),
        ]);

/// _runBit is what follows the path and the frames its run starts and ends
/// on, chosen from one flat list of the canvas's elements and every team's
/// players: one decision. In More.
PanelBit _runBit(CanvasController controller, PathElement e, VoidCallback begin,
    void Function(PathElement) now, void Function(PathElement) relink) {
  // Where the run ends as it plays: round a closed path, no further than
  // the scene goes.
  var end = e.endFrameIn(controller.document.frames - 1);
  var followed = e.follow == null
      ? "Nobody follows it"
      : "${controller.followerLabel(e.follow)} · "
          "frames ${e.firstFrame}–$end";
  var options = _followOptions(controller);
  // A follower that is none of the choices (no longer on the canvas, say)
  // is shown by the name the summary gives it, for as long as it is the
  // one, as a font not known is.
  var gone = e.follow != null && !options.any((o) => o.$1 == e.follow);
  if (gone) {
    options.insert(1, (e.follow!, controller.followerLabel(e.follow)));
  }
  return PanelBit(PanelSection.more, summary: followed, children: [
    CanvasControlGroup(
      label: "The run",
      help: "What runs along the path -- anything on the canvas, or "
          "one player of a team -- and the frames the run starts and "
          "ends on. The points between are timed in Points. Round a "
          "closed path the run ends back at its start, taking as long "
          "over the last piece as over the one before it.",
      rule: false,
      children: [
        CanvasDropdown<PathFollow>(
          label: "Who follows",
          value: e.follow ?? _nobody,
          // The least it can be: wider, and the frame fields and button
          // wrap onto their own line in a narrow sidebar.
          width: 112,
          options: options,
          onChanged: (follow) {
            // Nothing to follow again: it is not there.
            if (gone && follow == e.follow) return;
            // Detach the old follower first, or its baked keyframes stay
            // and it keeps running a route nothing is attached to: in the
            // same step as what follows, so one undo takes back both.
            begin();
            controller.clearPathFollow(e);
            if (follow == _nobody) {
              now(e.copyWith(clearFollow: true));
              return;
            }
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
          onChanged: (v) => relink(e.spreadRun(v.round(), end)),
        ),
        CanvasNumberField(
          key: const ValueKey("pathEndFrame"),
          label: "End",
          value: end.toDouble(),
          min: 0,
          max: (controller.document.frames - 1).toDouble(),
          width: 54,
          onChanged: (v) => relink(e.spreadRun(e.firstFrame, v.round())),
        ),
        const CanvasLineBreak(),
        CanvasTextButton(
          key: const ValueKey("pathSpread"),
          icon: Icons.horizontal_distribute,
          label: "Space the points evenly",
          onPressed: () => relink(e.spreadRun(e.firstFrame, end)),
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
  ]);
}

/// _nobody is the choice of nothing following: no element has an empty id.
const _nobody = PathFollow(elementId: "");

/// _followOptions is everything that could follow a path, players included
/// and paths excluded (a path following a path is a knot).
List<(PathFollow, String)> _followOptions(CanvasController controller) {
  var out = <(PathFollow, String)>[(_nobody, "Nothing")];
  for (var element in controller.document.elements) {
    if (element is PathElement) continue;
    if (element is TeamElement) {
      for (var i = 0; i < element.players.length; i++) {
        var spot = element.players[i];
        var who = spot.name.isNotEmpty ? spot.name : "#${spot.number}";
        out.add((
          PathFollow(elementId: element.id, playerIndex: i),
          "$who — ${element.name}"
        ));
      }
      continue;
    }
    out.add((PathFollow(elementId: element.id), element.name));
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
                // Start and End fields above set them. Round a closed path
                // the run ends on the first point again, not the last.
                label: i == 0
                    ? "Start"
                    : i == e.nodes.length - 1 && !e.closed
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
                // Only before a piece of the curve: past an open path's last
                // point there is none to halve, which is what the run's Carry
                // it on is for; a closed path's last has the closing piece.
                onPressed: i >= e.segments
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
