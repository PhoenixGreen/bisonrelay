import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/character_look.dart';
import 'package:bruig/plugin_system/canvas/render/vrm/vrm_mesh.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

// vrm_look.dart draws a new 3D character in its CharacterLook: the
// materials' shading, shadow colour and highlights set for the look, and a
// finish over the whole picture (shaders/studio_finish.frag) that draws the
// lines from the character's depth and normals, grades its colour, lays it
// on paper, and gives it the look's finish -- manga, pencil, watercolour,
// painterly, comic or ink sketch.

/// StudioFinishPass is the finish, run on the picture as it is seen.
class StudioFinishPass extends CustomRenderPass {
  final gpu.Shader shader;
  CharacterLook look;

  /// pixelRatio is the screen's, so lines are as thick on every screen.
  double pixelRatio;

  /// paper is whether the look's paper is drawn behind the figure: not on
  /// a canvas, where the figure stands on whatever is behind it.
  bool paper;

  StudioFinishPass(this.shader, this.look,
      {this.pixelRatio = 1, this.paper = true});

  static Future<gpu.Shader?>? _shader;

  /// load is the finish's shader, once: null where it could not be loaded.
  static Future<gpu.Shader?> load() => _shader ??= () async {
        try {
          final lib = await gpu.loadShaderLibraryAsync(
              await gpu.resolveShaderBundleKey('studio'));
          return lib?['StudioFinish'];
        } catch (_) {
          return null;
        }
      }();

  @override
  String get name => 'studio-finish';

  @override
  RenderStage get stage => RenderStage.afterToneMapping;

  @override
  Set<RenderInput> get inputs => const {RenderInput.normals};

  static final gpu.SamplerOptions _nearest = gpu.SamplerOptions(
    minFilter: gpu.MinMagFilter.nearest,
    magFilter: gpu.MinMagFilter.nearest,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );

  @override
  void execute(RenderPassContext context) {
    final depth = context.sceneDepthLinear;
    if (depth == null) return;
    context.applyShader(
      shader,
      textures: {'linear_depth': depth},
      samplers: {'linear_depth': _nearest},
      uniforms: {
        'Finish':
            ByteData.sublistView(finishUniforms(look, pixelRatio, paper: paper))
      },
      frameInfo: true,
    );
  }
}

/// finishUniforms are [l]'s dials as the finish's Finish block holds them:
/// eight vec4s.
/// With no [paper], the figure is drawn alone, clear round it.
Float32List finishUniforms(CharacterLook l, double px, {bool paper = true}) {
  final on = l.lineStyle != "none";
  final pencil = l.lineStyle == "pencil";
  List<double> rgb(int c) =>
      [((c >> 16) & 0xff) / 255, ((c >> 8) & 0xff) / 255, (c & 0xff) / 255, 1];
  return Float32List.fromList([
    // lines: inner, inner reach, silhouette, wobble
    on ? l.inner : 0, (0.7 + l.width * 0.9) * px, on && pencil ? 0.85 : 0,
    pencil ? 1.4 : (l.lineStyle == "brush" ? 0.5 : 0),
    // style: outline reach, grain, finish, tinted
    on && !pencil ? (0.6 + l.width * 3.2) * px : 0, pencil ? 0.8 : 0,
    switch (l.render) {
      "manga" => 1,
      "pencil" => 2,
      "watercolour" => 3,
      "painterly" => 4,
      "comic" => 5,
      "sketch" => 6,
      _ => 0, //
    }
        .toDouble(),
    l.lineMode == "tinted" ? 1 : 0,
    l.sat, l.bright, l.warmth, l.bands,
    l.tone, l.contrast, l.hatch, l.wash,
    l.bleed, l.edge, l.brush, l.dots,
    l.paper, paper ? 0 : 1, 0, 0,
    ...rgb(l.lineColour),
    ...rgb(l.paperColour),
  ]);
}

/// lightDirection is the way [l]'s light travels, for the scene's light:
/// from the viewer's left, the front, the right, or above.
vm.Vector3 lightDirection(CharacterLook l) {
  // Where the light is, with the character facing the camera along -z.
  final at = switch (l.light) {
    "front" => vm.Vector3(0, 1.6, -3),
    "right" => vm.Vector3(-1.6, 2.2, -2.2),
    "top" => vm.Vector3(-0.2, 3.4, -1),
    _ => vm.Vector3(1.6, 2.2, -2.2),
  };
  return -at.normalized();
}

