#version 460 core

// adjust.frag is every adjustment a picture's adjustment layer can make,
// done to the layers under it. One shader rather than one each: the mode
// picks the adjustment, and the three vectors carry its settings -- see
// ImageAdjustment and adjust_painter.dart, which say what each means.
//
// Curves and gradient maps go by a lookup strip, uLut: 256 pixels across,
// one row, read at the input level.

#include <flutter/runtime_effect.glsl>

// uSize first and uImage the first sampler: as an image filter -- see
// ImageFilter.shader -- the engine sets both, to the layer being drawn.
uniform vec2 uSize;
uniform vec2 uOrigin;
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

// px is how many of the picture's pixels a thousandth of its shorter side
// is: neighbouring kinds give their sizes so, and look the same at any size.
float px(float thousandths) {
  return max(1.0, thousandths * min(uSize.x, uSize.y));
}

// near is the colour at [at], premultiplied by its alpha; straight takes
// the alpha back out.
vec4 near(vec2 at) {
  return texture(uImage, clamp(at, vec2(0.0), vec2(1.0)));
}

vec3 straight(vec4 s) {
  return s.a > 0.0 ? s.rgb / s.a : vec3(0.0);
}

// around is the average colour in a circle [r] pixels across [uv]: three
// rings of eight and the middle, weighted by alpha.
vec3 around(vec2 uv, float r) {
  vec4 sum = near(uv);
  for (int ring = 1; ring <= 3; ring++) {
    float reach = r * float(ring) / 3.0;
    for (int i = 0; i < 8; i++) {
      // Each ring turned a little from the last, so the taps spread.
      float a = (float(i) + float(ring) * 0.33) * 0.7853982;
      sum += near(uv + vec2(cos(a), sin(a)) * reach / uSize);
    }
  }
  return sum.a > 0.0 ? sum.rgb / sum.a : vec3(0.0);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// table reads the colour table in uLut (n² by n: red along each of n
// blocks, blue block by block, green down) at [c], between its points.
vec3 tableTexel(float r, float g, float b, float n) {
  return texture(uLut, vec2((r + b * n + 0.5) / (n * n), (g + 0.5) / n)).rgb;
}

vec3 tableSlice(vec2 rg, float b, float n) {
  vec2 f = floor(rg);
  vec2 t = rg - f;
  vec2 f1 = min(f + 1.0, vec2(n - 1.0));
  vec3 low = mix(tableTexel(f.x, f.y, b, n), tableTexel(f1.x, f.y, b, n), t.x);
  vec3 high = mix(tableTexel(f.x, f1.y, b, n), tableTexel(f1.x, f1.y, b, n), t.x);
  return mix(low, high, t.y);
}

vec3 table(vec3 c, float n) {
  vec3 p = clamp(c, 0.0, 1.0) * (n - 1.0);
  float b0 = floor(p.z);
  float b1 = min(b0 + 1.0, n - 1.0);
  return mix(tableSlice(p.xy, b0, n), tableSlice(p.xy, b1, n), p.z - b0);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - uOrigin) / uSize;
  int mode = int(uMode + 0.5);
  // Each kind its own if, not a chain of else-ifs: SkSL nests a chain,
  // and too deep a chain will not compile.
  // Kinds that move the picture read it from somewhere else.
  if (mode == 22) {
    // Pixelate: each cell the colour at its middle.
    float cell = px(uA.x);
    uv = (floor(uv * uSize / cell) + 0.5) * cell / uSize;
  }
  if (mode == 26) {
    // Ripple: pushed across the waves, uA.x pixels at most, waves uA.y
    // apart, running at angle uA.z.
    vec2 along = vec2(cos(uA.z), sin(uA.z));
    vec2 across = vec2(-along.y, along.x);
    float wave = sin(dot(uv * uSize, along) / px(uA.y) * 6.2831853);
    uv += across * wave * px(uA.x) / uSize;
  }
  vec4 src = texture(uImage, uv);
  if (src.a <= 0.0) {
    fragColor = vec4(0.0);
    return;
  }
  // The sampler hands back premultiplied colour; adjustments are of the
  // colour itself.
  vec3 c = src.rgb / src.a;

  if (mode == 0) {
    // Brightness and contrast: uA.x brightness, uA.y contrast, -1 to 1.
    c = c + uA.x;
    float k = uA.y >= 0.0 ? 1.0 / max(0.01, 1.0 - uA.y) : 1.0 + uA.y;
    c = (c - 0.5) * k + 0.5;
  }
  if (mode == 1) {
    // Levels: uA input black, input white, gamma; uB output black, white.
    c = clamp((c - uA.x) / max(1e-4, uA.y - uA.x), 0.0, 1.0);
    c = pow(c, vec3(1.0 / max(0.01, uA.z)));
    c = mix(vec3(uB.x), vec3(uB.y), c);
  }
  if (mode == 2) {
    // Curves: each channel through its own row of the strip.
    c = vec3(lut(c.r, 0), lut(c.g, 1), lut(c.b, 2));
  }
  if (mode == 3) {
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
  }
  if (mode == 4) {
    // Vibrance: uA.x lifts the dull colours more than the vivid ones, and
    // skin least; uA.y saturation, all alike.
    float l = dot(c, LUMA);
    float mx = max(max(c.r, c.g), c.b);
    float mn = min(min(c.r, c.g), c.b);
    float sat = mx - mn;
    float k = 1.0 + uA.x * (1.0 - sat) * (uA.x > 0.0 ? 1.0 : 0.6);
    c = mix(vec3(l), c, k * (1.0 + uA.y));
  }
  if (mode == 5) {
    // Warmth and tint, -1 to 1: towards amber or blue, and magenta or green.
    c = c * vec3(1.0 + uA.x * 0.18, 1.0 - uA.y * 0.12, 1.0 - uA.x * 0.18);
    c.r += uA.y * 0.04;
    c.b += uA.y * 0.04;
  }
  if (mode == 6) {
    // Photo filter: uB.rgb the filter's colour, uA.x density, uA.y above a
    // half keeps the brightness as it was.
    float l = dot(c, LUMA);
    vec3 filtered = mix(c, c * uB.rgb * 1.6, uA.x);
    if (uA.y > 0.5) filtered *= l / max(1e-4, dot(filtered, LUMA));
    c = filtered;
  }
  if (mode == 7) {
    // Keep one colour: uA.x the hue kept (whole turns), uA.y how far either
    // side of it counts, uA.z the softness of that boundary, uA.w how much
    // the rest loses its colour. Greys, which have no hue, go with the rest.
    vec3 hsl = rgb2hsl(clamp(c, 0.0, 1.0));
    float d = abs(fract(hsl.x - uA.x + 0.5) - 0.5);
    float keep = 1.0 - smoothstep(uA.y, uA.y + max(1e-3, uA.z), d);
    keep *= smoothstep(0.05, 0.25, hsl.y);
    float l = dot(c, LUMA);
    c = mix(c, vec3(l), uA.w * (1.0 - keep));
  }
  if (mode == 8) {
    // Black and white: uA.rgb how much each channel gives, uB.rgb a tint
    // and uB.a its strength.
    float l = clamp(dot(c, uA.rgb), 0.0, 1.0);
    vec3 grey = vec3(l);
    vec3 tinted = l < 0.5 ? 2.0 * grey * uB.rgb
                          : 1.0 - 2.0 * (1.0 - grey) * (1.0 - uB.rgb);
    c = mix(grey, tinted, uB.a);
  }
  if (mode == 9) {
    // Gradient map: brightness read as a place along the strip.
    float l = clamp(dot(c, LUMA), 0.0, 1.0);
    c = vec3(lut(l, 0), lut(l, 1), lut(l, 2));
  }
  if (mode == 10) {
    // Exposure: uA.x stops, uA.y offset, uA.z gamma.
    c = c * exp2(uA.x) + uA.y;
    c = pow(max(c, 0.0), vec3(1.0 / max(0.01, uA.z)));
  }
  if (mode == 11) {
    // Posterise: uA.x levels a channel.
    float n = max(2.0, uA.x);
    c = floor(clamp(c, 0.0, 0.9999) * n) / (n - 1.0);
  }
  if (mode == 12) {
    // Threshold: white above uA.x, black below.
    float l = dot(c, LUMA);
    c = vec3(step(uA.x, l));
  }
  if (mode == 13) {
    c = 1.0 - c;
  }
  if (mode == 14) {
    // Channel mixer: each channel out made from the three in, uA red's,
    // uB green's, uC blue's.
    c = vec3(dot(c, uA.rgb), dot(c, uB.rgb), dot(c, uC.rgb));
  }
  if (mode == 15) {
    // Colour balance: uA shadows', uB midtones', uC highlights' push
    // towards red, green, blue (or away, to cyan, magenta, yellow); uA.w
    // above a half keeps the brightness as it was.
    float l = dot(c, LUMA);
    float sh = 1.0 - smoothstep(0.0, 0.5, l);
    float hi = smoothstep(0.5, 1.0, l);
    float mid = 1.0 - sh - hi;
    vec3 moved = c + (uA.rgb * sh + uB.rgb * mid + uC.rgb * hi) * 0.25;
    if (uA.w > 0.5) moved += l - dot(moved, LUMA);
    c = moved;
  }
  if (mode == 16) {
    // Colour mixer: the strip, read at the hue, says how far to turn it,
    // how much to saturate it and how far to lighten it -- by as much as
    // the colour has colour, so greys are left alone.
    vec3 hsl = rgb2hsl(clamp(c, 0.0, 1.0));
    vec3 m = texture(uLut, vec2(hsl.x * (255.0 / 256.0) + 0.5 / 256.0, 0.5)).rgb;
    float w = smoothstep(0.03, 0.25, hsl.y);
    hsl.x = fract(hsl.x + (m.r - 0.5) * (120.0 / 360.0) * w);
    hsl.y = clamp(hsl.y * mix(1.0, m.g * 2.0, w), 0.0, 1.0);
    c = hsl2rgb(hsl);
    float lift = (m.b - 0.5) * 2.0 * w;
    c = lift >= 0.0 ? mix(c, vec3(1.0), lift * 0.5) : c * (1.0 + lift * 0.5);
  }
  if (mode == 17) {
    // Shadows and highlights: where the surroundings (over uA.z) are dark,
    // the darks open up (uA.x); where they are bright, the brights come
    // down (uA.y) -- as a curve, so black and white stay put and a face in
    // shadow brightens while the sky beside it does not.
    float local = dot(around(uv, px(uA.z)), LUMA);
    float open = uA.x * (1.0 - smoothstep(0.05, 0.6, local));
    float hold = uA.y * smoothstep(0.4, 0.95, local);
    c = pow(clamp(c, 0.0, 1.0), vec3(1.0 / (1.0 + open * 1.4)));
    c = 1.0 - pow(1.0 - clamp(c, 0.0, 1.0), vec3(1.0 / (1.0 + hold * 1.4)));
  }
  if (mode == 18) {
    // Clarity: the difference from the surroundings (over uA.z) pushed by
    // uA.x, most in the midtones. Clearing haze (uA.y) takes a veil off,
    // or puts one on.
    float l = dot(c, LUMA);
    float local = dot(around(uv, px(uA.z)), LUMA);
    c += (l - local) * uA.x * 1.6 * (4.0 * l * (1.0 - l));
    if (uA.y > 0.0) {
      float veil = 0.15 * uA.y;
      c = (c - veil) / (1.0 - veil);
      float g = dot(c, LUMA);
      c = mix(vec3(g), c, 1.0 + 0.35 * uA.y);
    } else {
      c = mix(c, vec3(0.78), -uA.y * 0.45);
    }
  }
  if (mode == 19) {
    // Sharpen: pushed away from its surroundings by uA.x, judged over uA.y.
    float r = px(uA.y);
    vec3 soft = vec3(0.0);
    for (int i = 0; i < 8; i++) {
      float a = float(i) * 0.7853982;
      soft += straight(near(uv + vec2(cos(a), sin(a)) * r / uSize));
    }
    c += (c - soft / 8.0) * uA.x;
  }
  if (mode == 20) {
    // High pass: only the detail, on grey -- laid over in Overlay, it
    // sharpens; uA.x its reach, uA.y its strength.
    c = vec3(0.5) + (c - around(uv, px(uA.x))) * uA.y;
  }
  if (mode == 21) {
    // Noise: uA.x of it, uA.y how coloured, in grains uA.z across.
    vec2 cell = floor(uv * uSize / px(uA.z));
    float grey = hash(cell) + hash(cell + 17.31) - 1.0;
    vec3 coloured = vec3(hash(cell + 3.7), hash(cell + 9.1), hash(cell + 5.3)) * 2.0 - 1.0;
    c += mix(vec3(grey), coloured, uA.y) * uA.x;
  }
  if (mode == 23) {
    // Find edges: where the colour changes fast, a line -- dark on white --
    // uA.x strong, uA.y wide; uA.z keeps the lines' own colour.
    vec2 d = vec2(px(uA.y)) / uSize;
    vec3 tl = straight(near(uv + vec2(-d.x, -d.y)));
    vec3 t = straight(near(uv + vec2(0.0, -d.y)));
    vec3 tr = straight(near(uv + vec2(d.x, -d.y)));
    vec3 l = straight(near(uv + vec2(-d.x, 0.0)));
    vec3 r = straight(near(uv + vec2(d.x, 0.0)));
    vec3 bl = straight(near(uv + vec2(-d.x, d.y)));
    vec3 b = straight(near(uv + vec2(0.0, d.y)));
    vec3 br = straight(near(uv + vec2(d.x, d.y)));
    vec3 gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    vec3 gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    vec3 edge = clamp(sqrt(gx * gx + gy * gy) * uA.x * 0.5, 0.0, 1.0);
    c = mix(vec3(1.0 - dot(edge, LUMA)), 1.0 - edge, uA.z);
  }
  if (mode == 24) {
    // Emboss: lit from angle uA.x, raised uA.y, uA.z deep, uA.w keeping
    // the picture's colour.
    vec2 d = vec2(cos(uA.x), sin(uA.x)) * px(uA.y) / uSize;
    float rise = dot(straight(near(uv - d)) - straight(near(uv + d)), LUMA);
    vec3 grey = vec3(0.5 + rise * uA.z * 2.0);
    c = mix(grey, c + rise * uA.z, uA.w);
  }
  if (mode == 25) {
    // Oil paint (Kuwahara): of the four squares round each pixel, the
    // calmest one's average -- flat strokes, kept edges. uA.x the brush.
    float r = px(uA.x);
    vec3 best = c;
    float calmest = 1e9;
    for (int q = 0; q < 4; q++) {
      vec2 dir = vec2(q == 0 || q == 3 ? -1.0 : 1.0, q < 2 ? -1.0 : 1.0);
      vec3 sum = vec3(0.0);
      vec3 sq = vec3(0.0);
      for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
          vec2 o = vec2(float(x), float(y)) * (r / 3.0) * dir;
          vec3 s = straight(near(uv + o / uSize));
          sum += s;
          sq += s * s;
        }
      }
      vec3 mean = sum / 16.0;
      vec3 v = sq / 16.0 - mean * mean;
      float spread = v.r + v.g + v.b;
      if (spread < calmest) {
        calmest = spread;
        best = mean;
      }
    }
    c = best;
  }
  if (mode == 27) {
    // Colour table: every colour as the table has it, uA.x of the way;
    // the table is uA.y points a side.
    c = mix(c, table(c, uA.y), uA.x);
  }
  c = clamp(c, 0.0, 1.0);
  fragColor = vec4(c * src.a, src.a);
}
