#version 460 core

// character_paint.frag lights a drawn character as a painter does: each
// shape of it -- a leg, a lock of hair, a sleeve -- rounded from its own
// outline, so light falls softly across it and shadow comes in from its
// edges; shadows tinted as skin, hair and cloth take them; light caught
// round the rim; a sheen across hair; a soft shadow where one part lies
// over another; and a line round it all, fine where the light falls and
// heavier in shadow.
//
// Read from three pictures of the same size, uSize, made by the sketch as
// it is drawn: its colours, how high each shape is raised from its edge,
// and what each pixel is made of and in what order it was laid down. See
// painted_light.dart, which makes them.

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
// Where the light comes from: x right, y up, z towards the reader.
uniform vec3 uLight;
// How soft the edge between light and shadow is: 0 a hard cel edge, 1 a
// gradual turn.
uniform float uSoft;
// How far round the shadow falls.
uniform float uShift;
// How rounded the shapes are.
uniform float uRound;
// The rim light's strength, and the hair's sheen.
uniform float uRim;
uniform float uSheen;
// The line's width in pixels, and its colour.
uniform float uLine;
uniform vec4 uInk;
// The colour each material's shadow is, as a share of its own colour.
uniform vec3 uSkinShade;
uniform vec3 uHairShade;
uniform vec3 uClothShade;
// How dark a part's shadow on what is behind it is, and how far it falls.
uniform float uContact;
uniform float uContactReach;

uniform sampler2D uAlbedo;
uniform sampler2D uHeight;
uniform sampler2D uPart;

out vec4 fragColor;

float heightAt(vec2 px) {
  return texture(uHeight, px / uSize).r;
}

// The order a part was laid down in: later is in front.
float orderAt(vec2 px) {
  vec4 p = texture(uPart, px / uSize);
  return p.g * 255.0 + p.b * 255.0 * 256.0;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  vec2 uv = px / uSize;
  vec4 albedo = texture(uAlbedo, uv);

  // Outside: the line round the outside, and nothing further off.
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
  vec4 part = texture(uPart, uv);
  float material = floor(part.r * 255.0 + 0.5);
  float order = orderAt(px);

  // Which way the surface faces, from how its height rises from the edge.
  float d = 1.5;
  float hx = heightAt(px + vec2(d, 0.0)) - heightAt(px - vec2(d, 0.0));
  float hy = heightAt(px + vec2(0.0, d)) - heightAt(px - vec2(0.0, d));
  // y on the page runs down; the light's runs up.
  vec3 n = normalize(vec3(-hx * uRound, hy * uRound, 1.0));

  vec3 l = normalize(uLight);
  float ndl = dot(n, l);
  // Wrapped round, so the turn into shadow is gentle; then as soft as the
  // style says.
  float wrapped = (ndl + 0.5) / 1.5;
  float edge = 0.5 - uShift;
  float lit = smoothstep(edge - 0.02 - uSoft * 0.25, edge + 0.02 + uSoft * 0.25, wrapped);

  vec3 shade = material < 1.5 ? uSkinShade : (material < 2.5 ? uHairShade : uClothShade);
  // Features drawn flat -- eyes, mouths, prints -- are lit a little only.
  if (material > 3.5) shade = mix(vec3(1.0), shade, 0.35);
  vec3 colour = base * mix(shade, vec3(1.0), lit);
  // A painted gradient through the lit side too, not one flat colour.
  colour *= 0.94 + 0.1 * clamp(ndl, 0.0, 1.0);

  // Light caught round the edge away from the light.
  float rim = pow(1.0 - clamp(n.z, 0.0, 1.0), 2.5) *
      smoothstep(-0.1, 0.5, -dot(normalize(n.xy + 1e-4), normalize(l.xy)));
  colour += vec3(1.0, 0.97, 0.92) * rim * uRim * (material > 3.5 ? 0.0 : 1.0);

  // Hair: a band of sheen across where it turns towards the light.
  if (material > 1.5 && material < 2.5) {
    float band = exp(-pow((ndl - 0.55) / 0.12, 2.0));
    colour += vec3(1.0, 0.95, 0.85) * band * uSheen * lit;
  }

  // A soft shadow where a part in front lies between this and the light.
  float occluded = 0.0;
  vec2 toLight = normalize(vec2(l.x, -l.y));
  for (int k = 1; k <= 8; k++) {
    float r = float(k) * uContactReach / 8.0;
    vec2 q = px + toLight * r;
    if (texture(uAlbedo, q / uSize).a < 0.5) continue;
    if (orderAt(q) > order + 0.5) {
      occluded = max(occluded, 1.0 - float(k - 1) / 8.0);
    }
  }
  colour = mix(colour, colour * shade * 0.9, occluded * uContact);

  // A line where one part meets another, heavier in shadow.
  float width = uLine * (0.45 + 0.75 * (1.0 - lit));
  float line = 0.0;
  if (uLine > 0.0) {
    for (int k = 0; k < 8; k++) {
      float a = float(k) * 0.7853982;
      vec2 q = px + vec2(cos(a), sin(a)) * width * 0.6;
      vec4 o = texture(uAlbedo, q / uSize);
      if (o.a < 0.5) continue;
      // Only the part behind takes the line, so it follows the edge of the
      // one in front.
      if (orderAt(q) > order + 0.5) line = 1.0;
    }
  }
  colour = mix(colour, uInk.rgb, line * uInk.a * 0.85);

  fragColor = vec4(clamp(colour, 0.0, 1.0) * albedo.a, albedo.a);
}
