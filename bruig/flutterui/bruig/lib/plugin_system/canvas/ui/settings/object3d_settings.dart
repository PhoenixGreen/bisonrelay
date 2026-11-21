import 'package:flutter/material.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/object3d_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart'
    show AssetKind, CanvasLibrary, LibraryAsset;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart'
    show modelClipsOnto;
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';

/// object3dSettings is a 3D object's own sections: which model it shows and
/// how it is seen in its box, and the animations read from its file.
List<Widget> object3dSettings(
  BuildContext context,
  CanvasController controller,
  Object3dElement e,
  void Function(CanvasElement) write,
  VoidCallback begin,
  VoidCallback commit,
) =>
    [
      section(e, "object3d",
          icon: Icons.view_in_ar,
          title: "3D object",
          summary: e.assetId.isEmpty
              ? "No model yet"
              : "${e.animations.length} animations of its own",
          children: [
            _ModelChoice(
              element: e,
              onPick: (a) {
                begin();
                var next = e.copyWith(assetId: a.id, animations: a.animations);
                write(next.withBase(
                    // Named after its model, unless renamed.
                    name: e.base.name == "3D object" ? a.name : null,
                    motion: modelClipsOnto(e.base.motion, e.id, a.animations)));
                commit();
              },
            ),
            CanvasControlGroup(
                label: "Seen",
                help: "How it is seen in its box. On a 3D stage, "
                    "the stage's camera sees it instead.",
                children: [
                  for (var (key, label, value, min, max, set) in [
                    (
                      "turn",
                      "Turn",
                      e.turn,
                      -360.0,
                      360.0,
                      (double v) => e.copyWith(turn: v)
                    ),
                    (
                      "tilt",
                      "Tilt",
                      e.tilt,
                      -89.0,
                      89.0,
                      (double v) => e.copyWith(tilt: v)
                    ),
                    (
                      "zoom",
                      "Closer",
                      e.zoom,
                      0.2,
                      8.0,
                      (double v) => e.copyWith(zoom: v)
                    ),
                  ])
                    CanvasNumberField(
                      key: ValueKey("object3d-$key"),
                      label: label,
                      value: value,
                      min: min,
                      max: max,
                      decimals: key == "zoom" ? 2 : 0,
                      width: 64,
                      onChanged: (v) {
                        begin();
                        write(set(v));
                      },
                      onCommit: commit,
                    ),
                ]),
          ]),
      // The animations read from its file.
      section(e, "object3dAnimations",
          icon: Icons.animation,
          title: "Its animations",
          summary: e.animations.isEmpty
              ? "None in its file"
              : [for (var (n, _) in e.animations) n].join(", "),
          children: [
            if (e.animations.isEmpty)
              const CanvasHint("This model has no animations of its "
                  "own: it moves as any element does, by clips.")
            else
              CanvasControlGroup(
                  label: "Its animations",
                  help: "Read from its file, and in its slots as "
                      "clips From the model: played, placed on the "
                      "timeline and layered as any clip is.",
                  children: [
                    CanvasTextButton(
                      key: const ValueKey("object3dSlots"),
                      label: "Put them in its slots again",
                      onPressed: () {
                        begin();
                        write(e.withBase(
                            motion: modelClipsOnto(
                                e.base.motion, e.id, e.animations)));
                        commit();
                      },
                    ),
                  ]),
          ]),
    ];

/// _ModelChoice is which of the library's 3D objects a 3D object shows. One
/// added from the Add panel starts with none and is given one here.
class _ModelChoice extends StatefulWidget {
  final Object3dElement element;
  final ValueChanged<LibraryAsset> onPick;
  const _ModelChoice({required this.element, required this.onPick});

  @override
  State<_ModelChoice> createState() => _ModelChoiceState();
}

class _ModelChoiceState extends State<_ModelChoice> {
  late final Future<List<LibraryAsset>> _models =
      CanvasLibrary.list(kind: AssetKind.model);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LibraryAsset>>(
        future: _models,
        builder: (context, got) {
          if (got.connectionState != ConnectionState.done) {
            return const SizedBox(height: 32);
          }
          var models = got.data ?? const <LibraryAsset>[];
          var now = widget.element.assetId;
          if (models.isEmpty && now.isEmpty) {
            return const CanvasHint(
                "No 3D objects in the library yet. Add a .glb file under "
                "Assets › 3D objects, then choose it here.",
                key: ValueKey("object3dNoModels"));
          }
          return CanvasControlGroup(
              label: "Model",
              help: "Which of the library's 3D objects it shows. Its own "
                  "animations come with it, as clips in its slots.",
              children: [
                CanvasDropdown<String>(
                  key: const ValueKey("object3dModel"),
                  label: "Model",
                  value: now,
                  width: 200,
                  options: [
                    if (now.isEmpty) ("", "None yet"),
                    if (now.isNotEmpty && !models.any((m) => m.id == now))
                      (now, "Not in the library"),
                    for (var m in models) (m.id, m.name),
                  ],
                  onChanged: (id) {
                    var picked = models.where((m) => m.id == id).firstOrNull;
                    if (picked != null && id != now) widget.onPick(picked);
                  },
                ),
              ]);
        },
      );
}
