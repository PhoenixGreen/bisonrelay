import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/stage_settings.dart';
import 'package:flutter/material.dart';

// backdrop_settings.dart is a background's first Pattern choice (flat or a
// 3D stage) and the stage's settings, for canvas and Background element.

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

/// stageBackdropSettings is a stage background's settings: the kind picker,
/// then camera, set and light. [write] puts back the edited stage.
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
