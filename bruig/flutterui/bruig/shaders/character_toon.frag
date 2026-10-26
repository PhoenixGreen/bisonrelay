#version 460 core

// character_toon.frag draws a 3D character as it is drawn by hand: lit a
// pixel at a time from pictures of it made beforehand -- its colours, which
// way each part of it faces, how far away it is, and its shadow colours --
// and inked: a line round its outside, and lines inside it where one part
// stands in front of another or the surface turns sharply.
//
// Every picture is the same size, uSize, and lies over the same pixels. See
// toon_renderer.dart, which makes them.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
// Where the light comes from: x right, y up, z towards the reader.
uniform vec3 uLight;
// 0 soft light, 1 cel bands.
uniform float uMode;
// Cel: how hard the edge between light and shadow is, and how far round.
uniform float uToony;
uniform float uShift;
// Light caught round the rim: colour and strength, and how tight.
uniform vec4 uRim;
uniform float uRimPower;
// The outline's width in pixels, and how strong the lines inside are.
uniform float uLine;
uniform float uInner;
uniform vec4 uInk;
// The shadow as a printed screen: 0 solid, 1 halftone dots, 2 a finer
// screentone at an angle.
uniform float uPattern;

uniform sampler2D uAlbedo;
uniform sampler2D uNormal;
uniform sampler2D uDepth;
uniform sampler2D uShade;

out vec4 fragColor;

float depthAt(vec2 uv) {
  vec4 d = texture(uDepth, uv);
  return d.r + d.g / 255.0;
}

vec3 normalAt(vec2 uv) {
  return normalize(texture(uNormal, uv).xyz * 2.0 - 1.0);
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec4 albedo = texture(uAlbedo, uv);

  // Outside the figure: ink, near enough to it, and nothing further off.
  if (albedo.a < 0.5) {
    if (uLine <= 0.0) {
      fragColor = vec4(0.0);
      return;
    }
    float cover = 0.0;
    for (int k = 0; k < 12; k++) {
      float a = float(k) * 0.5235988;
      vec2 o = vec2(cos(a), sin(a));
      cover = max(cover, texture(uAlbedo, (px + o * uLine) / uSize).a);
      cover = max(cover, texture(uAlbedo, (px + o * uLine * 0.5) / uSize).a);
    }
    float ink = smoothstep(0.3, 0.7, cover) * uInk.a;
    fragColor = vec4(uInk.rgb * ink, ink);
    return;
  }

  vec3 base = albedo.rgb / albedo.a;
  vec3 n = normalAt(uv);
  float ndl = dot(n, normalize(uLight));
  vec3 colour;
  if (uMode > 0.5) {
    vec4 s = texture(uShade, uv);
    vec3 shade = s.a > 0.0 ? s.rgb / s.a : vec3(0.72, 0.66, 0.84);
    float soft = max(0.02, 1.0 - uToony);
    float lit = clamp((ndl + uShift + soft * 0.5) / soft, 0.0, 1.0);
    if (uPattern > 0.5) {
      // Dots on a grid, bigger the deeper the shadow: printed shading.
      float dark = clamp(1.0 - (ndl + 0.35) / 0.9, 0.0, 1.0);
      float cell = max(4.0, uLine * (uPattern > 1.5 ? 1.6 : 2.6));
      vec2 g = px;
      if (uPattern > 1.5) g = vec2(g.x + g.y, g.y - g.x) * 0.7071;
      vec2 c = mod(g, cell) - cell * 0.5;
      float r = cell * 0.62 * sqrt(dark);
      float dot = 1.0 - smoothstep(r - 0.8, r + 0.8, length(c));
      colour = mix(base, base * shade * 0.85, dot);
    } else {
      colour = mix(base * shade, base, lit);
    }
  } else {
    float k = 0.45 + 0.55 * max(ndl, 0.0) + 0.08 * max(n.z, 0.0);
    colour = base * min(k, 1.1);
  }
  colour += uRim.rgb * uRim.a * pow(1.0 - clamp(abs(n.z), 0.0, 1.0), uRimPower);

  // Lines inside: where one part stands in front of another, or the
  // surface turns sharply, or the colour changes, as at a cuff. Depth is
  // compared across the pixel, both ways at once: a surface sloping away
  // changes depth steadily, which is no edge; one part in front of another
  // changes it on one side only.
  float edge = 0.0;
  if (uInner > 0.0) {
    float d0 = depthAt(uv);
    float r = max(1.0, uLine * 0.5);
    for (int k = 0; k < 4; k++) {
      float a = float(k) * 0.7853982;
      vec2 o = vec2(cos(a), sin(a)) * r;
      vec2 q1 = (px + o) / uSize;
      vec2 q2 = (px - o) / uSize;
      vec4 c1 = texture(uAlbedo, q1);
      vec4 c2 = texture(uAlbedo, q2);
      if (c1.a < 0.5 || c2.a < 0.5) continue;
      float bend = abs(depthAt(q1) + depthAt(q2) - 2.0 * d0);
      edge = max(edge, smoothstep(0.025, 0.06, bend));
      float nd = max(1.0 - dot(normalAt(q1), n), 1.0 - dot(normalAt(q2), n));
      edge = max(edge, smoothstep(0.6, 0.95, nd) * 0.8);
      float cd = max(length(c1.rgb / c1.a - base), length(c2.rgb / c2.a - base));
      edge = max(edge, smoothstep(0.25, 0.45, cd) * 0.6);
    }
    edge *= uInner;
  }
  colour = mix(colour, uInk.rgb, edge * uInk.a);
  fragColor = vec4(clamp(colour, 0.0, 1.0) * albedo.a, albedo.a);
}
