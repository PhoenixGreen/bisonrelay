#version 460 core

// adjust.frag is every adjustment a picture's adjustment layer can make,
// done to the layers under it. One shader rather than one each: the mode
// picks the adjustment, and the three vectors carry its settings -- see
// ImageAdjustment and adjust_painter.dart, which say what each means.
//
// Curves and gradient maps go by a lookup strip, uLut: 256 pixels across,
// one row, read at the input level.

#include <flutter/runtime_effect.glsl>

uniform vec2 uOrigin;
uniform vec2 uSize;
uniform float uMode;
uniform vec4 uA;
uniform vec4 uB;
uniform vec4 uC;
uniform sampler2D uImage;
uniform sampler2D uLut;

out vec4 fragColor;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

vec3 rgb2hsl(vec3 c) {
  float mx = max(max(c.r, c.g), c.b);
  float mn = min(min(c.r, c.g), c.b);
  float l = (mx + mn) * 0.5;
  float d = mx - mn;
  if (d < 1e-5) return vec3(0.0, 0.0, l);
  float s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn);
  float h;
  if (mx == c.r) {
    h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
  } else if (mx == c.g) {
    h = (c.b - c.r) / d + 2.0;
  } else {
    h = (c.r - c.g) / d + 4.0;
  }
  return vec3(h / 6.0, s, l);
}

float hue2rgb(float p, float q, float t) {
  t = fract(t);
  if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
  if (t < 0.5) return q;
  if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
  return p;
}

vec3 hsl2rgb(vec3 hsl) {
  if (hsl.y <= 0.0) return vec3(hsl.z);
  float q = hsl.z < 0.5 ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
  float p = 2.0 * hsl.z - q;
  return vec3(hue2rgb(p, q, hsl.x + 1.0 / 3.0), hue2rgb(p, q, hsl.x),
              hue2rgb(p, q, hsl.x - 1.0 / 3.0));
}

float lut(float v, int channel) {
  vec4 c = texture(uLut, vec2(clamp(v, 0.0, 1.0) * (255.0 / 256.0) + 0.5 / 256.0, 0.5));
  return channel == 0 ? c.r : channel == 1 ? c.g : c.b;
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - uOrigin) / uSize;
  vec4 src = texture(uImage, uv);
  if (src.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  // The sampler hands back premultiplied colour; adjustments are of the
  // colour itself.
  vec3 c = src.rgb / src.a;
  int mode = int(uMode + 0.5);

  if (mode == 0) {
    // Brightness and contrast: uA.x brightness, uA.y contrast, -1 to 1.
    c = c + uA.x;
    float k = uA.y >= 0.0 ? 1.0 / max(0.01, 1.0 - uA.y) : 1.0 + uA.y;
    c = (c - 0.5) * k + 0.5;
  } else if (mode == 1) {
    // Levels: uA input black, input white, gamma; uB output black, white.
    c = clamp((c - uA.x) / max(1e-4, uA.y - uA.x), 0.0, 1.0);
    c = pow(c, vec3(1.0 / max(0.01, uA.z)));
    c = mix(vec3(uB.x), vec3(uB.y), c);
  } else if (mode == 2) {
    // Curves: each channel through its own row of the strip.
    c = vec3(lut(c.r, 0), lut(c.g, 1), lut(c.b, 2));
  } else if (mode == 3) {
    // Hue and saturation: uA.x hue turn (whole turns), uA.y saturation and
    // uA.z lightness, -1 to 1; uA.w above a half colourises.
    vec3 hsl = rgb2hsl(clamp(c, 0.0, 1.0));
    if (uA.w > 0.5) {
      hsl.x = fract(uA.x);
      hsl.y = clamp(0.5 + uA.y * 0.5, 0.0, 1.0);
    } else {
      hsl.x = fract(hsl.x + uA.x);
      hsl.y = clamp(hsl.y * (1.0 + uA.y), 0.0, 1.0);
    }
    c = hsl2rgb(hsl);
    c = uA.z >= 0.0 ? mix(c, vec3(1.0), uA.z) : c * (1.0 + uA.z);
  } else if (mode == 4) {
    // Vibrance: uA.x lifts the dull colours more than the vivid ones, and
    // skin least; uA.y saturation, all alike.
    float l = dot(c, LUMA);
    float mx = max(max(c.r, c.g), c.b);
    float mn = min(min(c.r, c.g), c.b);
    float sat = mx - mn;
    float k = 1.0 + uA.x * (1.0 - sat) * (uA.x > 0.0 ? 1.0 : 0.6);
    c = mix(vec3(l), c, k * (1.0 + uA.y));
  } else if (mode == 5) {
    // Warmth and tint, -1 to 1: towards amber or blue, and magenta or green.
    c = c * vec3(1.0 + uA.x * 0.18, 1.0 - uA.y * 0.12, 1.0 - uA.x * 0.18);
    c.r += uA.y * 0.04;
    c.b += uA.y * 0.04;
  } else if (mode == 6) {
    // Photo filter: uB.rgb the filter's colour, uA.x density, uA.y above a
    // half keeps the brightness as it was.
    float l = dot(c, LUMA);
    vec3 filtered = mix(c, c * uB.rgb * 1.6, uA.x);
    if (uA.y > 0.5) filtered *= l / max(1e-4, dot(filtered, LUMA));
    c = filtered;
  } else if (mode == 7) {
    // Keep one colour: uA.x the hue kept (whole turns), uA.y how far either
    // side of it counts, uA.z the softness of that boundary, uA.w how much
    // the rest loses its colour. Greys, which have no hue, go with the rest.
    vec3 hsl = rgb2hsl(clamp(c, 0.0, 1.0));
    float d = abs(fract(hsl.x - uA.x + 0.5) - 0.5);
    float keep = 1.0 - smoothstep(uA.y, uA.y + max(1e-3, uA.z), d);
    keep *= smoothstep(0.05, 0.25, hsl.y);
    float l = dot(c, LUMA);
    c = mix(c, vec3(l), uA.w * (1.0 - keep));
  } else if (mode == 8) {
    // Black and white: uA.rgb how much each channel gives, uB.rgb a tint
    // and uB.a its strength.
    float l = clamp(dot(c, uA.rgb), 0.0, 1.0);
    vec3 grey = vec3(l);
    vec3 tinted = l < 0.5 ? 2.0 * grey * uB.rgb
                          : 1.0 - 2.0 * (1.0 - grey) * (1.0 - uB.rgb);
    c = mix(grey, tinted, uB.a);
  } else if (mode == 9) {
    // Gradient map: brightness read as a place along the strip.
    float l = clamp(dot(c, LUMA), 0.0, 1.0);
    c = vec3(lut(l, 0), lut(l, 1), lut(l, 2));
  } else if (mode == 10) {
    // Exposure: uA.x stops, uA.y offset, uA.z gamma.
    c = c * exp2(uA.x) + uA.y;
    c = pow(max(c, 0.0), vec3(1.0 / max(0.01, uA.z)));
  } else if (mode == 11) {
    // Posterise: uA.x levels a channel.
    float n = max(2.0, uA.x);
    c = floor(clamp(c, 0.0, 0.9999) * n) / (n - 1.0);
  } else if (mode == 12) {
    // Threshold: white above uA.x, black below.
    float l = dot(c, LUMA);
    c = vec3(step(uA.x, l));
  } else if (mode == 13) {
    c = 1.0 - c;
  }
  c = clamp(c, 0.0, 1.0);
  fragColor = vec4(c * src.a, src.a);
}
