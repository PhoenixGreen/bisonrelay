#version 460 core

// chroma_key.frag takes one colour out of a picture -- a green screen.
//
// Measured in chroma (the Cb/Cr of YCbCr) and by the colour's direction
// there, not by distance in RGB: a green screen is never one green, it is
// brighter where the lights are and darker in the folds, and those are the
// same hue at different brightness.
//
// See video_key.dart for how it is driven, and ChromaKey for the settings.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec3 uKey;
uniform float uTolerance;
uniform float uSoftness;
uniform float uSpill;
uniform sampler2D uImage;

out vec4 fragColor;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

vec2 chroma(vec3 rgb) {
  float y = dot(rgb, LUMA);
  return vec2((rgb.b - y) * 0.565, (rgb.r - y) * 0.713);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uImage, uv);
  if (c.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  // The sampler hands back premultiplied colour.
  vec3 rgb = c.rgb / c.a;

  vec2 key = chroma(uKey);
  vec2 here = chroma(rgb);
  float keyLen = length(key);

  // How screen-like a pixel is, by the *direction* of its colour rather than
  // how far it is from the key. Chroma shrinks as a colour darkens, so a
  // distance measured in chroma leaves the shadowed folds of a screen behind
  // -- they are the same green, just less of it. So: how far off the key's
  // hue the pixel points (the tangent of the angle between them), and
  // whether it has enough colour at all to be screen rather than a grey
  // that happens to lean green.
  vec2 dir = keyLen > 0.0001 ? key / keyLen : vec2(0.0);
  float along = dot(here, dir);
  float across = length(here - dir * along);
  float angle = along > 0.0 ? across / along : 1000.0;

  float inner = uTolerance * 0.8;
  float outer = inner + uSoftness * 0.8 + 0.0005;
  float hueIn = 1.0 - smoothstep(inner, outer, angle);
  float enough = smoothstep(keyLen * 0.08, keyLen * 0.2, along);
  float alpha = 1.0 - hueIn * enough;

  // Spill: whatever of the screen's hue is left in a kept pixel is taken
  // out, in proportion. Light bounces off the screen onto whoever is in
  // front of it, and without this they wear a green outline.
  if (keyLen > 0.0001) {
    if (along > 0.0) {
      vec2 fixedC = here - dir * along * uSpill;
      float y = dot(rgb, LUMA);
      float b = y + fixedC.x / 0.565;
      float r = y + fixedC.y / 0.713;
      float g = (y - 0.299 * r - 0.114 * b) / 0.587;
      rgb = clamp(vec3(r, g, b), 0.0, 1.0);
    }
  }

  float a = alpha * c.a;
  fragColor = vec4(rgb * a, a);
}
