#version 460 core

// sharpen.frag is the sharpening brush's unsharp mask: the picture, pushed
// away from a blurred copy of itself by uAmount -- which is what makes an
// edge crisper, and leaves a flat area as it was. In the picture's own
// pixels: uSize is its size. See brush_painter.dart.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uAmount;
uniform sampler2D uImage;
uniform sampler2D uBlur;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uImage, uv);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec4 b = texture(uBlur, uv);
  vec3 sharp = c.rgb / c.a;
  vec3 soft = b.a > 0.0 ? b.rgb / b.a : sharp;
  vec3 out3 = clamp(sharp + (sharp - soft) * uAmount, 0.0, 1.0);
  fragColor = vec4(out3 * c.a, c.a);
}
