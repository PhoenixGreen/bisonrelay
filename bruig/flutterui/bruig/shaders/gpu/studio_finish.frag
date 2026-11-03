// The Character Studio's finish: the character's lines found in its depth
// and normals and laid over its colour, the colour graded, the paper behind
// it, and the drawn finishes -- manga, pencil, watercolour, painterly, comic
// and ink sketch. Run after tone mapping, on the image as it is seen.

precision highp float;

uniform sampler2D input_color;
uniform sampler2D linear_depth;

uniform PostFrameInfo {
  vec2 resolution;
  vec2 texel_size;
  float time;
  float _pad;
}
frame;

uniform Finish {
  // inner lines' strength, their reach in pixels, the outline's strength,
  // and how much a pencil line wanders
  vec4 lines;
  // the outline's reach in pixels, line grain, finish (0 colour .. 6
  // sketch), and 1 to tint lines by the colour under them
  vec4 style;
  // saturation, brightness, warmth, tone bands
  vec4 grade;
  // screentone, contrast, hatching, colour wash
  vec4 finish_a;
  // bleed, pooled edges, brush size, dot size
  vec4 finish_b;
  // paper grain, and 1 for no paper: the figure alone, clear round it, to
  // lay on a canvas
  vec4 finish_c;
  vec4 line_colour;
  vec4 paper;
}
f;

in vec2 v_uv;
out vec4 frag_color;

float Hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float Noise(vec2 p) {
  vec2 i = floor(p), u = fract(p);
  u = u * u * (3.0 - 2.0 * u);
  return mix(mix(Hash(i), Hash(i + vec2(1.0, 0.0)), u.x),
             mix(Hash(i + vec2(0.0, 1.0)), Hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The view-space depth, nought where nothing was drawn.
float DepthAt(vec2 uv) { return texture(linear_depth, uv).r; }
float BackgroundAt(vec2 uv) {
  float d = DepthAt(uv);
  return (d <= 1e-5 || d > 1e5) ? 1.0 : 0.0;
}

vec3 NormalAt(vec2 uv) {
  vec2 e = texture(linear_depth, uv).gb;
  vec3 n = vec3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
  if (n.z < 0.0) {
    n.xy = (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
  }
  return normalize(n);
}

vec4 ColourAt(vec2 uv) {
  vec4 c = texture(input_color, uv);
  float bg = BackgroundAt(uv);
  float a = (1.0 - bg) * clamp(c.a, 0.0, 1.0);
  return vec4(c.a > 0.001 ? c.rgb / c.a : vec3(0.0), a);
}

float Lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 Grade(vec3 c) {
  float sat = f.grade.x, bright = f.grade.y, warmth = f.grade.z, bands = f.grade.w;
  float l = Lum(c);
  if (bands > 0.01) {
    float n = floor(6.5 - bands * 4.0);
    float q = floor(l * n + 0.5) / n;
    c *= (q + 0.03) / (l + 0.03);
  }
  l = Lum(c);
  c = mix(vec3(l), c, 1.0 + sat);
  c *= 1.0 + bright * 0.55;
  c += vec3(0.07, 0.02, -0.07) * warmth;
  return clamp(c, 0.0, 1.0);
}

// The painterly finish: each pixel takes the calmest of four corners round it.
void Corner(vec2 uv, vec2 dx, vec2 dy, float r, out vec3 mean, out float vari) {
  vec3 s = vec3(0.0), s2 = vec3(0.0);
  float n = 0.0;
  for (int j = 0; j <= 6; j++) {
    for (int i = 0; i <= 6; i++) {
      if (float(i) > r || float(j) > r) continue;
      vec3 c = ColourAt(uv + dx * float(i) + dy * float(j)).rgb;
      s += c;
      s2 += c * c;
      n += 1.0;
    }
  }
  mean = s / n;
  vec3 v = s2 / n - mean * mean;
  vari = v.r + v.g + v.b;
}

float Halftone(float v, float ang, float size) {
  vec2 g = mat2(cos(ang), -sin(ang), sin(ang), cos(ang)) * gl_FragCoord.xy / size;
  return step(length(fract(g) - 0.5), sqrt(clamp(v, 0.0, 1.0)) * 0.62);
}

void main() {
  vec2 px = frame.texel_size, uv = v_uv;
  float inner = f.lines.x, inner_px = f.lines.y, silhouette = f.lines.z, wobble = f.lines.w;
  float outline_px = f.style.x, grain = f.style.y, mode = f.style.z, tinted = f.style.w;
  float tone = f.finish_a.x, contrast = f.finish_a.y, hatch = f.finish_a.z, wash = f.finish_a.w;
  float bleed = f.finish_b.x, edge = f.finish_b.y, brush = f.finish_b.z, dots = f.finish_b.w;
  float paper_k = f.finish_c.x;
  bool clear = f.finish_c.y > 0.5;

  // Lines: where the surface folds (its normals turn sharply) or steps back
  // (its depth jumps) between this pixel and those round it, and the
  // outline where the figure meets the paper.
  vec2 w = vec2(Noise(uv * frame.resolution / 9.0), Noise(uv * frame.resolution / 9.0 + 7.3)) - 0.5;
  vec2 suv = uv + w * wobble * px * 3.0;
  vec3 n0 = NormalAt(suv);
  float z0 = DepthAt(suv), bg0 = BackgroundAt(suv);
  float line = 0.0;
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.785398;
    vec2 dir = vec2(cos(a), sin(a));
    vec2 o = dir * inner_px * px;
    float bg1 = BackgroundAt(suv + o);
    if (bg0 < 0.5 && bg1 < 0.5) {
      vec3 n1 = NormalAt(suv + o);
      float z1 = DepthAt(suv + o);
      float crease = smoothstep(0.12, 0.35, 1.0 - dot(n0, n1));
      float dz = abs(z0 - z1) / max(0.05, abs(z0));
      float steps = smoothstep(0.004, 0.014, dz);
      line = max(line, max(crease * 0.85, steps) * inner);
    } else if (bg0 != bg1) {
      line = max(line, silhouette);
    }
    // The outline, drawn on the paper round the figure.
    if (outline_px > 0.0 && bg0 > 0.5 && BackgroundAt(suv + dir * outline_px * px) < 0.5) {
      line = 1.0;
    }
  }
  if (grain > 0.0) line *= mix(1.0, 0.45 + 0.9 * Noise(uv * frame.resolution / 2.2), grain);

  vec4 cc = ColourAt(uv);
  vec3 col = Grade(cc.rgb);
  float fg = cc.a;
  float lum = Lum(col);
  float paper_n = 1.0 - paper_k * 0.12 * (Noise(gl_FragCoord.xy / 3.0) * 0.6 + Noise(gl_FragCoord.xy / 11.0) * 0.4);
  // With no paper the page is clear: every finish below mixes its colour
  // over the page by how much figure there is, so over a clear page its
  // colour comes out premultiplied by [cover], which is then its alpha.
  vec3 page = clear ? vec3(0.0) : f.paper.rgb * paper_n;
  float cover = fg;
  // What a print takes on from its paper: nothing, with no paper.
  vec3 tint = clear ? vec3(1.0) : page;

  if (mode > 0.5 && mode < 1.5) {
    // Manga: white, screentone in the mid shades, solid black in the deep.
    float size = 3.0 + tone * 5.0, hi = 0.5 + contrast * 0.25, lo = 0.08 + contrast * 0.2;
    vec2 r = mat2(0.7071, -0.7071, 0.7071, 0.7071) * gl_FragCoord.xy / size;
    float d = length(fract(r) - 0.5);
    float t = lum > hi ? 1.0 : (lum > lo ? step(0.42 * (hi - lum) / (hi - lo) + 0.08, d) : 0.0);
    col = mix(page, vec3(t) * mix(vec3(1.0), tint, 0.2), fg);
  } else if (mode > 1.5 && mode < 2.5) {
    // Pencil: a washed colour on paper, hatched in the shadows.
    vec3 wc = mix(vec3(lum), col, 0.25 + wash * 0.6);
    wc = mix(wc, vec3(1.0), 0.35 - wash * 0.2);
    float sp = 7.0 - hatch * 4.0;
    float h1 = step(0.55, fract((gl_FragCoord.x + gl_FragCoord.y) / sp)) * smoothstep(0.6, 0.3, lum);
    float h2 = step(0.55, fract((gl_FragCoord.x - gl_FragCoord.y) / sp)) * smoothstep(0.35, 0.12, lum);
    wc *= 1.0 - (h1 + h2) * 0.3 * (0.6 + 0.4 * Noise(gl_FragCoord.xy / 2.0));
    col = mix(page, wc * paper_n, fg);
  } else if (mode > 2.5 && mode < 3.5) {
    // Watercolour: the colour bled out, pooled darker at its edges, the
    // paper through it.
    vec3 acc = vec3(0.0);
    float ws = 0.0;
    for (int k = 0; k < 10; k++) {
      float a = float(k) * 0.628 + Noise(uv * frame.resolution / 25.0) * 4.0;
      vec2 o = vec2(cos(a), sin(a)) * (1.0 + bleed * 7.0) * (0.5 + Noise(uv * frame.resolution / 13.0 + float(k))) * px;
      vec4 c = ColourAt(uv + o);
      acc += Grade(c.rgb) * c.a;
      ws += c.a;
    }
    vec3 blur = ws > 0.0 ? acc / ws : col;
    float fgb = clamp(ws / 10.0, 0.0, 1.0);
    vec3 wc = mix(col, blur, 0.55);
    float pool = smoothstep(0.03, 0.22, length(col - blur)) + ((fgb > 0.05 && fgb < 0.95) ? 0.6 : 0.0);
    wc *= 1.0 - edge * 0.35 * pool;
    float gran = Noise(gl_FragCoord.xy / 2.5) * 0.5 + Noise(gl_FragCoord.xy / 8.0) * 0.5;
    wc *= 0.9 + 0.2 * gran * paper_k;
    wc = mix(wc, vec3(1.0), 0.12 + wash * 0.3);
    cover = max(fg, fgb * 0.85);
    col = mix(page, wc * paper_n, cover);
  } else if (mode > 3.5 && mode < 4.5) {
    // Painterly.
    float r = 1.0 + brush * 5.0;
    vec3 m0, m1, m2, m3;
    float v0, v1, v2, v3;
    Corner(uv, vec2(-px.x, 0.0), vec2(0.0, -px.y), r, m0, v0);
    Corner(uv, vec2(px.x, 0.0), vec2(0.0, -px.y), r, m1, v1);
    Corner(uv, vec2(-px.x, 0.0), vec2(0.0, px.y), r, m2, v2);
    Corner(uv, vec2(px.x, 0.0), vec2(0.0, px.y), r, m3, v3);
    vec3 pm = m0;
    float pv = v0;
    if (v1 < pv) { pm = m1; pv = v1; }
    if (v2 < pv) { pm = m2; pv = v2; }
    if (v3 < pv) { pm = m3; pv = v3; }
    float a = 0.0;
    for (int k = 0; k < 4; k++) {
      vec2 o = vec2(float(k) - 1.5, 0.0) * r * 0.5 * px;
      a += ColourAt(uv + o).a;
    }
    a = clamp(a / 4.0, 0.0, 1.0);
    cover = max(fg, a);
    col = mix(page, Grade(pm) * (0.94 + 0.06 * paper_n), cover);
  } else if (mode > 4.5 && mode < 5.5) {
    // Comic: bold flat colour, its shadows printed as dots of a darker
    // shade of it, the deepest dark solid black.
    float size = 3.0 + dots * 6.0;
    vec3 bold = clamp(mix(vec3(lum), col, 1.25) * 1.12, 0.0, 1.0);
    float shade = smoothstep(0.5, 0.18, lum);
    float dt = Halftone(shade * 0.85, 0.785, size);
    vec3 printed = mix(bold, bold * 0.45, dt);
    printed *= 1.0 - step(lum, 0.05 + contrast * 0.12);
    col = mix(page, printed * mix(vec3(1.0), tint, 0.35), fg);
  } else if (mode > 5.5) {
    // Ink sketch: no colour, the lines and some hatching.
    float sp = 7.0 - hatch * 4.0;
    float h1 = step(0.6, fract((gl_FragCoord.x + gl_FragCoord.y) / sp)) * smoothstep(0.55, 0.3, lum);
    float h2 = step(0.6, fract((gl_FragCoord.x - gl_FragCoord.y) / sp)) * smoothstep(0.3, 0.1, lum);
    col = mix(page, page * (1.0 - (h1 + h2) * 0.55 * (0.6 + 0.4 * Noise(gl_FragCoord.xy / 2.0))), fg);
  } else {
    col = mix(page, col, fg);
  }
  vec3 ink = tinted > 0.5 ? Grade(cc.rgb) * 0.38 : f.line_colour.rgb;
  float l = clamp(line, 0.0, 1.0);
  col = mix(col, ink, l);
  frag_color = clear ? vec4(col, cover * (1.0 - l) + l) : vec4(col, 1.0);
}
