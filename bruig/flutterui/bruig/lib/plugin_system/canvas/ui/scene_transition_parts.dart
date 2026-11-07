import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/transition_sound.dart';
import 'package:flutter/material.dart';

// scene_transition_parts.dart is how one scene gives way to the next, in the
// parts the Animation panel lays side by side for a scene picked from the
// timeline: which transition, how long, what it looks like, its sound, and
// where it comes from. On the master canvas it is the default, used by every
// scene without a transition of its own.

/// TransitionPart is one part of a scene's transition.
enum TransitionPart { choice, timing, looks, sound, source }

/// SceneTransitionTarget is the transition [scene] gives way with, and how
/// to write it: the default on the master canvas, else the one after the
/// scene.
class SceneTransitionTarget {
  final CanvasController controller;
  final int scene;
  const SceneTransitionTarget(this.controller, this.scene);

  bool get master => controller.document.editingMaster;

  SceneTransition get value => master
      ? controller.document.defaultTransition
      : controller.document.transitionAfter(scene);

  /// last is whether there is no scene after it to give way to.
  bool get last => !master && scene >= controller.document.allScenes.length - 1;

  void write(SceneTransition next) => master
      ? controller.setDefaultTransition(next)
      : controller.setSceneTransition(scene, next);

  /// shows is whether [part] has anything to show for this transition: a
  /// cut has no length, look or sound, and the master's is where every
  /// other comes from.
  bool shows(TransitionPart part) {
    var v = value;
    return switch (part) {
      TransitionPart.choice => true,
      TransitionPart.timing || TransitionPart.sound => v.on,
      TransitionPart.looks => v.on && _looks(v),
      TransitionPart.source => !master,
    };
  }
}

/// _started is [value] changed to another kind, set up the way that kind
/// looks best: one set of settings cannot suit every kind (six suits blinds
/// but not halftone dots). The colour is carried over, as a design choice.
SceneTransition _started(SceneTransition value, SceneTransitionKind kind) =>
    SceneTransition.bestFor(kind).copyWith(color: value.color);

/// _looks is whether a transition has anything to say about how it looks.
bool _looks(SceneTransition value) {
  var kind = value.kind;
  return kind.takesColour ||
      kind.takesWay ||
      kind.takesShape ||
      kind.takesCount ||
      kind.takesSpacing ||
      kind.takesRadius ||
      kind.takesAngle ||
      kind.takesCentre ||
      kind.takesSoftness;
}

/// SceneTransitionPart is [part] of [target]'s transition: its controls,
/// down a column.
class SceneTransitionPart extends StatelessWidget {
  final SceneTransitionTarget target;
  final TransitionPart part;

  /// onPreview plays the transition on the canvas.
  final VoidCallback? onPreview;

  const SceneTransitionPart(
      {required this.target, required this.part, this.onPreview, super.key});

  @override
  Widget build(BuildContext context) {
    var value = target.value;
    var write = target.write;
    var document = target.controller.document;
    Widget column(List<Widget> children) => CanvasControlScope(
          maxWidth: 260,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );
    return switch (part) {
      TransitionPart.choice => column([
          // The family first, then the kind, rather than two dozen names in
          // one list. Choosing a family applies its first kind, so the canvas
          // shows something at once.
          CanvasDropdown<SceneTransitionFamily>(
            key: const ValueKey("transitionFamily"),
            label: "Gives way with",
            value: value.kind.familyOf,
            width: 160,
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
              width: 190,
              options: [
                for (var k in SceneTransitionKind.inFamily(value.kind.familyOf))
                  (k, k.label)
              ],
              onChanged: (v) => write(_started(value, v)),
            ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            CanvasIconButton(
              key: const ValueKey("resetTransition"),
              icon: Icons.restart_alt,
              tooltip: "Put every setting here back to what this "
                  "transition looks best at",
              onPressed: () => write(SceneTransition.bestFor(value.kind)),
            ),
            CanvasIconButton(
              key: const ValueKey("previewTransition"),
              icon: Icons.play_circle_outline,
              tooltip: target.last
                  ? "The last scene gives way to nothing"
                  : "Play it on the canvas",
              onPressed: target.last ? null : onPreview,
            ),
          ]),
        ]),
      TransitionPart.timing => column([
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
            options: [for (var e in SceneTransitionEase.values) (e, e.label)],
            onChanged: (v) => write(value.copyWith(ease: v)),
          ),
        ]),
      TransitionPart.looks => column([
          if (value.kind.takesColour)
            CanvasColorButton(
              label: value.kind.covers ? "Colour" : "Through",
              color: value.color,
              onChanged: (c) => write(value.copyWith(color: c)),
            ),
          if (value.kind.takesWay)
            CanvasDropdown<SceneTransitionWay>(
              key: const ValueKey("transitionWay"),
              label: "Which way",
              // The way it points, or this kind's first way if the saved one
              // is not in its list (older barn doors point right): a dropdown
              // whose value is not among its options shows nothing.
              value: SceneTransitionWay.waysFor(value.kind).contains(value.way)
                  ? value.way
                  : SceneTransitionWay.waysFor(value.kind).first,
              width: 140,
              // The ways this kind has, in its own words: barn doors have an
              // axis, and shapes can stay put instead of travelling.
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
          // Where a zoom grows from: the middle, or anywhere on the page.
          if (value.kind.takesCentre) ...[
            CanvasNumberField(
              key: const ValueKey("transitionCentreX"),
              label: "Centre across",
              value: value.centreX,
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              onChanged: (v) => write(value.copyWith(centreX: v)),
            ),
            CanvasNumberField(
              key: const ValueKey("transitionCentreY"),
              label: "Centre down",
              value: value.centreY,
              min: 0,
              max: 1,
              decimals: 2,
              width: 62,
              onChanged: (v) => write(value.copyWith(centreY: v)),
            ),
          ],
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
      TransitionPart.sound => column([
          CanvasTransitionSound(
            value: value,
            onChanged: write,
            onEvery: (t) => target.controller.soundEveryTransition(t),
          ),
        ]),
      TransitionPart.source => column([
          CanvasToggle(
            key: const ValueKey("transitionCustom"),
            label: "Set on this ${document.kind.one}",
            value: document.allScenes[target.scene].custom,
            onChanged: (v) => target.controller.setSceneTransition(target.scene,
                v ? document.transitionAfter(target.scene) : null),
          ),
        ]),
    };
  }
}
