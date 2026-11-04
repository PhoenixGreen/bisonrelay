import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/camera_section.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/cues_section.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transition_sound.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// transitions_panel.dart is how one scene gives way to the next: the settings
// of the transition after the scene showing, laid out down the sidebar. On the
// master canvas it edits the default, used by every scene without a transition
// of its own.

/// _started is [value] changed to another kind, set up the way that kind
/// looks best: one set of settings cannot suit every kind (six suits blinds
/// but not halftone dots). The colour is carried over, as a design choice.
SceneTransition _started(SceneTransition value, SceneTransitionKind kind) =>
    SceneTransition.bestFor(kind).copyWith(color: value.color);

/// _looks is whether a transition has anything to say about how it looks,
/// so a plain one gets no empty heading.
bool _looks(SceneTransition value) {
  var kind = value.kind;
  return kind.takesColour ||
      kind.takesWay ||
      kind.takesShape ||
      kind.takesCount ||
      kind.takesSpacing ||
      kind.takesRadius ||
      kind.takesAngle ||
      kind.takesSoftness;
}

class CanvasTransitionsPanel extends StatelessWidget {
  final CanvasController controller;

  /// onPreview plays the transition on the canvas. Null where there is
  /// nothing to play (the last scene gives way to nothing).
  final VoidCallback? onPreview;

  const CanvasTransitionsPanel({
    required this.controller,
    this.onPreview,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        // The panel's own width, which the top row sizes itself to, so the two
        // names and their two buttons stay on one line.
        builder: (context, _) => LayoutBuilder(
          builder: (context, room) => _body(context, room.maxWidth),
        ),
      );

  Widget _body(BuildContext context, double room) {
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

    // The line's room left for the two dropdowns, after the two buttons
    // (each as wide as a control is tall) and every control's gap, counted
    // from the panel's constants so it follows them. The second dropdown is
    // wider, for names like "Fade through a colour".
    var free = room -
        16 -
        2 * (controlHeight + canvasControlGap) -
        // The two dropdowns are captioned, and keep the wider gap.
        2 * canvasCaptionedGap;
    var family = (free * 0.42).clamp(62.0, 128.0);
    var which = (free * 0.58).clamp(80.0, 168.0);

    // Laid out as the settings panel is: the same scope, width and gap
    // under the header.
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
                  : "After ${document.nameOf(index)}",
              // A sentence rather than a section name, so it gets more room before
              // the next caption.
              captionGap: 14,
              children: [
                // The family first, then the kind, rather than two dozen names in one
                // list. Choosing a family applies its first kind, so the canvas shows
                // something at once.
                CanvasDropdown<SceneTransitionFamily>(
                  key: const ValueKey("transitionFamily"),
                  label: "Gives way with",
                  value: value.kind.familyOf,
                  width: family,
                  tight: true,
                  options: [
                    for (var f in SceneTransitionFamily.values)
                      (f, f == SceneTransitionFamily.none ? "A cut" : f.label)
                  ],
                  onChanged: (f) => write(_started(
                      value,
                      f == SceneTransitionFamily.none
                          ? SceneTransitionKind.cut
                          : SceneTransitionKind.inFamily(f).first)),
                ),
                if (value.on)
                  CanvasDropdown<SceneTransitionKind>(
                    key: const ValueKey("transitionKind"),
                    label: "Which",
                    value: value.kind,
                    width: which,
                    tight: true,
                    options: [
                      for (var k
                          in SceneTransitionKind.inFamily(value.kind.familyOf))
                        (k, k.label)
                    ],
                    onChanged: (v) => write(_started(value, v)),
                  ),
                // Back to the beginning, beside the preview.
                CanvasIconButton(
                  key: const ValueKey("resetTransition"),
                  icon: Icons.restart_alt,
                  tooltip: "Put every setting here back to what this "
                      "transition looks best at",
                  onPressed: () => write(SceneTransition.bestFor(value.kind)),
                ),
                // Beside the two names rather than at the foot of the panel.
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
            // How long it takes, in a group apart from how it looks.
            if (value.on)
              CanvasControlGroup(label: "How long", children: [
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
              ]),
            // What it looks like: only the settings the kind uses.
            if (value.on && _looks(value))
              CanvasControlGroup(label: "What it looks like", children: [
                if (value.kind.takesColour)
                  CanvasColorButton(
                    label: value.kind.covers ? "Colour" : "Through",
                    color: value.color,
                    onChanged: (c) => write(value.copyWith(color: c)),
                  ),
                // What the overlay kinds need: a direction, a shape, how many bars,
                // how soft the edge is.
                if (value.kind.takesWay)
                  CanvasDropdown<SceneTransitionWay>(
                    key: const ValueKey("transitionWay"),
                    label: "Which way",
                    // The way it points, or this kind's first way if the saved one is not
                    // in its list (older barn doors point right): a dropdown whose value
                    // is not among its options shows nothing.
                    value: SceneTransitionWay.waysFor(value.kind)
                            .contains(value.way)
                        ? value.way
                        : SceneTransitionWay.waysFor(value.kind).first,
                    width: 128,
                    // The ways this kind has, in its own words: barn doors have an axis,
                    // not four directions, and shapes can stay put instead of travelling.
                    options: [
                      for (var w in SceneTransitionWay.waysFor(value.kind))
                        (w, w.saysFor(value.kind))
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
              ]),
            if (value.on)
              CanvasTransitionSound(
                value: value,
                onChanged: write,
                onEvery: (t) => controller.soundEveryTransition(t),
              ),
            // Where this transition came from. Not on the shared canvas, whose
            // transition is the default every scene comes from.
            if (!master)
              CanvasControlGroup(label: "Where it comes from", children: [
                CanvasToggle(
                  key: const ValueKey("transitionCustom"),
                  label: "Set on this ${document.kind.one}",
                  value: custom,
                  onChanged: (v) => controller.setSceneTransition(
                      index, v ? document.transitionAfter(index) : null),
                ),
                CanvasHint(
                    "Off, this ${document.kind.one} uses the transition set on "
                    "the master ${document.kind.one}, and changing that one "
                    "changes it here. On, it keeps its own whatever the "
                    "master says."),
              ]),
            CanvasCuesSection(controller: controller),
            if (!master) CanvasCameraSection(controller: controller),
          ],
        ),
      ),
    );
  }
}
