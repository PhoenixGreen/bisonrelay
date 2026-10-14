#version 460 core

// texture.frag draws a texture layer: grain, paper, grunge, dust, a
// vignette, a light leak, halftone dots or scan lines -- see TextureSpec and
// texture_painter.dart.
//
// Measured in the canvas's own units through uUnit (a thousandth of the
// frame's shorter side), never in screen pixels: the grain is the same grain
// at every zoom and in every export, and the same seed draws the same
// texture every time.

#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;
uniform vec2 uSize;
uniform float uMode;
uniform float uSeed;
uniform float uUnit;
uniform vec4 uA;
uniform vec4 uColour;
uniform vec4 uSecond;

out vec4 fragColor;

float hash(vec2 p) {
  p = p + uSeed * vec2(17.13, 31.71);
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p, float roughness) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 5; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(13.1, 7.7);
    a *= mix(0.35, 0.65, roughness);
  }
  return v;
}

vec4 premul(vec3 c, float a) {
  a = clamp(a, 0.0, 1.0);
  return vec4(c * a, a);
}

void main() {
  vec2 local = FlutterFragCoord().xy - uOrigin;
  // In thousandths of the frame's shorter side.
  vec2 p = local / max(1e-6, uUnit);
  vec2 uv = local / uSize;
  int mode = int(uMode + 0.5);

  if (mode == 0) {
    // Film grain: a grey about the middle, for overlay, finer or coarser.
    vec2 cell = p / max(0.25, uA.x);
    float n = hash(floor(cell)) - 0.5;
    vec3 c = vec3(n);
    if (uA.z > 0.0) {
      c = mix(c, vec3(hash(floor(cell) + 3.1), hash(floor(cell) + 7.7),
                      hash(floor(cell) + 11.3)) - 0.5, uA.z);
    }
    fragColor = vec4(vec3(0.5) + c * uA.y * 0.8, 1.0);
  } else if (mode == 1) {
    // Paper: a soft mottle, and fibres stretched one way.
    float mottle = fbm(p / max(1.0, uA.x), 0.5);
    float fibre = noise(vec2(p.x / max(1.0, uA.x) * 6.0, p.y / max(1.0, uA.x) * 0.4));
    float n = mix(mottle, fibre, uA.y * 0.5);
    vec3 c = uColour.rgb * (1.0 - uA.z * 0.35 + n * uA.z * 0.5);
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
  } else if (mode == 2) {
    // Grunge: blotches where the noise rises past how much is to be covered.
    float n = fbm(p / max(1.0, uA.x), uA.z);
    float edge = 1.0 - uA.y;
    float a = smoothstep(edge - 0.08, edge + 0.08, n);
    fragColor = premul(uColour.rgb, a * uColour.a);
  } else if (mode == 3) {
    // Dust and scratches: sparse specks, and thin lines down the picture.
    // Round specks of different sizes, one at most to a cell, few cells
    // with any.
    vec2 g = p / max(0.5, uA.z) / 3.0;
    vec2 cell = floor(g);
    vec2 at = vec2(hash(cell + 1.7), hash(cell + 4.3)) * 0.6 + 0.2;
    float r = 0.12 + 0.25 * hash(cell + 9.1);
    float speck = step(1.0 - uA.x * 0.012, hash(cell)) *
                  (1.0 - smoothstep(r * 0.5, r, length(fract(g) - at)));
    float lane = floor(p.x / 4.0);
    float scratch = step(1.0 - uA.y * 0.03, hash(vec2(lane, 0.37)));
    float along = smoothstep(0.2, 0.8, noise(vec2(lane, p.y / 140.0)));
    float a = max(speck, scratch * along * 0.8);
    fragColor = premul(uColour.rgb, a * uColour.a);
  } else if (mode == 4) {
    // Vignette: clear in the middle, colour towards the edges -- round, or
    // following the frame's shape.
    vec2 d = uv - 0.5;
    d.x *= mix(1.0, uSize.x / uSize.y, uA.z);
    float r = length(d) * 2.0 / mix(1.0, max(1.0, uSize.x / uSize.y), uA.z) ;
    float a = smoothstep(uA.x, uA.x + max(0.01, uA.y), r);
    fragColor = premul(uColour.rgb, a * uColour.a);
  } else if (mode == 5) {
    // Light leak: two soft pools of warm light from the edges.
    vec2 c1 = vec2(hash(vec2(1.0, 2.0)) * 0.3, 0.1 + hash(vec2(3.0, 4.0)) * 0.8);
    vec2 c2 = vec2(0.7 + hash(vec2(5.0, 6.0)) * 0.3, hash(vec2(7.0, 8.0)));
    float s = mix(0.2, 0.9, uA.x);
    float soft = mix(0.05, 1.0, uA.y);
    float a1 = 1.0 - smoothstep(s * (1.0 - soft), s, distance(uv, c1));
    float a2 = 1.0 - smoothstep(s * 0.8 * (1.0 - soft), s * 0.8, distance(uv, c2));
    vec3 c = uColour.rgb * a1 + uSecond.rgb * a2;
    float a = clamp(max(a1, a2) * uA.z, 0.0, 1.0);
    fragColor = premul(c / max(1e-3, a1 + a2) * (a1 + a2 > 0.0 ? 1.0 : 0.0), a);
  } else if (mode == 6) {
    // Halftone dots, on a turned grid.
    float t = radians(uA.y);
    mat2 turn = mat2(cos(t), -sin(t), sin(t), cos(t));
    vec2 q = turn * p / max(1.0, uA.x);
    vec2 f = fract(q) - 0.5;
    float a = 1.0 - smoothstep(uA.z * 0.5 - 0.04, uA.z * 0.5 + 0.04, length(f));
    fragColor = premul(uColour.rgb, a * uColour.a);
  } else {
    // Scan lines.
    float t = radians(uA.z);
    float across = dot(p, vec2(-sin(t), cos(t)));
    float f = fract(across / max(1.0, uA.x));
    float a = 1.0 - smoothstep(uA.y - 0.05, uA.y + 0.05, f);
    fragColor = premul(uColour.rgb, a * uColour.a);
  }
}
