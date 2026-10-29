import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/play.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// play_settings.dart is what an element does when the canvas is played as
// a game -- see play.dart and canvas_game.dart.

Widget playSection(CanvasController controller, CanvasElement e,
    SettingsWrite write, VoidCallback begin, VoidCallback commit) {
  var spec = e.base.play;
  void set(PlaySpec next, {bool live = false}) {
    begin();
    write(e.rebase(e.base.copyWith(play: next)));
    if (!live) commit();
  }

  return section(e, "play",
      icon: Icons.sports_esports_outlined,
      title: "Play",
      summary: spec.as.label,
      children: [
        CanvasControlGroup(
          label: "Play",
          hideCaption: true,
          rule: false,
          children: [
            CanvasDropdown<PlayAs>(
              key: const ValueKey("playAs"),
              label: "When played",
              value: spec.as,
              width: 170,
              options: [for (var p in PlayAs.values) (p, p.label)],
              onChanged: (p) => set(spec.copyWith(as: p)),
            ),
            if (spec.as.moves)
              CanvasNumberField(
                key: const ValueKey("playSpeed"),
                label: "Speed",
                value: spec.speed,
                min: 10,
                max: 5000,
                width: 64,
                onChanged: (v) => set(spec.copyWith(speed: v), live: true),
                onCommit: commit,
              ),
            if (spec.as == PlayAs.platformer) ...[
              CanvasNumberField(
                key: const ValueKey("playJump"),
                label: "Jump",
                value: spec.jump,
                min: 0,
                max: 5000,
                width: 64,
                onChanged: (v) => set(spec.copyWith(jump: v), live: true),
                onCommit: commit,
              ),
              CanvasNumberField(
                key: const ValueKey("playGravity"),
                label: "Gravity",
                value: spec.gravity,
                min: 0,
                max: 20000,
                width: 70,
                onChanged: (v) => set(spec.copyWith(gravity: v), live: true),
                onCommit: commit,
              ),
            ],
            if (spec.as == PlayAs.platformer || spec.as == PlayAs.topDown)
              CanvasToggle(
                key: const ValueKey("playFollow"),
                label: "The view follows it",
                value: spec.follow,
                onChanged: (v) => set(spec.copyWith(follow: v)),
              ),
            CanvasHint(switch (spec.as) {
              PlayAs.none => "Played as a game, it plays its own timeline and "
                  "nothing else.",
              PlayAs.platformer => "Walks left and right with the controls, "
                  "falls, and jumps. It lands on whatever is set to be "
                  "something solid, and on the canvas's bottom edge. Speed "
                  "and jump are in the canvas's units.",
              PlayAs.topDown => "Walks every way with the controls, stopped "
                  "by whatever is set to be something solid -- a game seen "
                  "from above.",
              PlayAs.camera => "Moves the view itself with the controls: "
                  "everything else, and the parallax, moves with it.",
              PlayAs.solid => "Something to stand on and to bump into: a "
                  "floor, a platform, a wall.",
            }),
          ],
        ),
      ]);
}
