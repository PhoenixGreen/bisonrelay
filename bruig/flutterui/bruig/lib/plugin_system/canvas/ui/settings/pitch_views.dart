import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';

// pitch_views.dart is a pitch camera's shots and saved views: the five
// places a camera usually is for each View, and the ones somebody has kept.

/// pitchCameraKeys are the settings a camera is: what a shot or a saved view
/// puts in place, "zoom" being the spec's Size.
const pitchCameraKeys = [
  "tiltV",
  "tiltH",
  "turn",
  "perspective",
  "panX",
  "panY",
  "zoom",
];

/// pitchCameraOf is [spec]'s camera, as a shot or a saved view holds one.
Map<String, double> pitchCameraOf(ProceduralSpec spec) {
  var params = pitchCameraParams(spec.params);
  return {
    for (var k in pitchCameraKeys)
      k: k == "zoom" ? spec.scale / 0.05 : (params[k] ?? 0),
  };
}

/// withPitchCamera is [spec] seen through [camera].
ProceduralSpec withPitchCamera(
    ProceduralSpec spec, Map<String, double> camera) {
  var next = spec;
  for (var MapEntry(:key, :value) in camera.entries) {
    next = key == "zoom"
        ? next.copyWith(scale: value * 0.05)
        : next.withParam(key, value);
  }
  return next;
}

bool _sameCamera(Map<String, double> a, Map<String, dynamic> b) =>
    pitchCameraKeys.every((k) {
      var v = b[k];
      return v is num && ((a[k] ?? 0) - v).abs() < 0.01;
    });

/// pitchShotDropdown is the five shots [spec]'s View offers, the one it is
/// on picked out -- or Custom, once the camera has been moved off them.
Widget pitchShotDropdown(
    ProceduralSpec spec, ValueChanged<ProceduralSpec> onChanged) {
  var view = spec.choice("view");
  var shots = pitchShots[view] ?? const [];
  var now = pitchShotOf(view, pitchCameraParams(spec.params), spec.scale);
  return CanvasDropdown<int>(
    key: const ValueKey("pitchShot"),
    label: "Shot",
    value: now,
    width: 128,
    options: [
      if (now < 0) (-1, "Custom"),
      for (var (i, (name, _)) in shots.indexed) (i, name),
    ],
    onChanged: (i) {
      if (i < 0) return;
      onChanged(withPitchCamera(spec, shots[i].$2));
    },
  );
}

/// PitchSavedViews keeps cameras: the one in use saved under a name, and
/// any saved one put back. Watches the saved views, which are shared by
/// every pitch.
class PitchSavedViews extends StatefulWidget {
  final ProceduralSpec spec;
  final ValueChanged<ProceduralSpec> onChanged;

  const PitchSavedViews(
      {super.key, required this.spec, required this.onChanged});

  @override
  State<PitchSavedViews> createState() => _PitchSavedViewsState();
}

class _PitchSavedViewsState extends State<PitchSavedViews> {
  final store = SavedPresetStore.pitchViews;
  String? _name;

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          var camera = pitchCameraOf(widget.spec);
          var saved = store.presets;
          var current =
              saved.where((p) => _sameCamera(camera, p.data)).firstOrNull;
          var name = _name ?? current?.name ?? "View ${saved.length + 1}";
          return CanvasWrap(children: [
            CanvasDropdown<String>(
              key: const ValueKey("pitchSavedView"),
              label: "Saved views",
              value: current?.id ?? "",
              width: 128,
              options: [
                if (current == null) ("", saved.isEmpty ? "None yet" : "—"),
                for (var p in saved) (p.id, p.name),
              ],
              onChanged: (id) {
                var p = saved.where((p) => p.id == id).firstOrNull;
                if (p == null) return;
                setState(() => _name = null);
                widget.onChanged(withPitchCamera(widget.spec, {
                  for (var k in pitchCameraKeys)
                    if (p.data[k] is num) k: (p.data[k] as num).toDouble(),
                }));
              },
            ),
            CanvasTextField(
              key: const ValueKey("pitchViewName"),
              label: "Name",
              value: name,
              width: 96,
              onChanged: (v) => setState(() => _name = v),
            ),
            CanvasIconButton(
              key: const ValueKey("pitchSaveView"),
              icon: Icons.bookmark_add_outlined,
              tooltip: "Save view",
              onPressed: name.trim().isEmpty
                  ? null
                  : () async {
                      // The same name again is the same view, changed.
                      for (var p in saved.where((p) => p.name == name.trim())) {
                        await store.remove(p);
                      }
                      await store.save(name, camera);
                      if (mounted) setState(() => _name = null);
                    },
            ),
            if (current != null)
              CanvasIconButton(
                key: const ValueKey("pitchDeleteView"),
                icon: Icons.delete_outline,
                tooltip: "Delete view",
                onPressed: () async {
                  await store.remove(current);
                  if (mounted) setState(() => _name = null);
                },
              ),
          ]);
        },
      );
}
