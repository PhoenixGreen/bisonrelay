import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// canvas_transition_bar.dart is how one scene gives way to the next.
//
// A line over the timeline, like the pose bar next to it and for the same
// reason: it belongs to the moment being worked on rather than to the
// document, and a strip that pushed the canvas up every time it opened would
// move the design while somebody was looking at it.
//
// It edits one thing: the transition after the scene showing. On the master
// canvas it edits the default instead -- the one every scene without a
// transition of its own uses -- which is what makes the master the place
// where the look of the whole sequence is decided.

class CanvasTransitionBar extends StatelessWidget {
  final CanvasController controller;

  /// onPreview plays the transition on the canvas. Null where there is
  /// nothing to play -- the last scene gives way to nothing.
  final VoidCallback? onPreview;

  const CanvasTransitionBar({
    required this.controller,
    this.onPreview,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _bar(context),
      );

  Widget _bar(BuildContext context) {
    var theme = ThemeNotifier.of(context);
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

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainerLow,
        border: Border(
            top: BorderSide(color: theme.colors.outlineVariant, width: 1)),
      ),
      child: CanvasControlScope(
        maxWidth: 400,
        inline: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CanvasControlGroup(
              label: master
                  ? "Every scene, unless it says otherwise"
                  : "After ${scenes[index].saysAt(index)}",
              children: [
                CanvasDropdown<SceneTransitionKind>(
                  key: const ValueKey("transitionKind"),
                  label: "Gives way with",
                  value: value.kind,
                  width: 168,
                  options: [
                    for (var k in SceneTransitionKind.values) (k, k.label)
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
                      label: "Through",
                      color: value.color,
                      onChanged: (c) => write(value.copyWith(color: c)),
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
          ]),
        ),
      ),
    );
  }
}

/// Overlap is how many frames the two scenes are both playing for -- see
/// SceneTransition.overlap. Nothing means the outgoing scene is held on its
/// last frame while the incoming one waits, which is what a fade through a
/// colour usually wants; the same number as the length is a straight cross
/// over.
