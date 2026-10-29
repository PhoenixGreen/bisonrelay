import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_settings.dart';
import 'package:flutter/material.dart';

// backdrop_settings.dart is the first choice in a background's Pattern
// layers -- a flat pattern or a 3D stage -- and the stage's settings for
// when it is a stage. Shared by the canvas's own background and the
// Background element, which make the same choice.

/// backdropKindPicker chooses what a background draws.
Widget backdropKindPicker(
        BackdropKind kind, ValueChanged<BackdropKind> onPick) =>
    CanvasControlGroup(
      label: "Background",
      help: "A 2D background is a generated pattern, with layers laid over "
          "it. A 3D stage is a floor and a wall seen through a camera, that "
          "characters stand on: the camera places them, sizes them for how "
          "far away they are, and turns them as it swings round. Each keeps "
          "its own settings, so trying the other loses nothing.",
      children: [
        CanvasSegmented<BackdropKind>(
          key: const ValueKey("backdropKind"),
          options: [for (var k in BackdropKind.values) (k, k.label)],
          value: kind,
          keyOf: (k) => "backdropKind-${k.name}",
          onChanged: onPick,
        ),
      ],
    );

/// stageBackdropSettings is a background's settings while it is a stage:
/// the Pattern layers section with only the choice in it -- there are no
/// pattern layers on a stage -- then the stage's camera, set and light.
///
/// [write] is handed the stage as edited, with its camera's keys on its
/// track, for the caller to put back where the stage lives.
List<Widget> stageBackdropSettings(
  BuildContext context,
  CanvasController controller,
  StageElement stage, {
  required Widget picker,
  required void Function(StageElement) write,
  required VoidCallback begin,
  required VoidCallback commit,
  required String rememberAs,
}) =>
    [
      CanvasSection(
        key: const ValueKey("backgroundSection-layers"),
        icon: Icons.layers_outlined,
        title: "Pattern layers",
        summary: BackdropKind.stage.label,
        remember: "$rememberAs.layers",
        initiallyOpen: true,
        children: [picker],
      ),
      ...stageSettings(context, controller, stage,
          (next) => write(next as StageElement), begin, commit),
    ];
