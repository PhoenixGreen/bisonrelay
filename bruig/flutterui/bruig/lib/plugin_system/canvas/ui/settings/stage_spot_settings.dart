import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character3d_element.dart';
import 'package:bruig/plugin_system/canvas/model/stage_spot.dart';
import 'package:bruig/plugin_system/canvas/render/stage/stage_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:flutter/material.dart';

// stage_spot_settings.dart is where an element stands on a 3D stage, set on
// the element: on the page or on a stage, where on its floor, how big, which
// way round, and how it stands. See stage_spot.dart.

/// stageSpotSettings is [e]'s place on a stage, as a section: nothing where
/// it cannot stand on one, or there is no stage to stand on.
List<Widget> stageSpotSettings(
  BuildContext context,
  CanvasController controller,
  CanvasElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) {
  if (!canStand(e)) return const [];
  final doc = controller.document;
  final stages = stagesIn(doc.elements, backdrop: doc.drawnBackground);
  final spot = e.base.spot;
  if (stages.isEmpty && spot == null) return const [];
  void now(CanvasElement next) {
    begin();
    write(next);
    commit();
  }

  // Where it stands on this frame: its own spot, or its keys' -- and set,
  // this frame's key where it is keyed.
  final shown = e.spotAt(controller.frame) ?? spot;
  void live(StageSpot s) {
    begin();
    write(controller.spotted(e, s));
  }

  final stage = spot == null
      ? null
      : stageNamed(spot.stage, doc.elements,
          backdrop: doc.drawnBackground, page: doc.size.rect);
  final size = stage?.size ?? 6;
  final body = e is Character3dElement;
  return [
    section(e, "stageSpot",
        icon: Icons.theater_comedy_outlined,
        title: "On a stage",
        summary: spot == null
            ? "On the page"
            : stages.where((s) => s.$1 == spot.stage).firstOrNull?.$2 ??
                "A stage not here",
        changes: spot == null ? 0 : 1,
        onReset: spot == null ? null : () => now(e.withBase(clearSpot: true)),
        children: [
          CanvasControlGroup(
              label: "Stands on",
              help: "On the page, where its box is; or on a 3D stage, where "
                  "the stage's camera sees it -- moving with the camera as "
                  "the set does, nearer things in front. Drag it on the "
                  "canvas to move it across the floor.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("stageSpotOn"),
                  label: "Stands on",
                  width: 200,
                  value: spot?.stage ?? "",
                  options: [
                    ("", "The page"),
                    for (final (id, name) in stages) (id, name),
                    if (spot != null && stage == null)
                      (spot.stage, "A stage not here"),
                  ],
                  onChanged: (id) {
                    if (id.isEmpty) {
                      now(e.withBase(clearSpot: true));
                      return;
                    }
                    if (spot != null) {
                      now(e.withBase(spot: spot.copyWith(stage: id)));
                      return;
                    }
                    // Each one put a step along from the last, not on top of it.
                    final already = doc.elements
                        .where((x) => x.base.spot?.stage == id)
                        .length;
                    final x = (already.isEven ? 1 : -1) * (already + 1) ~/ 2;
                    now(e.withBase(
                        spot: StageSpot(id, x: x * 1.2, height: 1.6)));
                  },
                ),
                if (spot != null && !body)
                  CanvasDropdown<SpotStand>(
                    key: const ValueKey("stageSpotStand"),
                    label: "How",
                    width: 170,
                    value: spot.stand,
                    options: [for (final s in SpotStand.values) (s, s.label)],
                    onChanged: (s) => now(e.withBase(
                        spot: spot.copyWith(
                            stand: s,
                            // On the wall, its lift is how far up it hangs.
                            lift: s == SpotStand.wall && spot.lift == 0
                                ? 1
                                : null))),
                  ),
              ]),
          if (shown != null)
            CanvasControlGroup(
                label: "Where",
                help: body
                    ? "Where on the floor it stands, in metres from the "
                        "middle, and which way it faces: nought faces where "
                        "the camera starts. It is as tall as it was made."
                    : "Where it stands, in metres from the middle of the "
                        "floor; how big it is -- its longer side, the other "
                        "following its box; and which way it faces.",
                children: [
                  CanvasSlider(
                    key: const ValueKey("stageSpotX"),
                    label: "Across",
                    value: shown.x.clamp(-size, size),
                    min: -size,
                    max: size,
                    decimals: 1,
                    onChanged: (v) => live(shown.copyWith(x: v)),
                    onCommit: commit,
                  ),
                  if (shown.stand != SpotStand.wall)
                    CanvasSlider(
                      key: const ValueKey("stageSpotZ"),
                      label: "Nearer",
                      value: shown.z.clamp(-size, size),
                      min: -size,
                      max: size,
                      decimals: 1,
                      onChanged: (v) => live(shown.copyWith(z: v)),
                      onCommit: commit,
                    ),
                  CanvasSlider(
                    key: const ValueKey("stageSpotLift"),
                    label: shown.stand == SpotStand.wall
                        ? "Up the wall"
                        : "Off the floor",
                    value: shown.lift.clamp(0.0, 6.0),
                    min: 0,
                    max: 6,
                    decimals: 1,
                    onChanged: (v) => live(shown.copyWith(lift: v)),
                    onCommit: commit,
                  ),
                  if (!body)
                    CanvasSlider(
                      key: const ValueKey("stageSpotHeight"),
                      label: "Size",
                      value: shown.height.clamp(0.1, 10.0),
                      min: 0.1,
                      max: 10,
                      decimals: 1,
                      onChanged: (v) => live(shown.copyWith(height: v)),
                      onCommit: commit,
                    ),
                  if (shown.stand == SpotStand.upright ||
                      shown.stand == SpotStand.floor)
                    CanvasSlider(
                      key: const ValueKey("stageSpotFacing"),
                      label: "Facing",
                      value: shown.facing.clamp(-180.0, 180.0),
                      min: -180,
                      max: 180,
                      decimals: 0,
                      onChanged: (v) => live(shown.copyWith(facing: v)),
                      onCommit: commit,
                    ),
                ]),
          if (spot != null)
            CanvasControlGroup(
                label: "On the timeline",
                help: "A key holds where it stands on this frame. With keys "
                    "on two frames it moves between them, as the camera's "
                    "keys move the camera; keyed, moving it -- here or by "
                    "dragging it -- keys it where the playhead is.",
                children: [
                  if (controller.hasSpotKey(e))
                    CanvasTextButton(
                      key: const ValueKey("stageSpotUnkey"),
                      label: "Take this frame's key off",
                      icon: Icons.remove_circle_outline,
                      onPressed: () {
                        begin();
                        controller.clearSpotKey(e);
                        commit();
                      },
                    )
                  else
                    CanvasTextButton(
                      key: const ValueKey("stageSpotKey"),
                      label: "Key where it stands",
                      icon: Icons.add_circle_outline,
                      onPressed: () {
                        begin();
                        controller.keySpot(e);
                        commit();
                      },
                    ),
                ]),
        ]),
  ];
}