/// shadowTints are the shadow colours a look's shadowTint names.
const Map<String, (double, double, double)> _tints = {
  "neutral": (0.62, 0.62, 0.66),
  "warm": (0.78, 0.6, 0.6),
  "cool": (0.6, 0.64, 0.8),
  "purple": (0.66, 0.56, 0.78),
};

/// styleMaterial sets an MToon [m], drawing [part], as [l] draws it:
/// how sharply it turns from light to shade, how dark and what colour the
/// shade, and its rim of light. [base] is the colour it is drawn in.
void styleMaterial(PreprocessedMaterial m, VrmPart? part, CharacterLook l,
    {vm.Vector3? base, bool cloth = false}) {
  final p = m.parameters;
  final b = base ?? vm.Vector3(1, 1, 1);
  // Eyes, brows and the inside of the mouth are lit, never shaded.
  final lit =
      part == VrmPart.eyes || part == VrmPart.brows || part == VrmPart.mouth;
  final mode = lit
      ? "none"
      : (part == VrmPart.face && l.shading == "cel" ? "soft" : l.shading);
  final a = l.amount;
  final (toony, shift) = switch (mode) {
    "none" => (0.95, -1.0),
    "cel" => (0.97, 0.25 - a * 0.9),
    "soft" => (0.6, 0.1 - a * 0.7),
    _ => (0.08, -0.1 - a * 0.3),
  };
  final t = _tints[l.shadowTint] ?? _tints["neutral"]!;
  final face = part == VrmPart.face;
  final k = lit ? 0.0 : (face ? 0.18 : 0.35) + a * (face ? 0.35 : 0.65);
  final shade = vm.Vector3(b.x * t.$1, b.y * t.$2, b.z * t.$3);
  final rimOn = !lit && (l.highlight == "rim" || l.highlight == "both");
  // A glossy shine on hair and the like; skin and cloth stay matt.
  final gloss = !lit &&
      !cloth &&
      (l.highlight == "gloss" || l.highlight == "both") &&
      !const [VrmPart.face, VrmPart.skin, VrmPart.top, VrmPart.bottom]
          .contains(part);
  if (gloss) {
    final t = glossTexture();
    p.setTexture('matcap_texture', t.gpuTexture, sampler: t.sampledSampler);
  }
  final r = rimOn ? 0.55 * l.shine : 0.0;
  p
    ..setFloat('shading_toony_factor', toony)
    ..setFloat('shading_shift_factor', shift)
    ..setVec3('shade_color_factor', b + (shade - b) * k)
    ..setVec3('parametric_rim_color_factor', vm.Vector3(r, r, r * 1.1))
    ..setFloat('parametric_rim_fresnel_power_factor', 4)
    ..setFloat('parametric_rim_lift_factor', 0.05)
    ..setFloat('rim_lighting_mix_factor', 1)
    ..setVec3('matcap_factor', vm.Vector3.all(gloss ? 0.5 * l.shine : 0))
    ..setVec3('emissive_factor', vm.Vector3.zero());
}

Texture2D? _gloss;

/// glossTexture is the shine a glossy look lays on: a soft white spot high
/// on the left of a black ground, seen as the surface turns to the light.
Texture2D glossTexture() => _gloss ??= () {
      const n = 128;
      final px = Uint8List(n * n * 4);
      for (var y = 0; y < n; y++) {
        for (var x = 0; x < n; x++) {
          final d = math.sqrt((x + 0.5 - 46) * (x + 0.5 - 46) +
              (y + 0.5 - 40) * (y + 0.5 - 40));
          final t = ((d - 2) / 28).clamp(0.0, 1.0);
          // White to light grey by a third of the way, then to black.
          final v =
              t < 0.35 ? 255 - (34 * t / 0.35) : 221 * (1 - (t - 0.35) / 0.65);
          final at = (y * n + x) * 4;
          px[at] = px[at + 1] = px[at + 2] = v.round().clamp(0, 255);
          px[at + 3] = 255;
        }
      }
      return Texture2D.fromPixels(px, n, n);
    }();
