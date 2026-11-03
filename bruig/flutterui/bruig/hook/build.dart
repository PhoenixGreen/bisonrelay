import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

/// Compiles the Flutter GPU shaders the canvas draws with (shaders/gpu/) into
/// flutter_scene_generated/, which pubspec.yaml lists as assets: the new
/// Character Studio's finish, which draws a 3D character's lines and the
/// paper it is on (lib/plugin_system/canvas/render/vrm/vrm_look.dart).
///
/// The shaders under shaders/ itself are Flutter's own fragment programs,
/// listed under flutter: shaders: in pubspec.yaml; these are not those.
void main(List<String> args) async {
  await build(args, (input, output) async {
    await buildTargetShaderBundleJson(
      buildInput: input,
      buildOutput: output,
      manifestFileName: 'shaders/gpu/studio.shaderbundle.json',
    );
  });
}
