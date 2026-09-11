import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// transitions_panel.dart is how one scene gives way to the next.
//
// A panel in the sidebar rather than a line over the timeline. It was a line:
// a dozen controls laid out sideways in a strip four hundred pixels wide,
// which meant scrolling sideways to reach half of them and scrolling back to
// see what the first ones said. These are settings, and settings belong in
// the column the other settings are in -- laid out down the page, where a
// dozen of them is a list rather than a corridor.
//
// It edits one thing: the transition after the scene showing. On the master
// canvas it edits the default instead -- the one every scene without a
// transition of its own uses -- which is what makes the master the place
// where the look of the whole sequence is decided.

class CanvasTransitionsPanel extends StatelessWidget {
  final CanvasController controller;

  /// onPreview plays the transition on the canvas. Null where there is
  /// nothing to play -- the last scene gives way to nothing.
  final VoidCallback? onPreview;

  const CanvasTransitionsPanel({
    required this.controller,
    this.onPreview,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _body(context),
      );

  Widget _body(BuildContext context) {
    var document = controller.document;
    var master = document.editingMaster;
    var index = document.at;
    var scenes = document.allScenes;

    // What is being edited: the default on the master canvas, and the
    // transition after this scene otherwise.
    var custom = !master && scenes[index].custom;
    var value =
        master ? document.defaultTransition : document.transitionAfter(index);

    void write(SceneTransition next) {
      if (master) {
        controller.setDefaultTransition(next);
        return;
      }
      controller.setSceneTransition(index, next);
    }

    var last = !master && index >= scenes.length - 1;

    // Laid out the way the settings panel beside it is: the same scope, the
    // same width, the same gap under the header. Lifted from the line over
    // the timeline, these controls kept that line's arrangement -- captions
    // beside their controls and packed in tight, which is right for a strip
    // and wrong for a column.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: CanvasControlScope(
        maxWidth: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CanvasControlGroup(
              label: master
                  ? "Every scene, unless it says otherwise"
                  : "After ${scenes[index].saysAt(index)}",
              children: [
                // The family first, then the one. Two dozen names in a single
                // list is a wall nobody reads to the end of; asked in two
                // steps the question is "what sort of change" and then
                // "which one". Choosing a family applies the first of its
                // kinds, so the canvas shows something at once.
                CanvasDropdown<SceneTransitionFamily>(
                  key: const ValueKey("transitionFamily"),
                  label: "Gives way with",
                  value: value.kind.familyOf,
                  width: 128,
                  options: [
                    for (var f in SceneTransitionFamily.values)
                      (f, f == SceneTransitionFamily.none ? "A cut" : f.label)
                  ],
                  onChanged: (f) => write(value.copyWith(
                      kind: f == SceneTransitionFamily.none
                          ? SceneTransitionKind.cut
                          : SceneTransitionKind.inFamily(f).first)),
                ),
                if (value.on)
                  CanvasDropdown<SceneTransitionKind>(
                    key: const ValueKey("transitionKind"),
                    label: "Which",
                    value: value.kind,
                    width: 168,
                    options: [
                      for (var k
                          in SceneTransitionKind.inFamily(value.kind.familyOf))
                        (k, k.label)
                    ],
                    onChanged: (v) => write(value.copyWith(kind: v)),
                  ),
                if (value.on) ...[
                  CanvasNumberField(
                    key: const ValueKey("transitionFrames"),
                    label: "Frames",
                    value: value.frames.toDouble(),
                    min: 1,
                    max: 600,
                    decimals: 0,
                    width: 58,
                    onChanged: (v) => write(value.copyWith(frames: v.round())),
                  ),
                  CanvasNumberField(
                    key: const ValueKey("transitionOverlap"),
                    label: "Overlap",
                    value: value.overlap.toDouble(),
                    min: 0,
                    max: 600,
                    decimals: 0,
                    width: 58,
                    onChanged: (v) => write(value.copyWith(overlap: v.round())),
                  ),
                  CanvasDropdown<SceneTransitionEase>(
                    label: "Timing",
                    value: value.ease,
                    width: 128,
                    options: [
                      for (var e in SceneTransitionEase.values) (e, e.label)
                    ],
                    onChanged: (v) => write(value.copyWith(ease: v)),
                  ),
                  if (value.kind.takesColour)
                    CanvasColorButton(
                      label: value.kind.covers ? "Colour" : "Through",
                      color: value.color,
                      onChanged: (c) => write(value.copyWith(color: c)),
                    ),
                  // What the overlay kinds need, and only the ones that need
                  // it: a direction, a shape, how many bars, how soft the
                  // edge is.
                  if (value.kind.takesWay)
                    CanvasDropdown<SceneTransitionWay>(
                      key: const ValueKey("transitionWay"),
                      label: "Which way",
                      value: value.way,
                      width: 128,
                      options: [
                        for (var w in SceneTransitionWay.values) (w, w.label)
                      ],
                      onChanged: (v) => write(value.copyWith(way: v)),
                    ),
                  if (value.kind.takesShape)
                    CanvasDropdown<ShapeKind>(
                      key: const ValueKey("transitionShape"),
                      label: "Shape",
                      value: value.shape,
                      width: 140,
                      options: [for (var k in ShapeKind.values) (k, k.label)],
                      onChanged: (v) => write(value.copyWith(shape: v)),
                    ),
                  if (value.kind.takesCount)
                    CanvasNumberField(
                      key: const ValueKey("transitionCount"),
                      label: switch (value.kind) {
                        SceneTransitionKind.blinds => "Bars",
                        SceneTransitionKind.burst => "Rays",
                        SceneTransitionKind.brush => "Strokes",
                        SceneTransitionKind.splatter => "Splats",
                        SceneTransitionKind.tiles => "Across",
                        SceneTransitionKind.halftone => "Dots",
                        SceneTransitionKind.arrow => "Arrows",
                        _ => "How many",
                      },
                      value: value.count.toDouble(),
                      min: 1,
                      max: 40,
                      decimals: 0,
                      width: 54,
                      onChanged: (v) => write(value.copyWith(count: v.round())),
                    ),
                  if (value.kind.takesSpacing)
                    CanvasNumberField(
                      key: const ValueKey("transitionSpacing"),
                      label: "Apart",
                      value: value.spacing,
                      min: 0,
                      max: 2,
                      decimals: 2,
                      width: 58,
                      onChanged: (v) => write(value.copyWith(spacing: v)),
                    ),
                  if (value.kind.takesRadius)
                    CanvasNumberField(
                      key: const ValueKey("transitionRadius"),
                      label: "Size",
                      value: value.radius,
                      min: 0.05,
                      max: 1,
                      decimals: 2,
                      width: 58,
                      onChanged: (v) => write(value.copyWith(radius: v)),
                    ),
                  if (value.kind.takesAngle)
                    CanvasNumberField(
                      key: const ValueKey("transitionAngle"),
                      label: "Angle",
                      value: value.angle,
                      min: -180,
                      max: 180,
                      decimals: 0,
                      width: 58,
                      onChanged: (v) => write(value.copyWith(angle: v)),
                    ),
                  if (value.kind.takesSoftness)
                    CanvasNumberField(
                      key: const ValueKey("transitionSoftness"),
                      label: "Soft edge",
                      value: value.softness,
                      min: 0,
                      max: 1,
                      decimals: 2,
                      width: 62,
                      onChanged: (v) => write(value.copyWith(softness: v)),
                    ),
                ],
                CanvasIconButton(
                  key: const ValueKey("previewTransition"),
                  icon: Icons.play_circle_outline,
                  tooltip: last
                      ? "The last scene gives way to nothing"
                      : "Play it on the canvas",
                  onPressed: last ? null : onPreview,
                ),
              ],
            ),
            // Where this transition came from. Not on the shared canvas,
            // where the transition being edited *is* the one every scene
            // comes from.
            if (!master)
              CanvasControlGroup(label: "Where it comes from", children: [
                CanvasToggle(
                  key: const ValueKey("transitionCustom"),
                  label: "Set on this scene",
                  value: custom,
                  onChanged: (v) => controller.setSceneTransition(
                      index, v ? document.transitionAfter(index) : null),
                ),
                const CanvasHint(
                    "Off, this scene uses the transition set on the master "
                    "scene, and changing that one changes it here. On, it "
                    "keeps its own whatever the master says."),
              ]),
          ],
        ),
      ),
    );
  }
}
