#version 460 core

// heal.frag is the healing brush: the spot filled with the light and colour
// of what is round it (uFill), with the fine detail -- grain, texture, the
// small edges -- of a patch beside it (uOffset away) laid back over that.
// The detail is the patch less a blur of itself, so its own colour does not
// come with it. In the picture's own pixels: uSize is its size, and uFillRect
// where the fill was drawn (left, top, width, height). See brush_painter.dart.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uOffset;
uniform vec4 uFillRect;
uniform sampler2D uImage;
uniform sampler2D uBlur;
uniform sampler2D uFill;

out vec4 fragColor;

vec3 straight(vec4 c, vec3 otherwise) {
  return c.a > 0.0 ? c.rgb / c.a : otherwise;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec4 f = texture(uFill, (p - uFillRect.xy) / uFillRect.zw);
  if (f.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 fill = f.rgb / f.a;
  vec2 from = (p + uOffset) / uSize;
  vec3 near = straight(texture(uImage, from), fill);
  vec3 soft = straight(texture(uBlur, from), near);
  vec3 healed = clamp(fill + (near - soft), 0.0, 1.0);
  fragColor = vec4(healed * f.a, f.a);
}
