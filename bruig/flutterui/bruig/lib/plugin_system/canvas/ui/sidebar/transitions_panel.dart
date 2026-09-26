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

/// _started is [value] changed to another kind, set up the way that kind
/// looks best.
///
/// One set of settings cannot suit two dozen transitions -- six is a
/// sensible number of blinds and a poor number of halftone dots -- so
/// changing kind starts from what the new one wants rather than from
/// whatever the last one left behind. Its colour is carried over, because
/// that is a decision about the design rather than about the transition, and
/// somebody who has chosen a pink transition means the next one to be pink
/// too.
SceneTransition _started(SceneTransition value, SceneTransitionKind kind) =>
    SceneTransition.bestFor(kind).copyWith(color: value.color);

/// _looks is whether a transition has anything to say about how it looks.
///
/// A slide has a direction and nothing else; a cut has none of it. Asked
/// before the group is built so an empty heading and a rule under it are not
/// what somebody gets for choosing a plain one.
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
        // The panel's own width, because the top row sizes itself to it. The
        // two names and the two buttons beside them are one question -- what
        // this transition is, and what it looks like -- and a Wrap that
        // breaks them apart puts the buttons on a line of their own with the
        // whole width of the panel to the right of them.
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

    // How much of the line the two names may take. The buttons are each as
    // wide as a control is tall, and every control on the line keeps a gap to
    // its right; what is left is shared between the two dropdowns, the second
    // wider than the first because "Fade through a colour" is a longer thing
    // to say than "Fade". Each still has a floor: past that the name in it is
    // an ellipsis, and three letters and a dot is not a setting anybody can
    // read.
    //
    // Counted from the panel's own constants rather than written out as a
    // number. It was 70 for two buttons and their gaps, which stopped being
    // true the day those gaps were put on one scale with the rest -- and what
    // it looked like was the second button on a line of its own with the
    // width of the panel to the right of it.
    var free = room -
        16 -
        2 * (controlHeight + canvasControlGap) -
        2 * canvasControlGap;
    var family = (free * 0.42).clamp(62.0, 128.0);
    var which = (free * 0.58).clamp(80.0, 168.0);

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
                  : "After ${scenes[index].saysAt(index, document.kind)}",
              // A sentence rather than a section's name, so it is given the
              // room a sentence needs -- close under it, it and the caption
              // of the control below read as one run of text.
              captionGap: 14,
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
                // Back to the beginning. Beside the preview because they are
                // the two ways out of a transition that has been fiddled
                // with past the point of remembering what it was: one says
                // what the fiddling did, the other undoes all of it.
                CanvasIconButton(
                  key: const ValueKey("resetTransition"),
                  icon: Icons.restart_alt,
                  tooltip: "Put every setting here back to what this "
                      "transition looks best at",
                  onPressed: () => write(SceneTransition.bestFor(value.kind)),
                ),
                // Beside the two names rather than at the foot of the panel:
                // the settings under it are for fiddling with, and this is
                // the button that says what the fiddling did.
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
            // How long it takes, kept apart from what it looks like. One
            // group of ten controls is what this panel was, and ten small
            // boxes wrapped into a block read as a field of boxes -- the
            // settings panel beside it splits the same number into Colours,
            // Amount and Movement, and that is the whole difference.
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
            // What it looks like: a colour, a direction, a shape, how many of
            // them, how soft the edge is. Only the ones the kind uses.
            if (value.on && _looks(value))
              CanvasControlGroup(label: "What it looks like", children: [
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
                    // The way it is pointed, or the first one this kind has
                    // if it is pointed somewhere this kind does not go. A
                    // transition set up before barn doors became an axis
                    // holds one pointing right, and a dropdown whose value
                    // is not in its own list shows nothing at all -- which
                    // is a setting that looks like it has not been set.
                    value: SceneTransitionWay.waysFor(value.kind)
                            .contains(value.way)
                        ? value.way
                        : SceneTransitionWay.waysFor(value.kind).first,
                    width: 128,
                    // The ways this kind actually has, said the way this
                    // kind says them. Barn doors have an axis and not four
                    // directions -- "to the left" and "to the right" opened
                    // the same doors -- and the shapes can stay where they
                    // are instead of travelling.
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
